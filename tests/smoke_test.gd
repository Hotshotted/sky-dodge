extends SceneTree
## Headless smoke test:  godot --headless --path . --script res://tests/smoke_test.gd
## Exits with code 1 if anything below fails (CI runs this before exporting).
##   1. boot: the splash pre-warm draws every effect on screen, lasts long enough, then cleans up
##   2. three consecutive runs, each with near misses, ended by a crash and restarted IN PLACE by a
##      tap: the game-over UI shows the reason and score, the run resets, and NO new nodes,
##      materials or resources are created after start-up (pooled effects stay alive and warm)
##   2b. fuel: it drains, a can refills it (with a pooled pop), empty fuel ends the run with "Out of fuel"
##   2c. fuel can placement: only in open columns, never on the safe path, risk-biased
##   3. ?debug flags parse, and switching an effect off really skips it
##   4. plane collision capsules: span matches the wings, rounded corners graze past a cube corner
##   5. closest-approach near-miss detection reports the right side

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures.append(what)

func real_wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		await process_frame

## Everything that exists in the game right now: node ids, material ids, and engine counters.
func snapshot(main: Node) -> Dictionary:
	var nodes := {}
	var mats := {}
	_walk(main, nodes, mats)
	return {
		"nodes": nodes, "mats": mats,
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
	}

func _walk(n: Node, nodes: Dictionary, mats: Dictionary) -> void:
	nodes[n.get_instance_id()] = true
	var found: Array = []
	if n is GeometryInstance3D:
		found.append(n.material_override)
		found.append(n.material_overlay)
	if n is MeshInstance3D or n is CPUParticles3D:
		var mesh: Mesh = n.mesh
		if mesh is PrimitiveMesh:
			found.append(mesh.material)
		elif mesh != null:
			for i in mesh.get_surface_count():
				found.append(mesh.surface_get_material(i))
	for m in found:
		while m != null:
			mats[m.get_instance_id()] = true
			m = m.next_pass if m is BaseMaterial3D else null
	for c in n.get_children():
		_walk(c, nodes, mats)

func same_world(a: Dictionary, b: Dictionary) -> bool:
	return a["nodes"].hash() == b["nodes"].hash() and a["mats"].hash() == b["mats"].hash() \
			and a["node_count"] == b["node_count"] and a["resource_count"] == b["resource_count"]

func describe(a: Dictionary) -> String:
	return "%d nodes, %d materials, %d engine nodes, %d resources" % [a["nodes"].size(), a["mats"].size(), a["node_count"], a["resource_count"]]

func tap() -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = true
	Input.parse_input_event(ev)

## Put an obstacle right on the plane, then let the next frame crash into it.
func force_crash(main: Node) -> void:
	var pl: Node = main.player
	main.spawner._rows_make_for_test(pl.position.z, [pl.position.x])
	main.score = 1234.0   # a known score to look for in the game-over text

## Fire n near misses through the real handler (sparks, streaks, flash, popup, trail, haptic, punch).
func do_near_misses(main: Node, n: int) -> void:
	for i in n:
		var row = main.spawner._rows_make_for_test(-5.0, [1.0])
		main._on_near_miss({"side": 1, "node": row.obs[0], "outline": row.outlines[0]})
		await real_wait(0.05)
		main.spawner._release_row(row)

func count_visible(nodes: Array) -> int:
	var c := 0
	for n in nodes:
		if n.visible:
			c += 1
	return c

func _initialize() -> void:
	var tuning := root.get_node("Tuning")
	tuning.blocked_columns_min = 4   # crowded rows: easy to crash on purpose
	tuning.blocked_columns_max = 4
	DebugFlags.parse([])   # no debug flags

	print("1. boot and the visible pre-warm")
	var t_boot := Time.get_ticks_msec()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	await process_frame
	check(main._warming, "pre-warm is running at boot")
	check(is_instance_valid(main.hud._splash), "splash screen is shown during the pre-warm")
	var emitting := 0
	for e in main.fx._emitters:
		if e.emitting and e.visible:
			emitting += 1
	check(emitting == main.fx.SPARK_EMITTERS, "both spark emitters are drawing during the pre-warm (%d)" % emitting)
	check(count_visible(main.fx._streak_nodes) == main.fx.STREAK_POOL, "every pooled streak is visible during the pre-warm")
	check(main.trail._pts.size() >= 60 and main.trail._alpha > 0.0, "full-length trail ribbon is drawing (%d points)" % main.trail._pts.size())
	check(count_visible(main.hud._pop_labels) == main.hud.POPUP_POOL, "every pooled popup label is visible during the pre-warm")
	check(main.hud._over.visible, "game-over text is drawn during the pre-warm (font glyphs)")
	var cubes: Array = []
	for r in main.spawner._all_rows:
		cubes.append_array(r.cubes)
	check(cubes.size() == main.spawner.POOL_ROWS * tuning.column_count and count_visible(cubes) == cubes.size(),
			"every pooled obstacle cube (%d) is drawn during the pre-warm" % cubes.size())
	var cans: Array = []
	for r in main.spawner._all_rows:
		cans.append(r.can)
	check(count_visible(cans) == main.spawner.POOL_ROWS, "every pooled fuel can (%d) is drawn during the pre-warm" % cans.size())
	check(count_visible(main.fx._pickup_emitters) == main.fx.PICKUP_EMITTERS, "both fuel-pickup emitters are drawing during the pre-warm")
	var waited := 0.0
	while main._warming and waited < 12.0:
		await real_wait(0.1)
		waited += 0.1
	var boot_s := (Time.get_ticks_msec() - t_boot) / 1000.0
	check(not main._warming, "pre-warm finished (%.1f s)" % boot_s)
	check(boot_s >= tuning.prewarm_min_seconds, "pre-warm ran at least prewarm_min_seconds (%.1f s >= %.1f s)" % [boot_s, tuning.prewarm_min_seconds])
	await process_frame
	check(not is_instance_valid(main.hud._splash) or main.hud._splash.is_queued_for_deletion(), "splash removed afterwards")
	check(main.hud._mult.text == "x1" and not main.hud._over.visible, "HUD back to normal (x1, no game-over text)")
	var in_play := 0   # cubes legitimately visible: the live game has started spawning its first row(s)
	for r in main.spawner._rows:
		in_play += r.xs.size()
	var cans_in_play := 0
	for r in main.spawner._rows:
		cans_in_play += int(r.has_can)
	check(count_visible(cans) == cans_in_play and count_visible(main.fx._pickup_emitters) == 0, "no pre-warm cans or pickup puffs left behind")
	check(count_visible(cubes) == in_play and count_visible(main.fx._streak_nodes) == 0 and main.trail._pts.is_empty()
			and count_visible(main.fx._emitters) == 0, "no pre-warm effects left behind (only the live game's own cubes are showing: %d)" % in_play)
	check(main.alive, "run starts alive")

	print("1b. pre-warm length adapts to frame times")
	var saved_min: float = tuning.prewarm_min_seconds
	var saved_max: float = tuning.prewarm_max_seconds
	var saved_ms: float = tuning.prewarm_stable_ms
	tuning.prewarm_min_seconds = 0.3
	tuning.prewarm_max_seconds = 1.2
	tuning.prewarm_stable_ms = 0.0001     # no frame is ever "calm": must stop at the hard cap
	var t1 := Time.get_ticks_msec()
	await main._prewarm()
	var never_calm_s := (Time.get_ticks_msec() - t1) / 1000.0
	check(never_calm_s >= 1.15 and never_calm_s < 1.6, "frames never settle -> stops at prewarm_max_seconds (%.2f s, cap 1.2)" % never_calm_s)
	tuning.prewarm_stable_ms = 100000.0   # every frame is calm: stops as soon as the minimum has passed
	t1 = Time.get_ticks_msec()
	await main._prewarm()
	var calm_s := (Time.get_ticks_msec() - t1) / 1000.0
	check(calm_s >= 0.3 and calm_s < 0.7, "frames calm -> stops soon after prewarm_min_seconds (%.2f s, min 0.3)" % calm_s)
	tuning.prewarm_min_seconds = saved_min
	tuning.prewarm_max_seconds = saved_max
	tuning.prewarm_stable_ms = saved_ms
	check(not main._warming and count_visible(main.fx._streak_nodes) == 0, "repeat pre-warm cleans up after itself")

	print("2. three runs, restarted in place")
	await process_frame
	var base := snapshot(main)
	print("  start-up world: " + describe(base))
	var first_instance := main
	for run in [1, 2, 3]:
		print("  -- run %d --" % run)
		check(main.score < 100.0 and main.multiplier == 1 and main.alive and main.fuel > tuning.fuel_start - 5.0,
				"run %d starts fresh (score %d, x%d, fuel %.0f)" % [run, int(main.score), main.multiplier, main.fuel])
		check(not main.hud._over.visible, "game-over UI hidden while playing")
		await do_near_misses(main, 3)
		check(main.multiplier == 4 and main.hud._mult.text == "x4", "three near misses give x4 (%s)" % main.hud._mult.text)
		check(count_visible(main.hud._pop_labels) >= 1 and count_visible(main.fx._emitters) >= 1, "popup and sparks are showing")
		# fuel: drains; a can refills it with a pooled pop
		var f0: float = main.fuel
		await real_wait(0.4)
		check(main.fuel < f0 and absf((f0 - main.fuel) - tuning.fuel_drain * 0.4) < tuning.fuel_drain * 0.25,
				"fuel drains at about fuel_drain (%.2f in 0.4 s, expect ~%.2f)" % [f0 - main.fuel, tuning.fuel_drain * 0.4])
		main.fuel = 40.0
		var can_row = main.spawner._rows_make_for_test(main.player.position.z, [])
		main.spawner._place_can_for_test(can_row, main.player.position.x)
		await real_wait(0.1)
		check(not can_row.has_can and not can_row.can.visible, "driving into a can collects it")
		check(absf(main.fuel - (40.0 + tuning.fuel_refill)) < 1.5, "a can refills fuel_refill (%.1f -> %.1f)" % [40.0, main.fuel])
		check(count_visible(main.fx._pickup_emitters) >= 1 and main.hud._fuel_pulse_ms > 0, "the pickup pop (emitter + gauge flash) is showing")
		main.fuel = tuning.fuel_start - 5.0
		var cap_row = main.spawner._rows_make_for_test(main.player.position.z, [])
		main.spawner._place_can_for_test(cap_row, main.player.position.x)
		await real_wait(0.1)
		check(main.fuel <= tuning.fuel_start + 0.001, "a refill never goes above a full tank (%.1f)" % main.fuel)
		var snap := snapshot(main)
		check(same_world(base, snap), "near misses created nothing new  [%s]" % describe(snap))
		if run == 3:
			break
		var header: String = main.HEADER_CRASH
		var reason: String = main.REASON_OBSTACLE
		if run == 2:   # this run ends by running dry instead
			header = main.HEADER_FUEL
			reason = main.REASON_FUEL
			main.score = 1234.0
			main.fuel = 0.05
			await real_wait(0.3)
		else:
			force_crash(main)
			await real_wait(0.2)
		check(not main.alive, "run %d ends (%s)" % [run, header])
		check(main.hud._over.visible, "game-over UI is visible")
		var shown: String = main.hud._over.text
		var other_header: String = main.HEADER_FUEL if run != 2 else main.HEADER_CRASH
		check(shown.begins_with(header + "\n") and shown.contains(reason) and shown.contains("Score: 1234") and not shown.contains(other_header),
				"game-over header is \"%s\" with \"%s\" and the score, not \"%s\"  (\"%s\")" % [header, reason, other_header, shown.replace("\n", " | ")])
		check(run != 2 or main.fuel <= 0.0, "out-of-fuel run ended with an empty tank")
		await real_wait(0.6)   # Main ignores taps for 0.5 s after a crash
		tap()
		await real_wait(0.3)
		check(main == first_instance and current_scene == first_instance, "tap restarted the run IN PLACE (same scene instance)")
		check(main.alive and main.score < 100.0 and main.multiplier == 1, "restart reset score and multiplier")
		check(main.fuel > tuning.fuel_start - tuning.fuel_drain, "restart refilled the tank (%.1f / %.0f)" % [main.fuel, tuning.fuel_start])
		check(absf(main.hud._fuel_frac - main.fuel / tuning.fuel_start) < 0.05, "fuel gauge shows the full tank again")
		check(not main.hud._over.visible and main.hud._mult.text == "x1", "game-over UI hidden, multiplier label reset")
		check(count_visible(main.hud._pop_labels) == 0 and main.trail._pts.is_empty(), "old popups and trail cleared")
		check(main.player.active and absf(main.player.position.x) < 0.01 and main.player.velocity == Vector2.ZERO, "plane is back at the start")
		var stale_rows := 0   # anything near the plane would be left over from the previous run
		for r in main.spawner._rows:
			if r.position.z > -10.0:
				stale_rows += 1
		check(stale_rows == 0, "previous run's obstacles are gone (%d rows, new run's own rows are far above)" % main.spawner._rows.size())
		var after := snapshot(main)
		check(same_world(base, after), "restart created nothing new  [%s]" % describe(after))

	main.set_process(false)   # freeze the game loop: no real obstacles or near misses while the rest pokes at things
	await real_wait(1.2)      # let the last popup / streaks / flash expire
	var sp: Node = main.spawner
	var pl: Node = main.player

	print("2c. fuel can placement")
	var saved_chance: float = tuning.fuel_can_chance
	var saved_bias: float = tuning.fuel_risk_bias
	var saved_blk_min: int = tuning.blocked_columns_min   # the test's "crowded" rows leave one open column: no risky spot
	var saved_blk_max: int = tuning.blocked_columns_max
	tuning.blocked_columns_min = 2
	tuning.blocked_columns_max = 3
	tuning.fuel_can_chance = 1.0
	tuning.fuel_risk_bias = 1.0     # strict: risky spots only
	var n: int = tuning.column_count
	var bad_open := 0
	var on_safe := 0
	var not_risky := 0
	var placed := 0
	var rows := 4000
	var prev: Array[bool] = []
	for i in n:
		prev.append(true)
	var safe := n / 2
	for i in rows:
		var open: Array[bool] = sp._generate_open_columns(prev)
		var next_open: Array[bool] = sp._generate_open_columns(open)
		safe = sp._pick_safe_col(open, safe)
		var c: int = sp._choose_can_column(open, next_open, safe)
		if c >= 0:
			placed += 1
			if not open[c]:
				bad_open += 1
			if c == safe:
				on_safe += 1
			var beside := (c > 0 and not open[c - 1]) or (c < n - 1 and not open[c + 1])
			if not (beside or not next_open[c]):
				not_risky += 1
		prev = open
	check(placed > rows * 0.5, "cans are placed in most rows when chance is 1 (%d of %d)" % [placed, rows])
	check(bad_open == 0, "a can is never inside an obstacle column")
	check(on_safe == 0, "with risk bias 1 a can is never on the main safe path")
	check(not_risky == 0, "with risk bias 1 every can is next to an obstacle or in a column that closes next row")
	# bias 0: any open column, so some cans land on the safe path
	tuning.fuel_risk_bias = 0.0
	var any_on_safe := 0
	var any_placed := 0
	prev = []
	for i in n:
		prev.append(true)
	for i in rows:
		var open2: Array[bool] = sp._generate_open_columns(prev)
		var next2: Array[bool] = sp._generate_open_columns(open2)
		safe = sp._pick_safe_col(open2, safe)
		var c2: int = sp._choose_can_column(open2, next2, safe)
		if c2 >= 0:
			any_placed += 1
			if c2 == safe:
				any_on_safe += 1
		prev = open2
	check(any_on_safe > any_placed * 0.15, "with bias 0 cans also land on the safe path (%d of %d)" % [any_on_safe, any_placed])
	# lookahead: the "next row" the can placement saw is the row that really spawns next
	tuning.fuel_can_chance = 0.0
	sp.reset()
	sp._spawn_row(-30.0)
	var predicted: Array[bool] = sp._pending_open.duplicate()
	sp._spawn_row(-40.0)
	var actual_xs: Array[float] = sp._rows[-1].xs.duplicate()
	var matches := true
	for i in n:
		var blocked_in_row := actual_xs.any(func(x): return absf(x - tuning.column_center(i)) < 0.01)
		if blocked_in_row == predicted[i]:
			matches = false
	check(matches, "can placement looks at the real next row (lookahead matches the row that spawns)")
	sp.reset()
	tuning.fuel_can_chance = saved_chance
	tuning.fuel_risk_bias = saved_bias
	tuning.blocked_columns_min = saved_blk_min
	tuning.blocked_columns_max = saved_blk_max

	print("3. debug flags")
	DebugFlags.parse(["nofx=sparks,bogus", "noprewarm", "perf", "v=abc1234"])
	check(DebugFlags.off("sparks") and not DebugFlags.off("streaks"), "nofx=sparks switches off only sparks")
	check(DebugFlags.noprewarm and DebugFlags.perf, "noprewarm and perf are read")
	check(DebugFlags.summary() == "nofx=sparks noprewarm perf ?bogus", "summary shown by the stamp: \"%s\"" % DebugFlags.summary())
	DebugFlags.parse(["nofx=all"])
	check(DebugFlags.EFFECTS.all(func(e): return DebugFlags.off(e)), "nofx=all switches every effect off")
	check(DebugFlags.summary() == "nofx=" + ",".join(DebugFlags.EFFECTS), "summary lists them all")
	DebugFlags.parse(["nofx=Sparks%2CPopup"])   # URL-encoded comma, upper case
	check(DebugFlags.off("sparks") and DebugFlags.off("popup") and not DebugFlags.off("flash"), "names are case-insensitive and URL-decoded")
	DebugFlags.parse(["nofx=sparks,streaks,popup,flash,trail,haptic"])
	main.multiplier = 1
	for e in main.fx._emitters:
		e.emitting = false
		e.visible = false
	var row = sp._rows_make_for_test(-5.0, [1.0])
	main._on_near_miss({"side": 1, "node": row.obs[0], "outline": row.outlines[0]})
	check(main.multiplier == 2, "multiplier still rises with every effect off")
	check(count_visible(main.fx._emitters) == 0 and count_visible(main.fx._streak_nodes) == 0
			and count_visible(main.hud._pop_labels) == 0 and sp._flashes.is_empty(),
			"no spark / streak / popup / flash with ?nofx")
	DebugFlags.parse([])
	sp._release_row(row)

	print("3b. ?perf near-miss log")
	main.hud._perf_label = Label.new()
	main.hud.add_child(main.hud._perf_label)
	main.hud.note_near_miss(0.4)
	for i in 5:
		main.hud._update_perf(0.07 if i == 2 else 0.02)
	check(main.hud._nm_log.size() >= 1 and main.hud._nm_log[-1].contains("code 0.4 ms") and main.hud._nm_log[-1].contains("worst 70 ms"),
			"perf readout logs handler time and the worst following frame (%s)" % str(main.hud._nm_log[-1] if main.hud._nm_log.size() > 0 else ""))
	main.hud._perf_label.queue_free()
	main.hud._perf_label = null

	print("4. rounded wings: visible model and collision stay in sync")
	var k: float = tuning.plane_hit_scale
	var caps: PackedFloat32Array = pl.hit_capsules()
	var half: Vector2 = sp._obstacle_half()
	var wing_tip: float = pl.collision_half_span()
	check(absf(wing_tip - pl.WING_HALF.x * k) < 0.01, "collision wingspan matches the visible wings (%.3f half-span)" % wing_tip)
	var fo := caps.size() - 5
	check(absf(caps[fo + 3] + caps[fo + 4] - (pl.BODY_Z + pl.BODY_HALF.y * k)) < 0.001, "fuselage capsule reaches the visible tail")
	var wing_mesh: Mesh = pl._model.get_child(1).mesh
	var aabb := wing_mesh.get_aabb()
	check(absf(aabb.size.x - 2.0 * pl.WING_HALF.x) < 0.01 and absf(aabb.size.y - pl.WING_THICKNESS) < 0.001,
			"visible wing mesh is %.2f wide, %.2f thick" % [aabb.size.x, aabb.size.y])
	# every point of the visible outline (scaled by plane_hit_scale) lies inside the collision circles
	var outline: PackedVector2Array = pl.wing_outline(tuning.plane_tip_radius)
	var worst := 0.0
	for v in outline:
		var sv := Vector2(v.x * k, pl.WING_Z + (v.y - pl.WING_Z) * k)
		var best := INF
		for o in range(0, caps.size() - 5, 5):
			best = minf(best, Vector2(caps[o], caps[o + 1]).distance_to(sv) - caps[o + 4])
		worst = maxf(worst, best)
	check(worst < 0.03, "collision covers the visible wing outline (worst gap %.3f)" % worst)
	# the wing tapers: the chord at the tip is much narrower than at the root
	var root_r := 0.0
	var tip_r := INF
	for o in range(0, caps.size() - 5, 5):
		root_r = maxf(root_r, caps[o + 4])
		tip_r = minf(tip_r, caps[o + 4])
	check(root_r > 0.3 and tip_r < 0.25 and tip_r < root_r * 0.8, "collision tapers toward the tips (root %.2f, tip %.2f)" % [root_r, tip_r])
	var p0 := Vector2(0.0, 0.0)
	sp.reset()
	var test_row = sp._rows_make_for_test(0.0, [wing_tip + half.x + 0.05])
	check(not sp.hits(p0, caps), "wingtip 0.05 clear of a cube survives")
	test_row.xs[0] = wing_tip + half.x - 0.02
	check(sp.hits(p0, caps), "wingtip 0.02 inside a cube crashes")
	# corner graze: a cube corner 0.05 inside the old BOX corner of the wing, but outside the rounded tip
	var box_x: float = wing_tip
	var box_z: float = pl.WING_Z + pl.WING_HALF.y * k
	test_row.xs[0] = box_x - 0.05 + half.x
	test_row.position.z = box_z - 0.05 + half.y
	check(not sp.hits(p0, caps), "rounded wingtip survives a cube-corner graze that a box would have crashed on")
	# how much of the box's corner zone does the rounded tip give back?
	var saved := 0
	var total := 0
	for ix in 11:
		for iz in 11:
			var cx: float = box_x - 0.25 * ix / 10.0
			var cz: float = box_z - 0.25 * iz / 10.0
			test_row.xs[0] = cx + half.x
			test_row.position.z = cz + half.y
			total += 1
			if not sp.hits(p0, caps):
				saved += 1
	var pct := 100.0 * saved / total
	check(pct > 40.0, "a cube corner anywhere in the old box's 0.25 x 0.25 tip corner survives %.0f%% of the time (a box: 0%%)" % pct)
	sp.reset()

	print("5. near-miss closest approach")
	var near_row = sp._rows_make_for_test(-4.0, [wing_tip + half.x + 0.3])   # passes 0.3 clear on the right
	var found: Array[Dictionary] = []
	var z := -4.0
	while z < 6.0:
		near_row.position.z = z
		found.append_array(sp.update_near_misses(p0, caps))
		z += 0.1
	check(found.size() == 1 and found[0]["side"] == 1, "a pass 0.3 clear on the right gives one near miss on the right")
	sp.reset()
	var far_row = sp._rows_make_for_test(-4.0, [wing_tip + half.x + 1.5])    # 1.5 clear: not a near miss
	found.clear()
	z = -4.0
	while z < 6.0:
		far_row.position.z = z
		found.append_array(sp.update_near_misses(p0, caps))
		z += 0.1
	check(found.is_empty(), "a pass 1.5 clear is not a near miss")

	print("")
	if failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		print("SMOKE TEST FAILED: %d check(s)" % failures.size())
		quit(1)
