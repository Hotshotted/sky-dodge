extends SceneTree
## Balance simulation with the test bots (a tuning tool, not part of CI):
##   godot --headless --path . --script res://tests/threat_sim.gd
## Plays the real game loop at 30 fps. A SPEC is "mode:build:upgrades[:solid]":
##   mode     skilled | lazy | afk            (see tests/bots.gd)
##   build    none | guns | utility | mixed | single:<perk id> (takes only that perk when offered) | only:<perk id> (that perk at level 3 from the start) | full (every active perk at level 3 from the start, no picks)
##   upgrades none | mid | max                (permanent upgrades)
##   solid    obstacles hurt (default: a perfect obstacle pilot, so the hunters and the fuel are what is measured)
## Env: SIM_SPECS="spec,spec,...", SIM_RUNS, SIM_MAX (seconds), SIM_SEED, SIM_TRACE=1 (the first run's timeline), SIM_TUNE="key=val,...".
## Prints survival (min / median / max), hits, kills, cans, distance, coins and what ended the runs.

const DT := 1.0 / 30.0
var max_seconds := 720.0
var runs := 5
const ACTIVES := ["flak", "pods", "tail", "wingman", "shockwave", "banner", "skywriter", "magnet_field", "roll"]

func tn() -> Node:
	return root.get_node("Tuning")

func simulate(spec: String, seed_value: int, trace: bool) -> Dictionary:
	var parts := spec.split(":")
	var mode := parts[0]
	var build := parts[1] if parts.size() > 1 else "none"
	if (build == "single" or build == "only") and parts.size() > 2:
		build = build + ":" + parts[2]
		parts.remove_at(2)
	var upgrades := parts[2] if parts.size() > 2 else "none"
	var solid := parts.size() > 3 and parts[3] == "solid"
	seed(seed_value)
	var Bots = load("res://tests/bots.gd")
	var bot = Bots.new()
	bot.root = root
	bot.mode = mode
	bot.build = "mixed" if build == "full" else build
	var save: Node = root.get_node("Save")
	Bots.apply_upgrades(save, tn(), upgrades)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.player.set_process(false)
	main.restart()
	main.spawner.obstacles_solid = solid
	bot.start(main)
	if build.begins_with("only:"):   # one perk at level 3 from the start, no picks
		main.picks.enabled = false
		main.picks.next_pick = INF
		main.picks.set_perk(build.substr(5), 3)
		tn().boss_rare_pick = false
		bot.build = "none"
	if build == "full":
		tn().boss_rare_pick = false
		main.picks.enabled = false
		main.picks.next_pick = INF
		for id in ACTIVES:
			main.picks.set_perk(id, 3)
		for id in ["fuel_miser", "hot_streak", "lucky_whiskers", "scavenger"]:
			main.picks.set_perk(id, 3)
	var th = main.spawner.threats
	var t := 0.0
	var pick_log: Array = []
	while main.alive and t < max_seconds:
		bot.drive(main, t)
		main._process(DT)
		t += DT
		if main._picking:
			var idx: int = bot.choose_card(main)
			if trace:
				pick_log.append([snappedf(main.elapsed, 0.1), "PICK: " + String(main._pick_cards[idx]["name"]) + (" L%d" % main._pick_cards[idx]["level"] if main._pick_cards[idx]["kind"] == "perk" else "") + ("  (RARE)" if main._pick_rare else "")])
			main._on_pick_chosen(idx)
	var reason: String = "survived %ds" % int(max_seconds) if main.alive else String(main.hud._over.text.split("\n")[1] if main.hud._over.text.contains("\n") else main.hud._over.text)
	var res := {"t": t, "hits": main.hits_taken, "kills": th.kills, "shots": th.shots, "wing": main.gadgets.wingman_hits, "bosses": th.bosses_done,
			"cans": main.run_cans, "reason": reason, "last": main.last_hit_name, "score": main.score, "meters": tn().meters(main.run_distance),
			"timeline": th.timeline.duplicate(), "picks": pick_log, "snipes": main.spawner.snipes, "kill_coins": main.threat_coins, "boss_coins": main.boss_coins, "bonus": main.bonus}
	main.queue_free()
	await process_frame
	return res

func median(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])

func _initialize() -> void:
	DebugFlags.parse(["noprewarm"])
	for kv in OS.get_environment("SIM_TUNE").split(",", false):
		var parts := kv.split("=")
		tn().set(parts[0], float(parts[1]))
	if OS.get_environment("SIM_RUNS") != "":
		runs = int(OS.get_environment("SIM_RUNS"))
	if OS.get_environment("SIM_MAX") != "":
		max_seconds = float(OS.get_environment("SIM_MAX"))
	var seed_base := int(OS.get_environment("SIM_SEED")) if OS.get_environment("SIM_SEED") != "" else 2000
	var specs: PackedStringArray = OS.get_environment("SIM_SPECS").split(",", false) if OS.get_environment("SIM_SPECS") != "" else PackedStringArray(["skilled:none:none", "skilled:single:flak:none", "skilled:mixed:none", "skilled:full:none", "skilled:mixed:mid", "lazy:full:max", "afk:full:max"])
	for spec in specs:
		var times: Array = []
		var hits := 0
		var kills := 0
		var cans := 0
		var coins := 0.0
		var metersum := 0.0
		var reasons := {}
		for i in runs:
			var r: Dictionary = await simulate(spec, seed_base + i, i == 0 and OS.get_environment("SIM_TRACE") != "")
			times.append(r["t"])
			hits += r["hits"]
			kills += r["kills"]
			cans += r["cans"]
			coins += r["score"]
			metersum += r["meters"]
			var why: String = r["last"] if r["last"] != "" else r["reason"]
			reasons[why] = int(reasons.get(why, 0)) + 1
			print("  %s seed %d: %.0f s, %.0f m, cans %d, hits %d, kills %d, coins %.0f, snipes %d (kill coins %.0f, boss coins %.0f), ended: %s | %s" % [spec, seed_base + i, r["t"], r["meters"], r["cans"], r["hits"], r["kills"], r["score"], r["snipes"], r["kill_coins"], r["boss_coins"], r["reason"], r["last"]])
			if i == 0 and OS.get_environment("SIM_TRACE") != "":
				var merged: Array = r["timeline"] + r["picks"]
				merged.sort_custom(func(a, b): return a[0] < b[0])
				for e in merged:
					print("      %5.1f s  %s" % [e[0], e[1]])
		print("%-28s survival s: min %.0f  median %.0f  max %.0f | hits %.1f  kills %.1f  cans %.1f | %.0f m | coins %.0f" % [spec, times.min(), median(times), times.max(), float(hits) / runs, float(kills) / runs, float(cans) / runs, metersum / runs, coins / runs])
		print("       ended by %s" % str(reasons))
	root.get_node("Save").reset_all()
	quit()
