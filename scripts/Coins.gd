class_name Coins
extends Node3D
## Coin trails: short lines of coins along the routes of a pattern (risky routes, between obstacles, through barn
## doorways, around windmill blades). Each coin rides a Spawner row (its z is the row's z plus an offset), is collected by
## touching it and pays Tuning.trail_coin_value into the run score. Fuel cans and hay stay the bigger prizes.
## One MultiMesh of POOL quads is built at start-up; spawning only fills a free slot, collecting or scrolling off frees it.

const POOL := 150
const SIZE := 0.8                     # the coin's diameter
const Y := 0.3                        # drawn just under the plane's layer

var dropped := 0                      # spawn() calls that found the pool empty (the tests expect 0)
var count := 0                        # coins alive
var _rows: Array = []                 # per slot: the carrier row (anything with .position.z / .visible), null = free
var _x := PackedFloat32Array()
var _dz := PackedFloat32Array()
var _free: Array[int] = []
var _alive: Array[int] = []           # the slots in use
var _mm := MultiMesh.new()
var _mi := MultiMeshInstance3D.new()
var _got := Vector3.ZERO              # where the latest coin was collected (the sound / pop uses it)
var last_pos := Vector3.ZERO

func _ready() -> void:
	_rows.resize(POOL)
	_x.resize(POOL)
	_dz.resize(POOL)
	for i in POOL:
		_free.append(POOL - 1 - i)
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2(SIZE, SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/coin.gdshader") as Shader
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = q
	_mm.instance_count = POOL
	_mm.visible_instance_count = 0
	_mi.multimesh = _mm
	_mi.material_override = mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.extra_cull_margin = 100.0
	add_child(_mi)

## One coin on `row`, `x` across and `dz` down the screen from the row (negative = further up). False if the pool is empty.
func spawn(row, x: float, dz: float) -> bool:
	if _free.is_empty():
		dropped += 1
		return false
	var i: int = _free.pop_back()
	_rows[i] = row
	_x[i] = x
	_dz[i] = dz
	_alive.append(i)
	count += 1
	return true

## A line of `n` coins from (x0, dz0) to (x1, dz1).
func spawn_line(row, x0: float, dz0: float, x1: float, dz1: float, n: int) -> int:
	var placed := 0
	for k in n:
		var t := float(k) / maxf(n - 1, 1)
		if spawn(row, lerpf(x0, x1, t), lerpf(dz0, dz1, t)):
			placed += 1
	return placed

func _free_slot(i: int) -> void:
	_rows[i] = null
	_free.append(i)
	count -= 1

## Every coin of a row that has gone (the row went back to the pool).
func release_row(row) -> void:
	var k := 0
	while k < _alive.size():
		var i := _alive[k]
		if _rows[i] == row:
			_free_slot(i)
			_alive.remove_at(k)
		else:
			k += 1

func release_all() -> void:
	for i in _alive:
		_rows[i] = null
		_free.append(i)
	_alive.clear()
	count = 0
	_mm.visible_instance_count = 0

## Every frame: put the coins where their rows are and drop the ones that scrolled off the bottom. `plane_z` = the plane's z.
func sync(plane_z: float) -> void:
	var k := 0
	var n := 0
	while k < _alive.size():
		var i := _alive[k]
		var row = _rows[i]
		var z: float = row.position.z + _dz[i]
		if not row.visible or z > plane_z + 14.0:
			_free_slot(i)
			_alive.remove_at(k)
			continue
		_mm.set_instance_transform(n, Transform3D(Basis.IDENTITY, Vector3(_x[i], Y, z)))
		n += 1
		k += 1
	_mm.visible_instance_count = n

## Collect every coin the plane's shapes touch (`caps` as Spawner.collect_cans). Returns how many; `last_pos` = the latest one.
func collect(p: Vector2, caps: PackedFloat32Array, radius: float) -> int:
	var got := 0
	var k := 0
	var window := 3.0   # coins further than this from the plane's z are skipped quickly (a long Tow Banner widens it)
	for o in range(0, caps.size(), 5):
		window = maxf(window, maxf(absf(caps[o + 1]), absf(caps[o + 3])) + caps[o + 4] + radius + 0.5)
	while k < _alive.size():
		var i := _alive[k]
		var cz: float = _rows[i].position.z + _dz[i]
		var hit := false
		if absf(cz - p.y) < window:
			var centre := Vector2(_x[i], cz)
			for o in range(0, caps.size(), 5):
				var a := Vector2(p.x + caps[o], p.y + caps[o + 1])
				var b := Vector2(p.x + caps[o + 2], p.y + caps[o + 3])
				if Collision.point_segment(centre, a, b) - caps[o + 4] < radius:
					hit = true
					break
		if hit:
			last_pos = Vector3(_x[i], Y, cz)
			_free_slot(i)
			_alive.remove_at(k)
			got += 1
		else:
			k += 1
	if got > 0:
		sync(p.y)   # (the collected ones disappear this frame)
	return got

## Magnet Field: coins within `radius` of p move `move` units toward it.
func pull(p: Vector2, radius: float, move: float) -> void:
	for i in _alive:
		var cz: float = _rows[i].position.z + _dz[i]
		if absf(cz - p.y) > radius or absf(_x[i] - p.x) > radius:
			continue
		var pos := Vector2(_x[i], cz)
		var d := pos.distance_to(p)
		if d >= radius or d < 0.001:
			continue
		var np := pos.move_toward(p, move)
		_x[i] = np.x
		_dz[i] += np.y - cz

## Where coin number `n` (0 .. count-1) is now, for the tests.
func position_of(n: int) -> Vector3:
	var i := _alive[n]
	return Vector3(_x[i], Y, _rows[i].position.z + _dz[i])

## Pre-warm: draw a full screen of coins.
func prewarm_show() -> void:
	for i in POOL:
		_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(-5.0 + 10.0 * float(i % 12) / 11.0, Y, -6.0 + float(i / 12) * 1.0)))
	_mm.visible_instance_count = POOL

func prewarm_hide() -> void:
	release_all()
