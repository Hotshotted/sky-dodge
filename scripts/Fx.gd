class_name Fx
extends Node3D
## Near-miss visual effects built from simple primitives that work in the Compatibility renderer:
## a spark burst (CPUParticles3D) and a few speed streaks (thin stretched boxes).
## Streak timing uses real time, so hitstop doesn't stretch it.

var _streaks: Array[Dictionary] = []  # {node, mat, z0, born_ms}
var _streak_mesh := BoxMesh.new()
const STREAK_LIFE := 0.35

func _init() -> void:
	_streak_mesh.size = Vector3(0.06, 0.04, 3.0)

## Burst of sparks at `pos` (a wingtip), flying outward toward `side` (-1 left / +1 right)
## and backward (+z) because the world scrolls past the plane.
func sparks(pos: Vector3, side: int) -> void:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = mat
	var ramp := Gradient.new()  # white-hot -> orange -> transparent
	ramp.colors = PackedColorArray([Color(1, 1, 0.85, 1), Color(1, 0.6, 0.15, 1), Color(1, 0.3, 0.05, 0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	p.mesh = quad
	p.color_ramp = ramp
	p.amount = Tuning.spark_count
	p.lifetime = Tuning.spark_lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3(side, 0.25, 0.9)
	p.spread = 65.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 13.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.emitting = false
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)

## Brief streaks that start ahead of the plane and rush past it (screen-down).
func streaks(origin: Vector3) -> void:
	for i in Tuning.streak_count:
		var mi := MeshInstance3D.new()
		mi.mesh = _streak_mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 1, 1, 0.8)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat
		var side := -1.0 if randf() < 0.5 else 1.0
		var z0 := origin.z - randf_range(2.0, 9.0)
		mi.position = Vector3(origin.x + side * randf_range(1.4, 4.2), origin.y, z0)
		add_child(mi)
		_streaks.append({"node": mi, "mat": mat, "z0": z0, "born": Time.get_ticks_msec()})

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for i in range(_streaks.size() - 1, -1, -1):
		var s: Dictionary = _streaks[i]
		var age := (now - int(s["born"])) / 1000.0
		if age >= STREAK_LIFE:
			(s["node"] as Node).queue_free()
			_streaks.remove_at(i)
			continue
		var mi := s["node"] as MeshInstance3D
		mi.position.z = float(s["z0"]) + Tuning.streak_speed * age
		var mat := s["mat"] as StandardMaterial3D
		mat.albedo_color.a = 0.8 * (1.0 - age / STREAK_LIFE)

## Remove everything currently alive (used after the startup pre-warm).
func clear() -> void:
	for c in get_children():
		c.queue_free()
	_streaks.clear()
