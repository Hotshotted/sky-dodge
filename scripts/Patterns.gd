class_name Patterns
extends RefCounted
## Handcrafted Countryside patterns: short obstacle sequences (2-6 rows tall) stored as data in PatternData.gd.
##   name, diff (1-5), rows, tags, speed [lo, hi] (the scroll speeds it is built and checked for),
##   items (what stands in the way), cans / hay (optional slots: a fuel can or a hay bale MAY appear there)
## An item: {"t": kind, "r": row, "x": x, ...}. Rows are spawn_spacing apart; "dz" shifts an item down the screen (units).
## Patterns can be mirrored left <-> right. check() plays a pattern with the real Kit and finds out, with a
## search over where the plane can be, whether it can be flown at a given speed (see check()).

const SPACING := 10.0
const WALL := 5.6                       # power lines run out to here (just past the screen edge)

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

## Put the items of `pat` into the kit. carriers[r] is the row object (anything with a .position.z) that pattern row r
## hangs on. hay_fill: which hay slots are filled (empty = all of them). only_row >= 0: just that row's items (the game
## places a pattern one row at a time, as the rows come). Returns the number of things placed.
static func realize(kit, pat: Dictionary, mirror: bool, carriers: Array, hay_fill: Array = [], only_row: int = -1) -> int:
	var placed := 0
	for src in pat["items"]:
		if only_row >= 0 and int(src["r"]) != only_row:
			continue
		var it: Dictionary = mirror_item(src) if mirror else src
		var row = carriers[int(it["r"])]
		var dz: float = float(it.get("dz", 0.0))
		var x: float = float(it.get("x", 0.0))
		match String(it["t"]):
			"barn":
				kit.spawn(Kit.BARN, row, x, dz, float(it.get("hx", 1.2)))
				placed += 1
			"silo":
				kit.spawn(Kit.SILO, row, x, dz)
				placed += 1
			"windmill":
				kit.spawn(Kit.WINDMILL, row, x, dz, 0.0, 0.0, 0.0, 0.0, float(it.get("phase", 0.0)), float(it.get("dir", 1.0)))
				placed += 1
			"balloon":
				kit.spawn(Kit.BALLOON, row, x, dz, 0.0, 0.0, float(it.get("amp", _tn().balloon_amp)), float(it.get("rate", _tn().balloon_rate)), float(it.get("phase", 0.0)))
				placed += 1
			"kite":
				kit.spawn(Kit.KITE, row, x, dz, 0.0, 0.0, float(it.get("amp", _tn().kite_amp)), float(it.get("rate", _tn().kite_rate)), float(it.get("phase", 0.0)))
				placed += 1
			"powerline":
				var edges: Array[float] = [-WALL]
				for gp in it["gaps"]:
					edges.append(float(gp[0]))
					edges.append(float(gp[1]))
				edges.append(WALL)
				for i in range(0, edges.size(), 2):
					if edges[i + 1] - edges[i] > 0.4:
						kit.spawn(Kit.POWERLINE, row, edges[i], dz, edges[i + 1])
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
				kit.spawn(Kit.DUSTER, row, 0.0, dz, 0.0, 0.0, 0.0, 0.0, 0.0, float(it.get("dir", 1.0)), float(it.get("delay", 0.0)))
				placed += 1
	var slots: Array = pat.get("hay", [])
	for i in slots.size():
		if only_row >= 0 and int(slots[i]["r"]) != only_row:
			continue
		if hay_fill.is_empty() or (i < hay_fill.size() and hay_fill[i]):
			var h: Dictionary = mirror_item(slots[i]) if mirror else slots[i]
			kit.spawn(Kit.HAY, carriers[int(h["r"])], float(h["x"]), float(h.get("dz", 0.0)), 0.0, 0.0)
			placed += 1
	return placed

## Where cans MAY be placed for pattern row r: [[x, ...]] slots of that row.
static func can_slots(pat: Dictionary, row: int, mirror: bool) -> Array[float]:
	var out: Array[float] = []
	for c in pat.get("cans", []):
		if int(c["r"]) == row:
			out.append(-float(c["x"]) if mirror else float(c["x"]))
	return out

# ---------- the passability check ----------

const CELL := 0.25                      # the plane's possible x positions are searched on this grid...
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
## Returns {"ok", "why"}.
static func check(kit, pat: Dictionary, mirror: bool, speed: float, plane_z: float, top_z: float, caps: PackedFloat32Array, x_lim: float, carriers: Array) -> Dictionary:
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
	for aim in aims:
		var r := _run(kit, pat, mirror, speed, plane_z, top_z, caps, x_lim, carriers, aim)
		if r == "":
			return {"ok": true, "why": ""}
		why = r
	return {"ok": false, "why": why}

## One play-through (a fixed crow aim). "" = a path exists, else where it was lost.
static func _run(kit, pat: Dictionary, mirror: bool, speed: float, plane_z: float, top_z: float, caps: PackedFloat32Array, x_lim: float, carriers: Array, aim: float) -> String:
	kit.release_all()
	kit.screen_top_z = top_z
	kit.plane_z = plane_z
	kit.plane_x = 0.0
	kit.aim_override = aim
	var z0 := top_z - 14.0
	var rows := int(pat["rows"])
	for r in rows:
		carriers[r].position.z = z0 - r * SPACING
	kit.dropped = 0
	realize(kit, pat, mirror, carriers)
	if kit.dropped > 0:
		return "the kit ran out of pooled things (%d) for this pattern" % kit.dropped
	var cells := int(round(2.0 * x_lim / CELL)) + 1
	var cur: Array[bool] = []
	var nxt: Array[bool] = []
	for i in cells:
		cur.append(true)
		nxt.append(false)
	var launched := false
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
			if cur[i] or (i > 0 and cur[i - 1]) or (i < cells - 1 and cur[i + 1]):
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
		var tmp := cur
		cur = nxt
		nxt = tmp
	kit.release_all()
	kit.aim_override = -99.0
	return ""
