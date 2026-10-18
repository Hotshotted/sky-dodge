class_name Perks
extends Node
## What the player has picked THIS RUN: perk levels, running boosts, and the score at which the next pick
## comes. Pure bookkeeping (no nodes are created while it runs); Main applies the effects.

signal changed          # perks or boosts changed (the HUD redraws its icons)

var levels := {}        # perk id -> level (1-3)
var boosts := {}        # boost id -> seconds left
var picks_taken := 0
var next_pick := 0.0    # score at which the next pick comes
var perm_mult := 1.0    # map multiplier x Coin Value: it scales the pick prices
var _price_sum := 0.0
var enabled := true     # false: no picks at all (the tests that set the score by hand use this)
var debug_grants := {}  # ?tune: perk id -> level, given at the start of every run

## A fresh run: no perks or boosts, the first pick at pick_first x the permanent multiplier.
func start_run(perm_mult_: float) -> void:
	levels.clear()
	boosts.clear()
	perm_mult = maxf(perm_mult_, 0.0001)
	picks_taken = 0
	_price_sum = price(0)
	next_pick = _price_sum if enabled else INF
	for id in debug_grants:
		levels[id] = int(debug_grants[id])
	changed.emit()

## What pick number `k` (0 = the first) costs in score: pick_first x multiplier, +20% each time.
func price(k: int) -> float:
	return Tuning.pick_first * perm_mult * pow(Tuning.pick_growth, k)

## A pick was taken: the next one is due `price` more score later.
func advance() -> void:
	picks_taken += 1
	_price_sum += price(picks_taken)
	next_pick = _price_sum

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
		pool.append({"kind": "boost", "id": d["id"], "name": d["name"], "glyph": d["glyph"], "color": d["color"], "line": d["line"], "level": 0, "owned": false})
		weights.append(Tuning.boost_weight)
	for d in Tuning.supplies:
		if d.get("needs", "") == "crates" and not Tuning.crates_enabled:
			continue
		var line: String = d["line"]
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
	return out

func perk_card(d: Dictionary, new_level: int, owned: bool) -> Dictionary:
	return {"kind": "perk", "id": d["id"], "name": d["name"], "glyph": d["glyph"], "color": d["color"],
			"line": String(d["line"]).replace("{v}", _num(Tuning.perk_value(d["id"], new_level))), "level": new_level, "owned": owned}

## The Coin Bag: a share of what the next pick costs.
func coin_bag_amount() -> float:
	return floorf(Tuning.coin_bag_fraction * price(picks_taken + 1))

## Take a card: perks level up and boosts start here; supplies (instant) are Main's job.
func take(card: Dictionary) -> void:
	match card["kind"]:
		"perk":
			levels[card["id"]] = card["level"]
		"boost":
			boosts[card["id"]] = Tuning.boost_time
	changed.emit()
