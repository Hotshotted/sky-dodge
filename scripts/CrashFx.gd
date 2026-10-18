class_name CrashFx
extends Node3D
## The crash sequence's visuals: a smoke trail behind the falling plane, a pop of debris, and Whiskers, who ejects with a
## parachute and drifts down. All created once; start() / stop() only move and show / hide them.
## The timeline is Main's (it passes the time since the crash to update()); nothing here touches Engine.time_scale.

const FLOOR_Y := -1.6
var _smoke: CPUParticles3D
var _debris: CPUParticles3D
var _whiskers: Node3D          # the little pilot
var _chute: Node3D             # the parachute (canopy + lines), opens after the ejection
var _vel := Vector3.ZERO
var _t_eject := 0.0
var _side := 1.0
var active := false

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.vertex_color_use_as_albedo = true
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = smat
	var ramp := Gradient.new()   # black smoke -> grey -> gone
	ramp.colors = PackedColorArray([Color(0.1, 0.1, 0.1, 0.9), Color(0.35, 0.35, 0.38, 0.6), Color(0.6, 0.6, 0.65, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	_smoke = CPUParticles3D.new()
	_smoke.mesh = quad
	_smoke.color_ramp = ramp
	_smoke.amount = 36
	_smoke.lifetime = 1.1
	_smoke.local_coords = false
	_smoke.direction = Vector3(0, 1, 0.4)
	_smoke.spread = 40.0
	_smoke.initial_velocity_min = 0.6
	_smoke.initial_velocity_max = 2.2
	_smoke.gravity = Vector3(0, 0.6, 1.5)
	_smoke.scale_amount_min = 0.5
	_smoke.scale_amount_max = 1.4
	_smoke.emitting = false
	_smoke.visible = false
	add_child(_smoke)
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 0.06, 0.1)
	var dmat := StandardMaterial3D.new()
	dmat.vertex_color_use_as_albedo = true
	dmat.roughness = 1.0
	box.material = dmat
	var dramp := Gradient.new()   # orange metal -> dark
	dramp.colors = PackedColorArray([Color(1.0, 0.65, 0.2), Color(0.85, 0.3, 0.15), Color(0.25, 0.25, 0.28)])
	dramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	_debris = CPUParticles3D.new()
	_debris.mesh = box
	_debris.color_ramp = dramp
	_debris.amount = 22
	_debris.lifetime = 1.0
	_debris.one_shot = true
	_debris.explosiveness = 1.0
	_debris.local_coords = false
	_debris.spread = 180.0
	_debris.initial_velocity_min = 3.0
	_debris.initial_velocity_max = 8.5
	_debris.gravity = Vector3(0, -7.0, 2.0)
	_debris.angular_velocity_min = -540.0
	_debris.angular_velocity_max = 540.0
	_debris.emitting = false
	_debris.visible = false
	add_child(_debris)
	# Whiskers: an orange cat in a harness (boxes), with a red and white parachute
	_whiskers = Node3D.new()
	_whiskers.visible = false
	add_child(_whiskers)
	_add_box(_whiskers, Vector3(0.36, 0.3, 0.32), Vector3(0, 0, 0), Color(0.95, 0.55, 0.15))
	_add_box(_whiskers, Vector3(0.34, 0.24, 0.3), Vector3(0, 0.26, 0), Color(1.0, 0.62, 0.2))
	_add_box(_whiskers, Vector3(0.08, 0.1, 0.06), Vector3(-0.12, 0.44, 0), Color(0.95, 0.5, 0.12))
	_add_box(_whiskers, Vector3(0.08, 0.1, 0.06), Vector3(0.12, 0.44, 0), Color(0.95, 0.5, 0.12))
	_add_box(_whiskers, Vector3(0.1, 0.05, 0.04), Vector3(0, 0.22, 0.16), Color(1, 1, 1))   # muzzle
	_add_box(_whiskers, Vector3(0.38, 0.05, 0.1), Vector3(0, 0.12, 0.0), Color(0.2, 0.25, 0.7))   # scarf
	_chute = Node3D.new()
	_whiskers.add_child(_chute)
	var dome := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.95
	sph.height = 0.95
	sph.is_hemisphere = true
	sph.radial_segments = 10
	sph.rings = 3
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.95, 0.25, 0.25)
	cmat.roughness = 1.0
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dome.mesh = sph
	dome.material_override = cmat
	dome.position = Vector3(0, 1.25, 0)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_chute.add_child(dome)
	for sgn in [-1.0, 1.0]:
		var line := _add_box(_chute, Vector3(0.02, 1.15, 0.02), Vector3(sgn * 0.35, 0.68, 0), Color(0.9, 0.9, 0.9))
		line.rotation.z = -sgn * 0.45
	_chute.visible = false

func _add_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## The crash happened at `pos`: debris pops, smoke starts, Whiskers is about to eject (`side` = which way he is thrown).
func start(pos: Vector3, side: float) -> void:
	active = true
	_side = side
	_t_eject = 0.0
	_debris.global_position = pos
	_debris.visible = true
	_debris.restart()
	_debris.emitting = true
	_smoke.global_position = pos
	_smoke.visible = true
	_smoke.restart()
	_smoke.emitting = true
	_whiskers.visible = false
	_chute.visible = false

## `t` = seconds since the crash, `delta` = this frame's step, `plane` = the falling plane.
func update(delta: float, t: float, plane: Vector3) -> void:
	if not active:
		return
	if t < 1.6:
		_smoke.global_position = plane
	else:
		_smoke.emitting = false
	if t >= 0.18 and not _whiskers.visible:   # the ejection
		_whiskers.visible = true
		_whiskers.position = plane + Vector3(0, 0.3, 0)
		_vel = Vector3(_side * 1.8, 5.5, -0.6)
		_t_eject = 0.0
		_chute.visible = true
		_chute.scale = Vector3(0.01, 0.01, 0.01)
	if _whiskers.visible:
		_t_eject += delta
		var open := clampf((_t_eject - 0.55) / 0.3, 0.0, 1.0)   # the parachute opens
		if open <= 0.0:
			_vel.y -= 9.0 * delta
		else:
			_vel.y = move_toward(_vel.y, -1.1, 7.0 * delta)
			_vel.x = move_toward(_vel.x, sin(_t_eject * 2.2) * 0.5, 3.0 * delta)
			_vel.z = move_toward(_vel.z, 0.2, 2.0 * delta)
		_chute.scale = Vector3.ONE * lerpf(0.01, 1.0, open * open * (3.0 - 2.0 * open))
		_whiskers.position += _vel * delta
		_whiskers.rotation.z = lerpf(_whiskers.rotation.z, 0.0 if open > 0.0 else _side * -0.8, minf(delta * 6.0, 1.0))
		if _whiskers.position.y < FLOOR_Y:
			_whiskers.position.y = FLOOR_Y
			_vel = Vector3.ZERO

func stop() -> void:
	active = false
	_smoke.emitting = false
	_smoke.visible = false
	_debris.emitting = false
	_debris.visible = false
	_whiskers.visible = false
	_chute.visible = false

## Pre-warm: draw everything once.
func prewarm_show(pos: Vector3) -> void:
	start(pos, 1.0)
	_whiskers.visible = true
	_whiskers.position = pos + Vector3(1.5, 0.5, 0)
	_chute.visible = true
	_chute.scale = Vector3.ONE
