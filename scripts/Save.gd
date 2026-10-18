extends Node
## Persistent progress in one small JSON file in user:// (in the web build that is the browser's
## IndexedDB, so it survives reloads). Only written when something changes between runs (a run
## ends, a purchase, a loadout change, a debug button), never while flying. Autoload name: Save.

## Emitted whenever the stored data changed (the menus refresh their texts from it).
signal changed

## Bump when the file layout changes, and teach _migrate() how to read the old one.
##   1: high_score, coins (ints), levels {fuel_tank, efficiency, refill, magnet, bonus_cap}
##   2: coins and high_score are floats (score IS coins), upgrade tabs, gear slots + loadout, stats
const VERSION := 2

var path := "user://save.json"      # (tests point this somewhere else)
var high_score := 0.0               # most coins earned in one run
var coins := 0.0
var levels := {}                    # upgrade id -> level
var slots := 1                      # gear slots unlocked (1..3)
var loadout: Array = ["", "", ""]   # gear id equipped in each slot ("" = empty)
var stats := {}                     # lifetime counters (cans, close calls ...)

func _ready() -> void:
	load_game()

func _defaults() -> void:
	high_score = 0.0
	coins = 0.0
	levels = {}
	for u in Tuning.upgrades:
		levels[u["id"]] = 0
	slots = 1
	loadout = ["", "", ""]
	stats = {}

## Read the save file; a missing, unreadable or corrupt file just means a fresh start.
func load_game() -> void:
	_defaults()
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				_apply(_migrate(parsed))
	changed.emit()

## Bring an older file layout up to the current one. Version 0 = a file without a "version" field.
## Unknown extra fields are ignored, missing ones fall back to defaults.
func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 0))
	if v < 1:
		d["version"] = 1   # v0 -> v1: same fields, just stamped with a version
		v = 1
	if v < 2:
		# v1 -> v2: the Can Magnet was a plane upgrade (levels 0-8); it is gear now (levels 0-3).
		var lv: Dictionary = d.get("levels", {})
		var old_magnet := int(lv.get("magnet", 0))
		var gear_level := mini(3, int(ceil(old_magnet / 3.0)))
		lv["magnet"] = gear_level
		d["levels"] = lv
		d["slots"] = 1
		d["loadout"] = ["magnet" if gear_level > 0 else "", "", ""]
		d["version"] = 2
	return d

func _apply(d: Dictionary) -> void:
	high_score = maxf(float(d.get("high_score", 0.0)), 0.0)
	coins = maxf(float(d.get("coins", 0.0)), 0.0)
	var lv: Variant = d.get("levels", {})
	if lv is Dictionary:
		for u in Tuning.upgrades:
			var m := int(u["max"])
			var l := maxi(int(lv.get(u["id"], 0)), 0)
			levels[u["id"]] = l if m < 0 else mini(l, m)
	slots = clampi(int(d.get("slots", 1)), 1, 3)
	var lo: Variant = d.get("loadout", [])
	if lo is Array:
		for i in 3:
			var id := String(lo[i]) if i < lo.size() else ""
			loadout[i] = id if (i < slots and _is_gear(id) and level(id) > 0) else ""
	var st: Variant = d.get("stats", {})
	if st is Dictionary:
		stats = st.duplicate()

func _is_gear(id: String) -> bool:
	return not Tuning.upgrade_def(id).is_empty() and Tuning.upgrade_def(id)["tab"] == "gear"

func to_dict() -> Dictionary:
	return {"version": VERSION, "high_score": high_score, "coins": coins, "levels": levels.duplicate(),
			"slots": slots, "loadout": loadout.duplicate(), "stats": stats.duplicate()}

func save_game() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(to_dict()))
		f.close()
	changed.emit()

func level(id: String) -> int:
	return int(levels.get(id, 0))

func is_maxed(id: String) -> bool:
	var m := Tuning.max_level(id)
	return m >= 0 and level(id) >= m

func cost_of_next(id: String) -> float:
	return Tuning.upgrade_cost(id, level(id))

func can_buy(id: String) -> bool:
	return not is_maxed(id) and coins >= cost_of_next(id)

## Buy the next level of an upgrade. Returns false (and changes nothing) if maxed or too poor.
## A gear piece bought for the first time goes into a free slot if there is one.
func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var first_time := level(id) == 0
	coins -= cost_of_next(id)
	levels[id] = level(id) + 1
	if first_time and _is_gear(id) and not is_equipped(id):
		for i in slots:
			if loadout[i] == "":
				loadout[i] = id
				break
	save_game()
	return true

## Gear counts only while equipped (in an unlocked slot): its level, else 0.
func gear_level(id: String) -> int:
	return level(id) if is_equipped(id) else 0

func is_equipped(id: String) -> bool:
	for i in slots:
		if loadout[i] == id:
			return true
	return false

## Put an owned piece of gear in a slot (it leaves any other slot; whatever was in the slot comes
## out). Equipping what already sits in that slot takes it out. Returns false if not allowed.
func equip(id: String, slot: int) -> bool:
	if slot < 0 or slot >= slots or not _is_gear(id) or level(id) <= 0:
		return false
	if loadout[slot] == id:
		loadout[slot] = ""
	else:
		for i in 3:
			if loadout[i] == id:
				loadout[i] = loadout[slot]   # swap places with what was in the target slot
		loadout[slot] = id
	save_game()
	return true

## Cost of the next gear slot, or -1 if all are unlocked.
func next_slot_cost() -> float:
	return -1.0 if slots >= 3 else Tuning.gear_slot_costs[slots]

func buy_slot() -> bool:
	var c := next_slot_cost()
	if c < 0.0 or coins < c:
		return false
	coins -= c
	slots += 1
	save_game()
	return true

## End of a run: store the coins earned and the high score. Returns true if it is a new best.
func record_run(earned: float) -> bool:
	earned = floorf(maxf(earned, 0.0))
	var best := earned > high_score
	if best:
		high_score = earned
	coins += earned
	save_game()
	return best

func add_coins(n: float) -> void:
	coins = maxf(coins + n, 0.0)
	save_game()

func add_stat(name: String, n: float = 1.0) -> void:
	stats[name] = float(stats.get(name, 0.0)) + n

func stat(name: String) -> float:
	return float(stats.get(name, 0.0))

func reset_all() -> void:
	_defaults()
	save_game()
