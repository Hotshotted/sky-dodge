extends Node3D
## The plane, seen from above. A floating virtual stick steers it in 2D
## (x = sideways, z = forward/back): stick deflection sets the target velocity.

signal stick_changed(active: bool, base: Vector2, knob: Vector2)  # drives the on-screen stick

const PLANE_Y := 1.2  # model height: above the obstacles so it draws on top

var velocity := Vector2.ZERO   # (x, z) velocity in units/s
var active := true             # false once crashed
var z_min := 0.0               # forward/back range, set by Main from the screen shape
var z_max := 0.0
var _zone_set := false
var _touch_index := -1             # finger that owns the stick (-1 = none)
var _origin := Vector2.ZERO        # where that finger first touched (stick base), screen px
var _deflection := Vector2.ZERO    # stick output, length 0..1 (after dead zone)
var _snapping := false             # released and nearly stopped: easing to a column centre
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
	if not active:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_begin(event.index, event.position)
		elif not event.pressed and event.index == _touch_index:
			_end()
	elif event is InputEventScreenDrag:
		if _touch_index == -1:  # finger already down when the run (re)started
			_begin(event.index, event.position)
		elif event.index == _touch_index:
			_move(event.position)

func _begin(index: int, pos: Vector2) -> void:
	_touch_index = index
	_origin = pos
	_snapping = false
	_move(pos)

func _end() -> void:
	_touch_index = -1
	_deflection = Vector2.ZERO
	stick_changed.emit(false, _origin, _origin)

func _move(pos: Vector2) -> void:
	var offset := (pos - _origin).limit_length(Tuning.stick_max_radius)  # knob stays inside the ring
	var raw := offset.length() / Tuning.stick_max_radius                 # 0..1
	var dz := Tuning.stick_dead_zone
	var mag := 0.0 if raw < dz else (raw - dz) / (1.0 - dz)              # dead zone, rescaled to 0..1
	_deflection = offset.normalized() * mag
	stick_changed.emit(true, _origin, _origin + offset)

func _process(delta: float) -> void:
	if not active:
		return
	delta = minf(delta, 0.05)  # avoid huge steps after a hitch

	# 1) Target velocity: stick direction x deflection x max speed (screen right = +x, down = +z).
	var target := _deflection * Tuning.plane_max_speed

	# 2) After release and a full stop, ease sideways toward the nearest column centre.
	if _touch_index == -1 and Tuning.snap_strength > 0.0:
		if velocity.length() < Tuning.snap_start_speed:
			_snapping = true
		if _snapping:
			target.x = (_nearest_column_x(position.x) - position.x) * Tuning.snap_strength

	# 3) Velocity approaches the target (about response_time seconds), per axis.
	var k := 1.0 - exp(-3.0 * delta / maxf(Tuning.plane_response_time, 0.001))
	for axis in 2:
		var v: float = velocity[axis]
		var want: float = target[axis]
		if Tuning.reversal_decay_time > 0.0 and v * want < 0.0 and absf(v) > 0.4:
			# Optional reversal penalty: old velocity dies out first (~ln(100) decay).
			v *= exp(-4.6 * delta / Tuning.reversal_decay_time)
		else:
			v = lerpf(v, want, k)
		velocity[axis] = v

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
	var tk := 1.0 - exp(-Tuning.tilt_smoothing * delta)
	_model.rotation.z = lerpf(_model.rotation.z, -velocity.x * Tuning.bank_amount, tk)
	_model.rotation.y = lerpf(_model.rotation.y, -velocity.x * Tuning.yaw_amount, tk)

func crash() -> void:
	active = false
	_end()

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
