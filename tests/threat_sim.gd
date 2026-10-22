extends SceneTree
## Threat balance simulation (a tuning tool, not part of CI):
##   godot --headless --path . --script res://tests/threat_sim.gd
## Plays the real game loop (30 fps) with a REACTING autopilot: it flies the obstacle rows like the CHASER of
## fuel_balance_sim, and dodges telegraphed threats after a human-ish delay with a capped speed. Two builds:
##   NOPERK   no picks at all (the base game), boss rewards ignored
##   BUILD    takes the real picks (guns first, then the best of what is offered), boss rare picks included
## Reports survival time, shots / kills, hits taken and what ended the runs; SIM_TRACE=1 prints the first run's
## timeline of picks and events. Env: SIM_RUNS, SIM_MAX (seconds), SIM_ONLY (NOPERK|BUILD), SIM_TUNE="key=val,...".

const DT := 1.0 / 30.0
var max_seconds := 420.0
var runs := 6
const REACT := 0.22            # seconds before a new danger changes the pilot's mind
const SPEED := 15.0            # the pilot's top sideways / forward speed (the finger can do ~16)
const Z_OFFS := [0.0, -2.5, 2.0, -4.5]

func tn() -> Node:
	return root.get_node("Tuning")

func open_columns(row) -> Array[int]:
	var cols: Array[int] = []
	for c in tn().column_count:
		var cx: float = tn().column_center(c)
		var blocked := false
		for x in row.xs:
			if absf(x - cx) < 0.01:
				blocked = true
		if not blocked:
			cols.append(c)
	return cols

## The column the pilot wants for the next unpassed row (open, next to other open ones, a fuel can if reachable).
func row_target(row, cur_x: float, reach: float) -> float:
	var cols := open_columns(row)
	if cols.is_empty():
		return cur_x
	var n: int = tn().column_count
	var best: int = cols[0]
	var best_s := -INF
	for c in cols:
		var opens := 0
		for d in [-1, 1]:
			if c + d >= 0 and c + d < n and cols.has(c + d):
				opens += 1
		var cx: float = tn().column_center(c)
		var can: bool = row.has_can and absf(row.can_x - cx) < 0.01
		var s := (30.0 if (can and absf(cx - cur_x) <= reach) else 0.0) + 2.0 * opens - absf(cx - cur_x) * 0.1
		if s > best_s:
			best_s = s
			best = c
	return tn().column_center(best)

var _zones: Array = []
var _seen := {}          # zone key -> sim time first seen (the reaction delay)
var _cands: Array[Vector2] = []

## The cost of standing at (cx, cz) with respect to the threats alone (0 = nothing to fear).
func threat_cost(main: Node, t: float, cx: float, cz: float, cur: Vector2 = Vector2(INF, INF)) -> float:
	var th = main.spawner.threats
	var c := 0.0
	for z in _zones:
		var key := str(z["kind"]) + ":" + str(snappedf(z["rect"].position.x, 0.5))
		if not _seen.has(key):
			_seen[key] = t
		var r: Rect2 = (z["rect"] as Rect2).grow_individual(1.0, 0.9, 1.0, 0.9)
		if r.has_point(Vector2(cx, cz)) and float(z["at"]) <= 0.95 and t - float(_seen[key]) >= REACT:
			c += 1000.0
	if cur.x < 1.0e9:
		if th.crow_danger_path(cur, Vector2(cx, cz), SPEED) < 3.2:
			c += 900.0
	elif th.crow_danger(cx, cz) <= 3.2:
		c += 900.0
	for b in main.spawner.hazards.bolts_in_play():
		if b.state == 2 or (b.state == 1 and tn().lightning_warn - b.t <= 0.95):
			if absf(cx - tn().column_center(b.col)) < tn().column_width() * 0.5 + 1.2:
				c += 1000.0
	return c

## Flying from `cur` toward `cand` at the pilot's top speed (and then holding there), as the world arrives at `spd`:
## is the whole second clear of obstacles? (A margin either side covers wiggling kites and weaving crows.)
func path_clear(main: Node, caps: PackedFloat32Array, spd: float, cur: Vector2, cand: Vector2) -> bool:
	var dir := cand - cur
	for k in range(0, 11):
		var tau := 0.1 * k
		var q := cur + dir.limit_length(SPEED * tau)
		for dx in [0.0, -0.55, 0.55]:
			if main.spawner.probe(Vector2(q.x + dx, q.y - spd * tau), caps):
				return false
	return true

## Where to fly: the best spot among a grid around the screen: reachable without touching an obstacle, clear of every
## threat about to be armed, near the fuel can / the usual line.
func plan(main: Node, t: float, target_x: float, base_z: float) -> Vector2:
	var pl: Node = main.player
	var th = main.spawner.threats
	th.zones(1.3, _zones)
	var cur := Vector2(pl.position.x, pl.position.z)
	var caps: PackedFloat32Array = pl.hit_capsules()
	var spd: float = main.spawner.scroll_speed
	var best := Vector2(target_x, base_z)
	var best_c := INF
	for xi in 15:
		var cx: float = -5.1 + xi * 0.73
		for zo in Z_OFFS:
			var cz: float = clampf(base_z + float(zo), pl.z_min, pl.z_max)
			var cand := Vector2(cx, cz)
			var c := threat_cost(main, t, cx, cz, cur)
			if not path_clear(main, caps, spd, cur, cand):
				c += 1000.0 if main.spawner.obstacles_solid else 250.0   # (obstacles that cannot hurt are only a nuisance)
			c += absf(cx - target_x) * 2.0 + absf(cz - base_z) * 0.8 + cur.distance_to(cand) * 0.3
			if c < best_c:
				best_c = c
				best = cand
	return best

const PRIORITY := {
	"GUNS": ["flak", "pods", "tail"],
	"UTILITY": ["wingman", "shockwave", "magnet_field", "skywriter", "banner", "roll"],
	"MIXED": ["flak", "wingman", "shockwave", "magnet_field", "pods", "skywriter", "roll", "banner", "tail"],
}

func choose_card(main: Node, kind: String) -> int:
	var order: Array = PRIORITY.get(kind, PRIORITY["MIXED"])
	var best := 0
	var best_s := -1.0
	for i in main._pick_cards.size():
		var c: Dictionary = main._pick_cards[i]
		var s := 10.0
		var id: String = c["id"]
		if c["kind"] == "perk":
			var pos := order.find(id)
			if pos >= 0:
				s = 100.0 - 6.0 * pos + (12.0 if c["owned"] else 0.0)   # the build's own perks first, level-ups favoured
			elif id in ["fuel_miser", "scavenger", "hot_streak", "lucky_whiskers"]:
				s = 50.0
			else:
				s = 30.0
		elif c["kind"] == "supply" and (id == "full_tank" or id == "patch") and main.fuel < tn().fuel_max() * 0.55:
			s = 85.0
		elif c["kind"] == "boost":
			s = 25.0
		if s > best_s:
			best_s = s
			best = i
	return best

## Is a telegraphed threat about to arm over the plane's spot? (The pilot rolls then.)
func imminent(main: Node) -> bool:
	var th = main.spawner.threats
	th.zones(0.5, _zones)
	var pp := Vector2(main.player.position.x, main.player.position.z)
	for z in _zones:
		if (z["rect"] as Rect2).grow_individual(0.9, 0.8, 0.9, 0.8).has_point(pp) and float(z["at"]) <= 0.3:
			return true
	if th.crow_danger(pp.x, pp.y) <= 0.45:
		return true
	for b in main.spawner.hazards.bolts_in_play():
		if (b.state == 2 or (b.state == 1 and tn().lightning_warn - b.t <= 0.3)) and absf(pp.x - tn().column_center(b.col)) < tn().column_width() * 0.5 + 1.2:
			return true
	return false

func simulate(kind: String, seed_value: int, trace: bool) -> Dictionary:
	seed(seed_value)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.player.set_process(false)
	main.restart()
	tn().boss_rare_pick = kind != "NOPERK"
	root.get_node("Save").unlock_all_milestones()
	if kind == "NOPERK":
		main.picks.enabled = false
		main.picks.next_pick = INF
	_seen.clear()
	main.spawner.obstacles_solid = OS.get_environment("SIM_SOLID") != ""   # default: a perfect obstacle pilot, so the threats are what is measured
	var th = main.spawner.threats
	var t := 0.0
	var target_x := 0.0
	var pick_log: Array = []
	var next_plan := 0.0
	main._update_plane_zone()   # (sets the plane's range and its starting height)
	var base_z: float = main.player.position.z
	var goal := Vector2(main.player.position.x, main.player.position.z)
	var boss_env := OS.get_environment("SIM_BOSS")
	var boss_done := false
	var force := OS.get_environment("SIM_FORCE")
	if boss_env != "":
		force = ""
		th._script.clear()
		th._script_i = 0
		tn().threat_rate_start = 0.0
		tn().threat_rate_end = 0.0
		th._next_boss_m = 1.0e9
	if force != "":
		th._script.clear()
		th._script_i = 0
		tn().threat_rate_start = 0.0
		tn().threat_rate_end = 0.0
		tn().boss_first_meters = 1.0e9
		th._next_boss_m = 1.0e9
	while main.alive and t < max_seconds:
		var pl: Node = main.player
		target_x = 0.0
		for r in main.spawner._rows:   # the nearest fuel can that can still be reached in time
			if r.passed or not r.has_can:
				continue
			var dz: float = r.position.z - pl.position.z
			if dz > 1.0 or dz < -26.0:
				continue
			var time_left: float = -dz / maxf(main.spawner.scroll_speed, 1.0)
			if absf(r.can_x - pl.position.x) <= SPEED * maxf(time_left - 0.15, 0.0) + 0.5:
				target_x = r.can_x
				break
		if main.gadgets.level("roll") > 0 and main.gadgets.roll_cd <= 0.0 and imminent(main):
			main.try_roll()
		if t >= next_plan:
			next_plan = t + 0.08
			goal = plan(main, t, target_x, base_z)
		var d := goal - Vector2(pl.position.x, pl.position.z)
		var step := d.limit_length(SPEED * DT)
		pl.position.x += step.x
		pl.position.z += step.y
		if force != "" and t >= 4.0 and fmod(t, 9.0) < DT and th.active_count() == 0:
			th.elapsed = main.elapsed
			th.plane_x = pl.position.x
			th.plane_z = pl.position.z
			th._launch(th.NAMES.find(force) if th.NAMES.find(force) >= 0 else 0)
		if boss_env != "" and not boss_done and t >= 4.0:
			boss_done = true
			th._start_boss(int(boss_env) if boss_env != "mini" else 0, boss_env == "mini")
		var hb: int = main.hits_taken
		main._process(DT)
		t += DT
		if th.active_count() > 0 and OS.get_environment("SIM_CROWLOG") != "" and fmod(t, 0.2) < DT:
			for gg in th._groups:
				if gg.active and gg.kind == 2 and gg.state == 2:
					var xs2 := []
					for m in gg.members:
						xs2.append("%.1f" % m.x)
					print("    t=%.2f plane=(%.2f,%.2f) goal=(%.2f,%.2f) flock z=%.1f xs=%s danger_here=%.2f hits=%d" % [t, pl.position.x, pl.position.z, goal.x, goal.y, gg.z - pl.position.z, str(xs2), th.crow_danger(pl.position.x, pl.position.z), main.hits_taken])
		if main.hits_taken != hb and OS.get_environment("SIM_DEBUG") != "":
			var cols := []
			for ci in range(main.spawner.kit.col_count):
				var o: int = ci * 10
				var kc: PackedFloat32Array = main.spawner.kit.col
				if absf(kc[o + 2] - pl.position.z) < 7.0:
					cols.append("%s(%.1f,%.1f,%.1f,%.1f)" % ["R" if kc[o] == 0.0 else "C", kc[o + 1], kc[o + 2] - pl.position.z, kc[o + 3], kc[o + 4]])
			print("  HIT t=%.2f plane=(%.2f,%.2f) goal=(%.2f,%.2f) spd=%.1f kit near: %s" % [t, pl.position.x, pl.position.z, goal.x, goal.y, main.spawner.scroll_speed, " ".join(cols)])
		if main._picking:
			var idx := choose_card(main, kind)
			if trace:
				pick_log.append([snappedf(main.elapsed, 0.1), "PICK: " + String(main._pick_cards[idx]["name"]) + (" L%d" % main._pick_cards[idx]["level"] if main._pick_cards[idx]["kind"] == "perk" else "") + ("  (RARE)" if main._pick_rare else "")])
			main._on_pick_chosen(idx)
	var reason: String = "survived %ds" % int(max_seconds) if main.alive else String(main.hud._over.text.split("\n")[1] if main.hud._over.text.contains("\n") else main.hud._over.text)
	var res := {"t": t, "hits": main.hits_taken, "kills": th.kills, "shots": th.shots, "wing": main.gadgets.wingman_hits, "wash": main.gadgets.washes, "rolls": main.gadgets.rolls, "scatter": main.gadgets.scatters, "bosses": th.bosses_done,
			"cans": main.run_cans, "reason": reason, "last": main.last_hit_name, "score": main.score, "meters": tn().meters(main.run_distance),
			"timeline": th.timeline.duplicate(), "picks": pick_log, "launched": th.launched.duplicate(), "hits_by": {}}
	for k in th.hits_by_kind:
		res["hits_by"][th.NAMES[k]] = th.hits_by_kind[k]
	main.queue_free()
	await process_frame
	return res

func median(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])

func _initialize() -> void:
	DebugFlags.parse(["noprewarm"])
	for kv in OS.get_environment("SIM_TUNE").split(",", false):
		var parts := kv.split("=")
		tn().set(parts[0], float(parts[1]))
	if OS.get_environment("SIM_RUNS") != "":
		runs = int(OS.get_environment("SIM_RUNS"))
	if OS.get_environment("SIM_MAX") != "":
		max_seconds = float(OS.get_environment("SIM_MAX"))
	var only := OS.get_environment("SIM_ONLY")
	var seed_base := int(OS.get_environment("SIM_SEED")) if OS.get_environment("SIM_SEED") != "" else 2000
	for kind in (OS.get_environment("SIM_KINDS").split(",", false) if OS.get_environment("SIM_KINDS") != "" else ["NOPERK", "GUNS", "UTILITY", "MIXED"]):
		if only != "" and only != kind:
			continue
		var times: Array = []
		var hits := 0
		var kills := 0
		var shots := 0
		var wing := 0
		var rolls := 0
		var washes := 0
		var scat := 0
		var bosses := 0
		var reasons := {}
		var metersum := 0.0
		var hit_kinds := {}
		var launched := {}
		for i in runs:
			var r: Dictionary = await simulate(kind, seed_base + i, i == 0 and OS.get_environment("SIM_TRACE") != "")
			times.append(r["t"])
			hits += r["hits"]
			kills += r["kills"]
			shots += r["shots"]
			wing += r["wing"]
			rolls += r["rolls"]
			washes += r["wash"]
			scat += r["scatter"]
			bosses += r["bosses"]
			metersum += r["meters"]
			reasons[r["last"] if r["last"] != "" else r["reason"]] = int(reasons.get(r["last"] if r["last"] != "" else r["reason"], 0)) + 1
			for k in r["hits_by"]:
				hit_kinds[k] = int(hit_kinds.get(k, 0)) + int(r["hits_by"][k])
			for k in r["launched"]:
				launched[k] = int(launched.get(k, 0)) + int(r["launched"][k])
			print("  %s seed %d: %.0f s, %.0f m, cans %d, hits %d, kills %d, shots %d, bosses %d, ended: %s | %s" % [kind, seed_base + i, r["t"], r["meters"], r["cans"], r["hits"], r["kills"], r["shots"], r["bosses"], r["reason"], r["last"]])
			if i == 0 and OS.get_environment("SIM_TRACE") != "":
				var merged: Array = r["timeline"] + r["picks"]
				merged.sort_custom(func(a, b): return a[0] < b[0])
				for e in merged:
					if e[0] <= float(OS.get_environment("SIM_TRACE_UNTIL") if OS.get_environment("SIM_TRACE_UNTIL") != "" else "200"):
						print("      %5.1f s  %s" % [e[0], e[1]])
		print("%-8s survival s: min %.0f  median %.0f  max %.0f | hits/run %.1f | shots/run %.1f kills/run %.1f | wingman hits %.1f, waves %.0f, rolls %.1f, smoke scatters %.1f | bosses/run %.1f | m/run %.0f" % [
				kind, times.min(), median(times), times.max(), float(hits) / runs, float(shots) / runs, float(kills) / runs, float(wing) / runs, float(washes) / runs, float(rolls) / runs, float(scat) / runs, float(bosses) / runs, metersum / runs])
		print("       ended by %s | hits by %s | launched (all runs) %s" % [str(reasons), str(hit_kinds), str(launched)])
	quit()
