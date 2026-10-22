extends SceneTree
## Screenshots of the hunting threats and bosses (needs a display):
##   xvfb-run -a -s "-screen 0 540x1200x24" godot --rendering-driver opengl3 --resolution 540x1200 --script res://tests/threat_shots.gd -- out=docs/screens/threats
var out := "/tmp/threat_shots"
var main: Node

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var save: Node = root.get_node("Save")
	save.path = "user://threat_shots_save.json"
	save.reset_all()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	while main._warming:
		await process_frame
	main.hud.play_pressed.emit()
	DebugFlags.god = true
	var tn: Node = root.get_node("Tuning")
	tn.first_pick_min_seconds = 9999.0
	tn.first_pick_max_seconds = 10000.0
	await _seconds(2.0)
	main.picks.enabled = true
	main._begin_pick(false)
	await _seconds(1.2)
	_shot("00_first_pick_guns")
	main._on_pick_chosen(0)
	main.picks.enabled = false
	await _seconds(1.0)
	var th = main.spawner.threats
	th._script.clear()
	th._launch(th.HAWK)
	th._launch(th.DRONE)
	await _seconds(1.0)
	_shot("01_hawk_and_drone_warning")
	await _seconds(2.0)
	th.hide_all()
	th._launch(th.GOOSE)
	await _seconds(2.0)
	_shot("02_geese")
	th.hide_all()
	th._launch(th.CROW)
	await _seconds(3.2)
	_shot("03_crows_from_behind")
	th.hide_all()
	th._boss_gap_t = 0.0
	th._start_boss(0, false)
	await _seconds(2.6)
	_shot("04_falcon_banner")
	await _seconds(4.0)
	_shot("05_falcon_bombs")
	th.hide_all()
	th._boss_stage = 0
	th.boss_active = false
	th._boss_gap_t = 0.0
	th._start_boss(1, false)
	await _seconds(7.0)
	_shot("06_thunderhead")
	th.hide_all()
	th._boss_stage = 0
	th.boss_active = false
	th._boss_gap_t = 0.0
	th._start_boss(2, false)
	await _seconds(5.5)
	_shot("07_goose_general")
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
