extends SceneTree
## Headless smoke test:  godot --headless --path . --script res://tests/smoke_test.gd
## Exits with code 1 if anything below fails (CI runs this before exporting).
##   1. boot: the splash pre-warm draws every effect on screen, lasts long enough, then cleans up
##   2. three consecutive runs, each with near misses, ended by a crash and restarted IN PLACE by a
##      tap: the game-over UI shows the reason and score, the run resets, and NO new nodes,
##      materials or resources are created after start-up (pooled effects stay alive and warm)
##   2b. fuel: it drains, a can refills it (with a pooled pop), empty fuel ends the run with "Out of fuel"
##   2c. fuel can placement: only in open columns, never on the safe path, risk-biased
##   2d. tuning panel (?tune): opens over the paused game, sliders edit Tuning live and apply, Copy and
##       Reset work, closing resumes, and none of it allocates anything; absent without ?tune
##   2e. the opening: the first row reaches the plane after ~opening_seconds, and never starts on screen
##   2f. a tap on the TUNE button doesn't restart the game; a tap elsewhere does
##   2g. controls: the plane moves 1:1 with the finger (no momentum), clamps to the play area, banks from
##       its real velocity, snap and visual smoothing work; a fast flick through a cube still crashes and
##       through a can still collects it (swept collision)
##   2h. clouds (free-floating bundles): none before cloud_start_time, more of them with speed, varied
##       sizes, off the column grid, drifting; never cover every open column's centre line (thousands of
##       generated rows, checked every step), fade in late, sit above obstacles/cans but below the plane,
##       hide cans more often, ?nofx=clouds disables them, restart clears them, nothing new is allocated
##   2i. bonus: logarithmic streak bonus, cap (gold MAX label), gradual decay, reset on crash, huge caps
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

## Feed the player a finger drag of `rel` viewport pixels (straight to its _input, in viewport units).
func drag_by(pl: Node, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	ev.position = Vector2(500.0, 900.0)
	ev.relative = rel
	pl._input(ev)

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
	DebugFlags.parse(["tune"])   # the whole run has the tuning panel, so it is part of the "nothing new" baseline

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
	check(main.tune_panel != null and main.tune_panel._panel.visible and main.tune_panel._panel_layer.layer == 0,
			"?tune: the panel is drawn during the pre-warm, under the splash (layer 0)")
	check(not main.tune_panel._button.visible, "?tune: the TUNE button stays hidden while starting up")
	var cans: Array = []
	for r in main.spawner._all_rows:
		cans.append(r.can)
	check(count_visible(cans) == main.spawner.POOL_ROWS, "every pooled fuel can (%d) is drawn during the pre-warm" % cans.size())
	var blobs: Array = []
	for cl in main.spawner._all_clouds:
		blobs.append_array(cl.puffs)
	check(blobs.size() == main.spawner.CLOUD_POOL * main.spawner.PUFFS_PER_CLOUD and count_visible(blobs) == blobs.size(),
			"every pooled cloud puff (%d) is drawn during the pre-warm" % blobs.size())
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
	check(main.hud._bonus_label.text == "" and not main.hud._over.visible, "HUD back to normal (x1, no game-over text)")
	var in_play := 0   # cubes legitimately visible: the live game has started spawning its first row(s)
	for r in main.spawner._rows:
		in_play += r.xs.size()
	var cans_in_play := 0
	for r in main.spawner._rows:
		cans_in_play += int(r.has_can)
	check(count_visible(cans) == cans_in_play and count_visible(main.fx._pickup_emitters) == 0, "no pre-warm cans or pickup puffs left behind")
	check(count_visible(blobs) == 0, "no pre-warm cloud puffs left behind (no clouds in the first %.0f s)" % tuning.cloud_start_time)
	check(count_visible(cubes) == in_play and count_visible(main.fx._streak_nodes) == 0 and main.trail._pts.is_empty()
			and count_visible(main.fx._emitters) == 0, "no pre-warm effects left behind (only the live game's own cubes are showing: %d)" % in_play)
	check(main.alive, "run starts alive")
	check(not main.tune_panel._panel.visible and main.tune_panel._button.visible, "?tune: panel hidden and TUNE button shown once started")

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
		check(main.score < 100.0 and main.bonus == 1 and main.alive and main.fuel > tuning.fuel_start - 5.0,
				"run %d starts fresh (score %d, x%.1f, fuel %.0f)" % [run, int(main.score), main.bonus, main.fuel])
		check(not main.hud._over.visible, "game-over UI hidden while playing")
		await do_near_misses(main, 3)
		check(is_equal_approx(main.bonus, tuning.streak_bonus(3.0)) and main.hud._bonus_label.text == "x%.1f POINTS" % main.bonus, "three close calls give x%.1f (%s)" % [main.bonus, main.hud._bonus_label.text])
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
		check(main.alive and main.score < 100.0 and main.bonus == 1, "restart reset score and bonus")
		check(main.fuel > tuning.fuel_start - tuning.fuel_drain, "restart refilled the tank (%.1f / %.0f)" % [main.fuel, tuning.fuel_start])
		check(absf(main.hud._fuel_frac - main.fuel / tuning.fuel_start) < 0.05, "fuel gauge shows the full tank again")
		check(not main.hud._over.visible and main.hud._bonus_label.text == "", "game-over UI hidden, bonus label reset")
		check(count_visible(main.hud._pop_labels) == 0 and main.trail._pts.is_empty(), "old popups and trail cleared")
		check(main.player.active and absf(main.player.position.x) < 0.01 and main.player.velocity == Vector2.ZERO, "plane is back at the start")
		var stale_rows := 0   # anything near the plane would be left over from the previous run
		for r in main.spawner._rows:
			if r.position.z > -4.0:   # a leftover would be near the plane; the new run's first row is far above
				stale_rows += 1
		check(stale_rows == 0, "previous run's obstacles are gone (%d rows, new run's own rows are far above)" % main.spawner._rows.size())
		var after := snapshot(main)
		check(same_world(base, after), "restart created nothing new  [%s]" % describe(after))

	print("2d. tuning panel")
	var panel = main.tune_panel   # (untyped: naming the class would compile it before the autoloads exist)
	var defaults := {}
	for e in panel.ENTRIES:
		defaults[e[0]] = tuning.get(e[0])
	for t in panel.TOGGLES:
		defaults[t[0]] = tuning.get(t[0])
	check(panel.ENTRIES.size() == 19 and panel._sliders.size() == 19 and panel._toggles.size() == 1, "19 sliders and 1 on/off switch for the tuned values")
	var all_match := true
	for e in panel.ENTRIES:
		if not is_equal_approx(panel._sliders[e[0]].value, tuning.get(e[0])):
			all_match = false
	check(all_match, "each slider starts at the current Tuning value")
	var events: Array[String] = []
	panel.changed.connect(func(property: String) -> void: events.append(property))
	panel.open()
	check(paused and panel.is_open and panel._panel.visible and panel._panel_layer.layer == 19 and panel._button.text == "CLOSE",
			"opening the panel pauses the game and shows it over everything")
	var score_open: float = main.score
	await real_wait(0.3)
	check(main.score == score_open, "the game is really paused while the panel is open")
	panel._sliders["fuel_drain"].value = 4.0
	check(is_equal_approx(tuning.fuel_drain, 4.0) and events.has("fuel_drain"), "dragging a slider edits Tuning live (fuel_drain = %.1f)" % tuning.fuel_drain)
	check(panel._value_labels["fuel_drain"].text.contains("4.0") and panel._value_labels["fuel_drain"].text.contains("default"), "the label shows the value and the default (\"%s\")" % panel._value_labels["fuel_drain"].text)
	var live_row = main.spawner._rows_make_for_test(-5.0, [1.0])
	panel._sliders["obstacle_scale"].value = 0.5
	check(absf(live_row.obs[0].scale.x - tuning.column_width() * 0.5) < 0.001, "obstacle scale applies to rows already on screen")
	panel._sliders["plane_tip_radius"].value = 0.30
	panel._sliders["base_speed"].value = 9.0
	panel._sliders["sensitivity"].value = 1.5
	panel._toggles["snap_enabled"].button_pressed = true
	check(tuning.snap_enabled and events.has("snap_enabled") and is_equal_approx(tuning.sensitivity, 1.5), "the sensitivity slider and the snap switch edit Tuning live")
	panel.copy_values()
	var copied: String = panel.last_copied_text
	check(copied.contains("fuel_drain = 4.0") and copied.contains("obstacle_scale = 0.50") and copied.contains("plane_tip_radius = 0.30")
			and copied.contains("base_speed = 9.0") and copied.contains("sensitivity = 1.50") and copied.contains("snap_enabled = true")
			and not copied.contains("fuel_refill"),
			"Copy values lists only what changed  (\"%s\")" % copied.replace("\n", "; "))
	check(panel._out.text.begins_with("Copied"), "the copied text is also shown on screen")
	panel.reset_defaults()
	var back := true
	for e in panel.ENTRIES:
		if not is_equal_approx(tuning.get(e[0]), defaults[e[0]]) or not is_equal_approx(panel._sliders[e[0]].value, defaults[e[0]]):
			back = false
	back = back and not tuning.snap_enabled and not panel._toggles["snap_enabled"].button_pressed
	check(back and panel.changed_text() == "(no changes)", "Reset restores every default (sliders and the snap switch)")
	check(absf(live_row.obs[0].scale.x - tuning.column_width() * tuning.obstacle_scale) < 0.001, "...including the obstacle size on screen")
	panel._sliders["plane_tip_radius"].value = 0.30   # leave one visual change to check after resuming
	panel.close()
	check(not paused and not panel.is_open and not panel._panel.visible and panel._button.text == "TUNE", "closing the panel resumes the game")
	await real_wait(0.2)
	check(main.score > score_open, "...and it is running again")
	check(main.player._wing_built_for == 0.30, "the visible wing was reshaped for the new tip radius")
	var panel_tip := 1.0
	var caps2: PackedFloat32Array = main.player.hit_capsules()
	for o in range(0, caps2.size() - 5, 5):
		panel_tip = minf(panel_tip, caps2[o + 4])
	check(absf(panel_tip - 0.30 * tuning.plane_hit_scale) < 0.02, "...and the collision follows it (tip circle %.3f)" % panel_tip)
	panel.reset_defaults()
	main.spawner.reset(-30.0)
	await real_wait(0.1)
	var after_panel := snapshot(main)
	check(same_world(base, after_panel), "opening, editing, copying, resetting and closing created nothing new  [%s]" % describe(after_panel))

	print("2e. the opening")
	main.restart()
	main.set_process(false)   # step the game by hand
	var plane_z: float = main.player.position.z
	var first_row_z: float = main._first_row_z(main._half_height())
	check(first_row_z <= -(main._half_height() + 1.0) + 0.001, "the first row starts above the screen (z %.1f, screen top %.1f)" % [first_row_z, -main._half_height()])
	var saved_blk_a: int = tuning.blocked_columns_min   # no cubes, so the plane can't crash into the row we're timing
	var saved_blk_b: int = tuning.blocked_columns_max
	tuning.blocked_columns_min = 0
	tuning.blocked_columns_max = 0
	main.spawner.reset(first_row_z)
	var open_t := 0.0
	var arrived := -1.0
	while open_t < 6.0 and arrived < 0.0:
		main._process(1.0 / 60.0)
		open_t += 1.0 / 60.0
		for r in main.spawner._rows:
			if arrived < 0.0 and r.position.z >= main.player.position.z:
				arrived = open_t
	check(arrived > 0.0 and absf(arrived - tuning.opening_seconds) < 0.25 + (0.0 if first_row_z < -(main._half_height() + 1.0) + 0.01 else 1.0),
			"the first row reaches the plane after %.2f s (opening_seconds %.1f)" % [arrived, tuning.opening_seconds])
	tuning.blocked_columns_min = saved_blk_a
	tuning.blocked_columns_max = saved_blk_b
	var z_short: float = main._first_row_z(3.0)
	var z_tall: float = main._first_row_z(25.0)
	var travel: float = tuning.base_speed * tuning.opening_seconds + 0.5 * tuning.speed_ramp * tuning.opening_seconds * tuning.opening_seconds
	check(absf(z_short - (plane_z - travel)) < 0.001, "on a short screen the row starts exactly opening_seconds away")
	check(z_tall <= -26.0 + 0.001, "on a very tall screen it never starts on screen (z %.1f)" % z_tall)
	main.restart()

	print("2f. the TUNE button doesn't restart the game")
	await real_wait(0.3)   # let the button's rect settle
	force_crash(main)
	main.set_process(true)
	await real_wait(0.2)
	check(not main.alive, "crashed")
	await real_wait(0.6)
	var press := InputEventScreenTouch.new()
	press.pressed = true
	press.position = panel._button_rect.get_center()
	main._input(press)
	check(not main.alive and panel.button_hit(press.position), "a tap on the TUNE button is ignored by the game (still on the game-over screen)")
	var elsewhere := InputEventScreenTouch.new()
	elsewhere.pressed = true
	elsewhere.position = Vector2(100.0, 900.0)
	main._input(elsewhere)
	check(main.alive, "a tap anywhere else restarts")

	main.set_process(false)   # freeze the game loop: no real obstacles or near misses while the rest pokes at things

	print("2g. controls: 1:1 follow, no momentum, swept collision")
	var saved_ctl := {"blocked_a": tuning.blocked_columns_min, "blocked_b": tuning.blocked_columns_max, "chance": tuning.fuel_can_chance,
			"sens": tuning.sensitivity, "smooth": tuning.visual_smoothing, "snap": tuning.snap_enabled}
	tuning.blocked_columns_min = 0
	tuning.blocked_columns_max = 0
	tuning.fuel_can_chance = 0.0
	tuning.sensitivity = 1.0
	tuning.visual_smoothing = 0.0
	tuning.snap_enabled = false
	main.restart()
	var pc = main.player
	var spc = main.spawner
	spc.reset(-200.0)   # nothing near the plane unless the test puts it there
	var wpp: float = pc.world_per_pixel()
	var stretch: float = 1.0 / cos(deg_to_rad(tuning.camera_tilt_deg))
	var dt := 1.0 / 60.0
	var x_start: float = pc.position.x
	var z_start: float = pc.position.z
	drag_by(pc, Vector2(120.0, 0.0))
	main._process(dt)
	check(absf((pc.position.x - x_start) - 120.0 * wpp) < 0.0001, "a 120 px drag moves the plane exactly 120 px of screen (%.4f units, expect %.4f)" % [pc.position.x - x_start, 120.0 * wpp])
	drag_by(pc, Vector2(0.0, -60.0))
	main._process(dt)
	check(absf((pc.position.z - z_start) - (-60.0 * wpp * stretch)) < 0.0001, "up/down drags follow 1:1 on screen too (tilt-corrected)")
	var x_now: float = pc.position.x
	var v_move: float = pc.velocity.length()
	main._process(dt)
	main._process(dt)
	check(pc.position.x == x_now and pc.velocity.length() < 0.0001 and v_move > 1.0, "no momentum: the plane stops the instant the finger does")
	drag_by(pc, Vector2(60.0, 0.0))
	main._process(dt)
	check(absf(pc.velocity.x - 60.0 * wpp / dt) < 0.01, "velocity is the plane's actual movement (%.2f u/s)" % pc.velocity.x)
	tuning.sensitivity = 0.5
	x_now = pc.position.x
	drag_by(pc, Vector2(100.0, 0.0))
	main._process(dt)
	check(absf((pc.position.x - x_now) - 50.0 * wpp) < 0.0001, "sensitivity 0.5 moves the plane half as far")
	tuning.sensitivity = 1.0
	drag_by(pc, Vector2(100000.0, 0.0))
	main._process(dt)
	var x_limit: float = tuning.ortho_size * 0.5 - tuning.plane_edge_margin
	check(absf(pc.position.x - x_limit) < 0.0001, "a huge drag is clamped to the play area (x = %.2f)" % pc.position.x)
	check(main.alive, "...and flying into the screen edge doesn't crash")
	drag_by(pc, Vector2(0.0, 100000.0))
	main._process(dt)
	check(absf(pc.position.z - pc.z_max) < 0.0001, "...and so is the forward/back range")
	# banking and yaw follow the real velocity, smoothed, and stay bounded
	pc.position.x = -2.0
	for i in 8:
		drag_by(pc, Vector2(80.0, 0.0))
		main._process(dt)
	var roll: float = pc._model.rotation.z
	var yaw: float = pc._model.rotation.y
	check(roll < -0.05 and roll >= -tuning.bank_max - 0.001 and yaw < 0.0 and yaw >= -tuning.yaw_max - 0.001,
			"moving right banks and yaws the plane, within limits (roll %.2f, yaw %.2f)" % [roll, yaw])
	for i in 60:
		main._process(dt)
	check(absf(pc._model.rotation.z) < 0.02, "it levels out again once it stops")
	# soft snap: off by default, eases to the nearest column centre when on, never while the finger is down
	pc.position.x = 0.8
	pc.touching = false
	for i in 90:
		main._process(dt)
	check(absf(pc.position.x - 0.8) < 0.0001, "snap off: the plane stays exactly where the finger left it")
	tuning.snap_enabled = true
	pc.touching = true
	for i in 30:
		main._process(dt)
	check(absf(pc.position.x - 0.8) < 0.0001, "snap on, finger down: no snapping")
	pc.touching = false
	for i in 120:
		main._process(dt)
	check(absf(pc.position.x - 0.0) < 0.01, "snap on, finger lifted: eases to the nearest column centre (x = %.3f)" % pc.position.x)
	tuning.snap_enabled = false
	# visual smoothing lags only the DRAWN plane, never the collision position
	tuning.visual_smoothing = 0.1
	x_now = pc.position.x
	drag_by(pc, Vector2(200.0, 0.0))
	main._process(dt)
	check(absf((pc.position.x - x_now) - 200.0 * wpp) < 0.0001 and pc._model.position.length() > 0.2,
			"visual smoothing: true position jumps, the drawn plane trails (%.2f behind)" % pc._model.position.length())
	for i in 60:
		main._process(dt)
	check(pc._model.position.length() < 0.05, "...and catches up")
	tuning.visual_smoothing = 0.0
	drag_by(pc, Vector2(200.0, 0.0))
	main._process(dt)
	check(pc._model.position == Vector3.ZERO, "smoothing 0: the drawn plane is exactly on the true position")

	# swept collision: a flick of 6 units in ONE frame
	main.restart()
	spc.reset(-200.0)
	pc.position.x = -3.0
	var cube_row = spc._rows_make_for_test(pc.position.z, [0.0])
	var end_x := 3.0
	var end_clear: bool = not spc.hits(Vector2(end_x, pc.position.z), pc.hit_capsules())
	drag_by(pc, Vector2((end_x - pc.position.x) / wpp, 0.0))
	main._process(dt)
	check(end_clear, "(setup) the flick's END point alone is clear of the cube, so only a swept test can see it")
	check(not main.alive and main.hud._over.text.contains(main.HEADER_CRASH), "a fast flick through a cube crashes")
	var touch_x: float = -(spc._obstacle_half().x + pc.collision_half_span())   # wingtip meets the cube's left edge
	check(absf(pc.position.x - touch_x) < 0.02, "...stopping exactly where it first touched, not inside it or on the far side (x = %.3f, touch at %.3f)" % [pc.position.x, touch_x])
	main.restart()
	spc.reset(-200.0)
	pc.position.x = -3.0
	spc._rows_make_for_test(pc.position.z, [])   # an empty row: nothing to hit
	drag_by(pc, Vector2(6.0 / wpp, 0.0))
	main._process(dt)
	check(main.alive and absf(pc.position.x - 3.0) < 0.0001, "the same flick through empty space is fine")
	# ...and through a fuel can
	main.restart()
	spc.reset(-200.0)
	pc.position.x = -3.0
	main.fuel = 50.0
	var can_row = spc._rows_make_for_test(pc.position.z, [])
	spc._place_can_for_test(can_row, 0.0)
	var cans_caps: PackedFloat32Array = pc.hit_capsules()
	var closest := INF
	for o in range(0, cans_caps.size(), 5):
		closest = minf(closest, Vector2(end_x + cans_caps[o], pc.position.z + cans_caps[o + 1]).distance_to(Vector2(0.0, can_row.position.z)) - cans_caps[o + 4])
	drag_by(pc, Vector2((end_x - pc.position.x) / wpp, 0.0))
	main._process(dt)
	check(closest > tuning.fuel_pickup_radius, "(setup) the flick's end point alone would miss the can (%.2f away)" % closest)
	check(not can_row.has_can and main.fuel > 50.0 + tuning.fuel_refill - 1.0, "a fast flick through a fuel can collects it (fuel %.1f)" % main.fuel)
	check(main.alive, "...without crashing")
	tuning.blocked_columns_min = saved_ctl["blocked_a"]
	tuning.blocked_columns_max = saved_ctl["blocked_b"]
	tuning.fuel_can_chance = saved_ctl["chance"]
	tuning.sensitivity = saved_ctl["sens"]
	tuning.visual_smoothing = saved_ctl["smooth"]
	tuning.snap_enabled = saved_ctl["snap"]
	main.restart()
	main.set_process(false)
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

	print("2h. clouds")
	var cl_saved := {"start": tuning.cloud_start_time, "freq": tuning.cloud_frequency, "chance": tuning.fuel_can_chance,
			"under": tuning.fuel_can_under_cloud_chance, "bias": tuning.fuel_risk_bias, "bmin": tuning.blocked_columns_min, "bmax": tuning.blocked_columns_max}
	tuning.blocked_columns_min = 2
	tuning.blocked_columns_max = 3
	var ncol: int = tuning.column_count
	sp.reset()
	var step := 1.5
	sp.plane_z = 4.0
	# (a) nothing before cloud_start_time
	tuning.cloud_start_time = 25.0
	tuning.cloud_frequency = 1.0
	sp.run_time = 5.0
	sp.scroll_speed = 12.0
	var early := 0
	for i in 400:
		sp.advance(step)
		early += sp._clouds.size()
	check(early == 0, "no clouds before cloud_start_time (%d bundle-steps in 400 steps)" % early)
	# (b) the frequency grows with speed (average bundles alive over the same distance)
	tuning.cloud_frequency = 0.3
	sp.run_time = 30.0
	var at_start_speed: float = tuning.base_speed + tuning.speed_ramp * tuning.cloud_start_time
	var alive := []
	for spd in [at_start_speed, tuning.max_speed]:
		sp.scroll_speed = spd
		sp.reset()
		var total := 0
		for i in 3000:
			sp.advance(step)
			total += sp._clouds.size()
		alive.append(float(total) / 3000.0)
	check(alive[0] > 0.5 and alive[1] > alive[0] * 1.4, "clouds come more often at speed: %.1f bundles alive at start speed, %.1f at top speed" % [alive[0], alive[1]])
	# (c) fairness over thousands of rows, with clouds as frequent as possible, checked at EVERY step:
	# every row ahead of the plane keeps an open column whose centre line no visible puff covers now
	# or while it drifts to the plane.
	tuning.cloud_frequency = 1.5
	sp.scroll_speed = tuning.max_speed
	sp.run_time = 100.0
	tuning.fuel_can_chance = 0.18
	tuning.fuel_can_under_cloud_chance = 0.45
	tuning.fuel_risk_bias = 1.0
	sp.reset()
	sp.puffs_removed = 0
	var rows_n := 3000
	var seen_rows := 0
	var cloud_rows := 0
	var covered_gaps := 0
	var covered_cubes := 0
	var unfair := 0
	var eligible := 0
	var can_under := 0
	var can_on_safe := 0
	var last_row = null
	var rmin := INF
	var rmax := 0.0
	var off_grid := 0
	var bundles := 0
	var sizes := {}
	var max_alive := 0
	var st := {"bundles": 0, "rmin": INF, "rmax": 0.0, "off": 0}
	var on_spawn := func(cl):
		st["bundles"] += 1
		var used := 0
		for k in cl.puffs.size():
			used += int(cl.on[k])
			if cl.on[k]:
				st["rmin"] = minf(st["rmin"], cl.rad[k])
				st["rmax"] = maxf(st["rmax"], cl.rad[k])
		sizes[clampi(used, 1, 7)] = true
		var nearest := INF
		for c in ncol:
			nearest = minf(nearest, absf(cl.position.x - tuning.column_center(c)))
		st["off"] += int(nearest > 0.3)
	sp.cloud_spawned.connect(on_spawn)
	while seen_rows < rows_n:
		sp.advance(step)
		max_alive = maxi(max_alive, sp._clouds.size())
		for r in sp._rows:
			if r.open.is_empty() or r.position.z > sp.plane_z:
				continue
			if sp._clear_column(r) < 0:
				unfair += 1
		var fr = sp._rows[-1]
		if fr != last_row:
			last_row = fr
			seen_rows += 1
			var safe_c: int = sp._safe_col
			var any_cov := false
			var cov_open_not_safe := false
			for c in ncol:
				if fr.cloud_cov[c]:
					any_cov = true
					covered_gaps += 1
					if c != safe_c:
						cov_open_not_safe = true
				elif fr.open[c] == false and sp._covered(fr.position.z, tuning.column_center(c)):
					covered_cubes += 1
			cloud_rows += int(any_cov)
			if cov_open_not_safe:
				eligible += 1
				if fr.has_can:
					for c in ncol:
						if fr.cloud_cov[c] and absf(fr.can_x - tuning.column_center(c)) < 0.01:
							can_under += 1
			if fr.has_can and absf(fr.can_x - tuning.column_center(safe_c)) < 0.01:
				can_on_safe += 1
	sp.cloud_spawned.disconnect(on_spawn)
	bundles = st["bundles"]
	rmin = st["rmin"]
	rmax = st["rmax"]
	off_grid = st["off"]
	check(unfair == 0, "FAIRNESS: over %d generated rows (%d with open gaps under cloud) no row ever lost every open column's centre line to cloud" % [seen_rows, cloud_rows])
	check(covered_gaps > 500 and covered_cubes > 300 and sp.puffs_removed > 50,
			"(not vacuous) clouds covered %d open gaps and %d cubes, and the rule had to remove %d puffs" % [covered_gaps, covered_cubes, sp.puffs_removed])
	check(bundles > 300 and rmin < 1.2 and rmax > 2.0 and sizes.size() >= 5,
			"bundles vary: %d of them, puff radius %.1f to %.1f, %d different puff counts" % [bundles, rmin, rmax, sizes.size()])
	check(float(off_grid) / bundles > 0.5, "they are not snapped to the columns (%.0f%% sit more than 0.3 from a column centre)" % (100.0 * off_grid / bundles))
	check(max_alive <= sp.CLOUD_POOL, "never more bundles than the pool (%d <= %d)" % [max_alive, sp.CLOUD_POOL])
	check(eligible > 300 and float(can_under) / eligible > 0.35, "cans are placed under clouds %.0f%% of the time they can be (chance %.2f) (%d of %d rows)" % [100.0 * can_under / maxf(eligible, 1.0), tuning.fuel_can_under_cloud_chance, can_under, eligible])
	check(can_on_safe == 0, "...and still never on the safe path")
	# (c2) coverage at the normal tuning, for the record
	tuning.cloud_frequency = cl_saved["freq"]
	var cov_report := []
	for spd in [at_start_speed, tuning.max_speed]:
		sp.scroll_speed = spd
		sp.reset()
		var any_rows := 0
		var n_rows := 0
		var lr = null
		while n_rows < 1500:
			sp.advance(step)
			var cr2 = sp._rows[-1]
			if cr2 != lr:
				lr = cr2
				n_rows += 1
				any_rows += int(cr2.cloud_cov.has(true))
		cov_report.append(100.0 * any_rows / n_rows)
	print("   (coverage at default tuning: %.0f%% of rows have a gap under cloud at start speed, %.0f%% at top speed)" % [cov_report[0], cov_report[1]])
	# (c3) drift: a bundle moves with the scroll (z) and sideways by slope per unit scrolled
	sp.reset()
	sp._spawn_cloud(-10.0)
	var dc = sp._clouds[-1]
	dc.slope = 0.1
	var x_before: float = dc.position.x
	var z_before: float = dc.position.z
	sp._advance_clouds(10.0)
	check(is_equal_approx(dc.position.z, z_before + 10.0) and is_equal_approx(dc.position.x, x_before + 1.0), "a bundle scrolls with the world and drifts sideways (slope 0.1 x 10 units = 1.0)")
	# (d) late reveal
	sp.reset()
	sp.plane_z = 3.0
	sp._spawn_cloud(-10.0)
	var cr = sp._clouds[-1]
	var reveal: float = tuning.cloud_reveal_distance
	var alphas := []
	for z in [sp.plane_z - reveal - 10.0, sp.plane_z - reveal, sp.plane_z - reveal * 0.5, sp.plane_z, sp.plane_z + 8.0]:
		cr.position.z = z - cr.oz[0]
		sp._update_cloud_alpha(cr)
		alphas.append(cr.mats[0].albedo_color.a)
	check(is_equal_approx(alphas[0], tuning.cloud_max_opacity) and is_equal_approx(alphas[1], tuning.cloud_max_opacity),
			"far from the plane a cloud is nearly opaque (%.2f)" % alphas[0])
	check(alphas[2] < alphas[1] and alphas[2] > alphas[3], "it fades as it approaches (%.2f at half the reveal distance)" % alphas[2])
	check(is_equal_approx(alphas[3], tuning.cloud_min_opacity) and is_equal_approx(alphas[4], tuning.cloud_min_opacity),
			"at the plane (and after passing it) it is at cloud_min_opacity (%.2f)" % alphas[3])
	sp.reset()
	# (e) vertical layering: above obstacles and cans, below the plane
	var puff_aabb: AABB = sp._cloud_mesh.get_aabb()
	var cloud_bottom: float = sp.CLOUD_Y + puff_aabb.position.y
	var cloud_top: float = sp.CLOUD_Y + 0.03 + puff_aabb.end.y   # (+0.03: each puff sits a hair higher or lower)
	var obstacle_top: float = tuning.column_width() * tuning.obstacle_scale * 0.5 + tuning.outline_thickness
	var can_top: float = 0.25 + 0.12 + tuning.fuel_can_size * 0.5
	var plane_bottom := INF
	for part in pl._model.get_children():
		var pa: AABB = part.global_transform * part.mesh.get_aabb()
		plane_bottom = minf(plane_bottom, pa.position.y)
	check(cloud_bottom >= obstacle_top and cloud_bottom >= can_top - 0.001, "clouds sit above the obstacles (top %.2f) and cans (top %.2f): slab starts at %.2f" % [obstacle_top, can_top, cloud_bottom])
	check(cloud_top < plane_bottom, "...and below the plane (cloud top %.2f < plane bottom %.2f), so the plane always draws on top" % [cloud_top, plane_bottom])
	# (f) ?nofx=clouds
	DebugFlags.parse(["nofx=clouds"])
	sp.reset()
	var none := 0
	for i in 600:
		sp.advance(step)
		none += sp._clouds.size()
	DebugFlags.parse([])
	check(none == 0, "?nofx=clouds: no clouds at all")
	# (g) restart clears them and nothing new was allocated by any of that
	sp.scroll_speed = tuning.max_speed
	tuning.cloud_frequency = 1.5
	for i in 200:
		sp.advance(step)
	check(sp._clouds.size() > 0, "clouds exist before the restart")
	main.restart()
	var shown := 0
	for cl in sp._all_clouds:
		shown += int(cl.visible)
		for pf in cl.puffs:
			shown += int(pf.visible)
	check(shown == 0 and sp._clouds.is_empty(), "an in-place restart clears every cloud")
	tuning.cloud_start_time = cl_saved["start"]
	tuning.cloud_frequency = cl_saved["freq"]
	tuning.fuel_can_chance = cl_saved["chance"]
	tuning.fuel_can_under_cloud_chance = cl_saved["under"]
	tuning.fuel_risk_bias = cl_saved["bias"]
	tuning.blocked_columns_min = cl_saved["bmin"]
	tuning.blocked_columns_max = cl_saved["bmax"]
	sp.run_time = 0.0
	main.set_process(false)
	var after_clouds := snapshot(main)
	check(same_world(base, after_clouds), "generating thousands of cloud rows created nothing new  [%s]" % describe(after_clouds))

	print("2i. bonus: logarithmic streak bonus with a cap")
	var bsaved := {"scale": tuning.bonus_scale, "cap": tuning.bonus_cap}
	tuning.bonus_scale = 1.2
	tuning.bonus_cap = 3.0
	check(tuning.streak_bonus(0.0) == 1.0 and is_equal_approx(tuning.streak_bonus(1.0), 1.0 + 1.2 * log(2.0)) and is_equal_approx(tuning.streak_bonus(3.0), 1.0 + 1.2 * log(4.0)),
			"bonus = 1 + scale * ln(1 + streak)  (streak 1 = %.2f, 3 = %.2f)" % [tuning.streak_bonus(1.0), tuning.streak_bonus(3.0)])
	check(tuning.streak_bonus(1000.0) == 3.0 and tuning.streak_bonus(tuning.streak_at_cap()) >= 3.0 - 0.0001, "clamped to bonus_cap (3.0), reached at streak %.1f" % tuning.streak_at_cap())
	main._reset_bonus()
	main.set_process(false)
	var brow = sp._rows_make_for_test(-5.0, [1.0])
	var bev := {"side": 1, "node": brow.obs[0], "outline": brow.outlines[0]}
	DebugFlags.parse(["nofx=sparks,streaks,popup,flash,trail,haptic"])
	var seen_bonus := []
	for i in 12:
		main._on_near_miss(bev)
		seen_bonus.append(main.bonus)
	var rising := true
	for i in range(1, seen_bonus.size()):
		rising = rising and seen_bonus[i] >= seen_bonus[i - 1]
	check(rising and main.bonus == 3.0 and main.streak <= tuning.streak_at_cap() + 0.0001, "twelve close calls rise and stop at the cap; the streak is held at the cap's streak (%.1f)" % main.streak)
	check(main.hud._bonus_label.text == "x3.0 POINTS  MAX" and main.hud._bonus_label.get_theme_color("font_color").is_equal_approx(tuning.bonus_gold),
			"at the cap the label is gold and says MAX (\"%s\")" % main.hud._bonus_label.text)
	# popup tiers keyed to bonus thresholds, with the bonus in the text
	check(tuning.popup_tier(1.8) == 0 and tuning.popup_tier(2.0) == 1 and tuning.popup_tier(2.79) == 1 and tuning.popup_tier(2.8) == 2 and tuning.popup_tier(50.0) == 2,
			"popup tiers: Close call below x2.0, Closer to x2.8, Whisker close above")
	check((tuning.near_miss_texts[1] % 2.4) == "Closer!\nx2.4 points", "popups show the bonus with one decimal")
	# gradual decay: holds, then eases down smoothly to x1, and the label goes away
	var hold: float = tuning.bonus_hold_time
	var t_el := 0.0
	var b_prev: float = main.bonus
	var held := true
	var smooth := true
	var monotone := true
	var drop_start := -1.0
	while main.streak > 0.0 and t_el < 60.0:
		main._decay_bonus(0.05)
		t_el += 0.05
		if main.bonus < b_prev - 0.0001 and drop_start < 0.0:
			drop_start = t_el
		if main.bonus > b_prev + 0.0001:
			monotone = false
		if t_el < hold - 0.06 and main.bonus < 3.0:
			held = false
		if b_prev - main.bonus > 0.2:
			smooth = false
		b_prev = main.bonus
	check(held and monotone and smooth and drop_start >= hold - 0.1, "the bonus holds %.1f s, then eases down smoothly (first drop at %.2f s)" % [hold, drop_start])
	check(main.bonus == 1.0 and main.streak == 0.0 and t_el < 30.0, "...and reaches x1 after %.1f s" % t_el)
	await real_wait(tuning.bonus_hold_time * 0 + 0.7)
	check(main.hud._bonus_label.text == "", "the label shrinks away at x1")
	# a crash / the end of a run resets the streak
	main._on_near_miss(bev)
	main._on_near_miss(bev)
	main._end_run(main.HEADER_CRASH, main.REASON_OBSTACLE)
	check(main.bonus == 1.0 and main.streak == 0.0 and main.hud._bonus_label.text == "", "a crash resets the streak and bonus")
	main.restart()
	main.set_process(false)
	# high caps: the maths and the looks stay sane (the cap will be raised by upgrades)
	tuning.bonus_scale = 3.0
	tuning.bonus_cap = 1000.0
	var okv := true
	for b in [1.0, 1.05, 2.0, 6.0, 50.0, 999.0, 1000.0]:
		var c: Color = tuning.bonus_color(b)
		okv = okv and c.r >= 0.0 and c.r <= 1.0 and c.g >= 0.0 and c.g <= 1.0 and c.b >= 0.0 and c.b <= 1.0 and tuning.bonus_swell(b) <= tuning.bonus_swell(tuning.bonus_visual_max) + 0.0001
	check(okv and tuning.at_cap(1000.0) and not tuning.at_cap(999.0), "colours and score swell are clamped visually for a cap of 1000")
	main._reset_bonus()
	for i in 40:
		main._on_near_miss(bev)
	main.hud.set_score(12345, main.bonus)
	main.hud._update_bonus_look(Time.get_ticks_msec())
	check(main.bonus < 1000.0 and main.bonus > 6.0 and main.hud._score.scale.x <= tuning.bonus_swell(tuning.bonus_visual_max) + 0.11,
			"a long streak with a huge cap: x%.1f, score scale %.2f stays bounded" % [main.bonus, main.hud._score.scale.x])
	main.hud.set_bonus(1000.0, main.hud.BONUS_PUNCH)
	check(main.hud._bonus_label.text == "x1000.0 POINTS  MAX", "the label copes with a four-digit bonus (\"%s\")" % main.hud._bonus_label.text)
	main._reset_bonus()
	main.hud.clear_bonus()
	DebugFlags.parse([])
	sp._release_row(brow)
	tuning.bonus_scale = bsaved["scale"]
	tuning.bonus_cap = bsaved["cap"]

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
	main._reset_bonus()
	for e in main.fx._emitters:
		e.emitting = false
		e.visible = false
	var row = sp._rows_make_for_test(-5.0, [1.0])
	main._on_near_miss({"side": 1, "node": row.obs[0], "outline": row.outlines[0]})
	check(main.bonus > 1.5, "bonus still rises with every effect off")
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

	print("6. players (no ?tune) get no panel")
	DebugFlags.parse([])
	var plain: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(plain)
	await process_frame
	await process_frame
	check(plain.tune_panel == null, "without ?tune there is no tuning panel at all")
	plain.queue_free()

	print("")
	if failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		print("SMOKE TEST FAILED: %d check(s)" % failures.size())
		quit(1)
