extends Node3D
## Streams rows of obstacles toward the plane: the world scrolls toward +Z (screen-down)
## while the plane flies toward -Z (screen-up).
## Obstacles live on hidden columns across the screen width. Each row blocks a few columns
## and always leaves at least one open column that touches (same or adjacent column) an open
## column of the previous row, so there is always a path through.

const GROUND_Y := -2.0

## One row of obstacles, plus the bookkeeping for near-miss detection.
class Row extends Node3D:
	var xs: Array[float] = []             # x of each obstacle
	var obs: Array[MeshInstance3D] = []   # the obstacle nodes (same order)
	var outlines: Array[ShaderMaterial] = []  # each obstacle's own outline material (same order)
	var entered := false                  # plane has been inside this row's depth window
	var passed := false                   # near-miss check already done
	var min_clear := INF                  # smallest gap seen while overlapping
	var min_idx := -1                     # obstacle that gave that gap

var _rows: Array[Row] = []
var _prev_open: Array[bool] = []   # open flags of previous row, index = column
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
	reset()

func reset() -> void:
	for r in _rows:
		r.queue_free()
	_rows.clear()
	_prev_open.clear()
	for i in Tuning.column_count:
		_prev_open.append(true)  # first row may use any column
	_last_row_z = -Tuning.first_row_distance + Tuning.spawn_spacing

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
		_rows.pop_front().queue_free()

## Half size (x, z) of an obstacle as you SEE it: the cube plus its black outline rim.
func _obstacle_half() -> Vector2:
	return Vector2(Tuning.column_width() * Tuning.obstacle_scale * 0.5 + Tuning.outline_thickness,
			Tuning.obstacle_depth * 0.5 + Tuning.outline_thickness)

## True if any of the plane's collision boxes (see Player.hit_boxes) overlaps an obstacle.
## `p` = plane position (x, z).
func hits(p: Vector2, boxes: Array[Vector4]) -> bool:
	var half := _obstacle_half()
	for r in _rows:
		for ox in r.xs:
			for b in boxes:
				if absf(r.position.z - (p.y + b.y)) < half.y + b.w and absf(ox - (p.x + b.x)) < half.x + b.z:
					return true
	return false

## Call every frame with the plane position (x, z) and its collision boxes. For each row, tracks
## the smallest sideways gap between a plane box and an obstacle edge while they overlap in depth,
## and once the row has fully passed returns a near-miss event if that gap was under
## near_miss_distance: {"side": -1/+1 (which side the obstacle was), "node": MeshInstance3D}.
func update_near_misses(p: Vector2, boxes: Array[Vector4]) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var half := _obstacle_half()
	var behind := -INF  # how far behind the plane origin its collision shape reaches
	for b in boxes:
		behind = maxf(behind, b.y + b.w)
	for r in _rows:
		if r.passed:
			continue
		for b in boxes:
			if absf(r.position.z - (p.y + b.y)) < half.y + b.w:  # this box overlaps the row in depth
				r.entered = true
				for i in r.xs.size():
					var gap := absf(r.xs[i] - (p.x + b.x)) - (half.x + b.z)
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

## Startup pre-warm: two cubes in view (one drawn white-outlined) so the cube material and the
## outline shader get compiled before the first real obstacle / near miss. Caller frees them.
func prewarm_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = _obstacle_mesh
		mi.material_override = _obstacle_mat
		var outline := _new_outline()
		if i == 1:
			outline.set_shader_parameter("outline_color", Color.WHITE)
		mi.material_overlay = outline
		mi.position = Vector3(-2.0 + 4.0 * i, 0, 0)
		add_child(mi)
		nodes.append(mi)
	return nodes

func _update_look() -> void:
	_obstacle_mat.albedo_color = Tuning.obstacle_color
	if Tuning.outline_thickness != _last_thickness:  # live-tuning: push a changed width to every outline
		_last_thickness = Tuning.outline_thickness
		for r in _rows:
			for m in r.outlines:
				m.set_shader_parameter("thickness", Tuning.outline_thickness)

func _spawn_row(z: float) -> void:
	var open := _generate_open_columns()
	_prev_open = open
	var row := Row.new()
	row.position.z = z
	var width := Tuning.column_width() * Tuning.obstacle_scale
	for i in Tuning.column_count:
		if open[i]:
			continue
		var x := Tuning.column_center(i)
		row.xs.append(x)
		var mi := MeshInstance3D.new()
		mi.mesh = _obstacle_mesh
		mi.material_override = _obstacle_mat
		var outline := _new_outline()
		mi.material_overlay = outline  # black inverted-hull outline drawn over the cube
		mi.scale = Vector3(width, width, Tuning.obstacle_depth)  # mesh is a unit cube
		mi.position = Vector3(x, 0, 0)
		row.add_child(mi)
		row.obs.append(mi)
		row.outlines.append(outline)
	var stripe := MeshInstance3D.new()
	stripe.mesh = _stripe_mesh
	stripe.scale = Vector3(Tuning.ortho_size * 2.0, 0.1, 0.4)
	stripe.position = Vector3(0, GROUND_Y, 0)
	row.add_child(stripe)
	add_child(row)
	_rows.append(row)

## Pick which columns are open: choose one guaranteed-open column that is reachable from the
## previous row's open columns, then block a random number of the others.
func _generate_open_columns() -> Array[bool]:
	var n := Tuning.column_count
	var reachable: Array[int] = []
	for i in n:
		for j in n:
			if _prev_open[j] and absi(i - j) <= 1:
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
