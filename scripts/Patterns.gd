class_name Patterns
extends RefCounted
## Handcrafted Countryside patterns: short obstacle sequences (2-6 rows tall) stored as data in PatternData.gd.
##   name, diff (1-5), rows, tags, speed [lo, hi] (the scroll speeds it is built and checked for),
##   items (what stands in the way), cans / hay (optional slots: a fuel can or a hay bale MAY appear there)
## An item: {"t": kind, "r": row, "x": x, ...}. Rows are spawn_spacing apart; "dz" shifts an item down the screen (units).
## Patterns can be mirrored left <-> right. check() plays a pattern with the real Kit and finds out, with a
## search over where the plane can be, whether it can be flown at a given speed (see check()).

const SPACING := 10.0
const WALL := 6.8                       # power lines run out to here (just past the screen edge)

## (Tuning is an autoload: reached through the tree so scripts that load this file before the autoloads exist still compile)
static func _tn() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("/root/Tuning")

static func all() -> Array:
	return PatternData.LIST

static func find(pattern_name: String) -> Dictionary:
	for p in PatternData.LIST:
		if p["name"] == pattern_name:
			return p
	return {}

static func has_tag(p: Dictionary, tag: String) -> bool:
	return (p["tags"] as Array).has(tag)

## A copy of an item turned left <-> right.
static func mirror_item(it: Dictionary) -> Dictionary:
	var m := it.duplicate()
	if m.has("x"):
		m["x"] = -float(m["x"])
	if m.has("dir"):
		m["dir"] = -float(m["dir"])
	if m.has("phase"):
		m["phase"] = -float(m["phase"])
	if m.has("gaps"):
		var g: Array = []
		for gp in m["gaps"]:
			g.append([-float(gp[1]), -float(gp[0])])
		g.reverse()
		m["gaps"] = g
	return m

## Everything a pattern needs that would otherwise be built (and thrown away) every time it is placed: its mirrored items
## and hay slots, and its can slots per row (plain and mirrored). Built once for every pattern by warm() at start-up.
static var _cache := {}
static var _edges: Array[float] = []

static func warm() -> void:
	for pat in PatternData.LIST:
		_entry(pat)

static func _entry(pat: Dictionary) -> Dictionary:
	var key: String = pat["name"]
	if _cache.has(key):
		return _cache[key]
	var m_items: Array = []
	for it in pat["items"]:
		m_items.append(mirror_item(it))
	var m_hay: Array = []
	for h in pat.get("hay", []):
		m_hay.append(mirror_item(h))
	var cans := [[], []]   # [plain, mirrored], each: per row an Array[float] of x
	for side in 2:
		for r in int(pat["rows"]):
			var xs: Array[float] = []
			for c in pat.get("cans", []):
				if int(c["r"]) == r:
					xs.append(-float(c["x"]) if side == 1 else float(c["x"]))
			cans[side].append(xs)
	var e := {"items_m": m_items, "hay_m": m_hay, "cans": cans}
	_cache[key] = e
	return e

## Put the items of `pat` into the kit. carriers[r] is the row object (anything with a .position.z) that pattern row r
## hangs on. hay_fill: which hay slots are filled (empty = all of them). only_row >= 0: just that row's items (the game
## places a pattern one row at a time, as the rows come). coins: the Coins pool that gets the pattern's coin trails (null = none).
## Returns the number of things placed.
static func realize(kit, pat: Dictionary, mirror: bool, carriers: Array, hay_fill: Array = [], only_row: int = -1, coins = null) -> int:
	var placed := 0
	var entry := _entry(pat)
	var items: Array = entry["items_m"] if mirror else pat["items"]
	for it in items:
		if only_row >= 0 and int(it["r"]) != only_row:
			continue
		var row = carriers[int(it["r"])]
		var dz: float = float(it.get("dz", 0.0))
		var x: float = float(it.get("x", 0.0))
		match it["t"]:
			"barn":   # "wall": a fly-through barn (a doorway between two walls of this thickness); "hx": a closed one
				if it.get("door", true):
					kit.spawn(Kit.BARN, row, x, dz, float(it.get("wall", 1.0)), 1.0)
				else:
					kit.spawn(Kit.BARN, row, x, dz, float(it.get("hx", 1.2)), 0.0)
				placed += 1
			"tractor":
				kit.spawn(Kit.TRACTOR, row, 0.0, dz, 0.0, 0.0, 0.0, 0.0, 0.0, float(it.get("dir", 1.0)))
				placed += 1
			"windmill":   # "v": 0 standard, 1 large (3 blades), 2 small and fast
				kit.spawn(Kit.WINDMILL, row, x, dz, float(it.get("v", 0)), 0.0, 0.0, 0.0, float(it.get("phase", 0.0)), float(it.get("dir", 1.0)))
				placed += 1
			"balloon":
				kit.spawn(Kit.BALLOON, row, x, dz, 0.0, 0.0, float(it.get("amp", _tn().balloon_amp)), float(it.get("rate", _tn().balloon_rate)), float(it.get("phase", 0.0)))
				placed += 1
			"kite":
				kit.spawn(Kit.KITE, row, x, dz, 0.0, 0.0, float(it.get("amp", _tn().kite_amp)), float(it.get("rate", _tn().kite_rate)), float(it.get("phase", 0.0)))
				placed += 1
			"powerline":
				_edges.clear()
				_edges.append(-WALL)
				for gp in it["gaps"]:
					_edges.append(float(gp[0]))
					_edges.append(float(gp[1]))
				_edges.append(WALL)
				for i in range(0, _edges.size(), 2):
					if _edges[i + 1] - _edges[i] > 0.4:
						kit.spawn(Kit.POWERLINE, row, _edges[i], dz, _edges[i + 1])
						placed += 1
			"crow":
				var n := int(it.get("n", 3))
				var lead = null
				for i in n:
					var o := float(i) - (n - 1) * 0.5
					var c = kit.spawn(Kit.CROW, row, x + o * float(it.get("spread", 0.9)), dz, 0.0, o * 0.4, o * float(it.get("aim", 0.8)), 0.0, 0.0, 1.0, absf(o) * float(it.get("stag", 0.12)))
					if c != null:
						if lead == null:
							lead = c
						c.leader = lead
						placed += 1
			"duster":
				kit.spawn(Kit.DUSTER, row, 0.0, dz, float(it.get("arrive", 0.7)), 0.0, 0.0, 0.0, 0.0, float(it.get("dir", 1.0)), float(it.get("delay", 0.0)))
				placed += 1
	if coins != null:
		var sgn := -1.0 if mirror else 1.0
		for c in (pat.get("coins", []) as Array):   # a trail: n coins from (x, dz) to "to" = [x, dz]
			if only_row >= 0 and int(c["r"]) != only_row:
				continue
			var to: Array = c["to"]
			placed += coins.spawn_line(carriers[int(c["r"])], sgn * float(c["x"]), float(c["dz"]), sgn * float(to[0]), float(to[1]), int(c["n"]))
	var slots: Array = entry["hay_m"] if mirror else pat.get("hay", [])
	for i in slots.size():
		if only_row >= 0 and int(slots[i]["r"]) != only_row:
			continue
		if hay_fill.is_empty() or (i < hay_fill.size() and hay_fill[i]):
			var h: Dictionary = slots[i]
			kit.spawn(Kit.HAY, carriers[int(h["r"])], float(h["x"]), float(h.get("dz", 0.0)), 0.0, 0.0)
			placed += 1
	return placed

## Where cans MAY be placed for pattern row r: the x of each slot (a cached array: nothing is built).
static func can_slots(pat: Dictionary, row: int, mirror: bool) -> Array[float]:
	return _entry(pat)["cans"][1 if mirror else 0][row]

# ---------- the passability check ----------

const CELL := 0.25                      # the plane's possible x positions are searched on this grid...
const MIN_ROUTE_CELLS := 3
const COMFORT := 0.1                    # routes are counted for a plane this much fatter: a route has to be flyable with room to spare
const STEP := 1.0 / 30.0                # ...once per step, and may move one cell per step (7.5 units/second)

## The plane's hit shapes made simpler and a bit bigger (one wing capsule + the fuselage), so the search is quick and
## errs on the side of "harder than the real plane".
static func simple_caps(real: PackedFloat32Array) -> PackedFloat32Array:
	var n := real.size() / 5
	var minx := INF
	var maxx := -INF
	var rad := 0.0
	var zsum := 0.0
	for i in n - 1:
		var o := i * 5
		minx = minf(minx, minf(real[o], real[o + 2]))
		maxx = maxf(maxx, maxf(real[o], real[o + 2]))
		rad = maxf(rad, real[o + 4])
		zsum += real[o + 1]
	var wz := zsum / maxf(n - 1, 1)
	var out := PackedFloat32Array()
	out.append_array([minx, wz, maxx, wz, rad])
	var f := (n - 1) * 5
	out.append_array([real[f], real[f + 1], real[f + 2], real[f + 3], real[f + 4]])
	return out

## Can the plane fly pattern `pat` at scroll speed `speed` (plane at z = plane_z, top of the screen at top_z)?
## Plays the pattern with the real Kit (so the models' own hit shapes and moving parts decide) and keeps the set of x
## positions the plane could be at, moving at most 7.5 units/s, never touching anything. Hay bales count as solid.
## A crow flock aims at the plane's x when it swoops, so every aim is tried (the plane has to be there at that moment).
## With count_routes it also counts the distinct comfortable routes (see routes_of(); hay bales are optional, so left out of that count): "routes" = the most any crow aim leaves (-1 = not counted).
## Returns {"ok", "why", "routes"}.
static func check(kit, pat: Dictionary, mirror: bool, speed: float, plane_z: float, top_z: float, caps: PackedFloat32Array, x_lim: float, carriers: Array, count_routes: bool = false) -> Dictionary:
	var has_crow := false
	for it in pat["items"]:
		if it["t"] == "crow":
			has_crow = true
	var aims: Array[float] = [-99.0]
	if has_crow:
		aims = []
		var a := -x_lim
		while a <= x_lim + 0.01:
			aims.append(a)
			a += 0.5
	var why := ""
	var ok := false
	for aim in aims:
		var r := _run(kit, pat, mirror, speed, plane_z, top_z, caps, x_lim, carriers, aim)
		if r == "":
			ok = true
		else:
			why = r
	if not ok:
		return {"ok": false, "why": why, "routes": 0}
	if not count_routes:   # (counting doubles the work: only the pattern checker and one smoke-test pass ask for it)
		return {"ok": true, "why": "", "routes": -1}
	var fat := caps.duplicate()
	for o in range(4, fat.size(), 5):
		fat[o] += COMFORT
	var best := 0
	last_viable = []
	for aim in aims:
		if _run(kit, pat, mirror, speed, plane_z, top_z, fat, x_lim, carriers, aim, false) == "":
			best = maxi(best, _last_routes)
	return {"ok": true, "why": "", "routes": best}

static var last_viable: Array = []   # the pruned viable cells of the latest route count (the checker's "show" mode draws them)
static var _last_routes := 0   # the route count of the latest successful _run

## The screen shapes every pattern is checked on: [top_z, plane_z] on a short and a tall screen, with the plane low and high
## in its zone (scaled with the camera's width, so zooming out keeps the same screens).
static func screen_cfgs() -> Array:
	var k: float = _tn().ortho_size / 10.0
	return [[-9.1 * k, 7.6 * k], [-10.4 * k, 8.9 * k], [-9.1 * k, 2.0 * k], [-10.4 * k, 2.4 * k]]

## How many distinct routes a play-through left. `alive[t]` = the x cells the plane can be on after step t (forward
## reachable); `frozen[t]` = it could not move at step t. Cells that cannot reach the end are dropped (dead ends), then the
## viable cells of each step are cut into intervals, and the routes are the paths through the intervals from the start to the
## end: an obstacle in the middle of open sky splits one interval into two (two routes, round the left or the right of it)
## and the two join again behind it. A wide open stretch is ONE route however wide it is. Capped at 99.
static func routes_of(alive: Array, frozen: Array, cells: int) -> int:
	var n := alive.size()
	if n == 0:
		return 0
	var ok: Array = []
	ok.resize(n)
	ok[n - 1] = alive[n - 1]
	for t in range(n - 2, -1, -1):
		var cur: PackedByteArray = (alive[t] as PackedByteArray).duplicate()
		var nx: PackedByteArray = ok[t + 1]
		var can_move: bool = int(frozen[t + 1]) <= 0
		for i in cells:
			if cur[i] == 0:
				continue
			var good := nx[i] != 0 or (can_move and ((i > 0 and nx[i - 1] != 0) or (i < cells - 1 and nx[i + 1] != 0)))
			cur[i] = 1 if good else 0
		ok[t] = cur
	last_viable = ok
	# intervals per step and the number of paths reaching each
	var prev_iv: Array = []   # [lo, hi, paths]
	for t in n:
		var cur_iv: Array = []
		var row: PackedByteArray = ok[t]
		var i := 0
		while i < cells:
			if row[i] == 0:
				i += 1
				continue
			var lo := i
			while i < cells and row[i] != 0:
				i += 1
			if i - lo >= MIN_ROUTE_CELLS:   # (a sliver of space is not a route)
				cur_iv.append([lo, i - 1, 1.0])
		if t > 0:
			var can_move2: bool = int(frozen[t]) <= 0
			for iv in cur_iv:
				var sum := 0.0
				for pv in prev_iv:
					var reach := 1 if can_move2 else 0
					if pv[0] <= iv[1] + reach and pv[1] >= iv[0] - reach:
						sum += pv[2]
				iv[2] = minf(sum, 99.0)
		prev_iv = cur_iv
	var total := 0.0
	for iv in prev_iv:
		total += iv[2]
	return int(minf(total, 99.0))

## One play-through (a fixed crow aim). "" = a path exists, else where it was lost.
static func _run(kit, pat: Dictionary, mirror: bool, speed: float, plane_z: float, top_z: float, caps: PackedFloat32Array, x_lim: float, carriers: Array, aim: float, with_hay: bool = true) -> String:
	kit.release_all()
	kit.screen_top_z = top_z
	kit.plane_z = plane_z
	kit.plane_x = 0.0
	kit.scroll_speed = speed
	kit.aim_override = aim
	var z0 := top_z - 14.0
	var rows := int(pat["rows"])
	for r in rows:
		carriers[r].position.z = z0 - r * SPACING
	kit.dropped = 0
	var no_hay: Array = []
	if not with_hay:
		for _h in (pat.get("hay", []) as Array):
			no_hay.append(false)
		if no_hay.is_empty():
			no_hay = [false]
	realize(kit, pat, mirror, carriers, no_hay)
	if kit.dropped > 0:
		return "the kit ran out of pooled things (%d) for this pattern" % kit.dropped
	var cells := int(round(2.0 * x_lim / CELL)) + 1
	var cur: Array[bool] = []
	var nxt: Array[bool] = []
	for i in cells:
		cur.append(true)
		nxt.append(false)
	var alive_log: Array = []
	var frozen_log: Array = []
	var launched := false
	var warned := false          # a crop duster's warning has started
	var freeze := 0              # steps the plane can not move yet (human reaction time after a warning)
	var has_crow := aim > -90.0
	var end_z := plane_z + 9.0
	var steps := 0
	var p := Vector2(0.0, plane_z)
	while carriers[rows - 1].position.z < end_z and steps < 2000:
		steps += 1
		for r in rows:
			carriers[r].position.z += speed * STEP
		kit.update(STEP)
		var near: Array[int] = []
		for ci in kit.col_count:
			var q: int = ci * Kit.STRIDE
			var bound: float = kit.col[q + 3] + (kit.col[q + 4] if kit.col[q] == Kit.T_RECT else 0.0) + 0.5
			if absf(kit.col[q + 2] - plane_z) < bound + 2.0:
				near.append(ci)
		if not warned:
			for e in kit.active:
				if e.kind == Kit.DUSTER and e.state >= 1:
					warned = true
					if steps <= 1:
						kit.release_all()
						return "a crop duster's warning is already running when the pattern appears (no time to warn)"
					freeze = int(ceil(_tn().duster_react / STEP))
		if has_crow and not launched:
			for e in kit.active:
				if e.kind == Kit.CROW and e.state == 2:
					launched = true
			if launched:   # the flock just chose its line: the plane must be about where it aimed
				for i in cells:
					if absf(-x_lim + i * CELL - aim) > 0.6:
						cur[i] = false
		var any := false
		for i in cells:
			var ok := false
			if cur[i] or (freeze <= 0 and ((i > 0 and cur[i - 1]) or (i < cells - 1 and cur[i + 1]))):
				ok = true
				if not near.is_empty():
					p.x = -x_lim + i * CELL
					for ci in near:
						var hit := false
						for o in range(0, caps.size(), 5):
							if kit.gap(p, caps, o, ci) < 0.0:
								hit = true
								break
						if hit:
							ok = false
							break
			nxt[i] = ok
			any = any or ok
		if not any:
			kit.release_all()
			kit.aim_override = -99.0
			return "no way through at step %d (t=%.2f s, aim %.1f)" % [steps, steps * STEP, aim]
		var snap := PackedByteArray()
		snap.resize(cells)
		for i in cells:
			snap[i] = 1 if nxt[i] else 0
		alive_log.append(snap)
		frozen_log.append(1 if freeze > 0 else 0)
		freeze = maxi(freeze - (1 if warned else 0), 0) if freeze > 0 else 0
		var tmp := cur
		cur = nxt
		nxt = tmp
	kit.release_all()
	kit.aim_override = -99.0
	_last_routes = routes_of(alive_log, frozen_log, cells)
	return ""

# ---------- the coin trails' placement check ----------

## A stand-in for the Coins pool that only remembers where coins would go.
class CoinProbe extends RefCounted:
	var pts: Array[Vector3] = []   # x, z, row index
	func spawn_line(row, x0: float, dz0: float, x1: float, dz1: float, n: int) -> int:
		for k in n:
			var t := float(k) / maxf(n - 1, 1)
			pts.append(Vector3(lerpf(x0, x1, t), row.position.z + lerpf(dz0, dz1, t), 0.0))
		return n

## What is wrong with this pattern's coin trails: a coin inside something that stands still (a barn, a power line pole or wire,
## a hay bale, a windmill's hub), or out of the plane's reach sideways. Moving things (blades, crows, balloons, kites, the tractor,
## the duster) may pass over a coin: that is the risk of the route. Returns the problems (empty = fine).
static func coin_problems(kit, pat: Dictionary, mirror: bool, carriers: Array, x_lim: float) -> Array[String]:
	var out: Array[String] = []
	kit.release_all()
	kit.plane_z = 8.0
	kit.screen_top_z = -11.0
	kit.scroll_speed = 7.0
	for r in int(pat["rows"]):
		carriers[r].position.z = -20.0 - r * SPACING
	var probe := CoinProbe.new()
	realize(kit, pat, mirror, carriers, [], -1, probe)
	kit.update(0.0)
	var dot := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.4 + 0.1])   # a coin (and a margin) as a circle
	for pt in probe.pts:
		if absf(pt.x) > x_lim + 0.4:
			out.append("a coin at x=%.1f is out of the plane's reach" % pt.x)
		for ci in kit.col_count:
			var owner: int = int(kit.col[ci * Kit.STRIDE + 7])
			var e = kit.active[owner] if owner >= 0 and owner < kit.active.size() else null
			var still: bool = e != null and (e.kind == Kit.BARN or e.kind == Kit.POWERLINE or e.kind == Kit.HAY)
			if e != null and e.kind == Kit.WINDMILL:   # (only the hub is solid ground: the blades sweep)
				still = Vector2(pt.x - e.px, pt.y - e.pz).length() < _tn().windmill_hub[int(e.a)] + 0.5
				if still:
					out.append("a coin at (%.1f, %.1f) is on a windmill hub" % [pt.x, pt.y])
				continue
			if still and kit.gap(Vector2(pt.x, pt.y), dot, 0, ci) < 0.0:
				out.append("a coin at (%.1f, %.1f) is inside a %s" % [pt.x, pt.y, Kit.NAMES[e.kind]])
	kit.release_all()
	return out
