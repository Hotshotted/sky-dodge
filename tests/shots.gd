extends SceneTree
## Screenshot harness (needs a display, e.g. xvfb + software GL):
##   xvfb-run -a -s "-screen 0 540x1200x24" godot --rendering-driver opengl3 --resolution 540x1200 --script res://tests/shots.gd -- out=/tmp/shots
## Starts a run, spawns one of each Countryside kit thing in front of the plane at several times of day, saves PNGs.

var out := "/tmp/shots"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	while main._warming:
		await process_frame
	await _frames(5)
	var names := ["meadow_weave", "farm_lane", "windmill_meadow", "balloon_meadow", "powerline_gate", "crow_ambush"]
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
	DebugFlags.god = true
	var tn: Node = root.get_node("/root/Tuning")
	tn.first_pick_min_seconds = 9999.0
	tn.first_pick_max_seconds = 10000.0
	for n in names:
		if only != "" and n != only:
			continue
		DebugFlags.pattern = n
		main.restart()
		main.elapsed = 100.0   # (past the gentle first minute)
		await _seconds(4.0)
		var k := 0
		for tod in [0.0, 0.35, 0.7, 1.0]:
			main.tod_override = tod
			main._apply_time_of_day(tod)
			await _seconds(0.8)
			_shot("%s_%d" % [n, k])
			k += 1
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
