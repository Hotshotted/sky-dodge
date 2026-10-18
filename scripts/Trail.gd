class_name Trail
extends MeshInstance3D
## Ribbon behind the plane. Visible while the bonus is 2x or more, its colour follows the
## bonus tier, and it fades out once the bonus is back to x1.
## Points are stored in world space and scroll with the world (+z) like the obstacles.

var _pts: Array[Vector2] = []   # (x, z) of each ribbon point, newest first
var _alpha := 0.0               # overall fade 0..1
var _color := Color.WHITE
var _mesh := ImmediateMesh.new()

func _init() -> void:
	mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat

## Pre-warm: fill the ribbon to its FULL length (the size it reaches in real play) so its largest
## buffers are allocated and drawn before the first real near miss, not during it.
func fill_for_prewarm(origin: Vector2) -> void:
	_pts.clear()
	for i in int(Tuning.trail_length / 0.15):
		_pts.append(Vector2(origin.x + sin(i * 0.3) * 0.5, origin.y + i * 0.15))
	_alpha = 1.0
	_color = Tuning.trail_colors[0]
	_rebuild(origin.y)

func clear() -> void:
	_pts.clear()
	_alpha = 0.0
	_mesh.clear_surfaces()

## `step` = how far the world scrolled this frame, `origin` = (x, z) where the ribbon starts
## (the plane's tail), `bonus` = current score bonus.
func advance(step: float, origin: Vector2, bonus: float, delta: float) -> void:
	for i in _pts.size():
		_pts[i].y += step
	var on := Tuning.bonus_active(bonus)
	if on:
		if _pts.is_empty() or _pts[0].distance_to(origin) >= 0.15:  # keep the point count bounded
			_pts.push_front(origin)
		var target := Tuning.trail_colors[Tuning.tier_index(bonus, Tuning.trail_colors.size())]
		_color = target if _alpha <= 0.0 else _color.lerp(target, 1.0 - exp(-8.0 * delta))
	_alpha = move_toward(_alpha, 1.0 if on else 0.0, delta / maxf(Tuning.trail_fade_time, 0.01))
	while _pts.size() > 0 and _pts.back().y - origin.y > Tuning.trail_length:
		_pts.pop_back()
	_rebuild(origin.y)

func _rebuild(origin_z: float) -> void:
	_mesh.clear_surfaces()
	if _alpha <= 0.0 or _pts.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in _pts:
		var t := clampf((p.y - origin_z) / Tuning.trail_length, 0.0, 1.0)  # 0 at plane .. 1 at far end
		var half := Tuning.trail_width * 0.5 * (1.0 - 0.6 * t)
		var c := Color(_color.r, _color.g, _color.b, _alpha * (1.0 - t) * 0.85)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(Vector3(p.x - half, 0.0, p.y))
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(Vector3(p.x + half, 0.0, p.y))
	_mesh.surface_end()
