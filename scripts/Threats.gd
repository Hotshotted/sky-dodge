class_name Threats
extends Node3D
## The Countryside's ACTIVE enemies: they hunt the plane, and the gun perks (Flak Cannon, Wing Pods, Tail Gun) are the answer.
##   HAWK     a shadow grows where the plane is and the hawk screeches; the aim locks, then it dives on that spot
##   GEESE    a V-formation sweeps across the screen, drifting toward the plane; an arrow marks the lane first
##   CROWS    a flock closes in from BEHIND, following the plane's x; weave (or shoot them) to break it up
##   DRONE    hovers at the top tracking the plane, winds up (lane glows red, whine), then darts down the locked lane
##   BOSSES   Flash the Falcon (flies alongside dropping bombs), the Thunderhead (a storm cell calling lightning),
##            the Goose General (a wall of geese with a gap) and the opening mini-boss, a rival crop duster
## Everything warns before it can hurt (see Tuning, "Hunting threats"): a threat is never armed until its telegraph has played,
## the aim of a hawk / bomb is a local zone (the plane can always step out of it), and the drone's lane and the Thunderhead's
## bolts use the lightning fairness rule (never the safe path of a passing row, never the only open column).
## Every node and material is created once in _ready (nothing is built during a run); a threat is only shown / hidden.
## Positions are SCREEN-space world coordinates (x sideways, z up the screen is negative), not scrolled with the ground.

signal telegraph(kind: int)                       # a threat began its warning (sound + first-time hint)
signal killed(kind: int, pos: Vector3, by_gun: bool)
signal shot(gun: String, cost: float)             # a gun fired (the coins are taken by Main)
signal boss_warning(boss_name: String)            # the banner time: the fight starts boss_warn_time later
signal boss_started(boss_name: String)
signal boss_ended(boss_name: String, defeated: bool, mini: bool)
signal event(text: String)                        # something new happened (the timeline)
signal blast(pos: Vector3, big: bool)             # a bomb landed / a gun burst (sound + shake)

enum { HAWK, GOOSE, CROW, DRONE, BOMB, FALCON, DUSTER, STORM, GENERAL, GGOOSE }
const NAMES := ["hawk", "goose", "crow", "drone", "bomb", "falcon", "duster", "storm", "general", "general goose"]
const CAUSES := ["Dived on by a hawk", "Clipped by a goose squadron", "Caught by the crow flock", "Struck by a drone", "Caught in a bomb blast",
		"Hit Flash the Falcon", "Hit the rival duster", "Struck by the Thunderhead", "Rammed the Goose General", "Smashed by the Goose General's flock"]
const BOSS_NAMES := ["Flash the Falcon", "The Thunderhead", "The Goose General"]
const BOSS_COLORS := [Color(0.35, 0.65, 1.0), Color(0.75, 0.6, 1.0), Color(1.0, 0.8, 0.3)]
const MINI_NAME := "Rival Crop Duster"
const HAWK_POOL := 2
const GOOSE_POOL := 14
const CROW_POOL := 6
const DRONE_POOL := 2
const BOMB_POOL := 6
const BLAST_POOL := 6
const TRACER_POOL := 3
const GROUPS := 4                    # two goose squads, the crow flock, the General's formation
const FLY_Y := 1.0
const MARK_Y := 0.07
const HAWK_START := 4.5              # a diving hawk starts this far above its target
const V_BACK := [0.0, 1.0, 1.0, 2.0, 2.0]
const V_SIDE := [0.0, 0.9, -0.9, 1.8, -1.8]
const CROW_OFF := [-1.3, -0.65, 0.0, 0.65, 1.3, 0.0]

class Th extends Node3D:
	var kind := 0
	var active := false
	var state := 0
	var t := 0.0
	var hp := 1.0
	var x := 0.0
	var z := 0.0
	var prev_z := 0.0
	var lx := 0.0                    # the locked target
	var lz := 0.0
	var dir := 1.0
	var phase := 0.0
	var armed := false               # can hurt the plane right now
	var shown := false               # on screen and shootable
	var radius := Vector2(1.0, 1.0)  # half size (x, z) of what it touches around its centre (the plane's reach included)
	var body: Node3D
	var wing_l: Node3D
	var wing_r: Node3D
	var marker: MeshInstance3D
	var marker_mat: StandardMaterial3D
	var eye_mat: StandardMaterial3D
	var group = null
	var back := 0.0
	var side := 0.0
	var dying := 0.0                 # > 0: the death spin / fade is playing

class Grp:
	var kind := 0
	var active := false
	var state := 0
	var t := 0.0
	var x := 0.0
	var z := 0.0
	var dir := 1.0
	var members: Array[Th] = []
	var arrow: MeshInstance3D
	var arrow_mat: StandardMaterial3D
	var gap := 0.0
	var wave := 0

var spawner: Node3D                      # Spawner: rows (for the lane rule), hazards, plane_z, scroll_speed
var enabled := true
var plane_x := 0.0
var plane_z := 0.0
var half_h := 13.0                       # the screen spans z = -half_h .. +half_h (Main sets it)
var z_min := 0.0                         # the plane's range
var z_max := 0.0
var elapsed := 0.0
var meters := 0.0
var wave_phase := 0
var kills := 0                           # threats shot down this run
var kills_by_kind := {}
var shots := 0
var hits_by_kind := {}                   # kind -> times the plane was hit
var last_hit_kind := -1
var timeline: Array = []                 # [run seconds, text]: what happened and when
var gun_levels := {}                     # gun id -> level (Main sets from the perks)
var launched := {}                       # kind name -> launches this run
var bosses_done := 0
var boss_active := false
var boss_name := ""
var boss_t := 0.0
var boss_hp := 0.0
var boss_hp_max := 1.0
var boss_mini := false
var boss_kind := -1
var intro_shown := {}                    # kinds whose first-time hint was shown this run

var _hawks: Array[Th] = []
var _geese: Array[Th] = []
var _crows: Array[Th] = []
var _drones: Array[Th] = []
var _bombs: Array[Th] = []
var _blasts: Array[Th] = []
var _tracers: Array[MeshInstance3D] = []
var _tracer_t := PackedFloat32Array()
var _groups: Array[Grp] = []
var _falcon: Th
var _duster: Th
var _storm: Th
var _general: Th
var _all: Array[Th] = []
var _mats := {}
var _meshes := {}
var _outline: ShaderMaterial
var _script_i := 0
var _script_wait := 0.0
var _budget := 0.0
var _since_launch := 99.0
var _next_boss_m := 0.0
var _boss_rot := 0
var _boss_gap_t := 0.0
var _boss_stage := 0                     # 0 none, 1 warning, 2 fight, 3 leaving
var _boss_leave_t := 0.0
var _boss_defeated := false
var _boss_drop_t := 0.0
var _boss_strike_t := 0.0
var _general_pass_t := 0.0
var _gun_cd := {"flak": 0.0, "pods": 0.0, "tail": 0.0}
var _clock := 0.0
var _hawk_next := 0
var _last_kind := -1
var _script: Array = []
var _prewarm := false

func _ready() -> void:
	_outline = ShaderMaterial.new()
	_outline.shader = preload("res://shaders/outline_part.gdshader")
	_outline.set_shader_parameter("thickness", 0.06)
	for i in HAWK_POOL:
		_hawks.append(_track(_build_hawk()))
	for i in GOOSE_POOL:
		_geese.append(_track(_build_goose()))
	for i in CROW_POOL:
		_crows.append(_track(_build_crow()))
	for i in DRONE_POOL:
		_drones.append(_track(_build_drone()))
	for i in BOMB_POOL:
		_bombs.append(_track(_build_bomb()))
	for i in BLAST_POOL:
		_blasts.append(_track(_build_blast()))
	_falcon = _track(_build_falcon())
	_duster = _track(_build_duster())
	_storm = _track(_build_storm())
	_general = _track(_build_general())
	for i in GROUPS:
		var g := Grp.new()
		g.arrow_mat = _flat(Color(1.0, 0.3, 0.1, 0.0))
		g.arrow = MeshInstance3D.new()
		g.arrow.mesh = _arrow_mesh()
		g.arrow.material_override = g.arrow_mat
		g.arrow.visible = false
		add_child(g.arrow)
		_groups.append(g)
	for i in TRACER_POOL:
		var mi := MeshInstance3D.new()
		mi.mesh = _box(0.1, 0.05, 1.0)
		mi.material_override = _flat(Color(1.0, 0.85, 0.35, 0.9))
		mi.visible = false
		add_child(mi)
		_tracers.append(mi)
		_tracer_t.append(0.0)
	hide_all()

func _track(t: Th) -> Th:
	_all.append(t)
	add_child(t)
	return t

# ---------- materials and meshes (all built in _ready) ----------

func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 1.0
		m.metallic_specular = 0.0
		_mats[key] = m
	return _mats[key]

func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 2
	return m

func _box(w: float, h: float, d: float) -> BoxMesh:
	var key := "b%.3f,%.3f,%.3f" % [w, h, d]
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = Vector3(w, h, d)
		_meshes[key] = m
	return _meshes[key]

func _disc_mesh() -> CylinderMesh:
	if not _meshes.has("disc"):
		var m := CylinderMesh.new()
		m.top_radius = 1.0
		m.bottom_radius = 1.0
		m.height = 0.02
		m.radial_segments = 20
		m.rings = 1
		_meshes["disc"] = m
	return _meshes["disc"]

func _arrow_mesh() -> ArrayMesh:
	if not _meshes.has("arrow"):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# a chevron pointing toward -z (the caller turns it)
		var pts := [Vector3(0, 0, -1.0), Vector3(1.3, 0, 0.5), Vector3(0, 0, 0.0), Vector3(0, 0, -1.0), Vector3(0, 0, 0.0), Vector3(-1.3, 0, 0.5)]
		for p in pts:
			st.add_vertex(p)
		var m := ArrayMesh.new()
		st.generate_normals()
		st.commit(m)
		_meshes["arrow"] = m
	return _meshes["arrow"]

func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, outlined: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	if outlined:
		mi.material_overlay = _outline
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	parent.add_child(mi)
	return mi

func _new_th(kind: int) -> Th:
	var t := Th.new()
	t.kind = kind
	t.body = Node3D.new()
	t.add_child(t.body)
	t.visible = false
	return t

func _add_marker(t: Th, color: Color) -> void:
	t.marker_mat = _flat(color)
	t.marker = MeshInstance3D.new()
	t.marker.mesh = _disc_mesh()
	t.marker.material_override = t.marker_mat
	t.marker.top_level = true            # placed in world coordinates, not turned or lifted with the body
	t.marker.visible = false
	t.add_child(t.marker)

func _wings(t: Th, span: float, chord: float, color: Color, y: float = 0.0, z: float = 0.0) -> void:
	t.wing_l = Node3D.new()
	t.wing_r = Node3D.new()
	t.wing_l.position = Vector3(-0.12, y, z)
	t.wing_r.position = Vector3(0.12, y, z)
	t.body.add_child(t.wing_l)
	t.body.add_child(t.wing_r)
	_part(t.wing_l, _box(span, 0.05, chord), color, Vector3(-span * 0.5, 0, 0))
	_part(t.wing_r, _box(span, 0.05, chord), color, Vector3(span * 0.5, 0, 0))

func _build_hawk() -> Th:
	var t := _new_th(HAWK)
	_part(t.body, _box(0.5, 0.22, 1.0), Color(0.45, 0.3, 0.18), Vector3(0, 0, 0))
	_part(t.body, _box(0.3, 0.18, 0.3), Color(0.9, 0.85, 0.7), Vector3(0, 0.04, -0.6))
	_part(t.body, _box(0.12, 0.1, 0.18), Color(0.95, 0.7, 0.15), Vector3(0, 0, -0.78), false)
	_part(t.body, _box(0.5, 0.05, 0.4), Color(0.35, 0.22, 0.12), Vector3(0, 0, 0.7))
	_wings(t, 1.45, 0.75, Color(0.38, 0.25, 0.14))
	_add_marker(t, Color(0.0, 0.0, 0.0, 0.0))
	t.radius = Vector2(Tuning.hawk_radius.x, Tuning.hawk_radius.y)
	return t

func _build_goose() -> Th:
	var t := _new_th(GOOSE)
	_part(t.body, _box(0.4, 0.2, 0.75), Color(0.93, 0.93, 0.95), Vector3(0, 0, 0))
	_part(t.body, _box(0.16, 0.16, 0.4), Color(0.2, 0.2, 0.24), Vector3(0, 0.02, -0.5))
	_part(t.body, _box(0.12, 0.08, 0.16), Color(0.95, 0.6, 0.15), Vector3(0, 0.02, -0.76), false)
	_wings(t, 1.0, 0.5, Color(0.8, 0.82, 0.88))
	t.radius = Vector2(Tuning.geese_radius.x, Tuning.geese_radius.y)
	return t

func _build_crow() -> Th:
	var t := _new_th(CROW)
	_part(t.body, _box(0.34, 0.16, 0.55), Color(0.14, 0.14, 0.18), Vector3(0, 0, 0))
	_part(t.body, _box(0.12, 0.1, 0.16), Color(0.95, 0.6, 0.15), Vector3(0, 0, -0.34), false)
	_wings(t, 0.6, 0.4, Color(0.22, 0.22, 0.28))
	t.radius = Vector2(Tuning.crow_radius.x, Tuning.crow_radius.y)
	return t

func _build_drone() -> Th:
	var t := _new_th(DRONE)
	_part(t.body, _box(0.8, 0.28, 0.8), Color(0.35, 0.38, 0.45), Vector3.ZERO)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_part(t.body, _box(0.12, 0.06, 0.12), Color(0.2, 0.22, 0.26), Vector3(sx * 0.55, 0.0, sz * 0.55), false)
			var rot := _part(t.body, _box(0.9, 0.02, 0.12), Color(0.65, 0.68, 0.75), Vector3(sx * 0.55, 0.2, sz * 0.55), false)
			rot.rotation.y = 0.5 * (sx * sz)
	t.eye_mat = _mat(Color(1.0, 0.15, 0.1)).duplicate()
	t.eye_mat.emission_enabled = true
	t.eye_mat.emission = Color(1.0, 0.1, 0.05)
	t.eye_mat.emission_energy_multiplier = 0.2
	var eye := MeshInstance3D.new()
	eye.mesh = _box(0.28, 0.12, 0.28)
	eye.material_override = t.eye_mat
	eye.position = Vector3(0, 0.2, 0)
	t.body.add_child(eye)
	_add_marker(t, Color(1.0, 0.2, 0.1, 0.0))
	t.marker.mesh = _box(2.0, 0.02, 2.0)   # the lane: a strip, scaled to half its width and length
	t.radius = Vector2(Tuning.drone_radius.x, Tuning.drone_radius.y)
	return t

func _build_bomb() -> Th:
	var t := _new_th(BOMB)
	_part(t.body, _box(0.5, 0.5, 0.5), Color(0.55, 0.4, 0.22), Vector3.ZERO)
	_part(t.body, _box(0.52, 0.12, 0.52), Color(0.85, 0.2, 0.15), Vector3(0, 0.1, 0), false)
	_add_marker(t, Color(1.0, 0.25, 0.1, 0.0))
	t.radius = Vector2(Tuning.bomb_radius + 0.8, Tuning.bomb_radius + 0.8)
	return t

func _build_blast() -> Th:
	var t := _new_th(BOMB)
	_add_marker(t, Color(1.0, 0.7, 0.2, 0.0))
	return t

func _build_falcon() -> Th:
	var t := _new_th(FALCON)
	_part(t.body, _box(0.7, 0.3, 1.7), Color(0.2, 0.45, 0.9), Vector3.ZERO)
	_part(t.body, _box(0.46, 0.22, 0.46), Color(0.95, 0.95, 1.0), Vector3(0, 0.05, -0.85))
	_part(t.body, _box(0.2, 0.12, 0.28), Color(0.95, 0.7, 0.15), Vector3(0, 0.02, -1.15), false)
	_part(t.body, _box(1.0, 0.06, 0.55), Color(0.85, 0.15, 0.2), Vector3(0, 0.05, 0.95))
	_part(t.body, _box(0.5, 0.1, 0.12), Color(0.9, 0.15, 0.2), Vector3(0, 0.2, -0.55), false)   # his scarf
	_wings(t, 2.1, 0.95, Color(0.16, 0.36, 0.78), 0.0, -0.1)
	t.radius = Vector2(1.9, 1.3)
	return t

func _build_duster() -> Th:
	var t := _new_th(DUSTER)
	_part(t.body, _box(0.55, 0.3, 1.8), Color(0.95, 0.8, 0.15), Vector3.ZERO)
	_part(t.body, _box(0.6, 0.2, 0.5), Color(0.2, 0.2, 0.25), Vector3(0, 0.1, -0.5), false)
	_part(t.body, _box(3.2, 0.06, 0.75), Color(0.9, 0.3, 0.2), Vector3(0, 0.05, -0.1))
	_part(t.body, _box(3.0, 0.06, 0.6), Color(0.95, 0.85, 0.3), Vector3(0, 0.14, 0.05))
	_part(t.body, _box(1.2, 0.05, 0.4), Color(0.9, 0.3, 0.2), Vector3(0, 0.05, 0.85))
	t.radius = Vector2(2.2, 1.2)
	return t

func _build_storm() -> Th:
	var t := _new_th(STORM)
	var dark := Color(0.28, 0.3, 0.38)
	_part(t.body, _box(3.6, 0.7, 2.2), dark, Vector3.ZERO)
	_part(t.body, _box(2.4, 0.9, 2.8), Color(0.22, 0.24, 0.32), Vector3(-1.5, 0.1, 0.4))
	_part(t.body, _box(2.4, 0.9, 2.6), Color(0.22, 0.24, 0.32), Vector3(1.6, 0.1, -0.3))
	_part(t.body, _box(2.0, 0.8, 1.8), Color(0.35, 0.37, 0.46), Vector3(0.1, 0.35, -0.2))
	t.eye_mat = _mat(Color(1.0, 0.95, 0.4)).duplicate()
	t.eye_mat.emission_enabled = true
	t.eye_mat.emission = Color(1.0, 0.9, 0.3)
	t.eye_mat.emission_energy_multiplier = 0.1
	var flash := MeshInstance3D.new()
	flash.mesh = _box(1.0, 0.3, 0.7)
	flash.material_override = t.eye_mat
	flash.position = Vector3(0, 0.75, 0)
	t.body.add_child(flash)
	t.radius = Vector2(3.0, 1.8)
	return t

func _build_general() -> Th:
	var t := _new_th(GENERAL)
	_part(t.body, _box(1.0, 0.45, 1.7), Color(0.93, 0.93, 0.95), Vector3.ZERO)
	_part(t.body, _box(0.36, 0.34, 0.8), Color(0.18, 0.18, 0.22), Vector3(0, 0.04, -1.1))
	_part(t.body, _box(0.3, 0.14, 0.32), Color(0.95, 0.6, 0.15), Vector3(0, 0.02, -1.6), false)
	_part(t.body, _box(0.8, 0.3, 0.5), Color(1.0, 0.8, 0.2), Vector3(0, 0.3, -0.5))     # his gold chest plate
	_part(t.body, _box(0.5, 0.22, 0.4), Color(0.2, 0.25, 0.5), Vector3(0, 0.45, -1.0))    # the general's cap
	_wings(t, 2.4, 1.1, Color(0.8, 0.82, 0.88))
	t.radius = Vector2(2.6, 1.7)
	return t

# ---------- lifecycle ----------

func hide_all() -> void:
	for t in _all:
		_release(t)
	for g in _groups:
		g.active = false
		g.members.clear()
		g.arrow.visible = false
	for mi in _tracers:
		mi.visible = false

func _release(t: Th) -> void:
	t.active = false
	t.armed = false
	t.shown = false
	t.dying = 0.0
	t.group = null
	t.visible = false
	if t.marker != null:
		t.marker.visible = false

## A fresh run: nothing in play, the opening script starts over.
func reset() -> void:
	hide_all()
	_script_i = 0
	_script_wait = 0.0
	_budget = 0.0
	_since_launch = 99.0
	_next_boss_m = Tuning.boss_first_meters
	_boss_rot = 0
	_boss_gap_t = 0.0
	_boss_stage = 0
	boss_active = false
	boss_name = ""
	boss_mini = false
	boss_kind = -1
	bosses_done = 0
	kills = 0
	kills_by_kind.clear()
	shots = 0
	hits_by_kind.clear()
	last_hit_kind = -1
	timeline.clear()
	launched.clear()
	intro_shown.clear()
	_gun_cd = {"flak": 0.0, "pods": 0.0, "tail": 0.0}
	elapsed = 0.0
	meters = 0.0
	_clock = 0.0
	_hawk_next = 0
	_last_kind = -1
	_general_wave = 0
	_script = [
		[Tuning.first_hawk_time, "hawk"], [Tuning.first_hawk_time + 8.0, "match"], [Tuning.first_golden_time, "golden"],
		[Tuning.first_hawk_time + 32.0, "hawk"], [Tuning.first_geese_time, "geese"], [Tuning.first_geese_time + 14.0, "hawk"],
		[Tuning.mini_boss_time, "mini"], [Tuning.first_crows_time, "crows"], [Tuning.first_drone_time, "drone"]]

func _log(text: String) -> void:
	timeline.append([snappedf(elapsed, 0.1), text])
	event.emit(text)

func active_count() -> int:
	var n := 0
	for t in _hawks:
		n += 1 if t.active else 0
	for t in _drones:
		n += 1 if t.active else 0
	for g in _groups:
		n += 1 if g.active and g.kind != GENERAL else 0
	return n

func _free(pool: Array[Th]) -> Th:
	for t in pool:
		if not t.active:
			return t
	return null

func _free_group() -> Grp:
	for g in _groups:
		if not g.active:
			return g
	return null

func _clamp_z(z: float) -> float:
	return clampf(z, -half_h + 1.5, half_h - 1.0)

# ---------- per-frame ----------

## Main calls this every frame of a run (delta in seconds of simulation).
func update(delta: float) -> void:
	if not enabled or DebugFlags.off("threats"):
		return
	_clock += delta
	_director(delta)
	_since_launch += delta
	for t in _hawks:
		if t.active:
			_update_hawk(t, delta)
	for g in _groups:
		if g.active:
			match g.kind:
				GOOSE:
					_update_squad(g, delta)
				CROW:
					_update_crows(g, delta)
				GENERAL:
					_update_general(g, delta)
	for t in _drones:
		if t.active:
			_update_drone(t, delta)
	for t in _bombs:
		if t.active:
			_update_bomb(t, delta)
	if boss_active:
		_update_boss(delta)
	_update_guns(delta)
	for t in _blasts:
		if t.active:
			t.t += delta
			var k := t.t / 0.32
			if k >= 1.0:
				_release(t)
			else:
				t.marker.global_position = Vector3(t.x, MARK_Y + 0.01, t.z)
				t.marker.scale = Vector3.ONE * lerpf(0.4, t.radius.x, 1.0 - (1.0 - k) * (1.0 - k))
				t.marker_mat.albedo_color.a = 0.55 * (1.0 - k)
	for i in _tracers.size():
		if _tracer_t[i] > 0.0:
			_tracer_t[i] -= delta
			if _tracer_t[i] <= 0.0:
				_tracers[i].visible = false
	_update_dying(delta)

func _update_dying(delta: float) -> void:
	for t in _all:
		if t.dying > 0.0 and t.active:
			t.dying -= delta
			t.body.rotation.y += delta * 14.0
			t.body.scale = Vector3.ONE * maxf(t.dying / 0.35, 0.05)
			if t.dying <= 0.0:
				_release(t)

func _face(t: Node3D, dx: float, dz: float) -> void:
	t.rotation.y = atan2(-dx, -dz)

func _flap(t: Th, rate: float, amount: float) -> void:
	if t.wing_l == null:
		return
	var a := sin(_clock * rate + t.phase) * amount
	t.wing_l.rotation.z = a
	t.wing_r.rotation.z = -a

func _put(t: Th, x: float, z: float, y: float = FLY_Y) -> void:
	t.x = x
	t.z = z
	t.position = Vector3(x, y, z)

# ---------- director ----------

func _unlocked(kind: int) -> bool:
	match kind:
		HAWK:
			return elapsed >= Tuning.first_hawk_time + 20.0
		GOOSE:
			return elapsed >= Tuning.first_geese_time + 10.0
		CROW:
			return elapsed >= Tuning.first_crows_time + 5.0
		DRONE:
			return elapsed >= Tuning.first_drone_time + 5.0
	return false

## How far into the ramp the run is: 0 before it starts, 1 at threat_ramp_end, and on past that (up to 4) so the pressure keeps rising.
func _ramp() -> float:
	return clampf((elapsed - Tuning.threat_ramp_start) / maxf(Tuning.threat_ramp_end - Tuning.threat_ramp_start, 1.0), 0.0, 4.0)

## Hit points of a regular threat launched now: 1 until the ramp ends, then growing, so a gun build is not endless.
func hp_scale() -> float:
	return 1.0 + maxf(_ramp() - 1.0, 0.0) * Tuning.threat_hp_growth

func threat_rate() -> float:
	return Tuning.threat_rate_start + (Tuning.threat_rate_end - Tuning.threat_rate_start) * _ramp()

func max_active() -> int:
	var k := _ramp()
	return roundi(lerpf(Tuning.threat_max_active_start, Tuning.threat_max_active_end, minf(k, 1.0)) + maxf(k - 1.0, 0.0) * 1.5)

func _director(delta: float) -> void:
	if _boss_stage == 0 and _boss_gap_t > 0.0:
		_boss_gap_t -= delta
	# the opening script: one new thing at a time, each alone
	if _script_i < _script.size() and elapsed >= float(_script[_script_i][0]) and not boss_active:
		if active_count() == 0 or _script_wait > 4.0:
			if _run_script(String(_script[_script_i][1])) or _script_wait > 6.0:
				_script_i += 1
				_script_wait = 0.0
			else:
				_script_wait += delta   # (it could not launch just now, e.g. no room for the crows: it tries again for a few seconds)
		else:
			_script_wait += delta
	# bosses at distance milestones
	if not boss_active and _boss_gap_t <= 0.0 and meters >= _next_boss_m and elapsed > Tuning.mini_boss_time + 20.0 and active_count() <= 1:
		_next_boss_m = maxf(_next_boss_m, meters) + Tuning.boss_every_meters
		_start_boss(_boss_rot % 3, false)
		_boss_rot += 1
	if boss_active or _script_i < _script.size() or elapsed < Tuning.threat_ramp_start:
		return
	var factor: float = Tuning.threat_wave_factor[clampi(wave_phase, 0, 3)]
	_budget = minf(_budget + threat_rate() * factor * delta, 6.0)
	if _since_launch < Tuning.threat_min_gap or active_count() >= max_active():
		return
	var cands: Array[int] = []
	for k in [HAWK, GOOSE, CROW, DRONE]:
		if _unlocked(k) and _budget >= float(Tuning.threat_cost[k]):
			cands.append(k)
	if cands.is_empty():
		return
	if cands.size() > 1 and _last_kind in cands:
		cands.erase(_last_kind)   # variety: not the same thing twice in a row
	var pick: int = cands.pick_random()
	if _launch(pick):
		_last_kind = pick
		_budget -= float(Tuning.threat_cost[pick])
		_since_launch = 0.0

func _run_script(what: String) -> bool:
	match what:
		"hawk":
			return _launch(HAWK)
		"match":   # the second meeting is the one the gun the player took answers: Flak -> a hawk, Wing Pods -> geese, Tail Gun -> crows
			if int(gun_levels.get("tail", 0)) > 0:
				return _launch(CROW, true)
			if int(gun_levels.get("pods", 0)) > 0:
				return _launch(GOOSE, true)
			return _launch(HAWK)
		"geese":
			return _launch(GOOSE, true)
		"crows":
			return _launch(CROW, true)
		"drone":
			return _launch(DRONE, true)
		"mini":
			_start_boss(0, true)
			return true
		"golden":
			var dropped := 0
			for off in [-1.7, 0.0, 1.7]:
				if spawner.drop_can_ahead(plane_x + off, true):
					dropped += 1
			_log("Golden cans drop ahead (%d)" % dropped)
			return true
	return true

func _launch(kind: int, gentle: bool = false) -> bool:
	var ok := false
	match kind:
		HAWK:
			ok = _launch_hawk()
		GOOSE:
			ok = _launch_squad(gentle)
		CROW:
			ok = _launch_crows(gentle)
		DRONE:
			ok = _launch_drone()
	if ok:
		launched[NAMES[kind]] = int(launched.get(NAMES[kind], 0)) + 1
	return ok

func _intro(kind: int) -> void:
	telegraph.emit(kind)
	if not intro_shown.has(kind):
		intro_shown[kind] = true

# ---------- hawk ----------

func _launch_hawk() -> bool:
	var h := _free(_hawks)
	if h == null:
		return false
	h.active = true
	h.state = 1
	h.t = 0.0
	h.armed = false
	h.shown = true
	h.hp = hp_scale()
	h.dying = 0.0
	h.phase = randf() * 6.0
	h.lx = plane_x
	h.lz = _clamp_z(plane_z)
	h.body.scale = Vector3.ONE * 0.45
	h.body.rotation = Vector3.ZERO
	h.visible = true
	h.marker.visible = true
	_face(h.body, 0.0, 1.0)   # the nose points down the screen
	_put(h, h.lx, h.lz - HAWK_START)
	_log("Hawk circles")
	_intro(HAWK)
	return true

func _update_hawk(h: Th, delta: float) -> void:
	h.t += delta
	_flap(h, 22.0, 0.5)
	match h.state:
		1:   # the shadow grows and follows the plane, then locks
			var locked := h.t >= Tuning.hawk_warn - Tuning.hawk_lock
			if not locked:
				h.lx = move_toward(h.lx, plane_x, 14.0 * delta)
				h.lz = move_toward(h.lz, _clamp_z(plane_z), 10.0 * delta)
			var k := clampf(h.t / Tuning.hawk_warn, 0.0, 1.0)
			h.body.scale = Vector3.ONE * lerpf(0.45, 1.15, k)
			_put(h, h.lx, h.lz - HAWK_START * (1.0 - 0.15 * k), lerpf(FLY_Y + 1.5, FLY_Y, k))
			h.marker.global_position = Vector3(h.lx, MARK_Y, h.lz)
			h.marker.scale = Vector3.ONE * lerpf(0.5, Tuning.hawk_radius.x * 1.05, k)
			h.marker_mat.albedo_color = Color(1.0, 0.18, 0.08, 0.5) if locked and int(h.t * 16.0) % 2 == 0 else (Color(0.9, 0.2, 0.1, 0.4) if locked else Color(0.0, 0.0, 0.0, 0.18 + 0.25 * k))
			if h.t >= Tuning.hawk_warn:
				h.state = 2
				h.t = 0.0
				h.armed = true
		2:   # the dive
			var p := clampf(h.t / Tuning.hawk_dive, 0.0, 1.0)
			h.prev_z = h.z
			_put(h, h.lx, lerpf(h.lz - HAWK_START, h.lz + 0.6, p * p), FLY_Y)
			h.body.scale = Vector3.ONE * lerpf(1.15, 1.3, p)
			h.marker_mat.albedo_color = Color(1.0, 0.1, 0.05, 0.6)
			if p >= 1.0:
				h.state = 3
				h.t = 0.0
		3:   # pulls out and leaves
			h.prev_z = h.z
			_put(h, h.lx, h.z + 26.0 * delta, FLY_Y)
			h.marker_mat.albedo_color.a = maxf(h.marker_mat.albedo_color.a - 4.0 * delta, 0.0)
			if h.t > 0.22:
				h.armed = false
			if h.z > half_h + 3.0 or h.t > 1.2:
				_release(h)

# ---------- geese ----------

func _take_members(pool: Array[Th], n: int, kind_out: int) -> Array[Th]:
	var out: Array[Th] = []
	for t in pool:
		if not t.active and out.size() < n:
			out.append(t)
	if out.size() < n:
		return []
	return out

func _launch_squad(gentle: bool) -> bool:
	var g := _free_group()
	if g == null or boss_active:
		return false
	var mem := _take_members(_geese, geese_n(gentle), GOOSE)
	if mem.is_empty():
		return false
	g.kind = GOOSE
	g.active = true
	g.state = 1
	g.t = 0.0
	g.dir = 1.0 if randf() < 0.5 else -1.0
	var bottom := z_max
	var lane := plane_z - 0.3 + randf_range(-0.8, 0.8)
	if randf() > Tuning.lightning_aim and not gentle:
		lane = randf_range(-half_h + 5.0, plane_z - 3.0)
	if plane_z > bottom - 3.4:
		lane = plane_z - 3.6   # a plane against the bottom edge gets its lane above it: it can stay put
	g.z = _clamp_z(lane)
	g.x = -g.dir * (Tuning.ortho_size * 0.5 + 3.4)
	g.members = mem
	for i in mem.size():
		var m: Th = mem[i]
		m.active = true
		m.kind = GOOSE
		m.group = g
		m.back = V_BACK[i % 5]
		m.side = V_SIDE[i % 5]
		m.hp = hp_scale()
		m.armed = false
		m.shown = false
		m.dying = 0.0
		m.visible = false
		m.phase = randf() * 6.0
		m.body.scale = Vector3.ONE
		m.body.rotation = Vector3.ZERO
		_face(m.body, g.dir, 0.0)
	g.arrow.visible = true
	g.arrow.position = Vector3(-g.dir * (Tuning.ortho_size * 0.5 - 0.9), MARK_Y + 0.02, g.z)
	g.arrow.rotation.y = atan2(-g.dir, 0.0)
	g.arrow.scale = Vector3.ONE * 1.1
	_log("Geese squadron incoming")
	_intro(GOOSE)
	return true

func geese_n(gentle: bool) -> int:
	return maxi(3, Tuning.geese_count - (2 if gentle and elapsed < Tuning.first_geese_time + 20.0 else 0))

func _update_squad(g: Grp, delta: float) -> void:
	g.t += delta
	if g.state == 1:
		var pulse := 0.5 + 0.5 * sin(g.t * 16.0)
		g.arrow_mat.albedo_color = Color(1.0, 0.35, 0.1, 0.25 + 0.55 * pulse * (g.t / Tuning.geese_warn))
		g.arrow.scale = Vector3.ONE * (1.1 + 0.25 * pulse)
		if g.t >= Tuning.geese_warn:
			g.state = 2
			g.t = 0.0
			g.arrow.visible = false
			for m in g.members:
				m.visible = true
				m.shown = true
				m.armed = true
		return
	# crossing: the lane drifts gently toward the plane until the lead is close in x, then holds
	g.x += g.dir * Tuning.geese_speed * delta
	if absf(g.x - plane_x) > 3.2 and (g.x - plane_x) * g.dir < 0.0:
		g.z = _clamp_z(move_toward(g.z, plane_z, Tuning.geese_steer * delta))
	var alive := false
	for m in g.members:
		if not m.active:
			continue
		if m.dying > 0.0:
			alive = true
			continue
		m.prev_z = m.z
		_put(m, g.x - g.dir * m.back, g.z + m.side)
		_flap(m, 14.0, 0.45)
		var on_screen := absf(m.x) < Tuning.ortho_size * 0.5 + 3.0
		m.armed = on_screen
		if (m.x - g.dir * 0.0) * g.dir < Tuning.ortho_size * 0.5 + 4.0:
			alive = true
	if not alive:
		_end_group(g)

func _end_group(g: Grp) -> void:
	for m in g.members:
		if m.active:
			_release(m)
	g.members.clear()
	g.active = false
	g.arrow.visible = false

# ---------- crows ----------

func _launch_crows(gentle: bool) -> bool:
	var g := _free_group()
	if g == null or boss_active:
		return false
	if not _rows_roomy():
		return false
	var mem := _take_members(_crows, Tuning.crow_count - (1 if gentle else 0), CROW)
	if mem.is_empty():
		return false
	g.kind = CROW
	g.active = true
	g.state = 1
	g.t = 0.0
	g.x = plane_x
	g.z = half_h + 3.0
	g.members = mem
	for i in mem.size():
		var m: Th = mem[i]
		m.active = true
		m.group = g
		m.side = CROW_OFF[i]
		m.back = float(i % 3) * 0.6
		m.hp = hp_scale()
		m.armed = false
		m.shown = false
		m.dying = 0.0
		m.visible = false
		m.phase = randf() * 6.0
		m.body.scale = Vector3.ONE
		m.body.rotation = Vector3.ZERO
		m.x = plane_x + m.side
		_face(m.body, 0.0, -1.0)
	g.arrow.visible = true
	g.arrow.rotation.y = 0.0
	g.arrow.scale = Vector3.ONE * 1.1
	_log("Crows close in from behind")
	_intro(CROW)
	return true

## The crows need room to weave: every row that passes the plane while they close in has two or more open columns.
func _rows_roomy() -> bool:
	if spawner == null:
		return true
	for r in spawner.hazards._rows_in_window(Tuning.crow_warn + 3.5):
		var n := 0
		for o in r.open:
			n += 1 if o else 0
		if n < 2:
			return false
	return true

func _update_crows(g: Grp, delta: float) -> void:
	g.t += delta
	if g.state == 1:
		var pulse := 0.5 + 0.5 * sin(g.t * 16.0)
		g.arrow.position = Vector3(plane_x, MARK_Y + 0.02, half_h - 1.4)
		g.arrow_mat.albedo_color = Color(1.0, 0.35, 0.1, 0.25 + 0.55 * pulse * (g.t / Tuning.crow_warn))
		g.arrow.scale = Vector3.ONE * (1.1 + 0.25 * pulse)
		if g.t >= Tuning.crow_warn:
			g.state = 2
			g.t = 0.0
			g.arrow.visible = false
			for m in g.members:
				m.visible = true
				m.shown = true
				m.armed = true
		return
	g.z -= Tuning.crow_close * delta
	var alive := false
	for m in g.members:
		if not m.active:
			continue
		if m.dying > 0.0:
			alive = true
			continue
		m.prev_z = m.z
		if m.z > plane_z + 2.2:   # (a crow commits once it is close: it flies straight on, never homing)
			m.x = move_toward(m.x, plane_x + m.side, Tuning.crow_follow * delta)
		_put(m, m.x, g.z + m.back)
		m.position.x += sin(_clock * 3.0 + m.phase) * 0.12   # (a wobble you see; the crow's own x stays clean)
		_flap(m, 20.0, 0.55)
		if m.z > -half_h - 3.0:
			alive = true
	if not alive:
		_end_group(g)

# ---------- drone ----------

func _launch_drone() -> bool:
	var d := _free(_drones)
	if d == null or boss_active:
		return false
	d.active = true
	d.state = 1
	d.t = 0.0
	d.armed = false
	d.shown = true
	d.hp = hp_scale()
	d.dying = 0.0
	d.lx = plane_x
	d.body.scale = Vector3.ONE
	d.body.rotation = Vector3.ZERO
	d.visible = true
	d.marker.visible = true
	d.marker_mat.albedo_color = Color(1.0, 0.2, 0.1, 0.0)
	_put(d, clampf(plane_x, -5.0, 5.0), -half_h - 1.0)
	_log("Drone hovers")
	_intro(DRONE)
	return true

func _drone_top() -> float:
	return -half_h + 3.0

func _update_drone(d: Th, delta: float) -> void:
	d.t += delta
	d.body.rotation.y += delta * 30.0 * (1.0 if d.state != 3 else 2.0)
	match d.state:
		1:   # comes in from the top, then hovers and tracks the plane
			var top := _drone_top()
			d.prev_z = d.z
			var nz := move_toward(d.z, top, 12.0 * delta)
			_put(d, move_toward(d.x, clampf(plane_x, -5.2, 5.2), 5.0 * delta), nz)
			var sw := Tuning.column_width() + 1.2
			var bottom := half_h + 3.0
			d.marker.global_position = Vector3(d.x, MARK_Y, (top + bottom) * 0.5)
			d.marker.scale = Vector3(sw * 0.5, 1.0, (bottom - top) * 0.5)
			d.marker_mat.albedo_color = Color(1.0, 0.5, 0.2, 0.08)
			if d.t >= Tuning.drone_track:
				d.state = 2
				d.t = 0.0
				d.lx = d.x
				var col: int = spawner.hazards.col_of(d.lx)
				var dur := Tuning.drone_wind + Tuning.drone_dart + 0.3
				if not spawner.hazards.strike_allowed(col, dur):
					var alt: int = spawner.hazards.nearest_allowed(col, dur)
					if alt < 0:
						d.state = 5   # no safe lane right now: it gives up and leaves
						return
					d.lx = Tuning.column_center(alt)
				telegraph.emit(DRONE)
		2:   # wind-up: the lane glows and pulses, the eye burns
			var k := clampf(d.t / Tuning.drone_wind, 0.0, 1.0)
			d.x = move_toward(d.x, d.lx, 14.0 * delta)
			var sw2 := Tuning.column_width() + 1.2
			d.position.x = d.x + sin(_clock * 60.0) * 0.06 * k
			var bottom2 := half_h + 3.0
			d.marker.global_position = Vector3(d.lx, MARK_Y, (_drone_top() + bottom2) * 0.5)
			d.marker.scale = Vector3(sw2 * 0.5, 1.0, (bottom2 - _drone_top()) * 0.5)
			d.marker_mat.albedo_color = Color(1.0, 0.1, 0.05, (0.18 + 0.3 * k) * (0.6 + 0.4 * sin(d.t * 26.0)))
			d.eye_mat.emission_energy_multiplier = 0.3 + 3.0 * k
			if d.t >= Tuning.drone_wind:
				d.state = 3
				d.t = 0.0
				d.armed = true
		3:   # the dart down the locked lane
			var len := half_h * 2.0 + 6.0
			d.prev_z = d.z
			_put(d, d.lx, _drone_top() + len * clampf(d.t / Tuning.drone_dart, 0.0, 1.0))
			d.marker_mat.albedo_color = Color(1.0, 0.1, 0.05, 0.5 * (1.0 - d.t / Tuning.drone_dart))
			if d.t >= Tuning.drone_dart:
				d.state = 5
				d.armed = false
		5:   # leaves (up or off the bottom)
			d.armed = false
			d.marker.visible = false
			d.prev_z = d.z
			_put(d, d.x, d.z - 18.0 * delta if d.z < _drone_top() + 1.0 else d.z + 20.0 * delta)
			if d.z < -half_h - 3.0 or d.z > half_h + 3.0:
				d.eye_mat.emission_energy_multiplier = 0.2
				_release(d)

# ---------- bombs (the bosses' drops) ----------

func _drop_bomb(fx0: float, fz0: float, warn: float) -> bool:
	var b := _free(_bombs)
	if b == null:
		return false
	var tx := plane_x + randf_range(-1.6, 1.6)
	var tz := _clamp_z(plane_z - randf_range(2.5, 5.0))
	b.active = true
	b.state = 1
	b.t = 0.0
	b.lx = clampf(tx, -5.2, 5.2)
	b.lz = tz
	b.phase = fx0
	b.dir = fz0
	b.armed = false
	b.shown = false
	b.hp = 1.0
	b.dying = 0.0
	b.visible = true
	b.marker.visible = true
	b.body.visible = true
	b.body.scale = Vector3.ONE
	b.body.rotation = Vector3.ZERO
	b.back = warn
	_put(b, fx0, fz0, FLY_Y + 1.0)
	return true

func _update_bomb(b: Th, delta: float) -> void:
	b.t += delta
	if b.state == 1:
		var k := clampf(b.t / b.back, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		_put(b, lerpf(b.phase, b.lx, e), lerpf(b.dir, b.lz, e), FLY_Y + 1.0 + 1.6 * sin(PI * k))
		b.body.rotation.y += delta * 8.0
		b.marker.global_position = Vector3(b.lx, MARK_Y, b.lz)
		b.marker.scale = Vector3.ONE * lerpf(0.5, Tuning.bomb_radius, k)
		b.marker_mat.albedo_color = Color(1.0, 0.25, 0.08, (0.2 + 0.4 * k) * (0.7 + 0.3 * sin(b.t * 18.0)))
		if k >= 1.0:
			b.state = 2
			b.t = 0.0
			b.armed = true
			b.body.visible = false
			b.x = b.lx
			b.z = b.lz
			b.position = Vector3(b.lx, FLY_Y, b.lz)
			blast.emit(Vector3(b.lx, FLY_Y, b.lz), true)
	else:
		b.marker.global_position = Vector3(b.lx, MARK_Y + 0.01, b.lz)
		b.marker.scale = Vector3.ONE * Tuning.bomb_radius * (1.0 + 0.3 * b.t / Tuning.bomb_blast)
		b.marker_mat.albedo_color = Color(1.0, 0.7, 0.2, 0.7 * (1.0 - b.t / Tuning.bomb_blast))
		if b.t >= Tuning.bomb_blast:
			b.armed = false
			_release(b)

# ---------- bosses ----------

func _start_boss(which: int, mini: bool) -> void:
	boss_active = true
	boss_mini = mini
	boss_kind = which
	boss_name = MINI_NAME if mini else BOSS_NAMES[which]
	_boss_stage = 1
	boss_t = 0.0
	_boss_defeated = false
	_boss_drop_t = 1.4
	_boss_strike_t = 1.6
	var hp_max: float = Tuning.mini_boss_hp if mini else float(Tuning.boss_hp[which]) * minf(1.0 + Tuning.boss_hp_growth * float(bosses_done), 3.0)   # later bosses are tougher
	boss_hp = hp_max
	boss_hp_max = hp_max
	_log("%s: warning" % boss_name)
	boss_warning.emit(boss_name)

func _boss_unit() -> Th:
	if boss_mini:
		return _duster
	match boss_kind:
		0:
			return _falcon
		1:
			return _storm
		_:
			return _general

func _update_boss(delta: float) -> void:
	boss_t += delta
	var u := _boss_unit()
	match _boss_stage:
		1:   # the banner: nothing hostile yet
			if boss_t >= Tuning.boss_warn_time:
				_boss_stage = 2
				boss_t = 0.0
				_boss_enter(u)
				boss_started.emit(boss_name)
				_log("%s arrives" % boss_name)
		2:
			var limit := Tuning.mini_boss_time_limit if boss_mini else Tuning.boss_time
			_boss_move(u, delta)
			if boss_hp <= 0.0 and not _boss_defeated:
				_boss_defeated = true
				_boss_leave(u, true)
			elif boss_t >= limit:
				_boss_leave(u, false)
		3:
			_boss_leave_t += delta
			_boss_exit(u, delta)
			if _boss_leave_t > 1.4:
				_boss_finish(u)

func _boss_enter(u: Th) -> void:
	u.active = true
	u.visible = true
	u.shown = true
	u.armed = false
	u.dying = 0.0
	u.body.scale = Vector3.ONE
	u.body.rotation = Vector3.ZERO
	u.state = 1
	u.t = 0.0
	u.hp = boss_hp
	u.dir = 1.0 if randf() < 0.5 else -1.0
	if boss_mini:
		_put(u, -u.dir * 8.0, -half_h + 5.0)
		_face(u.body, u.dir, 0.0)
	elif boss_kind == 0:
		_put(u, u.dir * 9.0, plane_z - 9.0)
	elif boss_kind == 1:
		_put(u, -6.0, -half_h - 3.0, FLY_Y + 0.3)
		u.dir = 1.0
	else:
		_general_pass_t = 0.0
		u.visible = false
		u.shown = false
		_start_general_pass(1)

func _boss_move(u: Th, delta: float) -> void:
	_flap(u, 16.0, 0.35)
	if boss_mini:
		# sweeps back and forth across the top, dropping sacks ahead of the plane (slow and clearly marked)
		u.prev_z = u.z
		var nx := u.x + u.dir * 3.6 * delta
		if absf(nx) > 6.8:
			u.dir = -u.dir
			_face(u.body, u.dir, 0.0)
		_put(u, nx, -half_h + 5.0 + sin(boss_t * 1.2) * 1.0)
		_boss_drop_t -= delta
		if _boss_drop_t <= 0.0:
			_boss_drop_t = Tuning.duster_drop_every
			_drop_bomb(u.x, u.z, Tuning.bomb_warn + 0.5)
		return
	match boss_kind:
		0:   # Flash flies alongside, swapping sides now and then, dropping bombs in the plane's path
			var side := 1.0 if int(boss_t / 6.5) % 2 == 0 else -1.0
			var goal_x := clampf(plane_x + side * 4.0, -5.2, 5.2)
			if absf(goal_x - plane_x) < 2.6:
				goal_x = plane_x - side * 4.0
			var gz := plane_z - 1.0 + sin(boss_t * 1.7) * 1.4
			u.prev_z = u.z
			_put(u, lerpf(u.x, goal_x, 1.0 - exp(-2.6 * delta)), lerpf(u.z, gz, 1.0 - exp(-3.0 * delta)))
			_face(u.body, 0.0, -1.0)
			u.body.rotation.z = clampf((goal_x - u.x) * -0.1, -0.5, 0.5)
			_boss_drop_t -= delta
			if _boss_drop_t <= 0.0:
				_boss_drop_t = Tuning.falcon_drop_every
				_drop_bomb(u.x, u.z, Tuning.bomb_warn)
		1:   # the Thunderhead drifts across the top calling bolts down the lanes
			var nx2 := -5.0 + 10.0 * (0.5 + 0.5 * sin(boss_t * 0.55 - 1.2))
			u.prev_z = u.z
			_put(u, nx2, -half_h + 3.2, FLY_Y + 0.3)
			u.eye_mat.emission_energy_multiplier = 0.2 + (1.8 if fmod(boss_t, Tuning.storm_strike_every) < 0.15 else 0.0)
			_boss_strike_t -= delta
			if _boss_strike_t <= 0.0:
				_boss_strike_t = Tuning.storm_strike_every
				var col: int = spawner.hazards.col_of(plane_x if randf() < Tuning.storm_aim else u.x + randf_range(-2.5, 2.5))
				if not spawner.hazards.force_strike(col):
					spawner.hazards.force_strike(spawner.hazards.nearest_allowed(col))
		_:
			# the Goose General's formation: pass after pass
			_general_pass_t += delta
			if _general_group() == null and _general_wave < Tuning.general_waves:
				_start_general_pass(_general_wave + 1)

var _general_wave := 0

func _general_group() -> Grp:
	for g in _groups:
		if g.active and g.kind == GENERAL:
			return g
	return null

func _start_general_pass(wave: int) -> void:
	var g := _free_group()
	if g == null:
		return
	var mem := _take_members(_geese, GOOSE_POOL, GGOOSE)
	if mem.is_empty():
		mem = _take_members(_geese, 10, GGOOSE)
	if mem.is_empty():
		return
	_general_wave = wave
	g.kind = GENERAL
	g.active = true
	g.state = 2
	g.t = 0.0
	g.wave = wave
	g.dir = 1.0 if randf() < 0.5 else -1.0
	g.gap = clampf(plane_x + g.dir * randf_range(3.0, 4.2), -4.4, 4.4)
	if absf(g.gap) < 3.2:
		g.gap = 3.6 * (1.0 if g.gap >= 0.0 else -1.0)
	g.z = -half_h - 3.5
	g.x = 0.0
	g.members = mem
	var n := mem.size()
	for i in n:
		var m: Th = mem[i]
		m.active = true
		m.group = g
		m.kind = GGOOSE
		m.side = (float(i) - float(n - 1) * 0.5) * 1.05          # x offset across the wall
		m.back = absf(m.side) * 0.22                              # the V: the wings trail
		m.hp = 1.0
		m.armed = false
		m.shown = false
		m.visible = false
		m.dying = 0.0
		m.phase = randf() * 6.0
		m.body.scale = Vector3.ONE
		m.body.rotation = Vector3.ZERO
		_face(m.body, 0.0, 1.0)
	var u := _general
	u.active = true
	u.visible = false
	u.shown = false
	u.hp = boss_hp
	u.dying = 0.0
	u.group = g
	u.body.scale = Vector3.ONE
	u.body.rotation = Vector3.ZERO
	_face(u.body, 0.0, 1.0)
	telegraph.emit(GENERAL)
	_log("General's wall, pass %d" % wave)

func _update_general(g: Grp, delta: float) -> void:
	g.t += delta
	g.z += 5.2 * delta
	g.gap = clampf(g.gap + sin(g.t * 0.9 + g.wave) * 0.9 * delta, -4.6, 4.6)
	var alive := false
	for m in g.members:
		if not m.active:
			continue
		if m.dying > 0.0:
			alive = true
			continue
		var mx: float = m.side
		var in_gap := absf(mx - g.gap) < Tuning.general_gap * 0.5 or absf(mx) > Tuning.ortho_size * 0.5 + 0.2
		m.prev_z = m.z
		_put(m, mx, g.z + m.back)
		_flap(m, 12.0, 0.4)
		m.visible = not in_gap
		m.shown = m.visible and m.z > -half_h - 1.0 and m.z < half_h + 1.0
		m.armed = m.shown
		if m.z < half_h + 3.0 and not in_gap:
			alive = true
	var u := _general
	if u.active and u.dying <= 0.0:
		var ux := 0.0
		if absf(ux - g.gap) < Tuning.general_gap * 0.5 + 1.8:
			ux = clampf(g.gap + (-1.0 if g.gap > 0.0 else 1.0) * (Tuning.general_gap * 0.5 + 2.6), -4.0, 4.0)   # never in the gap
		u.prev_z = u.z
		_put(u, ux, g.z - 1.2)
		u.visible = true
		u.shown = u.z > -half_h - 1.0 and u.z < half_h + 1.0
		u.armed = u.shown
		_flap(u, 9.0, 0.35)
		if u.z < half_h + 3.0:
			alive = true
	if not alive:
		_end_group(g)
		_general.visible = false
		_general.armed = false
		_general.shown = false

func _boss_leave(u: Th, defeated: bool) -> void:
	_boss_stage = 3
	_boss_leave_t = 0.0
	_boss_defeated = defeated
	for g in _groups:
		if g.active and g.kind == GENERAL:
			for m in g.members:
				if m.active and m.dying <= 0.0 and m.visible:
					_kill(m, true, false)
			_end_group(g)
	u.armed = false
	u.shown = false
	if defeated:
		blast.emit(Vector3(u.x, FLY_Y, u.z), true)
		killed.emit(u.kind, Vector3(u.x, FLY_Y, u.z), true)
		u.dying = 0.0
	_log("%s %s" % [boss_name, "driven off" if defeated else "survived"])

func _boss_exit(u: Th, delta: float) -> void:
	if not u.visible:
		return
	if _boss_defeated:
		u.body.rotation.y += delta * 10.0
		u.body.scale = Vector3.ONE * maxf(1.0 - _boss_leave_t / 1.0, 0.05)
		_put(u, u.x, u.z - 4.0 * delta)
	else:
		_put(u, u.x + (u.dir if u.x != 0.0 else 1.0) * 12.0 * delta, u.z - 9.0 * delta)

func _boss_finish(u: Th) -> void:
	_release(u)
	u.body.scale = Vector3.ONE
	_boss_stage = 0
	boss_active = false
	_boss_gap_t = 30.0
	bosses_done += 1
	_general_wave = 0
	boss_ended.emit(boss_name, _boss_defeated, boss_mini)

func damage_boss(amount: float) -> void:
	if boss_active and _boss_stage == 2:
		boss_hp = maxf(boss_hp - amount, 0.0)

# ---------- hits ----------

func _boss_target() -> Th:
	if boss_active and _boss_stage == 2:
		var u := _boss_unit()
		if u.active and u.shown:
			return u
	return null

## Is the plane touching a threat? Returns the kind (or -1). `p` is the plane's (x, z); the sweep from `from`
## covers fast movement. Only armed threats count.
func hit(p: Vector2, from: Vector2 = Vector2(INF, INF)) -> int:
	if not enabled:
		return -1
	for h in _hawks:
		if h.active and h.armed and absf(p.x - h.x) < h.radius.x and p.y > minf(h.prev_z, h.z) - h.radius.y and p.y < maxf(h.prev_z, h.z) + h.radius.y:
			return _hit(HAWK)
	for g in _groups:
		if not g.active:
			continue
		for m in g.members:
			if m.active and m.armed and m.dying <= 0.0 and absf(p.x - m.x) < m.radius.x and absf(p.y - m.z) < m.radius.y:
				return _hit(GGOOSE if g.kind == GENERAL else m.kind)
	if _general.active and _general.armed and _general.dying <= 0.0 and absf(p.x - _general.x) < _general.radius.x and absf(p.y - _general.z) < _general.radius.y:
		return _hit(GENERAL)
	for d in _drones:
		if d.active and d.armed and absf(p.x - d.x) < d.radius.x and p.y > minf(d.prev_z, d.z) - d.radius.y and p.y < maxf(d.prev_z, d.z) + d.radius.y:
			return _hit(DRONE)
	for b in _bombs:
		if b.active and b.armed and Vector2(p.x - b.lx, p.y - b.lz).length() < Tuning.bomb_radius + 0.9:
			return _hit(BOMB)
	return -1

func _hit(kind: int) -> int:
	last_hit_kind = kind
	hits_by_kind[kind] = int(hits_by_kind.get(kind, 0)) + 1
	return kind

# ---------- guns ----------

func _gun_sector_ok(gun: String, dx: float, dz: float) -> bool:
	var d := sqrt(dx * dx + dz * dz)
	if d < 0.01:
		return true
	var c := -dz / d   # cosine of the angle from straight ahead (the nose is -z)
	match gun:
		"flak":
			return c >= 0.55
		"pods":
			return absf(c) < 0.55
		_:
			return c <= -0.55

func _targets(out: Array[Th]) -> void:
	out.clear()
	for t in _hawks:
		if t.active and t.shown:
			out.append(t)
	for t in _drones:
		if t.active and t.shown and t.state != 5:
			out.append(t)
	for g in _groups:
		if g.active and g.kind != GENERAL:
			for m in g.members:
				if m.active and m.shown and m.dying <= 0.0:
					out.append(m)
	var bt := _boss_target()
	if bt != null:
		out.append(bt)
	var gg := _general_group()
	if gg != null:
		for m in gg.members:
			if m.active and m.shown and m.dying <= 0.0:
				out.append(m)

var _tgt_buf: Array[Th] = []

func _update_guns(delta: float) -> void:
	for gun in _gun_cd:
		_gun_cd[gun] = maxf(_gun_cd[gun] - delta, 0.0)
	if gun_levels.is_empty():
		return
	_targets(_tgt_buf)
	if _tgt_buf.is_empty():
		return
	for gun in ["flak", "pods", "tail"]:
		var lvl := int(gun_levels.get(gun, 0))
		if lvl <= 0 or _gun_cd[gun] > 0.0:
			continue
		var rng: float = Tuning.gun_range[gun][lvl - 1]
		var best: Th = null
		var best_d := INF
		for t in _tgt_buf:
			if t.dying > 0.0 or not t.shown:
				continue
			var dx := t.x - plane_x
			var dz := t.z - plane_z
			var d := sqrt(dx * dx + dz * dz)
			if d > rng or d >= best_d or not _gun_sector_ok(gun, dx, dz):
				continue
			best = t
			best_d = d
		if best == null:
			continue
		_fire(gun, lvl, best)

func _fire(gun: String, lvl: int, target: Th) -> void:
	_gun_cd[gun] = float(Tuning.gun_cooldown[gun][lvl - 1])
	shots += 1
	shot.emit(gun, 0.0)
	var radius: float = Tuning.gun_blast[gun][lvl - 1]
	var dmg: float = Tuning.gun_damage[lvl - 1]
	var tx := target.x
	var tz := target.z
	_show_tracer(Vector3(plane_x, FLY_Y + 0.3, plane_z), Vector3(tx, FLY_Y + 0.3, tz))
	_show_blast(tx, tz, radius)
	blast.emit(Vector3(tx, FLY_Y, tz), false)
	_targets(_tgt_buf)
	for t in _tgt_buf:
		if t.dying > 0.0:
			continue
		if Vector2(t.x - tx, t.z - tz).length() <= radius + (0.6 if t == target else 0.0):
			_damage(t, dmg)

func _damage(t: Th, dmg: float) -> void:
	if t.kind == FALCON or t.kind == STORM or t.kind == DUSTER or t.kind == GENERAL:
		damage_boss(dmg)
		blast.emit(Vector3(t.x, FLY_Y, t.z), false)
		return
	t.hp -= dmg
	if t.hp <= 0.0:
		_kill(t, true, true)

func _kill(t: Th, by_gun: bool, pay: bool) -> void:
	t.armed = false
	t.shown = false
	t.dying = 0.35
	killed.emit(t.kind if t.kind != GGOOSE else GOOSE, Vector3(t.x, FLY_Y, t.z), by_gun and pay)
	if by_gun and pay:
		kills += 1
		var key: int = t.kind if t.kind != GGOOSE else GOOSE
		kills_by_kind[key] = int(kills_by_kind.get(key, 0)) + 1
	# a downed hawk or drone has nothing more to do
	if t.kind == HAWK or t.kind == DRONE:
		t.marker.visible = false
		t.state = 5 if t.kind == DRONE else 4

func _show_tracer(a: Vector3, b: Vector3) -> void:
	for i in _tracers.size():
		if _tracer_t[i] <= 0.0:
			var mi := _tracers[i]
			var d := b - a
			mi.position = (a + b) * 0.5
			mi.scale = Vector3(1.0, 1.0, maxf(d.length(), 0.1))
			mi.rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)
			mi.visible = true
			_tracer_t[i] = 0.12
			return

func _show_blast(x: float, z: float, radius: float) -> void:
	var t := _free(_blasts)
	if t == null:
		return
	t.active = true
	t.t = 0.0
	t.x = x
	t.z = z
	t.radius = Vector2(radius, radius)
	t.marker.visible = true
	t.marker_mat.albedo_color = Color(1.0, 0.7, 0.2, 0.5)

# ---------- queries for the autopilot and the fairness checks ----------

## Every danger zone that will be armed within `horizon` seconds, as {rect: Rect2 (x, z), at: seconds until armed, kind}.
## (Moving threats are given as the area they sweep over the horizon: a cautious reading.)
func zones(horizon: float, out: Array) -> void:
	out.clear()
	for h in _hawks:
		if h.active and h.state in [1, 2]:
			var at := maxf(Tuning.hawk_warn - h.t, 0.0) if h.state == 1 else 0.0
			if at <= horizon:
				var lz := h.lz
				out.append({"rect": Rect2(h.lx - h.radius.x, lz - HAWK_START - h.radius.y, h.radius.x * 2.0, HAWK_START + h.radius.y * 2.0), "at": at, "kind": HAWK})
	for g in _groups:
		if not g.active:
			continue
		if g.kind == GOOSE:
			var at2 := maxf(Tuning.geese_warn - g.t, 0.0) if g.state == 1 else 0.0
			if at2 <= horizon:
				var zlo := g.z - 1.2 - 1.05
				out.append({"rect": Rect2(-Tuning.ortho_size * 0.5 - 4.0, g.z - 0.9 - 1.05, Tuning.ortho_size + 8.0, 3.6 + 2.1), "at": at2, "kind": GOOSE, "lane": zlo})
		elif g.kind == GENERAL:
			var half := Tuning.general_gap * 0.5
			var h := 5.0 + 5.2 * horizon          # the wall's body plus where it will have moved to
			out.append({"rect": Rect2(-Tuning.ortho_size * 0.5 - 1.0, g.z - 2.5, g.gap - half + Tuning.ortho_size * 0.5 + 1.0, h), "at": 0.0, "kind": GGOOSE})
			out.append({"rect": Rect2(g.gap + half, g.z - 2.5, Tuning.ortho_size * 0.5 - g.gap - half + 1.0, h), "at": 0.0, "kind": GGOOSE})
	for d in _drones:
		if d.active and d.state in [2, 3]:
			var at4 := maxf(Tuning.drone_wind - d.t, 0.0) if d.state == 2 else 0.0
			if at4 <= horizon:
				out.append({"rect": Rect2(d.lx - d.radius.x, -half_h - 2.0, d.radius.x * 2.0, half_h * 2.0 + 6.0), "at": at4, "kind": DRONE})
	for b in _bombs:
		if b.active:
			var at5 := maxf(b.back - b.t, 0.0) if b.state == 1 else 0.0
			if at5 <= horizon:
				var br := Tuning.bomb_radius + 0.9
				out.append({"rect": Rect2(b.lx - br, b.lz - br, br * 2.0, br * 2.0), "at": at5, "kind": BOMB})

## Seconds until a crow would touch a plane that stays at (cx, cz) from now on (INF: none will). The flock follows the plane's x
## at crow_follow, so a plane that jumps away late is missed. (The autopilot uses it to weave.)
func crow_danger(cx: float, cz: float) -> float:
	var best := INF
	for g in _groups:
		if not g.active or g.kind != CROW:
			continue
		var wait := maxf(Tuning.crow_warn - g.t, 0.0) if g.state == 1 else 0.0
		for m in g.members:
			if not m.active or m.dying > 0.0:
				continue
			var mz: float = (g.z + m.back) if g.state == 2 else (half_h + 3.0 + m.back)
			var dz := mz - cz
			if dz < -m.radius.y - 1.0:
				continue   # already past
			var tt := wait + maxf(dz, 0.0) / Tuning.crow_close
			var mx0: float = m.x if g.state == 2 else cx + m.side
			var mx := move_toward(mx0, cx + m.side, Tuning.crow_follow * tt)
			if absf(mx - cx) < m.radius.x:
				best = minf(best, tt)
	return best

## A Prop Wash shockwave from `centre`: every threat within `radius` is shoved away (a hawk's, bomb's and drone's aim, a squadron's lane,
## the crows' x), and with `damage` > 0 it is hurt as well (the Shock and Awe combo).
func push(centre: Vector2, radius: float, amount: float, damage: float) -> void:
	var sgn := func(v: float) -> float:
		return 1.0 if v >= 0.0 else -1.0
	for h in _hawks:
		if h.active and h.state <= 2 and Vector2(h.lx - centre.x, h.lz - centre.y).length() < radius:
			h.lx = clampf(h.lx + amount * sgn.call(h.lx - centre.x), -5.4, 5.4)
	for d in _drones:
		if d.active and d.state <= 2 and Vector2(d.x - centre.x, d.z - centre.y).length() < radius + 3.0:
			d.lx = clampf(d.lx + amount * sgn.call(d.x - centre.x), -5.2, 5.2)
			d.x = clampf(d.x + amount * sgn.call(d.x - centre.x), -5.2, 5.2)
	for b in _bombs:
		if b.active and b.state == 1 and Vector2(b.lx - centre.x, b.lz - centre.y).length() < radius:
			b.lx = clampf(b.lx + amount * sgn.call(b.lx - centre.x), -5.4, 5.4)
			b.lz = _clamp_z(b.lz + amount * sgn.call(b.lz - centre.y))
	for g in _groups:
		if not g.active:
			continue
		if g.kind == GOOSE and absf(g.z - centre.y) < radius:
			g.z = _clamp_z(g.z + amount * sgn.call(g.z - centre.y))
		elif g.kind == CROW:
			for m in g.members:
				if m.active and Vector2(m.x - centre.x, m.z - centre.y).length() < radius:
					m.x = clampf(m.x + amount * sgn.call(m.x - centre.x), -6.0, 6.0)
	if damage > 0.0:
		_targets(_tgt_buf)
		for t in _tgt_buf:
			if t.dying <= 0.0 and Vector2(t.x - centre.x, t.z - centre.y).length() <= radius:
				_damage(t, damage)

## Smoke at `p`: the crows and geese touching it are brought down (with `all_kinds`, every kind of threat). Returns how many were hit.
func smoke_hit(p: Vector2, radius: float, all_kinds: bool) -> int:
	var n := 0
	_targets(_tgt_buf)
	for t in _tgt_buf:
		if t.dying > 0.0 or not t.shown:
			continue
		var bird := t.kind == GOOSE or t.kind == CROW
		if (bird or (all_kinds and (t.kind == HAWK or t.kind == DRONE))) and Vector2(t.x - p.x, t.z - p.y).length() < radius + 0.7:
			_damage(t, 1.0)
			n += 1
	return n

## The same, for a plane that flies from `cur` to `cand` at `speed` and holds there: seconds until the first touch (INF: none).
func crow_danger_path(cur: Vector2, cand: Vector2, speed: float) -> float:
	var g: Grp = null
	for gg in _groups:
		if gg.active and gg.kind == CROW:
			g = gg
	if g == null:
		return INF
	var n := g.members.size()
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	for m in g.members:
		xs.append(m.x if g.state == 2 else cur.x + m.side)
		zs.append((g.z if g.state == 2 else half_h + 3.0) + m.back)
	var wait := maxf(Tuning.crow_warn - g.t, 0.0) if g.state == 1 else 0.0
	var dir := cand - cur
	var t := 0.0
	while t < 3.2:
		t += 0.05
		var pp := cur + dir.limit_length(speed * t)
		for i in n:
			var m: Th = g.members[i]
			if not m.active or m.dying > 0.0:
				continue
			if t > wait:
				zs[i] -= Tuning.crow_close * 0.05
				if zs[i] > pp.y + 2.2:
					xs[i] = move_toward(xs[i], pp.x + m.side, Tuning.crow_follow * 0.05)
			if t > wait and absf(xs[i] - pp.x) < m.radius.x + 0.7 and absf(zs[i] - pp.y) < m.radius.y + 0.5:
				return t
	return INF

func prewarm_show() -> void:
	_prewarm = true
	var i := 0
	for t in _all:
		if t.kind == BOMB and t.marker_mat != null and t in _blasts:
			continue
		t.visible = true
		var ang := float(i) * 0.9
		t.position = Vector3(cos(ang) * 4.0, FLY_Y, -4.0 + sin(ang) * 4.0)
		if t.marker != null:
			t.marker.visible = true
			t.marker.global_position = Vector3(t.position.x, MARK_Y, t.position.z)
			t.marker.scale = Vector3.ONE * 0.8
			t.marker_mat.albedo_color.a = 0.3
		i += 1
	for g in _groups:
		g.arrow.visible = true
		g.arrow_mat.albedo_color = Color(1.0, 0.35, 0.1, 0.6)
		g.arrow.position = Vector3(-3.0 + 2.0 * _groups.find(g), MARK_Y, 3.0)
	for mi in _tracers:
		mi.visible = true
		mi.position = Vector3(0, FLY_Y, -2)

func prewarm_hide() -> void:
	_prewarm = false
	hide_all()
