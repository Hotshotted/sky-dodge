class_name Kit
extends Node3D
## The Countryside obstacle kit: simple low-poly things built in code from a few primitives (flat-shaded,
## black outline), all pooled (every node is created once at start-up and reused).
##   BARN              closed: a static blocker; with a doorway: a fly-through (flying straight through is a Barnstormer)
##   TRACTOR           drives sideways across the lane, dust plume first, and drops hay bales behind it
##   WINDMILL          static base, turning blades that sweep part of the lane
##   CROW              a flock enters from the top: it hovers at the edge (telegraph), then swoops toward where the
##                     plane is at that moment and flies straight on (never homing once it has started)
##   BALLOON           big and slow, drifts sideways so gaps shift
##   POWERLINE         a wire between two poles (gaps beside the poles); touching the wire crashes
##   DUSTER            another plane crossing the screen sideways, announced by an arrow at the edge ~1 s before
##   KITE              small, wiggles side to side
##   HAY               a hay bale: the Countryside's crate (same rules, same colour-coded glow)
## Every thing has colliders (rectangles / circles) built from the SAME numbers as its model, so the hit shape is
## what you see. Things belong to a "carrier" row of the Spawner: its z is their clock and, for most, their position.

enum { BARN, TRACTOR, WINDMILL, CROW, BALLOON, POWERLINE, DUSTER, KITE, HAY }
const NAMES := ["barn", "tractor", "windmill", "crow", "balloon", "powerline", "duster", "kite", "hay"]
const POOL := [10, 4, 6, 14, 6, 10, 3, 6, 16]
const STRIDE := 10           # collider floats: type, cx, cz, hx (radius for circles), hz, cos, sin, owner, flags, bounding radius
const MAX_COLLIDERS := 96
const T_RECT := 0.0
const T_CIRCLE := 1.0
const F_HAY := 1.0
const NEAR_RANGE := 5.0
const HAY_HALF := Vector2(0.6, 0.55)     # hay bale: half width (x), half depth (z)
const BARN_DEPTH := 1.3
const BARN_LONG := 1.9                   # a fly-through barn is longer than a closed one
const WALLS := [0.6, 1.0, 1.6]           # wall thicknesses a fly-through barn comes in
const BALLOON_RADIUS := 1.3
const KITE_RADIUS := 0.42
const CROW_RADIUS := 0.34
const POLE_HALF := 0.22
const WIRE_HALF := 0.1
const DUSTER_BODY := Vector2(0.85, 0.22)  # fuselage half size (x along the flight, z)
const DUSTER_WING := Vector2(0.3, 1.2)    # wing half size (x, z)

class Ent extends Node3D:
	var kind := 0
	var in_use := false
	var row = null                     # the carrier Spawner.Row
	var x0 := 0.0                      # base x
	var dz := 0.0                      # z offset from the carrier row
	var a := 0.0
	var b := 0.0
	var amp := 0.0
	var rate := 0.0
	var phase := 0.0
	var dir := 1.0
	var leader: Ent = null             # crows: the first of the flock (its aim is shared)
	var aim_x := 0.0
	var aim_set := false
	var delay := 0.0                   # extra seconds before a crow / duster starts its telegraph
	var age := 0.0
	var state := 0                     # crow / duster: 0 waiting for its row, 1 telegraph, 2 flying
	var state_age := 0.0
	var px := 0.0                      # where it is now (world x, z)
	var pz := 0.0
	var vx := 0.0
	var vz := 0.0
	var ang := 0.0                     # windmill blade angle
	var solid := true                  # has colliders right now
	var min_clear := INF               # closest approach so far (for close calls)
	var min_side := 1
	var entered := false
	var passed := false
	var crate_kind := 0                # hay: 1 gold / 2 green / 3 purple, 0 once broken
	var reach := Vector2.ZERO          # bounding half size (x, z)
	var parts: Array[MeshInstance3D] = []
	var outline: ShaderMaterial
	var pivot: Node3D                  # the turning blades / flapping wings
	var wing_l: Node3D
	var wing_r: Node3D
	var glow: MeshInstance3D           # hay: the contents glow
	var ghost: MeshInstance3D          # Cloud Eye frame
	var arrow: Node3D                  # duster / tractor: the telegraph (world coordinates)
	var rig: Node3D                    # duster / tractor: the model, turned the way it goes
	var thru := 0                      # barn: frames the plane was inside the doorway
	var arrow_mesh: Node3D             # duster: the arrow, the glowing edge and the row line (kept so nothing is looked up per frame)
	var edge_node: Node3D
	var line_node: Node3D
	var puffs: Array[Node3D] = []      # tractor: the dust plume's puffs
	var drops := 0                     # tractor: bales dropped so far
	var drop_t := 0.0
	var tail: Node3D
	var col_first := 0
	var col_n := 0

var ghost_mesh: Mesh               # set by the Spawner (Cloud Eye frame)
var ghost_mat: Material
var _shader: Shader = preload("res://shaders/outline_part.gdshader")
var _all: Array[Ent] = []
var _free: Array = []              # per kind: Array of free Ents
var active: Array[Ent] = []
var col := PackedFloat32Array()    # the colliders of everything in play, rebuilt each update()
var col_count := 0
var screen_top_z := -9.0           # set by the Spawner: the top edge of the screen (world z)
var plane_x := 0.0
var plane_z := 0.0
var _mats := {}
var _meshes := {}
var glow_mats: Array[StandardMaterial3D] = []
var arrow_mat := StandardMaterial3D.new()
var warn_mat := StandardMaterial3D.new()
var warn_line_mat := StandardMaterial3D.new()
var scroll_speed := 7.0            # set by the Spawner: the dusters time their warning by it   # the crop duster's red edge glow and row line
var last_hit_hay := false
var dropped := 0                   # spawn() calls that found their pool empty (tests expect 0)
var aim_override := -99.0          # the validator forces where a crow flock aims

func _ready() -> void:
	col.resize(MAX_COLLIDERS * STRIDE)
	for k in 3:
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Tuning.crate_colors[k]
		glow_mats.append(gm)
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_mat.albedo_color = Color(1.0, 0.35, 0.1)
	arrow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	warn_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	warn_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warn_mat.albedo_color = Color(1.0, 0.1, 0.05, 0.3)
	warn_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	warn_mat.render_priority = 3
	warn_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	warn_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warn_line_mat.albedo_color = Color(1.0, 0.1, 0.05, 0.2)
	warn_line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	warn_line_mat.render_priority = 3
	for k in POOL.size():
		var lst: Array[Ent] = []
		_free.append(lst)
		for i in POOL[k]:
			var e := _build(k)
			_all.append(e)
			lst.append(e)
	for h in [0.8, 1.2, 1.6, 2.0, 2.4]:   # every size a barn / wire can have, built now (nothing is made during a run)
		_box(2.0 * h, 0.5, 2.0 * BARN_DEPTH)
		_wedge(2.0 * h + 0.1, 0.24, 2.0 * BARN_DEPTH + 0.1)
	for i in range(1, 25):
		_box(0.5 * i, 0.05, 2.0 * WIRE_HALF)
	for w in WALLS:
		_box(w, 0.5, 2.0 * BARN_LONG)
		_box(w + 0.1, 0.12, 2.0 * BARN_LONG + 0.1)
	_box(Tuning.barn_door_width, 0.02, 2.0 * BARN_LONG)
	for v in 3:
		_box(Tuning.windmill_blade[v], 0.05, 2.0 * Tuning.windmill_width[v])
		_cyl(Tuning.windmill_hub[v], Tuning.windmill_hub[v] * 0.6, 0.5, 8)

# ---------- meshes and materials ----------

func _mat(c: Color, vertex_colors: bool = false) -> StandardMaterial3D:
	var key := "%s%s" % [c.to_html(), "v" if vertex_colors else ""]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 1.0
		m.metallic_specular = 0.0
		m.vertex_color_use_as_albedo = vertex_colors
		_mats[key] = m
	return _mats[key]

func _box(w: float, h: float, d: float) -> BoxMesh:
	var key := "box%.3f,%.3f,%.3f" % [w, h, d]
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = Vector3(w, h, d)
		_meshes[key] = m
	return _meshes[key]

## One flat-shaded triangle (its own normal, one colour), wound to face away from the part's centre.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.dot((a + b + c) / 3.0) < 0.0:
		var tmp := b
		b = c
		c = tmp
		n = -n
	n = n.normalized()
	for v in [a, c, b]:
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(v)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_tri(st, a, b, c, color)
	_tri(st, a, c, d, color)

## A low-poly cylinder / cone (rb = bottom radius, rt = top radius), `seg` sides, centred on its origin.
func _cyl(rb: float, rt: float, h: float, seg: int) -> ArrayMesh:
	var key := "cyl%.3f,%.3f,%.3f,%d" % [rb, rt, h, seg]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := Color.WHITE
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var b0 := Vector3(cos(a0) * rb, -h * 0.5, sin(a0) * rb)
		var b1 := Vector3(cos(a1) * rb, -h * 0.5, sin(a1) * rb)
		var t0 := Vector3(cos(a0) * rt, h * 0.5, sin(a0) * rt)
		var t1 := Vector3(cos(a1) * rt, h * 0.5, sin(a1) * rt)
		_quad(st, b0, b1, t1, t0, white)
		_tri(st, Vector3(0, h * 0.5, 0), t0, t1, white)
		_tri(st, Vector3(0, -h * 0.5, 0), b1, b0, white)
	var m := ArrayMesh.new()
	st.commit(m)
	_meshes[key] = m
	return m

## A low-poly ellipsoid (half = true: only the top half), alternating two colours around it when `stripes`.
func _ball(rx: float, ry: float, rz: float, seg: int, lat: int, half: bool, c1: Color, c2: Color) -> ArrayMesh:
	var key := "ball%.3f,%.3f,%.3f,%d,%d,%s,%s,%s" % [rx, ry, rz, seg, lat, str(half), c1.to_html(), c2.to_html()]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := lat * (1 if half else 2)
	for r in rings:
		var t0 := PI * 0.5 * r / lat
		var t1 := PI * 0.5 * (r + 1) / lat
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var col_i := c1 if i % 2 == 0 else c2
			var p00 := Vector3(rx * sin(t0) * cos(a0), ry * cos(t0), rz * sin(t0) * sin(a0))
			var p01 := Vector3(rx * sin(t0) * cos(a1), ry * cos(t0), rz * sin(t0) * sin(a1))
			var p10 := Vector3(rx * sin(t1) * cos(a0), ry * cos(t1), rz * sin(t1) * sin(a0))
			var p11 := Vector3(rx * sin(t1) * cos(a1), ry * cos(t1), rz * sin(t1) * sin(a1))
			if r == 0:
				_tri(st, p00, p10, p11, col_i)
			else:
				_quad(st, p00, p10, p11, p01, col_i)
	if half:   # a flat underside
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			_tri(st, Vector3.ZERO, Vector3(rx * cos(a1), 0, rz * sin(a1)), Vector3(rx * cos(a0), 0, rz * sin(a0)), c1)
	var m := ArrayMesh.new()
	st.commit(m)
	_meshes[key] = m
	return m

## A roof: a triangular prism with its ridge along x.
func _wedge(w: float, h: float, d: float) -> ArrayMesh:
	var key := "wedge%.3f,%.3f,%.3f" % [w, h, d]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color.WHITE
	var a := Vector3(-w * 0.5, -h * 0.5, -d * 0.5)
	var b := Vector3(w * 0.5, -h * 0.5, -d * 0.5)
	var cc := Vector3(w * 0.5, -h * 0.5, d * 0.5)
	var dd := Vector3(-w * 0.5, -h * 0.5, d * 0.5)
	var r0 := Vector3(-w * 0.5, h * 0.5, 0)
	var r1 := Vector3(w * 0.5, h * 0.5, 0)
	_quad(st, a, b, cc, dd, c)
	_quad(st, a, b, r1, r0, c)
	_quad(st, dd, cc, r1, r0, c)
	_tri(st, a, dd, r0, c)
	_tri(st, b, cc, r1, c)
	var m := ArrayMesh.new()
	st.commit(m)
	_meshes[key] = m
	return m

## The telegraph arrow (flat, pointing +x), 1.2 long.
func _arrow() -> ArrayMesh:
	if _meshes.has("arrow"):
		return _meshes["arrow"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color.WHITE
	var t := 0.04
	var pts := [Vector2(0.6, 0.0), Vector2(0.0, 0.55), Vector2(0.0, 0.2), Vector2(-0.6, 0.2), Vector2(-0.6, -0.2), Vector2(0.0, -0.2), Vector2(0.0, -0.55)]
	for y in [t, -t]:   # two faces (fan from the tip)
		for i in range(1, pts.size() - 1):
			var A := Vector3(pts[0].x, y, pts[0].y)
			var B := Vector3(pts[i].x, y, pts[i].y)
			var C := Vector3(pts[i + 1].x, y, pts[i + 1].y)
			var n := (B - A).cross(C - A)
			if (n.y > 0.0) != (y > 0.0):
				var tmp := B
				B = C
				C = tmp
			for v in [A, C, B]:
				st.set_normal(Vector3(0, 1 if y > 0.0 else -1, 0))
				st.set_color(c)
				st.add_vertex(v)
	var m := ArrayMesh.new()
	st.commit(m)
	_meshes["arrow"] = m
	return m

# ---------- building the pooled things ----------

func _part(e: Ent, mesh: Mesh, color: Color, pos: Vector3, parent: Node3D = null, vertex_colors: bool = false, outlined: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color, vertex_colors)
	if outlined:
		mi.material_overlay = e.outline
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	(parent if parent != null else e).add_child(mi)
	e.parts.append(mi)
	return mi

func _build(kind: int) -> Ent:
	var e := Ent.new()
	e.kind = kind
	e.outline = ShaderMaterial.new()
	e.outline.shader = _shader
	e.outline.set_shader_parameter("thickness", Tuning.outline_thickness)
	match kind:
		BARN:   # closed: part 0 body + part 1 roof. Fly-through: parts 0/1 left wall + roof, 2/3 right wall + roof, 4 floor
			_part(e, _box(2.0, 0.5, 2.0), Color(0.78, 0.22, 0.18), Vector3(0, 0.15, 0))
			_part(e, _wedge(2.0, 0.24, 2.0), Color(0.5, 0.13, 0.11), Vector3(0, 0.52, 0))
			_part(e, _box(2.0, 0.5, 2.0), Color(0.78, 0.22, 0.18), Vector3(0, 0.15, 0))
			_part(e, _box(2.0, 0.12, 2.0), Color(0.5, 0.13, 0.11), Vector3(0, 0.5, 0))
			_part(e, _box(2.0, 0.02, 2.0), Color(0.8, 0.7, 0.5), Vector3(0, 0.0, 0), null, false, false)
		TRACTOR:   # drives along +x of its rig (the rig turns it the way it goes)
			e.rig = Node3D.new()
			e.add_child(e.rig)
			_part(e, _box(1.1, 0.34, 0.8), Color(0.2, 0.62, 0.3), Vector3(0, 0.2, 0), e.rig)
			_part(e, _box(0.7, 0.26, 0.5), Color(0.15, 0.5, 0.25), Vector3(0.85, 0.16, 0), e.rig)
			_part(e, _box(0.5, 0.3, 0.6), Color(0.95, 0.85, 0.3), Vector3(-0.2, 0.5, 0), e.rig)
			for sz in [-1.0, 1.0]:
				_part(e, _box(0.5, 0.3, 0.14), Color(0.15, 0.15, 0.17), Vector3(-0.45, 0.12, 0.5 * sz), e.rig)
				_part(e, _box(0.3, 0.22, 0.12), Color(0.15, 0.15, 0.17), Vector3(0.85, 0.08, 0.38 * sz), e.rig)
			e.arrow = Node3D.new()   # the dust plume at the edge it will drive in from (world coordinates)
			for k in 3:
				var puff := MeshInstance3D.new()
				puff.mesh = _box(0.4, 0.4, 0.4)
				puff.material_override = _mat(Color(0.82, 0.72, 0.52))
				puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				puff.position = Vector3(0.0, 0.4, 0.0)
				e.arrow.add_child(puff)
				e.puffs.append(puff)
			add_child(e.arrow)
			e.arrow.visible = false
		WINDMILL:   # tower and hub; the blades (up to 4) turn on the pivot and are sized when it is spawned
			_part(e, _cyl(0.85, 0.5, 0.5, 8), Color(0.92, 0.86, 0.7), Vector3(0, 0.2, 0))
			_part(e, _cyl(0.22, 0.22, 0.18, 8), Color(0.45, 0.3, 0.2), Vector3(0, 0.52, 0))
			e.pivot = Node3D.new()
			e.pivot.position = Vector3(0, 0.6, 0)
			e.add_child(e.pivot)
			for k in 4:
				_part(e, _box(1.0, 0.05, 0.4), Color(0.78, 0.6, 0.38) if k % 2 == 0 else Color(0.86, 0.7, 0.45), Vector3(0, 0.001 * k, 0), e.pivot)
		CROW:
			_part(e, _box(0.3, 0.12, 0.44), Color(0.2, 0.2, 0.24), Vector3(0, 0.4, 0))
			_part(e, _box(0.12, 0.1, 0.12), Color(0.95, 0.6, 0.15), Vector3(0, 0.4, -0.28), null, false, false)
			e.wing_l = Node3D.new()
			e.wing_r = Node3D.new()
			e.wing_l.position = Vector3(-0.15, 0.4, 0)
			e.wing_r.position = Vector3(0.15, 0.4, 0)
			e.add_child(e.wing_l)
			e.add_child(e.wing_r)
			_part(e, _box(0.34, 0.04, 0.26), Color(0.3, 0.3, 0.36), Vector3(-0.17, 0, 0), e.wing_l)
			_part(e, _box(0.34, 0.04, 0.26), Color(0.3, 0.3, 0.36), Vector3(0.17, 0, 0), e.wing_r)
		BALLOON:
			_part(e, _ball(BALLOON_RADIUS, 0.3, BALLOON_RADIUS, 10, 2, false, Color(0.9, 0.25, 0.25), Color(0.98, 0.85, 0.3)), Color.WHITE, Vector3(0, 0.3, 0), null, true)
			_part(e, _box(0.4, 0.2, 0.4), Color(0.55, 0.38, 0.22), Vector3(0, 0.2, 0), null, false, false)
		POWERLINE:   # sized when spawned
			_part(e, _box(1.0, 0.05, 2.0 * WIRE_HALF), Color(0.55, 0.57, 0.62), Vector3(0, 0.4, 0))
			_part(e, _box(2.0 * POLE_HALF, 0.55, 2.0 * POLE_HALF), Color(0.5, 0.36, 0.22), Vector3(0, 0.12, 0))
			_part(e, _box(2.0 * POLE_HALF, 0.55, 2.0 * POLE_HALF), Color(0.5, 0.36, 0.22), Vector3(0, 0.12, 0))
			_part(e, _box(1.0, 0.07, 0.16), Color(0.42, 0.3, 0.18), Vector3(0, 0.44, 0), null, false, false)
			_part(e, _box(1.0, 0.07, 0.16), Color(0.42, 0.3, 0.18), Vector3(0, 0.44, 0), null, false, false)
		DUSTER:   # flies along +x of its rig
			e.rig = Node3D.new()
			e.add_child(e.rig)
			_part(e, _box(2.0 * DUSTER_BODY.x, 0.2, 2.0 * DUSTER_BODY.y), Color(0.95, 0.85, 0.2), Vector3(0, 0.4, 0), e.rig)
			_part(e, _box(2.0 * DUSTER_WING.x, 0.06, 2.0 * DUSTER_WING.y), Color(0.2, 0.65, 0.35), Vector3(0.1, 0.42, 0), e.rig)
			_part(e, _box(0.34, 0.05, 0.9), Color(0.2, 0.65, 0.35), Vector3(-0.75, 0.42, 0), e.rig)
			e.pivot = Node3D.new()
			e.pivot.position = Vector3(0.92, 0.4, 0)
			e.rig.add_child(e.pivot)
			_part(e, _box(0.06, 0.04, 0.8), Color(0.3, 0.3, 0.3), Vector3.ZERO, e.pivot, false, false)
			e.arrow = Node3D.new()   # the arrow, the glowing edge and the red row line: world coordinates, children of the kit
			var ar := MeshInstance3D.new()
			ar.mesh = _arrow()
			ar.material_override = arrow_mat
			ar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			e.arrow.add_child(ar)
			e.arrow_mesh = ar
			var edge_glow := MeshInstance3D.new()
			edge_glow.mesh = _box(0.9, 0.02, 34.0)
			edge_glow.material_override = warn_mat
			edge_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			edge_glow.name = "edge"
			e.arrow.add_child(edge_glow)
			e.edge_node = edge_glow
			var row_line := MeshInstance3D.new()
			row_line.mesh = _box(Tuning.ortho_size, 0.02, 0.2)
			row_line.material_override = warn_line_mat
			row_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			row_line.name = "line"
			e.arrow.add_child(row_line)
			e.line_node = row_line
			add_child(e.arrow)
			e.arrow.visible = false
		KITE:
			var dia := _part(e, _box(0.6, 0.04, 0.6), Color(0.95, 0.3, 0.55), Vector3(0, 0.5, 0))
			dia.rotation.y = PI * 0.25
			e.tail = Node3D.new()
			e.tail.position = Vector3(0, 0.5, 0.45)
			e.add_child(e.tail)
			for k in 3:
				_part(e, _box(0.14, 0.03, 0.14), Color(0.98, 0.85, 0.3) if k % 2 == 0 else Color(0.3, 0.7, 0.95), Vector3(0, 0, 0.22 * k), e.tail, false, false)
			_part(e, _box(0.04, 0.02, 5.0), Color(0.85, 0.85, 0.9), Vector3(0, 0.45, 2.9), null, false, false)   # the string (not solid)
		HAY:
			var bale := _part(e, _cyl(0.5, 0.5, 1.1, 8), Color(0.92, 0.78, 0.3), Vector3(0, 0.0, 0))
			bale.rotation.z = PI * 0.5
			e.glow = MeshInstance3D.new()
			e.glow.mesh = _box(0.8, 0.04, 0.6)
			e.glow.material_override = glow_mats[0]
			e.glow.position = Vector3(0, 0.52, 0)
			e.glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			e.add_child(e.glow)
	if ghost_mesh != null:
		e.ghost = MeshInstance3D.new()
		e.ghost.mesh = ghost_mesh
		e.ghost.material_override = ghost_mat
		e.ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.ghost.visible = false
		add_child(e.ghost)
	e.visible = false
	add_child(e)
	return e

# ---------- spawning ----------

## Put a thing in play, attached to a carrier row. See Ent for what each number means per kind.
func spawn(kind: int, row, x0: float, dz: float, a: float = 0.0, b: float = 0.0, amp: float = 0.0, rate: float = 0.0, phase: float = 0.0, dir: float = 1.0, delay: float = 0.0) -> Ent:
	var lst: Array = _free[kind]
	if lst.is_empty():
		dropped += 1
		return null
	var e: Ent = lst.pop_back()
	e.row = row
	e.x0 = x0
	e.dz = dz
	e.a = a
	e.b = b
	e.amp = amp
	e.rate = rate
	e.phase = phase
	e.dir = dir
	e.delay = delay
	e.leader = null
	e.aim_set = false
	e.age = 0.0
	e.state = 0
	e.state_age = 0.0
	e.min_clear = INF
	e.entered = false
	e.passed = false
	e.solid = true
	e.ang = phase
	e.crate_kind = 0
	e.in_use = true
	_setup(e)
	active.append(e)
	_pose(e, 0.0)
	e.visible = e.kind != CROW and e.kind != DUSTER or e.state > 0
	return e

## Size the parts of a thing for its parameters (barns and power lines come in several sizes).
func _setup(e: Ent) -> void:
	match e.kind:
		BARN:
			var open := e.b > 0.5
			if open:   # fly-through: two walls with a doorway between them
				var wall: float = WALLS[0]
				for w in WALLS:
					if absf(w - e.a) < absf(wall - e.a):
						wall = w
				e.a = wall
				var c: float = Tuning.barn_door_width * 0.5 + wall * 0.5
				e.reach = Vector2(Tuning.barn_door_width * 0.5 + wall, BARN_LONG)
				e.parts[0].mesh = _box(wall, 0.5, 2.0 * BARN_LONG)
				e.parts[0].position = Vector3(-c, 0.15, 0)
				e.parts[1].mesh = _box(wall + 0.1, 0.12, 2.0 * BARN_LONG + 0.1)
				e.parts[1].position = Vector3(-c, 0.5, 0)
				e.parts[2].mesh = _box(wall, 0.5, 2.0 * BARN_LONG)
				e.parts[2].position = Vector3(c, 0.15, 0)
				e.parts[3].mesh = _box(wall + 0.1, 0.12, 2.0 * BARN_LONG + 0.1)
				e.parts[3].position = Vector3(c, 0.5, 0)
				e.parts[4].mesh = _box(Tuning.barn_door_width, 0.02, 2.0 * BARN_LONG)
				for k in 5:
					e.parts[k].visible = true
			else:
				var hx := snappedf(e.a, 0.4)
				e.a = hx
				e.reach = Vector2(hx, BARN_DEPTH)
				e.parts[0].mesh = _box(2.0 * hx, 0.5, 2.0 * BARN_DEPTH)
				e.parts[0].position = Vector3(0, 0.15, 0)
				e.parts[1].mesh = _wedge(2.0 * hx + 0.1, 0.24, 2.0 * BARN_DEPTH + 0.1)
				e.parts[1].position = Vector3(0, 0.52, 0)
				e.parts[0].visible = true
				e.parts[1].visible = true
				for k in range(2, 5):
					e.parts[k].visible = false
			e.thru = 0
		TRACTOR:
			e.reach = Vector2(1.3, 0.6)
			e.drops = 0
			e.drop_t = 0.0
			e.rig.rotation.y = 0.0 if e.dir > 0.0 else PI
			e.arrow.visible = false
		WINDMILL:
			var v := clampi(int(e.a), 0, 2)
			e.a = v
			var n: int = Tuning.windmill_blades[v]
			var len: float = Tuning.windmill_blade[v]
			e.reach = Vector2(len, len)
			# Set once, here: the start angle that puts the blades at `phase` when this row reaches the plane's row, at the
			# scroll speed now (speed only changes in BREATHER steps, and windmill patterns are never chosen around one).
			var to_plane: float = (plane_z - _carrier_z(e)) / maxf(scroll_speed, 1.0)
			e.phase = e.phase - e.dir * Tuning.windmill_speed[v] * to_plane
			e.parts[0].mesh = _cyl(Tuning.windmill_hub[v], Tuning.windmill_hub[v] * 0.6, 0.5, 8)
			for k in 4:
				var bl: MeshInstance3D = e.parts[2 + k]
				bl.visible = k < n
				if k < n:
					var phi := TAU * k / n
					bl.mesh = _box(len, 0.05, 2.0 * Tuning.windmill_width[v])
					bl.position = Vector3(cos(phi) * len * 0.5, 0.001 * k, sin(phi) * len * 0.5)
					bl.rotation.y = -phi
		CROW:
			e.reach = Vector2(CROW_RADIUS, CROW_RADIUS)
		BALLOON:
			e.reach = Vector2(BALLOON_RADIUS, BALLOON_RADIUS)
		POWERLINE:
			var xa := minf(e.x0, e.a)
			var len := maxf(0.5, snappedf(absf(e.a - e.x0), 0.5))   # wires come in 0.5 steps
			e.x0 = xa
			e.a = xa + len
			var xb := e.a
			e.reach = Vector2(len * 0.5 + POLE_HALF, POLE_HALF)
			(e.parts[0]).mesh = _box(len, 0.05, 2.0 * WIRE_HALF)
			(e.parts[0]).position = Vector3(0.0, 0.4, 0.0)
			(e.parts[1]).position = Vector3(xa - (xa + xb) * 0.5, 0.12, 0.0)
			(e.parts[2]).position = Vector3(xb - (xa + xb) * 0.5, 0.12, 0.0)
			(e.parts[3]).position = Vector3(xa - (xa + xb) * 0.5, 0.44, 0.0)
			(e.parts[4]).position = Vector3(xb - (xa + xb) * 0.5, 0.44, 0.0)
			(e.parts[3]).mesh = _box(0.9, 0.07, 0.16)
			(e.parts[4]).mesh = _box(0.9, 0.07, 0.16)
		DUSTER:
			e.reach = Vector2(DUSTER_BODY.x + 0.4, DUSTER_WING.y)
			e.rig.rotation.y = 0.0 if e.dir > 0.0 else PI   # the nose points the way it flies
		KITE:
			e.reach = Vector2(KITE_RADIUS, KITE_RADIUS)
		HAY:
			e.reach = HAY_HALF
			var ck := int(e.b)
			if ck < 1 or ck > 3:   # contents by the usual odds (gold / green / purple)
				var roll := randf()
				var acc := 0.0
				ck = 3
				for i in 3:
					acc += Tuning.crate_weights[i]
					if roll <= acc:
						ck = i + 1
						break
			e.crate_kind = ck
			e.glow.material_override = glow_mats[ck - 1]
			e.glow.visible = true
			e.parts[0].visible = true
	if e.ghost != null:
		e.ghost.scale = Vector3(2.0 * e.reach.x + 0.3, 1.0, 2.0 * e.reach.y + 0.3)
	e.rotation = Vector3.ZERO

func release(e: Ent) -> void:
	e.visible = false
	e.in_use = false
	e.row = null
	if e.ghost != null:
		e.ghost.visible = false
	if e.arrow != null:
		e.arrow.visible = false
	var i := active.find(e)
	if i >= 0:
		active.remove_at(i)
	(_free[e.kind] as Array).append(e)

func release_row(row) -> void:
	for i in range(active.size() - 1, -1, -1):
		if active[i].row == row:
			release(active[i])

func release_all() -> void:
	for i in range(active.size() - 1, -1, -1):
		release(active[i])
	col_count = 0

# ---------- motion ----------

func _carrier_z(e: Ent) -> float:
	return (e.row.position.z if e.row != null else 0.0) + e.dz

## Where a thing is at `delta` after its last update, and what its parts do. Crows and the duster are in SCREEN space
## (they fly on their own); everything else is carried along by its row.
func _pose(e: Ent, delta: float) -> void:
	match e.kind:
		BARN, HAY:
			e.px = e.x0
			e.pz = _carrier_z(e)
		TRACTOR:
			_pose_tractor(e, delta)
		WINDMILL:
			e.px = e.x0
			e.pz = _carrier_z(e)
			# constant angular speed on the simulation clock (e.age): nothing the plane does can change it. The starting angle
			# was set once at spawn (see _setup) so that the blades show `phase` when the row reaches the plane.
			e.ang = e.phase + e.dir * Tuning.windmill_speed[int(e.a)] * e.age
			e.pivot.rotation.y = -e.ang
		BALLOON:
			e.px = clampf(e.x0 + e.amp * sin(e.rate * e.age + e.phase), -4.4, 4.4)
			e.pz = _carrier_z(e)
		KITE:
			e.px = clampf(e.x0 + e.amp * sin(e.rate * e.age + e.phase), -4.4, 4.4)
			e.pz = _carrier_z(e)
			e.tail.rotation.y = sin(e.age * 5.0) * 0.5
		POWERLINE:
			e.px = (e.x0 + e.a) * 0.5
			e.pz = _carrier_z(e)
		CROW:
			_pose_crow(e, delta)
		DUSTER:
			_pose_duster(e, delta)
	e.position = Vector3(e.px, 0.0, e.pz)
	if e.ghost != null:
		e.ghost.position = Vector3(e.px, 1.012, e.pz)

func _trigger_z() -> float:
	return screen_top_z - 1.0

func _pose_crow(e: Ent, delta: float) -> void:
	e.state_age += delta
	match e.state:
		0:   # waiting for the row to come into view
			e.solid = false
			e.visible = false
			e.px = e.x0 + e.a
			e.pz = screen_top_z - 3.0 + e.b
			if e.row != null and _carrier_z(e) >= _trigger_z():
				e.state = 1
				e.state_age = 0.0
				e.visible = true
		1:   # hovering at the top edge: the warning
			e.solid = false
			e.px = e.x0 + e.a
			e.pz = screen_top_z + 0.8 + e.b * 0.6
			e.wing_l.rotation.z = sin(e.age * 22.0) * 0.6
			e.wing_r.rotation.z = -sin(e.age * 22.0) * 0.6
			if e.state_age >= Tuning.crow_telegraph + e.delay:
				# the swoop: toward where the plane IS right now, then a straight line. Never re-aimed.
				var lead: Ent = e.leader if e.leader != null else e
				if not lead.aim_set:
					lead.aim_x = aim_override if aim_override > -90.0 else plane_x
					lead.aim_set = true
				var aim := Vector2(lead.aim_x + e.amp, plane_z)
				var d := (aim - Vector2(e.px, e.pz))
				d = d.normalized() if d.length() > 0.001 else Vector2(0, 1)
				e.vx = d.x * Tuning.crow_speed
				e.vz = d.y * Tuning.crow_speed
				e.state = 2
				e.state_age = 0.0
				e.solid = true
		2:
			e.px += e.vx * delta
			e.pz += e.vz * delta
			e.wing_l.rotation.z = sin(e.age * 16.0) * 0.5
			e.wing_r.rotation.z = -sin(e.age * 16.0) * 0.5
			e.rotation.y = atan2(-e.vx, -e.vz) if false else 0.0
	if e.state == 2:
		e.rotation.y = atan2(e.vx, e.vz) + PI   # the beak points the way it flies
	else:
		e.rotation.y = 0.0

func _pose_tractor(e: Ent, delta: float) -> void:
	e.state_age += delta
	var edge := Tuning.ortho_size * 0.5 + 1.4
	e.pz = _carrier_z(e)
	match e.state:
		0:   # waiting for its row to come close to the screen
			e.solid = false
			e.visible = false
			e.px = -e.dir * edge
			if e.row != null and e.pz >= _trigger_z() - Tuning.tractor_lead:
				e.state = 1
				e.state_age = 0.0
		1:   # a dust plume at the edge it will drive in from
			e.solid = false
			e.visible = false
			e.px = -e.dir * edge
			e.arrow.visible = true
			e.arrow.position = Vector3(-e.dir * (Tuning.ortho_size * 0.5 - 0.7), 0.0, e.pz)
			for k in e.puffs.size():
				var puff := e.puffs[k]
				var t := fposmod(e.state_age * 1.6 + k * 0.33, 1.0)
				puff.position = Vector3(e.dir * t * 0.9, 0.3 + t * 0.7, (k - 1) * 0.45)
				puff.scale = Vector3.ONE * (0.6 + t * 1.1) * (1.0 - t * 0.5)
			if e.state_age >= Tuning.tractor_telegraph:
				e.state = 2
				e.state_age = 0.0
				e.arrow.visible = false
				e.solid = true
				e.visible = true
		2:
			e.px = -e.dir * edge + e.dir * Tuning.tractor_speed * e.state_age
			e.drop_t += delta
			if e.drops < Tuning.tractor_drops and e.drop_t >= Tuning.tractor_drop_every and absf(e.px) < Tuning.ortho_size * 0.5 - 0.2:
				e.drop_t = 0.0
				e.drops += 1
				spawn(HAY, e.row, e.px - e.dir * 1.5, e.dz, 0.0, 0.0)   # a bale behind it (its contents by the usual odds)

func _pose_duster(e: Ent, delta: float) -> void:
	e.state_age += delta
	var edge := Tuning.ortho_size * 0.5 + 1.4
	e.pz = _carrier_z(e)
	var half := Tuning.ortho_size * 0.5
	match e.state:
		0:   # waiting until it is time to warn: the telegraph, plus the delay and the wait before it reaches the plane row
			e.solid = false
			e.visible = false
			e.px = -e.dir * edge
			if e.row != null and (plane_z - e.pz) / maxf(scroll_speed, 1.0) <= Tuning.duster_telegraph + e.delay + e.a:
				e.state = 1
				e.state_age = 0.0
		1:   # the warning (drawn below): it ends when the duster enters
			e.solid = false
			e.visible = false
			e.px = -e.dir * edge
			if e.state_age >= Tuning.duster_telegraph + e.delay:
				e.state = 2
				e.state_age = 0.0
				e.arrow.visible = false
				e.solid = true
				e.visible = true
		2:
			e.px = -e.dir * edge + e.dir * Tuning.duster_speed * e.state_age
			e.pivot.rotation.x += delta * 40.0
	if e.state == 1:   # the edge it comes from glows red and pulses, a faint red line marks its row, an arrow points in
		e.arrow.visible = true
		var pulse := 0.5 + 0.5 * sin(e.state_age * 11.0)
		warn_mat.albedo_color = Color(1.0, 0.08, 0.05, 0.18 + 0.32 * pulse)
		warn_line_mat.albedo_color = Color(1.0, 0.1, 0.05, 0.2)
		arrow_mat.albedo_color = Color(1.0, 0.35, 0.1) * (0.6 + 0.4 * pulse)
		e.arrow.position = Vector3.ZERO
		e.arrow_mesh.position = Vector3(-e.dir * (half - 1.3), 0.5, screen_top_z + 1.6)
		e.arrow_mesh.rotation.y = 0.0 if e.dir > 0.0 else PI
		e.edge_node.position = Vector3(-e.dir * (half - 0.45), 1.45, plane_z - 9.0)
		e.line_node.position = Vector3(0.0, 0.3, e.pz)

## Advance everything (called each frame by the Spawner after the rows have moved).
func update(delta: float) -> void:
	for i in range(active.size() - 1, -1, -1):
		var e := active[i]
		e.age += delta
		_pose(e, delta)
		if e.kind != CROW and e.kind != DUSTER and e.pz - e.reach.y > plane_z + 12.0:   # long gone off the bottom
			release(e)
		elif e.kind == CROW and e.state == 2 and (e.pz > plane_z + 9.0 or absf(e.px) > 12.0):
			release(e)
		elif e.kind == DUSTER and e.state == 2 and e.px * e.dir > Tuning.ortho_size * 0.5 + 2.0:
			release(e)
		elif e.kind == TRACTOR and e.state == 2 and e.px * e.dir > Tuning.ortho_size * 0.5 + 1.8:
			release(e)
	_fill_colliders()

# ---------- colliders ----------

func _add(owner_i: int, type: float, cx: float, cz: float, hx: float, hz: float, ang: float = 0.0, flags: float = 0.0) -> void:
	if col_count >= MAX_COLLIDERS:
		return
	var o := col_count * STRIDE
	col[o] = type
	col[o + 1] = cx
	col[o + 2] = cz
	col[o + 3] = hx
	col[o + 4] = hz
	col[o + 5] = cos(ang)
	col[o + 6] = sin(ang)
	col[o + 7] = owner_i
	col[o + 8] = flags
	col[o + 9] = hx if type == T_CIRCLE else sqrt(hx * hx + hz * hz)   # (a circle that holds the whole shape: the quick test)
	col_count += 1

func _fill_colliders() -> void:
	col_count = 0
	for i in active.size():
		var e := active[i]
		e.col_first = col_count
		if e.solid:
			match e.kind:
				BARN:
					if e.b > 0.5:   # the two walls; the doorway between them is open
						var c: float = Tuning.barn_door_width * 0.5 + e.a * 0.5
						_add(i, T_RECT, e.px - c, e.pz, e.a * 0.5, BARN_LONG)
						_add(i, T_RECT, e.px + c, e.pz, e.a * 0.5, BARN_LONG)
					else:
						_add(i, T_RECT, e.px, e.pz, e.a, BARN_DEPTH)
				TRACTOR:
					_add(i, T_RECT, e.px - 0.075 * e.dir, e.pz, 0.64, 0.58)   # body, cab and rear wheels
					_add(i, T_RECT, e.px + 0.85 * e.dir, e.pz, 0.36, 0.46)    # hood and front wheels
				WINDMILL:
					var v := int(e.a)
					var n: int = Tuning.windmill_blades[v]
					var len: float = Tuning.windmill_blade[v]
					_add(i, T_CIRCLE, e.px, e.pz, Tuning.windmill_hub[v], 0.0)
					for k in n:
						var phi: float = e.ang + TAU * k / n
						_add(i, T_RECT, e.px + cos(phi) * len * 0.5, e.pz + sin(phi) * len * 0.5, len * 0.5, Tuning.windmill_width[v], phi)
				CROW:
					_add(i, T_CIRCLE, e.px, e.pz, CROW_RADIUS, 0.0)
				BALLOON:
					_add(i, T_CIRCLE, e.px, e.pz, BALLOON_RADIUS, 0.0)
				POWERLINE:
					var xa := minf(e.x0, e.a)
					var xb := maxf(e.x0, e.a)
					_add(i, T_RECT, (xa + xb) * 0.5, e.pz, (xb - xa) * 0.5, WIRE_HALF)
					_add(i, T_RECT, xa, e.pz, POLE_HALF, POLE_HALF)
					_add(i, T_RECT, xb, e.pz, POLE_HALF, POLE_HALF)
				DUSTER:
					_add(i, T_RECT, e.px, e.pz, DUSTER_BODY.x, DUSTER_BODY.y)
					_add(i, T_RECT, e.px + 0.1 * e.dir, e.pz, DUSTER_WING.x, DUSTER_WING.y)
				KITE:
					_add(i, T_CIRCLE, e.px, e.pz, KITE_RADIUS, 0.0)
				HAY:
					if e.crate_kind != 0:
						_add(i, T_RECT, e.px, e.pz, HAY_HALF.x, HAY_HALF.y, 0.0, F_HAY)
		e.col_n = col_count - e.col_first

## The gap between plane shape `o` of `caps` (at plane position p) and collider `ci` (outline included): negative = overlap.
func gap(p: Vector2, caps: PackedFloat32Array, o: int, ci: int) -> float:
	var q := ci * STRIDE
	var center := Vector2(col[q + 1], col[q + 2])
	var a := Vector2(p.x + caps[o], p.y + caps[o + 1])
	var b := Vector2(p.x + caps[o + 2], p.y + caps[o + 3])
	var rim := Tuning.outline_thickness
	if col[q] == T_CIRCLE:
		return Collision.point_segment(center, a, b) - caps[o + 4] - col[q + 3] - rim
	var c := col[q + 5]
	var s := col[q + 6]
	var da := a - center
	var db := b - center
	var la := Vector2(da.x * c + da.y * s, -da.x * s + da.y * c)
	var lb := Vector2(db.x * c + db.y * s, -db.x * s + db.y * c)
	return Collision.segment_rect(la, lb, Vector2(col[q + 3] + rim, col[q + 4] + rim)) - caps[o + 4]

## The radius of a circle around the plane's origin that holds all its shapes.
func plane_radius(caps: PackedFloat32Array) -> float:
	var r := 0.0
	for o in range(0, caps.size(), 5):
		r = maxf(r, maxf(Vector2(caps[o], caps[o + 1]).length(), Vector2(caps[o + 2], caps[o + 3]).length()) + caps[o + 4])
	return r

## Is any collider overlapping the plane shapes right now? (sets last_hit_hay if it was a hay bale)
func hits(p: Vector2, caps: PackedFloat32Array) -> bool:
	var pr := plane_radius(caps) + Tuning.outline_thickness
	for ci in col_count:
		var q := ci * STRIDE
		if absf(col[q + 2] - p.y) > NEAR_RANGE + 2.0 or absf(col[q + 1] - p.x) > 7.0:
			continue
		var dx := col[q + 1] - p.x
		var dz := col[q + 2] - p.y
		var reach := pr + col[q + 9]
		if dx * dx + dz * dz > reach * reach:   # the circles around the plane and this shape do not even touch
			continue
		for o in range(0, caps.size(), 5):
			if gap(p, caps, o, ci) < 0.0:
				last_hit_hay = col[q + 8] == F_HAY
				return true
	return false

## The smallest gap between the plane and a thing's shapes. Shapes farther than `margin` beyond the quick circles
## (the plane's radius `pr` and the shape's) are skipped: their exact gap would be bigger than `margin` anyway.
func min_gap_of(e: Ent, p: Vector2, caps: PackedFloat32Array, pr: float = INF, margin: float = 0.0) -> float:
	var best := INF
	for ci in range(e.col_first, e.col_first + e.col_n):
		if pr < INF:
			var q := ci * STRIDE
			var dx := col[q + 1] - p.x
			var dz := col[q + 2] - p.y
			var reach := pr + col[q + 9] + margin
			if dx * dx + dz * dz > reach * reach:
				continue
		for o in range(0, caps.size(), 5):
			best = minf(best, gap(p, caps, o, ci))
	return best

## Close calls: track each thing's closest approach while it is near the plane; once it has gone by (or flown off),
## report it if it came closer than `limit` without touching. Events carry what Main needs.
func update_near_misses(p: Vector2, caps: PackedFloat32Array, limit: float, behind: float, out: Array[Dictionary], whisker: float) -> void:
	var pr := plane_radius(caps) + Tuning.outline_thickness
	for e in active:
		if e.passed or not e.solid:
			if not e.passed and e.state == 0:
				pass
			continue
		var near := absf(e.pz - p.y) < NEAR_RANGE + e.reach.y and absf(e.px - p.x) < 6.0 + e.reach.x
		if e.kind == BARN and e.b > 0.5 and absf(p.y - e.pz) < BARN_LONG and absf(p.x - e.px) < Tuning.barn_door_width * 0.5:
			e.thru += 1
		if near:
			e.entered = true
			var g := min_gap_of(e, p, caps, pr, limit + 0.3)
			if g < e.min_clear:
				e.min_clear = g
				e.min_side = 1 if e.px > p.x else -1
		var gone := false
		match e.kind:
			CROW:
				gone = e.pz - e.reach.y > p.y + behind or absf(e.px) > 11.0
			DUSTER:
				gone = (e.px - p.x) * e.dir > e.reach.x + 1.0 + 1.1 and e.entered or e.pz - e.reach.y > p.y + behind
			_:
				gone = e.pz - e.reach.y > p.y + behind
		if gone:
			e.passed = true
			if e.kind == BARN and e.thru >= 2 and e.min_clear >= 0.0:   # straight through the doorway
				out.append({"side": 1 if randf() < 0.5 else -1, "node": e.parts[0], "outline": e.outline, "clearance": 0.0, "whisker": true, "special": "barnstormer", "row": null, "k": -1})
			elif e.entered and e.min_clear < limit and e.kind != HAY:
				out.append({"side": e.min_side, "node": e.parts[0], "outline": e.outline, "clearance": e.min_clear, "whisker": e.min_clear <= whisker, "row": null, "k": -1})

## Hay: break the bales the plane touches head-on (or any touch with `battering`). Returns [{kind, pos}].
func break_hay(p: Vector2, caps: PackedFloat32Array, battering: bool, speed_ok: bool, from_z: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in active:
		if e.kind != HAY or e.crate_kind == 0 or not e.solid:
			continue
		if absf(e.pz - p.y) > NEAR_RANGE or absf(e.px - p.x) > 4.0:
			continue
		var touching := false
		for ci in range(e.col_first, e.col_first + e.col_n):
			for o in range(0, caps.size(), 5):
				if gap(p, caps, o, ci) < 0.0:
					touching = true
		if not touching:
			continue
		var front: bool = maxf(p.y, from_z) > e.pz and absf(p.x - e.px) <= HAY_HALF.x + Tuning.outline_thickness + Tuning.crate_front_forgive
		if battering or (front and speed_ok):
			out.append({"kind": e.crate_kind, "pos": Vector3(e.px, 0.4, e.pz)})
			e.crate_kind = 0
			e.solid = false
			e.visible = false
			if e.ghost != null:
				e.ghost.visible = false
	_fill_colliders()
	return out

## A survived hit: the things the plane overlaps are done (no close-call credit for them).
func mark_hit(p: Vector2, caps: PackedFloat32Array) -> void:
	for e in active:
		if e.solid and not e.passed and min_gap_of(e, p, caps, plane_radius(caps) + Tuning.outline_thickness, 0.1) < 0.0:
			e.passed = true

# ---------- pre-warm ----------

## Pre-warm: show EVERY pooled thing on screen (variants too: closed and fly-through barns of every size, all three
## windmills, hay of every colour, the crow, the duster with its warning, the tractor with its dust), stacked on a grid
## inside the view, so every mesh, material and outline is drawn before real play. Nothing is allocated for this: the
## things come from their pools like in a run, and prewarm_hide() puts them back.
func prewarm_show() -> void:
	release_all()
	var slot := 0
	for k in KINDS_COUNT():
		var count := (_free[k] as Array).size()
		for i in count:
			var fake_row := _FakeRow.new()
			fake_row.position.z = 0.0
			var a := 0.0
			var b := 0.0
			match k:
				BARN:   # sizes 0..4 closed (hx 0.8 .. 2.4), then fly-through with the three wall thicknesses
					if i % 2 == 0:
						a = 0.8 + 0.4 * ((i / 2) % 5)
					else:
						a = WALLS[(i / 2) % WALLS.size()]
						b = 1.0
				WINDMILL:
					a = float(i % 3)
				POWERLINE:
					a = -4.0 + 0.7 * i
				HAY:
					b = float(1 + i % 3)   # every glow colour
			var x := -3.6 + 1.8 * (slot % 5)
			var z := -6.0 + 2.1 * ((slot / 5) % 6)
			var e := spawn(k, fake_row, x, 0.0, a, b, 0.5, 1.0, float(i), 1.0 if i % 2 == 0 else -1.0)
			slot += 1
			if e == null:
				continue
			if k == CROW or k == DUSTER or k == TRACTOR:
				e.state = 2
			e.solid = true
			e.visible = true
			_pose(e, 0.0)
			e.position = Vector3(x, 0.0, z)
			e.px = x
			e.pz = z
			if e.ghost != null:
				e.ghost.position = Vector3(x, 1.012, z)
			if k == DUSTER:   # the warning: arrow, glowing edge and row line, in view
				e.arrow.visible = true
				e.arrow.position = Vector3.ZERO
				e.arrow_mesh.position = Vector3(-2.0 + 2.0 * i, 0.5, -5.0)
				e.edge_node.position = Vector3(4.2, 1.45, 0.0)
				e.line_node.position = Vector3(0.0, 0.3, z)
				warn_mat.albedo_color.a = 0.4
				warn_line_mat.albedo_color.a = 0.3
			if k == TRACTOR:   # the dust plume
				e.arrow.visible = true
				e.arrow.position = Vector3(x + 1.2, 0.0, z)
				for pf in e.puffs:
					pf.position = Vector3(0.0, 0.5, 0.0)
					pf.scale = Vector3.ONE
	_fill_colliders()

class _FakeRow extends RefCounted:
	var position := Vector3.ZERO

static func KINDS_COUNT() -> int:
	return 9
