extends SceneTree
## Screenshots of the active gear (needs a display):
##   xvfb-run -a -s "-screen 0 540x1200x24" godot --rendering-driver opengl3 --resolution 540x1200 --script res://tests/gear_shots.gd -- out=docs/screens/gear
var out := "/tmp/gear_shots"
var main: Node

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var save: Node = root.get_node("Save")
	save.path = "user://gear_shots_save.json"
	save.reset_all()
	save.unlock_all_milestones()
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
	await _seconds(2.5)
	for lvl in [1, 3]:
		for id in ["wingman", "shockwave", "banner", "skywriter", "magnet_field", "roll", "flak", "pods", "tail"]:
			main.picks.set_perk(id, lvl)
		main.gadgets._wash_cd = 0.0
		await _seconds(2.2)
		_shot("gear_level_%d" % lvl)
		await _seconds(0.9)
		_shot("gear_level_%d_b" % lvl)
	main.picks.enabled = true
	main._begin_pick(false)
	await _seconds(1.2)
	_shot("pick_with_build")
	main._on_pick_chosen(0)
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
