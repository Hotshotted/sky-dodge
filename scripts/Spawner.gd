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
	var entered := false                  # plane has been inside this row's depth window
	var passed := false                   # near-miss check already done
	var min_clear := INF                  # smallest gap seen while overlapping
	var min_idx := -1                     # obstacle that gave that gap

var _rows: Array[Row] = []
var _prev_open: Array[bool] = []   # open flags of previous row, index = column
var _last_row_z := 0.0
var _obstacle_mesh := BoxMesh.new()  # unit cube, scaled per obstacle
var _obstacle_mat := StandardMaterial3D.new()
var _outline_mat := ShaderMaterial.new()
var _stripe_mesh := BoxMesh.new()

func _ready() -> void:
	# One shared material (+ black outline pass) for every obstacle.
	_obstacle_mat.roughness = 1.0          # matte: flat, gradient-free shading
	_obstacle_mat.metallic_specular = 0.0
	_outline_mat.shader = preload("res://shaders/outline.gdshader")
	_obstacle_mat.next_pass = _outline_mat  # draws the black hull right after the cube itself
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

## True if a box at plane position `p` (x, z) touches any obstacle.
func hits(p: Vector2) -> bool:
	var half_w := Tuning.column_width() * Tuning.obstacle_scale * 0.5
	var half_d := Tuning.obstacle_depth * 0.5 + Tuning.plane_hit_half.y
	for r in _rows:
		if absf(r.position.z - p.y) > half_d:
			continue
		for cx in r.xs:
			if absf(cx - p.x) < half_w + Tuning.plane_hit_half.x:
				return true
	return false

## Call every frame with the plane position (x, z). For each row, tracks the smallest gap between
## the plane's hit box and an obstacle edge while the plane overlaps the row's depth, and when the
## row has fully passed returns a near-miss event if that gap was under near_miss_distance:
## {"side": -1/+1 (which side the obstacle was), "node": MeshInstance3D, "clearance": float}.
func update_near_misses(p: Vector2) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var half_w := Tuning.column_width() * Tuning.obstacle_scale * 0.5
	var half_d := Tuning.obstacle_depth * 0.5 + Tuning.plane_hit_half.y
	for r in _rows:
		if r.passed:
			continue
		var dz := r.position.z - p.y
		if absf(dz) < half_d:
			r.entered = true
			for i in r.xs.size():
				var gap := absf(r.xs[i] - p.x) - (half_w + Tuning.plane_hit_half.x)
				if gap < r.min_clear:
					r.min_clear = gap
					r.min_idx = i
		elif dz >= half_d:  # row has scrolled past the plane
			r.passed = true
			if r.entered and r.min_idx >= 0 and r.min_clear < Tuning.near_miss_distance:
				var side := 1 if r.xs[r.min_idx] > p.x else -1
				events.append({"side": side, "node": r.obs[r.min_idx], "clearance": r.min_clear})
	return events

## Flash one obstacle's outline white for near_miss_flash_time real seconds.
func flash_obstacle(mi: MeshInstance3D) -> void:
	var mat := _obstacle_mat.duplicate() as StandardMaterial3D
	var outline := _outline_mat.duplicate() as ShaderMaterial
	outline.set_shader_parameter("outline_color", Color.WHITE)
	outline.set_shader_parameter("thickness", Tuning.outline_thickness * 1.8)
	mat.next_pass = outline
	mi.material_override = mat
	# Real-time timer (ignores Engine.time_scale), so hitstop doesn't stretch the flash.
	get_tree().create_timer(Tuning.near_miss_flash_time, true, false, true).timeout.connect(
		func() -> void:
			if is_instance_valid(mi):
				mi.material_override = _obstacle_mat)

func _update_look() -> void:
	_obstacle_mat.albedo_color = Tuning.obstacle_color
	_outline_mat.set_shader_parameter("thickness", Tuning.outline_thickness)

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
		mi.scale = Vector3(width, width, Tuning.obstacle_depth)  # mesh is a unit cube
		mi.position = Vector3(x, 0, 0)
		row.add_child(mi)
		row.obs.append(mi)
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
