extends Node3D
## Streams rows of obstacles toward the plane: the world scrolls toward +Z (screen-down)
## while the plane flies toward -Z (screen-up).
## Obstacles live on hidden columns across the screen width. Each row blocks a few columns
## and always leaves at least one open column that touches (same or adjacent column) an open
## column of the previous row, so there is always a path through.

const GROUND_Y := -2.0
const NEAR_RANGE := 4.0   # only rows within this many units (z) of the plane are collision-checked
const FAR_X := 3.2        # ...and only obstacles within this sideways distance (the wing reaches ~1.1 + a cube ~1)
const POOL_ROWS := 12     # rows created once at startup and reused forever (about 6 are alive at a time)

## One row of obstacles: a cube (with its own outline material) per column, created once and
## reused, plus the bookkeeping for near-miss detection.
class Row extends Node3D:
	var cubes: Array[MeshInstance3D] = []          # one per column; hidden when that column is open
	var cube_outlines: Array[ShaderMaterial] = []  # each cube's own outline material
	var stripe: MeshInstance3D
	var can: MeshInstance3D               # this row's fuel can (hidden unless has_can)
	var can_outline: ShaderMaterial
	var has_can := false
	var can_x := 0.0
	var xs: Array[float] = []             # x of each blocked column this time round
	var obs: Array[MeshInstance3D] = []   # the cubes in use (same order as xs)
	var outlines: Array[ShaderMaterial] = []  # their outline materials (same order)
	var entered := false                  # plane has been near this row
	var passed := false                   # near-miss check already done
	var min_clear := INF                  # closest approach seen
	var min_idx := -1                     # obstacle that gave it

	func clear_state() -> void:
		has_can = false
		xs.clear()
		obs.clear()
		outlines.clear()
		entered = false
		passed = false
		min_clear = INF
		min_idx = -1

var _rows: Array[Row] = []       # rows currently in play, nearest the top of the screen last
var _all_rows: Array[Row] = []   # every row ever created (the pool)
var _free_rows: Array[Row] = []  # pool rows not in play
var _prev_open: Array[bool] = []   # open flags of the last row spawned, index = column
var _pending_open: Array[bool] = []  # open flags of the NEXT row, generated one row early (so fuel can
									 # placement can tell which columns are about to close)
var _safe_col := 2                 # column of the main safe path through the last spawned row
var _can_mesh := BoxMesh.new()     # unit cube
var _can_mat := StandardMaterial3D.new()
var _picked: Array[Vector3] = []   # cans collected by the last collect_cans() call (reused)
var _last_row_z := 0.0
var _obstacle_mesh := BoxMesh.new()  # unit cube, scaled per obstacle
var _obstacle_mat := StandardMaterial3D.new()
var _outline_shader: Shader = preload("res://shaders/outline.gdshader")
var _stripe_mesh := BoxMesh.new()
var _last_thickness := -1.0
var _flashes: Array[Dictionary] = []   # {mat, end_ms}: outlines currently flashing white

func _ready() -> void:
	# One shared material for every cube. Each cube gets its OWN outline material (same shader),
	# so a near miss can flash one outline by changing a uniform, with no material swap.
	_obstacle_mat.roughness = 1.0          # matte: flat, gradient-free shading
	_obstacle_mat.metallic_specular = 0.0
	_can_mat.roughness = 1.0
	_can_mat.metallic_specular = 0.0
	_update_look()
	# Ground far below the obstacles; the stripes on each row give a sense of scrolling speed.
	var ground := MeshInstance3D.new()
	var gm := BoxMesh.new()
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.2, 0.26, 0.34)
	gm.material = gmat
	ground.mesh = gm
	ground.scale = Vector3(60.0, 0.1, 120.0)
	ground.position = Vector3(0, GROUND_Y - 0.1, 0)
	add_child(ground)
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_color = Color(0.3, 0.38, 0.5)
	_stripe_mesh.material = stripe_mat
	for i in POOL_ROWS:  # everything is created now, so nothing is allocated while playing
		_make_row()
	reset()

## Put every row back in the pool and start the obstacle stream over (restart in place). The first
## row of the new run appears at world z = first_row_z (negative = above the plane).
func reset(first_row_z: float = -12.0) -> void:
	for r in _rows.duplicate():
		_release_row(r)
	_rows.clear()
	_flashes.clear()
	_prev_open.clear()
	_pending_open.clear()
	_safe_col = Tuning.column_count / 2
	for i in Tuning.column_count:
		_prev_open.append(true)  # first row may use any column
	_last_row_z = first_row_z + Tuning.spawn_spacing

## Move the world toward the plane by `dist` units and spawn/remove rows as needed.
func advance(dist: float) -> void:
	_update_look()
	for r in _rows:
		r.position.z += dist
	_last_row_z += dist
	while _last_row_z > -Tuning.spawn_distance:
		_last_row_z -= Tuning.spawn_spacing
		_spawn_row(_last_row_z)
	while not _rows.is_empty() and _rows[0].position.z > Tuning.spawn_distance:
		_release_row(_rows.pop_front())

## Half size (x, z) of an obstacle as you SEE it: the cube plus its black outline rim.
func _obstacle_half() -> Vector2:
	return Vector2(Tuning.column_width() * Tuning.obstacle_scale * 0.5 + Tuning.outline_thickness,
			Tuning.obstacle_depth * 0.5 + Tuning.outline_thickness)

## Gap between plane shape number `i` (CAP_STRIDE floats at caps[i * stride]) and an obstacle (cube +
## outline) centred at (ox, oz): positive = clear space, negative = overlapping. `p` = plane (x, z).
func _gap(p: Vector2, caps: PackedFloat32Array, o: int, ox: float, oz: float, half: Vector2) -> float:
	var a := Vector2(p.x + caps[o] - ox, p.y + caps[o + 1] - oz)
	if caps[o] == caps[o + 2] and caps[o + 1] == caps[o + 3]:   # a circle: cheap path
		return Collision.point_rect(a, half) - caps[o + 4]
	var b := Vector2(p.x + caps[o + 2] - ox, p.y + caps[o + 3] - oz)
	return Collision.segment_rect(a, b, half) - caps[o + 4]

## True if any plane shape (see Player.hit_capsules) overlaps an obstacle.
func hits(p: Vector2, caps: PackedFloat32Array) -> bool:
	var half := _obstacle_half()
	for r in _rows:
		if absf(r.position.z - p.y) > NEAR_RANGE:
			continue
		for ox in r.xs:
			if absf(ox - p.x) > FAR_X:
				continue
			for o in range(0, caps.size(), 5):
				if _gap(p, caps, o, ox, r.position.z, half) < 0.0:
					return true
	return false

## Call every frame with the plane position (x, z) and its shapes. Each row remembers the
## closest approach (smallest gap between a plane shape and an obstacle) while it is near the
## plane; once the row has fully passed it returns a near-miss event if that closest approach was
## under near_miss_distance: {"side": -1/+1 (which side the obstacle was), "node", "outline"}.
func update_near_misses(p: Vector2, caps: PackedFloat32Array) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var half := _obstacle_half()
	var behind := -INF  # how far behind the plane origin its collision shape reaches
	for o in range(0, caps.size(), 5):
		behind = maxf(behind, maxf(caps[o + 1], caps[o + 3]) + caps[o + 4])
	for r in _rows:
		if r.passed:
			continue
		if absf(r.position.z - p.y) < NEAR_RANGE:
			r.entered = true
			for i in r.xs.size():
				if absf(r.xs[i] - p.x) > FAR_X:
					continue
				for o in range(0, caps.size(), 5):
					var gap := _gap(p, caps, o, r.xs[i], r.position.z, half)
					if gap < r.min_clear:
						r.min_clear = gap
						r.min_idx = i
		if r.position.z - p.y > behind + half.y:  # row has fully scrolled past the plane
			r.passed = true
			if r.entered and r.min_idx >= 0 and r.min_clear < Tuning.near_miss_distance:
				var side := 1 if r.xs[r.min_idx] > p.x else -1
				events.append({"side": side, "node": r.obs[r.min_idx], "outline": r.outlines[r.min_idx]})
	return events

## Flash one obstacle's outline white for near_miss_flash_time seconds: just uniform changes on
## the outline material it already has (no new material, no swap).
func flash_obstacle(outline: ShaderMaterial) -> void:
	outline.set_shader_parameter("outline_color", Color.WHITE)
	outline.set_shader_parameter("thickness", Tuning.outline_thickness * 1.8)
	_flashes.append({"mat": outline, "end": Time.get_ticks_msec() + int(Tuning.near_miss_flash_time * 1000.0)})

func _process(_delta: float) -> void:
	_update_flashes()  # runs even when the world isn't scrolling (e.g. on the crash screen)
	var t := Time.get_ticks_msec() / 1000.0
	for r in _rows:   # fuel cans bob gently so they read as pickups
		if r.has_can:
			r.can.position.y = 0.25 + 0.12 * sin(t * 4.0 + r.can_x)

func _update_flashes() -> void:
	var now := Time.get_ticks_msec()
	for i in range(_flashes.size() - 1, -1, -1):
		if now >= int(_flashes[i]["end"]):
			var m := _flashes[i]["mat"] as ShaderMaterial
			m.set_shader_parameter("outline_color", Color.BLACK)
			m.set_shader_parameter("thickness", Tuning.outline_thickness)
			_flashes.remove_at(i)

func _new_outline() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _outline_shader
	m.set_shader_parameter("thickness", Tuning.outline_thickness)
	return m

## Startup pre-warm: show EVERY pooled cube in view (alternate rows with a white outline) so each
## cube's outline material, and the cube material and shader, are drawn before real play.
func prewarm_show(with_flash: bool) -> void:
	for idx in _all_rows.size():
		var row := _all_rows[idx]
		row.position = Vector3(0.0, 0.0, -8.0 + 1.5 * idx)
		row.visible = true
		for i in row.cubes.size():
			var mi := row.cubes[i]
			mi.visible = true
			mi.position = Vector3(Tuning.column_center(i), 0.0, 0.0)
			mi.scale = Vector3.ONE
			row.cube_outlines[i].set_shader_parameter("outline_color", Color.WHITE if (with_flash and idx % 2 == 1) else Color.BLACK)
		row.can.visible = true   # every pooled fuel can is drawn too
		row.can.position = Vector3(Tuning.column_center(idx % Tuning.column_count), 0.4, 0.5)
		row.can.scale = Vector3.ONE * Tuning.fuel_can_size

## End of the pre-warm: hide the pooled rows again.
func prewarm_hide() -> void:
	for row in _all_rows:
		_hide_row(row)

## Test helper: put a row at z with obstacles at the given x positions (no randomness).
func _rows_make_for_test(z: float, xs: Array) -> Row:
	var row := _acquire_row()
	row.position = Vector3(0.0, 0.0, z)
	row.visible = true
	for k in xs.size():
		row.xs.append(xs[k])
		row.obs.append(row.cubes[k])
		row.outlines.append(row.cube_outlines[k])
	_rows.append(row)
	return row

func _update_look() -> void:
	_obstacle_mat.albedo_color = Tuning.obstacle_color
	_can_mat.albedo_color = Tuning.fuel_can_color
	if Tuning.outline_thickness != _last_thickness:  # live-tuning: push a changed width to every outline
		_last_thickness = Tuning.outline_thickness
		for r in _all_rows:
			for m in r.cube_outlines:
				m.set_shader_parameter("thickness", Tuning.outline_thickness)
			r.can_outline.set_shader_parameter("thickness", Tuning.outline_thickness)

## Create one pooled row (cubes + outline materials + stripe), hidden, and add it to the pool.
func _make_row() -> Row:
	var row := Row.new()
	for i in Tuning.column_count:
		var mi := MeshInstance3D.new()
		mi.mesh = _obstacle_mesh
		mi.material_override = _obstacle_mat
		var outline := _new_outline()
		mi.material_overlay = outline  # black inverted-hull outline drawn over the cube
		mi.visible = false
		row.add_child(mi)
		row.cubes.append(mi)
		row.cube_outlines.append(outline)
	row.can = MeshInstance3D.new()
	row.can.mesh = _can_mesh
	row.can.material_override = _can_mat
	row.can_outline = _new_outline()
	row.can.material_overlay = row.can_outline
	row.can.visible = false
	row.add_child(row.can)
	row.stripe = MeshInstance3D.new()
	row.stripe.mesh = _stripe_mesh
	row.stripe.position = Vector3(0, GROUND_Y, 0)
	row.add_child(row.stripe)
	row.visible = false
	add_child(row)
	_all_rows.append(row)
	_free_rows.append(row)
	return row

func _acquire_row() -> Row:
	if _free_rows.is_empty():
		_make_row()  # only if the pool was too small (live-tuned spacing); normally never
	var row: Row = _free_rows.pop_back()
	row.clear_state()
	return row

func _release_row(row: Row) -> void:
	_hide_row(row)
	row.clear_state()
	_rows.erase(row)
	if not _free_rows.has(row):
		_free_rows.append(row)

func _hide_row(row: Row) -> void:
	row.visible = false
	row.can.visible = false
	row.has_can = false
	for i in row.cubes.size():
		row.cubes[i].visible = false
		row.cube_outlines[i].set_shader_parameter("outline_color", Color.BLACK)
		row.cube_outlines[i].set_shader_parameter("thickness", Tuning.outline_thickness)

func _spawn_row(z: float) -> void:
	# Rows are generated one ahead: `open` is this row, `next_open` the row after it.
	var open: Array[bool] = _pending_open if not _pending_open.is_empty() else _generate_open_columns(_prev_open)
	var next_open := _generate_open_columns(open)
	_prev_open = open
	_pending_open = next_open
	_safe_col = _pick_safe_col(open, _safe_col)
	var row := _acquire_row()
	row.position = Vector3(0.0, 0.0, z)
	row.visible = true
	var width := Tuning.column_width() * Tuning.obstacle_scale
	for i in mini(Tuning.column_count, row.cubes.size()):
		if open[i]:
			continue
		var x := Tuning.column_center(i)
		var mi := row.cubes[i]
		mi.position = Vector3(x, 0, 0)
		mi.scale = Vector3(width, width, Tuning.obstacle_depth)  # mesh is a unit cube
		mi.visible = true
		row.xs.append(x)
		row.obs.append(mi)
		row.outlines.append(row.cube_outlines[i])
	row.stripe.scale = Vector3(Tuning.ortho_size * 2.0, 0.1, 0.4)
	var can_col := _choose_can_column(open, next_open, _safe_col)
	if can_col >= 0:
		_place_can(row, Tuning.column_center(can_col))
	_rows.append(row)

func _place_can(row: Row, x: float) -> void:
	row.has_can = true
	row.can_x = x
	row.can.position = Vector3(x, 0.25, 0.0)
	row.can.scale = Vector3.ONE * Tuning.fuel_can_size
	row.can_outline.set_shader_parameter("outline_color", Color.BLACK)
	row.can_outline.set_shader_parameter("thickness", Tuning.outline_thickness)
	row.can.visible = true

## The main safe path: the open column with the most open neighbours, i.e. the widest gap (ties go
## to the one closest to the previous safe column). This is where a careful player flies.
func _pick_safe_col(open: Array[bool], prev_safe: int) -> int:
	var n := open.size()
	var best := -1
	var best_score := -INF
	for c in n:
		if not open[c]:
			continue
		var score := 10.0 * (int(c > 0 and open[c - 1]) + int(c < n - 1 and open[c + 1])) - absi(c - prev_safe)
		if score > best_score:
			best_score = score
			best = c
	return best

## Which column (if any) gets a fuel can in the row whose open columns are `open`, given the next
## row's open columns and the safe-path column `safe`. A can goes in an open column, with chance
## fuel_can_chance. Then with probability fuel_risk_bias it is put in a RISKY column (not on the
## safe path, and next to an obstacle or in a column that closes next row; the riskier the more
## likely), otherwise in any open column. Returns -1 for no can.
func _choose_can_column(open: Array[bool], next_open: Array[bool], safe: int) -> int:
	if randf() >= Tuning.fuel_can_chance:
		return -1
	var n := open.size()
	var anywhere: Array[int] = []
	var risky: Array[int] = []
	var weights: Array[float] = []
	for c in n:
		if not open[c]:
			continue
		anywhere.append(c)
		if c == safe:
			continue
		var beside := int(c > 0 and not open[c - 1]) + int(c < n - 1 and not open[c + 1])  # obstacles next to it
		var closes := int(not next_open[c])                                                # blocked next row
		if beside > 0 or closes > 0:
			risky.append(c)
			weights.append(1.0 + beside + 2.0 * closes + float(absi(c - safe) >= 2))
	if randf() < Tuning.fuel_risk_bias:
		if risky.is_empty():
			return -1          # no risky spot in this row: no can (don't leak one onto the safe path)
		var total := 0.0
		for w in weights:
			total += w
		var roll := randf() * total
		for i in risky.size():
			roll -= weights[i]
			if roll <= 0.0:
				return risky[i]
		return risky[-1]
	return anywhere.pick_random() if not anywhere.is_empty() else -1

## Collect any fuel can the plane's shapes touch. Returns the world position of each can picked up
## (the same array object every call: nothing is allocated).
func collect_cans(p: Vector2, caps: PackedFloat32Array) -> Array[Vector3]:
	_picked.clear()
	for r in _rows:
		if not r.has_can or absf(r.position.z - p.y) > NEAR_RANGE:
			continue
		var centre := Vector2(r.can_x, r.position.z)
		for o in range(0, caps.size(), 5):
			var a := Vector2(p.x + caps[o], p.y + caps[o + 1])
			var b := Vector2(p.x + caps[o + 2], p.y + caps[o + 3])
			if Collision.point_segment(centre, a, b) - caps[o + 4] < Tuning.fuel_pickup_radius:
				r.has_can = false
				r.can.visible = false
				_picked.append(Vector3(r.can_x, 0.4, r.position.z))
				break
	return _picked

## Apply the current obstacle_scale / can size to rows already in play (used by the tuning panel,
## so a slider change shows up at once instead of only on newly spawned rows).
func refresh_obstacles() -> void:
	var width := Tuning.column_width() * Tuning.obstacle_scale
	for r in _rows:
		for mi in r.obs:
			mi.scale = Vector3(width, width, Tuning.obstacle_depth)
		if r.has_can:
			r.can.scale = Vector3.ONE * Tuning.fuel_can_size

## Test helper: put a fuel can on a row.
func _place_can_for_test(row: Row, x: float) -> void:
	_place_can(row, x)

## Pick which columns are open: choose one guaranteed-open column that is reachable from the
## previous row's open columns, then block a random number of the others.
func _generate_open_columns(prev: Array[bool]) -> Array[bool]:
	var n := Tuning.column_count
	var reachable: Array[int] = []
	for i in n:
		for j in n:
			if prev[j] and absi(i - j) <= 1:
				reachable.append(i)
				break
	var guaranteed: int = reachable.pick_random()
	var blocked := clampi(randi_range(Tuning.blocked_columns_min, Tuning.blocked_columns_max), 0, n - 1)
	var others: Array[int] = []
	for i in n:
		if i != guaranteed:
			others.append(i)
	others.shuffle()
	var open: Array[bool] = []
	for i in n:
		open.append(true)
	for k in blocked:
		open[others[k]] = false
	return open
