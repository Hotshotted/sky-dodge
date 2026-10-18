extends SceneTree
## Plays every Countryside pattern (mirrored and not, at the low, middle and high end of its speed band, on a short and
## a tall screen) with the real Kit and prints which ones can not be flown. Run: godot --headless --script tests/pattern_check.gd
## The smoke test does the same and fails on any miss; this prints the details while patterns are being built.

func _initialize() -> void:
	var P = load("res://scripts/Patterns.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var kit = main.spawner.kit
	var carriers: Array = []
	for i in 8:
		var n := Node3D.new()
		root.add_child(n)
		carriers.append(n)
	var caps: PackedFloat32Array = P.simple_caps(main.player.hit_capsules())
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
	var tn: Node = root.get_node("/root/Tuning")
	var x_lim: float = tn.ortho_size * 0.5 - tn.plane_edge_margin
	if "sweep" in OS.get_cmdline_user_args():   # -- sweep only=<name> : which windmill phases pass at the stepped speeds
		var base: Dictionary = P.find(only)
		var steps_v: Array[float] = [7.0, 10.2, 13.4, 16.6, 19.8, 23.0, 26.0]
		var ph := 0.0
		while ph < TAU:
			var cand: Dictionary = base.duplicate(true)
			for it in cand["items"]:
				if it["t"] == "windmill":
					it["phase"] = ph + float(it.get("phase_off", 0.0))
			var line2 := ""
			for sv in steps_v:
				var ok2 := true
				for mir in [false, true]:
					for cfg in [[-9.1, 7.6], [-10.4, 8.9], [-9.1, 2.0], [-10.4, 2.4]]:
						if not P.check(kit, cand, mir, sv, cfg[1], cfg[0], caps, x_lim, carriers)["ok"]:
							ok2 = false
				line2 += "#" if ok2 else "."
			print("phase %.1f  %s  (speeds 7 10.2 13.4 16.6 19.8 23 26)" % [ph, line2])
			ph += 0.3
		quit(0)
		return
	if "map" in OS.get_cmdline_user_args():   # -- map : pass (#) / fail (.) at every speed 7 .. 26
		for pat in P.all():
			if only != "" and pat["name"] != only:
				continue
			var line := ""
			var sp3 := 7.0
			while sp3 <= 26.0:
				var okk := true
				for mir in [false, true]:
					for cfg in [[-9.1, 7.6], [-10.4, 8.9], [-9.1, 2.0], [-10.4, 2.4]]:
						if not P.check(kit, pat, mir, sp3, cfg[1], cfg[0], caps, x_lim, carriers)["ok"]:
							okk = false
				line += "#" if okk else "."
				sp3 += 1.0
			print("%-20s %s  (7..26; declared %.0f..%.0f)" % [pat["name"], line, pat["speed"][0], pat["speed"][1]])
		quit(0)
		return
	if "scan" in OS.get_cmdline_user_args():   # ./pattern_check.gd -- scan : how fast can each pattern be flown
		for pat in P.all():
			if only != "" and pat["name"] != only:
				continue
			var top := 0.0
			var sp2 := 7.0
			while sp2 <= 26.0:
				var allok := true
				for mir in [false, true]:
					for cfg in [[-9.1, 7.6], [-10.4, 8.9], [-9.1, 2.0], [-10.4, 2.4]]:
						if not P.check(kit, pat, mir, sp2, cfg[1], cfg[0], caps, x_lim, carriers)["ok"]:
							allok = false
				if not allok:
					break
				top = sp2
				sp2 += 1.0
			print("%-20s flyable at 7 .. %.0f (declared %.0f .. %.0f)" % [pat["name"], top, pat["speed"][0], pat["speed"][1]])
		quit(0)
		return
	var bad := 0
	var t0 := Time.get_ticks_msec()
	for pat in P.all():
		if only != "" and pat["name"] != only:
			continue
		var fails: Array[String] = []
		var lo: float = pat["speed"][0]
		var hi: float = pat["speed"][1]
		var speeds: Array[float] = [lo, (lo + hi) * 0.5, hi]
		for mir in [false, true]:
			for sp in speeds:
				for cfg in [[-9.1, 7.6], [-10.4, 8.9], [-9.1, 2.0], [-10.4, 2.4]]:
					var r: Dictionary = P.check(kit, pat, mir, sp, cfg[1], cfg[0], caps, x_lim, carriers)
					if not r["ok"]:
						fails.append("%s v=%.0f cfg=%s: %s" % ["mirror" if mir else "plain", sp, str(cfg), r["why"]])
		print("%-20s d%d %s" % [pat["name"], pat["diff"], "OK" if fails.is_empty() else "FAIL x%d" % fails.size()])
		for f in fails.slice(0, 4):
			print("      ", f)
		bad += int(not fails.is_empty())
	print("%d pattern(s) not flyable; %d ms" % [bad, Time.get_ticks_msec() - t0])
	quit(1 if bad > 0 else 0)
