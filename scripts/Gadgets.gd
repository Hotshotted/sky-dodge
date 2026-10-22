class_name Gadgets
extends Node3D
## The ACTIVE, visible perks that are not guns: the gear on and around the plane. Each level changes what you see.
##   WINGMAN       a small drone beside the plane (two at level 3): it collects nearby coins and cans, takes one hit for you,
##                 then recharges (dimmed while it does)
##   PROP WASH     a shockwave ring every few seconds that shoves obstacles and threats aside (bigger and sooner per level)
##   TOW BANNER    a banner trailing the plane that collects the coins along its length
##   SKYWRITER     a smoke trail that scatters birds and kites flying into it (longer, thicker per level)
##   MAGNET FIELD  an aura that pulls coins and cans in (wider per level)
##   BARREL ROLL   double-tap for a short invulnerable roll (the cooldown shortens per level)
## Pooled like everything else: every node is built once in _ready and only shown / moved. Main does the collecting and the
## paying (so the score and the sounds stay in one place); this class owns the state and the visuals.

signal wash_fired(pos: Vector3, radius: float)
signal wingman_absorbed(pos: Vector3)
signal wingman_ready(index: int)
signal roll_started
signal roll_ended
signal roll_ready
signal scattered(pos: Vector3)

const WINGMEN := 2
const SMOKE_POOL := 48
const SMOKE_EVERY := 0.1             # seconds between puffs
const Y := 1.0

var spawner: Node3D                  # Spawner (the kit and the threats live there)
var picks                            # Perks: the levels
var combo_shock_awe := false         # Prop Wash also hurts threats
var combo_smokescreen := false       # the smoke hurts every kind of threat

var _wm: Array[Node3D] = []
var _wm_rotors: Array[Array] = []
var _wm_mats: Array[StandardMaterial3D] = []
var _wm_pos: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _wm_charge: Array[float] = [0.0, 0.0]     # seconds until the wingman can take a hit again (0 = ready)
var _wash_ring: MeshInstance3D
var _wash_mat: StandardMaterial3D
var _wash_t := -1.0                  # seconds since the ring was fired (-1 = idle)
var _wash_radius := 4.0
var _wash_cd := 0.0
var _banner: Node3D
var _banner_cloth: MeshInstance3D
var _banner_sway := 0.0
var _banner_len := 3.5
var _banner_caps := PackedFloat32Array([0.0, 1.4, 0.0, 4.9, 0.5])
var _smoke: Array[MeshInstance3D] = []
var _smoke_mat: StandardMaterial3D
var _sx := PackedFloat32Array()
var _sz := PackedFloat32Array()
var _sage := PackedFloat32Array()
var _sn := 0
var _smoke_t := 0.0
var _aura: MeshInstance3D
var _aura_mat: StandardMaterial3D
var _aura_ring: MeshInstance3D
var _clock := 0.0
var roll_cd := 0.0                   # seconds until the next roll (0 = ready)
var roll_t := 0.0                    # seconds of roll left
var wingman_hits := 0                # hits the wingmen took this run
var scatters := 0                    # birds / kites the smoke brought down this run
var washes := 0
var rolls := 0
var _scatter_buf: Array[Vector2] = []
var _tmp_caps := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 1.3])

func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	for i in WINGMEN:
		var root := Node3D.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.85, 1.0)
		mat.roughness = 1.0
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.8, 1.0)
		mat.emission_energy_multiplier = 0.5
		_wm_mats.append(mat)
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.22, 0.6)
		body.mesh = bm
		body.material_override = mat
		root.add_child(body)
		var eye := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(0.2, 0.12, 0.2)
		eye.mesh = em
		eye.material_override = _plain(Color(0.1, 0.12, 0.2))
		eye.position = Vector3(0, 0.14, -0.12)
		root.add_child(eye)
		var rotors: Array[Node3D] = []
		for sx in [-1.0, 1.0]:
			var r := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(0.7, 0.03, 0.1)
			r.mesh = rm
			r.material_override = _plain(Color(0.85, 0.9, 1.0))
			r.position = Vector3(sx * 0.42, 0.18, 0.0)
			root.add_child(r)
			rotors.append(r)
		_wm_rotors.append(rotors)
		root.visible = false
		add_child(root)
		_wm.append(root)
	_wash_mat = _flat(Color(0.7, 1.0, 0.85, 0.0))
	_wash_ring = MeshInstance3D.new()
	_wash_ring.mesh = _ring_mesh()
	_wash_ring.material_override = _wash_mat
	_wash_ring.top_level = true
	_wash_ring.visible = false
	add_child(_wash_ring)
	_banner = Node3D.new()
	_banner.visible = false
	add_child(_banner)
	_banner_cloth = MeshInstance3D.new()
	_banner_cloth.mesh = box
	_banner_cloth.material_override = _plain(Color(1.0, 0.6, 0.25))
	_banner.add_child(_banner_cloth)
	var stripe := MeshInstance3D.new()
	stripe.mesh = box
	stripe.material_override = _plain(Color(1.0, 0.95, 0.85))
	stripe.scale = Vector3(0.3, 0.06, 0.9)
	stripe.position = Vector3(0, 0.03, 0.0)
	_banner_cloth.add_child(stripe)
	_smoke_mat = _flat(Color(0.92, 0.94, 1.0, 0.55))
	for i in SMOKE_POOL:
		var p := MeshInstance3D.new()
		p.mesh = box
		p.material_override = _smoke_mat
		p.visible = false
		add_child(p)
		_smoke.append(p)
	_sx.resize(SMOKE_POOL)
	_sz.resize(SMOKE_POOL)
	_sage.resize(SMOKE_POOL)
	_aura_mat = _flat(Color(0.8, 0.5, 1.0, 0.16))
	_aura = MeshInstance3D.new()
	_aura.mesh = _disc_mesh()
	_aura.material_override = _aura_mat
	_aura.top_level = true
	_aura.visible = false
	add_child(_aura)
	_aura_ring = MeshInstance3D.new()
	_aura_ring.mesh = _ring_mesh()
	_aura_ring.material_override = _aura_mat
	_aura_ring.top_level = true
	_aura_ring.visible = false
	add_child(_aura_ring)

func _plain(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m

func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 2
	return m

func _disc_mesh() -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 1.0
	m.bottom_radius = 1.0
	m.height = 0.02
	m.radial_segments = 28
	m.rings = 1
	return m

func _ring_mesh() -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = 0.93
	m.outer_radius = 1.0
	m.rings = 28
	m.ring_segments = 4
	return m

func level(id: String) -> int:
	return picks.level(id) if picks != null else 0

## A fresh run.
func reset() -> void:
	for i in WINGMEN:
		_wm_charge[i] = 0.0
		_wm[i].visible = false
	_wash_t = -1.0
	_wash_cd = 1.5
	_wash_ring.visible = false
	_banner.visible = false
	_sn = 0
	_smoke_t = 0.0
	for p in _smoke:
		p.visible = false
	_aura.visible = false
	_aura_ring.visible = false
	roll_cd = 0.0
	roll_t = 0.0
	wingman_hits = 0
	scatters = 0
	washes = 0
	rolls = 0
	_banner_sway = 0.0
	_clock = 0.0

func wingman_count() -> int:
	var l := level("wingman")
	return 0 if l <= 0 else (2 if l >= 3 else 1)

func wingman_pos(i: int) -> Vector2:
	return _wm_pos[i]

func wingman_ready_count() -> int:
	var n := 0
	for i in wingman_count():
		n += 1 if _wm_charge[i] <= 0.0 else 0
	return n

## A hit comes: a ready wingman takes it (and recharges). Returns whether one did.
func absorb_hit() -> bool:
	for i in wingman_count():
		if _wm_charge[i] <= 0.0:
			_wm_charge[i] = Tuning.perk_value("wingman", level("wingman"))
			wingman_hits += 1
			wingman_absorbed.emit(Vector3(_wm_pos[i].x, Y, _wm_pos[i].y))
			return true
	return false

## The banner's shape for coin collection: capsules relative to the plane (Coins.collect).
func banner_caps() -> PackedFloat32Array:
	return _banner_caps

func banner_length() -> float:
	return Tuning.perk_value("banner", level("banner"))

func aura_radius() -> float:
	return Tuning.perk_value("magnet_field", level("magnet_field"))

func rolling() -> bool:
	return roll_t > 0.0

## Double-tap: roll if the perk is held and ready.
func try_roll() -> bool:
	if level("roll") <= 0 or roll_cd > 0.0 or roll_t > 0.0:
		return false
	roll_t = Tuning.roll_time
	roll_cd = Tuning.perk_value("roll", level("roll"))
	rolls += 1
	roll_started.emit()
	return true

## Every frame of a run. `plane` = the plane's position, `vel_x` its sideways speed, `step` the distance the world scrolled.
func step(delta: float, plane: Vector3, vel_x: float, step_dist: float) -> void:
	_clock += delta
	var px := plane.x
	var pz := plane.z
	_step_wingmen(delta, px, pz)
	_step_wash(delta, px, pz)
	_step_banner(delta, px, pz, vel_x)
	_step_smoke(delta, px, pz, step_dist)
	_step_aura(px, pz)
	if roll_t > 0.0:
		roll_t = maxf(roll_t - delta, 0.0)
		if roll_t <= 0.0:
			roll_ended.emit()
	if roll_cd > 0.0:
		roll_cd = maxf(roll_cd - delta, 0.0)
		if roll_cd <= 0.0 and level("roll") > 0:
			roll_ready.emit()

func _step_wingmen(delta: float, px: float, pz: float) -> void:
	var n := wingman_count()
	for i in WINGMEN:
		var on := i < n
		_wm[i].visible = on
		if not on:
			continue
		var side := -1.0 if i == 0 else 1.0
		if n == 1:
			side = 1.0 if px < 0.0 else -1.0   # a lone wingman keeps to the roomier side
		var goal := Vector2(px + side * Tuning.wingman_offset, pz + 0.7 + 0.15 * sin(_clock * 2.0 + i))
		goal.x = clampf(goal.x, -5.4, 5.4)
		_wm_pos[i] = _wm_pos[i].lerp(goal, 1.0 - exp(-7.0 * delta))
		if _wm_pos[i] == Vector2.ZERO:
			_wm_pos[i] = goal
		_wm[i].position = Vector3(_wm_pos[i].x, Y, _wm_pos[i].y)
		_wm[i].rotation.z = clampf((goal.x - _wm_pos[i].x) * -0.3, -0.4, 0.4)
		if _wm_charge[i] > 0.0:
			_wm_charge[i] = maxf(_wm_charge[i] - delta, 0.0)
			if _wm_charge[i] <= 0.0:
				wingman_ready.emit(i)
		var ready := _wm_charge[i] <= 0.0
		_wm_mats[i].albedo_color = Color(0.55, 0.85, 1.0) if ready else Color(0.35, 0.4, 0.5)
		_wm_mats[i].emission_energy_multiplier = 0.6 if ready else 0.0
		_wm[i].scale = Vector3.ONE * (1.0 if ready else 0.8)
		for r in _wm_rotors[i]:
			(r as Node3D).rotation.y += delta * (40.0 if ready else 6.0)
		if roll_t > 0.0 and combo_wing_roll:
			_wm[i].rotation.z = TAU * (1.0 - roll_t / Tuning.roll_time)

var combo_wing_roll := false

func _step_wash(delta: float, px: float, pz: float) -> void:
	var l := level("shockwave")
	if l <= 0:
		_wash_ring.visible = false
		_wash_t = -1.0
		return
	_wash_radius = Tuning.wash_radius[l - 1]
	if _wash_t < 0.0:
		_wash_cd -= delta
		if _wash_cd <= 0.0:
			_wash_cd = Tuning.perk_value("shockwave", l)
			_wash_t = 0.0
			washes += 1
			var c := Vector2(px, pz)
			if spawner != null:
				spawner.kit.shove(c, _wash_radius, Tuning.wash_shove)
				spawner.shove_rows(c, _wash_radius)
				spawner.threats.push(c, _wash_radius, Tuning.wash_push, 1.0 if combo_shock_awe else 0.0)
			wash_fired.emit(Vector3(px, Y, pz), _wash_radius)
	if _wash_t >= 0.0:
		_wash_t += delta
		var k := clampf(_wash_t / 0.55, 0.0, 1.0)
		var e := 1.0 - (1.0 - k) * (1.0 - k)
		_wash_ring.visible = true
		_wash_ring.global_position = Vector3(px, 0.12, pz)
		_wash_ring.scale = Vector3.ONE * maxf(_wash_radius * e, 0.3)
		_wash_mat.albedo_color = Color(0.7, 1.0, 0.85, 0.75 * (1.0 - k))
		if k >= 1.0:
			_wash_t = -1.0
			_wash_ring.visible = false

func _step_banner(delta: float, px: float, pz: float, vel_x: float) -> void:
	var l := level("banner")
	_banner.visible = l > 0
	if l <= 0:
		return
	_banner_len = banner_length()
	_banner_sway = lerpf(_banner_sway, clampf(-vel_x * 0.12, -1.6, 1.6), 1.0 - exp(-6.0 * delta))
	var wave := sin(_clock * 5.0) * 0.12
	var ang := atan2(_banner_sway + wave, _banner_len)
	_banner.position = Vector3(px, Y - 0.05, pz + 1.3)
	_banner.rotation.y = -ang
	_banner_cloth.scale = Vector3(0.9 + 0.15 * l, 0.05, _banner_len)
	_banner_cloth.position = Vector3(0, 0, _banner_len * 0.5)
	# the coin net: from the tow point to the banner's end, in the plane's frame
	var ex := sin(ang) * _banner_len
	var ez := cos(ang) * _banner_len
	_banner_caps[0] = 0.0
	_banner_caps[1] = 1.3
	_banner_caps[2] = ex
	_banner_caps[3] = 1.3 + ez
	_banner_caps[4] = Tuning.banner_width

func _step_smoke(delta: float, px: float, pz: float, step_dist: float) -> void:
	var l := level("skywriter")
	if l <= 0:
		if _sn > 0:
			_sn = 0
			for p in _smoke:
				p.visible = false
		return
	var length := Tuning.perk_value("skywriter", l)
	var puff: float = Tuning.skywriter_puff[l - 1]
	# the smoke stays where it was laid: it scrolls with the world
	for i in _sn:
		_sz[i] += step_dist
		_sage[i] += delta
	_smoke_t -= delta
	if _smoke_t <= 0.0:
		_smoke_t = SMOKE_EVERY
		if _sn >= SMOKE_POOL:   # the oldest goes
			for i in range(1, _sn):
				_sx[i - 1] = _sx[i]
				_sz[i - 1] = _sz[i]
				_sage[i - 1] = _sage[i]
			_sn -= 1
		_sx[_sn] = px
		_sz[_sn] = pz + 1.2
		_sage[_sn] = 0.0
		_sn += 1
	# drop what is beyond the trail's length
	var drop := 0
	while drop < _sn and _sz[drop] - (pz + 1.2) > length:
		drop += 1
	if drop > 0:
		for i in range(drop, _sn):
			_sx[i - drop] = _sx[i]
			_sz[i - drop] = _sz[i]
			_sage[i - drop] = _sage[i]
		_sn -= drop
	var kit_on: bool = spawner != null and spawner.kit_on
	for i in SMOKE_POOL:
		var p := _smoke[i]
		if i < _sn:
			var age := _sage[i]
			var fade := clampf(1.0 - (_sz[i] - (pz + 1.2)) / length, 0.0, 1.0)
			var s := puff * (0.7 + 0.5 * clampf(age * 2.0, 0.0, 1.0))
			p.visible = true
			p.position = Vector3(_sx[i] + sin(age * 4.0 + float(i)) * 0.08, Y - 0.1, _sz[i])
			p.scale = Vector3(s, 0.12, s)
			p.rotation.y = float(i) * 0.7
			if i == 0:
				_smoke_mat.albedo_color.a = 0.5 + 0.1 * l
			p.scale.y = 0.08 + 0.1 * fade
		else:
			p.visible = false
	if spawner == null:
		return
	# birds and kites that fly into it are scattered (every other puff is enough to catch them)
	var r: float = Tuning.skywriter_radius * (1.0 + 0.2 * (l - 1))
	for i in range(0, _sn, 2):
		var pt := Vector2(_sx[i], _sz[i])
		if kit_on:
			_scatter_buf.clear()
			spawner.kit.scatter_near(pt, r, _scatter_buf)
			for q in _scatter_buf:
				scatters += 1
				scattered.emit(Vector3(q.x, Y, q.y))
		var hit: int = spawner.threats.smoke_hit(pt, r, combo_smokescreen)
		scatters += hit

func _step_aura(px: float, pz: float) -> void:
	var l := level("magnet_field")
	_aura.visible = l > 0
	_aura_ring.visible = l > 0
	if l <= 0:
		return
	var r := aura_radius()
	var pulse := 0.5 + 0.5 * sin(_clock * 3.0)
	_aura.global_position = Vector3(px, 0.1, pz)
	_aura.scale = Vector3(r, 1.0, r)
	_aura_ring.global_position = Vector3(px, 0.11, pz)
	_aura_ring.scale = Vector3.ONE * (r * (0.93 + 0.07 * pulse))
	_aura_mat.albedo_color = Color(0.8, 0.5, 1.0, 0.1 + 0.05 * l + 0.05 * pulse)

## Pre-warm: draw all of it once.
func prewarm_show() -> void:
	for i in WINGMEN:
		_wm[i].visible = true
		_wm[i].position = Vector3(-2.0 + 4.0 * i, Y, 3.0)
	_wash_ring.visible = true
	_wash_ring.global_position = Vector3(0, 0.12, 0)
	_wash_ring.scale = Vector3.ONE * 3.0
	_wash_mat.albedo_color = Color(0.7, 1.0, 0.85, 0.5)
	_banner.visible = true
	_banner.position = Vector3(0, Y, 4.0)
	_banner_cloth.scale = Vector3(1.0, 0.05, 4.0)
	_banner_cloth.position = Vector3(0, 0, 2.0)
	for i in SMOKE_POOL:
		_smoke[i].visible = true
		_smoke[i].position = Vector3(-3.0 + 6.0 * float(i % 12) / 11.0, Y - 0.1, 1.0 + float(i / 12))
		_smoke[i].scale = Vector3(0.8, 0.1, 0.8)
	_aura.visible = true
	_aura_ring.visible = true
	_aura.global_position = Vector3(0, 0.1, 0)
	_aura.scale = Vector3(3.0, 1.0, 3.0)
	_aura_ring.global_position = Vector3(0, 0.11, 0)
	_aura_ring.scale = Vector3.ONE * 3.0

func prewarm_hide() -> void:
	reset()
