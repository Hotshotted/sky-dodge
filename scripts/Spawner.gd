extends Node3D
## Streams rows of obstacles toward the plane: the world scrolls toward +Z (screen-down)
## while the plane flies toward -Z (screen-up).
## Obstacles live on hidden columns across the screen width. Each row blocks a few columns
## and always leaves at least one open column that touches (same or adjacent column) an open
## column of the previous row, so there is always a path through.

const GROUND_Y := -2.0
const NEAR_RANGE := 4.0   # only rows within this many units (z) of the plane are collision-checked
const FAR_X := 3.2        # ...and only obstacles within this sideways distance (the wing reaches ~1.1 + a cube ~1)
const MAX_ROWS_PER_FRAME := 1   # Countryside: at most this many rows are built in one frame
const POOL_ROWS := 12     # rows created once at startup and reused forever (about 6 are alive at a time)
## Clouds: puffs lie in a thin slab ABOVE the obstacles and fuel cans (tops at 0.67 / 0.77) and BELOW
## the plane (its lowest point is 1.02), so plain depth testing hides what is under them and keeps
## the plane drawn on top and fully visible.
const GHOST_Y := 1.012              # Cloud Eye frames sit just above the cloud slab (below the plane at 1.025)
const CLOUD_Y := 0.78
const CLOUD_HEIGHT := 0.2           # puff top = 0.98
const CLOUD_POOL := 12              # cloud bundles created once at startup (about 6 are alive at a time)
const PUFFS_PER_CLOUD := 7          # most puffs one bundle holds
const PUFF_EDGE := 1.07             # the puff's lumpy outline reaches this far past its scale
const CLOUD_PATH_HALF := 1.0        # half the depth (z) of a row's path that the fairness check protects

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
	var can_dz := 0.0                     # how far the Can Magnet has pulled the can along z (relative to the row)
	var open: Array[bool] = []            # per column: open (no cube); the fairness check reads this
	var safe_col := -1                    # the main safe-path column through this row (lightning never strikes it)
	var obs_cols: Array[int] = []         # the column of each obstacle in use (same order as obs)
	var crate_kind: Array[int] = []       # per obstacle: 0 = a plain cube, 1 gold / 2 green / 3 purple crate
	var crate_glows: Array[MeshInstance3D] = []   # one glow plate per column (shown on crates)
	var gull_k: Array[int] = []           # which of the obstacles (index into xs / obs) are drifting gulls
	var gull_lo: Array[float] = []        # how far each may drift (x range) and how fast / which way
	var gull_hi: Array[float] = []
	var gull_v: Array[float] = []
	var gull_phase: Array[float] = []
	var nudge_k: Array[int] = []          # obstacles being shoved sideways by Prop Wash (index into xs / obs)
	var nudge_v: Array[float] = []        # ...and their sideways velocity (units/second)
	var nudge_d: Array[int] = []          # ...and how far down a Wingwalker chain each one is (0 = the first)
	var can_golden := false               # the can is a golden one (Golden Whiskers)
	var cloud_cov: Array[bool] = []       # per column: cloud will cover that column's centre line (for can placement)
	var xs: Array[float] = []             # x of each blocked column this time round
	var ghosts: Array[MeshInstance3D] = []        # one Cloud Eye outline frame per column (hidden unless needed)
	var obs_ghosts: Array[MeshInstance3D] = []    # the frames of the cubes in use (same order as obs)
	var obs: Array[MeshInstance3D] = []   # the cubes in use (same order as xs)
	var outlines: Array[ShaderMaterial] = []  # their outline materials (same order)
	var breather := false                 # spawned during a BREATHER
	var step_mark := false                # the BREATHER's speed step is applied when this row reaches the plane
	var entered := false                  # plane has been near this row
	var passed := false                   # near-miss check already done
	var min_clear := INF                  # closest approach seen
	var min_idx := -1                     # obstacle that gave it

	func clear_state() -> void:
		has_can = false
		open.clear()
		for i in cloud_cov.size():
			cloud_cov[i] = false
		can_dz = 0.0
		safe_col = -1
		obs_cols.clear()
		crate_kind.clear()
		gull_k.clear()
		gull_lo.clear()
		gull_hi.clear()
		gull_v.clear()
		gull_phase.clear()
		nudge_k.clear()
		nudge_v.clear()
		nudge_d.clear()
		can_golden = false
		xs.clear()
		obs.clear()
		obs_ghosts.clear()
		outlines.clear()
		step_mark = false
		breather = false
		entered = false
		passed = false
		min_clear = INF
		min_idx = -1

## A free-floating cloud bundle: a few puffs around a centre, created once and reused. It lives in world
## space (scrolls with the rows) and drifts sideways by `slope` units per unit of scroll.
class Cloud extends Node3D:
	var puffs: Array[MeshInstance3D] = []
	var mats: Array[StandardMaterial3D] = []   # one per puff: its alpha is the reveal fade
	var ox: Array[float] = []                  # puff offsets from the bundle centre (x, z) and radius
	var oz: Array[float] = []
	var rad: Array[float] = []
	var on: Array[bool] = []                   # puff in use (and not removed by the fairness rule)
	var slope := 0.0
	var in_use := false

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
var plane_z := 0.0                 # set by Main each frame: where the plane is (clouds fade as they near it)
var run_time := 0.0                # set by Main each frame: seconds into the run (clouds start late)
var scroll_speed := 0.0            # set by Main each frame: world speed (cloud frequency grows with it)
var _ghost_mesh := ArrayMesh.new()   # Cloud Eye: a flat frame the size of a cube
var _ghost_mat := StandardMaterial3D.new()
var _eye_shown := false            # Cloud Eye frames may be visible (so they get hidden again when it is unequipped)
var _cloud_mesh := ArrayMesh.new() # the shared low-poly puff
var _clouds: Array[Cloud] = []       # bundles in play
var _all_clouds: Array[Cloud] = []   # every bundle ever created (the pool)
var _free_clouds: Array[Cloud] = []
var puffs_removed := 0              # puffs removed by the fairness rule (the tests count them)
signal cloud_spawned(cloud)         # for the tests
var _last_row_z := 0.0
var _obstacle_mesh := BoxMesh.new()  # unit cube, scaled per obstacle
var _obstacle_mat := StandardMaterial3D.new()
var _outline_shader: Shader = preload("res://shaders/outline.gdshader")
var _stripe_mesh := BoxMesh.new()
var _last_thickness := -1.0
var _flashes: Array[Dictionary] = []   # {mat, end_ms}: outlines currently flashing white
var map := 0                       # the map being played (see Tuning.maps)
var plane_x := 0.0                 # set by Main each frame (lightning likes to aim at the plane)
var hazards := Hazards.new()       # wind gusts and lightning
var kit := Kit.new()               # the Countryside obstacle kit (barns, windmills, crows ...), pooled
var threats := Threats.new()       # the Countryside's hunting threats and bosses, pooled (see Threats.gd)
var kit_on := false                # this run uses the kit instead of cubes (Countryside only)
var obstacles_solid := true         # false: nothing collides (the balance sim isolates the threats with it)
var kit_enabled := true            # (tests switch the kit off to count cubes)
var _gull_mat := StandardMaterial3D.new()   # gulls are white (the cubes' material is swapped at spawn, both pre-built)
var coins := Coins.new()           # the pattern coin trails
var ground_mi: MeshInstance3D      # the ground plane (Main gives it the ground colour material)
var _ground_mat := StandardMaterial3D.new()
var _stripe_mat := StandardMaterial3D.new()
var _obs_color := Color(1.0, 0.3, 0.12)
var _cloud_color := Color.WHITE
var _cloud_tint := Color.WHITE
var _cloud_tint_mix := 0.0
var _blocked_add := 0
var _gull_share := 0.0
var _cloud_mult := 1.0
var crate_shower_rows := 0          # Crate Shower supply: how many of the next rows are crate-rich
var whisker_scale := 1.0           # Daredevil 3: Whisker closes count from twice as far
var near_miss_scale := 1.0         # Daredevil: close calls count from this much farther
signal bump(pos: Vector3, depth: int)   # a shoved obstacle hit another one (Prop Wash); depth = 0 for the first, 1+ down a chain
var chain_nudges := false           # Wingwalker: a bump shoves the obstacle it hit, too
var picked_golden: Array[bool] = [] # for each can in the last collect_cans() result: was it golden?
var _golden_can_mat := StandardMaterial3D.new()
var _crate_mat := StandardMaterial3D.new()                 # the wooden crate body
var _crate_glow_mats: Array[StandardMaterial3D] = []       # gold, green, purple glow plates
var _glow_mesh := BoxMesh.new()
var last_hit_crate := false        # the last hits() found a crate under the plane (it crashed on a crate)
const BROKEN_X := 1.0e6            # a broken crate's x: far off, so nothing ever touches it again

func _ready() -> void:
	# One shared material for every cube. Each cube gets its OWN outline material (same shader),
	# so a near miss can flash one outline by changing a uniform, with no material swap.
	_obstacle_mat.roughness = 1.0          # matte: flat, gradient-free shading
	_obstacle_mat.metallic_specular = 0.0
	_can_mat.roughness = 1.0
	_can_mat.metallic_specular = 0.0
	_build_puff_mesh()
	_build_ghost_mesh()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.albedo_color = Color(0.05, 0.05, 0.12, 0.62)
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mat.render_priority = 2   # after the cloud puffs
	_update_look()
	# Ground far below the obstacles; the stripes on each row give a sense of scrolling speed.
	var ground := MeshInstance3D.new()
	var gm := BoxMesh.new()
	_ground_mat.albedo_color = Color(0.2, 0.26, 0.34)
	gm.material = _ground_mat
	ground.mesh = gm
	ground.scale = Vector3(60.0, 0.1, 120.0)
	ground.position = Vector3(0, GROUND_Y - 0.1, 0)
	ground_mi = ground
	add_child(ground)
	_stripe_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.04)   # (a faint speed cue only: the countryside gives the scroll)
	_stripe_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_stripe_mesh.material = _stripe_mat
	_crate_mat.albedo_color = Tuning.crate_wood
	_crate_mat.roughness = 1.0
	_crate_mat.metallic_specular = 0.0
	for k in 3:
		var cmat := StandardMaterial3D.new()
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cmat.albedo_color = Tuning.crate_colors[k]
		_crate_glow_mats.append(cmat)
	_golden_can_mat.albedo_color = Color(1.0, 0.82, 0.15)
	_golden_can_mat.roughness = 1.0
	_golden_can_mat.metallic_specular = 0.0
	_gull_mat.albedo_color = Color(0.96, 0.97, 1.0)
	_gull_mat.roughness = 1.0
	_gull_mat.metallic_specular = 0.0
	hazards.spawner = self
	add_child(hazards)
	Patterns.warm()   # (every pattern's mirrored copy and can slots, built now)
	kit.ghost_mesh = _ghost_mesh
	kit.ghost_mat = _ghost_mat
	add_child(kit)
	threats.spawner = self
	add_child(threats)
	add_child(coins)
	for i in POOL_ROWS:  # everything is created now, so nothing is allocated while playing
		_make_row()
	for i in CLOUD_POOL:
		_make_cloud_node()
	reset()

## Time of day tints the clouds a little (they are lit by their own colour).
func set_sky_tint(tint: Color, mix: float) -> void:
	_cloud_tint = tint
	_cloud_tint_mix = mix

## Choose the map for the next run: palette, how many columns get blocked, the gull share, how many clouds, and
## the hazards (gusts, lightning). Call before reset().
func apply_map(index: int) -> void:
	map = clampi(index, 0, Tuning.maps.size() - 1)
	var m := Tuning.map_def(map)
	_obs_color = m["obstacle"]
	_cloud_color = m["cloud"]
	_blocked_add = int(m["blocked_add"])
	_gull_share = float(m["gull_share"])
	_cloud_mult = float(m["cloud_mult"])
	_ground_mat.albedo_color = m["ground"]
	hazards.configure(float(m["gust_chance"]), float(m["lightning_interval"]))
	kit_on = kit_enabled and map == 0 and not DebugFlags.off("kit")
	threats.enabled = kit_on and Tuning.threats_enabled
	_update_look()

## Put every row back in the pool and start the obstacle stream over (restart in place). The first
## row of the new run appears at world z = first_row_z (negative = above the plane).
func reset(first_row_z: float = -12.0) -> void:
	for r in _rows.duplicate():
		_release_row(r)
	_rows.clear()
	_flashes.clear()
	_prev_open.clear()
	_pending_open.clear()
	for c in _clouds.duplicate():
		_release_cloud(c)
	hazards.reset()
	threats.reset()
	kit.release_all()
	coins.release_all()
	_pat = {}
	_pat_next = {}
	_pat_row = 0
	pattern_name = ""
	wave_phase = 0
	wave_cycle = 0
	speed_steps = 0
	speed_steps_planned = 0
	base_speed_now = -1.0
	_step_marked_cycle = -1
	_wave_start = 0.0
	_wave_apply()
	snipes = 0
	_safe_col = Tuning.column_count / 2
	for i in Tuning.column_count:
		_prev_open.append(true)  # first row may use any column
	_last_row_z = first_row_z + Tuning.spawn_spacing

## Move the world toward the plane by `dist` units and spawn/remove rows as needed.
var rows_spawned := 0              # rows spawned by the latest advance() (the ?perf hitch log reports it)

func advance(dist: float) -> void:
	rows_spawned = 0
	_update_look()
	for r in _rows:
		r.position.z += dist
	_last_row_z += dist
	_advance_clouds(dist)
	hazards.advance(dist)
	kit.plane_z = plane_z   # (windmills set their start angle at spawn from these)
	kit.scroll_speed = scroll_speed
	if kit_on:
		for r in _rows:
			if r.step_mark and r.position.z >= plane_z - 8.0:
				r.step_mark = false
				speed_steps += 1
	while _last_row_z > -Tuning.spawn_distance and (rows_spawned < MAX_ROWS_PER_FRAME or not kit_on):   # (after a slow frame the rest follow on the next ones)
		_last_row_z -= Tuning.spawn_spacing
		rows_spawned += 1
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
	return obstacles_solid and probe(p, caps)

## Would a plane with these shapes at p touch an obstacle? (hits() is this, unless the sim switched obstacles off.)
func probe(p: Vector2, caps: PackedFloat32Array) -> bool:
	var half := _obstacle_half()
	for r in _rows:
		if absf(r.position.z - p.y) > NEAR_RANGE:
			continue
		for k in r.xs.size():
			var ox: float = r.xs[k]
			if absf(ox - p.x) > FAR_X:
				continue
			for o in range(0, caps.size(), 5):
				if _gap(p, caps, o, ox, r.position.z, half) < 0.0:
					last_hit_crate = k < r.crate_kind.size() and r.crate_kind[k] != 0
					return true
	if kit_on and kit.hits(p, caps):
		last_hit_crate = kit.last_hit_hay
		return true
	return false

## Call every frame with the plane position (x, z) and its shapes. Each row remembers the
## closest approach (smallest gap between a plane shape and an obstacle) while it is near the
## plane; once the row has fully passed it returns a near-miss event if that closest approach was
## under near_miss_distance: {"side": -1/+1 (which side the obstacle was), "node", "outline",
## "clearance" (the closest gap), "whisker" (true if within whisker_close_distance)}.
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
			if r.entered and r.min_idx >= 0 and r.min_clear < Tuning.near_miss_distance * near_miss_scale:
				var side := 1 if r.xs[r.min_idx] > p.x else -1
				events.append({"side": side, "node": r.obs[r.min_idx], "outline": r.outlines[r.min_idx],
						"clearance": r.min_clear, "whisker": r.min_clear <= Tuning.whisker_close_distance * whisker_scale, "row": r, "k": r.min_idx})
	if kit_on:
		kit.update_near_misses(p, caps, Tuning.near_miss_distance * near_miss_scale, behind, events, Tuning.whisker_close_distance * whisker_scale)
	return events

## Flash one obstacle's outline white for near_miss_flash_time seconds: just uniform changes on
## the outline material it already has (no new material, no swap).
func flash_obstacle(outline: ShaderMaterial) -> void:
	outline.set_shader_parameter("outline_color", Color.WHITE)
	outline.set_shader_parameter("thickness", Tuning.outline_thickness * 1.8)
	_flashes.append({"mat": outline, "end": Time.get_ticks_msec() + int(Tuning.near_miss_flash_time * 1000.0)})

var _bob := 0.0                    # visual clock for the bobbing cans (advances by the frame's delta, at most 0.05)
var _glow_clock := 0.0

func _process(_delta: float) -> void:
	_update_flashes()  # runs even when the world isn't scrolling (e.g. on the crash screen)
	_bob += minf(_delta, 0.05)
	var t := _bob
	for r in _rows:   # fuel cans bob gently so they read as pickups
		if r.has_can:
			r.can.position.y = 0.25 + 0.12 * sin(t * 4.0 + r.can_x)
	for c in _clouds:
		_update_cloud_alpha(c)
	_update_cloud_eye()

## Cloud Eye gear: obstacles with cloud over them get a faint dark frame drawn above the cloud.
func _update_cloud_eye() -> void:
	var eye := Tuning.gear_value("cloud_eye") > 0.0
	if not eye and not _eye_shown:
		return
	_eye_shown = eye
	for r in _rows:
		for k in r.obs.size():
			r.obs_ghosts[k].visible = eye and _cloud_over(r.xs[k], r.position.z)
	for e in kit.active:
		if e.ghost != null:
			e.ghost.visible = eye and e.solid and _cloud_over(e.px, e.pz)

## Is any visible puff right over the point (x, z) right now?
func _cloud_over(x: float, z: float) -> bool:
	for cl in _clouds:
		for k in cl.puffs.size():
			if not cl.on[k]:
				continue
			var dx: float = cl.position.x + cl.ox[k] - x
			var dz: float = cl.position.z + cl.oz[k] - z
			var r: float = cl.rad[k] * PUFF_EDGE + 0.3
			if dx * dx + dz * dz < r * r:
				return true
	return false

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
func prewarm_show(with_flash: bool, with_clouds: bool = true) -> void:
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
		for i in row.cubes.size():   # every other cube is drawn as a gull (or a crate), so those materials are warm too
			row.cubes[i].material_override = _gull_mat if (idx + i) % 3 == 0 else (_crate_mat if (idx + i) % 3 == 1 else _obstacle_mat)
		for i in row.crate_glows.size():
			var cgl := row.crate_glows[i]
			cgl.material_override = _crate_glow_mats[(idx + i) % 3]
			cgl.position = Vector3(Tuning.column_center(i), 0.55, 0.0)
			cgl.scale = Vector3(0.8, 0.04, 1.0)
			cgl.visible = (idx + i) % 3 == 1
		for g in row.ghosts:   # ...and every Cloud Eye frame
			g.visible = true
			g.position = Vector3(Tuning.column_center(row.ghosts.find(g)), GHOST_Y, 0.0)
			g.scale = Vector3(1.0, 1.0, 1.0)
		row.can.visible = true   # every pooled fuel can is drawn too
		row.can.material_override = _golden_can_mat if idx == 0 else _can_mat   # (one golden, so that material is warm)
		row.can.position = Vector3(Tuning.column_center(idx % Tuning.column_count), 0.4, 0.5)
		row.can.scale = Vector3.ONE * Tuning.fuel_can_size
	if with_clouds:   # every pooled cloud puff is drawn too (over the cubes, at a middling opacity)
		for idx in _all_clouds.size():
			var cl := _all_clouds[idx]
			cl.position = Vector3(Tuning.column_center(idx % Tuning.column_count), 0.0, -8.0 + 1.5 * idx)
			cl.visible = true
			for k in cl.puffs.size():
				cl.mats[k].albedo_color = Color(_cloud_color, 0.6)
				cl.puffs[k].visible = true
				cl.puffs[k].position = Vector3((k - 3) * 0.8, CLOUD_Y, 0.0)
				cl.puffs[k].scale = Vector3(1.5, 1.0, 1.5)
	hazards.prewarm_show()   # every pooled wind gust and lightning strip too
	kit.prewarm_show()       # ...and one of each kit thing
	coins.prewarm_show()     # ...and a screenful of coins
	threats.prewarm_show()   # ...and every hunting threat, its marker and the guns' tracers

## End of the pre-warm: hide the pooled rows again.
func prewarm_hide() -> void:
	hazards.prewarm_hide()
	threats.prewarm_hide()
	kit.release_all()
	coins.prewarm_hide()
	for row in _all_rows:
		for cube in row.cubes:
			cube.material_override = _obstacle_mat
		row.can.material_override = _can_mat
		_hide_row(row)
	for cl in _all_clouds:
		_hide_cloud(cl)

## Test helper: put a row at z with obstacles at the given x positions (no randomness).
func _rows_make_for_test(z: float, xs: Array) -> Row:
	var row := _acquire_row()
	row.position = Vector3(0.0, 0.0, z)
	row.visible = true
	for k in xs.size():
		row.xs.append(xs[k])
		row.obs.append(row.cubes[k])
		row.obs_ghosts.append(row.ghosts[k])
		row.obs_cols.append(k)
		row.crate_kind.append(0)
		row.outlines.append(row.cube_outlines[k])
	_rows.append(row)
	return row

func _update_look() -> void:
	_obstacle_mat.albedo_color = _obs_color
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
	for i in Tuning.column_count:
		var cg := MeshInstance3D.new()
		cg.mesh = _glow_mesh
		cg.material_override = _crate_glow_mats[0]
		cg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cg.visible = false
		row.add_child(cg)
		row.crate_glows.append(cg)
	for i in Tuning.column_count:
		var g := MeshInstance3D.new()
		g.mesh = _ghost_mesh
		g.material_override = _ghost_mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visible = false
		row.add_child(g)
		row.ghosts.append(g)
	row.can = MeshInstance3D.new()
	row.can.mesh = _can_mesh
	row.can.material_override = _can_mat
	row.can_outline = _new_outline()
	row.can.material_overlay = row.can_outline
	row.can.visible = false
	row.add_child(row.can)
	for i in Tuning.column_count:
		row.cloud_cov.append(false)
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
	kit.release_row(row)
	coins.release_row(row)
	_hide_row(row)
	row.clear_state()
	_rows.erase(row)
	if not _free_rows.has(row):
		_free_rows.append(row)

func _hide_row(row: Row) -> void:
	row.visible = false
	row.can.visible = false
	row.has_can = false
	for g in row.ghosts:
		g.visible = false
	for cg in row.crate_glows:
		cg.visible = false
	for i in row.cubes.size():
		row.cubes[i].visible = false
		row.cube_outlines[i].set_shader_parameter("outline_color", Color.BLACK)
		row.cube_outlines[i].set_shader_parameter("thickness", Tuning.outline_thickness)

func _spawn_row(z: float) -> void:
	# Rows are generated one ahead: `open` is this row, `next_open` the row after it.
	var open: Array[bool] = _pending_open if not _pending_open.is_empty() else _generate_open_columns(_prev_open)
	var next_open := _generate_open_columns(open)
	if kit_on:   # the kit decides what is in the way; the row only carries it (cans, clouds) and says which columns are free
		_spawn_kit_row(z)
		return
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
		mi.material_override = _obstacle_mat
		mi.visible = true
		var g := row.ghosts[i]
		g.position = Vector3(x, GHOST_Y, 0.0)
		g.scale = Vector3(width + 0.3, 1.0, Tuning.obstacle_depth + 0.3)
		row.xs.append(x)
		row.obs.append(mi)
		row.obs_ghosts.append(g)
		row.obs_cols.append(i)
		row.crate_kind.append(0)
		row.outlines.append(row.cube_outlines[i])
	row.stripe.scale = Vector3(Tuning.ortho_size * 2.0, 0.1, 0.4)
	for c in open.size():
		row.open.append(open[c])
	row.safe_col = _safe_col
	_make_crates(row, width)
	_make_gulls(row, width)
	_rows.append(row)
	hazards.on_row_spawned(z)
	if not DebugFlags.off("clouds") and run_time >= Tuning.cloud_start_time:
		_keep_row_fair(row)
	_spawn_clouds_for_row(z)
	for c in mini(open.size(), row.cloud_cov.size()):
		row.cloud_cov[c] = open[c] and _covered(z, Tuning.column_center(c))
	var can_col := _choose_can_column(open, next_open, _safe_col, row.cloud_cov)
	if can_col >= 0:
		_place_can(row, Tuning.column_center(can_col))

## Countryside row: the next row of the current pattern (a new pattern is chosen when one has been played out).
## The row only carries things (cans, clouds, its kit things) and says which columns are free.
var _pat: Dictionary = {}
var _pat_row := 0
var _pat_next: Dictionary = {}      # the pattern after this one, chosen a frame early (the choice is its own bit of work)
var _pool_buf: Array[Dictionary] = []   # scratch lists for _choose_pattern (reused: nothing is built per choice)
var _w_buf: Array[float] = []
var _pat_mirror := false
var _pat_last := ""
var _cycle_i := -1
var pattern_name := ""              # the pattern being played (the ?tune panel shows it)
var _carriers: Array = [null, null, null, null, null, null, null, null]   # the current pattern's rows (reused)
var _hay_fill: Array[bool] = []

func _spawn_kit_row(z: float) -> void:
	if _pat.is_empty() or _pat_row >= int(_pat["rows"]):
		_pat = _pat_next if not _pat_next.is_empty() else _choose_pattern()
		_pat_next = {}
		_pat_row = 0
		_pat_mirror = randf() < 0.5
		_pat_last = _pat["name"]
		pattern_name = _pat["name"]
		_hay_fill.clear()
		var hay_p := _hay_probability()
		for h in (_pat.get("hay", []) as Array):
			_hay_fill.append(randf() < hay_p)
	var row := _acquire_row()
	row.position = Vector3(0.0, 0.0, z)
	row.visible = true
	row.stripe.scale = Vector3(Tuning.ortho_size * 2.0, 0.1, 0.4)
	_carriers[_pat_row] = row
	row.breather = wave_phase == 3
	if wave_phase == 3 and _step_marked_cycle != wave_cycle:   # the first BREATHER row of a cycle carries the speed step
		_step_marked_cycle = wave_cycle
		row.step_mark = true
		speed_steps_planned += 1
	Patterns.realize(kit, _pat, _pat_mirror, _carriers, _hay_fill, _pat_row, null if DebugFlags.off("coins") else coins)
	var open: Array[bool] = []
	for c in Tuning.column_count:
		open.append(true)
	_kit_open_flags(row, open)
	if not DebugFlags.off("snipe"):
		_snipe_row(row, open)
	for c in open.size():
		row.open.append(open[c])
	_safe_col = _pick_safe_col(open, _safe_col)
	row.safe_col = _safe_col
	_prev_open = open
	_pending_open = open.duplicate()
	_rows.append(row)
	hazards.on_row_spawned(z)
	if not DebugFlags.off("clouds") and run_time >= Tuning.cloud_start_time:
		_keep_row_fair(row)
	_spawn_clouds_for_row(z)
	for c in mini(open.size(), row.cloud_cov.size()):
		row.cloud_cov[c] = open[c] and _covered(z, Tuning.column_center(c))
	# a can in one of the pattern's can slots (an extra chance under cloud)
	var slots := Patterns.can_slots(_pat, _pat_row, _pat_mirror)
	if not slots.is_empty():
		var x: float = slots.pick_random()
		var chance := _can_probability()
		if _covered(z, x):
			chance = maxf(chance, Tuning.fuel_can_under_cloud_chance)
		if randf() < chance:
			_place_can(row, x)
	_pat_row += 1

## The chance a new row gets a "snipe": a barn in the column the plane is flying in right now. A plane that stands still is hit
## within seconds, whatever it carries; a moving one just keeps moving (the row always keeps two or more open columns, and the
## barn is visible from the top of the screen for well over a second). It rises with the run, with no ceiling but snipe_max.
func snipe_chance() -> float:
	if not kit_on or run_time < Tuning.snipe_after:
		return 0.0
	return clampf(Tuning.snipe_start + Tuning.snipe_per_min * (run_time - Tuning.snipe_after) / 60.0, 0.0, Tuning.snipe_max)

var snipes := 0                    # snipe barns placed this run (the tests and the sim read it)

func _snipe_row(row: Row, open: Array[bool]) -> void:
	if randf() >= snipe_chance():
		return
	var n := Tuning.column_count
	var col := clampi(roundi(plane_x / Tuning.column_width() + (n - 1) * 0.5), 0, n - 1)
	if not open[col]:
		return   # (the pattern already blocks it)
	var free := 0
	for o in open:
		free += 1 if o else 0
	if free < 3:
		return
	var e = kit.spawn(Kit.BARN, row, Tuning.column_center(col), 0.0, 0.9)
	if e == null:
		return
	var again: Array[bool] = []
	for c in n:
		again.append(true)
	_kit_open_flags(row, again)
	var left := 0
	for o in again:
		left += 1 if o else 0
	if left < 2:   # it would leave no room: not this row
		kit.release(e)
		return
	snipes += 1
	for c in n:
		open[c] = again[c]

func _can_probability() -> float:
	return clampf(Tuning.pattern_can_chance * wave_can_mult, 0.0, 1.0)

func _hay_probability() -> float:
	if not Tuning.crates_enabled or DebugFlags.off("crates"):
		return 0.0
	if crate_shower_rows > 0:
		crate_shower_rows -= 1
		return 1.0
	if run_time < Tuning.crate_start_time:
		return 0.0
	return clampf(Tuning.crate_chance * Tuning.hay_slot_factor * wave_hay_mult, 0.0, 1.0)

var wave_can_mult := 1.0            # the intensity wave scales how many cans / hay bales the slots give
var wave_hay_mult := 1.0
const WAVE_NAMES := ["CALM", "BUILD", "PEAK", "BREATHER"]
var wave_phase := 0
var base_speed_now := -1.0           # set by Main: the Countryside speed before Tailwind (eased); differs from the target while a step is under way
var speed_steps := 0                # speed steps applied so far (a BREATHER reached the plane)
var speed_steps_planned := 0        # ...and spawned (patterns are chosen for the speed they will be flown at)
var _step_marked_cycle := -1
var wave_cycle := 0                 # finished CALM-BUILD-PEAK-BREATHER rounds this run
var _wave_start := 0.0              # run_time when the current phase began

## The Countryside's scroll speed after `steps` steps.
func stepped_speed(steps: int) -> float:
	var v := Tuning.base_speed
	for i in steps:
		v += Tuning.speed_step_table[i] if i < Tuning.speed_step_table.size() else Tuning.speed_step_late   # (no ceiling: the world keeps getting faster)
	return v

func wave_name() -> String:
	return "%s #%d" % [WAVE_NAMES[wave_phase], wave_cycle + 1]

## Phases change when a new pattern is about to be chosen (catching up if time jumped).
func _wave_update() -> void:
	if run_time - _wave_start >= Tuning.wave_seconds[wave_phase]:   # (one phase per pattern at most: none is ever skipped)
		_wave_start += Tuning.wave_seconds[wave_phase]
		_wave_step()

func _wave_step() -> void:
	wave_phase = (wave_phase + 1) % WAVE_NAMES.size()
	if wave_phase == 0:
		wave_cycle += 1
	_wave_apply()

func _wave_apply() -> void:
	wave_can_mult = Tuning.wave_can[wave_phase]
	wave_hay_mult = Tuning.wave_hay[wave_phase]

## ?tune button: jump to the next phase now (the pattern after the current one comes from it).
func cycle_wave() -> void:
	_wave_step()
	_wave_start = run_time
	_pat = {}
	_pat_next = {}

## The pattern difficulty range of the current phase (rises with every finished cycle, except in the BREATHER).
func wave_range() -> Vector2:
	var rise := Tuning.wave_rise * wave_cycle if wave_phase != 3 else 0.0
	return Vector2(minf(Tuning.wave_diff_lo[wave_phase] + rise, 5.0), minf(Tuning.wave_diff_hi[wave_phase] + rise, 5.0))

## Which columns this row's things block (for Lucky Whiskers cans, cloud fairness and the safe path).
func _kit_open_flags(row: Row, open: Array[bool]) -> void:
	for e in kit.active:
		if e.row != row:
			continue
		var lo := 0.0
		var hi := 0.0
		match e.kind:
			Kit.BARN, Kit.BALLOON, Kit.KITE, Kit.HAY:
				lo = e.px - e.reach.x - 0.8
				hi = e.px + e.reach.x + 0.8
				if e.kind == Kit.BARN and e.b > 0.5:   # the doorway stays open: block the two walls separately
					var door: float = Tuning.barn_door_width * 0.5
					for c in open.size():
						var cx := Tuning.column_center(c)
						if absf(cx - e.px) > door - 0.3 and absf(cx - e.px) < e.reach.x + 0.8:
							open[c] = false
					continue
			Kit.TRACTOR:
				continue   # it drives through; the bales it drops are things of their own
			Kit.WINDMILL:
				lo = e.px - 1.6
				hi = e.px + 1.6
			Kit.POWERLINE:
				lo = e.x0 - 0.3
				hi = e.a + 0.3
			_:
				continue
		for c in open.size():
			var cx := Tuning.column_center(c)
			if cx > lo and cx < hi:
				open[c] = false
	if not open.has(true):   # (never a fully blocked row on paper: the widest gap stays "open")
		open[open.size() / 2] = true

## The next pattern, from the current wave phase: its difficulty range, only patterns built for the current scroll speed,
## never the same one twice in a row. ?pattern=<name> repeats one pattern (the phases still run).
func _choose_pattern() -> Dictionary:
	_wave_update()
	if DebugFlags.pattern == "cycle":   # ?pattern=cycle: every pattern in turn (for profiling)
		_cycle_i += 1
		return Patterns.all()[_cycle_i % Patterns.all().size()]
	if DebugFlags.pattern != "":
		var forced := Patterns.find(DebugFlags.pattern)
		if not forced.is_empty():
			return forced
	var rng := wave_range()
	var opening := kit_on and run_time < Tuning.gentle_seconds   # the opening: easy but busy (see Tuning.gentle_seconds)
	if opening:
		rng = Vector2(1.0, lerpf(1.0, Tuning.gentle_max_diff, run_time / Tuning.gentle_seconds))   # (easy at first, a touch more by the end)
	var windmills_wait := kit_on and base_speed_now >= 0.0 and (speed_steps_planned != speed_steps or absf(base_speed_now - stepped_speed(speed_steps_planned)) > 0.05)
	var spd := maxf(scroll_speed, stepped_speed(speed_steps_planned)) if kit_on else scroll_speed
	var spd_hi := spd   # the first BREATHER pattern is chosen before its step is planned, but is flown at the faster speed
	if kit_on and wave_phase == 3 and _step_marked_cycle != wave_cycle:
		spd_hi = maxf(spd, stepped_speed(speed_steps_planned + 1))
	var slack := 0.5
	while slack < 6.0:
		var pool := _pool_buf
		var weights := _w_buf
		pool.clear()
		weights.clear()
		for p in Patterns.all():
			if p["name"] == _pat_last or float(p["diff"]) < rng.x - slack or float(p["diff"]) > rng.y + slack:
				continue
			if opening and Patterns.has_tag(p, "calm"):   # (no empty stretches in the opening)
				continue
			if windmills_wait and Patterns.has_tag(p, "windmill"):   # (their blade timing must not span a speed step)
				continue
			if spd < float(p["speed"][0]) - 0.01 or spd_hi > float(p["speed"][1]):
				continue
			pool.append(p)
			var w := 1.0 + 0.5 * (float(p["diff"]) - rng.x)
			if opening and Patterns.has_tag(p, "opening"):
				w *= Tuning.opening_weight
			if wave_phase == 3 and Patterns.has_tag(p, "calm"):
				w *= 12.0   # the breather is nearly empty
			weights.append(maxf(w, 0.1))
		if not pool.is_empty():
			var total := 0.0
			for w in weights:
				total += w
			var roll := randf() * total
			for i in pool.size():
				roll -= weights[i]
				if roll <= 0.0:
					return pool[i]
			return pool[-1]
		slack += 1.0
	var best: Dictionary = {}   # faster than anything built for: the pattern that holds up best at speed
	for p in Patterns.all():
		if best.is_empty() or float(p["speed"][1]) > float(best["speed"][1]):
			best = p
	return best

func _place_can(row: Row, x: float) -> void:
	row.has_can = true
	row.can_x = x
	row.can_dz = 0.0
	row.can_golden = false
	row.can.material_override = _can_mat
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

## Which column (if any) gets a fuel can in the row whose open columns are `open` (`covered` = which columns have cloud over them), given the next
## row's open columns and the safe-path column `safe`. A can goes in an open column, with chance
## fuel_can_chance. Then with probability fuel_risk_bias it is put in a RISKY column (not on the
## safe path, and next to an obstacle or in a column that closes next row; the riskier the more
## likely), otherwise in any open column. Returns -1 for no can.
func _choose_can_column(open: Array[bool], next_open: Array[bool], safe: int, covered: Array[bool] = []) -> int:
	# Under a cloud: an extra chance for a can in a covered open column (never on the safe path).
	if not covered.is_empty():
		var hidden: Array[int] = []
		for c in open.size():
			if open[c] and covered[c] and c != safe:
				hidden.append(c)
		if not hidden.is_empty() and randf() < Tuning.fuel_can_under_cloud_chance:
			return hidden.pick_random()
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
	picked_golden.clear()
	for r in _rows:
		var cz := r.position.z + r.can_dz
		if not r.has_can or absf(cz - p.y) > NEAR_RANGE:
			continue
		var centre := Vector2(r.can_x, cz)
		for o in range(0, caps.size(), 5):
			var a := Vector2(p.x + caps[o], p.y + caps[o + 1])
			var b := Vector2(p.x + caps[o + 2], p.y + caps[o + 3])
			if Collision.point_segment(centre, a, b) - caps[o + 4] < Tuning.fuel_pickup_radius:
				r.has_can = false
				r.can.visible = false
				_picked.append(Vector3(r.can_x, 0.4, cz))
				picked_golden.append(r.can_golden)
				break
	return _picked

## Can Magnet: every can within `radius` of the plane at p (x, z) moves toward it by up to `move` units.
func pull_cans(p: Vector2, radius: float, move: float) -> bool:
	var moved := false
	for r in _rows:
		if not r.has_can:
			continue
		var pos := Vector2(r.can_x, r.position.z + r.can_dz)
		var d := pos.distance_to(p)
		if d >= radius or d < 0.001:
			continue
		var np := pos.move_toward(p, move)
		r.can_x = np.x
		r.can_dz = np.y - r.position.z
		r.can.position.x = np.x
		r.can.position.z = r.can_dz
		moved = true
	return moved

## A hit the plane survived (Nine Lives): the rows whose obstacles it overlaps are done (no close-call credit).
func mark_hit_rows(p: Vector2, caps: PackedFloat32Array) -> void:
	var half := _obstacle_half()
	for r in _rows:
		if absf(r.position.z - p.y) > NEAR_RANGE:
			continue
		for ox in r.xs:
			if absf(ox - p.x) > FAR_X:
				continue
			for o in range(0, caps.size(), 5):
				if _gap(p, caps, o, ox, r.position.z, half) < 0.0:
					r.passed = true
					r.min_clear = INF
	if kit_on:
		kit.mark_hit(p, caps)

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

## ---- Crates: breakable blocks with something inside ----------------------------------------------------

## Turn some of this row's obstacles into crates (a crate still takes a blocked cell, so the open columns,
## and with them every fairness rule, are untouched).
func _make_crates(row: Row, width: float) -> void:
	if not Tuning.crates_enabled or DebugFlags.off("crates"):
		return
	var chance := 0.0
	if crate_shower_rows > 0:
		chance = Tuning.crate_shower_chance
		crate_shower_rows -= 1
	elif run_time >= Tuning.crate_start_time:
		chance = Tuning.crate_chance
	if chance <= 0.0:
		return
	for k in row.obs.size():
		if randf() >= chance:
			continue
		var roll := randf()
		var kind := 0
		var acc := 0.0
		for w in Tuning.crate_weights:
			acc += w
			if roll <= acc / 1.0:
				break
			kind += 1
		kind = mini(kind, 2)
		row.crate_kind[k] = kind + 1
		var mi: MeshInstance3D = row.obs[k]
		mi.material_override = _crate_mat
		mi.scale = Vector3(width, width * 0.8, Tuning.obstacle_depth)
		var glow := row.crate_glows[row.obs_cols[k]]
		glow.material_override = _crate_glow_mats[kind]
		glow.position = Vector3(row.xs[k], width * 0.4 + 0.02, 0.0)
		glow.scale = Vector3(width * 0.78, 0.04, Tuning.obstacle_depth * 0.78)
		glow.visible = true

## Break the crates the plane touches head-on. A touch breaks a crate when the plane is below its centre and within its
## width plus crate_front_forgive (the front face), and `speed_ok` (see ram_speed); with `battering` (the perk) any
## touch breaks it. `from_z` = where the plane was at the start of this frame's path. Anything else (a side touch) stays and crashes the plane. Returns what broke:
## [{"kind": 1 gold / 2 green / 3 purple, "pos": where}].
func break_crates(p: Vector2, caps: PackedFloat32Array, battering: bool, speed_ok: bool = true, from_z: float = -INF) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var half := _obstacle_half()
	for r in _rows:
		if absf(r.position.z - p.y) > NEAR_RANGE:
			continue
		for k in r.xs.size():
			if r.crate_kind[k] == 0 or absf(r.xs[k] - p.x) > FAR_X:
				continue
			var touching := false
			for o in range(0, caps.size(), 5):
				if _gap(p, caps, o, r.xs[k], r.position.z, half) < 0.0:
					touching = true
					break
			if not touching:
				continue
			# front = the plane came from below the crate (this step or the start of the frame's path: a fast flick can jump past its centre)
			var front: bool = maxf(p.y, from_z) > r.position.z and absf(p.x - r.xs[k]) <= half.x + Tuning.crate_front_forgive
			if battering or (front and speed_ok):
				out.append({"kind": r.crate_kind[k], "pos": Vector3(r.xs[k], 0.4, r.position.z)})
				r.crate_kind[k] = 0
				r.xs[k] = BROKEN_X
				r.obs[k].visible = false
				r.crate_glows[r.obs_cols[k]].visible = false
				r.obs_ghosts[k].visible = false
	if kit_on:
		out.append_array(kit.break_hay(p, caps, battering, speed_ok, from_z))
	return out

## ---- Gulls: obstacles that drift sideways ------------------------------------------------------------
const GULL_HEIGHT := 0.55      # a gull is a flatter block than a cube (same footprint, so the hit box matches)
const WING_CLEARANCE := 1.1    # the plane's half wingspan

## Turn some of this row's obstacles into gulls. A gull may drift sideways by gull_drift of a column, but never
## toward the row's safe-path column unless that column is far away, so the safe gap never shrinks.
func _make_gulls(row: Row, width: float) -> void:
	if _gull_share <= 0.0 or DebugFlags.off("hazards"):
		return
	var colw := Tuning.column_width()
	var amp := Tuning.gull_drift * colw
	var need := width * 0.5 + Tuning.outline_thickness + WING_CLEARANCE + 0.15
	var keep_x := Tuning.column_center(row.safe_col)
	for k in row.obs.size():
		if row.crate_kind[k] != 0 or randf() >= _gull_share:
			continue
		var x0: float = row.xs[k]
		var lo := x0 - amp
		var hi := x0 + amp
		if keep_x > x0 and (keep_x - x0) - amp < need:
			hi = x0
		elif keep_x < x0 and (x0 - keep_x) - amp < need:
			lo = x0
		var mi: MeshInstance3D = row.obs[k]
		mi.material_override = _gull_mat
		mi.scale = Vector3(width, width * GULL_HEIGHT, Tuning.obstacle_depth)
		row.gull_k.append(k)
		row.gull_lo.append(lo)
		row.gull_hi.append(hi)
		row.gull_v.append(Tuning.gull_speed * (1.0 if randf() < 0.5 else -1.0) if hi - lo > 0.01 else 0.0)
		row.gull_phase.append(randf() * TAU)

## Prop Wash: shove obstacle `k` of `row` sideways (dir = -1 / +1) at `speed` units/second. Gulls keep to their own drift.
## Prop Wash on the cube rows (the other maps): the cubes within the ring are nudged away from its centre.
func shove_rows(centre: Vector2, radius: float) -> void:
	if kit_on:
		return   # (the Countryside's obstacles are the kit's; the cube rows of the other maps are all "small": cubes)
	for r in _rows:
		if absf(r.position.z - centre.y) > radius:
			continue
		for k in r.xs.size():
			if absf(r.xs[k] - centre.x) < radius and r.xs[k] < 1.0e5:
				nudge_obstacle(r, k, 1 if r.xs[k] >= centre.x else -1, Tuning.wash_shove * 0.6)

func nudge_obstacle(row: Row, k: int, dir: int, speed: float, depth: int = 0) -> void:
	if k < 0 or k >= row.xs.size() or row.gull_k.has(k):
		return
	var i := row.nudge_k.find(k)
	if i < 0:
		row.nudge_k.append(k)
		row.nudge_v.append(dir * speed)
		row.nudge_d.append(depth)
	else:
		row.nudge_v[i] = dir * speed
		row.nudge_d[i] = depth

func _update_nudges(r: Row, delta: float, width: float) -> void:
	var half := Tuning.ortho_size * 0.5
	for i in range(r.nudge_k.size() - 1, -1, -1):
		var k: int = r.nudge_k[i]
		var v: float = r.nudge_v[i]
		var x: float = clampf(r.xs[k] + v * delta, -half, half)
		var hit_other := -1
		for j in r.xs.size():
			if j != k and absf(r.xs[j] - x) < width and (r.xs[j] - r.xs[k]) * v > 0.0:
				hit_other = j
				break
		r.xs[k] = x
		r.obs[k].position.x = x
		r.obs_ghosts[k].position.x = x
		if hit_other >= 0:
			var depth: int = r.nudge_d[i]
			r.nudge_k.remove_at(i)
			r.nudge_v.remove_at(i)
			r.nudge_d.remove_at(i)
			bump.emit(Vector3(x, 0.4, r.position.z), depth)
			if chain_nudges and depth + 1 < Tuning.chain_max:   # Wingwalker: the one that was hit is shoved on
				nudge_obstacle(r, hit_other, 1 if v > 0.0 else -1, maxf(absf(v), Tuning.prop_wash_push * 0.6), depth + 1)
			continue
		v *= exp(-Tuning.prop_wash_friction * delta)
		if absf(v) < 0.3 or absf(x) >= half:
			r.nudge_k.remove_at(i)
			r.nudge_v.remove_at(i)
			r.nudge_d.remove_at(i)
		else:
			r.nudge_v[i] = v

## Lucky Whiskers: put a fuel can in the nearest row ahead of the plane that has none, in the open column closest to x.
func drop_can_ahead(x: float, golden: bool = false) -> bool:
	var best: Row = null
	for r in _rows:
		if r.has_can or r.open.is_empty() or r.position.z > plane_z - 4.0 or r.position.z < plane_z - 24.0:
			continue
		if best == null or r.position.z > best.position.z:
			best = r
	if best == null:
		return false
	var col := -1
	for c in best.open.size():
		if best.open[c] and (col < 0 or absf(Tuning.column_center(c) - x) < absf(Tuning.column_center(col) - x)):
			col = c
	if col < 0:
		return false
	_place_can(best, Tuning.column_center(col))
	if golden:
		best.can_golden = true
		best.can.material_override = _golden_can_mat
	return true

## Per-frame hazard update (Main calls it during a run): gulls drift and flap, gusts and lightning run.
func update_hazards(delta: float) -> void:
	_glow_clock += delta
	var now := _glow_clock
	var pulse := 0.92 + 0.08 * sin(now * 5.0)   # the crates glow breathes
	for k in 3:
		_crate_glow_mats[k].albedo_color = Tuning.crate_colors[k] * pulse
	var width := Tuning.column_width() * Tuning.obstacle_scale
	for r in _rows:
		for gi in r.gull_k.size():
			var k: int = r.gull_k[gi]
			var x: float = r.xs[k] + r.gull_v[gi] * delta
			if x > r.gull_hi[gi]:
				x = r.gull_hi[gi]
				r.gull_v[gi] = -absf(r.gull_v[gi])
			elif x < r.gull_lo[gi]:
				x = r.gull_lo[gi]
				r.gull_v[gi] = absf(r.gull_v[gi])
			r.xs[k] = x
			var mi: MeshInstance3D = r.obs[k]
			mi.position.x = x
			mi.scale.y = width * GULL_HEIGHT * (0.85 + 0.2 * sin(now * 9.0 + r.gull_phase[gi]))
			r.obs_ghosts[k].position.x = x
		if not r.nudge_k.is_empty():
			_update_nudges(r, delta, width)
	hazards.update(delta)
	if kit_on:
		for k in 3:
			kit.glow_mats[k].albedo_color = Tuning.crate_colors[k] * pulse
		kit.plane_x = plane_x
		kit.plane_z = plane_z
		kit.scroll_speed = scroll_speed
		kit.update(delta)
		if _pat_next.is_empty() and not _pat.is_empty() and _pat_row >= int(_pat["rows"]) - 1:   # the last row of this pattern is out: choose the next one now
			_pat_next = _choose_pattern()
			_pat_last = _pat_next["name"]

## ---- Clouds: free-floating bundles --------------------------------------------------------------
## Bundles appear above the top of the screen at a random sideways position, in three size classes
## (wisps, medium clumps, large banks), and drift sideways a little as they scroll. None before
## cloud_start_time; after that they come more often as the run speeds up.

func _make_cloud_node() -> Cloud:
	var cl := Cloud.new()
	for k in PUFFS_PER_CLOUD:
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true   # the puff's baked facet tones
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		mat.roughness = 1.0
		mat.metallic_specular = 0.0
		var puff := MeshInstance3D.new()
		puff.mesh = _cloud_mesh
		puff.material_override = mat
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.visible = false
		cl.add_child(puff)
		cl.puffs.append(puff)
		cl.mats.append(mat)
		cl.ox.append(0.0)
		cl.oz.append(0.0)
		cl.rad.append(1.0)
		cl.on.append(false)
	cl.visible = false
	add_child(cl)
	_all_clouds.append(cl)
	_free_clouds.append(cl)
	return cl

func _hide_cloud(cl: Cloud) -> void:
	cl.visible = false
	cl.in_use = false
	for k in cl.puffs.size():
		cl.puffs[k].visible = false
		cl.on[k] = false

func _release_cloud(cl: Cloud) -> void:
	_hide_cloud(cl)
	_clouds.erase(cl)
	if not _free_clouds.has(cl):
		_free_clouds.append(cl)

## Scroll the bundles (they drift sideways as they go), recycle the ones past the bottom, and create new
## ones at the top. The creation rate is cloud_frequency bundles per row spacing, growing with speed.
func _advance_clouds(dist: float) -> void:
	for i in range(_clouds.size() - 1, -1, -1):
		var cl := _clouds[i]
		cl.position.z += dist
		cl.position.x += cl.slope * dist
		if cl.position.z - 7.0 > 12.0:
			_release_cloud(cl)

## Bundles are created along with the rows: cloud_frequency of them per row (more at speed), placed
## anywhere sideways and anywhere within a few units of the new row in depth, so they sit over
## rows and between them as they happen to fall.
func _spawn_clouds_for_row(z: float) -> void:
	if DebugFlags.off("clouds") or run_time < Tuning.cloud_start_time:
		return
	var speed_at_start := Tuning.base_speed + Tuning.speed_ramp * Tuning.cloud_start_time
	var rate := minf(Tuning.cloud_frequency * _cloud_mult * clampf(scroll_speed / maxf(speed_at_start, 0.1), 1.0, 3.0), 3.0)
	var n := int(rate) + int(randf() < rate - floorf(rate))
	for i in n:
		_spawn_cloud(z + randf_range(-6.0, 4.0))

func _spawn_cloud(z: float) -> void:
	if _free_clouds.is_empty():
		return
	var cl: Cloud = _free_clouds.pop_back()
	var roll := randf()
	var count: int
	var r_lo: float
	var r_hi: float
	var spread: float
	if roll < 0.4:        # a wisp
		count = randi_range(1, 2)
		r_lo = 0.7
		r_hi = 1.1
		spread = 0.7
	elif roll < 0.8:      # a medium clump
		count = randi_range(3, 4)
		r_lo = 1.0
		r_hi = 1.6
		spread = 1.6
	else:                 # a large bank
		count = randi_range(5, PUFFS_PER_CLOUD)
		r_lo = 1.4
		r_hi = 2.4
		spread = 2.8
	var half := Tuning.ortho_size * 0.5
	cl.position = Vector3(randf_range(-half - 0.5, half + 0.5), 0.0, z)
	cl.slope = randf_range(-Tuning.cloud_max_drift, Tuning.cloud_max_drift)
	for k in cl.puffs.size():
		var used := k < count
		cl.on[k] = used
		cl.puffs[k].visible = used
		if not used:
			continue
		var r := randf_range(r_lo, r_hi)
		cl.ox[k] = 0.0 if k == 0 else randf_range(-1.0, 1.0) * spread * 1.3   # wider than deep, like a bank
		cl.oz[k] = 0.0 if k == 0 else randf_range(-1.0, 1.0) * spread * 0.8
		cl.rad[k] = r
		cl.puffs[k].position = Vector3(cl.ox[k], CLOUD_Y + randf() * 0.03, cl.oz[k])
		cl.puffs[k].scale = Vector3(r, 1.0, r)
		cl.puffs[k].rotation = Vector3(0.0, randf() * TAU, 0.0)
	cl.visible = true
	cl.in_use = true
	_clouds.append(cl)
	# FAIRNESS: no row already in play may end up with every open column hidden. Where one would,
	# remove this bundle's puffs from the way of a column that was clear until now.
	for row in _rows:
		if row.open.is_empty() or _clear_column(row) >= 0:
			continue
		for c in row.open.size():
			if row.open[c] and not _covered(row.position.z, Tuning.column_center(c), null, cl):
				_covered(row.position.z, Tuning.column_center(c), cl, null, true)
				break
	var any := false
	for k in count:
		any = any or cl.on[k]
	if not any:
		_release_cloud(cl)
	else:
		_update_cloud_alpha(cl)
		cloud_spawned.emit(cl)

## Will any puff cover the centre line of a column in a row at world z `rz`? The line is the path
## the plane would fly through the row (x = the column's centre, z within the row's cube depth), and
## every puff drifts along its slope until the row reaches the plane, so the whole drift is checked.
## `only` / `skip` restrict which bundle is looked at; `hide_hits` removes the puffs that cover it.
func _covered(rz: float, cx: float, only: Cloud = null, skip: Cloud = null, hide_hits: bool = false) -> bool:
	var s_max := maxf(plane_z - rz, 0.0)   # scroll left before the row reaches the plane
	var hit := false
	for cl in _clouds:
		if cl == skip or (only != null and cl != only):
			continue
		for k in cl.puffs.size():
			if not cl.on[k]:
				continue
			var r: float = cl.rad[k] * PUFF_EDGE
			var dz := maxf(absf(cl.position.z + cl.oz[k] - rz) - CLOUD_PATH_HALF, 0.0)   # z offsets never change as everything scrolls together
			if dz >= r:
				continue
			var w := sqrt(r * r - dz * dz)
			var x0: float = cl.position.x + cl.ox[k]
			var x1 := x0 + cl.slope * s_max
			if minf(x0, x1) < cx + w and maxf(x0, x1) > cx - w:
				if not hide_hits:
					return true
				hit = true
				cl.on[k] = false
				cl.puffs[k].visible = false
				puffs_removed += 1
	return hit

## An open column of the row whose centre line no cloud covers, or -1 if every open column is covered.
func _clear_column(row: Row) -> int:
	for c in row.open.size():
		if row.open[c] and not _covered(row.position.z, Tuning.column_center(c)):
			return c
	return -1

## A new row must keep at least one open column visible: if the clouds already in play cover them
## all, the puffs covering the safe-path column are removed.
func _keep_row_fair(row: Row) -> void:
	if _clear_column(row) >= 0:
		return
	var c := _safe_col if (_safe_col < row.open.size() and row.open[_safe_col]) else row.open.find(true)
	_covered(row.position.z, Tuning.column_center(c), null, null, true)

## Late reveal: nearly opaque while far above the plane, fading to cloud_min_opacity as it reaches it.
func _update_cloud_alpha(cl: Cloud) -> void:
	for k in cl.puffs.size():
		if not cl.on[k]:
			continue
		var ahead := plane_z - (cl.position.z + cl.oz[k])   # > 0: the puff is above the plane (not reached yet)
		var t := clampf(1.0 - ahead / maxf(Tuning.cloud_reveal_distance, 0.1), 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)   # smoothstep: eases in and out
		cl.mats[k].albedo_color = Color(_cloud_color.lerp(_cloud_tint, _cloud_tint_mix * 0.6), lerpf(Tuning.cloud_max_opacity, Tuning.cloud_min_opacity, t))

## The shared puff: a flat, low-poly dome (about 45 triangles) with its facets tinted a touch
## differently, so it reads as a soft, puffy, flat-shaded shape. Built once.
func _build_puff_mesh() -> void:
	const N := 9
	var rings := [[0.55, 0.85, 1.0], [0.9, 0.45, 0.97], [1.0, 0.0, 0.92]]   # radius, height fraction, tone
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring_pts: Array = []
	for ri in rings.size():
		var pts: Array[Vector3] = []
		for i in N:
			var a := TAU * (i + 0.5 * (ri % 2)) / N
			var rad: float = rings[ri][0] * (0.93 + 0.14 * absf(sin(i * 2.7 + ri * 1.3)))   # a lumpy outline
			pts.append(Vector3(cos(a) * rad, rings[ri][1] * CLOUD_HEIGHT, sin(a) * rad))
		ring_pts.append(pts)
	var top := Vector3(0.0, CLOUD_HEIGHT, 0.0)
	for i in N:
		var j := (i + 1) % N
		var tint := 1.0 if i % 2 == 0 else 0.965
		_puff_tri(st, top, ring_pts[0][j], ring_pts[0][i], Color(1, 1, 1) * tint)
		for r in 2:
			var tone: float = rings[r + 1][2] * tint
			var c := Color(tone * 0.97, tone * 0.985, tone)   # a hint of blue in the shade
			_puff_tri(st, ring_pts[r][i], ring_pts[r][j], ring_pts[r + 1][i], c)
			_puff_tri(st, ring_pts[r][j], ring_pts[r + 1][j], ring_pts[r + 1][i], c)
	st.commit(_cloud_mesh)

## Cloud Eye frame: a flat square ring (outer 1.0 wide, inner 0.76), built once, scaled per obstacle.
func _build_ghost_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var o := 0.5
	var i := 0.38
	var quads := [[-o, -o, o, -i], [-o, i, o, o], [-o, -i, -i, i], [i, -i, o, i]]   # x0, z0, x1, z1 of the four bars
	for q in quads:
		var a := Vector3(q[0], 0.0, q[1])
		var b := Vector3(q[2], 0.0, q[1])
		var c := Vector3(q[2], 0.0, q[3])
		var d := Vector3(q[0], 0.0, q[3])
		for v in [a, b, c, a, c, d]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	st.commit(_ghost_mesh)

## One flat-shaded triangle (its own normal, one colour), wound so it faces up/out.
func _puff_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.y < 0.0:
		var tmp := b
		b = c
		c = tmp
		n = -n
	n = n.normalized()
	for v in [a, c, b]:   # Godot's front faces wind clockwise
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(v)

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
	var blocked := clampi(randi_range(Tuning.blocked_columns_min, Tuning.blocked_columns_max) + _blocked_add, 0, n - 1)
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
