class_name GroundWorld
extends Node3D
## The countryside far below the play layer: patchwork fields, roads, a river, farmhouses, cows and fences, scrolling
## slower than the obstacles (parallax), muted toward the haze and without outlines. Scenery only: nothing collides.
## Four chunks of ground are built once and recycled as they scroll off the bottom; refilling one only moves and shows
## pooled boxes. The plane's soft shadow and Rusty's airstrip (the takeoff) live here too.

const CHUNKS := 4
const LEN := 15.0                 # a chunk's length in z
const HALF_W := 7.5               # scenery spans x = -7.5 .. 7.5 (the screen shows about +-5)
const FIELD_Y := -2.02
const FIELD_COLS := 3
const FIELD_ROWS := 2
const COWS := 3

class Chunk extends Node3D:
	var fields: Array[MeshInstance3D] = []
	var road_h: MeshInstance3D
	var road_dashes: Array[MeshInstance3D] = []
	var road_v: MeshInstance3D
	var river: Array[MeshInstance3D] = []
	var house: Node3D
	var cows: Array[MeshInstance3D] = []
	var fence_rail: MeshInstance3D
	var fence_posts: MeshInstance3D

var parallax := 0.45              # how fast the ground scrolls compared with the obstacles
var _chunks: Array[Chunk] = []
var _field_mats: Array[StandardMaterial3D] = []
var _road_mat := StandardMaterial3D.new()
var _dash_mat := StandardMaterial3D.new()
var _river_mat := StandardMaterial3D.new()
var _wall_mat := StandardMaterial3D.new()
var _roof_mat := StandardMaterial3D.new()
var _cow_mat := StandardMaterial3D.new()
var _fence_mat := StandardMaterial3D.new()
var _strip_mat := StandardMaterial3D.new()
var _river_x := 0.0
var _river_left := 0                # chunks of river still to come
var _haze := Color(0.5, 0.58, 0.68)
var _base_colors: Array[Color] = []
var shadow: MeshInstance3D
var _shadow_mat := StandardMaterial3D.new()
var airstrip: Node3D
var _airstrip_z := 0.0
var airstrip_active := false
var palette_map := 0

func _ready() -> void:
	for i in 6:
		var m := StandardMaterial3D.new()
		m.roughness = 1.0
		m.metallic_specular = 0.0
		_field_mats.append(m)
	for m in [_road_mat, _dash_mat, _river_mat, _wall_mat, _roof_mat, _cow_mat, _fence_mat, _strip_mat]:
		(m as StandardMaterial3D).roughness = 1.0
		(m as StandardMaterial3D).metallic_specular = 0.0
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
	c.road_h = _mesh_box(c, Vector3(2.0 * HALF_W, 0.04, 1.1), _road_mat)
	for k in 5:
		c.road_dashes.append(_mesh_box(c, Vector3(0.9, 0.045, 0.1), _dash_mat))
	c.road_v = _mesh_box(c, Vector3(1.0, 0.04, LEN), _road_mat)
	for k in 4:
		c.river.append(_mesh_box(c, Vector3(1.8, 0.04, LEN / 4.0 + 0.3), _river_mat))
	c.house = Node3D.new()
	c.add_child(c.house)
	_mesh_box(c.house, Vector3(1.3, 0.5, 1.0), _wall_mat, Vector3(0, 0.25, 0))
	_mesh_box(c.house, Vector3(1.5, 0.12, 1.2), _roof_mat, Vector3(0, 0.56, 0))
	for k in COWS:
		c.cows.append(_mesh_box(c, Vector3(0.34, 0.18, 0.2), _cow_mat))
	c.fence_rail = _mesh_box(c, Vector3(1.0, 0.04, 0.05), _fence_mat)
	c.fence_posts = _mesh_box(c, Vector3(1.0, 0.14, 0.05), _fence_mat)
	c.position = Vector3(0.0, 0.0, -LEN * (index - 1.5))
	add_child(c)
	return c

func _build_airstrip() -> void:
	airstrip = Node3D.new()
	airstrip.visible = false
	_mesh_box(airstrip, Vector3(3.6, 0.05, 26.0), _strip_mat, Vector3(0, -1.98, 0))
	for k in 7:   # the centre-line dashes
		_mesh_box(airstrip, Vector3(0.16, 0.06, 1.6), _dash_mat, Vector3(0, -1.97, -10.0 + 3.4 * k))
	_mesh_box(airstrip, Vector3(2.6, 0.9, 2.2), _wall_mat, Vector3(-3.4, -1.55, 6.0))   # Rusty's hangar
	_mesh_box(airstrip, Vector3(2.9, 0.14, 2.5), _roof_mat, Vector3(-3.4, -1.05, 6.0))
	_mesh_box(airstrip, Vector3(0.08, 1.2, 0.08), _fence_mat, Vector3(2.4, -1.4, 3.0))   # the windsock pole and sock
	_mesh_box(airstrip, Vector3(0.7, 0.14, 0.14), _roof_mat, Vector3(2.75, -0.85, 3.0))
	var sign_label := Label3D.new()
	sign_label.text = "RUSTY'S AIRSTRIP"
	sign_label.font_size = 64
	sign_label.pixel_size = 0.014
	sign_label.outline_size = 12
	sign_label.rotation = Vector3(-PI / 2, 0, 0)
	sign_label.position = Vector3(-3.4, -0.9, 8.4)
	airstrip.add_child(sign_label)
	add_child(airstrip)

## Colours for a map: natural fields, roads and water, pulled toward the map's ground colour and the haze (so it is faded).
func apply_palette(map_index: int, ground: Color) -> void:
	palette_map = map_index
	_haze = ground.lerp(Color(0.62, 0.7, 0.82), 0.5)
	var natural: Array[Color] = [Color(0.36, 0.6, 0.28), Color(0.55, 0.7, 0.3), Color(0.8, 0.72, 0.32), Color(0.5, 0.38, 0.24), Color(0.28, 0.5, 0.3), Color(0.72, 0.62, 0.3)]
	var mix := 0.28 + 0.1 * map_index
	for i in 6:
		_field_mats[i].albedo_color = natural[i].lerp(ground, mix).lerp(_haze, 0.3)
	_road_mat.albedo_color = Color(0.42, 0.42, 0.44).lerp(_haze, 0.4)
	_dash_mat.albedo_color = Color(0.9, 0.9, 0.82).lerp(_haze, 0.35)
	_river_mat.albedo_color = Color(0.3, 0.55, 0.8).lerp(_haze, 0.35)
	_wall_mat.albedo_color = Color(0.9, 0.85, 0.75).lerp(_haze, 0.35)
	_roof_mat.albedo_color = Color(0.7, 0.28, 0.2).lerp(_haze, 0.35)
	_cow_mat.albedo_color = Color(0.92, 0.92, 0.9).lerp(_haze, 0.3)
	_fence_mat.albedo_color = Color(0.5, 0.38, 0.26).lerp(_haze, 0.3)
	_strip_mat.albedo_color = Color(0.36, 0.36, 0.38).lerp(_haze, 0.25)

## Rebuild a chunk's layout: patchwork, maybe a road, the river if it runs through, a house, cows, a fence.
func _refill(c: Chunk) -> void:
	var cw := 2.0 * HALF_W / FIELD_COLS
	var rd := LEN / FIELD_ROWS
	var i := 0
	for r in FIELD_ROWS:
		for col in FIELD_COLS:
			var f := c.fields[i]
			f.scale = Vector3(cw - 0.12, 1.0, rd - 0.12)
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
	for d in c.road_dashes:
		d.visible = c.road_h.visible
	if c.road_h.visible:
		var rz := randf_range(-LEN * 0.4, LEN * 0.4)
		c.road_h.position = Vector3(0.0, FIELD_Y + 0.02, rz)
		for k in c.road_dashes.size():
			c.road_dashes[k].position = Vector3(-HALF_W + 1.5 + k * 3.2, FIELD_Y + 0.025, rz)
	c.road_v.visible = road_roll > 0.75
	if c.road_v.visible:
		c.road_v.position = Vector3(randf_range(-5.5, 5.5), FIELD_Y + 0.02, 0.0)
	# a house and cows on the fields (never in the river)
	c.house.visible = randf() < 0.55
	if c.house.visible:
		c.house.position = Vector3(_free_x(c), FIELD_Y + 0.02, randf_range(-LEN * 0.35, LEN * 0.35))
		c.house.rotation.y = randf_range(-0.4, 0.4)
	for cow in c.cows:
		cow.visible = randf() < 0.7
		cow.position = Vector3(_free_x(c), FIELD_Y + 0.12, randf_range(-LEN * 0.45, LEN * 0.45))
		cow.rotation.y = randf() * TAU
	var fz := randf_range(-LEN * 0.4, LEN * 0.4)
	var fx := randf_range(-5.0, 5.0)
	var flen := randf_range(3.0, 6.0)
	c.fence_rail.visible = randf() < 0.7
	c.fence_posts.visible = c.fence_rail.visible
	c.fence_rail.scale = Vector3(flen, 1.0, 1.0)
	c.fence_posts.scale = Vector3(flen, 1.0, 1.0)
	c.fence_rail.position = Vector3(fx, FIELD_Y + 0.15, fz)
	c.fence_posts.position = Vector3(fx, FIELD_Y + 0.08, fz)

func _free_x(c: Chunk) -> float:
	for t in 4:
		var x := randf_range(-6.0, 6.0)
		var clear := true
		for seg in c.river:
			clear = clear and (not seg.visible or absf(seg.position.x - x) > 1.6)
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
		if _airstrip_z > 40.0:
			airstrip_active = false
			airstrip.visible = false

## Rusty's airstrip under the plane at the start of a run; `plane_z` = where the plane is.
func start_airstrip(plane_z: float) -> void:
	_airstrip_z = plane_z - 9.0
	airstrip.position = Vector3(0, 0, _airstrip_z)
	airstrip.visible = true
	airstrip_active = true

func stop_airstrip() -> void:
	airstrip_active = false
	airstrip.visible = false

## The plane's shadow follows it on the ground; it is tighter and darker when the plane is low.
func update_shadow(plane: Vector3, shown: bool) -> void:
	shadow.visible = shown
	if shown:
		var h := clampf((plane.y + 2.0) / 3.2, 0.2, 1.0)   # 1 at flying height
		shadow.position = Vector3(plane.x, -1.96, plane.z)
		shadow.scale = Vector3.ONE * lerpf(0.7, 1.0, h)
		_shadow_mat.albedo_color.a = lerpf(1.0, 0.7, h)

## Pre-warm: show every pooled piece.
func prewarm_show() -> void:
	for c in _chunks:
		for f in c.fields:
			f.visible = true
		c.road_h.visible = true
		for d in c.road_dashes:
			d.visible = true
		c.road_v.visible = true
		c.road_v.position = Vector3(3.5, FIELD_Y + 0.02, 0.0)
		for seg in c.river:
			seg.visible = true
		c.house.visible = true
		for cow in c.cows:
			cow.visible = true
		c.fence_rail.visible = true
		c.fence_posts.visible = true
	airstrip.visible = true
	airstrip.position = Vector3(0, 0, 0)

func prewarm_hide() -> void:
	for c in _chunks:
		_refill(c)
	airstrip.visible = false
	airstrip_active = false
