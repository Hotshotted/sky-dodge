extends Node3D
## The plane, seen from above. Moves freely in 2D (x = sideways, z = forward/back) using
## RELATIVE drag: it follows how far the finger moves, not where the finger is.

const PLANE_Y := 1.2  # model height: above the obstacles so it draws on top
## The plane's visible parts, used to build its collision shape (see hit_capsules). Model space.
const WING_Z := 0.1                      # wings are centred this far behind the origin
const WING_HALF := Vector2(1.1, 0.35)    # half span (x), half depth (z)
const BODY_Z := -0.075                   # fuselage + nose + tail fin, centred here
const BODY_HALF := Vector2(0.225, 1.125) # half width (x), half length (z): nose z -1.2 .. tail z 1.05
const WING_ROOT_X := 0.45                # the wing keeps its full chord out to here, then tapers
const WING_THICKNESS := 0.08
const BEAD_SPACING := 0.12               # collision circles along the wing (units apart)
const CAP_STRIDE := 5                    # hit_capsules() floats per shape: ax, az, bx, bz, radius

var velocity := Vector2.ZERO   # (x, z) velocity in units/s
var active := true             # false once crashed
var touching := false          # finger currently down?
var z_min := 0.0               # forward/back range, set by Main from the screen shape
var z_max := 0.0
var _zone_set := false
var _pending_drag := Vector2.ZERO  # finger pixels accumulated since last frame
var _input_vel := Vector2.ZERO     # smoothed velocity the finger is asking for
var _model: Node3D                 # visual child that banks/yaws
var _wing_beads := PackedFloat32Array()  # collision circles along the wing (x, z, radius), unrotated
var _caps := PackedFloat32Array()        # hit_capsules() output, updated in place every frame
var _hull_key := Vector2(-1.0, -1.0)     # (tip radius, hit scale) the collision was built for

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

## The wing's outline in model space: a tapered wing with rounded tips, the convex hull of a
## circle at each side of the root (full chord) and a circle at each tip. `tip_radius` sets how
## round / blunt the tips are (small = pointed taper, large = round, full chord = a stadium).
## The visible wing mesh AND the collision are both built from this one outline, so they can't
## drift apart.
static func wing_outline(tip_radius: float) -> PackedVector2Array:
	var rt := clampf(tip_radius, 0.02, WING_HALF.y)
	var xt := WING_HALF.x - rt                 # tip circle centre
	var xr := minf(WING_ROOT_X, xt)            # root circle centre
	var pts := PackedVector2Array()
	for sx in [-1.0, 1.0]:
		for i in 24:
			var a := TAU * i / 24.0
			pts.append(Vector2(sx * xr + cos(a) * WING_HALF.y, WING_Z + sin(a) * WING_HALF.y))
			pts.append(Vector2(sx * xt + cos(a) * rt, WING_Z + sin(a) * rt))
	return Geometry2D.convex_hull(pts)

## z-range of a convex outline at x: Vector2(low, high). (x outside the outline gives (INF, -INF).)
static func _chord(poly: PackedVector2Array, x: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if (a.x <= x and x <= b.x or b.x <= x and x <= a.x) and absf(b.x - a.x) > 0.000001:
			var z := a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
			lo = minf(lo, z)
			hi = maxf(hi, z)
	return Vector2(lo, hi)

## Collision-shape cache: the wing outline (scaled by plane_hit_scale) turned into a row of
## circles ("beads") whose radius follows the wing's chord, so the collision tapers and rounds off
## exactly like the visible wing. Rebuilt only when the tuning changes.
func _rebuild_collision() -> void:
	var k := Tuning.plane_hit_scale
	var outline := wing_outline(Tuning.plane_tip_radius)
	var scaled := PackedVector2Array()
	for p in outline:
		scaled.append(Vector2(p.x * k, WING_Z + (p.y - WING_Z) * k))
	var half_span := 0.0
	for p in scaled:
		half_span = maxf(half_span, absf(p.x))
	var rt := clampf(Tuning.plane_tip_radius, 0.02, WING_HALF.y) * k
	var xt := half_span - rt                   # centre of the (round) tip circle
	var n := maxi(int(ceil(2.0 * xt / BEAD_SPACING)), 1)
	_wing_beads = PackedFloat32Array()
	for i in n + 1:
		var x := -xt + 2.0 * xt * i / n
		var ch := _chord(scaled, x)
		var z := (ch.x + ch.y) * 0.5
		# Largest circle that fits INSIDE the outline here, so the collision never sticks out past
		# the visible wing (a circle as wide as the chord would poke out past the tapering edge).
		var r := INF
		for j in scaled.size():
			r = minf(r, Collision.point_segment(Vector2(x, z), scaled[j], scaled[(j + 1) % scaled.size()]))
		_wing_beads.append_array(PackedFloat32Array([x, z, r]))
	_caps.resize((n + 2) * CAP_STRIDE)         # the wing beads plus one fuselage capsule
	_hull_key = Vector2(Tuning.plane_tip_radius, Tuning.plane_hit_scale)

## Collision shapes as a flat array, CAP_STRIDE floats each: [ax, az, bx, bz, radius] = a segment
## a-b (relative to the plane's position) swept by a circle of that radius. The wing is a row of
## circles (a == b) that follow its tapering, rounded outline; the fuselage is one capsule with
## rounded nose and tail. All sized from the visible parts (times plane_hit_scale) and turned by
## the model's current yaw. The same array is rewritten every frame (nothing is allocated).
func hit_capsules() -> PackedFloat32Array:
	if _hull_key != Vector2(Tuning.plane_tip_radius, Tuning.plane_hit_scale):
		_rebuild_collision()
	var yaw := _model.rotation.y if _model else 0.0
	var c := cos(yaw)
	var s := sin(yaw)
	var o := 0
	for i in range(0, _wing_beads.size(), 3):
		var x := _wing_beads[i]
		var z := _wing_beads[i + 1]
		var rx := x * c + z * s       # rotate by yaw about the plane origin
		var rz := -x * s + z * c
		_caps[o] = rx
		_caps[o + 1] = rz
		_caps[o + 2] = rx
		_caps[o + 3] = rz
		_caps[o + 4] = _wing_beads[i + 2]
		o += CAP_STRIDE
	# Fuselage: segment along z with fully rounded ends (radius capped at the body's half width).
	var k := Tuning.plane_hit_scale
	var br := minf(Tuning.plane_hit_radius, BODY_HALF.x * k)
	var be := maxf(BODY_HALF.y * k - br, 0.0)
	var z0 := BODY_Z - be
	var z1 := BODY_Z + be
	_caps[o] = z0 * s
	_caps[o + 1] = z0 * c
	_caps[o + 2] = z1 * s
	_caps[o + 3] = z1 * c
	_caps[o + 4] = br
	return _caps

## Farthest sideways reach of the collision shape (the wingtip), unrotated.
func collision_half_span() -> float:
	if _hull_key != Vector2(Tuning.plane_tip_radius, Tuning.plane_hit_scale):
		_rebuild_collision()
	var m := 0.0
	for i in range(0, _wing_beads.size(), 3):
		m = maxf(m, absf(_wing_beads[i]) + _wing_beads[i + 2])
	return m

## Back to the start of a run (restart in place): centred, stopped, upright, controls live.
func reset() -> void:
	active = true
	velocity = Vector2.ZERO
	touching = false
	_pending_drag = Vector2.ZERO
	_input_vel = Vector2.ZERO
	_zone_set = false          # set_zone() will put the plane back at its start spot
	position = Vector3(0.0, PLANE_Y, position.z)
	_model.rotation = Vector3.ZERO

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
	var wings := MeshInstance3D.new()
	wings.mesh = _wing_mesh(wing_outline(Tuning.plane_tip_radius))
	var tail := _box(Vector3(0.08, 0.5, 0.5), Color(1.0, 0.45, 0.35))
	tail.position = Vector3(0, 0.3, 0.8)
	var nose := _box(Vector3(0.3, 0.25, 0.4), Color(0.9, 0.3, 0.3))
	nose.position = Vector3(0, 0, -1.0)
	for part in [body, wings, tail, nose]:
		_model.add_child(part)

## The visible wing: the outline extruded to a thin slab, flat-shaded.
func _wing_mesh(outline: PackedVector2Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := WING_THICKNESS * 0.5
	var centre := Vector2(0.0, WING_Z)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		# top and bottom: a triangle fan around the centre
		for face in [1.0, -1.0]:
			st.set_normal(Vector3(0, face, 0))
			for v in ([centre, a, b] if face > 0.0 else [centre, b, a]):
				st.add_vertex(Vector3(v.x, face * h, v.y))
		# rim: a quad facing outward
		var edge := b - a
		var n := Vector3(edge.y, 0.0, -edge.x).normalized()
		st.set_normal(n)
		for v in [Vector3(a.x, h, a.y), Vector3(b.x, h, b.y), Vector3(b.x, -h, b.y),
				Vector3(a.x, h, a.y), Vector3(b.x, -h, b.y), Vector3(a.x, -h, a.y)]:
			st.add_vertex(v)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.82, 0.25)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # winding can't make the wing vanish
	st.set_material(mat)
	return st.commit()

func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	mi.mesh = mesh
	return mi
