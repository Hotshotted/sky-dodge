extends SceneTree
## Headless smoke test:  godot --headless --path . --script res://tests/smoke_test.gd
## Exits with code 1 if anything below fails (CI runs this before exporting).
##   1. the game boots and the start-up pre-warm finishes
##   2. a crash shows the game-over UI: "CRASHED", the end reason and the final score
##   3. tapping restarts the run (fresh scene, game-over UI hidden, score reset)
##   4. the same crash/restart cycle works a second time
##   5. a near miss runs all the pooled effects without errors and raises the multiplier

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

	print("1. boot")
	var main := start_game()
	await real_wait(0.5)
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
