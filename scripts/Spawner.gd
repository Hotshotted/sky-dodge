extends Node3D
## Streams rows of obstacles toward the plane (the plane stays at z = 0; the world moves +Z).
## Obstacles live on a hidden 3x3 grid. Each row blocks a few cells and always leaves
## at least one open cell that touches (incl. diagonally) an open cell of the previous row,
## so there is always a path through.

var _rows: Array[Node3D] = []
var _prev_open: Array[bool] = []   # open flags of previous row, index = gx + 3*gy (0..8)
var _last_row_z := 0.0
var _obstacle_mesh: BoxMesh
var _stripe_mesh: BoxMesh

func _ready() -> void:
	_obstacle_mesh = BoxMesh.new()  # unit cube; each row supplies its own material (for fading)
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_color = Color(0.3, 0.38, 0.5)
	_stripe_mesh = BoxMesh.new()
	_stripe_mesh.material = stripe_mat
	# Static ground far below the grid so the camera looking down has something to read depth from.
	var ground := MeshInstance3D.new()
	var gm := BoxMesh.new()
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.2, 0.26, 0.34)
	gm.material = gmat
	ground.mesh = gm
	ground.scale = Vector3(120.0, 0.1, 400.0)
	ground.position = Vector3(0, -Tuning.cell_size * 2.5 - 0.2, -150.0)
	add_child(ground)
	reset()

func reset() -> void:
	for r in _rows:
		r.queue_free()
	_rows.clear()
	_prev_open.clear()
	for i in 9:
		_prev_open.append(true)  # first row may use any cell
	_last_row_z = -Tuning.first_row_distance + Tuning.spawn_spacing

## Move the world toward the plane by `dist` units and spawn/remove rows as needed.
func advance(dist: float) -> void:
	for r in _rows:
		r.position.z += dist
		_update_fade(r)
	_last_row_z += dist
	while _last_row_z > -Tuning.spawn_distance:
		_last_row_z -= Tuning.spawn_spacing
		_spawn_row(_last_row_z)
	while not _rows.is_empty() and _rows[0].position.z > 15.0:
		_rows.pop_front().queue_free()

## True if a box at plane position `p` (x,y) overlapping z = 0 touches any obstacle.
func hits(p: Vector2) -> bool:
	var half_obs := Tuning.cell_size * Tuning.obstacle_scale * 0.5
	var half_depth := Tuning.obstacle_depth * 0.5 + Tuning.plane_hit_half_z
	for r in _rows:
		if absf(r.position.z) > half_depth:
			continue
		for cell: Vector2 in r.get_meta("cells"):
			if absf(cell.x - p.x) < half_obs + Tuning.plane_hit_half.x \
					and absf(cell.y - p.y) < half_obs + Tuning.plane_hit_half.y:
				return true
	return false

## Fade a row toward fade_alpha as it nears the plane so it doesn't hide the rows behind it.
func _update_fade(row: Node3D) -> void:
	var t := clampf(1.0 - (-row.position.z) / Tuning.fade_start_distance, 0.0, 1.0)
	var mat: StandardMaterial3D = row.get_meta("mat")
	mat.albedo_color.a = lerpf(1.0, Tuning.fade_alpha, t)

func _spawn_row(z: float) -> void:
	var open := _generate_open_cells()
	_prev_open = open
	var row := Node3D.new()
	row.position.z = z
	var size := Tuning.cell_size * Tuning.obstacle_scale
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.3, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # always alpha, so no shader switch when fading
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	row.set_meta("mat", mat)
	var cells: Array[Vector2] = []
	for i in 9:
		if open[i]:
			continue
		var pos := Vector2(i % 3 - 1, i / 3 - 1) * Tuning.cell_size
		cells.append(pos)
		var mi := MeshInstance3D.new()
		mi.mesh = _obstacle_mesh
		mi.material_override = mat
		mi.scale = Vector3(size, size, Tuning.obstacle_depth)  # mesh is a unit cube
		mi.position = Vector3(pos.x, pos.y, 0)
		row.add_child(mi)
	row.set_meta("cells", cells)
	# Ground stripe: gives a sense of speed since the lane grid itself is invisible.
	var stripe := MeshInstance3D.new()
	stripe.mesh = _stripe_mesh
	stripe.scale = Vector3(40.0, 0.1, 0.8)
	stripe.position = Vector3(0, -Tuning.cell_size * 2.5, 0)
	row.add_child(stripe)
	add_child(row)
	_rows.append(row)

## Pick which cells are open: choose one guaranteed-open cell that is reachable from the
## previous row, then block a random number of the others.
func _generate_open_cells() -> Array[bool]:
	var reachable: Array[int] = []
	for i in 9:
		for j in 9:
			if _prev_open[j] and absi(i % 3 - j % 3) <= 1 and absi(i / 3 - j / 3) <= 1:
				reachable.append(i)
				break
	var guaranteed: int = reachable.pick_random()
	var blocked := randi_range(Tuning.blocked_cells_min, Tuning.blocked_cells_max)
	blocked = clampi(blocked, 0, 8)
	var cells: Array[int] = []
	for i in 9:
		if i != guaranteed:
			cells.append(i)
	cells.shuffle()
	var open: Array[bool] = []
	for i in 9:
		open.append(true)
	for k in blocked:
		open[cells[k]] = false
	return open
