extends SceneTree
## Fuel balance simulation (a tuning tool, not part of CI):
##   godot --headless --path . --script res://tests/fuel_balance_sim.gd
## Plays the real game loop with three simple autopilots and reports how long each survives:
##   SAFE    only flies the widest gap (never goes for risky cans)  -> should run dry in ~30-45 s
##   CHASER  steers for fuel cans whenever the gap is open          -> should sustain
##   RANDOM  any open gap, ignoring cans
## Obstacle crashes end a run too; the reason is printed.

const DT := 1.0 / 30.0
const MAX_SECONDS := 240.0
const RUNS := 12
const ONLY := ""

func open_columns(row) -> Array[int]:
	var cols: Array[int] = []
	var n: int = Tuning_n()
	for c in n:
		var cx: float = column_center(c)
		var blocked := false
		for x in row.xs:
			if absf(x - cx) < 0.01:
				blocked = true
		if not blocked:
			cols.append(c)
	return cols

func Tuning_get(name: String) -> float:
	return root.get_node("Tuning").get(name)

func Tuning_n() -> int:
	return root.get_node("Tuning").column_count

func column_center(c: int) -> float:
	return root.get_node("Tuning").column_center(c)

var _random_choice := {}   # row instance id -> column picked once for it

func pick_column(kind: String, row, cur_x: float, reach: float) -> int:
	var cols := open_columns(row)
	if cols.is_empty():
		return -1
	var n := Tuning_n()
	var best := cols[0]
	var best_score := -INF
	for c in cols:
		var opens := 0
		for d in [-1, 1]:
			if c + d >= 0 and c + d < n and cols.has(c + d):
				opens += 1
		var score := 0.0
		match kind:
			"SAFE":
				score = 10.0 * opens - absf(column_center(c) - cur_x) * 0.1
			"CHASER":
				var can: bool = row.has_can and absf(row.can_x - column_center(c)) < 0.01
				var reachable := absf(column_center(c) - cur_x) <= reach   # can we get there in time?
				score = (30.0 if (can and reachable) else 0.0) + 2.0 * opens - absf(column_center(c) - cur_x) * 0.1
			_:
				if not _random_choice.has(row.get_instance_id()):
					_random_choice[row.get_instance_id()] = cols.pick_random()
				score = 1.0 if c == _random_choice[row.get_instance_id()] else 0.0
		if score > best_score:
			best_score = score
			best = c
	return best

func simulate(kind: String, seed_value: int) -> Dictionary:
	seed(seed_value)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.player.set_process(false)   # we move the plane ourselves
	main.restart()
	_random_choice.clear()
	var t := 0.0
	var fuel_min := 1000.0   # lowest fuel after the first 20 s (how close the run came to empty)
	var pickups := 0
	var close_calls := 0
	var calls_counter: float = root.get_node("Save").stat("close_calls")
	var last_fuel: float = main.fuel
	var target_x := 0.0
	while main.alive and t < MAX_SECONDS:
		var pl: Node = main.player
		# steer toward the next row we have not yet passed
		for r in main.spawner._rows:
			if not r.passed:
				var dz: float = r.position.z - pl.position.z
				var spd: float = minf(Tuning_get("base_speed") + Tuning_get("speed_ramp") * main.elapsed, Tuning_get("max_speed"))
				# sideways travel must finish before the row's leading edge reaches the plane (~2.2 units early)
				var reach: float = 16.0 * maxf(-dz - 2.2, 0.0) / spd * 0.9
				var c := pick_column(kind, r, pl.position.x, reach)
				if dz > -2.2:   # the row has arrived: never cross its blocked columns, stay in the open one we're in
					var cols := open_columns(r)
					var nearest := -1
					for k in cols:
						if nearest < 0 or absf(column_center(k) - pl.position.x) < absf(column_center(nearest) - pl.position.x):
							nearest = k
					c = nearest
				if c >= 0:
					target_x = column_center(c)
				break
		var step := clampf(target_x - pl.position.x, -16.0 * DT, 16.0 * DT)
		pl.position.x += step
		if OS.get_environment("SIM_TRACE") == str(seed_value) and t > 4.0:
			var rr = null
			for r in main.spawner._rows:
				if not r.passed:
					rr = r
					break
			print("    t=%.2f x=%.2f target=%.2f | next row dz=%.1f blocked=%s can=%s@%.0f" % [t, pl.position.x, target_x, (rr.position.z - pl.position.z) if rr else 99.0, str(rr.xs) if rr else "-", str(rr.has_can) if rr else "-", rr.can_x if rr else 0.0])
		main._process(DT)
		t += DT
		if main.fuel > last_fuel + 5.0:
			pickups += 1
		last_fuel = main.fuel
		if t > 20.0:
			fuel_min = minf(fuel_min, main.fuel)
	if not main.alive and OS.get_environment("SIM_DEBUG") != "":
		var pl2: Node = main.player
		var near := []
		for r in main.spawner._rows:
			if absf(r.position.z - pl2.position.z) < 6.0:
				near.append("row z=%.1f blocked=%s can=%s@%.0f passed=%s" % [r.position.z - pl2.position.z, str(r.xs), str(r.has_can), r.can_x, str(r.passed)])
		print("  [%s seed %d] died t=%.1fs plane x=%.2f target x=%.2f | %s" % [kind, seed_value, t, pl2.position.x, target_x, " || ".join(near)])
	close_calls = int(root.get_node("Save").stat("close_calls") - calls_counter)
	var dist: float = main.score
	var reason: String = "survived" if main.alive else main.hud._over.text.split("\n")[1]
	main.queue_free()
	await process_frame
	return {"t": t, "pickups": pickups, "close_calls": close_calls, "score": dist, "reason": reason, "fuel_min": fuel_min if fuel_min < 999.0 else -1.0}

func _initialize() -> void:
	DebugFlags.parse(["noprewarm"])
	var tuning := root.get_node("Tuning")
	for kv in OS.get_environment("SIM_TUNE").split(",", false):   # e.g. SIM_TUNE="fuel_drain=2.6,fuel_can_chance=0.5"
		var parts := kv.split("=")
		tuning.set(parts[0], float(parts[1]))
	print("drain %.1f/s, refill %.0f, start %.0f, can chance %.2f, risk bias %.2f  (no cans at all: %.0f s)" % [
			tuning.fuel_drain, tuning.fuel_refill, tuning.fuel_start, tuning.fuel_can_chance, tuning.fuel_risk_bias,
			tuning.fuel_start / tuning.fuel_drain])
	for kind in (["CHASER"] if OS.get_environment("SIM_DEBUG") != "" else ["SAFE", "CHASER", "RANDOM"]):
		var times: Array[float] = []
		var picks := 0
		var calls := 0
		var coins_sum := 0.0
		var low := 0.0
		var low_n := 0
		var reasons := {}
		for i in RUNS:
			var r: Dictionary = await simulate(kind, 1000 + i)
			times.append(r["t"])
			picks += r["pickups"]
			calls += r["close_calls"]
			coins_sum += r["score"]
			if r["fuel_min"] >= 0.0:
				low += r["fuel_min"]
				low_n += 1
			reasons[r["reason"]] = reasons.get(r["reason"], 0) + 1
		times.sort()
		print("%-6s survival s: min %.0f  median %.0f  max %.0f | cans/run %.1f | close calls/run %.1f | coins/run %.0f | lowest fuel after 20 s (avg) %s | ended by %s" % [
				kind, times[0], times[times.size() / 2], times[-1], float(picks) / RUNS, float(calls) / RUNS, coins_sum / RUNS,
				("%.0f" % (low / low_n)) if low_n > 0 else "-", str(reasons)])
	quit()
