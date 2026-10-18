extends Node
## Persistent progress: high score, coins and upgrade levels, in one small JSON file in user://
## (in the web build user:// is the browser's IndexedDB, so it survives reloads). The file is only
## written when something changes between runs (a run ends, a purchase, a debug button), never
## while flying. Autoload name: Save.

## Emitted whenever the stored data changed (the menus refresh their texts from it).
signal changed

## Bump when the file layout changes, and teach _migrate() how to read the old one.
const VERSION := 1

var path := "user://save.json"      # (tests point this somewhere else)
var high_score := 0
var coins := 0
var levels := {}                    # upgrade id -> level

func _ready() -> void:
	load_game()

func _defaults() -> void:
	high_score = 0
	coins = 0
	levels = {}
	for u in Tuning.upgrades:
		levels[u["id"]] = 0

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

## Bring an older (or newer) file layout up to the current one. Version 0 = a file without a
## "version" field. Unknown extra fields are ignored, missing ones fall back to defaults.
func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 0))
	if v < 1:
		d["version"] = 1   # v0 -> v1: same fields, just stamped with a version
	return d

func _apply(d: Dictionary) -> void:
	high_score = maxi(int(d.get("high_score", 0)), 0)
	coins = maxi(int(d.get("coins", 0)), 0)
	var lv: Variant = d.get("levels", {})
	if lv is Dictionary:
		for u in Tuning.upgrades:
			levels[u["id"]] = clampi(int(lv.get(u["id"], 0)), 0, int(u["max_level"]))

func to_dict() -> Dictionary:
	return {"version": VERSION, "high_score": high_score, "coins": coins, "levels": levels.duplicate()}

func save_game() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(to_dict()))
		f.close()
	changed.emit()

func level(id: String) -> int:
	return int(levels.get(id, 0))

func cost_of_next(id: String) -> int:
	return Tuning.upgrade_cost(id, level(id))

func is_maxed(id: String) -> bool:
	return level(id) >= int(Tuning.upgrade_def(id)["max_level"])

func can_buy(id: String) -> bool:
	return not is_maxed(id) and coins >= cost_of_next(id)

## Buy the next level of an upgrade. Returns false (and changes nothing) if maxed or too poor.
func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	coins -= cost_of_next(id)
	levels[id] = level(id) + 1
	save_game()
	return true

## End of a run: store the coins earned and the high score. Returns true if it is a new best.
func record_run(points: int, earned: int) -> bool:
	var best := points > high_score
	if best:
		high_score = points
	coins += maxi(earned, 0)
	save_game()
	return best

func add_coins(n: int) -> void:
	coins = maxi(coins + n, 0)
	save_game()

func reset_all() -> void:
	_defaults()
	save_game()
