extends Node3D
## The plane. Moves freely in 2D (x = right, y = up) using RELATIVE drag:
## it follows how far the finger moves, not where the finger is.

var velocity := Vector2.ZERO   # current plane velocity (units/s)
var active := true             # false once crashed
var touching := false          # finger currently down?
var _pending_drag := Vector2.ZERO  # finger pixels accumulated since last frame (world-oriented: y up)
var _input_vel := Vector2.ZERO     # smoothed velocity the finger is asking for
var _model: Node3D                 # visual child that banks/pitches

func _ready() -> void:
	_build_model()

func _input(event: InputEvent) -> void:
	# With "emulate touch from mouse" on, mouse drags also arrive as these touch events.
	if event is InputEventScreenTouch:
		touching = event.pressed
	elif event is InputEventScreenDrag and active:
		# Screen y grows downward; world y grows upward.
		_pending_drag += Vector2(event.relative.x, -event.relative.y)

func _process(delta: float) -> void:
	if not active:
		return
	delta = minf(delta, 0.05)  # avoid huge steps after a hitch

	# 1) Turn finger movement into a smoothed target velocity.
	var raw := _pending_drag * Tuning.drag_sensitivity / delta
	raw = raw.limit_length(Tuning.max_move_speed)
	_pending_drag = Vector2.ZERO
	_input_vel = _input_vel.lerp(raw, 1.0 - exp(-Tuning.input_smoothing * delta))

	# 2) Update velocity per axis: accelerate, damp, or bleed off on reversal.
	for axis in 2:
		var want: float = _input_vel[axis]
		var v: float = velocity[axis]
		if absf(want) > 0.3:
			if v * want < 0.0 and absf(v) > 0.4:
				# Reversal penalty: old velocity dies out first; ~ln(100) decay over reversal_decay_time.
				v *= exp(-4.6 * delta / maxf(Tuning.reversal_decay_time, 0.01))
			else:
				v = move_toward(v, want, Tuning.move_accel * delta)
		else:
			v *= exp(-Tuning.move_damping * delta)
		velocity[axis] = v

	# 3) Soft snap toward the nearest hidden grid point once the finger is lifted.
	var pos := Vector2(position.x, position.y)
	if not touching and Tuning.snap_strength > 0.0:
		var target := _nearest_grid_point(pos)
		velocity += ((target - pos) * Tuning.snap_strength - velocity * Tuning.snap_damping) * delta

	# 4) Integrate and clamp to the flyable area.
	pos += velocity * delta
	var limit := Tuning.cell_size * Tuning.bounds_cells
	for axis in 2:
		if absf(pos[axis]) > limit:
			pos[axis] = signf(pos[axis]) * limit
			velocity[axis] = 0.0
	position = Vector3(pos.x, pos.y, 0.0)

	# 5) Visual banking (roll) and pitching, smoothed.
	var k := 1.0 - exp(-Tuning.tilt_smoothing * delta)
	_model.rotation.z = lerpf(_model.rotation.z, -velocity.x * Tuning.bank_amount, k)
	_model.rotation.x = lerpf(_model.rotation.x, velocity.y * Tuning.pitch_amount, k)

func crash() -> void:
	active = false

func _nearest_grid_point(p: Vector2) -> Vector2:
	var c := Tuning.cell_size
	return Vector2(clampf(roundf(p.x / c), -1.0, 1.0), clampf(roundf(p.y / c), -1.0, 1.0)) * c

## Greybox plane from primitives; nose points toward -Z.
func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	var body := _box(Vector3(0.45, 0.35, 1.8), Color(0.95, 0.95, 1.0))
	var wings := _box(Vector3(2.2, 0.08, 0.7), Color(1.0, 0.82, 0.25))
	wings.position = Vector3(0, 0, 0.1)
	var tail := _box(Vector3(0.08, 0.5, 0.5), Color(1.0, 0.45, 0.35))
	tail.position = Vector3(0, 0.3, 0.8)
	var nose := _box(Vector3(0.3, 0.25, 0.4), Color(0.9, 0.3, 0.3))
	nose.position = Vector3(0, 0, -1.0)
	for part in [body, wings, tail, nose]:
		_model.add_child(part)

func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	mi.mesh = mesh
	return mi
