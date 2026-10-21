class_name GroundWorld
extends Node3D
## The countryside below the play layer: big simple field patches, roads, a river and farmhouses. It scrolls at exactly the
## obstacles' speed (nothing is parallaxed, so a barn never slides over the ground it stands on). Readability comes from
## colour only: everything is muted, desaturated and pulled toward the haze, drawn flat and unshaded with soft faded edges
## (no outlines, no blur, no second render). Scenery only: nothing collides.
## Four chunks of ground are built once and recycled as they scroll off the bottom; refilling one only moves and shows
## pooled quads. The plane's soft shadow and Rusty's airstrip (the takeoff) live here too.

const CHUNKS := 4
const LEN := 15.0                 # a chunk's length in z
const HALF_W := 7.5               # scenery spans x = -7.5 .. 7.5 (the screen shows about +-5)
const FIELD_Y := -2.02
const FIELD_COLS := 2
const FIELD_ROWS := 2
const FEATHER := 0.45             # how wide the soft edges are (world units)

class Chunk extends Node3D:
	var fields: Array[MeshInstance3D] = []
	var road_h: MeshInstance3D
	var road_v: MeshInstance3D
	var river: Array[MeshInstance3D] = []
	var house: Node3D

var _chunks: Array[Chunk] = []
var _patch_shader: Shader = preload("res://shaders/ground_patch.gdshader")
var _quad := QuadMesh.new()         # the one unit quad every patch shares (scaled per patch)
var _field_mats: Array[ShaderMaterial] = []
var _road_mat: ShaderMaterial
var _river_mat: ShaderMaterial
var _wall_mat: ShaderMaterial
var _roof_mat: ShaderMaterial
var _strip_mat: ShaderMaterial
var _river_x := 0.0
var _river_left := 0                # chunks of river still to come
var _haze := Color(0.5, 0.58, 0.68)
var _ground_color := Color(0.2, 0.26, 0.34)
var _tint := Color.WHITE            # time of day: the sky's tint and how far it pulls the ground
var _tint_mix := 0.0
var base_mat := StandardMaterial3D.new()   # the flat colour under everything (the Spawner's ground plane wears it)
var sign_label: Label3D
var shadow: MeshInstance3D
var _shadow_mat := StandardMaterial3D.new()
var airstrip: Node3D
var _airstrip_z := 0.0
var airstrip_active := false
var palette_map := 0

func _patch_mat(priority: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _patch_shader
	m.set_shader_parameter("feather", FEATHER)
	m.render_priority = priority
	return m

func _ready() -> void:
	_quad.orientation = PlaneMesh.FACE_Y
	_quad.size = Vector2.ONE
	base_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 6:
		_field_mats.append(_patch_mat(-30))
	_road_mat = _patch_mat(-28)
	_river_mat = _patch_mat(-27)
	_strip_mat = _patch_mat(-26)
	_wall_mat = _patch_mat(-25)
	_roof_mat = _patch_mat(-24)
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
	_shadow_mat.render_priority = -20
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
	apply_debug()
	for c in _chunks:
		_refill(c)

## ?nofx=ground: no countryside, just the flat colour.
func apply_debug() -> void:
	var off := DebugFlags.off("ground")
	for c in _chunks:
		c.visible = not off

func _patch(parent: Node3D, size: Vector2, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = mat
	mi.scale = Vector3(size.x, 1.0, size.y)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _build_chunk(index: int) -> Chunk:
	var c := Chunk.new()
	for r in FIELD_ROWS:
		for col in FIELD_COLS:
			c.fields.append(_patch(c, Vector2.ONE, _field_mats[0]))   # (sized in _refill by scale: no mesh is rebuilt)
	c.road_h = _patch(c, Vector2(2.0 * HALF_W, 1.4), _road_mat)
	c.road_v = _patch(c, Vector2(1.2, LEN), _road_mat)
	for k in 4:
		c.river.append(_patch(c, Vector2(2.2, LEN / 4.0 + 2.0 * FEATHER), _river_mat))
	c.house = Node3D.new()
	c.add_child(c.house)
	_patch(c.house, Vector2(2.0, 1.5), _wall_mat)
	_patch(c.house, Vector2(1.5, 1.1), _roof_mat, Vector3(0, 0.01, 0))
	c.position = Vector3(0.0, 0.0, -LEN * (index - 1.5))
	add_child(c)
	return c

func _build_airstrip() -> void:
	airstrip = Node3D.new()
	airstrip.visible = false
	_patch(airstrip, Vector2(3.6, 26.0), _strip_mat, Vector3(0, -1.98, 0))
	_patch(airstrip, Vector2(2.6, 2.2), _wall_mat, Vector3(-3.4, -1.97, 6.0))   # Rusty's hangar
	_patch(airstrip, Vector2(2.1, 1.7), _roof_mat, Vector3(-3.4, -1.96, 6.0))
	add_child(airstrip)
	# the sign is plain, faint text
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
	_haze = base.lerp(_tint * base.v * 2.4, _tint_mix * 0.5)   # (dusk stays light enough for the dark obstacles to stand out)
	var natural: Array[Color] = [Color(0.36, 0.6, 0.28), Color(0.55, 0.7, 0.3), Color(0.8, 0.72, 0.32), Color(0.5, 0.38, 0.24), Color(0.28, 0.5, 0.3), Color(0.72, 0.62, 0.3)]
	var mix := 0.2 + 0.1 * palette_map
	for i in 6:
		_field_mats[i].set_shader_parameter("color", _soft(natural[i].lerp(_ground_color, mix)))
	_road_mat.set_shader_parameter("color", _soft(Color(0.5, 0.5, 0.52)))
	_river_mat.set_shader_parameter("color", _soft(Color(0.3, 0.55, 0.8)))
	_wall_mat.set_shader_parameter("color", _soft(Color(0.66, 0.62, 0.56)))
	_roof_mat.set_shader_parameter("color", _soft(Color(0.5, 0.34, 0.3)))
	_strip_mat.set_shader_parameter("color", _soft(Color(0.45, 0.45, 0.47)))
	base_mat.albedo_color = _haze.darkened(0.1)

## Every colour the countryside is drawn in right now (the tests check they stay muted).
func colors() -> Array[Color]:
	var out: Array[Color] = []
	for m in _field_mats:
		out.append(m.get_shader_parameter("color"))
	for m in [_road_mat, _river_mat, _wall_mat, _roof_mat, _strip_mat]:
		out.append((m as ShaderMaterial).get_shader_parameter("color"))
	out.append(base_mat.albedo_color)
	return out

## Rebuild a chunk's layout: big overlapping patches, maybe a road, the river if it runs through, a farmhouse.
func _refill(c: Chunk) -> void:
	var cw := 2.0 * HALF_W / FIELD_COLS
	var rd := LEN / FIELD_ROWS
	var i := 0
	for r in FIELD_ROWS:
		for col in FIELD_COLS:
			var f := c.fields[i]
			f.scale = Vector3(cw + FEATHER, 1.0, rd + FEATHER)   # (neighbours overlap by the feather: they blend)
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
		c.house.position = Vector3(_free_x(c), FIELD_Y + 0.03, randf_range(-LEN * 0.35, LEN * 0.35))
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

## Scroll by `dist`: exactly what the obstacles travel. Chunks that leave the bottom are recycled to the top.
func scroll(dist: float) -> void:
	for c in _chunks:
		c.position.z += dist
		if c.position.z - LEN * 0.5 > 20.0:   # past the bottom of the screen: back to the top of the line
			c.position.z -= LEN * CHUNKS
			_refill(c)
	if airstrip_active:
		_airstrip_z += dist
		airstrip.position.z = _airstrip_z
		sign_label.position.z = 8.4 + _airstrip_z
		if _airstrip_z > 40.0:
			stop_airstrip()

## Rusty's airstrip under the plane at the start of a run; `plane_z` = where the plane is.
func start_airstrip(plane_z: float) -> void:
	_airstrip_z = plane_z - 9.0
	airstrip.position = Vector3(0, 0, _airstrip_z)
	sign_label.position.z = 8.4 + _airstrip_z
	airstrip.visible = not DebugFlags.off("ground")
	sign_label.visible = airstrip.visible
	airstrip_active = true

func stop_airstrip() -> void:
	airstrip_active = false
	airstrip.visible = false
	sign_label.visible = false

## The plane's shadow falls offset from it in proportion to its altitude, and tightens and darkens when it is low.
func update_shadow(plane: Vector3, shown: bool) -> void:
	shadow.visible = shown and not DebugFlags.off("shadows")
	if shadow.visible:
		var alt := maxf(plane.y + 2.0, 0.0)
		var h := clampf((plane.y + 2.0) / 3.2, 0.2, 1.0)   # 1 at flying height
		shadow.position = Vector3(plane.x, -1.96, plane.z + alt * Tuning.shadow_per_altitude)
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
		c.visible = true
	airstrip.visible = true
	airstrip.position = Vector3(0, 0, 0)
	sign_label.visible = true

func prewarm_hide() -> void:
	for c in _chunks:
		_refill(c)
	apply_debug()
	airstrip.visible = false
	sign_label.visible = false
	airstrip_active = false
