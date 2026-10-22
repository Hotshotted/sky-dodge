extends RefCounted
## The test bots (shared by tests/threat_sim.gd, tests/economy_sim.gd and the smoke test's AFK guard). Load with
##   var Bots = load("res://tests/bots.gd"); var bot = Bots.new()
## They fly the real game loop one frame at a time: call bot.drive(main, t) BEFORE main._process(dt).
##   skilled   reacts after ~0.2 s, flies at 15 units/s, plans around obstacles and every telegraph, routes for fuel cans,
##             rolls when a telegraph is about to arm over it, and takes the picks of its build
##   lazy      only steers toward the nearest fuel can it can reach (no dodging, no rolling)
##   afk       zero input
## `solid` = false makes obstacles harmless to the plane (the sim then measures the threats alone: a "perfect obstacle pilot").

const DT := 1.0 / 30.0
const REACT := 0.22
const SPEED := 15.0
const Z_OFFS := [0.0, -2.5, 2.0, -4.5]
const PRIORITY := {
	"guns": ["flak", "pods", "tail"],
	"utility": ["wingman", "shockwave", "magnet_field", "skywriter", "banner", "roll"],
	"mixed": ["flak", "wingman", "shockwave", "magnet_field", "pods", "skywriter", "roll", "banner", "tail"],
}

var root: Node
var mode := "skilled"
var build := "mixed"          # key of PRIORITY, "none" (take nothing), or a single perk id ("single:flak")
var single := ""
var base_z := 0.0
var goal := Vector2.ZERO
var _next_plan := 0.0
var _zones: Array = []
var _seen := {}

func tn() -> Node:
	return root.get_node("Tuning")

## Start of a run (after main.restart()).
func start(main: Node) -> void:
	main._update_plane_zone()
	base_z = main.player.position.z
	goal = Vector2(main.player.position.x, main.player.position.z)
	_next_plan = 0.0
	_seen.clear()
	if build == "none" and main.picks.enabled:
		main.picks.enabled = false
		main.picks.next_pick = INF
		tn().boss_rare_pick = false
	else:
		tn().boss_rare_pick = true

## One frame of flying (before main._process).
func drive(main: Node, t: float) -> void:
	if mode == "afk":
		return
	var pl: Node = main.player
	var target_x := can_target(main, pl)
	if mode == "lazy":
		goal = Vector2(target_x, base_z)
	else:
		if main.gadgets.level("roll") > 0 and main.gadgets.roll_cd <= 0.0 and imminent(main):
			main.try_roll()
		if t >= _next_plan:
			_next_plan = t + 0.08
			goal = plan(main, t, target_x)
	var d := goal - Vector2(pl.position.x, pl.position.z)
	var step := d.limit_length(SPEED * DT)
	pl.position.x += step.x
	pl.position.z += step.y

## The fuel can the plane can still reach in time (its x), else the middle.
func can_target(main: Node, pl: Node) -> float:
	for r in main.spawner._rows:
		if r.passed or not r.has_can:
			continue
		var dz: float = r.position.z - pl.position.z
		if dz > 1.0 or dz < -26.0:
			continue
		var time_left: float = -dz / maxf(main.spawner.scroll_speed, 1.0)
		if absf(r.can_x - pl.position.x) <= SPEED * maxf(time_left - 0.15, 0.0) + 0.5:
			return r.can_x
	return 0.0

func threat_cost(main: Node, t: float, cx: float, cz: float, cur: Vector2 = Vector2(INF, INF)) -> float:
	var th = main.spawner.threats
	var c := 0.0
	for z in _zones:
		var key := str(z["kind"]) + ":" + str(snappedf(z["rect"].position.x, 0.5))
		if not _seen.has(key):
			_seen[key] = t
		var r: Rect2 = (z["rect"] as Rect2).grow_individual(1.0, 0.9, 1.0, 0.9)
		if r.has_point(Vector2(cx, cz)) and float(z["at"]) <= 0.95 and t - float(_seen[key]) >= REACT:
			c += 1000.0
	if cur.x < 1.0e9:
		if th.crow_danger_path(cur, Vector2(cx, cz), SPEED) < 3.2:
			c += 900.0
	elif th.crow_danger(cx, cz) <= 3.2:
		c += 900.0
	for b in main.spawner.hazards.bolts_in_play():
		if b.state == 2 or (b.state == 1 and tn().lightning_warn - b.t <= 0.95):
			if absf(cx - tn().column_center(b.col)) < tn().column_width() * 0.5 + 1.2:
				c += 1000.0
	return c

func path_clear(main: Node, caps: PackedFloat32Array, spd: float, cur: Vector2, cand: Vector2) -> bool:
	var dir := cand - cur
	for k in range(0, 11):
		var tau := 0.1 * k
		var q := cur + dir.limit_length(SPEED * tau)
		for dx in [0.0, -0.55, 0.55]:
			if main.spawner.probe(Vector2(q.x + dx, q.y - spd * tau), caps):
				return false
	return true

func plan(main: Node, t: float, target_x: float) -> Vector2:
	var pl: Node = main.player
	var th = main.spawner.threats
	th.zones(1.3, _zones)
	var cur := Vector2(pl.position.x, pl.position.z)
	var caps: PackedFloat32Array = pl.hit_capsules()
	var spd: float = main.spawner.scroll_speed
	var best := Vector2(target_x, base_z)
	var best_c := INF
	for xi in 15:
		var cx: float = -5.1 + xi * 0.73
		for zo in Z_OFFS:
			var cz: float = clampf(base_z + float(zo), pl.z_min, pl.z_max)
			var cand := Vector2(cx, cz)
			var c := threat_cost(main, t, cx, cz, cur)
			if not path_clear(main, caps, spd, cur, cand):
				c += 1000.0 if main.spawner.obstacles_solid else 250.0
			c += absf(cx - target_x) * 2.0 + absf(cz - base_z) * 0.8 + cur.distance_to(cand) * 0.3
			if c < best_c:
				best_c = c
				best = cand
	return best

func imminent(main: Node) -> bool:
	var th = main.spawner.threats
	th.zones(0.5, _zones)
	var pp := Vector2(main.player.position.x, main.player.position.z)
	for z in _zones:
		if (z["rect"] as Rect2).grow_individual(0.9, 0.8, 0.9, 0.8).has_point(pp) and float(z["at"]) <= 0.3:
			return true
	if th.crow_danger(pp.x, pp.y) <= 0.45:
		return true
	for b in main.spawner.hazards.bolts_in_play():
		if (b.state == 2 or (b.state == 1 and tn().lightning_warn - b.t <= 0.3)) and absf(pp.x - tn().column_center(b.col)) < tn().column_width() * 0.5 + 1.2:
			return true
	return false

## The card the build takes.
func choose_card(main: Node) -> int:
	var order: Array = PRIORITY.get(build, [])
	if build.begins_with("single:"):
		order = [build.substr(7)]
	var best := 0
	var best_s := -1.0
	for i in main._pick_cards.size():
		var c: Dictionary = main._pick_cards[i]
		var s := 10.0
		var id: String = c["id"]
		if c["kind"] == "perk":
			var pos := order.find(id)
			if pos >= 0:
				s = 100.0 - 6.0 * pos + (12.0 if c["owned"] else 0.0)
			elif build.begins_with("single:"):
				s = 5.0   # (a single-perk build takes nothing else that is a perk)
			elif id in ["fuel_miser", "scavenger", "hot_streak", "lucky_whiskers"]:
				s = 50.0
			else:
				s = 30.0
		elif c["kind"] == "supply" and (id == "full_tank" or id == "patch") and main.fuel < tn().fuel_max() * 0.55:
			s = 85.0
		elif c["kind"] == "boost":
			s = 25.0
		if s > best_s:
			best_s = s
			best = i
	return best

## Give a save a permanent-upgrade preset: "none", "mid" (about 40% of every upgrade, two gear slots) or "max" (every upgrade at its cap, three slots).
static func apply_upgrades(save: Node, tuning: Node, preset: String) -> void:
	save.reset_all()
	save.unlock_all_milestones()
	if preset == "none":
		return
	var frac := 0.4 if preset == "mid" else 1.0
	for u in tuning.upgrades:
		var cap: int = int(u["max"])
		var lvl: int = int(round((12 if cap < 0 else cap) * frac))
		if u["tab"] == "gear":
			lvl = int(round(maxf(float(cap) * frac, 1.0))) if cap > 0 else 1
		save.levels[u["id"]] = lvl
	save.slots = 3 if preset == "max" else 2
	save.loadout = ["nine_lives", "reserve_tank", "steady_nerves"] if preset == "max" else ["nine_lives", "reserve_tank", ""]
