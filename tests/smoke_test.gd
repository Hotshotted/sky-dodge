extends SceneTree
## Headless smoke test:  godot --headless --path . --script res://tests/smoke_test.gd
## Exits with code 1 if anything below fails (CI runs this before exporting).
##   1. the game boots and the start-up pre-warm finishes
##   2. a crash shows the game-over UI: "CRASHED", the end reason and the final score
##   3. tapping restarts the run (fresh scene, game-over UI hidden, score reset)
##   4. the same crash/restart cycle works a second time
##   5. a near miss runs all the pooled effects without errors and raises the multiplier
##   6. the start-up pre-warm really draws every effect on screen behind the splash, then cleans up
##   7. ?debug flags parse, and switching an effect off really skips it
##   8. plane collision capsules: span matches the wings, rounded corners graze past a cube corner
##   9. closest-approach near-miss detection reports the right side

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures.append(what)

func real_wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		await process_frame

func start_game() -> Node:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # so reload_current_scene() (tap to restart) has a scene to reload
	return main

func _initialize() -> void:
	var tuning := root.get_node("Tuning")
	tuning.blocked_columns_min = 4   # crowded rows: easy to crash on purpose
	tuning.blocked_columns_max = 4

	DebugFlags.parse([])   # no debug flags
	print("1. boot (and the visible pre-warm, section 6)")
	var main := start_game()
	await process_frame
	await process_frame
	await process_frame
	check(main._warming, "pre-warm is running at boot")
	check(is_instance_valid(main.hud._splash), "splash screen is shown during the pre-warm")
	var emitting := 0
	for e in main.fx._emitters:
		if e.emitting:
			emitting += 1
	check(emitting == main.fx.SPARK_EMITTERS, "both spark emitters are drawing during the pre-warm (%d)" % emitting)
	var streaks_vis := 0
	for n in main.fx._streak_nodes:
		if n.visible:
			streaks_vis += 1
	check(streaks_vis == main.fx.STREAK_POOL, "every pooled streak is visible during the pre-warm (%d)" % streaks_vis)
	check(main.trail._pts.size() >= 60 and main.trail._alpha > 0.0, "full-length trail ribbon is drawing during the pre-warm (%d points)" % main.trail._pts.size())
	var pops := 0
	for l in main.hud._pop_labels:
		if l.visible:
			pops += 1
	check(pops == main.hud.POPUP_POOL, "every pooled popup label is visible during the pre-warm (%d)" % pops)
	check(main.hud._over.visible, "game-over text is drawn during the pre-warm (font glyphs)")
	await real_wait(0.6)
	check(not main._warming, "pre-warm finished")
	check(not is_instance_valid(main.hud._splash) or main.hud._splash.is_queued_for_deletion(), "splash removed afterwards")
	check(main.hud._mult.text == "x1" and not main.hud._over.visible, "HUD back to normal (x1, no game-over text)")
	emitting = 0
	for e in main.fx._emitters:
		if e.emitting:
			emitting += 1
	var left_vis := 0
	for n in main.fx._streak_nodes:
		if n.visible:
			left_vis += 1
	var emitters_shown := 0
	for e in main.fx._emitters:
		if e.visible:
			emitters_shown += 1
	check(emitting == 0 and left_vis == 0 and main.trail._pts.is_empty() and emitters_shown == 0, "no pre-warm effects left behind (incl. already-spawned sparks)")
	check(main.alive, "run starts alive")
	check(not main._warming, "start-up pre-warm finished")

	for round in [1, 2]:
		print("%d. crash -> game-over UI -> tap restart (round %d)" % [round + 1, round])
		var hud: Node = main.hud
		check(not hud._over.visible, "game-over UI hidden while playing")
		force_crash(main)
		await real_wait(0.2)
		check(not main.alive, "crash ends the run")
		check(hud._over.visible, "game-over UI is visible after a crash")
		var shown: String = hud._over.text
		check(shown.contains("CRASHED") and shown.contains("Score: %d" % int(main.score)), "game-over text says CRASHED  (\"%s\")" % shown.replace("\n", " | "))
		check(shown.contains("Hit an obstacle"), "game-over text gives the end reason")
		check(shown.contains(str(int(main.score))), "game-over text shows the final score (%d)" % int(main.score))
		await real_wait(0.6)   # Main ignores taps for 0.5 s after a crash
		var old := main
		tap()
		await real_wait(0.4)
		main = current_scene
		check(main != old and is_instance_valid(main), "tap restarted the run (new scene instance)")
		check(main.alive and main.score < 100.0, "restarted run is alive and the score was reset (%d)" % int(main.score))
		check(not main.hud._over.visible, "game-over UI hidden after restart")

	print("5. near miss effects")
	tuning.blocked_columns_min = 1
	tuning.blocked_columns_max = 1
	var sp: Node = main.spawner
	sp._spawn_row(-5.0)
	var row: Node = sp._rows[-1]
	main._on_near_miss({"side": 1, "node": row.obs[0], "outline": row.outlines[0]})
	await real_wait(0.1)
	check(main.multiplier == 2, "near miss raises the multiplier to 2")
	check(main.hud._mult.text == "x2", "multiplier HUD shows x2")
	var popups := 0
	for l in main.hud._pop_labels:
		if l.visible:
			popups += 1
	check(popups == 1, "one popup is showing")
	var sparks_on := 0
	for e in main.fx._emitters:
		if e.visible and e.emitting:
			sparks_on += 1
	check(sparks_on == 1, "a near miss shows exactly one spark burst (emitter visible + emitting)")

	main.set_process(false)   # freeze the game loop: no real obstacles or near misses while sections 7-9 poke at things
	print("7. debug flags")
	DebugFlags.parse(["nofx=sparks,bogus", "noprewarm", "perf", "v=abc1234"])
	check(DebugFlags.off("sparks") and not DebugFlags.off("streaks"), "nofx=sparks switches off only sparks")
	check(DebugFlags.noprewarm and DebugFlags.perf, "noprewarm and perf are read")
	check(DebugFlags.summary() == "nofx=sparks noprewarm perf ?bogus", "summary shown by the stamp: \"%s\"" % DebugFlags.summary())
	DebugFlags.parse(["nofx=all"])
	check(DebugFlags.EFFECTS.all(func(e): return DebugFlags.off(e)), "nofx=all switches every effect off")
	check(DebugFlags.summary() == "nofx=" + ",".join(DebugFlags.EFFECTS), "summary lists them all")
	DebugFlags.parse(["nofx=Sparks%2CPopup"])   # URL-encoded comma, upper case
	check(DebugFlags.off("sparks") and DebugFlags.off("popup") and not DebugFlags.off("flash"), "names are case-insensitive and URL-decoded")
	# gating really skips the effect (first let the previous near miss's popup / streaks / flash expire)
	await real_wait(1.2)
	DebugFlags.parse(["nofx=sparks,streaks,popup,flash,trail,haptic"])
	main.multiplier = 1
	var outline_before: Color = row.outlines[0].get_shader_parameter("outline_color")
	for e in main.fx._emitters:
		e.emitting = false
	main._on_near_miss({"side": 1, "node": row.obs[0], "outline": row.outlines[0]})
	var any_emit := false
	for e in main.fx._emitters:
		if e.emitting:
			any_emit = true
	var any_streak := false
	for n in main.fx._streak_nodes:
		if n.visible:
			any_streak = true
	var any_pop := false
	for l in main.hud._pop_labels:
		if l.visible:
			any_pop = true
	check(main.multiplier == 2, "multiplier still rises with every effect off")
	check(not any_emit and not any_streak and not any_pop and sp._flashes.is_empty(),
			"no spark / streak / popup / flash with ?nofx (emit %s, streak %s, popup %s, flashes %d)" % [any_emit, any_streak, any_pop, sp._flashes.size()])
	DebugFlags.parse([])

	print("7b. ?perf near-miss log")
	main.hud._perf_label = Label.new()
	main.hud.add_child(main.hud._perf_label)
	main.hud.note_near_miss(0.4)
	for i in 5:
		main.hud._update_perf(0.07 if i == 2 else 0.02)
	check(main.hud._nm_log.size() == 1 and main.hud._nm_log[0].contains("code 0.4 ms") and main.hud._nm_log[0].contains("worst 70 ms"),
			"perf readout logs handler time and the worst following frame (%s)" % str(main.hud._nm_log))
	main.hud._perf_label.queue_free()
	main.hud._perf_label = null

	print("8. collision capsules")
	var pl: Node = main.player
	var caps: Array[PackedFloat32Array] = pl.hit_capsules()
	var span: float = caps[0][2] + caps[0][4]
	check(absf(span - pl.WING_HALF.x * tuning.plane_hit_scale) < 0.001, "wing capsule spans the visible wings (%.3f half-span)" % span)
	var length: float = caps[1][3] + caps[1][4]
	check(absf(length - (pl.BODY_Z + pl.BODY_HALF.y * tuning.plane_hit_scale)) < 0.001, "fuselage capsule reaches the visible tail (%.3f)" % length)
	var half: Vector2 = sp._obstacle_half()
	var wing_tip: float = caps[0][2] + caps[0][4]
	var p0 := Vector2(0.0, 0.0)
	# straight-on: wing tip 0.05 clear of an obstacle's visible edge survives, 0.02 inside crashes
	sp._rows.clear()
	var test_row = sp._rows_make_for_test(0.0, [wing_tip + half.x + 0.05])
	check(not sp.hits(p0, caps), "wingtip 0.05 clear of a cube survives")
	test_row.xs[0] = wing_tip + half.x - 0.02
	check(sp.hits(p0, caps), "wingtip 0.02 inside a cube crashes")
	# corner graze: a cube corner 0.05 inside the OLD box corner, but outside the rounded capsule
	var cx: float = (caps[0][2] + caps[0][4]) - 0.05
	var cz: float = caps[0][3] + (pl.WING_HALF.y * tuning.plane_hit_scale) - 0.05
	test_row.xs[0] = cx + half.x
	test_row.position.z = cz + half.y
	var box_would_hit: bool = cx < wing_tip and cz < pl.WING_Z + pl.WING_HALF.y * tuning.plane_hit_scale
	check(box_would_hit, "(sanity) a box-shaped hitbox would have crashed on that corner graze")
	check(not sp.hits(p0, caps), "rounded wingtip survives a cube-corner graze")
	sp._rows.clear()

	print("9. near-miss closest approach")
	var near_row = sp._rows_make_for_test(-4.0, [wing_tip + half.x + 0.3])   # passes 0.3 clear on the right
	var found: Array[Dictionary] = []
	var z := -4.0
	while z < 6.0:
		near_row.position.z = z
		found.append_array(sp.update_near_misses(p0, caps))
		z += 0.1
	check(found.size() == 1 and found[0]["side"] == 1, "a pass 0.3 clear on the right gives one near miss on the right")
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

## Put the plane right inside an obstacle.
func force_crash(main: Node) -> void:
	var sp: Node = main.spawner
	var pl: Node = main.player
	sp._spawn_row(pl.position.z)
	var row: Node = sp._rows[-1]
	pl.position.x = row.xs[0]
	main.score = 1234.0   # a known score to look for in the game-over text

func tap() -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = true
	Input.parse_input_event(ev)
