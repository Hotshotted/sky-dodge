class_name Main
extends Node3D
## Game loop: scroll speed, score, collision, camera, restart.

@onready var player: Node3D = $Player
@onready var spawner: Node3D = $Spawner
@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var hud: CanvasLayer = $Hud
var shadows := ShadowBlobs.new()   # soft shadows under obstacles and cans
var ground := GroundWorld.new()   # the countryside below (scrolls with the obstacles), the plane's shadow, Rusty's airstrip
var goals := Goals.new()        # gates for your best, the next medal and the next map unlock
var crash_fx := CrashFx.new()   # the crash sequence's smoke, debris and Whiskers
var sfx := Sfx.new()   # all sound (see Sfx.gd)
var gadgets := Gadgets.new()   # the active gear: wingmen, Prop Wash, banner, smoke, aura, roll (see Gadgets.gd)

## What ends a run, shown on the game-over screen as a big header plus a line under it.
## The plane's path each frame is tested in steps no longer than this (units), so a flick can't
## tunnel through an obstacle or skip a can (the thinnest thing it must not skip is ~1.3 wide).
const SWEEP_STEP := 0.4
const MAX_SWEEP_STEPS := 80
const CRASH_TIME := 1.5      # seconds of crash sequence before the results screen builds up
const HEADER_CRASH := "CRASHED"
const REASON_OBSTACLE := "Hit an obstacle"
const HEADER_FUEL := "OUT OF FUEL"
const REASON_FUEL := "The tank ran dry"
const HEADER_STRUCK := "STRUCK"
const REASON_STRUCK := "Hit by lightning"
const REASON_CRATE := "Clipped a crate"

## Which screen is up. A run is only on while screen == SCREEN_PLAY and alive.
enum { SCREEN_MENU, SCREEN_HANGAR, SCREEN_PLAY, SCREEN_OVER, SCREEN_LOGBOOK }
var screen := SCREEN_MENU
const MEDAL_NAMES := ["Bronze", "Silver", "Gold"]
var map := 0            # the map this run is on (Tuning.maps)
var run_distance := 0.0 # world units flown this run (Tuning.meters() turns it into meters)
var last_result := {}   # what the last run did to the map records (medals, unlocks)
var _env: Environment
var run_trail_coins := 0   # coins of the pattern trails collected this run
var _coin_chain := 0       # coins in the current trail (the chime climbs)
var _coin_last_ms := 0
var _coin_acc := 0.0       # coins paid since the last "+N" popup
var _coin_pop_pos := Vector3.ZERO
var run_cans := 0       # fuel cans collected this run
var last_earned := 0.0  # coins the last run earned (its score)
var coin_mult := 1.0    # everything earned this run is multiplied by this (map multiplier x Coin Value)
var lives := 0          # hits the plane can still ignore this run (Nine Lives charges)
var last_hit_name := ""  # what the hit that ended the run was (the results show it as a second line)
var hits_taken := 0     # hits that cost fuel this run (the results say "Out of fuel after 3 hits")
var _shake_t := 0.0     # seconds of screen shake left after a hit
var reserve_left := 0   # Reserve Tank refills still available this run
var _invuln := 0.0      # seconds of invulnerability left after a survived hit
var last_was_best := false
var score := 0.0        # THE COINS EARNED this run: distance x close-call bonus x multipliers (+ can and close-call pay)
var _steps := PackedFloat64Array()   # the bonus each close call of the streak earned (doubled for a Whisker close), oldest first
var streak := 0     # close calls in the current streak (steps come off one at a time after the hold time)
var bonus := 1.0    # points bonus from the streak, 1.0 = none
var fuel := 0.0         # drains steadily; fuel cans refill it; empty ends the run
var _bonus_timer := 0.0  # counts down to the streak starting to drop
var _decay_acc := 0.0   # fractional steps accumulated towards the next one coming off
var _warming := false
static var _haptic_warmed := false  # first-touch haptic warm-up done (once per app session)
static var _warmed := false  # pre-warm only once per app session
var prof := {}               # profiling (DebugFlags.profile only): part name -> [total us, worst us, calls] this frame run
var _takeoff_t := 99.0         # seconds since the run began (the plane lifts off from the airstrip over takeoff_seconds)
var tod_override := -1.0      # ?tune: hold the time of day at this value (0..1); -1 = follow the run
var _tod_applied := -1.0
var _tod_dark := 0.0
var _base_sky := Color(0.2, 0.26, 0.34)
var _base_ambient := Color(0.75, 0.78, 0.9)
var _mood_until_ms := 0
var _crash_t := -1.0          # seconds since the crash (-1 = no crash sequence running)
var _crash_speed := 0.0       # the world's speed when it happened (it rolls to a stop)
var _cam_ease := 0.0          # 0..1: how far the camera has eased toward the falling plane
var _results := {}            # what the results screen shows (built in _end_run)
var last_callout := ""       # the latest perk / gear callout (the tests read it)
var _callout_ms := {}         # perk / gear id -> when it last called out (they are rate-limited)
var _glide_l3_used := false
var _second_wind_count := 0
var last_cue := ""           # the latest speed cue shown on screen (the tests read it)
var _seen_steps := 0       # Countryside speed steps already announced
var _ramp_tier := 0        # other maps: speed tiers already announced
var _kit_speed := 0.0      # Countryside stepped scroll speed (eased)
var elapsed := 0.0      # run time, drives the speed ramp
var alive := true
var _death_time := 0.0
var fx := Fx.new()
var trail := Trail.new()
var tune_panel: TunePanel   # only exists when the URL has ?tune
var picks := Perks.new()              # this run's perks, boosts and the next pick's price
var pick_screen := PickScreen.new()   # the three cards (the game is paused while it is up)
var _picking := false
var _pick_cards: Array[Dictionary] = []
var _glide_left := 0.0                # Glide: seconds left in the glide (0 = not gliding)
var _gliding := false
var _combos := {}                     # combo id -> true: the combos that have switched on this run
var _crates_broken := 0
var _extra_picks := 0                 # purple crates broken: instant extra picks waiting to be shown
var _pick_is_extra := false
var _last_pick_time := 0.0             # run time of the latest pick (?perf shows the time since)
var _pick_gap_sum := 0.0               # ...and the sum of the gaps (run start -> first pick -> ...) for the average
var _pick_count := 0               # crates broken this run (Cat's Cradle counts them)
var _last_any_pick := -100.0       # run time of the latest pick of any kind
var _rare_picks := 0               # boss rewards waiting: each is a pick of three perks, level-ups favoured
var _pick_rare := false
var _last_tap_ms := -10000
var _last_tap_pos := Vector2.ZERO
var _gun_lv := {"flak": 0, "pods": 0, "tail": 0}   # the gun perks' levels (reused every frame)
var threat_coins := 0.0            # coins shooting threats down paid this run
var boss_coins := 0.0              # ...and the bosses' rewards
var burst_coins := 0.0             # ...and Wing Roll's bursts

func _ready() -> void:
	Engine.max_physics_steps_per_frame = 1   # no physics here: make sure a stall can never trigger catch-up steps
	fuel = Tuning.fuel_max()
	add_child(sfx)
	hud.sfx = sfx
	for list in [Tuning.perks, Tuning.upgrades, Tuning.boosts]:   # (the callout clock has a key for everything up front)
		for d in list:
			_callout_ms[d["id"]] = -100000
	add_child(ground)
	spawner.ground_mi.material_override = ground.base_mat
	add_child(shadows)
	add_child(crash_fx)
	add_child(goals)
	goals.reached.connect(_on_goal_reached)
	hud.play_again_pressed.connect(_on_play_again)
	hud.hangar_goto.connect(func(id: String):
		_open_hangar()
		hud.focus_upgrade(id))
	hud.result_tick.connect(func(p: float): sfx.play("tick", 0.5, 0.8 + 0.9 * p))
	hud.volume_changed.connect(func(_m: float, _s: float): sfx.apply_volumes())
	add_child(fx)
	add_child(trail)
	add_child(picks)
	add_child(pick_screen)
	pick_screen.chosen.connect(_on_pick_chosen)
	picks.changed.connect(func():
		hud.set_perks(picks.levels)
		_refresh_plane_items())
	Save.changed.connect(_refresh_plane_items)
	spawner.bump.connect(_on_bump)
	spawner.threats.telegraph.connect(_on_threat_telegraph)
	spawner.threats.killed.connect(_on_threat_killed)
	spawner.threats.shot.connect(_on_gun_shot)
	spawner.threats.blast.connect(_on_threat_blast)
	spawner.threats.boss_warning.connect(_on_boss_warning)
	spawner.threats.boss_started.connect(_on_boss_started)
	spawner.threats.boss_ended.connect(_on_boss_ended)
	add_child(gadgets)
	gadgets.spawner = spawner
	gadgets.picks = picks
	gadgets.wash_fired.connect(_on_wash)
	gadgets.wingman_absorbed.connect(_on_wingman_absorbed)
	gadgets.wingman_ready.connect(func(_i: int): _callout("wingman", "Wingman recharged"))
	gadgets.roll_started.connect(_on_roll_started)
	gadgets.roll_ended.connect(_on_roll_ended)
	gadgets.roll_ready.connect(func(): _callout("roll", "Barrel Roll ready"))
	gadgets.scattered.connect(func(pos: Vector3):
		if not DebugFlags.off("sparks"):
			fx.crate_burst(pos, 1)
		sfx.play("whoosh", 0.5, 1.5))
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
	hud.map_pressed.connect(func(i: int): Save.select_map(i))
	hud.logbook_pressed.connect(_open_logbook)
	spawner.hazards.lightning_struck.connect(hud.flash)
	hud.hangar_pressed.connect(_open_hangar)
	hud.back_pressed.connect(_show_menu)
	hud.upgrade_pressed.connect(_buy)
	hud.equip_pressed.connect(func(id: String, slot: int): Save.equip(id, slot))
	hud.buy_slot_pressed.connect(func(): Save.buy_slot())
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
	goals.prewarm_show(1.0)
	ground.prewarm_show()
	shadows.prewarm_show()
	player.prewarm_items(true)   # every perk and gear mark on the plane
	sfx.prewarm_start()   # every sound decoded once, silently
	crash_fx.prewarm_show(Vector3(0.0, 1.2, 1.0))   # smoke, debris, Whiskers and his parachute
	spawner.prewarm_show(not DebugFlags.off("flash"), not DebugFlags.off("clouds"))
	gadgets.prewarm_show()
	pick_screen.prewarm_show()      # the pick cards are drawn too
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
				fx.whisker(spot + Vector3(-0.6, 0, 1.2))   # round-robin: warms both whisker bursts
				fx.whisker(spot + Vector3(0.6, 0, 1.2))
				fx.coins(spot + Vector3(-0.8, 0, 2.2))   # round-robin: warms both coin bursts
				fx.coins(spot + Vector3(0.8, 0, 2.2))
				for kk in 3:   # every crate burst colour
					fx.crate_burst(spot + Vector3(-2.0 + 2.0 * kk, 0, 3.2), kk)
			if not DebugFlags.off("popup"):
				hud.prewarm_popups()
			if not DebugFlags.off("pickup"):
				fx.pickup(spot + Vector3(-1.0, 0, -1.5))   # round-robin: warms both pickup emitters
				fx.pickup(spot + Vector3(1.0, 0, -1.5))
				hud.fuel_pulse()
		if not DebugFlags.off("streaks"):
			fx.show_all_streaks(spot)
			fx.show_all_wind(spot)
		if not DebugFlags.off("trail"):
			trail.fill_for_prewarm(Vector2(spot.x, spot.z))  # full-length ribbon: alpha, vertex colours, big buffers
		await get_tree().process_frame
		# Stop once it has run long enough AND frames have been calm for a while (or at the cap).
		var t := Time.get_ticks_msec()
		calm_frames = calm_frames + 1 if (t - t_last) < Tuning.prewarm_stable_ms else 0
		t_last = t
		var elapsed_s := (t - t_start) / 1000.0
		hud.set_splash_progress(minf(elapsed_s / maxf(Tuning.prewarm_min_seconds, 0.1), 0.95))
		if elapsed_s >= Tuning.prewarm_max_seconds:
			break
		if elapsed_s >= Tuning.prewarm_min_seconds and calm_frames >= Tuning.prewarm_stable_frames:
			break
	fx.clear()
	goals.hide_all()
	ground.prewarm_hide()
	shadows.hide_all()
	player.prewarm_items(false)
	_refresh_plane_items()
	sfx.prewarm_end()
	crash_fx.stop()
	trail.clear()
	spawner.prewarm_hide()
	gadgets.prewarm_hide()
	pick_screen.hide_cards()
	hud.clear_bonus()
	hud.set_splash_progress(1.0)
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
	_crash_t = -1.0
	_cam_ease = 0.0
	_takeoff_t = 0.0
	_tod_applied = -1.0
	crash_fx.stop()
	ground.stop_airstrip()
	sfx.set_phase(0)
	sfx.start_music()
	sim_time = 0.0
	_run_start_ms = Time.get_ticks_msec()
	_paused_total_ms = 0
	_skip_frames = 0
	_note_event("run started")
	map = DebugFlags.start_map if DebugFlags.start_map >= 0 else Save.selected_map
	spawner.apply_map(map)
	_apply_palette()
	run_distance = 0.0
	hud.set_distance(0.0)
	run_cans = 0
	run_trail_coins = 0
	_coin_chain = 0
	_coin_acc = 0.0
	score = 0.0
	coin_mult = Tuning.map_coin_mult[map] * Tuning.coin_value_mult()
	lives = int(Tuning.gear_value("nine_lives"))
	hits_taken = 0
	last_hit_name = ""
	_shake_t = 0.0
	reserve_left = int(Tuning.gear_value("reserve_tank"))
	_invuln = 0.0
	_glide_left = 0.0
	_gliding = false
	_second_wind_count = 0
	_glide_l3_used = false
	_picking = false
	pick_screen.hide_cards()
	get_tree().paused = false
	picks.start_run(Tuning.pick_scale(map))
	_combos.clear()
	_crates_broken = 0
	_extra_picks = 0
	_pick_is_extra = false
	_last_pick_time = 0.0
	_pick_gap_sum = 0.0
	_pick_count = 0
	_rare_picks = 0
	_pick_rare = false
	_last_any_pick = -100.0
	threat_coins = 0.0
	boss_coins = 0.0
	burst_coins = 0.0
	hud.hide_boss()
	spawner.chain_nudges = false
	spawner.crate_shower_rows = 0
	gadgets.reset()
	_reset_bonus()
	var head := Tuning.gear_value("head_start")   # Head Start: begin at x1.5 / x2 (it fades like any bonus)
	if head > 1.0:
		_callout("head_start", "Head Start x%.1f" % head)
		_steps.append(head - 1.0)
		_refresh_bonus()
		_bonus_timer = Tuning.bonus_hold_time
		_decay_acc = 1.0
	elapsed = 0.0
	_kit_speed = Tuning.base_speed
	var map_mult: float = Tuning.map_def(map)["speed_mult"]
	if map_mult > 1.001:   # a faster map says so when the run starts
		last_cue = "%s: +%d%% speed" % [Tuning.map_def(map)["name"], int(round((map_mult - 1.0) * 100.0))]
		hud.show_combo("FASTER MAP", Tuning.speed_up_color, "+%d%% speed" % int(round((map_mult - 1.0) * 100.0)))
	_seen_steps = 0
	_ramp_tier = 0
	alive = true
	spawner.run_time = 0.0
	fuel = Tuning.fuel_max()
	fx.clear()
	trail.clear()
	hud.reset_for_run()
	goals.setup(_goal_list())
	hud.set_lives(lives)
	hud.set_next(picks.next_pick)
	hud.set_perks(picks.levels)   # (?tune can grant perks for every run)
	_refresh_plane_items()
	_check_combos()
	if bonus > 1.0:
		hud.set_bonus(bonus)
	player.reset()
	_update_plane_zone()
	spawner.reset(_first_row_z(_half_height()))   # after the plane is back: the opening is timed to reach it

## ---- Frame time: the simulation can never run ahead of the clock ----------------------------------------
## However long the real frame was, the simulation advances by at most Tuning.max_frame_delta; a stall (a tab
## switch, a long hitch) is dropped, not simulated; and a couple of frames are skipped after a pick, a stall or the
## window coming back, so nothing catches up. While the game is paused (the pick screen) or suspended (the window
## lost focus) no time accumulates anywhere. ?perf logs every frame over 50 ms and what was going on.

var _skip_frames := 0            # frames still to skip after a resume
var _suspended := false          # the window / tab is in the background: the world stands still
var _event := ""                 # the latest thing worth naming in the hitch log, and the frame it happened on
var _event_frame := -100
var sim_time := 0.0              # seconds of simulation this run (should track the wall clock minus pauses)
var _run_start_ms := 0
var _suspend_since_ms := 0
var _paused_since_ms := 0        # when the current pause / suspension began (0 = not paused)
var _paused_total_ms := 0

func _note_event(what: String) -> void:
	_event = what
	_event_frame = Engine.get_process_frames()

## The part of this real frame (`raw` seconds) the simulation may use: 0 to skip it.
func _frame_delta(raw: float) -> float:
	var used := 0.0
	var why := ""
	if _suspended:
		why = "window in the background"
	elif _skip_frames > 0:
		_skip_frames -= 1
		why = "skipped (resuming)"
	elif raw > Tuning.stall_delta:
		_skip_frames = Tuning.resume_skip_frames
		why = "stall dropped"
	else:
		used = minf(raw, Tuning.max_frame_delta)
		why = "clamped" if raw > Tuning.max_frame_delta else ""
	if raw > 0.05 and DebugFlags.perf_enabled():
		hud.note_hitch(raw, used, why, _hitch_context())
	return used

func _hitch_context() -> String:
	var parts: Array[String] = []
	if Engine.get_process_frames() - _event_frame <= 4 and _event != "":
		parts.append(_event)
	if spawner.rows_spawned > 0:
		parts.append("%d row(s) spawned" % spawner.rows_spawned)
	if _picking:
		parts.append("pick screen up")
	if _gliding:
		parts.append("gliding")
	if combo_banner_active():
		parts.append("combo banner")
	return ", ".join(parts) if not parts.is_empty() else "nothing special"

func combo_banner_active() -> bool:
	return hud._combo_label.visible

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			if not _suspended:
				_suspended = true
				_suspend_since_ms = Time.get_ticks_msec()   # (its own clock: a pick screen that was already up keeps its own)
				AudioServer.set_bus_mute(0, true)           # nothing keeps droning from a background tab
				_note_event("window went to the background")
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			if _suspended:
				_suspended = false
				_paused_total_ms += Time.get_ticks_msec() - _suspend_since_ms
				AudioServer.set_bus_mute(0, false)
				_skip_frames = Tuning.resume_skip_frames
				player.clear_input()   # (the drag that piled up while away must not jump the plane)
				_note_event("window came back")

## Seconds of this run on the wall clock, without the time spent paused.
func run_wall_time() -> float:
	return maxf((Time.get_ticks_msec() - _run_start_ms - _paused_total_ms) / 1000.0, 0.0)

## Profiling helper: add the time since t0 to the part `part`.
func _pf(part: String, t0: int) -> void:
	if not DebugFlags.profile:
		return
	var dt := Time.get_ticks_usec() - t0
	if not prof.has(part):
		prof[part] = [0, 0, 0]
	var rec: Array = prof[part]
	rec[0] += dt
	rec[1] = maxi(rec[1], dt)
	rec[2] += 1

func _process(raw_delta: float) -> void:
	hud.graph_push(raw_delta * 1000.0)
	_update_camera()
	_update_plane_zone()
	ground.update_shadow(player.position, not _warming and (screen == SCREEN_PLAY or screen == SCREEN_OVER))
	if screen == SCREEN_PLAY:
		_flush_coin_pop()
	_apply_time_of_day(_current_tod())
	if _shake_t > 0.0:
		_shake_t = maxf(_shake_t - raw_delta, 0.0)
	if _warming or not alive or screen != SCREEN_PLAY:
		shadows.update_from(spawner, _tod_dark, not _warming and screen == SCREEN_OVER)
	if not _warming and not alive and _crash_t >= 0.0 and screen == SCREEN_OVER:
		_update_crash(_frame_delta(raw_delta))
	if _warming or not alive:
		return
	var delta := _frame_delta(raw_delta)
	if DebugFlags.perf_enabled():
		hud.set_clock(sim_time, run_wall_time())
		hud.set_pick_stats(elapsed - _last_pick_time, _pick_gap_sum / maxf(_pick_count, 1), _pick_count)
	if delta <= 0.0:
		return
	sim_time += delta
	elapsed += delta
	player.step(delta)   # 1:1 finger movement this frame (the path from prev_xz to here is swept below)
	if _takeoff_t < Tuning.takeoff_seconds + delta:   # takeoff: the plane lifts off Rusty's airstrip
		if _takeoff_t == 0.0:
			ground.start_airstrip(player.position.z)
		_takeoff_t += delta
		var tk := clampf(_takeoff_t / Tuning.takeoff_seconds, 0.0, 1.0)
		tk = tk * tk * (3.0 - 2.0 * tk)
		player.position.y = lerpf(-1.55, player.PLANE_Y, tk)
		player._model.scale = Vector3.ONE * lerpf(0.85, 1.0, tk)
	picks.update(delta)
	var tail := 1.0 + Tuning.tailwind_speed_pct[picks.level("tailwind")] * 0.01   # Tailwind: a little more speed (its coins are in earn_mult)
	var speed := Tuning.map_speed(map, elapsed) * tail
	if spawner.kit_on:   # Countryside: no ramp, only the steps a BREATHER brings (eased in)
		_kit_speed = move_toward(_kit_speed, spawner.stepped_speed(spawner.speed_steps), Tuning.speed_step_rate * delta)
		speed = _kit_speed * tail   # (no ceiling: the patterns hold up as well as they can, the world keeps speeding up)
	if spawner.kit_on:
		spawner.base_speed_now = _kit_speed
	var step := speed * delta
	_crash_speed = speed
	score += step * Tuning.coins_per_unit * distance_pay() * earn_mult()
	spawner.near_miss_scale = 1.0 + picks.value("daredevil") * 0.01
	spawner.whisker_scale = 2.0 if picks.level("daredevil") >= 3 else 1.0
	spawner.plane_z = player.position.z   # clouds fade as they near the plane,
	spawner.run_time = elapsed            # start late in the run,
	spawner.scroll_speed = speed          # and come more often the faster it goes
	spawner.plane_x = player.position.x
	var t_pf := Time.get_ticks_usec()
	_speed_cues(speed / tail, delta)
	var want_mood: int = player.Mood.STARTLED if Time.get_ticks_msec() < _mood_until_ms else (player.Mood.GRIN if bonus >= 2.0 else player.Mood.NEUTRAL)
	if want_mood != player.mood:
		player.set_mood(want_mood)
	sfx.set_flight(true, (speed - Tuning.base_speed) / maxf(Tuning.max_speed - Tuning.base_speed, 1.0) * lerpf(0.3, 1.0, clampf(_takeoff_t / Tuning.takeoff_seconds, 0.0, 1.0)))
	sfx.set_phase(spawner.wave_phase if spawner.kit_on else int(elapsed / 30.0) % 3)
	_pf("speed cues + wind", t_pf)
	t_pf = Time.get_ticks_usec()
	spawner.advance(step)
	ground.scroll(step)
	_pf("spawner.advance (rows, clouds)", t_pf)
	t_pf = Time.get_ticks_usec()
	spawner.update_hazards(delta)
	_update_threats(delta)
	_update_gadgets(delta, step)
	spawner.coins.sync(player.position.z)
	shadows.update_from(spawner, _tod_dark, true)
	_pf("spawner.update_hazards (kit motion, colliders)", t_pf)
	t_pf = Time.get_ticks_usec()
	run_distance += step
	goals.update(Tuning.meters(run_distance), player.position.z, -_half_height())
	hud.set_distance(Tuning.meters(run_distance))
	hud.set_score(score, bonus)
	var push: float = spawner.hazards.push_at(player.position.x, player.position.z)   # wind gusts
	if push != 0.0:
		player.nudge_x(push * delta)
	var plane := Vector2(player.position.x, player.position.z)
	trail.advance(step, Vector2(plane.x, plane.y + 0.9), 1 if DebugFlags.off("trail") else bonus, delta)
	_decay_bonus(delta)
	hud.refresh_effects(picks.boosts, _glide_left)
	if not picks.has_boost("fuel_freeze"):   # Fuel Freeze: nothing burns
		var burn := Tuning.drain_rate() * (1.0 + Tuning.drain_growth_per_min * elapsed / 60.0) * pow(maxf(speed / Tuning.base_speed, 1.0), Tuning.drain_speed_exp) * (1.0 - picks.value("fuel_miser") * 0.01)
		fuel = maxf(fuel - burn * delta, 0.0)
	_pf("hud, trail, fuel", t_pf)
	var cd := picks.value("cloud_diver")      # Cloud Diver: fuel back while under a cloud
	if cd > 0.0 and spawner._cloud_over(plane.x, plane.y):
		_add_fuel(cd * delta)
		_callout("cloud_diver", "Cloud Diver: fuel back!")

	# Swept collision: the plane can move any distance in one frame (a fast flick), so test the whole
	# path from where it was to where it is, in small steps, instead of only the end point. Obstacles,
	# near misses and fuel cans are all checked along the way, and a crash stops the plane where it
	# first touched.
	var caps: PackedFloat32Array = player.hit_capsules()
	var reach := Tuning.pickup_reach()   # Can Magnet gear: cans inside the radius fly to the plane
	if picks.has_boost("magnet_storm"):
		reach = maxf(reach, Tuning.storm_radius)
	if combo_on("deadstick") and _gliding:   # Deadstick: while gliding, cans come from anywhere on screen
		reach = 60.0
	var aura := gadgets.aura_radius()   # Magnet Field: coins (never fuel cans: those you fly to) inside the aura are pulled in
	if aura > 0.0:
		spawner.coins.pull(plane, aura, Tuning.magnet_pull_speed * delta)
	spawner.chain_nudges = combo_on("wingwalker") or picks.level("prop_wash") >= 3   # (Prop Wash 3: bumps chain)
	if reach > 0.0 and spawner.pull_cans(plane, reach, Tuning.magnet_pull_speed * delta) and Tuning.gear_value("magnet") > 0.0:
		_callout("magnet", "Can Magnet!")
	if _invuln > 0.0:
		_invuln = maxf(_invuln - delta, 0.0)
		player.set_flicker(_invuln > 0.0 and not gadgets.rolling() and int(_invuln * 14.0) % 2 == 0)   # the plane sputters
	if _invuln <= 0.0 and not DebugFlags.god and spawner.hazards.hit(player.position.x):   # lightning
		if _hit_is_fatal():
			_fatal_hit(REASON_STRUCK)
			return
		_take_hit(plane, caps, REASON_STRUCK)
	if _invuln <= 0.0 and not DebugFlags.god:
		var tk: int = spawner.threats.hit(plane)
		if tk >= 0:
			var why: String = Threats.CAUSES[tk]
			if _hit_is_fatal():
				_fatal_hit(why)
				return
			_take_hit(plane, caps, why)
	var battering: bool = picks.level("battering_ram") > 0                          # Battering Ram: any touch breaks a crate
	var ram_ok: bool = Tuning.ram_speed <= 0.0 or player.velocity.y < -Tuning.ram_speed   # (optional extra: moving up fast enough)
	var from: Vector2 = player.prev_xz
	var steps := clampi(ceili(from.distance_to(plane) / SWEEP_STEP), 1, MAX_SWEEP_STEPS)
	for i in range(1, steps + 1):
		var p: Vector2 = from.lerp(plane, float(i) / steps)
		t_pf = Time.get_ticks_usec()
		for b in spawner.break_crates(p, caps, battering, ram_ok, from.y):   # a crate in the way breaks if it may
			_on_crate_break(b["kind"], b["pos"])
		_pf("collision: break_crates", t_pf)
		t_pf = Time.get_ticks_usec()
		var was_hit: bool = _invuln <= 0.0 and not DebugFlags.god and spawner.hits(p, caps)
		_pf("collision: hits", t_pf)
		if was_hit:
			if _hit_is_fatal():
				# This hit empties the tank for good. Find the step that hit and narrow it down to the exact first touch, so a
				# fast flick stops AT the obstacle instead of up to a sweep step inside it.
				var lo: Vector2 = from.lerp(plane, float(i - 1) / steps)
				var hi := p
				for k in 8:
					var mid := lo.lerp(hi, 0.5)
					if spawner.hits(mid, caps):
						hi = mid
					else:
						lo = mid
				player.position = Vector3(hi.x, player.position.y, hi.y)
				_fatal_hit(REASON_CRATE if spawner.last_hit_crate else REASON_OBSTACLE)
				return
			_take_hit(p, caps, REASON_CRATE if spawner.last_hit_crate else REASON_OBSTACLE)   # a hit costs fuel (or is ignored): the run goes on, the plane is invulnerable for a moment
			continue
		t_pf = Time.get_ticks_usec()
		for ev in spawner.update_near_misses(p, caps):
			_on_near_miss(ev)
		_pf("collision: near misses (+ effects)", t_pf)
		t_pf = Time.get_ticks_usec()
		var cans: Array[Vector3] = spawner.collect_cans(p, caps)   # a can grabbed in the last moment still saves you
		for ci in cans.size():
			_on_pickup(cans[ci], spawner.picked_golden[ci])
		_pf("collision: cans", t_pf)
		t_pf = Time.get_ticks_usec()
		var got_coins: int = spawner.coins.collect(p, caps, Tuning.coin_pickup_radius)
		if got_coins > 0:
			_on_coins(got_coins, spawner.coins.last_pos)
		_pf("collision: coins", t_pf)
	hud.set_fuel(fuel / Tuning.fuel_max())
	_check_fuel(delta)
	if not _picking:
		var due := score >= picks.next_pick
		if picks.picks_taken == 0 and picks.enabled:   # the first pick lives in a time window
			due = (due and elapsed >= Tuning.first_pick_min_seconds) or elapsed >= Tuning.first_pick_max_seconds
		elif due and elapsed - _last_pick_time < Tuning.pick_min_gap(picks.picks_taken - 1):   # ...and later ones keep a minimum spacing
			due = false
		var spaced := picks.picks_taken == 0 or elapsed - _last_any_pick >= Tuning.pick_spacing   # (two picks never come back to back)
		if _rare_picks > 0 and spaced:
			_begin_pick(true, true)   # a boss's reward: three perks
		elif due and spaced:
			_begin_pick(false)
		elif _extra_picks > 0 and spaced:
			_begin_pick(true)   # (a purple crate's pick is extra: it does not use up the score)

## Empty tank: Reserve Tank refills it; Glide (a perk) keeps you flying for a few seconds; else the run ends.
## Second Wind refills a share of the tank once when it runs low.
func _check_fuel(delta: float) -> void:
	var sw := picks.value("second_wind")
	if sw > 0.0 and _second_wind_count < (2 if picks.level("second_wind") >= 3 else 1) and fuel > 0.0 and fuel < Tuning.fuel_max() * Tuning.second_wind_below:
		_second_wind_count += 1
		_callout("second_wind", "Second Wind! +%d%%" % int(sw))
		_add_fuel(Tuning.fuel_max() * sw * 0.01)
		hud.fuel_pulse()
	if fuel > 0.0:
		_gliding = false
		_glide_left = 0.0
		return
	if reserve_left > 0:   # Reserve Tank: the tank refills itself
		reserve_left -= 1
		_callout("reserve_tank", "Reserve Tank saved you!")
		fuel = Tuning.fuel_max() * Tuning.reserve_refill_fraction
		hud.fuel_pulse()
		hud.set_fuel(fuel / Tuning.fuel_max())
		if not DebugFlags.off("sparks"):
			fx.pickup(player.position)
		return
	var glide := picks.value("glide")
	if glide > 0.0:
		if not _gliding:
			_gliding = true
			_glide_left = glide
		_glide_left -= delta
		_callout("glide", "Glide!")
		if _glide_left > 0.0:
			return
		if picks.level("glide") >= 3 and not _glide_l3_used:   # Glide 3: when the glide ends the tank is topped up once
			_glide_l3_used = true
			_gliding = false
			fuel = Tuning.fuel_max() * 0.2
			_callout("glide", "Glide: tank topped up!")
			return
	_end_run(HEADER_FUEL, _fuel_death_reason())

## "Out of fuel after 3 hits": what the results say when the tank is empty (hits count, so you see what drained it).
func _fuel_death_reason() -> String:
	if hits_taken <= 0:
		return REASON_FUEL
	return "Out of fuel after %d hit%s" % [hits_taken, "" if hits_taken == 1 else "s"]

## Coins per unit flown at the current bonus: bonus - bonus_pay_offset (x1 = 0.2, x2 = 1.2, x3 = 2.2).
func distance_pay() -> float:
	return maxf(bonus - Tuning.bonus_pay_offset, 0.0) if Tuning.score_uses_bonus else 1.0

## Everything earned is multiplied by this: the permanent multiplier (map x Coin Value), Tailwind, Double Coins.
func earn_mult() -> float:
	return coin_mult * (1.0 + picks.value("tailwind") * 0.01) * (2.0 if picks.has_boost("double_coins") else 1.0)

# ---------- In-run picks ----------

## The score reached the next pick: pause the game completely, deal three cards.
func _begin_pick(extra: bool = false, rare: bool = false) -> void:
	_pick_rare = rare
	_picking = true
	sfx.play("pick_open")
	sfx.duck(true)
	sfx.set_flight(false)
	_paused_since_ms = Time.get_ticks_msec()
	_note_event("pick screen opened")
	_pick_is_extra = extra
	if rare:
		_rare_picks = maxi(_rare_picks - 1, 0)
	elif extra:
		_extra_picks = maxi(_extra_picks - 1, 0)
	var mode := "rare" if rare else ("first" if (picks.picks_taken == 0 and not extra) else ("second" if (picks.picks_taken == 1 and not extra) else ""))
	_pick_cards = picks.roll(fuel / Tuning.fuel_max(), Tuning.pick_cards, mode)
	if tune_panel:
		tune_panel.set_available(false)
	var hints: Array = []
	for c in _pick_cards:
		hints.append(picks.would_complete(c))   # a card that would complete a combo is highlighted
	pick_screen.set_build(picks.levels)
	pick_screen.show_cards(_pick_cards, hints)
	get_tree().paused = true

func _on_pick_chosen(i: int) -> void:
	if i < 0 or i >= _pick_cards.size():
		return
	var card := _pick_cards[i]
	sfx.play("pick_select")
	sfx.duck(false)
	pick_screen.hide_cards()
	get_tree().paused = false
	_picking = false
	_paused_total_ms += Time.get_ticks_msec() - _paused_since_ms   # (the pause does not count as run time)
	_skip_frames = Tuning.resume_skip_frames                       # and nothing catches up after it
	_note_event("pick resume")
	if tune_panel:
		tune_panel.set_available(true)
	_pick_gap_sum += elapsed - _last_pick_time
	_last_any_pick = elapsed
	if not _pick_is_extra:
		_last_pick_time = elapsed
	_pick_count += 1
	_apply_card(card)
	if not _pick_is_extra:
		picks._bag_score = score
		picks.advance(score, elapsed, base_score())
	_pick_is_extra = false
	hud.set_next(picks.next_pick)
	_check_combos()

## Every speed change is explained on screen. Called each frame with the speed before Tailwind (`base`): a Countryside
## step (a BREATHER passing) and a tier of the other maps' ramp show a SPEED UP banner and the wind rush.
func _speed_cues(base: float, delta: float) -> void:
	if spawner.kit_on:
		if spawner.speed_steps != _seen_steps:
			var before: float = spawner.stepped_speed(_seen_steps)
			_seen_steps = spawner.speed_steps
			var after: float = spawner.stepped_speed(_seen_steps)
			if after > before + 0.01:
				_speed_up_cue(after / before - 1.0)
	else:
		var m := Tuning.map_def(map)
		var tier := int((base - Tuning.base_speed * m["speed_mult"]) / maxf(Tuning.speed_step, 0.1))
		if tier > _ramp_tier:
			_ramp_tier = tier
			_speed_up_cue(Tuning.speed_step / maxf(base, 1.0))
	fx.wind_update(delta, player.position, picks.value("tailwind") > 0.0 and alive and not DebugFlags.off("streaks"))

## The SPEED UP banner with its whoosh (and a nudge on the Tailwind icon, which speeds the plane up too).
func _speed_up_cue(fraction: float) -> void:
	last_cue = Tuning.speed_up_text
	sfx.play("speed_whoosh", 0.9)
	hud.show_combo(Tuning.speed_up_text, Tuning.speed_up_color, "+%d%% speed" % int(round(fraction * 100.0)))
	if not DebugFlags.off("streaks"):
		fx.whoosh()
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(40)
	if picks.value("tailwind") > 0.0:
		hud.pulse_perk("tailwind")

## Take a card: a perk levels up, a boost starts, a supply happens at once.
func _apply_card(card: Dictionary) -> void:
	picks.take(card)
	if card["kind"] == "perk" and card["id"] == "tailwind":   # Tailwind, picked or levelled: say what it does
		last_cue = "Tailwind! +%d%% speed" % int(Tuning.tailwind_speed_pct[int(card["level"])])
		if not DebugFlags.off("popup"):
			hud.popup(last_cue, 64, Tuning.tailwind_color, camera.unproject_position(player.position + Vector3(0, 0, -3.0)))
		hud.pulse_perk("tailwind")
	if card["kind"] != "supply":
		return
	match card["id"]:
		"full_tank":
			fuel = Tuning.fuel_max()
			hud.fuel_pulse()
		"patch":   # a Patch Kit repairs one hit
			_add_fuel(Tuning.fuel_max() * Tuning.patch_fuel_fraction)
			hud.fuel_pulse()
		"coin_bag":
			var amount := picks.coin_bag_amount()
			score += amount
			hud.coin_pop("+" + Tuning.fmt(amount), camera.unproject_position(player.position + Vector3(0, 0, -2.0)))
		"crate_shower":
			spawner.crate_shower_rows = Tuning.crate_shower_rows

# ---------- Gadgets: the active gear ----------

func try_roll() -> bool:
	return gadgets.try_roll()

func _update_gadgets(delta: float, step_dist: float) -> void:
	gadgets.combo_shock_awe = combo_on("shock_awe")
	gadgets.combo_smokescreen = combo_on("smokescreen")
	gadgets.combo_wing_roll = combo_on("wing_roll")
	gadgets.step(delta, player.position, player.velocity.x, step_dist)
	if gadgets.rolling():
		_invuln = maxf(_invuln, gadgets.roll_t + 0.05)   # a roll cannot be hit
	# wingmen: they collect what is near them
	var wcaps := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, Tuning.wingman_collect])
	for i in gadgets.wingman_count():
		var wp := gadgets.wingman_pos(i)
		var got: int = spawner.coins.collect(wp, wcaps, Tuning.coin_pickup_radius)
		if got > 0:
			_on_coins(got, spawner.coins.last_pos)
	# the banner: a net of coins behind the plane
	if gadgets.level("banner") > 0:
		var got2: int = spawner.coins.collect(Vector2(player.position.x, player.position.z), gadgets.banner_caps(), 0.1)
		if got2 > 0:
			_on_coins(got2 * (2 if combo_on("banner_ad") else 1), spawner.coins.last_pos)
			hud.pulse_perk("banner")

func gadget_level(id: String) -> int:
	return picks.level(id)

func _on_roll_started() -> void:
	player.roll(Tuning.roll_time)
	sfx.play("whoosh_big", 0.8, 1.3)
	hud.pulse_perk("roll")
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(Tuning.haptic_ms * 2)

func _on_roll_ended() -> void:
	if combo_on("wing_roll"):   # Wing Roll: the roll ends in a burst of coins from you and your wingmen
		var burst := maxf(10.0, Tuning.combo_wingroll_burst * earn_rate()) * earn_mult() / maxf(coin_mult, 0.001)
		score += burst
		burst_coins += burst
		picks.next_pick += burst
		if not DebugFlags.off("popup"):
			hud.coin_pop("+" + Tuning.fmt(floorf(burst)), camera.unproject_position(player.position + Vector3(0, 0, -1.5)))
		if not DebugFlags.off("sparks"):
			fx.coins(player.position + Vector3(0, 0, -0.8))
			for i in gadgets.wingman_count():
				fx.coins(Vector3(gadgets.wingman_pos(i).x, 1.0, gadgets.wingman_pos(i).y))
		sfx.play("coin", 1.0, 1.2)

func _on_wash(pos: Vector3, _radius: float) -> void:
	sfx.play("whoosh", 0.7, 0.7)
	hud.pulse_perk("shockwave")

func _on_wingman_absorbed(pos: Vector3) -> void:
	_invuln = Tuning.hit_invulnerable_time

# ---------- Threats: hunting enemies, guns, bosses ----------

## What the earning rate is right now (coins per second this run, at least a little): guns and kills are priced in it.
## The run's coins without the rewards (kills, bosses, roll bursts): what the earning rate, the pick prices and the rewards are measured in,
## so that rewards can never feed back on themselves.
func base_score() -> float:
	return maxf(score - threat_coins - boss_coins - burst_coins, 0.0)

func earn_rate() -> float:
	return maxf(base_score() / maxf(elapsed, 10.0), 0.5)

func _update_threats(delta: float) -> void:
	var th = spawner.threats
	th.plane_x = player.position.x
	th.plane_z = player.position.z
	th.half_h = _half_height()
	th.z_min = player.z_min
	th.z_max = player.z_max
	th.elapsed = elapsed
	th.meters = Tuning.meters(run_distance)
	th.wave_phase = spawner.wave_phase
	for id in _gun_lv:
		_gun_lv[id] = picks.level(id)
	th.gun_levels = _gun_lv
	th.update(delta)
	if th.boss_active:
		hud.set_boss(th.boss_name, th.boss_hp / maxf(th.boss_hp_max, 0.001), Threats.BOSS_COLORS[clampi(th.boss_kind, 0, 2)] if not th.boss_mini else Color(1.0, 0.8, 0.25))
	elif hud.boss_bar_visible():
		hud.hide_boss()

const THREAT_HINTS := ["HAWK! Watch its shadow", "GEESE! Slip over or under them", "CROWS behind you! Weave", "DRONE! Leave its lane", "", "", "", "", "THE GOOSE GENERAL!", ""]

func _on_threat_telegraph(kind: int) -> void:
	match kind:
		Threats.HAWK:
			sfx.play("screech", 0.9)
		Threats.GOOSE, Threats.GENERAL:
			sfx.play("honk", 0.9)
		Threats.CROW:
			sfx.play("caw", 0.9)
		Threats.DRONE:
			sfx.play("whine", 0.8)
	if kind < THREAT_HINTS.size() and THREAT_HINTS[kind] != "" and not spawner.threats.intro_shown.has(kind + 100) and not DebugFlags.off("popup"):
		spawner.threats.intro_shown[kind + 100] = true
		hud.popup(THREAT_HINTS[kind], 52, Color(1.0, 0.45, 0.3), camera.unproject_position(player.position + Vector3(0, 0, -6.0)))

func _on_gun_shot(gun: String, _cost: float) -> void:
	sfx.play("flak", 0.8, 1.0 + 0.1 * float(["flak", "pods", "tail"].find(gun)))
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(Tuning.haptic_ms)
	hud.pulse_perk(gun)

func _on_threat_killed(kind: int, pos: Vector3, by_gun: bool) -> void:
	if not DebugFlags.off("sparks"):
		fx.crate_burst(pos, 0 if kind != Threats.DRONE else 1)
	if by_gun:
		if combo_on("goldrush") and not DebugFlags.off("sparks"):
			fx.coins(pos)   # Gold Rush: the coins burst out and fly to you
		sfx.play("boom", 0.6, 1.3)
		var secs: float = Tuning.kill_pay_seconds[clampi(kind, 0, 3)] if kind <= Threats.DRONE else 0.0
		if secs > 0.0:
			var pay := maxf(Tuning.kill_pay_min, secs * earn_rate()) * (Tuning.combo_goldrush_mult if combo_on("goldrush") else 1.0)
			score += pay
			threat_coins += pay
			picks.next_pick += pay   # (a reward never brings the next pick sooner)
			if not DebugFlags.off("popup"):
				hud.coin_pop("+" + Tuning.fmt(floorf(pay)), camera.unproject_position(pos))

func _on_threat_blast(pos: Vector3, big: bool) -> void:
	if big:
		sfx.play("boom", 0.8)
		var d := Vector2(pos.x - player.position.x, pos.z - player.position.z).length()
		if d < 7.0 and not DebugFlags.off("shake"):
			_shake_t = maxf(_shake_t, Tuning.hit_shake_time * 0.45)

func _on_boss_warning(boss_name: String) -> void:
	sfx.play("alarm", 0.9)
	last_cue = "BOSS: " + boss_name
	var th = spawner.threats
	var col: Color = Color(1.0, 0.8, 0.25) if th.boss_mini else Threats.BOSS_COLORS[clampi(th.boss_kind, 0, 2)]
	hud.show_combo(boss_name, col, "RIVAL INCOMING!" if th.boss_mini else "BOSS INCOMING!")

func _on_boss_started(_boss_name: String) -> void:
	sfx.play("whoosh_big", 0.9)

func _on_boss_ended(boss_name: String, defeated: bool, mini: bool) -> void:
	var gap := picks.pick_gap()
	var frac: float = Tuning.mini_boss_reward if mini else (Tuning.boss_reward_defeat if defeated else Tuning.boss_reward_survive)
	var amount := floorf(gap * frac)
	score += amount
	boss_coins += amount
	picks.next_pick += amount   # (a boss's coins never bring the next pick sooner)
	if Tuning.boss_rare_pick:
		_rare_picks += 1
	sfx.play("ding", 1.0)
	last_cue = ("%s beaten! +%s" if defeated else "%s survived! +%s") % [boss_name, Tuning.fmt(amount)]
	if not DebugFlags.off("popup"):
		hud.show_combo("DRIVEN OFF!" if defeated else "SURVIVED!", Color(1.0, 0.85, 0.3), "+%s coins and a rare pick" % Tuning.fmt(amount))
		hud.coin_pop("+" + Tuning.fmt(amount), camera.unproject_position(player.position + Vector3(0, 0, -2.0)))
	if not DebugFlags.off("sparks"):
		fx.coins(player.position + Vector3(0, 0, -1.0))
	hud.hide_boss()

## Prop Wash: a shoved obstacle bumped another one: coins (each link of a Wingwalker chain pays one more time).
func _on_bump(pos: Vector3, depth: int) -> void:
	var pay := picks.value("prop_wash") * earn_mult() * (1.0 + depth)
	_callout("prop_wash", "Prop Wash +%s" % Tuning.fmt(pay))
	if pay <= 0.0:
		return
	score += pay
	hud.coin_pop("+" + Tuning.fmt(pay), camera.unproject_position(pos))
	if not DebugFlags.off("sparks"):
		fx.coins(pos)

## ---- Combos ----

func combo_on(id: String) -> bool:
	return _combos.has(id)

## Switch on every combo whose condition is now met: banner, a burst, and the effect from then on.
func _check_combos() -> void:
	for c in Tuning.combos:
		if _combos.has(c["id"]) or not picks.combo_ready(c):
			continue
		_combos[c["id"]] = true
		Save.discover_combo(c["id"])
		hud.show_combo(c["name"], c["color"])
		hud.flash(c["color"])
		if not DebugFlags.off("sparks"):
			fx.whisker(player.position + Vector3(-1.0, 0.0, -0.5))
			fx.whisker(player.position + Vector3(1.0, 0.0, -0.5))
			fx.coins(player.position + Vector3(0.0, 0.0, -1.5))

## Fuel in: never above a full tank. Fuel Overflow turns what would have spilled into coins.
func _add_fuel(amount: float) -> void:
	var room := Tuning.fuel_max() - fuel
	fuel += minf(amount, room)
	if amount > room and combo_on("fuel_overflow"):
		score += (amount - room) * Tuning.overflow_coin_rate * earn_mult()

## A crate broke (kind 1 gold = coins, 2 green = fuel, 3 purple = an extra pick).
func _on_crate_break(kind: int, pos: Vector3) -> void:
	_note_event("crate broke")
	Save.add_stat("crates")
	sfx.play("crunch", 1.0, [1.0, 1.12, 0.88][clampi(kind - 1, 0, 2)])
	hud.pulse_perk("tailwind")
	var ram := picks.level("battering_ram")
	var gold_touch := maxf(picks.value("golden_touch"), 1.0)   # Golden Touch: crates pay x3 / x5 / x8
	if ram > 0:
		_callout("battering_ram", "Battering Ram!")
		if ram >= 3:   # Battering Ram 3: every crate also refuels
			_add_fuel(Tuning.fuel_max() * 0.15)
	if gold_touch > 1.0:
		_callout("golden_touch", "Golden Touch x%d" % int(gold_touch))
		if picks.level("golden_touch") >= 3:   # Golden Touch 3: a can drops ahead too
			spawner.drop_can_ahead(player.position.x)
	if not DebugFlags.off("sparks"):
		fx.crate_burst(pos, kind - 1)
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(20)
	var at := camera.unproject_position(pos)
	match kind:
		1:
			var coins := Tuning.crate_coins * earn_mult() * gold_touch * (1.0 + 0.5 * maxi(ram - 1, 0))   # Battering Ram 2-3: more crate coins
			score += coins
			hud.coin_pop("+" + Tuning.fmt(coins), at)
		2:
			_add_fuel(Tuning.crate_fuel * gold_touch)
			hud.fuel_pulse()
			hud.coin_pop("FUEL", at)
		3:
			_extra_picks += 1
	_on_crate_broken()

## A crate was broken: Cat's Cradle gives a life back for every N of them.
func _on_crate_broken() -> void:
	_crates_broken += 1
	if combo_on("cats_cradle") and _crates_broken % Tuning.cradle_crates == 0:   # Cat's Cradle refuels a quarter tank
		_add_fuel(Tuning.fuel_max() * Tuning.cradle_fuel_fraction)
		hud.fuel_pulse()
		hud.coin_pop("FUEL", camera.unproject_position(player.position + Vector3(0, 0, -2.0)))

## The plane hit something (or was struck by lightning). A Shield or a Nine Lives charge ignores it; otherwise it costs
## hit_fuel_fraction of the tank (the run ends only if that empties it, see _check_fuel), drops the close-call bonus by
## hit_bonus_steps (Steady Nerves protects part of that) and gives about a second of invulnerability. The obstacle it hit gives
## no close-call credit. Strong feedback: crunch, screen shake, flicker, debris, a big "-25" on the fuel gauge.
func _take_hit(p: Vector2, caps: PackedFloat32Array, what: String = REASON_OBSTACLE) -> void:
	last_hit_name = _hit_name(what)
	_invuln = Tuning.hit_invulnerable_time
	spawner.mark_hit_rows(p, caps)
	if picks.has_boost("shield"):   # the Shield goes first
		picks.boosts.erase("shield")
		picks.changed.emit()
		_callout("shield", "Shield!")
		_hit_feedback(0.0)
		return
	if gadgets.absorb_hit():   # a wingman takes it
		_callout("wingman", "Wingman took the hit!")
		_hit_feedback(0.0)
		return
	if lives > 0:   # Nine Lives: ignore this hit
		lives -= 1
		_callout("nine_lives", "Nine Lives! Hit ignored")
		hud.set_lives(lives)
		_hit_feedback(0.0)
		return
	hits_taken += 1
	var cost := Tuning.hit_cost()
	fuel = maxf(fuel - cost, 0.0)
	hud.set_fuel(fuel / Tuning.fuel_max())
	# the close-call bonus drops a few steps (the most recent ones first); Steady Nerves protects part of the loss
	var protect := Tuning.gear_value("steady_nerves")
	var drop := ceili(float(Tuning.hit_bonus_steps) * (1.0 - protect) - 0.0001)
	_steps.resize(maxi(_steps.size() - drop, 0))
	_refresh_bonus()
	if drop > 0 and not _steps.is_empty() or protect > 0.0 and not _steps.is_empty():
		_bonus_timer = Tuning.bonus_hold_time
		hud.set_bonus(bonus, hud.BONUS_SHRINK)
	if protect > 0.0 and not _steps.is_empty():
		_callout("steady_nerves", "Steady Nerves kept your streak!")
	_hit_feedback(cost)

## What a hit was, for the results ("Clipped by a crow flock").
func _hit_name(what: String) -> String:
	if what == REASON_OBSTACLE and spawner.kit_on and spawner.kit.last_hit_kind >= 0:
		return Kit.CAUSES[spawner.kit.last_hit_kind]
	return what

## Would a hit now empty the tank for good (no Shield, no Nine Lives charge, no Reserve Tank, no Glide)?
func _hit_is_fatal() -> bool:
	if picks.has_boost("shield") or lives > 0 or reserve_left > 0 or picks.value("glide") > 0.0 or gadgets.wingman_ready_count() > 0:
		return false
	return fuel - Tuning.hit_cost() <= 0.0

## The hit that ends the run: it counts, the tank is empty, and the results name what drained it.
func _fatal_hit(what: String) -> void:
	hits_taken += 1
	fuel = 0.0
	hud.set_fuel(0.0)
	var cause := _fuel_death_reason()
	last_hit_name = _hit_name(what)
	_end_run(HEADER_FUEL if what != REASON_STRUCK else HEADER_STRUCK, cause)

func _hit_feedback(cost: float) -> void:
	sfx.play("crunch", 1.0)
	if not DebugFlags.off("shake"):
		_shake_t = Tuning.hit_shake_time
	if not DebugFlags.off("sparks"):
		fx.sparks(player.position + Vector3(-1.05, 0.0, 0.1), -1)
		fx.sparks(player.position + Vector3(1.05, 0.0, 0.1), 1)
		fx.crate_burst(player.position, 0)   # splinters and dust: debris
	if cost > 0.0:
		hud.fuel_damage(cost)
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(Tuning.haptic_ms * 4)

## End the run: freeze the plane and show the game-over screen with what ended it.
func _end_run(header: String, reason: String) -> void:
	_coin_last_ms = -100000
	_flush_coin_pop()
	alive = false
	fx.stop_wind()
	sfx.play("crash")
	sfx.stop_run()
	sfx.set_phase(3)
	_death_time = Time.get_ticks_msec() / 1000.0
	player.crash()
	player.set_flicker(false)
	_crash_t = 0.0
	player.set_cockpit(false)   # Whiskers has ejected
	if not DebugFlags.off("sparks"):
		crash_fx.start(player.global_position, -1.0 if player.position.x > 0.0 else 1.0)
	var cause := reason
	if reason == REASON_OBSTACLE and spawner.kit_on and spawner.kit.last_hit_kind >= 0:   # name what it hit
		cause = Kit.CAUSES[spawner.kit.last_hit_kind]
	_reset_bonus()   # a crash / the end of the run ends the streak
	hud.clear_bonus()
	screen = SCREEN_OVER
	last_earned = floorf(score)   # the score IS the coins: a crash keeps every one of them
	Save.add_stat("cans", run_cans)
	var meters_run := Tuning.meters(run_distance)
	var prev_best_m: float = float(Save.map_stat(map)["best_distance"])
	var coins_before: float = Save.coins
	last_was_best = last_earned > float(Save.map_stat(map)["best_score"])
	Save.record_run(score)
	last_result = Save.record_map_run(map, meters_run, score)
	last_result["milestones"] = Save.check_milestones()
	hud.show_game_over(header, cause, last_earned, last_was_best, float(Save.map_stat(map)["best_score"]), _result_text(meters_run))
	_results = _build_results(header, cause, meters_run, prev_best_m, coins_before)
	var unlocked_now: Array = last_result["milestones"]
	if not unlocked_now.is_empty():   # a popup for the new perk
		hud.show_combo(Tuning.perk_def(unlocked_now[0]["perk"])["name"], Color(1.0, 0.85, 0.3), "PERK UNLOCKED!")

## What the results screen shows: coins, distance against the best, how far the next map unlock and medal are, the
## milestones just earned, and an upgrade that can be afforded now.
func _build_results(header: String, cause: String, meters_run: float, prev_best_m: float, coins_before: float) -> Dictionary:
	var d := {"header": header, "cause": cause, "coins": last_earned, "meters": meters_run, "best_m": maxf(prev_best_m, 0.0),
			"new_best": bool(last_result.get("new_best_distance", false))}
	d["pct"] = clampf(meters_run / prev_best_m, 0.0, 1.0) if prev_best_m > 0.0 else 1.0
	var best_now: float = Save.map_stat(map)["best_distance"]
	for j in Tuning.maps.size():   # the next map to unlock
		if not Save.maps_unlocked[j]:
			var from_map: int = Tuning.maps[j]["unlock_from"]
			var need: float = Tuning.maps[j]["unlock_meters"]
			var have: float = Save.map_stat(from_map)["best_distance"]
			d["unlock_text"] = "%s to the %s" % [Tuning.fmt_m(maxf(need - have, 0.0)), Tuning.maps[j]["name"]]
			d["unlock_frac"] = clampf(have / maxf(need, 1.0), 0.0, 1.0)
			break
	var medals: Array = Tuning.map_def(map)["medals"]
	for k in medals.size():   # the next medal on this map
		var target: float = medals[k][0]
		if best_now < target:
			d["medal_text"] = "%s to %s  (+%s coins)" % [Tuning.fmt_m(target - best_now), MEDAL_NAMES[k], Tuning.fmt(medals[k][1])]
			d["medal_frac"] = clampf(best_now / target, 0.0, 1.0)
			break
	d["extra"] = _result_extra()
	var best_cost := -1.0   # an upgrade that can be bought now (one that just became affordable first)
	var best_new := false
	for u in Tuning.upgrades:
		var id: String = u["id"]
		if Save.is_maxed(id):
			continue
		var cost := Save.cost_of_next(id)
		if cost > Save.coins:
			continue
		var is_new := cost > coins_before
		if best_cost < 0.0 or (is_new and not best_new) or (is_new == best_new and cost > best_cost):
			best_cost = cost
			best_new = is_new
			d["afford_id"] = id
			d["afford_text"] = "%s  Lv %d  -  %s coins" % [u["name"], Save.level(id) + 1, Tuning.fmt(cost)]
	return d

## The milestone lines for the results screen (medals, unlocks, perks).
func _result_extra() -> String:
	var lines: Array[String] = []
	if last_hit_name != "":
		lines.append("Last hit: %s" % last_hit_name)
	var th = spawner.threats
	if th.kills > 0 or th.bosses_done > 0:
		lines.append("Shot down %d (+%s coins), bosses faced %d" % [th.kills, Tuning.fmt(threat_coins), th.bosses_done])
	for k in last_result.get("medals", []):
		lines.append("%s medal!  +%s coins" % [MEDAL_NAMES[k], Tuning.fmt(Tuning.map_def(map)["medals"][k][1])])
	for j in last_result.get("unlocked", []):
		lines.append("%s unlocked!" % Tuning.map_def(j)["name"])
	for m in last_result.get("milestones", []):
		lines.append("Perk unlocked: %s!" % Tuning.perk_def(m["perk"])["name"])
	return "\n".join(lines)

## The crash sequence, one frame: the plane spins down trailing smoke, debris has popped, the camera eases in, Whiskers
## has ejected; the world rolls to a stop (its own speed ramp, no time scaling). Then the results build up.
func _update_crash(delta: float) -> void:
	if delta <= 0.0:
		return
	_crash_t += delta
	var k := clampf(_crash_t / CRASH_TIME, 0.0, 1.0)
	_cam_ease = smoothstep(0.0, 0.9, _crash_t)
	player._model.rotation = Vector3(_crash_t * 2.5, _crash_t * lerpf(11.0, 5.0, k), _crash_t * 4.0)
	player._model.scale = Vector3.ONE * lerpf(1.0, 0.7, k)
	player.position.y = player.PLANE_Y - 1.8 * k * k
	crash_fx.update(delta, _crash_t, player.position)
	var slow := maxf(1.0 - _crash_t / 1.2, 0.0)
	if slow > 0.0:
		spawner.advance(_crash_speed * slow * delta)
		ground.scroll(_crash_speed * slow * delta)
		spawner.update_hazards(delta)
	fx.wind_update(delta, player.position, false)
	if _crash_t >= CRASH_TIME and not hud.results_visible() and not _results.is_empty():
		hud.show_results(_results)
		sfx.play("pick_open", 0.7)

## ?tune: crash now.
func debug_crash() -> void:
	if alive:
		_end_run(HEADER_CRASH, REASON_OBSTACLE)

## ?tune: show the results screen with sample numbers.
func debug_results() -> void:
	if not alive:
		return
	_end_run(HEADER_CRASH, REASON_OBSTACLE)
	_crash_t = CRASH_TIME

## The extra game-over lines: distance, medals, unlocks.
func _result_text(meters_run: float) -> String:
	var lines: Array[String] = []
	var best: float = Save.map_stat(map)["best_distance"]
	lines.append("%s%s" % [Tuning.fmt_m(meters_run), "  NEW BEST!" if last_result.get("new_best_distance", false) else "  (best %s)" % Tuning.fmt_m(best)])
	for k in last_result.get("medals", []):
		lines.append("%s medal!  +%s coins" % [MEDAL_NAMES[k], Tuning.fmt(Tuning.map_def(map)["medals"][k][1])])
	for j in last_result.get("unlocked", []):
		lines.append("%s unlocked!" % Tuning.map_def(j)["name"])
	for m in last_result.get("milestones", []):
		lines.append("Perk unlocked: %s!" % Tuning.perk_def(m["perk"])["name"])
	return "\n".join(lines)

## How far through the day the run is: 0 = morning, 1 = dusk (?tune can hold it).
func _current_tod() -> float:
	if tod_override >= 0.0:
		return tod_override
	return clampf(elapsed / Tuning.tod_seconds, 0.0, 1.0) if screen == SCREEN_PLAY or screen == SCREEN_OVER else 0.35

## Sky, ambient light and sun for time of day `t` (0..1): morning, the map's own look, sunset, dusk.
func _apply_time_of_day(t: float) -> void:
	if absf(t - _tod_applied) < 0.002:
		return
	_tod_applied = t
	var stops := Tuning.tod_stops
	var i := 0
	while i < stops.size() - 2 and t > stops[i + 1]:
		i += 1
	var k := clampf((t - stops[i]) / maxf(stops[i + 1] - stops[i], 0.001), 0.0, 1.0)
	var tint: Color = Tuning.tod_tint[i].lerp(Tuning.tod_tint[i + 1], k)
	var mix: float = lerpf(Tuning.tod_mix[i], Tuning.tod_mix[i + 1], k)
	_env.background_color = _base_sky.lerp(tint, mix)
	_env.ambient_light_color = _base_ambient.lerp(tint, mix * 0.6)
	_env.ambient_light_energy = lerpf(Tuning.tod_ambient_energy[i], Tuning.tod_ambient_energy[i + 1], k)
	sun.light_color = Tuning.tod_sun[i].lerp(Tuning.tod_sun[i + 1], k)
	sun.light_energy = lerpf(Tuning.tod_sun_energy[i], Tuning.tod_sun_energy[i + 1], k)
	spawner.set_sky_tint(tint, mix)
	ground.set_tint(tint, mix)
	_tod_dark = clampf((t - 0.7) / 0.3, 0.0, 1.0)

## ?tune: jump the time of day (morning, day, sunset, dusk, then back to following the run).
func debug_cycle_tod() -> void:
	var order := [0.0, 0.35, 0.7, 1.0, -1.0]
	var i := order.find(tod_override)
	tod_override = order[(i + 1) % order.size()]
	_apply_time_of_day(_current_tod())

## The map's colours: sky behind everything and the ambient light (the ground, obstacles and clouds
## are the Spawner's).
func _apply_palette() -> void:
	var m := Tuning.map_def(map)
	_base_sky = m["sky"]
	_base_ambient = m["ambient"]
	ground.apply_palette(map, m["ground"])
	_tod_applied = -1.0
	_apply_time_of_day(_current_tod())

## A fuel can was collected at `pos`: refill (never past a full tank) and pop.
func _on_pickup(pos: Vector3, golden: bool = false) -> void:
	run_cans += 1
	sfx.play("pickup", 1.0, 1.25 if golden else 1.0)
	hud.pulse_perk("tailwind")   # (Tailwind boosts what this can earns)
	if combo_on("deadstick") and _gliding:   # Deadstick: a can extends the glide instead of refuelling
		_glide_left += Tuning.deadstick_extend
	else:
		_add_fuel(Tuning.refill_amount())
	if golden:   # Golden Whiskers: fuel plus a big burst of coins
		var gold := Tuning.golden_can_coins * earn_mult()
		score += gold
		hud.coin_pop("+" + Tuning.fmt(gold), camera.unproject_position(pos) + Vector2(0, -60))
		if not DebugFlags.off("sparks"):
			fx.coins(pos)
			fx.whisker(pos)
	var bounty := (Tuning.can_bounty_pay() + picks.value("scavenger")) * earn_mult()   # Can Bounty + Scavenger
	if picks.value("scavenger") > 0.0:
		_callout("scavenger", "Scavenger +%s" % Tuning.fmt(bounty))
		if picks.level("scavenger") >= 3:   # Scavenger 3: each can adds a bonus step
			_add_step(false)
	if bounty > 0.0:
		score += bounty
		hud.coin_pop("+" + Tuning.fmt(bounty), camera.unproject_position(pos))
	if not DebugFlags.off("pickup"):
		fx.pickup(pos)
		hud.fuel_pulse()
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(15)

## Coins of a trail collected: they pay into the run score, the chime climbs along a trail, and a single "+N" pops when the
## trail is done (not one per coin).
func _on_coins(n: int, pos: Vector3) -> void:
	var now := Time.get_ticks_msec()
	_coin_chain = (_coin_chain if now - _coin_last_ms < 700 else 0) + n
	_coin_last_ms = now
	var pay: float = Tuning.trail_coin_value * earn_mult() * n
	score += pay
	run_trail_coins += n
	_coin_acc += pay
	_coin_pop_pos = pos
	sfx.play("coin", 0.8, 1.0 + 0.05 * minf(float(_coin_chain), 12.0))
	if not DebugFlags.off("haptic") and _coin_chain % 4 == 1:
		Input.vibrate_handheld(6)

func _flush_coin_pop() -> void:
	if _coin_acc > 0.0 and Time.get_ticks_msec() - _coin_last_ms > 600:
		hud.coin_pop("+" + Tuning.fmt(_coin_acc), camera.unproject_position(_coin_pop_pos) + Vector2(0, -50))
		_coin_acc = 0.0

## Near miss: raise the bonus and fire every bit of feedback at once. Each effect can be
## switched off from the URL (?nofx=sparks,streaks,flash,popup,trail,haptic,punch) to find out
## which one causes a hitch.
func _on_near_miss(ev: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var whisker: bool = ev.get("whisker", false) or picks.has_boost("whisker_window")   # Whisker Window: every close call counts
	if (combo_on("cloud_surfer") or picks.level("cloud_diver") >= 3) and spawner._cloud_over(player.position.x, player.position.z):   # Cloud Surfer / Cloud Diver 3: under a cloud counts too
		whisker = true
		if picks.level("cloud_diver") >= 3:
			_callout("cloud_diver", "Cloud Diver: Whisker!")
	_mood_until_ms = Time.get_ticks_msec() + 650   # Whiskers is startled
	sfx.play("barnstormer" if ev.get("special", "") == "barnstormer" else ("whoosh_big" if whisker else "whoosh"), 1.0, 1.0 + 0.04 * minf(bonus, 6.0))
	_add_step(whisker)
	hud.pulse_perk("tailwind")
	if whisker and randf() * 100.0 < picks.value("lucky_whiskers"):   # Lucky Whiskers: a can drops ahead
		if spawner.drop_can_ahead(player.position.x, combo_on("golden_whiskers")):
			_callout("lucky_whiskers", "Lucky Whiskers: +can")
	if whisker and picks.level("tailwind") >= 3:   # Tailwind 3: Whiskers refuel
		_add_fuel(Tuning.fuel_max() * 0.04)
		_callout("tailwind", "Tailwind: Whisker refuel!")
	var wash := picks.level("prop_wash")      # Prop Wash: the obstacle you just passed gets shoved aside
	if wash > 0 and ev.get("row") != null:
		spawner.nudge_obstacle(ev["row"], ev["k"], ev["side"], Tuning.prop_wash_push * (1.0 + 0.25 * (wash - 1)))
	Save.add_stat("close_calls")
	if whisker:
		Save.add_stat("whiskers")
	var pay := Tuning.close_call_pay() * earn_mult()   # Close Call Pay: a coin burst
	if pay > 0.0:
		score += pay
		hud.coin_pop("+" + Tuning.fmt(pay), camera.unproject_position(player.position + Vector3(ev["side"] * 1.6, 0.0, 0.9)))
		if not DebugFlags.off("sparks"):
			fx.coins(player.position + Vector3(ev["side"] * 1.0, 0.0, 0.2))
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
	var barnstormer: bool = ev.get("special", "") == "barnstormer"
	if whisker and not DebugFlags.off("sparks"):
		fx.whisker(player.position + Vector3(side * 1.05, 0.0, 0.1))   # the special burst
		if barnstormer:   # ...and one on the other wingtip too
			fx.whisker(player.position + Vector3(-side * 1.05, 0.0, 0.1))
	if not DebugFlags.off("popup"):
		var i := Tuning.popup_tier(bonus)
		var pos := camera.unproject_position(player.position + Vector3(0, 0, -2.0))
		if barnstormer:   # "Barnstormer!" + the number
			hud.popup(Tuning.barnstormer_text + "\n" + Tuning.popup_text(bonus), Tuning.whisker_size, Tuning.barnstormer_color, pos)
		elif whisker:   # "Whisker close!" + the number: bigger, in its own colour
			hud.popup(Tuning.whisker_text + "\n" + Tuning.popup_text(bonus), Tuning.whisker_size, Tuning.whisker_color, pos)
		else:         # regular close call: just the number
			hud.popup(Tuning.popup_text(bonus), Tuning.near_miss_sizes[mini(i, Tuning.near_miss_sizes.size() - 1)],
					Tuning.near_miss_colors[mini(i, Tuning.near_miss_colors.size() - 1)], pos)
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(Tuning.haptic_ms * (2 if whisker else 1))  # no-op where unsupported
	hud.note_near_miss((Time.get_ticks_usec() - t0) / 1000.0)

## A tuning-panel slider changed (or Reset ran): apply anything that needs more than reading the value.
func _on_tuning_changed(property: String) -> void:
	if property.begins_with("ground_"):
		ground._recolor()
	if property == "obstacle_scale":
		spawner.refresh_obstacles()   # rows already on screen change size now

## Without fresh near misses the bonus holds, then steps come off one at a time, the most recent
## first (x2.6 -> x2.5 -> x2.4 -> x2.2 ...), bonus_decay_rate per second, down to x1.
func _decay_bonus(delta: float) -> void:
	if streak <= 0:
		return
	if combo_on("barnstormer") and bonus > 2.0:   # Barnstormer: nothing fades while you are above x2
		return
	_bonus_timer -= delta
	if _bonus_timer > 0.0:
		return
	_decay_acc += Tuning.bonus_decay_rate / (1.0 + picks.value("hot_streak") * 0.01) * delta
	var dropped := false
	while _decay_acc >= 1.0 and not _steps.is_empty():
		if picks.level("hot_streak") >= 3 and bonus >= 2.0 and _bonus_without_last() < 2.0:   # Hot Streak 3: the bonus never drops below x2
			_decay_acc = 0.0
			_callout("hot_streak", "Hot Streak: x2 holds!")
			break
		_decay_acc -= 1.0
		_steps.remove_at(_steps.size() - 1)   # the newest step goes first, with the amount it earned
		dropped = true
	if dropped:
		_refresh_bonus()
		hud.set_bonus(bonus, hud.BONUS_SHRINK)   # shrinks each step: the bonus fades if you play safe

## The gates to put in this run: your best distance, the next medal, the next map unlock (this map's).
func _goal_list() -> Array:
	var out: Array = []
	var best: float = Save.map_stat(map)["best_distance"]
	if best > 0.0:
		out.append({"kind": "best", "meters": best, "text": "BEST  %s" % Tuning.fmt_m(best), "color": "best"})
	var medals: Array = Tuning.map_def(map)["medals"]
	var earned := int(Save.map_stat(map)["medals"])
	if earned < medals.size():   # the next medal
		out.append({"kind": "medal", "meters": float(medals[earned][0]), "text": "%s  %s" % [MEDAL_NAMES[earned].to_upper(), Tuning.fmt_m(medals[earned][0])], "color": MEDAL_NAMES[earned].to_lower()})
	for j in Tuning.maps.size():
		if not Save.maps_unlocked[j] and int(Tuning.maps[j]["unlock_from"]) == map:
			out.append({"kind": "unlock", "meters": float(Tuning.maps[j]["unlock_meters"]), "text": "%s  %s" % [String(Tuning.maps[j]["name"]).to_upper(), Tuning.fmt_m(Tuning.maps[j]["unlock_meters"])], "color": "unlock"})
			break
	return out

## A goal gate was passed: celebrate.
func _on_goal_reached(kind: String, text: String, color: Color) -> void:
	var title := "NEW BEST!" if kind == "best" else (text.get_slice("  ", 0) + " MEDAL!" if kind == "medal" else text.get_slice("  ", 0) + " UNLOCKED!")
	last_cue = title
	hud.show_combo(title, color, text.get_slice("  ", 1))
	if not DebugFlags.off("sparks"):
		fx.whisker(player.position + Vector3(0.0, 0.0, -0.4))
		fx.coins(player.position + Vector3(-1.0, 0.0, 0.2))
		fx.coins(player.position + Vector3(1.0, 0.0, 0.2))
	hud.flash(Color(color.r, color.g, color.b, 1.0))
	sfx.play("barnstormer", 0.9, 1.1)
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(60)

## The perks and gear the plane carries, drawn on it.
func _refresh_plane_items() -> void:
	var gear: Array = []
	for id in ["nine_lives", "reserve_tank", "magnet", "cloud_eye", "steady_nerves", "head_start"]:
		if Save.is_equipped(id):
			gear.append(id)
	player.set_items(picks.levels, gear)

## The bonus the streak would have if its newest step came off.
func _bonus_without_last() -> float:
	var total := 1.0
	for i in _steps.size() - 1:
		total += _steps[i]
	return total

## A perk or gear item acted: a little icon and a line pop up (each item at most every couple of seconds).
func _callout(id: String, text: String) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_callout_ms.get(id, -100000)) < 1800:
		return
	_callout_ms[id] = now
	last_callout = text
	if not DebugFlags.off("popup"):
		hud.callout(id, text)

## A close call advances the streak by one step: the next table step, doubled for a Whisker close,
## and never more than the room left under the cap (so every step in the streak is worth what it shows).
func _add_step(whisker: bool) -> void:
	var room := Tuning.bonus_cap_now() - (1.0 + _steps_sum())
	if room > 0.0005:
		_steps.append(minf(Tuning.step_for(_steps.size()) * (2.0 if whisker else 1.0), room))
	_refresh_bonus()

func _steps_sum() -> float:
	var total := 0.0
	for v in _steps:
		total += v
	return total

func _refresh_bonus() -> void:
	streak = _steps.size()
	bonus = Tuning.bonus_for_sum(_steps_sum())

## A crash, the end of a run or a restart: no streak, no bonus.
func _reset_bonus() -> void:
	_steps.clear()
	streak = 0
	bonus = 1.0
	_bonus_timer = 0.0
	_decay_acc = 0.0

## Camera tilted `camera_tilt_deg` away from straight down (so front faces show), placed so the
## screen centre always looks at world z = 0. Screen-up = world -Z.
func _update_camera() -> void:
	var tilt := deg_to_rad(Tuning.camera_tilt_deg)
	camera.size = Tuning.ortho_size * (1.0 - 0.2 * _cam_ease)   # (a crash: the camera eases in toward the plane)
	camera.position = Vector3(player.position.x * 0.55 * _cam_ease, 0, player.position.z * 0.35 * _cam_ease) + Vector3(0, cos(tilt), sin(tilt)) * 30.0
	camera.rotation = Vector3(-(PI / 2 - tilt), 0, 0)
	if _shake_t > 0.0:   # a hit: the screen shakes and settles
		var k := _shake_t / maxf(Tuning.hit_shake_time, 0.01)
		camera.position += Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * Tuning.hit_shake_amount * k * k

## Screen spans z = -half .. +half (stretched slightly by the camera tilt).
func _half_height() -> float:
	var vp := get_viewport().get_visible_rect().size
	return Tuning.ortho_size * 0.5 * vp.y / vp.x / cos(deg_to_rad(Tuning.camera_tilt_deg))

## World z where the first row of a run starts, so that it reaches the plane after about
## opening_seconds at the start speed and ramp. If that would put it on screen it starts just above
## the top edge instead (rows never pop in).
func _first_row_z(half_h: float) -> float:
	var t := Tuning.opening_seconds
	var m := Tuning.map_def(map)
	var travel: float = Tuning.base_speed * m["speed_mult"] * t + 0.5 * Tuning.speed_ramp * m["ramp_mult"] * t * t
	return minf(player.position.z - travel, -(half_h + 1.0))

## The plane may use the bottom `plane_zone_fraction` of the screen. The visible height
## depends on the device aspect (width is fixed), so work it out from the viewport.
func _update_plane_zone() -> void:
	var half_h := _half_height()
	var bottom := half_h - Tuning.plane_bottom_margin
	var top := half_h - 2.0 * half_h * Tuning.plane_zone_fraction
	player.set_zone(top, bottom)
	spawner.kit.screen_top_z = -half_h

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
	if not sfx.unlocked and ((event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed)):
		sfx.unlock()
	# Barrel Roll: a double tap (or double click) during a run.
	if screen == SCREEN_PLAY and alive and not _picking:
		var tapped: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
		if tapped:
			var now := Time.get_ticks_msec()
			var pos: Vector2 = event.position
			if now - _last_tap_ms <= Tuning.roll_double_tap_ms and pos.distance_to(_last_tap_pos) < 140.0:
				try_roll()
				_last_tap_ms = -10000
			else:
				_last_tap_ms = now
				_last_tap_pos = pos
	# A tap on the results screen skips its build-up (PLAY AGAIN restarts).
	if screen == SCREEN_OVER and event is InputEventScreenTouch and event.pressed and hud.results_visible():
		hud.skip_results()

## PLAY AGAIN on the results screen.
func _on_play_again() -> void:
	if screen == SCREEN_OVER and Time.get_ticks_msec() / 1000.0 - _death_time > 0.4:
		restart()

## Everything showing right now, by name: the HUD's screens and overlays plus the pick screen, the tuning panel, the crash
## sequence, the goal gates and the airstrip. The tests assert exactly the expected set after every transition.
func visible_screens() -> PackedStringArray:
	var out: PackedStringArray = hud.visible_overlays()
	if pick_screen.is_shown() and pick_screen.visible:
		out.append("pick")
	if tune_panel and tune_panel.is_open:
		out.append("tune")
	if crash_fx.active:
		out.append("crash")
	for gate in goals._gates:
		if (gate["root"] as Node3D).visible:
			out.append("goal_gate")
			break
	if ground.airstrip.visible:
		out.append("airstrip")
	return out

## Going to a menu screen: nothing of the last run may stay showing behind it (the crash, the goal gates, the airstrip,
## the shadows, the zoomed camera) and the pick screen is surely closed.
func _leave_world() -> void:
	crash_fx.stop()
	goals.hide_all()
	ground.stop_airstrip()
	shadows.hide_all()
	_crash_t = -1.0
	_cam_ease = 0.0
	if _picking or get_tree().paused:
		_picking = false
		pick_screen.hide_cards()
		get_tree().paused = false
		sfx.duck(false)
	hud.reset_transients()

## The start screen: the world waits (nothing scrolls) behind it.
func _show_menu() -> void:
	_leave_world()
	screen = SCREEN_MENU
	alive = false
	sfx.stop_run()
	sfx.set_phase(0)
	sfx.start_music()
	hud.set_volume_sliders(Save.audio_music, Save.audio_sound)
	hud.show_menu()

func _open_logbook() -> void:
	_leave_world()
	screen = SCREEN_LOGBOOK
	alive = false
	hud.show_logbook()

func _open_hangar() -> void:
	_leave_world()
	screen = SCREEN_HANGAR
	alive = false
	hud.show_hangar()

## A Hangar buy button: the effect applies from the next run (the fuel in the tank right now is untouched).
func _buy(id: String) -> void:
	Save.buy(id)   # (the Hangar redraws itself from Save.changed)

func _setup_environment() -> void:
	var env := Environment.new()
	_env = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.26, 0.34)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.9)
	env.ambient_light_energy = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
