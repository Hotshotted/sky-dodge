class_name Perks
extends Node
## What the player has picked THIS RUN: perk levels, running boosts, and the score at which the next pick
## comes. Pure bookkeeping (no nodes are created while it runs); Main applies the effects.

signal changed          # perks or boosts changed (the HUD redraws its icons)

var levels := {}        # perk id -> level (1-3)
var boosts := {}        # boost id -> seconds left
var picks_taken := 0
var _bag_score := 0.0   # (the score when the last pick was taken: the Coin Bag is sized from the gap to the next one)
var next_pick := 0.0    # score at which the next pick comes
var perm_mult := 1.0    # map multiplier x Coin Value: it scales the pick prices
var enabled := true     # false: no picks at all (the tests that set the score by hand use this)
var debug_grants := {}  # ?tune: perk id -> level, given at the start of every run

## A fresh run: no perks or boosts, the first pick at pick_first x the permanent multiplier.
func start_run(perm_mult_: float) -> void:
	levels.clear()
	boosts.clear()
	perm_mult = maxf(perm_mult_, 0.0001)
	picks_taken = 0
	next_pick = price(0) if enabled else INF
	for id in debug_grants:
		levels[id] = int(debug_grants[id])
	changed.emit()

## The score the very first pick needs (it also comes on the timer, see first_pick_min_seconds).
func price(k: int) -> float:
	return Tuning.pick_first * perm_mult * pow(Tuning.pick_growth, k)

## A pick was taken: the next one is priced in seconds of what you are earning this run (Tuning.pick_price), and is
## that far beyond the higher of the old threshold and the score you have now.
func advance(score_now: float = 0.0, elapsed: float = 1.0) -> void:
	picks_taken += 1
	var rate := maxf(score_now / maxf(elapsed, 5.0), 0.01)
	next_pick = maxf(next_pick, score_now) + Tuning.pick_price(picks_taken, rate, perm_mult)

func level(id: String) -> int:
	return int(levels.get(id, 0))

## The effect of an owned perk (0 if not owned).
func value(id: String) -> float:
	return Tuning.perk_value(id, level(id))

func has_boost(id: String) -> bool:
	return float(boosts.get(id, 0.0)) > 0.0

func boost_left(id: String) -> float:
	return float(boosts.get(id, 0.0))

func set_perk(id: String, lvl: int) -> void:
	if lvl <= 0:
		levels.erase(id)
	else:
		levels[id] = clampi(lvl, 1, 3)
	changed.emit()

## Tick the boost timers.
func update(delta: float) -> void:
	var gone := false
	for id in boosts.keys():
		boosts[id] = float(boosts[id]) - delta
		if boosts[id] <= 0.0:
			boosts.erase(id)
			gone = true
	if gone:
		changed.emit()

func _num(v: float) -> String:
	return ("%d" % int(round(v))) if absf(v - round(v)) < 0.001 else ("%.1f" % v)

## Is this perk offered at all? (Unlocked, not maxed, and crates exist if it needs them.)
func perk_offered(d: Dictionary) -> bool:
	if not Save.perk_unlocked(d["id"]):
		return false
	if d.get("needs", "") == "crates" and not Tuning.crates_enabled:
		return false
	return level(d["id"]) < 3

## Build the cards for a pick: `count` different ones, drawn by weight. Owned perks are offered more often; Full
## Tank more often when the tank is low. Each card is a Dictionary (kind, id, name, glyph, color, line, level, owned).
func roll(fuel_frac: float, count: int = 3) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	var weights: Array[float] = []
	for d in Tuning.perks:
		if not perk_offered(d):
			continue
		var lvl := level(d["id"])
		pool.append(perk_card(d, lvl + 1, lvl > 0))
		weights.append(1.0 + (Tuning.perk_owned_weight if lvl > 0 else 0.0))
	for d in Tuning.boosts:
		pool.append({"kind": "boost", "id": d["id"], "name": d["name"], "glyph": d["glyph"], "color": d["color"], "line": Tuning.pick_short[d["id"]], "level": 0, "owned": false})
		weights.append(Tuning.boost_weight)
	for d in Tuning.supplies:
		if d.get("needs", "") == "crates" and not Tuning.crates_enabled:
			continue
		var line: String = Tuning.pick_short[d["id"]]
		if d["id"] == "coin_bag":
			line = line.replace("{v}", Tuning.fmt(coin_bag_amount()))
		pool.append({"kind": "supply", "id": d["id"], "name": d["name"], "glyph": d["glyph"], "color": d["color"], "line": line, "level": 0, "owned": false})
		weights.append(Tuning.supply_weight * (Tuning.full_tank_low_weight if (d["id"] == "full_tank" and fuel_frac < 0.4) else 1.0))
	var out: Array[Dictionary] = []
	for n in mini(count, pool.size()):
		var total := 0.0
		for w in weights:
			total += w
		var roll_v := randf() * total
		var idx := pool.size() - 1
		for i in pool.size():
			roll_v -= weights[i]
			if roll_v <= 0.0:
				idx = i
				break
		out.append(pool[idx])
		pool.remove_at(idx)
		weights.remove_at(idx)
	# Every set of cards holds at least one perk: if none came up, a weighted perk (owned ones more likely) replaces the last card.
	var has_perk := false
	for c in out:
		has_perk = has_perk or c["kind"] == "perk"
	if not has_perk and not out.is_empty():
		var perks_pool: Array[Dictionary] = []
		var perk_w: Array[float] = []
		for d in Tuning.perks:
			if perk_offered(d):
				var lv := level(d["id"])
				perks_pool.append(perk_card(d, lv + 1, lv > 0))
				perk_w.append(1.0 + (Tuning.perk_owned_weight if lv > 0 else 0.0))
		if not perks_pool.is_empty():
			var tot := 0.0
			for w in perk_w:
				tot += w
			var rv := randf() * tot
			var pick := perks_pool.size() - 1
			for i in perks_pool.size():
				rv -= perk_w[i]
				if rv <= 0.0:
					pick = i
					break
			out[out.size() - 1] = perks_pool[pick]
	return out

func perk_card(d: Dictionary, new_level: int, owned: bool) -> Dictionary:
	return {"kind": "perk", "id": d["id"], "name": d["name"], "glyph": d["glyph"], "color": d["color"],
			"line": String(Tuning.pick_short[d["id"]]).replace("{v}", _num(Tuning.perk_value(d["id"], new_level))), "level": new_level, "owned": owned}

## The Coin Bag: a share of what the next pick costs.
func coin_bag_amount() -> float:
	var gap := next_pick - _bag_score
	if gap <= 0.0 or gap > 1.0e30:   # (no price set yet: use the plain one)
		gap = price(picks_taken + 1)
	return floorf(Tuning.coin_bag_fraction * gap)

## Take a card: perks level up and boosts start here; supplies (instant) are Main's job.
func take(card: Dictionary) -> void:
	match card["kind"]:
		"perk":
			levels[card["id"]] = card["level"]
		"boost":
			boosts[card["id"]] = Tuning.boost_time
	changed.emit()

## Is the combo's condition met right now? (Its perk at level 3 and the partner equipped / held.)
func combo_ready(c: Dictionary, levels_override: Dictionary = {}) -> bool:
	var lv: Dictionary = levels if levels_override.is_empty() else levels_override
	if int(lv.get(c["perk"], 0)) < 3:
		return false
	if c["partner_kind"] == "gear":
		return Save.is_equipped(c["partner"])
	return int(lv.get(c["partner"], 0)) > 0

## The combo that taking this card would complete (not active yet), or "".
func would_complete(card: Dictionary) -> String:
	if card["kind"] != "perk":
		return ""
	var after := levels.duplicate()
	after[card["id"]] = card["level"]
	for c in Tuning.combos:
		if combo_ready(c, after) and not combo_ready(c):
			return c["id"]
	return ""
