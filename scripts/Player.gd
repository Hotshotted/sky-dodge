extends Node3D
## The plane, seen from above. Moves freely in 2D (x = sideways, z = forward/back) using
## RELATIVE drag: it follows how far the finger moves, not where the finger is.

const PLANE_Y := 1.2  # model height: above the obstacles so it draws on top

var velocity := Vector2.ZERO   # (x, z) velocity in units/s
var active := true             # false once crashed
var touching := false          # finger currently down?
var z_min := 0.0               # forward/back range, set by Main from the screen shape
var z_max := 0.0
var _zone_set := false
var _pending_drag := Vector2.ZERO  # finger pixels accumulated since last frame
var _input_vel := Vector2.ZERO     # smoothed velocity the finger is asking for
var _model: Node3D                 # visual child that banks/yaws

func _ready() -> void:
	position = Vector3(0, PLANE_Y, 0)
	_build_model()

## Main calls this every frame: the lower part of the screen the plane may use.
func set_zone(top: float, bottom: float) -> void:
	z_min = top
	z_max = bottom
	if not _zone_set:  # first call: start low in the zone, centred
		_zone_set = true
		position.z = lerpf(z_max, z_min, 0.25)

func _input(event: InputEvent) -> void:
	# With "emulate touch from mouse" on, mouse drags also arrive as these touch events.
	if event is InputEventScreenTouch:
		touching = event.pressed
	elif event is InputEventScreenDrag and active:
		touching = true  # also covers a finger that was already down when the run restarted
		# Screen right = +x, screen down = +z, so no axis flip is needed.
		_pending_drag += event.relative

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
			if Tuning.reversal_decay_time > 0.0 and v * want < 0.0 and absf(v) > 0.4:
				# Optional reversal penalty: old velocity dies out first; ~ln(100) decay over reversal_decay_time.
				v *= exp(-4.6 * delta / Tuning.reversal_decay_time)
			else:
				v = move_toward(v, want, Tuning.move_accel * delta)
		else:
			v *= exp(-Tuning.move_damping * delta)
		velocity[axis] = v

	# 3) Soft snap (sideways only) toward the nearest column centre once the finger is lifted.
	if not touching and Tuning.snap_strength > 0.0:
		var target := _nearest_column_x(position.x)
		velocity.x += ((target - position.x) * Tuning.snap_strength - velocity.x * Tuning.snap_damping) * delta

	# 4) Integrate and clamp to the flyable area (full width, lower part of the screen).
	var x := position.x + velocity.x * delta
	var z := position.z + velocity.y * delta
	var x_limit := Tuning.ortho_size * 0.5 - Tuning.plane_edge_margin
	if absf(x) > x_limit:
		x = signf(x) * x_limit
		velocity.x = 0.0
	if z < z_min or z > z_max:
		z = clampf(z, z_min, z_max)
		velocity.y = 0.0
	position = Vector3(x, PLANE_Y, z)

	# 5) Visual banking (roll) and a slight yaw into the movement, smoothed.
	var k := 1.0 - exp(-Tuning.tilt_smoothing * delta)
	_model.rotation.z = lerpf(_model.rotation.z, -velocity.x * Tuning.bank_amount, k)
	_model.rotation.y = lerpf(_model.rotation.y, -velocity.x * Tuning.yaw_amount, k)

func crash() -> void:
	active = false

func _nearest_column_x(x: float) -> float:
	var i := roundi(x / Tuning.column_width() + (Tuning.column_count - 1) * 0.5)
	return Tuning.column_center(clampi(i, 0, Tuning.column_count - 1))

## Greybox plane from primitives; nose points toward -Z (screen up).
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
