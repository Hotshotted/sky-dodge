class_name Main
extends Node3D
## Game loop: scroll speed, score, collision, camera, restart.

@onready var player: Node3D = $Player
@onready var spawner: Node3D = $Spawner
@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var hud: CanvasLayer = $Hud

## What ends a run, shown on the game-over screen as a big header plus a line under it.
## The plane's path each frame is tested in steps no longer than this (units), so a flick can't
## tunnel through an obstacle or skip a can (the thinnest thing it must not skip is ~1.3 wide).
const SWEEP_STEP := 0.4
const MAX_SWEEP_STEPS := 80
const HEADER_CRASH := "CRASHED"
const REASON_OBSTACLE := "Hit an obstacle"
const HEADER_FUEL := "OUT OF FUEL"
const REASON_FUEL := "The tank ran dry"

## Which screen is up. A run is only on while screen == SCREEN_PLAY and alive.
enum { SCREEN_MENU, SCREEN_HANGAR, SCREEN_PLAY, SCREEN_OVER }
var screen := SCREEN_MENU
var run_cans := 0       # fuel cans collected this run (they pay coins at the end)
var last_earned := 0    # coins the last run paid
var last_was_best := false
var score := 0.0        # accumulates distance flown x bonus
var streak := 0     # close calls in the current streak (steps come off one at a time after the hold time)
var bonus := 1.0    # points bonus from the streak, 1.0 = none
var fuel := 0.0         # drains steadily; fuel cans refill it; empty ends the run
var _bonus_timer := 0.0  # counts down to the streak starting to drop
var _decay_acc := 0.0   # fractional steps accumulated towards the next one coming off
var _warming := false
static var _haptic_warmed := false  # first-touch haptic warm-up done (once per app session)
static var _warmed := false  # pre-warm only once per app session
var elapsed := 0.0      # run time, drives the speed ramp
var alive := true
var _death_time := 0.0
var fx := Fx.new()
var trail := Trail.new()
var tune_panel: TunePanel   # only exists when the URL has ?tune

func _ready() -> void:
	fuel = Tuning.fuel_max()
	add_child(fx)
	add_child(trail)
	if DebugFlags.tune_enabled():
		tune_panel = TunePanel.new()
		add_child(tune_panel)
		tune_panel.build()
		tune_panel.changed.connect(_on_tuning_changed)
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
	spawner.reset(_first_row_z(_half_height()))
	if not _warmed:
		_warmed = true
		if DebugFlags.prewarm_enabled():
			_prewarm()
	hud.play_pressed.connect(restart)
	hud.hangar_pressed.connect(_open_hangar)
	hud.back_pressed.connect(_show_menu)
	hud.upgrade_pressed.connect(_buy)
	if not _warming:
		_show_menu()
	if not _warming and tune_panel:
		tune_panel.set_available(true)

## First-use stutter fix: GL shaders / particle buffers / font glyphs set themselves up the first
## time they are used (and mobile browsers may compile shaders in the background). So at boot,
## behind a splash screen, draw EVERY near-miss effect for real (on screen, in view, nothing hidden
## or off-screen) and KEEP drawing until frame times settle (see Tuning.prewarm_*): both spark
## emitters, every pooled streak, every pooled obstacle cube and outline (some white), a
## full-length trail ribbon, every popup tier at every font size and the bonus punch. (The
## haptic call can't be warmed at boot: browsers only allow it after a touch, see _input.)
## Then hide it all. The game doesn't tick meanwhile. Everything stays alive for the whole app
## session (restarts don't reload the scene), so this only ever runs once. Skip with ?noprewarm;
## effects switched off with ?nofx= are not warmed either.
func _prewarm() -> void:
	_warming = true
	var spot := Vector3(0.0, 1.2, 1.0)
	hud.begin_prewarm(not DebugFlags.off("popup"))
	spawner.prewarm_show(not DebugFlags.off("flash"), not DebugFlags.off("clouds"))
	if tune_panel:
		tune_panel.prewarm_show(true)   # drawn under the splash like everything else
	if not DebugFlags.off("punch"):
		hud.set_bonus(Tuning.bonus_cap, hud.BONUS_PUNCH)   # (the capped, gold label too)
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
	hud.clear_bonus()
	hud.end_prewarm()
	if tune_panel:
		tune_panel.prewarm_show(false)
		tune_panel.set_available(true)
	_warming = false
	_show_menu()

## Start a fresh run IN PLACE. Nothing is reloaded, created or freed: every pooled effect,
## material and UI node stays alive (and warm) across runs; only the game state is reset.
func restart() -> void:
	screen = SCREEN_PLAY
	run_cans = 0
	score = 0.0
	_reset_bonus()
	elapsed = 0.0
	alive = true
	spawner.run_time = 0.0
	fuel = Tuning.fuel_max()
	fx.clear()
	trail.clear()
	hud.reset_for_run()
	player.reset()
	_update_plane_zone()
	spawner.reset(_first_row_z(_half_height()))   # after the plane is back: the opening is timed to reach it

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_update_camera()
	_update_plane_zone()
	if _warming or not alive:
		return

	elapsed += delta
	player.step(delta)   # 1:1 finger movement this frame (the path from prev_xz to here is swept below)
	var speed := minf(Tuning.base_speed + Tuning.speed_ramp * elapsed, Tuning.max_speed)
	var step := speed * delta
	score += step * (bonus if Tuning.score_uses_bonus else 1)
	spawner.plane_z = player.position.z   # clouds fade as they near the plane,
	spawner.run_time = elapsed            # start late in the run,
	spawner.scroll_speed = speed          # and come more often the faster it goes
	spawner.advance(step)
	hud.set_score(int(score), bonus)
	var plane := Vector2(player.position.x, player.position.z)
	trail.advance(step, Vector2(plane.x, plane.y + 0.9), 1 if DebugFlags.off("trail") else bonus, delta)
	_decay_bonus(delta)
	fuel = maxf(fuel - Tuning.drain_rate() * delta, 0.0)

	# Swept collision: the plane can move any distance in one frame (a fast flick), so test the whole
	# path from where it was to where it is, in small steps, instead of only the end point. Obstacles,
	# near misses and fuel cans are all checked along the way, and a crash stops the plane where it
	# first touched.
	var caps: PackedFloat32Array = player.hit_capsules()
	var from: Vector2 = player.prev_xz
	var steps := clampi(ceili(from.distance_to(plane) / SWEEP_STEP), 1, MAX_SWEEP_STEPS)
	for i in range(1, steps + 1):
		var p: Vector2 = from.lerp(plane, float(i) / steps)
		if spawner.hits(p, caps):
			# Found the step that hit: narrow it down to the exact first touch, so a fast flick
			# stops AT the obstacle instead of up to a sweep step inside it.
			var lo: Vector2 = from.lerp(plane, float(i - 1) / steps)
			var hi := p
			for k in 8:
				var mid := lo.lerp(hi, 0.5)
				if spawner.hits(mid, caps):
					hi = mid
				else:
					lo = mid
			player.position = Vector3(hi.x, player.position.y, hi.y)
			_end_run(HEADER_CRASH, REASON_OBSTACLE)
			return
		for ev in spawner.update_near_misses(p, caps):
			_on_near_miss(ev)
		for pos in spawner.collect_cans(p, caps):   # a can grabbed in the last moment still saves you
			_on_pickup(pos)
	hud.set_fuel(fuel / Tuning.fuel_max())
	if fuel <= 0.0:
		_end_run(HEADER_FUEL, REASON_FUEL)

## End the run: freeze the plane and show the game-over screen with what ended it.
func _end_run(header: String, reason: String) -> void:
	alive = false
	_death_time = Time.get_ticks_msec() / 1000.0
	player.crash()
	_reset_bonus()   # a crash / the end of the run ends the streak
	hud.clear_bonus()
	screen = SCREEN_OVER
	last_earned = int(score * Tuning.coins_per_score) + run_cans * Tuning.coins_per_can
	last_was_best = Save.record_run(int(score), last_earned)
	hud.show_game_over(int(score), header, reason, last_earned, last_was_best, Save.high_score)

## A fuel can was collected at `pos`: refill (never past a full tank) and pop.
func _on_pickup(pos: Vector3) -> void:
	run_cans += 1
	fuel = minf(fuel + Tuning.refill_amount(), Tuning.fuel_max())
	if not DebugFlags.off("pickup"):
		fx.pickup(pos)
		hud.fuel_pulse()
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(15)

## Near miss: raise the bonus and fire every bit of feedback at once. Each effect can be
## switched off from the URL (?nofx=sparks,streaks,flash,popup,trail,haptic,punch) to find out
## which one causes a hitch.
func _on_near_miss(ev: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	streak = mini(streak + 1, Tuning.streak_at_cap())
	bonus = Tuning.streak_bonus(streak)
	_decay_acc = 1.0   # when the hold time ends the first step comes off at once
	_bonus_timer = Tuning.bonus_hold_time
	hud.set_bonus(bonus, hud.BONUS_NONE if DebugFlags.off("punch") else hud.BONUS_PUNCH)
	var side: int = ev["side"]
	if not DebugFlags.off("sparks"):
		fx.sparks(player.position + Vector3(side * 1.05, 0.0, 0.1), side)  # wingtip nearest the obstacle
	if not DebugFlags.off("streaks"):
		fx.streaks(player.position)
	if not DebugFlags.off("flash"):
		spawner.flash_obstacle(ev["outline"])
	if not DebugFlags.off("popup"):
		var i := Tuning.popup_tier(bonus)
		var pos := camera.unproject_position(player.position + Vector3(0, 0, -2.0))
		hud.popup(Tuning.popup_text(bonus), Tuning.near_miss_sizes[mini(i, Tuning.near_miss_sizes.size() - 1)],
				Tuning.near_miss_colors[mini(i, Tuning.near_miss_colors.size() - 1)], pos)
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(Tuning.haptic_ms)  # no-op where unsupported
	hud.note_near_miss((Time.get_ticks_usec() - t0) / 1000.0)

## A tuning-panel slider changed (or Reset ran): apply anything that needs more than reading the value.
func _on_tuning_changed(property: String) -> void:
	if property == "obstacle_scale":
		spawner.refresh_obstacles()   # rows already on screen change size now

## Without fresh near misses the bonus holds, then steps come off one at a time, the most recent
## first (x2.6 -> x2.5 -> x2.4 -> x2.2 ...), bonus_decay_rate per second, down to x1.
func _decay_bonus(delta: float) -> void:
	if streak <= 0:
		return
	_bonus_timer -= delta
	if _bonus_timer > 0.0:
		return
	_decay_acc += Tuning.bonus_decay_rate * delta
	var dropped := false
	while _decay_acc >= 1.0 and streak > 0:
		_decay_acc -= 1.0
		streak -= 1
		dropped = true
	if dropped:
		bonus = Tuning.streak_bonus(streak)
		hud.set_bonus(bonus, hud.BONUS_SHRINK)   # shrinks each step: the bonus fades if you play safe

## A crash, the end of a run or a restart: no streak, no bonus.
func _reset_bonus() -> void:
	streak = 0
	bonus = 1.0
	_bonus_timer = 0.0
	_decay_acc = 0.0

## Camera tilted `camera_tilt_deg` away from straight down (so front faces show), placed so the
## screen centre always looks at world z = 0. Screen-up = world -Z.
func _update_camera() -> void:
	var tilt := deg_to_rad(Tuning.camera_tilt_deg)
	camera.size = Tuning.ortho_size
	camera.position = Vector3(0, cos(tilt), sin(tilt)) * 30.0
	camera.rotation = Vector3(-(PI / 2 - tilt), 0, 0)

## Screen spans z = -half .. +half (stretched slightly by the camera tilt).
func _half_height() -> float:
	var vp := get_viewport().get_visible_rect().size
	return Tuning.ortho_size * 0.5 * vp.y / vp.x / cos(deg_to_rad(Tuning.camera_tilt_deg))

## World z where the first row of a run starts, so that it reaches the plane after about
## opening_seconds at the start speed and ramp. If that would put it on screen it starts just above
## the top edge instead (rows never pop in).
func _first_row_z(half_h: float) -> float:
	var t := Tuning.opening_seconds
	var travel := Tuning.base_speed * t + 0.5 * Tuning.speed_ramp * t * t
	return minf(player.position.z - travel, -(half_h + 1.0))

## The plane may use the bottom `plane_zone_fraction` of the screen. The visible height
## depends on the device aspect (width is fixed), so work it out from the viewport.
func _update_plane_zone() -> void:
	var half_h := _half_height()
	var bottom := half_h - Tuning.plane_bottom_margin
	var top := half_h - 2.0 * half_h * Tuning.plane_zone_fraction
	player.set_zone(top, bottom)

func _input(event: InputEvent) -> void:
	# A touch on the tuning panel's TUNE button belongs to the button, not the game.
	if (event is InputEventScreenTouch or event is InputEventScreenDrag) and TunePanel.button_hit(event.position):
		return
	# Browsers only allow vibration after a touch, and the first real call connects to the device's
	# vibration service. A zero-length call is just a "cancel" and does NOT connect, so make an
	# imperceptible 1 ms pulse on the very first touch instead of on the first near miss.
	if not _haptic_warmed and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		_haptic_warmed = true
		if not DebugFlags.off("haptic"):
			Input.vibrate_handheld(1)
	# Tap to restart (small delay so the crash-causing drag can't restart instantly).
	if screen == SCREEN_OVER and event is InputEventScreenTouch and event.pressed \
			and Time.get_ticks_msec() / 1000.0 - _death_time > 0.5 and not hud.over_hangar_hit(event.position):
		restart()

## The start screen: the world waits (nothing scrolls) behind it.
func _show_menu() -> void:
	screen = SCREEN_MENU
	alive = false
	hud.show_menu()

func _open_hangar() -> void:
	screen = SCREEN_HANGAR
	alive = false
	hud.show_hangar()

## A Hangar buy button: the effect applies from the next run (the fuel in the tank right now is untouched).
func _buy(id: String) -> void:
	Save.buy(id)   # (the Hangar redraws itself from Save.changed)

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
