class_name Hazards
extends Node3D
## The map hazards that are not tied to a row of cubes (gulls are, see Spawner):
##   WIND GUSTS (Mountains, Stormfront): a zone between two rows that pushes the plane sideways. It is
##   drawn faintly from far away and lights up when it is close, so it is telegraphed.
##   LIGHTNING (Stormfront): a column strip that is shown for a second, then strikes.
## Both are pooled: every node is created once at start-up and reused (nothing is allocated in a run).
## Fairness (see Tuning): gusts sit well clear of every row; lightning never strikes the main safe-path
## column of a row that is passing the plane, and never the only open column of one.

signal lightning_struck

const GUST_POOL := 3
const STRIPES := 5
const BOLT_POOL := 2
const BOLT_LENGTH := 46.0
const BOLT_CENTER_Z := -6.0
const HIT_MARGIN := 0.6          # the wing's reach beyond the column's own width, each side
const FADE := 0.25

class Gust extends Node3D:
	var base: MeshInstance3D
	var stripes: Array[MeshInstance3D] = []
	var mat: StandardMaterial3D
	var x0 := 0.0
	var x1 := 0.0
	var dir := 1.0
	var length := 4.0
	var phase := 0.0
	var in_use := false

class Bolt extends Node3D:
	var strip: MeshInstance3D
	var core: MeshInstance3D
	var strip_mat: StandardMaterial3D
	var core_mat: StandardMaterial3D
	var state := 0          # 0 idle, 1 warning, 2 striking, 3 fading
	var t := 0.0
	var col := 0
	var fizzle := false     # the strike was cancelled (fairness): it just fades

var spawner: Node3D                 # Spawner: rows, plane_z, run_time, scroll_speed
var gust_chance := 0.0
var lightning_interval := 0.0       # seconds between strikes at the start of a run (0 = no lightning)
var _gusts: Array[Gust] = []
var _all_gusts: Array[Gust] = []
var _free_gusts: Array[Gust] = []
var _bolts: Array[Bolt] = []
var _next_strike := 0.0
var _box := BoxMesh.new()           # unit box, scaled per use

func _ready() -> void:
	for i in GUST_POOL:
		var g := Gust.new()
		g.mat = _flat_material(Color(0.85, 0.95, 1.0, 0.1))
		g.base = MeshInstance3D.new()
		g.base.mesh = _box
		g.base.material_override = g.mat
		g.add_child(g.base)
		for k in STRIPES:
			var st := MeshInstance3D.new()
			st.mesh = _box
			st.material_override = g.mat
			g.add_child(st)
			g.stripes.append(st)
		g.visible = false
		add_child(g)
		_all_gusts.append(g)
		_free_gusts.append(g)
	for i in BOLT_POOL:
		var b := Bolt.new()
		b.strip_mat = _flat_material(Color(1.0, 0.9, 0.3, 0.2))
		b.core_mat = _flat_material(Color(1.0, 1.0, 1.0, 0.0))
		b.strip = MeshInstance3D.new()
		b.strip.mesh = _box
		b.strip.material_override = b.strip_mat
		b.core = MeshInstance3D.new()
		b.core.mesh = _box
		b.core.material_override = b.core_mat
		b.add_child(b.strip)
		b.add_child(b.core)
		b.visible = false
		add_child(b)
		_bolts.append(b)

func _flat_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 1
	return m

## The map's hazard settings (from Tuning.maps) and a clean slate.
func configure(gust_chance_: float, lightning_interval_: float) -> void:
	gust_chance = gust_chance_
	lightning_interval = lightning_interval_
	reset()

func reset() -> void:
	for g in _all_gusts:
		g.visible = false
		g.in_use = false
	_gusts.clear()
	_free_gusts.clear()
	for g in _all_gusts:
		_free_gusts.append(g)
	for b in _bolts:
		_idle(b)
	_next_strike = Tuning.lightning_start

func _idle(b: Bolt) -> void:
	b.state = 0
	b.visible = false

# ---------- wind gusts ----------

## Called when a row is spawned at world z: maybe put a gust in the gap between it and the row below.
func on_row_spawned(z: float) -> void:
	if gust_chance <= 0.0 or DebugFlags.off("hazards") or _free_gusts.is_empty():
		return
	if randf() >= gust_chance:
		return
	var zc := z + Tuning.spawn_spacing * 0.5
	if zc > -14.0:   # never pop in on screen
		return
	var g: Gust = _free_gusts.pop_back()
	var half := Tuning.ortho_size * 0.5
	var cx := randf_range(-half + Tuning.gust_width * 0.5, half - Tuning.gust_width * 0.5)
	g.x0 = cx - Tuning.gust_width * 0.5
	g.x1 = cx + Tuning.gust_width * 0.5
	g.dir = -1.0 if randf() < 0.5 else 1.0
	g.length = minf(Tuning.gust_length, Tuning.spawn_spacing - 2.0 * Tuning.gust_clear)
	g.phase = randf()
	g.position = Vector3(0.0, 0.0, zc)
	g.base.position = Vector3(cx, 0.03, 0.0)
	g.base.scale = Vector3(Tuning.gust_width, 0.02, g.length)
	for st in g.stripes:
		st.scale = Vector3(0.14, 0.02, g.length * 0.85)
		st.position.y = 0.05
	g.in_use = true
	g.visible = true
	_gusts.append(g)

func advance(dist: float) -> void:
	for i in range(_gusts.size() - 1, -1, -1):
		var g := _gusts[i]
		g.position.z += dist
		if g.position.z - g.length * 0.5 > Tuning.spawn_distance:
			g.visible = false
			g.in_use = false
			_gusts.remove_at(i)
			_free_gusts.append(g)

## How hard the wind pushes sideways (units/second, + = right) on a plane at (x, z).
func push_at(x: float, z: float) -> float:
	var total := 0.0
	for g in _gusts:
		if absf(z - g.position.z) <= g.length * 0.5 and x >= g.x0 and x <= g.x1:
			total += g.dir * Tuning.gust_push
	return total

func is_lit(g: Gust) -> bool:
	var plane_z: float = spawner.plane_z
	return plane_z - (g.position.z - g.length * 0.5) <= Tuning.gust_telegraph

func gusts_in_play() -> Array[Gust]:
	return _gusts

# ---------- lightning ----------

var _clock := 0.0

## Per-frame update, driven by Main during a run (delta in seconds).
func update(delta: float) -> void:
	_clock += delta   # (advances by the frame's own delta, like everything else: a slow frame is never caught up)
	var now := _clock
	for g in _gusts:   # faint while far, lit when close; the stripes slide the way the wind blows
		g.mat.albedo_color.a = 0.4 if is_lit(g) else 0.12
		var w := g.x1 - g.x0
		for k in STRIPES:
			var f := fposmod(g.phase + float(k) / STRIPES + now * 0.5 * g.dir, 1.0)
			g.stripes[k].position.x = g.x0 + f * w
	if lightning_interval > 0.0 and not DebugFlags.off("hazards"):
		var run_time: float = spawner.run_time
		if run_time >= Tuning.lightning_start:
			_next_strike -= delta
			if _next_strike <= 0.0:
				if _start_strike():
					_next_strike = maxf(lightning_interval - Tuning.lightning_ramp * run_time / 60.0, 2.0) * randf_range(0.8, 1.2)
				else:
					_next_strike = 0.4   # nothing allowed right now: look again soon
	for b in _bolts:
		_update_bolt(b, delta)

func _col_x(col: int) -> float:
	return Tuning.column_center(col)

func _strip_width() -> float:
	return Tuning.column_width() + 2.0 * HIT_MARGIN

func _start_strike() -> bool:
	var b: Bolt = null
	for cand in _bolts:
		if cand.state == 0:
			b = cand
			break
	if b == null:
		return false
	var col := _pick_column()
	if col < 0:
		return false
	_begin(b, col)
	return true

func _begin(b: Bolt, col: int) -> void:
	b.col = col
	b.state = 1
	b.t = 0.0
	b.fizzle = false
	b.position = Vector3(_col_x(col), 0.0, BOLT_CENTER_Z)
	b.strip.scale = Vector3(_strip_width(), 0.04, BOLT_LENGTH)
	b.strip.position = Vector3(0.0, 0.06, 0.0)
	b.core.scale = Vector3(0.5, 0.05, BOLT_LENGTH)
	b.core.position = Vector3(0.0, 0.08, 0.0)
	b.strip_mat.albedo_color = Color(1.0, 0.9, 0.3, 0.2)
	b.core_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	b.visible = true

## The rows that will pass the plane while a strike warns and hits.
func _rows_in_window(dur: float = -1.0) -> Array:
	var out := []
	var plane_z: float = spawner.plane_z
	var span := dur if dur > 0.0 else Tuning.lightning_warn + Tuning.lightning_strike + 0.2
	var reach: float = 3.0 + float(spawner.scroll_speed) * span
	for r in spawner._rows:
		if r.open.is_empty():
			continue
		var d: float = plane_z - r.position.z   # > 0: the row is above the plane
		if d >= -3.0 and d <= reach:
			out.append(r)
	return out

## Is a strike on `col` allowed right now? Never on the safe path of a passing row, and every passing
## row keeps an open column that is not struck.
func strike_allowed(col: int, dur: float = -1.0) -> bool:
	for r in _rows_in_window(dur):
		if r.safe_col == col:
			return false
		var other := false
		for c in r.open.size():
			if r.open[c] and c != col:
				other = true
		if not other:
			return false
	return true

## The column under x (clamped to the screen).
func col_of(x: float) -> int:
	return clampi(roundi(x / Tuning.column_width() + (Tuning.column_count - 1) * 0.5), 0, Tuning.column_count - 1)

## The allowed column nearest to `col` for a strike lasting `dur` seconds (-1 = none is allowed right now).
func nearest_allowed(col: int, dur: float = -1.0) -> int:
	for d in Tuning.column_count:
		for sgn in [-1, 1]:
			var c: int = col + sgn * d
			if c >= 0 and c < Tuning.column_count and strike_allowed(c, dur):
				return c
	return -1

## A boss's strike: begin a bolt on `col` if one is free and the column is allowed. Returns whether it began.
func force_strike(col: int) -> bool:
	if DebugFlags.off("hazards") or not strike_allowed(col):
		return false
	for b in _bolts:
		if b.state == 0:
			_begin(b, col)
			return true
	return false

func _pick_column() -> int:
	var n := Tuning.column_count
	var allowed: Array[int] = []
	for c in n:
		if strike_allowed(c):
			allowed.append(c)
	if allowed.is_empty():
		return -1
	var plane_x := 0.0
	if spawner.get("plane_x") != null:
		plane_x = spawner.plane_x
	var aimed := roundi(plane_x / Tuning.column_width() + (n - 1) * 0.5)
	if allowed.has(aimed) and randf() < Tuning.lightning_aim:
		return aimed
	return allowed.pick_random()

func _update_bolt(b: Bolt, delta: float) -> void:
	if b.state == 0:
		return
	b.t += delta
	match b.state:
		1:
			var pulse := 0.5 + 0.5 * sin(b.t * 14.0)
			b.strip_mat.albedo_color.a = 0.14 + 0.28 * pulse * (b.t / Tuning.lightning_warn) + 0.1 * (b.t / Tuning.lightning_warn)
			if b.t >= Tuning.lightning_warn:
				if strike_allowed(b.col):
					b.state = 2
					b.t = 0.0
					b.strip_mat.albedo_color = Color(1.0, 0.97, 0.7, 0.9)
					b.core_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
					lightning_struck.emit()
				else:
					b.fizzle = true   # a row is passing whose only way is this column: no strike
					b.state = 3
					b.t = 0.0
		2:
			if b.t >= Tuning.lightning_strike:
				b.state = 3
				b.t = 0.0
		3:
			var k := clampf(1.0 - b.t / FADE, 0.0, 1.0)
			b.strip_mat.albedo_color.a = (0.2 if b.fizzle else 0.9) * k
			b.core_mat.albedo_color.a = k
			if b.t >= FADE:
				_idle(b)

## Is the plane at x standing in a column that is being struck right now?
func hit(x: float) -> bool:
	for b in _bolts:
		if b.state == 2 and absf(x - _col_x(b.col)) < Tuning.column_width() * 0.5 + HIT_MARGIN:
			return true
	return false

func bolts_in_play() -> Array[Bolt]:
	return _bolts

# ---------- pre-warm ----------

## Draw every pooled gust and bolt for a moment (under the splash), so their materials are ready.
func prewarm_show() -> void:
	for i in _all_gusts.size():
		var g := _all_gusts[i]
		g.visible = true
		g.length = 4.0
		g.position = Vector3(0.0, 0.0, -9.0 + 5.0 * i)
		g.base.position = Vector3(-3.0 + 3.0 * i, 0.03, 0.0)
		g.base.scale = Vector3(5.0, 0.02, 4.0)
		g.mat.albedo_color.a = 0.4
		for k in STRIPES:
			g.stripes[k].scale = Vector3(0.14, 0.02, 3.4)
			g.stripes[k].position = Vector3(-5.0 + 2.0 * k + 3.0 * i, 0.05, 0.0)
	for i in _bolts.size():
		var b := _bolts[i]
		b.visible = true
		b.position = Vector3(-2.0 + 4.0 * i, 0.0, BOLT_CENTER_Z)
		b.strip.scale = Vector3(_strip_width(), 0.04, BOLT_LENGTH)
		b.strip.position = Vector3(0.0, 0.06, 0.0)
		b.core.scale = Vector3(0.5, 0.05, BOLT_LENGTH)
		b.core.position = Vector3(0.0, 0.08, 0.0)
		b.strip_mat.albedo_color = Color(1.0, 0.95, 0.5, 0.35 + 0.3 * i)
		b.core_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.8 * i)

func prewarm_hide() -> void:
	reset()
