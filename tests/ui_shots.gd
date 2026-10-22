extends SceneTree
## UI screenshot harness (needs a display, e.g. xvfb + software GL):
##   xvfb-run -a -s "-screen 0 540x1200x24" godot --rendering-driver opengl3 --resolution 540x1200 --script res://tests/ui_shots.gd -- out=docs/screens/after
## Walks every screen (start, Hangar tabs, Logbook, a run, the pick screen, the results, the pause menu when there is one) and saves PNGs.

var out := "/tmp/ui_shots"
var main: Node

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var save: Node = root.get_node("Save")
	save.path = "user://ui_shots_save.json"
	save.reset_all()
	save.coins = 4200.0
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	while main._warming:
		await process_frame
	save.coins = 4200.0
	save.changed.emit()
	await _seconds(1.5)
	_shot("01_start")
	main._open_hangar()
	await _seconds(0.8)
	for tab in ["earnings", "plane", "gear"]:
		main.hud._select_tab(tab)
		await _seconds(0.8)
		_shot("02_hangar_" + tab)
	main._show_menu()
	await _seconds(0.5)
	main._open_logbook()
	await _seconds(0.8)
	_shot("03_logbook")
	main._show_menu()
	await _seconds(0.5)
	main.hud.play_pressed.emit()
	DebugFlags.god = true
	var tn: Node = root.get_node("Tuning")
	tn.first_pick_min_seconds = 9999.0
	tn.first_pick_max_seconds = 10000.0
	await _seconds(0.6)
	_shot("04_run_takeoff")
	main.elapsed = 100.0
	main.picks.set_perk("tailwind", 2) if main.picks.has_method("set_perk") else null
	await _seconds(5.0)
	_shot("05_run")
	main.picks.enabled = true
	main._begin_pick()
	await _seconds(1.2)
	_shot("06_pick")
	main._on_pick_chosen(0)
	await _seconds(0.5)
	DebugFlags.god = false
	main.score = 840.0
	main._end_run(main.HEADER_CRASH, main.REASON_OBSTACLE)
	await _seconds(4.5)
	_shot("07_results")
	if main.hud.has_method("show_pause"):
		main._show_menu()
		main.hud.play_pressed.emit()
		await _seconds(1.0)
		main.pause_game()
		await _seconds(1.0)
		_shot("08_pause")
	save.reset_all()
	quit()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _seconds(s: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < s * 1000.0:
		await process_frame

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
