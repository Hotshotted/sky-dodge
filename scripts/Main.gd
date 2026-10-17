extends Node3D
## Game loop: scroll speed, score, collision, camera, restart.

@onready var player: Node3D = $Player
@onready var spawner: Node3D = $Spawner
@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var hud: CanvasLayer = $Hud

const REASON_OBSTACLE := "Hit an obstacle"  # end reasons, shown on the game-over screen
const REASON_FUEL := "Out of fuel"

var score := 0.0        # accumulates distance flown x multiplier
var multiplier := 1     # raised by near misses, decays back to 1
var fuel := 0.0         # drains steadily; fuel cans refill it; empty ends the run
var _mult_timer := 0.0  # counts down to the next multiplier decay step
var _warming := false
static var _haptic_warmed := false  # first-touch haptic warm-up done (once per app session)
static var _warmed := false  # pre-warm only once per app session
var elapsed := 0.0      # run time, drives the speed ramp
var alive := true
var _death_time := 0.0
var fx := Fx.new()
var trail := Trail.new()

func _ready() -> void:
	fuel = Tuning.fuel_start
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
		if DebugFlags.prewarm_enabled():
			_prewarm()

## First-use stutter fix: GL shaders / particle buffers / font glyphs set themselves up the first
## time they are used (and mobile browsers may compile shaders in the background). So at boot,
## behind a splash screen, draw EVERY near-miss effect for real (on screen, in view, nothing hidden
## or off-screen) and KEEP drawing until frame times settle (see Tuning.prewarm_*): both spark
## emitters, every pooled streak, every pooled obstacle cube and outline (some white), a
## full-length trail ribbon, every popup tier at every font size and the multiplier punch. (The
## haptic call can't be warmed at boot: browsers only allow it after a touch, see _input.)
## Then hide it all. The game doesn't tick meanwhile. Everything stays alive for the whole app
## session (restarts don't reload the scene), so this only ever runs once. Skip with ?noprewarm;
## effects switched off with ?nofx= are not warmed either.
func _prewarm() -> void:
	_warming = true
	var spot := Vector3(0.0, 1.2, 1.0)
	hud.begin_prewarm(not DebugFlags.off("popup"))
	spawner.prewarm_show(not DebugFlags.off("flash"))
	if not DebugFlags.off("punch"):
		hud.set_multiplier(2, true)
	var t_start := Time.get_ticks_msec()
	var t_last := t_start
	var t_refresh := -100000
	var calm_frames := 0
	while true:
		var now := Time.get_ticks_msec()
		# Re-trigger the short-lived effects so something is always on screen.
		if now - t_refresh > 350:
			t_refresh = now
			if not DebugFlags.off("sparks"):
				fx.sparks(spot + Vector3(-1.5, 0, 0), -1)  # round-robin: warms both emitters
				fx.sparks(spot + Vector3(1.5, 0, 0), 1)
			if not DebugFlags.off("popup"):
				hud.prewarm_popups()
			if not DebugFlags.off("pickup"):
				fx.pickup(spot + Vector3(-1.0, 0, -1.5))   # round-robin: warms both pickup emitters
				fx.pickup(spot + Vector3(1.0, 0, -1.5))
				hud.fuel_pulse()
		if not DebugFlags.off("streaks"):
			fx.show_all_streaks(spot)
		if not DebugFlags.off("trail"):
			trail.fill_for_prewarm(Vector2(spot.x, spot.z))  # full-length ribbon: alpha, vertex colours, big buffers
		await get_tree().process_frame
		# Stop once it has run long enough AND frames have been calm for a while (or at the cap).
		var t := Time.get_ticks_msec()
		calm_frames = calm_frames + 1 if (t - t_last) < Tuning.prewarm_stable_ms else 0
		t_last = t
		var elapsed_s := (t - t_start) / 1000.0
		if elapsed_s >= Tuning.prewarm_max_seconds:
			break
		if elapsed_s >= Tuning.prewarm_min_seconds and calm_frames >= Tuning.prewarm_stable_frames:
			break
	fx.clear()
	trail.clear()
	spawner.prewarm_hide()
	hud.set_multiplier(1, false)
	hud.end_prewarm()
	_warming = false

## Start a fresh run IN PLACE. Nothing is reloaded, created or freed: every pooled effect,
## material and UI node stays alive (and warm) across runs; only the game state is reset.
func restart() -> void:
	score = 0.0
	multiplier = 1
	_mult_timer = 0.0
	elapsed = 0.0
	alive = true
	fuel = Tuning.fuel_start
	spawner.reset()
	fx.clear()
	trail.clear()
	hud.reset_for_run()
	player.reset()
	_update_plane_zone()

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
	trail.advance(step, Vector2(plane.x, plane.y + 0.9), 1 if DebugFlags.off("trail") else multiplier, delta)
	_decay_multiplier(delta)

	var caps: PackedFloat32Array = player.hit_capsules()
	if spawner.hits(plane, caps):
		_end_run(REASON_OBSTACLE)
		return

	for ev in spawner.update_near_misses(plane, caps):
		_on_near_miss(ev)

	# Fuel: burn it, then pick up any cans touched (a can grabbed in the last moment still saves you).
	fuel = maxf(fuel - Tuning.fuel_drain * delta, 0.0)
	for pos in spawner.collect_cans(plane, caps):
		_on_pickup(pos)
	hud.set_fuel(fuel / Tuning.fuel_start)
	if fuel <= 0.0:
		_end_run(REASON_FUEL)

## End the run: freeze the plane and show the game-over screen with what ended it.
func _end_run(reason: String) -> void:
	alive = false
	_death_time = Time.get_ticks_msec() / 1000.0
	player.crash()
	hud.show_game_over(int(score), reason)

## A fuel can was collected at `pos`: refill (never past a full tank) and pop.
func _on_pickup(pos: Vector3) -> void:
	fuel = minf(fuel + Tuning.fuel_refill, Tuning.fuel_start)
	if not DebugFlags.off("pickup"):
		fx.pickup(pos)
		hud.fuel_pulse()
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(15)

## Near miss: raise the multiplier and fire every bit of feedback at once. Each effect can be
## switched off from the URL (?nofx=sparks,streaks,flash,popup,trail,haptic,punch) to find out
## which one causes a hitch.
func _on_near_miss(ev: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	multiplier = mini(multiplier + 1, Tuning.multiplier_max)
	_mult_timer = Tuning.multiplier_hold_time
	hud.set_multiplier(multiplier, not DebugFlags.off("punch"))
	var side: int = ev["side"]
	if not DebugFlags.off("sparks"):
		fx.sparks(player.position + Vector3(side * 1.05, 0.0, 0.1), side)  # wingtip nearest the obstacle
	if not DebugFlags.off("streaks"):
		fx.streaks(player.position)
	if not DebugFlags.off("flash"):
		spawner.flash_obstacle(ev["outline"])
	if not DebugFlags.off("popup"):
		var n := Tuning.near_miss_texts.size()
		var i := Tuning.tier_index(multiplier, n)
		var pos := camera.unproject_position(player.position + Vector3(0, 0, -2.0))
		hud.popup(Tuning.near_miss_texts[i], Tuning.near_miss_sizes[mini(i, Tuning.near_miss_sizes.size() - 1)],
				Tuning.near_miss_colors[mini(i, Tuning.near_miss_colors.size() - 1)], pos)
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(Tuning.haptic_ms)  # no-op where unsupported
	hud.note_near_miss((Time.get_ticks_usec() - t0) / 1000.0)

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
	# Browsers only allow vibration after a touch, and the first real call connects to the device's
	# vibration service. A zero-length call is just a "cancel" and does NOT connect, so make an
	# imperceptible 1 ms pulse on the very first touch instead of on the first near miss.
	if not _haptic_warmed and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		_haptic_warmed = true
		if not DebugFlags.off("haptic"):
			Input.vibrate_handheld(1)
	# Tap to restart (small delay so the crash-causing drag can't restart instantly).
	if not alive and event is InputEventScreenTouch and event.pressed \
			and Time.get_ticks_msec() / 1000.0 - _death_time > 0.5:
		restart()

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
