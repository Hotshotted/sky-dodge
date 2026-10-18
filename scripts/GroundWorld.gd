class_name GroundWorld
extends Node3D
## The countryside far below the play layer: big simple field patches, roads, a river and farmhouses, scrolling slower
## than the obstacles (parallax). It is drawn in its own small SubViewport (1/ground_blur_div of the screen, unshaded, no
## outlines), muted toward the haze, and shown blurred on the ground plane under the play layer (shaders/backdrop.gdshader),
## so it reads as out of focus and never competes with the crisp obstacles. Scenery only: nothing collides.
## Four chunks of ground are built once and recycled as they scroll off the bottom; refilling one only moves and shows
## pooled boxes. The plane's soft shadow and Rusty's airstrip (the takeoff) live here too.

const CHUNKS := 4
const LEN := 15.0                 # a chunk's length in z
const HALF_W := 7.5               # scenery spans x = -7.5 .. 7.5 (the screen shows about +-5)
const FIELD_Y := -2.02
const FIELD_COLS := 2
const FIELD_ROWS := 2

class Chunk extends Node3D:
	var fields: Array[MeshInstance3D] = []
	var road_h: MeshInstance3D
	var road_v: MeshInstance3D
	var river: Array[MeshInstance3D] = []
	var house: Node3D

var parallax := 0.45              # how fast the ground scrolls compared with the obstacles
var _chunks: Array[Chunk] = []
var _field_mats: Array[StandardMaterial3D] = []
var _road_mat := StandardMaterial3D.new()
var _river_mat := StandardMaterial3D.new()
var _wall_mat := StandardMaterial3D.new()
var _roof_mat := StandardMaterial3D.new()
var _strip_mat := StandardMaterial3D.new()
var _river_x := 0.0
var _river_left := 0                # chunks of river still to come
var _haze := Color(0.5, 0.58, 0.68)
var _ground_color := Color(0.2, 0.26, 0.34)
var _tint := Color.WHITE            # time of day: the sky's tint and how far it pulls the ground
var _tint_mix := 0.0
var vp: SubViewport                 # the small picture of the countryside
var cam: Camera3D                   # looks at it exactly as the main camera looks at the play layer
var world: Node3D                   # everything the small picture shows
var backdrop_mat := ShaderMaterial.new()   # the ground plane's material: the picture, blurred
var sign_label: Label3D
var _vp_size := Vector2i.ZERO
var shadow: MeshInstance3D
var _shadow_mat := StandardMaterial3D.new()
var airstrip: Node3D
var _airstrip_z := 0.0
var airstrip_active := false
var palette_map := 0

func _ready() -> void:
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.gui_disable_input = true
	vp.size = Vector2i(270, 480)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED if DebugFlags.off("ground") else SubViewport.UPDATE_ALWAYS
	add_child(vp)
	world = Node3D.new()
	vp.add_child(world)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.near = 0.1
	cam.far = 100.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR   # (shows between the field patches: a dark haze, not a line)
	cam.environment = env
	vp.add_child(cam)
	_bg_env = env
	var shader := load("res://shaders/backdrop.gdshader") as Shader
	backdrop_mat.shader = shader
	backdrop_mat.set_shader_parameter("tex", vp.get_texture())
	backdrop_mat.set_shader_parameter("use_tex", 0.0 if DebugFlags.off("ground") else 1.0)
	for i in 6:
		_field_mats.append(StandardMaterial3D.new())
	for m in [_road_mat, _river_mat, _wall_mat, _roof_mat, _strip_mat]:
		_all_mats.append(m)
	_all_mats.append_array(_field_mats)
	for m in _all_mats:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for c in CHUNKS:
		_chunks.append(_build_chunk(c))
	# the plane's soft shadow: a dark radial gradient on the ground
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_texture = tex
	_shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(3.2, 2.6)
	q.orientation = PlaneMesh.FACE_Y
	shadow.mesh = q
	shadow.material_override = _shadow_mat
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.position = Vector3(0, -1.97, 0)
	add_child(shadow)
	_build_airstrip()
	apply_palette(0, Color(0.2, 0.26, 0.34))
	for c in _chunks:
		_refill(c)

var _bg_env: Environment
var _all_mats: Array[StandardMaterial3D] = []

## Keep the small picture's camera and size matched to the main view (the picture is 1/ground_blur_div as big).
func sync_camera(main_cam: Camera3D, view: Vector2) -> void:
	cam.global_transform = main_cam.global_transform
	cam.size = main_cam.size
	var want := Vector2i(maxi(int(view.x / Tuning.ground_blur_div), 8), maxi(int(view.y / Tuning.ground_blur_div), 8))
	if want != _vp_size:
		_vp_size = want
		vp.size = want
		backdrop_mat.set_shader_parameter("texel", Vector2(1.0 / want.x, 1.0 / want.y))
	backdrop_mat.set_shader_parameter("radius", Tuning.ground_blur_radius)

func _mesh_box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _build_chunk(index: int) -> Chunk:
	var c := Chunk.new()
	for r in FIELD_ROWS:
		for col in FIELD_COLS:
			c.fields.append(_mesh_box(c, Vector3(1.0, 0.04, 1.0), _field_mats[0]))   # (unit boxes, sized by scale: no mesh is rebuilt)
	c.road_h = _mesh_box(c, Vector3(2.0 * HALF_W, 0.04, 1.4), _road_mat)
	c.road_v = _mesh_box(c, Vector3(1.2, 0.04, LEN), _road_mat)
	for k in 4:
		c.river.append(_mesh_box(c, Vector3(2.2, 0.04, LEN / 4.0 + 0.3), _river_mat))
	c.house = Node3D.new()
	c.add_child(c.house)
	_mesh_box(c.house, Vector3(2.0, 0.5, 1.5), _wall_mat, Vector3(0, 0.25, 0))
	_mesh_box(c.house, Vector3(2.3, 0.12, 1.8), _roof_mat, Vector3(0, 0.56, 0))
	c.position = Vector3(0.0, 0.0, -LEN * (index - 1.5))
	world.add_child(c)
	return c

func _build_airstrip() -> void:
	airstrip = Node3D.new()
	airstrip.visible = false
	_mesh_box(airstrip, Vector3(3.6, 0.05, 26.0), _strip_mat, Vector3(0, -1.98, 0))
	_mesh_box(airstrip, Vector3(2.6, 0.9, 2.2), _wall_mat, Vector3(-3.4, -1.55, 6.0))   # Rusty's hangar
	_mesh_box(airstrip, Vector3(2.9, 0.14, 2.5), _roof_mat, Vector3(-3.4, -1.05, 6.0))
	world.add_child(airstrip)
	# the sign is plain text in the main view (soft, not part of the blurred picture)
	sign_label = Label3D.new()
	sign_label.text = "RUSTY'S AIRSTRIP"
	sign_label.font_size = 64
	sign_label.pixel_size = 0.014
	sign_label.outline_size = 0
	sign_label.modulate = Color(1, 1, 1, 0.5)
	sign_label.rotation = Vector3(-PI / 2, 0, 0)
	sign_label.position = Vector3(-3.4, -1.9, 8.4)
	sign_label.visible = false
	add_child(sign_label)

## Colours for a map: natural fields, roads and water, desaturated and pulled toward the map's ground colour and the haze.
func apply_palette(map_index: int, ground: Color) -> void:
	palette_map = map_index
	_ground_color = ground
	_recolor()

## Time of day: the sky's tint pulls the ground colours too (sunset warms them, dusk darkens them).
func set_tint(tint: Color, mix: float) -> void:
	_tint = tint
	_tint_mix = mix
	_recolor()

func _soft(c: Color) -> Color:
	var g := Color.from_hsv(c.h, c.s * Tuning.ground_saturation, c.v)
	return g.lerp(_haze, Tuning.ground_haze)

func _recolor() -> void:
	var base := _ground_color.lerp(Color(0.62, 0.7, 0.82), 0.5)
	_haze = base.lerp(_tint * base.v * 1.6, _tint_mix * 0.8)
	var natural: Array[Color] = [Color(0.36, 0.6, 0.28), Color(0.55, 0.7, 0.3), Color(0.8, 0.72, 0.32), Color(0.5, 0.38, 0.24), Color(0.28, 0.5, 0.3), Color(0.72, 0.62, 0.3)]
	var mix := 0.2 + 0.1 * palette_map
	for i in 6:
		_field_mats[i].albedo_color = _soft(natural[i].lerp(_ground_color, mix))
	_road_mat.albedo_color = _soft(Color(0.5, 0.5, 0.52))
	_river_mat.albedo_color = _soft(Color(0.3, 0.55, 0.8))
	_wall_mat.albedo_color = _soft(Color(0.9, 0.85, 0.75))
	_roof_mat.albedo_color = _soft(Color(0.7, 0.28, 0.2))
	_strip_mat.albedo_color = _soft(Color(0.45, 0.45, 0.47))
	_bg_env.background_color = _haze.darkened(0.15)
	backdrop_mat.set_shader_parameter("fallback", _haze.darkened(0.15))

## Rebuild a chunk's layout: big patches, maybe a road, the river if it runs through, a farmhouse.
func _refill(c: Chunk) -> void:
	var cw := 2.0 * HALF_W / FIELD_COLS
	var rd := LEN / FIELD_ROWS
	var i := 0
	for r in FIELD_ROWS:
		for col in FIELD_COLS:
			var f := c.fields[i]
			f.scale = Vector3(cw - 0.3, 1.0, rd - 0.3)
			f.position = Vector3(-HALF_W + cw * (col + 0.5), FIELD_Y, -LEN * 0.5 + rd * (r + 0.5))
			f.material_override = _field_mats[randi() % 6]
			i += 1
	# the river continues across chunks as a gentle S
	var river_on := _river_left > 0
	if not river_on and randf() < 0.3:
		_river_left = randi_range(2, 3)
		_river_x = randf_range(-3.5, 3.5)
		river_on = true
	if river_on:
		_river_left -= 1
	for k in 4:
		var seg := c.river[k]
		seg.visible = river_on
		if river_on:
			_river_x = clampf(_river_x + randf_range(-0.9, 0.9), -4.5, 4.5)
			seg.position = Vector3(_river_x, FIELD_Y + 0.01, -LEN * 0.5 + (k + 0.5) * LEN / 4.0)
	# a road across, or along
	var road_roll := randf()
	c.road_h.visible = road_roll < 0.4
	if c.road_h.visible:
		c.road_h.position = Vector3(0.0, FIELD_Y + 0.02, randf_range(-LEN * 0.4, LEN * 0.4))
	c.road_v.visible = road_roll > 0.75
	if c.road_v.visible:
		c.road_v.position = Vector3(randf_range(-5.5, 5.5), FIELD_Y + 0.02, 0.0)
	# a farmhouse on the fields (never in the river)
	c.house.visible = randf() < 0.55
	if c.house.visible:
		c.house.position = Vector3(_free_x(c), FIELD_Y + 0.02, randf_range(-LEN * 0.35, LEN * 0.35))
		c.house.rotation.y = randf_range(-0.4, 0.4)

func _free_x(c: Chunk) -> float:
	for t in 4:
		var x := randf_range(-6.0, 6.0)
		var clear := true
		for seg in c.river:
			clear = clear and (not seg.visible or absf(seg.position.x - x) > 2.0)
		if clear:
			return x
	return 6.0

## Scroll by `dist` units of obstacle travel (the ground moves `parallax` of that) and recycle chunks off the bottom.
func scroll(dist: float) -> void:
	var d := dist * parallax
	for c in _chunks:
		c.position.z += d
		if c.position.z - LEN * 0.5 > 14.0:   # past the bottom of the screen: back to the top of the line
			c.position.z -= LEN * CHUNKS
			_refill(c)
	if airstrip_active:
		_airstrip_z += dist   # (the airstrip is part of the play layer's speed, not the far ground's)
		airstrip.position.z = _airstrip_z
		sign_label.position.z = 8.4 + _airstrip_z
		if _airstrip_z > 40.0:
			stop_airstrip()

## Rusty's airstrip under the plane at the start of a run; `plane_z` = where the plane is.
func start_airstrip(plane_z: float) -> void:
	_airstrip_z = plane_z - 9.0
	airstrip.position = Vector3(0, 0, _airstrip_z)
	sign_label.position.z = 8.4 + _airstrip_z
	airstrip.visible = true
	sign_label.visible = not DebugFlags.off("ground")
	airstrip_active = true

func stop_airstrip() -> void:
	airstrip_active = false
	airstrip.visible = false
	sign_label.visible = false

## The plane's shadow follows it on the ground; it is tighter and darker when the plane is low.
func update_shadow(plane: Vector3, shown: bool) -> void:
	shadow.visible = shown and not DebugFlags.off("shadows")
	if shadow.visible:
		var h := clampf((plane.y + 2.0) / 3.2, 0.2, 1.0)   # 1 at flying height
		shadow.position = Vector3(plane.x, -1.96, plane.z + Tuning.shadow_offset * 0.6)
		shadow.scale = Vector3.ONE * lerpf(0.7, 1.0, h)
		_shadow_mat.albedo_color.a = lerpf(1.0, 0.7, h)

## Pre-warm: show every pooled piece.
func prewarm_show() -> void:
	for c in _chunks:
		for f in c.fields:
			f.visible = true
		c.road_h.visible = true
		c.road_v.visible = true
		c.road_v.position = Vector3(3.5, FIELD_Y + 0.02, 0.0)
		for seg in c.river:
			seg.visible = true
		c.house.visible = true
	airstrip.visible = true
	airstrip.position = Vector3(0, 0, 0)
	sign_label.visible = true

func prewarm_hide() -> void:
	for c in _chunks:
		_refill(c)
	airstrip.visible = false
	sign_label.visible = false
	airstrip_active = false
