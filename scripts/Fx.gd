class_name Fx
extends Node3D
## Near-miss visual effects built from simple primitives that work in the Compatibility renderer:
## a spark burst (CPUParticles3D) and a few speed streaks (thin stretched boxes).
## Everything is created ONCE at startup and reused, so a near miss allocates nothing.
## Streak timing uses real time.

const SPARK_EMITTERS := 2    # round-robin, so overlapping bursts don't cut each other off
const PICKUP_EMITTERS := 2   # fuel-pickup bursts, round-robin
const STREAK_POOL := 24      # max Tuning.streak_count
const STREAK_LIFE := 0.35

var _pickup_emitters: Array[CPUParticles3D] = []
var _next_pickup := 0
var _emitters: Array[CPUParticles3D] = []
var _next_emitter := 0
var _streak_nodes: Array[MeshInstance3D] = []
var _streak_mats: Array[StandardMaterial3D] = []
var _streak_z0 := PackedFloat32Array()
var _streak_born := PackedInt64Array()   # real ms when started; 0 = idle
var _next_streak := 0
const WHISKER_EMITTERS := 2
var _whisker_emitters: Array[CPUParticles3D] = []   # the gold burst of a Whisker close (pooled like the rest)
var _next_whisker := 0
const COIN_EMITTERS := 2
var _coin_emitters: Array[CPUParticles3D] = []      # the gold burst of a Close Call Pay
var _next_coin := 0

func _ready() -> void:
	# Spark emitters: configured once, restarted for each burst.
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
	for i in SPARK_EMITTERS:
		var p := CPUParticles3D.new()
		p.mesh = quad
		p.color_ramp = ramp
		p.amount = Tuning.spark_count
		p.lifetime = Tuning.spark_lifetime
		p.one_shot = true
		p.explosiveness = 1.0
		p.local_coords = false
		p.spread = 65.0
		p.initial_velocity_min = 5.0
		p.initial_velocity_max = 13.0
		p.gravity = Vector3.ZERO
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.2
		p.emitting = false
		add_child(p)
		_emitters.append(p)
	# Whisker-close burst: a bigger, gold-and-pink ring of sparks, all around the plane.
	var w_quad := QuadMesh.new()
	w_quad.size = Vector2(0.36, 0.36)
	var w_mat := StandardMaterial3D.new()
	w_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	w_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	w_mat.vertex_color_use_as_albedo = true
	w_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	w_quad.material = w_mat
	var w_ramp := Gradient.new()   # white -> gold -> pink -> transparent
	w_ramp.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 0.85, 0.2, 1), Color(1, 0.3, 0.85, 0.7), Color(1, 0.3, 0.85, 0)])
	w_ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	for i in WHISKER_EMITTERS:
		var p := CPUParticles3D.new()
		p.mesh = w_quad
		p.color_ramp = w_ramp
		p.amount = 30
		p.lifetime = 0.6
		p.one_shot = true
		p.explosiveness = 1.0
		p.local_coords = false
		p.direction = Vector3(0, 1, 0)
		p.spread = 180.0
		p.initial_velocity_min = 6.0
		p.initial_velocity_max = 16.0
		p.gravity = Vector3.ZERO
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4
		p.emitting = false
		p.visible = false
		add_child(p)
		_whisker_emitters.append(p)
	# Close Call Pay: a small gold burst of coins.
	var c_quad := QuadMesh.new()
	c_quad.size = Vector2(0.3, 0.3)
	var c_mat := StandardMaterial3D.new()
	c_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	c_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	c_mat.vertex_color_use_as_albedo = true
	c_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	c_quad.material = c_mat
	var c_ramp := Gradient.new()
	c_ramp.colors = PackedColorArray([Color(1, 0.95, 0.5, 1), Color(1, 0.8, 0.15, 1), Color(1, 0.7, 0.1, 0)])
	c_ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	for i in COIN_EMITTERS:
		var p := CPUParticles3D.new()
		p.mesh = c_quad
		p.color_ramp = c_ramp
		p.amount = 10
		p.lifetime = 0.5
		p.one_shot = true
		p.explosiveness = 1.0
		p.local_coords = false
		p.direction = Vector3(0, 1, -0.4)
		p.spread = 70.0
		p.initial_velocity_min = 4.0
		p.initial_velocity_max = 9.0
		p.gravity = Vector3.ZERO
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.2
		p.emitting = false
		p.visible = false
		add_child(p)
		_coin_emitters.append(p)
	# Fuel pickup bursts: green puffs rising from the can, same kind of emitter as the sparks.
	var pop_quad := QuadMesh.new()
	pop_quad.size = Vector2(0.34, 0.34)
	var pop_mat := StandardMaterial3D.new()
	pop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pop_mat.vertex_color_use_as_albedo = true
	pop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pop_quad.material = pop_mat
	var pop_ramp := Gradient.new()  # bright green -> fresh green -> transparent
	pop_ramp.colors = PackedColorArray([Color(0.85, 1, 0.8, 1), Color(0.25, 1, 0.5, 1), Color(0.1, 0.8, 0.3, 0)])
	pop_ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	for i in PICKUP_EMITTERS:
		var p := CPUParticles3D.new()
		p.mesh = pop_quad
		p.color_ramp = pop_ramp
		p.amount = Tuning.fuel_pop_count
		p.lifetime = 0.5
		p.one_shot = true
		p.explosiveness = 1.0
		p.local_coords = false
		p.direction = Vector3(0, 1, 0)
		p.spread = 180.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 7.0
		p.gravity = Vector3.ZERO
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.3
		p.emitting = false
		p.visible = false
		add_child(p)
		_pickup_emitters.append(p)
	# Streaks: thin stretched boxes, hidden until used.
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.04, 3.0)
	for i in STREAK_POOL:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1, 1, 1, 0.8)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = m
		mi.visible = false
		add_child(mi)
		_streak_nodes.append(mi)
		_streak_mats.append(m)
	_streak_z0.resize(STREAK_POOL)
	_streak_born.resize(STREAK_POOL)

## Burst of sparks at `pos` (a wingtip), flying outward toward `side` (-1 left / +1 right)
## and backward (+z) because the world scrolls past the plane.
func sparks(pos: Vector3, side: int) -> void:
	var p := _emitters[_next_emitter]
	_next_emitter = (_next_emitter + 1) % SPARK_EMITTERS
	if p.amount != Tuning.spark_count:  # only touch these when live-tuned (they reallocate buffers)
		p.amount = Tuning.spark_count
	if p.lifetime != Tuning.spark_lifetime:
		p.lifetime = Tuning.spark_lifetime
	p.direction = Vector3(side, 0.25, 0.9)
	p.global_position = pos
	p.visible = true
	p.restart()
	p.emitting = true

## The special burst of a Whisker close, all around `pos`.
func whisker(pos: Vector3) -> void:
	var p := _whisker_emitters[_next_whisker]
	_next_whisker = (_next_whisker + 1) % WHISKER_EMITTERS
	p.global_position = pos
	p.visible = true
	p.restart()
	p.emitting = true

## A small gold burst of coins (Close Call Pay).
func coins(pos: Vector3) -> void:
	var p := _coin_emitters[_next_coin]
	_next_coin = (_next_coin + 1) % COIN_EMITTERS
	p.global_position = pos
	p.visible = true
	p.restart()
	p.emitting = true

## Green burst where a fuel can was picked up (pooled emitters; nothing is allocated).
func pickup(pos: Vector3) -> void:
	var p := _pickup_emitters[_next_pickup]
	_next_pickup = (_next_pickup + 1) % PICKUP_EMITTERS
	if p.amount != Tuning.fuel_pop_count:
		p.amount = Tuning.fuel_pop_count
	p.global_position = pos
	p.visible = true
	p.restart()
	p.emitting = true

## Brief streaks that start ahead of the plane and rush past it (screen-down).
func streaks(origin: Vector3) -> void:
	for n in mini(Tuning.streak_count, STREAK_POOL):
		var i := _next_streak
		_next_streak = (_next_streak + 1) % STREAK_POOL
		var side := -1.0 if randf() < 0.5 else 1.0
		var z0 := origin.z - randf_range(2.0, 9.0)
		_streak_z0[i] = z0
		_streak_born[i] = Time.get_ticks_msec()
		_streak_nodes[i].position = Vector3(origin.x + side * randf_range(1.4, 4.2), origin.y, z0)
		_streak_mats[i].albedo_color.a = 0.8
		_streak_nodes[i].visible = true

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for i in STREAK_POOL:
		if _streak_born[i] == 0:
			continue
		var age := (now - _streak_born[i]) / 1000.0
		if age >= STREAK_LIFE:
			_streak_nodes[i].visible = false
			_streak_born[i] = 0
			continue
		_streak_nodes[i].position.z = _streak_z0[i] + Tuning.streak_speed * age
		_streak_mats[i].albedo_color.a = 0.8 * (1.0 - age / STREAK_LIFE)

## Pre-warm: show EVERY pooled streak at once around `origin`, so each one's material is drawn
## at least once. Call every frame during the pre-warm to keep them from expiring.
func show_all_streaks(origin: Vector3) -> void:
	for i in STREAK_POOL:
		_streak_z0[i] = origin.z - 2.0 - 0.3 * i
		_streak_born[i] = Time.get_ticks_msec()
		_streak_nodes[i].position = Vector3(origin.x + (-3.0 if i % 2 == 0 else 3.0) * (0.4 + 0.05 * i), origin.y, _streak_z0[i])
		_streak_mats[i].albedo_color.a = 0.8
		_streak_nodes[i].visible = true

## Stop and hide everything currently alive (used after the startup pre-warm).
func clear() -> void:
	for p in _emitters:
		p.emitting = false
		p.restart()
		p.emitting = false
		p.visible = false  # emitting=false alone leaves already-spawned particles on screen
	for p in _pickup_emitters:
		p.emitting = false
		p.restart()
		p.emitting = false
		p.visible = false
	for p in _whisker_emitters:
		p.emitting = false
		p.restart()
		p.emitting = false
		p.visible = false
	for p in _coin_emitters:
		p.emitting = false
		p.restart()
		p.emitting = false
		p.visible = false
	for i in STREAK_POOL:
		_streak_nodes[i].visible = false
		_streak_born[i] = 0
