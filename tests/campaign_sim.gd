extends SceneTree
## Economy / progression simulation with a real bot (a tuning tool, not part of CI):
##   godot --headless --path . --script res://tests/campaign_sim.gd
## A skilled bot (perfect obstacle pilot) plays run after run on the real game loop, with the real picks and the real Save: after every
## run it spends its coins like a sensible player (cheapest useful upgrade first, a gear slot when it can). Prints each run and the
## moments that matter: the first upgrade, the first gear piece, the first extra gear slot and the Coast unlock.
## Env: SIM_RUNS (max runs, default 40), SIM_MAX (seconds per run), SIM_SEED, SIM_BUILD (bot build, default mixed), SIM_TUNE.

const DT := 1.0 / 30.0
const BUY_ORDER := ["fuel_tank", "efficiency", "refill", "coin_value", "can_bounty", "close_call_pay", "bonus_cap"]
const GEAR_ORDER := ["nine_lives", "reserve_tank", "steady_nerves", "head_start", "magnet", "cloud_eye"]

func tn() -> Node:
	return root.get_node("Tuning")

func _initialize() -> void:
	DebugFlags.parse(["noprewarm"])
	for kv in OS.get_environment("SIM_TUNE").split(",", false):
		var parts := kv.split("=")
		tn().set(parts[0], float(parts[1]))
	var max_runs := int(OS.get_environment("SIM_RUNS")) if OS.get_environment("SIM_RUNS") != "" else 40
	var max_run_s := float(OS.get_environment("SIM_MAX")) if OS.get_environment("SIM_MAX") != "" else 900.0
	seed(int(OS.get_environment("SIM_SEED")) if OS.get_environment("SIM_SEED") != "" else 4242)
	var save: Node = root.get_node("Save")
	save.reset_all()
	var Bots = load("res://tests/bots.gd")
	var bot = Bots.new()
	bot.root = root
	bot.mode = "skilled"
	bot.build = OS.get_environment("SIM_BUILD") if OS.get_environment("SIM_BUILD") != "" else "mixed"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.player.set_process(false)
	var total_play := 0.0
	var first_upgrade := -1.0
	var first_gear := -1.0
	var first_slot := -1.0
	var coast := -1.0
	var first_upgrade_run := 0
	var first_gear_run := 0
	var first_slot_run := 0
	var coast_run := 0
	var best_m := 0.0
	print("run |  time | total |     m |   coins earned | balance after buying | bought")
	for run in max_runs:
		save.select_map(0)
		main.restart()
		main.set_process(false)
		main.spawner.obstacles_solid = false
		bot.start(main)
		var t := 0.0
		while main.alive and t < max_run_s:
			bot.drive(main, t)
			main._process(DT)
			t += DT
			if main._picking:
				main._on_pick_chosen(bot.choose_card(main))
		if main.alive:
			main._end_run(main.HEADER_CRASH, "ran out of patience")
		total_play += t
		var meters: float = tn().meters(main.run_distance)
		best_m = maxf(best_m, meters)
		var earned: float = main.last_earned
		var bought: Array[String] = []
		var spent_any := true
		while spent_any:
			spent_any = false
			if save.next_slot_cost() >= 0.0 and save.coins >= save.next_slot_cost() and save.slots < 2 + int(total_play / 600.0):
				if save.buy_slot():
					bought.append("slot")
					if first_slot < 0.0:
						first_slot = total_play
						first_slot_run = run + 1
					spent_any = true
					continue
			for id in GEAR_ORDER:
				if save.level(id) == 0 and save.can_buy(id):
					save.buy(id)
					bought.append(id)
					if first_gear < 0.0:
						first_gear = total_play
						first_gear_run = run + 1
					spent_any = true
					break
			if spent_any:
				continue
			var cheapest := ""
			var cost := INF
			for id in BUY_ORDER:
				if save.can_buy(id) and save.cost_of_next(id) < cost:
					cost = save.cost_of_next(id)
					cheapest = id
			if cheapest != "":
				save.buy(cheapest)
				bought.append(cheapest)
				if first_upgrade < 0.0:
					first_upgrade = total_play
					first_upgrade_run = run + 1
				spent_any = true
		if coast < 0.0 and save.map_unlocked(1):
			coast = total_play
			coast_run = run + 1
		print("%3d | %4.0f s | %4.1f min | %5.0f | %14.0f | %20.0f | %s | %s" % [run + 1, t, total_play / 60.0, meters, earned, save.coins, ", ".join(bought), main.hud._over.text.split("\n")[1] if main.hud._over.text.contains("\n") else ""])
		if coast >= 0.0 and run >= coast_run + 2:
			break
	print("")
	print("first upgrade bought: run %d, after %.1f min of play" % [first_upgrade_run, first_upgrade / 60.0])
	print("first gear piece: run %d, after %.1f min" % [first_gear_run, first_gear / 60.0])
	print("first extra gear slot: run %d, after %.1f min" % [first_slot_run, first_slot / 60.0])
	print("Coast unlock (%.0f m): run %d, after %.1f min (best distance so far %.0f m)" % [tn().map_def(1)["unlock_meters"], coast_run, coast / 60.0, best_m])
	save.reset_all()
	quit()
