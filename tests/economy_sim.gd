extends SceneTree
## Economy simulation (a tuning tool, not part of CI):
##   godot --headless --path . --script res://tests/economy_sim.gd
## Plays a player's first ~2 hours as an EXPECTED-VALUE model (no sampling noise): every run's expected
## coins, length and distance come from a small run model, the player then buys upgrades greedily
## (best gain per coin), and their skill improves modestly with practice.
## The run model is calibrated on the real autopilot runs of tests/fuel_balance_sim.gd (drain 6.5/s,
## refill 20, tank 100, no upgrades):
##   SAFE   (flies the widest gap, never chases cans): 15 s, 0.1 cans/run, 9 close calls, 260 coins
##   CHASER (goes for every can it can reach):        25 s median, 3.1 cans, 16 close calls, 504 coins
##   RANDOM:                                          17 s, 0.7 cans, 10 close calls, 299 coins
## "skill" blends those: can-catch rate, close-call rate and crash hazard all move with it.

const OVERHEAD := 12.0      # seconds between runs (game over, tap, restart)
const BUY_TIME := 6.0       # seconds per purchase in the Hangar
const SESSION := 7200.0     # simulate two hours
const DT := 0.5

var T: Node
var S: Node

## Two player types. ENGAGED chases close calls and cans (the model calibrated on the CHASER / SAFE autopilots). PASSIVE
## mostly steers well clear of everything: few close calls (a short, low streak), few cans, fewer crashes.
var passive := false

func skill_at(runs: int) -> float:
	return 0.25 + 0.35 * (1.0 - exp(-runs / 80.0))   # modest improvement: 0.25 -> ~0.6

func catch_rate(s: float) -> float:      # fuel cans collected per second
	return 0.01 + 0.03 * s if passive else 0.01 + 0.115 * s
func close_rate(s: float) -> float:      # close calls per second
	return 0.04 + 0.04 * s if passive else 0.35 + 0.30 * s
func hazard0(s: float) -> float:         # crash hazard per second at start speed
	return (0.03 * (1.0 - s) + 0.004) if passive else (0.045 * (1.0 - s) + 0.005)
func steps_reached(s: float) -> float:   # how long a close-call streak the player typically holds
	return 0.4 + 0.6 * s if passive else 3.0 + 6.0 * s

func speed_at(t: float) -> float:
	return minf(T.base_speed + T.speed_ramp * t, T.max_speed)

func bonus_for(n: float, cap: float) -> float:
	var total := 1.0
	var i := 0
	while float(i + 1) <= n:
		total += T.step_for(i)
		i += 1
	total += (n - float(i)) * T.step_for(i)
	return clampf(total, 1.0, cap)

## level: upgrade id -> level; equipped: gear ids in the loadout. Returns expected run stats.
func evaluate(level: Dictionary, equipped: Array, s: float, target_dist_units: float) -> Dictionary:
	var F: float = T.upgrade_value("fuel_tank", level["fuel_tank"])
	var d: float = T.upgrade_value("efficiency", level["efficiency"])
	var r: float = T.upgrade_value("refill", level["refill"])
	var cap: float = T.upgrade_value("bonus_cap", level["bonus_cap"])
	var coin_mult: float = T.upgrade_value("coin_value", level["coin_value"])
	var bounty: float = T.upgrade_value("can_bounty", level["can_bounty"])
	var ccpay: float = T.upgrade_value("close_call_pay", level["close_call_pay"])
	var lives := 0
	var reserve := 0
	var reach := 0.0
	var eye := false
	var steady := 0.0
	var head := 1.0
	for g in equipped:
		var lv: int = level[g]
		match g:
			"nine_lives": lives = lv
			"reserve_tank": reserve = lv
			"magnet": reach = T.upgrade_value("magnet", lv)
			"cloud_eye": eye = lv > 0
			"steady_nerves": steady = T.upgrade_value("steady_nerves", lv)
			"head_start": head = T.upgrade_value("head_start", lv)
	var lam: float = catch_rate(s) * (1.0 + 0.5 * reach / 3.5 + (0.1 if reach > 0.0 else 0.0))
	var net := d - r * lam
	var fuel_total: float = F * (1.0 + T.reserve_refill_fraction * reserve)
	var t_fuel: float = fuel_total / net if net > 0.4 else 400.0
	t_fuel = minf(t_fuel, 400.0)
	var c := close_rate(s)
	var base_b := bonus_for(steps_reached(s) * (1.0 + 0.15 * steady), cap)
	# integrate
	var t := 0.0
	var cum_h := 0.0
	var e_time := 0.0
	var e_coins := 0.0
	var e_dist := 0.0
	var dist := 0.0
	var p_target := 0.0
	var path_coins := 0.0     # coins if the plane never crashed: when does each pick price get reached?
	var pick_k := 0
	var picks_exp := 0.0
	var first_pick_t := -1.0
	var last_pick_t := 0.0
	var next_thr := 0.0
	var gap_sum := 0.0
	var gap_w := 0.0
	var target_t := -1.0
	var hyp_gap_sum := 0.0
	var hyp_gap_n := 0
	while t < maxf(t_fuel, 150.0):
		var alive := t < t_fuel
		var sp := speed_at(t)
		var h := hazard0(s) * pow(sp / T.base_speed, 1.5) * (0.9 if (eye and t > T.cloud_start_time) else 1.0)
		cum_h += h * DT
		# survival: at most `lives` crashes survived (Poisson)
		var surv := 0.0
		var term := exp(-cum_h)
		for k in lives + 1:
			surv += term
			term *= cum_h / float(k + 1)
		var b := base_b + (head - 1.0) * exp(-t / 8.0)
		var per_sec: float = sp * T.coins_per_unit * maxf(b - T.bonus_pay_offset, 0.0) * coin_mult + (lam * bounty + c * ccpay) * coin_mult
		var w := surv if alive else 0.0
		e_coins += w * per_sec * DT
		path_coins += per_sec * DT
		var pscale: float = coin_mult * (1.0 + T.pick_flat_weight * (bounty + ccpay) / T.pick_flat_ref)
		if pick_k == 0:
			var due: bool = (path_coins >= T.pick_first * pscale and t >= T.first_pick_min_seconds) or t >= T.first_pick_max_seconds
			if due:
				picks_exp += w
				first_pick_t = t
				last_pick_t = t
				pick_k = 1
				next_thr = maxf(T.pick_first * pscale, path_coins) + T.pick_price(pick_k, maxf(path_coins / maxf(t, 5.0), 0.01), pscale)
		else:
			while pick_k < 60 and path_coins >= next_thr:
				picks_exp += w
				gap_sum += (t - last_pick_t) * w
				gap_w += w
				hyp_gap_sum += t - last_pick_t
				hyp_gap_n += 1
				last_pick_t = t
				pick_k += 1
				next_thr = maxf(next_thr, path_coins) + T.pick_price(pick_k, maxf(path_coins / maxf(t, 5.0), 0.01), pscale)
		e_time += w * DT
		e_dist += w * sp * DT
		dist += sp * DT
		if target_t < 0.0 and dist >= target_dist_units:
			target_t = t
			p_target = surv
		t += DT
	return {"time": e_time, "coins": e_coins, "dist_units": e_dist, "p_target": p_target, "t_fuel": t_fuel, "picks": picks_exp, "first_pick": first_pick_t, "gap_sum": gap_sum, "gap_w": gap_w, "hyp_gap": (hyp_gap_sum / hyp_gap_n) if hyp_gap_n > 0 else -1.0}

## The score at which pick number k (0 = the first) comes: the sum of the prices so far.
func _pick_cum(k: int, perm: float) -> float:
	var total := 0.0
	for i in k + 1:
		total += T.pick_first * perm * pow(T.pick_growth, i)
	return total

func value_of(level: Dictionary, loadout: Array, s: float) -> float:
	var ev := evaluate(level, loadout, s, 1e9)
	return ev["coins"] / (ev["time"] + OVERHEAD)

## The best subset of owned gear that fits the slots.
func best_loadout(level: Dictionary, slots: int, s: float) -> Array:
	var owned: Array[String] = []
	for u in T.upgrades_in_tab("gear"):
		if level[u["id"]] > 0:
			owned.append(u["id"])
	var best: Array = []
	var best_v := value_of(level, [], s)
	var n := owned.size()
	for mask in range(1, 1 << n):
		var pick: Array = []
		for i in n:
			if mask & (1 << i):
				pick.append(owned[i])
		if pick.size() > slots:
			continue
		var v := value_of(level, pick, s)
		if v > best_v:
			best_v = v
			best = pick
	return best

func fmt(n: float) -> String:
	return T.fmt(n)

func play(label: String) -> Dictionary:
	var level := {}
	for u in T.upgrades:
		level[u["id"]] = 0
	var slots := 1
	var coins := 0.0
	var clock := 0.0
	var runs := 0
	var buys := 0
	var unlock_p := 1.0           # probability the 3,000 m goal has NOT been reached yet
	var target_units: float = 3000.0 / T.meters_per_unit
	var marks := [300.0, 900.0, 1800.0, 2700.0, 3600.0, 5400.0, 7200.0]
	var next_mark := 0
	var events: Array[String] = []
	var first_buy_run := -1
	var slot2_time := -1.0
	var unlock50 := -1.0
	var unlock90 := -1.0
	var earned := 0.0
	var reached := {}      # cumulative coins earned -> [run, minutes]
	var goals := [1000.0, 10000.0, 100000.0, 1000000.0, 10000000.0]
	print("")
	print("=== %s player ===" % label)
	print("minutes | runs | run length | coins/run | coins/min | balance | levels (coin/bounty/ccpay/cap | tank/eff/refill) | gear | slots | best-distance chance")
	while clock < SESSION:
		var s := skill_at(runs)
		var loadout := best_loadout(level, slots, s)
		var ev := evaluate(level, loadout, s, target_units)
		runs += 1
		coins += ev["coins"]
		earned += ev["coins"]
		for g in goals:
			if earned >= g and not reached.has(g):
				reached[g] = [runs, clock / 60.0]
		clock += ev["time"] + OVERHEAD
		unlock_p *= (1.0 - ev["p_target"])
		if unlock50 < 0.0 and unlock_p <= 0.5:
			unlock50 = clock
		if unlock90 < 0.0 and unlock_p <= 0.1:
			unlock90 = clock
		# shopping: best gain per coin, buy it if affordable (or if the best one is far off, the best affordable)
		var improved := true
		while improved:
			improved = false
			var cands: Array[Dictionary] = []
			for u in T.upgrades:
				var id: String = u["id"]
				var m: int = T.max_level(id)
				if m >= 0 and level[id] >= m:
					continue
				var cost: float = T.upgrade_cost(id, level[id])
				level[id] += 1
				var lo := best_loadout(level, slots, s)
				var v_after := value_of(level, lo, s)
				level[id] -= 1
				var v_before := value_of(level, best_loadout(level, slots, s), s)
				cands.append({"id": id, "cost": cost, "ratio": (v_after - v_before) / cost, "gain": v_after - v_before})
			if slots < 3:   # a gear slot: worth what the best extra owned gear adds
				var v_before2 := value_of(level, best_loadout(level, slots, s), s)
				var v_after2 := value_of(level, best_loadout(level, slots + 1, s), s)
				cands.append({"id": "slot", "cost": T.gear_slot_costs[slots], "ratio": (v_after2 - v_before2) / T.gear_slot_costs[slots], "gain": v_after2 - v_before2})
			cands.sort_custom(func(a, b): return a["ratio"] > b["ratio"])
			var pick := {}
			if not cands.is_empty() and cands[0]["gain"] > 0.0:
				if cands[0]["cost"] <= coins:
					pick = cands[0]
				else:
					for cd in cands:   # settle for a cheaper one if it is nearly as good per coin
						if cd["cost"] <= coins and cd["gain"] > 0.0 and cd["ratio"] >= 0.5 * cands[0]["ratio"]:
							pick = cd
							break
			# Players also want their toys: gear and slots get bought once they are a modest part of the balance,
			# whatever the coins-per-minute maths says.
			if pick.is_empty() or T.upgrade_def(pick["id"]).get("tab", "") != "gear":
				for cd in cands:
					var is_slot: bool = cd["id"] == "slot"
					var is_gear: bool = (not is_slot) and T.upgrade_def(cd["id"])["tab"] == "gear"
					if (is_slot and cd["cost"] <= 0.6 * coins) or (is_gear and cd["cost"] <= 0.3 * coins):
						if is_slot and best_loadout(level, slots + 1, s).size() <= best_loadout(level, slots, s).size():
							continue   # nothing to put in the new slot yet
						pick = cd
						break
			if not pick.is_empty():
				coins -= pick["cost"]
				clock += BUY_TIME
				buys += 1
				if pick["id"] == "slot":
					slots += 1
					if slot2_time < 0.0 and slots == 2:
						slot2_time = clock
					events.append("%5.1f min  2nd gear slot" % (clock / 60.0) if slots == 2 else "%5.1f min  3rd gear slot" % (clock / 60.0))
				else:
					level[pick["id"]] += 1
					if first_buy_run < 0:
						first_buy_run = runs
						events.append("%5.1f min  first purchase after run %d: %s" % [clock / 60.0, runs, pick["id"]])
					elif T.upgrade_def(pick["id"])["tab"] == "gear" and level[pick["id"]] == 1:
						events.append("%5.1f min  gear: %s" % [clock / 60.0, pick["id"]])
				improved = true
		if next_mark < marks.size() and clock >= marks[next_mark]:
			var run_len: float = ev["time"]
			print("%7.0f | %4d | %5.0f s | %9s | %9s | %7s | %d/%d/%d/%d | %d/%d/%d | %s | %d | %.0f%%" % [
					clock / 60.0, runs, run_len, fmt(ev["coins"]), fmt(ev["coins"] / (run_len + OVERHEAD) * 60.0), fmt(coins),
					level["coin_value"], level["can_bounty"], level["close_call_pay"], level["bonus_cap"],
					level["fuel_tank"], level["efficiency"], level["refill"], str(loadout), slots, (1.0 - unlock_p) * 100.0])
			print("          picks: first after %s, %.1f picks per run, %s between picks" % [("%.0f s" % ev["first_pick"]) if ev["first_pick"] >= 0.0 else "never", ev["picks"], ("%.0f s" % (ev["gap_sum"] / ev["gap_w"])) if ev["gap_w"] > 0.05 else "-"])
			print("          (if the run lasted: %s between picks)" % (("%.0f s" % ev["hyp_gap"]) if ev["hyp_gap"] >= 0.0 else "-"))
			next_mark += 1
	print("")
	for e in events:
		print(e)
	print("3,000 m goal (Coast unlock): 50%% chance reached by %.0f min, 90%% by %s (a run needs %.0f units = %.0f m)" % [
			unlock50 / 60.0, ("%.0f min" % (unlock90 / 60.0)) if unlock90 > 0.0 else "after the 2 hours", target_units, 3000.0])
	print("runs in 2 hours: %d, purchases: %d" % [runs, buys])
	return {"reached": reached, "first_buy_run": first_buy_run, "slot2": slot2_time, "runs": runs}

func _initialize() -> void:
	T = root.get_node("Tuning")
	S = root.get_node("Save")
	for kv in OS.get_environment("ECON_TUNE").split(",", false):
		var parts := kv.split("=")
		T.set(parts[0], float(parts[1]))
	passive = false
	var eng := play("ENGAGED (chases close calls)")
	passive = true
	var pas := play("PASSIVE (mostly avoids close calls)")
	print("")
	print("=== runs needed to earn the same total (passive / engaged) ===")
	for g in [1000.0, 10000.0, 100000.0, 1000000.0, 10000000.0]:
		var e: Array = eng["reached"].get(g, [-1, -1.0])
		var q: Array = pas["reached"].get(g, [-1, -1.0])
		print("%8s coins: engaged %s runs (%.0f min), passive %s runs (%.0f min)  ->  %s" % [fmt(g), str(e[0]) if e[0] >= 0 else "-", e[1], str(q[0]) if q[0] >= 0 else "-", q[1], ("%.1fx as many runs" % (float(q[0]) / e[0])) if (e[0] > 0 and q[0] > 0) else "-"])
	print("first purchase after run: engaged %d, passive %d" % [eng["first_buy_run"], pas["first_buy_run"]])
	quit()
