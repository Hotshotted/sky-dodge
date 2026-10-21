class_name ShadowBlobs
extends Node3D
## A soft dark shadow on the ground under every obstacle and fuel can. Things that stand on the ground (barns, windmills,
## power lines, tractors, hay) get a contact shadow directly beneath them; flying things (crows, balloons, kites, the duster,
## cans, floating cubes) get one offset toward the bottom of the screen by their altitude, so they read as airborne. One MultiMesh of soft rounded squares, created once; each frame the blobs are moved onto whatever is
## in play (rows' cubes, the kit's things, cans) and the rest are hidden by lowering the visible count.

const MAX := 128
const GROUND := -1.99

var _mm := MultiMesh.new()
var _mi := MultiMeshInstance3D.new()
var _mat := StandardMaterial3D.new()
var blob_pos := PackedVector3Array()   # where each placed blob is (x, z offset applied, alpha): the tests read it, since a headless renderer keeps no transforms
var count := 0                       # blobs placed this frame (the tests read it)
var _dark := 1.0                     # 1 by day, lower at dusk (a shadow on a dark ground is subtler)

func _ready() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var p := Vector2((x + 0.5) / 64.0 - 0.5, (y + 0.5) / 64.0 - 0.5)
			var q := p.abs() - Vector2(0.18, 0.18)   # a rounded square: soft all the way round, no hard edge
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
			img.set_pixel(x, y, Color(0, 0, 0, clampf(1.0 - d / 0.32, 0.0, 1.0) ** 1.6))
	var tex := ImageTexture.create_from_image(img)
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_texture = tex
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.render_priority = -20   # above the countryside patches (-30..-24), under everything else that is see-through
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2.ONE
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = q
	_mm.instance_count = MAX
	blob_pos.resize(MAX)
	_mm.visible_instance_count = 0
	_mi.multimesh = _mm
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.extra_cull_margin = 100.0
	add_child(_mi)

func prewarm_show() -> void:
	for i in MAX:
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1, 1, 1)), Vector3(0, GROUND, 0)))
		_mm.set_instance_color(i, Color(0, 0, 0, 0.3))
	_mm.visible_instance_count = MAX

func hide_all() -> void:
	_mm.visible_instance_count = 0
	count = 0

## One blob at ground point (x, z). `alt` is the altitude above the ground (0 = contact shadow, directly beneath).
func _put(x: float, z: float, hx: float, hz: float, alpha: float, alt: float = 0.0, rot: float = 0.0) -> void:
	if count >= MAX:
		return
	var g := lerpf(1.08, Tuning.shadow_grow, clampf(alt, 0.0, 1.0))
	var a := alpha * (1.15 if alt <= 0.0 else 0.8)   # a contact shadow is tighter and darker; a flying one softer
	var b := Basis(Vector3.UP, rot).scaled_local(Vector3(hx * 2.0 * g, 1.0, hz * 2.0 * g))
	_mm.set_instance_transform(count, Transform3D(b, Vector3(x, GROUND, z + alt * Tuning.shadow_per_altitude)))
	_mm.set_instance_color(count, Color(0, 0, 0, a * Tuning.shadow_alpha * _dark))
	blob_pos[count] = Vector3(x, a, z + alt * Tuning.shadow_per_altitude)
	count += 1

func _box_part(p: MeshInstance3D, alpha: float) -> void:
	var half: Vector3 = (p.mesh as BoxMesh).size * 0.5
	var pos := p.global_position
	_put(pos.x, pos.z, half.x, half.z, alpha, 0.0, p.global_transform.basis.get_euler().y)

## The shadow(s) of one kit thing.
func _kit_shadow(e) -> void:
	var p: Vector3 = e.global_position
	var alt: float = Tuning.shadow_altitude[e.kind]
	match e.kind:
		0:   # barn: its walls (a fly-through barn has a gap between two)
			if e.b > 0.5:
				_box_part(e.parts[0], 1.0)
				_box_part(e.parts[2], 1.0)
			else:
				_box_part(e.parts[0], 1.0)
		2:   # windmill: the tower's foot and the turning blades' cross
			_put(p.x, p.z, 0.55, 0.55, 1.0)
			for k in range(2, e.parts.size()):
				var bl: MeshInstance3D = e.parts[k]
				if bl.visible and bl.mesh is BoxMesh:
					_box_part(bl, 0.6)
		_:
			_put(p.x, p.z, maxf(e.reach.x, 0.2), maxf(e.reach.y, 0.2), 1.0, alt, e.rotation.y)

## Place a blob under everything in play. `tod_dark` (0..1) fades the shadows toward dusk.
func update_from(spawner: Node3D, tod_dark: float, shown: bool) -> void:
	if not shown or DebugFlags.off("shadows"):
		hide_all()
		return
	_dark = lerpf(1.0, 0.6, tod_dark)
	count = 0
	for row in spawner._rows:   # (typed loosely: Spawner has no class name)
		if not row.visible:
			continue
		for mi in row.cubes:
			if mi.visible:
				_put(mi.position.x, row.position.z, mi.scale.x * 0.5, mi.scale.z * 0.5, 1.0, Tuning.shadow_altitude_cube)
		if row.can.visible:
			_put(row.can.position.x, row.position.z + row.can.position.z, 0.3, 0.3, 0.8, Tuning.shadow_altitude_can)
	for e in spawner.kit.active:
		if e.visible and e.in_use:
			_kit_shadow(e)
	_mm.visible_instance_count = count
