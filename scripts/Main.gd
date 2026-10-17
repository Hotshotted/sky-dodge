extends Node3D
## Game loop: scroll speed, score, collision, camera, restart.

@onready var player: Node3D = $Player
@onready var spawner: Node3D = $Spawner
@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var hud: CanvasLayer = $Hud

var score := 0.0        # accumulates distance flown x multiplier
var multiplier := 1     # raised by near misses, decays back to 1
var _mult_timer := 0.0  # counts down to the next multiplier decay step
var _warming := false
static var _warmed := false  # pre-warm only once per app session (survives scene reloads)
var elapsed := 0.0      # run time, drives the speed ramp
var alive := true
var _death_time := 0.0
var fx := Fx.new()
var trail := Trail.new()

func _ready() -> void:
	add_child(fx)
	add_child(trail)
	_setup_environment()
	# Light from above (the camera mostly sees top faces).
	sun.look_at_from_position(Vector3.ZERO, Tuning.light_direction)
	sun.shadow_enabled = false
	# Straight-down orthographic camera, width locked so all columns always fit.
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = Tuning.ortho_size
	camera.near = 0.1
	camera.far = 100.0
	_update_camera()
	_update_plane_zone()
	if not _warmed:
		_warmed = true
		_prewarm()

## First-use stutter fix: GL shaders / particle materials / font glyphs compile the first time
## they are drawn. Draw every effect once, in view but under a black cover, for a few frames
## at startup, then remove it all. The game doesn't tick meanwhile.
func _prewarm() -> void:
	_warming = true
	var spot := Vector3(0.0, 1.2, 1.0)
	hud.begin_prewarm()
	var temps: Array = spawner.prewarm_nodes()
	fx.sparks(spot, 1)
	fx.streaks(spot)
	for i in 4:
		trail.advance(0.3, Vector2(spot.x, spot.z), 2, 0.1)  # builds a ribbon (alpha, vertex colour)
		await get_tree().process_frame
	fx.clear()
	trail.clear()
	for n in temps:
		n.queue_free()
	hud.end_prewarm()
	_warming = false

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_update_camera()
	_update_plane_zone()
	if _warming or not alive:
		return

	elapsed += delta
	var speed := minf(Tuning.base_speed + Tuning.speed_ramp * elapsed, Tuning.max_speed)
	var step := speed * delta
	score += step * (multiplier if Tuning.score_uses_multiplier else 1)
	spawner.advance(step)
	hud.set_score(int(score))
	var plane := Vector2(player.position.x, player.position.z)
	trail.advance(step, Vector2(plane.x, plane.y + 0.9), multiplier, delta)
	_decay_multiplier(delta)

	var boxes: Array[Vector4] = player.hit_boxes()
	if spawner.hits(plane, boxes):
		alive = false
		_death_time = Time.get_ticks_msec() / 1000.0
		player.crash()
		hud.show_game_over(int(score))
		return

	for ev in spawner.update_near_misses(plane, boxes):
		_on_near_miss(ev)

## Near miss: raise the multiplier and fire every bit of feedback at once.
func _on_near_miss(ev: Dictionary) -> void:
	multiplier = mini(multiplier + 1, Tuning.multiplier_max)
	_mult_timer = Tuning.multiplier_hold_time
	hud.set_multiplier(multiplier, true)
	var side: int = ev["side"]
	fx.sparks(player.position + Vector3(side * 1.05, 0.0, 0.1), side)  # wingtip nearest the obstacle
	fx.streaks(player.position)
	spawner.flash_obstacle(ev["outline"])
	var n := Tuning.near_miss_texts.size()
	var i := Tuning.tier_index(multiplier, n)
	var pos := camera.unproject_position(player.position + Vector3(0, 0, -2.0))
	hud.popup(Tuning.near_miss_texts[i], Tuning.near_miss_sizes[mini(i, Tuning.near_miss_sizes.size() - 1)],
			Tuning.near_miss_colors[mini(i, Tuning.near_miss_colors.size() - 1)], pos)
	Input.vibrate_handheld(Tuning.haptic_ms)  # no-op where unsupported

## Without fresh near misses the multiplier holds, then drops one step at a time down to 1x.
func _decay_multiplier(delta: float) -> void:
	if multiplier <= 1:
		return
	_mult_timer -= delta
	if _mult_timer <= 0.0:
		multiplier -= 1
		_mult_timer = Tuning.multiplier_decay_step
		hud.set_multiplier(multiplier, false)

## Camera tilted `camera_tilt_deg` away from straight down (so front faces show), placed so the
## screen centre always looks at world z = 0. Screen-up = world -Z.
func _update_camera() -> void:
	var tilt := deg_to_rad(Tuning.camera_tilt_deg)
	camera.size = Tuning.ortho_size
	camera.position = Vector3(0, cos(tilt), sin(tilt)) * 30.0
	camera.rotation = Vector3(-(PI / 2 - tilt), 0, 0)

## The plane may use the bottom `plane_zone_fraction` of the screen. The visible height
## depends on the device aspect (width is fixed), so work it out from the viewport.
func _update_plane_zone() -> void:
	var vp := get_viewport().get_visible_rect().size
	# Screen spans z = -half_h .. +half_h (stretched slightly by the camera tilt).
	var half_h := Tuning.ortho_size * 0.5 * vp.y / vp.x / cos(deg_to_rad(Tuning.camera_tilt_deg))
	var bottom := half_h - Tuning.plane_bottom_margin
	var top := half_h - 2.0 * half_h * Tuning.plane_zone_fraction
	player.set_zone(top, bottom)

func _input(event: InputEvent) -> void:
	# Tap to restart (small delay so the crash-causing drag can't restart instantly).
	if not alive and event is InputEventScreenTouch and event.pressed \
			and Time.get_ticks_msec() / 1000.0 - _death_time > 0.5:
		get_tree().reload_current_scene()

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.26, 0.34)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.9)
	env.ambient_light_energy = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
