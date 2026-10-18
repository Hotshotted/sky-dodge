extends SceneTree
## Headless profile of a long Countryside run: god mode, a plane that swings across the lane, every pattern cycling
## (?pattern=cycle), picks taken at once. Each frame is main._process(1/60) timed on its own. Prints the worst frames, what
## was happening in them, and where the time went. Run: godot --headless --script tests/profile_run.gd -- seconds=300
## (Headless has no GPU, so this is the script side of a frame: the part GDScript is responsible for.)

func _initialize() -> void:
	var seconds := 300.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seconds="):
			seconds = float(a.substr(8))
	var save: Node = root.get_node("Save")
	save.path = "user://profile_save.json"
	save.reset_all()
	DebugFlags.parse(["pattern=cycle"])
	DebugFlags.god = true
	DebugFlags.profile = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main.set_process(false)
	for i in 3:
		await process_frame
	var guard := 0
	while main._warming and guard < 300:
		await create_timer(0.1).timeout
		guard += 1
	main.set_process(false)
	await process_frame
	main.hud.play_pressed.emit()
	main.set_process(false)
	var sp = main.spawner
	var frames := int(seconds * 60.0)
	var times := PackedFloat32Array()
	times.resize(frames)
	var notes: Array[String] = []
	notes.resize(frames)
	var last_pat := ""
	var last_phase := -1
	var last_steps := 0
	var last_nm := 0
	var t_all := Time.get_ticks_usec()
	for f in frames:
		var t := f / 60.0
		main.player.position.x = 3.6 * sin(t * 0.9)
		main.player.prev_xz = Vector2(main.player.position.x, main.player.position.z)
		main.fuel = root.get_node("Tuning").fuel_max()
		var tags: Array[String] = []
		if main._picking:
			main._on_pick_chosen(0)
			tags.append("pick chosen")
		var t0 := Time.get_ticks_usec()
		main._process(1.0 / 60.0)
		times[f] = (Time.get_ticks_usec() - t0) / 1000.0
		var th := Time.get_ticks_usec()   # god mode skips the crash test: time it by hand so its cost is counted
		sp.hits(Vector2(main.player.position.x, main.player.position.z), main.player.hit_capsules())
		var dth := Time.get_ticks_usec() - th
		if not main.prof.has("collision: hits (timed by hand)"):
			main.prof["collision: hits (timed by hand)"] = [0, 0, 0]
		var hrec: Array = main.prof["collision: hits (timed by hand)"]
		hrec[0] += dth
		hrec[1] = maxi(hrec[1], dth)
		hrec[2] += 1
		if sp.pattern_name != last_pat:
			last_pat = sp.pattern_name
			tags.append("new pattern " + last_pat)
		if sp.wave_phase != last_phase:
			last_phase = sp.wave_phase
			tags.append("wave " + sp.wave_name())
		if sp.speed_steps != last_steps:
			last_steps = sp.speed_steps
			tags.append("speed step")
		if sp.rows_spawned > 0:
			tags.append("%d row(s) spawned" % sp.rows_spawned)
		if main._picking:
			tags.append("pick screen opened")
		if not main.alive:
			main.hud.play_pressed.emit()
			main.set_process(false)
			tags.append("restarted (crash)")
		notes[f] = ", ".join(tags)
	var total_s := (Time.get_ticks_usec() - t_all) / 1e6
	var sorted_ix: Array = range(frames)
	sorted_ix.sort_custom(func(a, b): return times[a] > times[b])
	var sum := 0.0
	for x in times:
		sum += x
	var avg := sum / frames
	var over: Array[float] = []
	for x in times:
		if x > 2.0 * avg + 1.0:
			over.append(x)
	print("PROFILE: %d frames (%.0f game seconds, %.1f s of wall time), average %.3f ms, speed steps %d, patterns seen cycling" % [frames, seconds, total_s, avg, sp.speed_steps])
	print("worst 12 frames:")
	for k in 12:
		var i: int = sorted_ix[k]
		print("  frame %5d (t=%6.1f s)  %6.2f ms   %s" % [i, i / 60.0, times[i], notes[i]])
	var p99 := times.duplicate()
	p99.sort()
	print("percentiles: 50%% %.3f  90%% %.3f  99%% %.3f  99.9%% %.3f  max %.3f ms" % [p99[frames / 2], p99[int(frames * 0.9)], p99[int(frames * 0.99)], p99[int(frames * 0.999)], p99[frames - 1]])
	print("frames over 2x average + 1 ms: %d" % over.size())
	print("where the time went (all frames):")
	var keys: Array = main.prof.keys()
	keys.sort_custom(func(a, b): return main.prof[a][0] > main.prof[b][0])
	for k in keys:
		var rec: Array = main.prof[k]
		print("  %-46s total %7.1f ms   per call %6.3f ms   worst %6.2f ms   calls %d" % [k, rec[0] / 1000.0, rec[0] / 1000.0 / maxf(rec[2], 1), rec[1] / 1000.0, rec[2]])
	var by_tag := {}
	for k in 40:
		var i2: int = sorted_ix[k]
		for tg in String(notes[i2]).split(", ", false):
			var key := String(tg).split(" ")[0] + " " + (String(tg).split(" ")[1] if String(tg).split(" ").size() > 1 else "")
			by_tag[key] = int(by_tag.get(key, 0)) + 1
	print("what the worst 40 frames had in common: %s" % str(by_tag))
	save.reset_all()
	quit(0)
