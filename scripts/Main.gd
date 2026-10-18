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
var run_cans := 0       # fuel cans collected this run
var last_earned := 0.0  # coins the last run earned (its score)
var coin_mult := 1.0    # everything earned this run is multiplied by this (map multiplier x Coin Value)
var lives := 0          # hits the plane can still survive this run (Nine Lives)
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
var _second_wind_used := false
var _combos := {}                     # combo id -> true: the combos that have switched on this run
var _crates_broken := 0
var _extra_picks := 0                 # purple crates broken: instant extra picks waiting to be shown
var _pick_is_extra := false
var _last_pick_time := 0.0             # run time of the latest pick (?perf shows the time since)
var _pick_gap_sum := 0.0               # ...and the sum of the gaps (run start -> first pick -> ...) for the average
var _pick_count := 0               # crates broken this run (Cat's Cradle counts them)

func _ready() -> void:
	Engine.max_physics_steps_per_frame = 1   # no physics here: make sure a stall can never trigger catch-up steps
	fuel = Tuning.fuel_max()
	add_child(fx)
	add_child(trail)
	add_child(picks)
	add_child(pick_screen)
	pick_screen.chosen.connect(_on_pick_chosen)
	picks.changed.connect(func(): hud.set_perks(picks.levels))
	spawner.bump.connect(_on_bump)
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
	spawner.prewarm_show(not DebugFlags.off("flash"), not DebugFlags.off("clouds"))
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
	pick_screen.hide_cards()
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
	score = 0.0
	coin_mult = Tuning.map_coin_mult[map] * Tuning.coin_value_mult()
	lives = int(Tuning.gear_value("nine_lives"))
	reserve_left = int(Tuning.gear_value("reserve_tank"))
	_invuln = 0.0
	_glide_left = 0.0
	_gliding = false
	_second_wind_used = false
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
	spawner.chain_nudges = false
	spawner.crate_shower_rows = 0
	_reset_bonus()
	var head := Tuning.gear_value("head_start")   # Head Start: begin at x1.5 / x2 (it fades like any bonus)
	if head > 1.0:
		_steps.append(head - 1.0)
		_refresh_bonus()
		_bonus_timer = Tuning.bonus_hold_time
		_decay_acc = 1.0
	elapsed = 0.0
	_kit_speed = Tuning.base_speed
	alive = true
	spawner.run_time = 0.0
	fuel = Tuning.fuel_max()
	fx.clear()
	trail.clear()
	hud.reset_for_run()
	hud.set_lives(lives)
	hud.set_next(picks.next_pick)
	hud.set_perks(picks.levels)   # (?tune can grant perks for every run)
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
				_paused_since_ms = Time.get_ticks_msec()
				_note_event("window went to the background")
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			if _suspended:
				_suspended = false
				_paused_total_ms += Time.get_ticks_msec() - _paused_since_ms
				_skip_frames = Tuning.resume_skip_frames
				player.clear_input()   # (the drag that piled up while away must not jump the plane)
				_note_event("window came back")

## Seconds of this run on the wall clock, without the time spent paused.
func run_wall_time() -> float:
	return maxf((Time.get_ticks_msec() - _run_start_ms - _paused_total_ms) / 1000.0, 0.0)

func _process(raw_delta: float) -> void:
	_update_camera()
	_update_plane_zone()
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
	picks.update(delta)
	var tail := 1.0 + picks.value("tailwind") * 0.01   # Tailwind: more speed and more coins
	var speed := Tuning.map_speed(map, elapsed) * tail
	if spawner.kit_on:   # Countryside: no ramp, only the steps a BREATHER brings (eased in)
		_kit_speed = move_toward(_kit_speed, spawner.stepped_speed(spawner.speed_steps), Tuning.speed_step_rate * delta)
		speed = _kit_speed * tail
	var step := speed * delta
	score += step * Tuning.coins_per_unit * distance_pay() * earn_mult()
	spawner.near_miss_scale = 1.0 + picks.value("daredevil") * 0.01
	spawner.plane_z = player.position.z   # clouds fade as they near the plane,
	spawner.run_time = elapsed            # start late in the run,
	spawner.scroll_speed = speed          # and come more often the faster it goes
	spawner.plane_x = player.position.x
	spawner.advance(step)
	spawner.update_hazards(delta)
	run_distance += step
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
		fuel = maxf(fuel - Tuning.drain_rate() * (1.0 - picks.value("fuel_miser") * 0.01) * delta, 0.0)
	var cd := picks.value("cloud_diver")      # Cloud Diver: fuel back while under a cloud
	if cd > 0.0 and spawner._cloud_over(plane.x, plane.y):
		_add_fuel(cd * delta)

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
	spawner.chain_nudges = combo_on("wingwalker")
	if reach > 0.0:
		spawner.pull_cans(plane, reach, Tuning.magnet_pull_speed * delta)
	if _invuln > 0.0:
		_invuln = maxf(_invuln - delta, 0.0)
		player.set_flicker(_invuln > 0.0 and int(_invuln * 14.0) % 2 == 0)   # the plane sputters
	if _invuln <= 0.0 and not DebugFlags.god and spawner.hazards.hit(player.position.x):   # lightning
		if _can_absorb():
			_absorb_hit(plane, caps)
		else:
			_end_run(HEADER_STRUCK, REASON_STRUCK)
			return
	var battering: bool = picks.level("battering_ram") > 0                          # Battering Ram: any touch breaks a crate
	var ram_ok: bool = Tuning.ram_speed <= 0.0 or player.velocity.y < -Tuning.ram_speed   # (optional extra: moving up fast enough)
	var from: Vector2 = player.prev_xz
	var steps := clampi(ceili(from.distance_to(plane) / SWEEP_STEP), 1, MAX_SWEEP_STEPS)
	for i in range(1, steps + 1):
		var p: Vector2 = from.lerp(plane, float(i) / steps)
		for b in spawner.break_crates(p, caps, battering, ram_ok, from.y):   # a crate in the way breaks if it may
			_on_crate_break(b["kind"], b["pos"])
		if _invuln <= 0.0 and not DebugFlags.god and spawner.hits(p, caps):
			if _can_absorb():   # Nine Lives / Shield / Patch: the plane takes the hit and keeps flying
				_absorb_hit(p, caps)
				continue
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
			_end_run(HEADER_CRASH, REASON_CRATE if spawner.last_hit_crate else REASON_OBSTACLE)
			return
		for ev in spawner.update_near_misses(p, caps):
			_on_near_miss(ev)
		var cans: Array[Vector3] = spawner.collect_cans(p, caps)   # a can grabbed in the last moment still saves you
		for ci in cans.size():
			_on_pickup(cans[ci], spawner.picked_golden[ci])
	hud.set_fuel(fuel / Tuning.fuel_max())
	_check_fuel(delta)
	if not _picking:
		var due := score >= picks.next_pick
		if picks.picks_taken == 0 and picks.enabled:   # the first pick lives in a time window
			due = (due and elapsed >= Tuning.first_pick_min_seconds) or elapsed >= Tuning.first_pick_max_seconds
		if due:
			_begin_pick(false)
		elif _extra_picks > 0:
			_begin_pick(true)   # (a purple crate's pick is extra: it does not use up the score)

## Empty tank: Reserve Tank refills it; Glide (a perk) keeps you flying for a few seconds; else the run ends.
## Second Wind refills a share of the tank once when it runs low.
func _check_fuel(delta: float) -> void:
	var sw := picks.value("second_wind")
	if sw > 0.0 and not _second_wind_used and fuel > 0.0 and fuel < Tuning.fuel_max() * Tuning.second_wind_below:
		_second_wind_used = true
		_add_fuel(Tuning.fuel_max() * sw * 0.01)
		hud.fuel_pulse()
	if fuel > 0.0:
		_gliding = false
		_glide_left = 0.0
		return
	if reserve_left > 0:   # Reserve Tank: the tank refills itself
		reserve_left -= 1
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
		if _glide_left > 0.0:
			return
	_end_run(HEADER_FUEL, REASON_FUEL)

## Coins per unit flown at the current bonus: bonus - bonus_pay_offset (x1 = 0.2, x2 = 1.2, x3 = 2.2).
func distance_pay() -> float:
	return maxf(bonus - Tuning.bonus_pay_offset, 0.0) if Tuning.score_uses_bonus else 1.0

## Everything earned is multiplied by this: the permanent multiplier (map x Coin Value), Tailwind, Double Coins.
func earn_mult() -> float:
	return coin_mult * (1.0 + picks.value("tailwind") * 0.01) * (2.0 if picks.has_boost("double_coins") else 1.0)

func _can_absorb() -> bool:
	return lives > 0 or picks.has_boost("shield")

# ---------- In-run picks ----------

## The score reached the next pick: pause the game completely, deal three cards.
func _begin_pick(extra: bool = false) -> void:
	_picking = true
	_paused_since_ms = Time.get_ticks_msec()
	_note_event("pick screen opened")
	_pick_is_extra = extra
	if extra:
		_extra_picks = maxi(_extra_picks - 1, 0)
	_pick_cards = picks.roll(fuel / Tuning.fuel_max(), Tuning.pick_cards)
	if tune_panel:
		tune_panel.set_available(false)
	var hints: Array = []
	for c in _pick_cards:
		hints.append(picks.would_complete(c))   # a card that would complete a combo is highlighted
	pick_screen.show_cards(_pick_cards, hints)
	get_tree().paused = true

func _on_pick_chosen(i: int) -> void:
	if i < 0 or i >= _pick_cards.size():
		return
	var card := _pick_cards[i]
	pick_screen.hide_cards()
	get_tree().paused = false
	_picking = false
	_paused_total_ms += Time.get_ticks_msec() - _paused_since_ms   # (the pause does not count as run time)
	_skip_frames = Tuning.resume_skip_frames                       # and nothing catches up after it
	_note_event("pick resume")
	if tune_panel:
		tune_panel.set_available(true)
	_pick_gap_sum += elapsed - _last_pick_time
	_last_pick_time = elapsed
	_pick_count += 1
	_apply_card(card)
	if not _pick_is_extra:
		picks._bag_score = score
		picks.advance(score, elapsed)
	_pick_is_extra = false
	hud.set_next(picks.next_pick)
	_check_combos()

## Take a card: a perk levels up, a boost starts, a supply happens at once.
func _apply_card(card: Dictionary) -> void:
	picks.take(card)
	if card["kind"] != "supply":
		return
	match card["id"]:
		"full_tank":
			fuel = Tuning.fuel_max()
			hud.fuel_pulse()
		"patch":
			lives += 1
			hud.set_lives(lives)
		"coin_bag":
			var amount := picks.coin_bag_amount()
			score += amount
			hud.coin_pop("+" + Tuning.fmt(amount), camera.unproject_position(player.position + Vector3(0, 0, -2.0)))
		"crate_shower":
			spawner.crate_shower_rows = Tuning.crate_shower_rows

## Prop Wash: a shoved obstacle bumped another one: coins (each link of a Wingwalker chain pays one more time).
func _on_bump(pos: Vector3, depth: int) -> void:
	var pay := picks.value("prop_wash") * earn_mult() * (1.0 + depth)
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
	var ram := picks.level("battering_ram")
	var gold_touch := maxf(picks.value("golden_touch"), 1.0)   # Golden Touch: crates pay x2 / x3 / x4
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
	if combo_on("cats_cradle") and _crates_broken % Tuning.cradle_crates == 0:
		lives += 1
		hud.set_lives(lives)

## A hit the plane survives: sputter (brief invulnerability), keep going, and the close-call streak
## drops (Steady Nerves keeps half or all of it). The obstacle it hit gives no close-call credit.
func _absorb_hit(p: Vector2, caps: PackedFloat32Array) -> void:
	if picks.has_boost("shield"):   # the Shield goes first
		picks.boosts.erase("shield")
		picks.changed.emit()
	else:
		lives -= 1
	_invuln = Tuning.hit_invulnerable_time
	spawner.mark_hit_rows(p, caps)
	var keep := Tuning.gear_value("steady_nerves")
	_steps.resize(int(round(_steps.size() * keep)))
	_refresh_bonus()
	if keep < 1.0:
		_bonus_timer = Tuning.bonus_hold_time
		hud.set_bonus(bonus, hud.BONUS_SHRINK)
	hud.set_lives(lives)
	if not DebugFlags.off("sparks"):
		fx.sparks(player.position + Vector3(-1.05, 0.0, 0.1), -1)
		fx.sparks(player.position + Vector3(1.05, 0.0, 0.1), 1)
	if not DebugFlags.off("haptic"):
		Input.vibrate_handheld(Tuning.haptic_ms * 3)

## End the run: freeze the plane and show the game-over screen with what ended it.
func _end_run(header: String, reason: String) -> void:
	alive = false
	_death_time = Time.get_ticks_msec() / 1000.0
	player.crash()
	player.set_flicker(false)
	_reset_bonus()   # a crash / the end of the run ends the streak
	hud.clear_bonus()
	screen = SCREEN_OVER
	last_earned = floorf(score)   # the score IS the coins: a crash keeps every one of them
	Save.add_stat("cans", run_cans)
	var meters_run := Tuning.meters(run_distance)
	last_was_best = last_earned > float(Save.map_stat(map)["best_score"])
	Save.record_run(score)
	last_result = Save.record_map_run(map, meters_run, score)
	last_result["milestones"] = Save.check_milestones()
	hud.show_game_over(header, reason, last_earned, last_was_best, float(Save.map_stat(map)["best_score"]), _result_text(meters_run))
	var unlocked_now: Array = last_result["milestones"]
	if not unlocked_now.is_empty():   # a popup for the new perk
		hud.show_combo(Tuning.perk_def(unlocked_now[0]["perk"])["name"], Color(1.0, 0.85, 0.3), "PERK UNLOCKED!")

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

## The map's colours: sky behind everything and the ambient light (the ground, obstacles and clouds
## are the Spawner's).
func _apply_palette() -> void:
	var m := Tuning.map_def(map)
	_env.background_color = m["sky"]
	_env.ambient_light_color = m["ambient"]

## A fuel can was collected at `pos`: refill (never past a full tank) and pop.
func _on_pickup(pos: Vector3, golden: bool = false) -> void:
	run_cans += 1
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
	if bounty > 0.0:
		score += bounty
		hud.coin_pop("+" + Tuning.fmt(bounty), camera.unproject_position(pos))
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
	var whisker: bool = ev.get("whisker", false) or picks.has_boost("whisker_window")   # Whisker Window: every close call counts
	if combo_on("cloud_surfer") and spawner._cloud_over(player.position.x, player.position.z):   # Cloud Surfer: under a cloud counts too
		whisker = true
	_add_step(whisker)
	if whisker and randf() * 100.0 < picks.value("lucky_whiskers"):   # Lucky Whiskers: a can drops ahead
		spawner.drop_can_ahead(player.position.x, combo_on("golden_whiskers"))
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
	_decay_acc += Tuning.bonus_decay_rate * (1.0 - picks.value("hot_streak") * 0.01) * delta
	var dropped := false
	while _decay_acc >= 1.0 and not _steps.is_empty():
		_decay_acc -= 1.0
		_steps.remove_at(_steps.size() - 1)   # the newest step goes first, with the amount it earned
		dropped = true
	if dropped:
		_refresh_bonus()
		hud.set_bonus(bonus, hud.BONUS_SHRINK)   # shrinks each step: the bonus fades if you play safe

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
	# Tap to restart (small delay so the crash-causing drag can't restart instantly).
	if screen == SCREEN_OVER and event is InputEventScreenTouch and event.pressed \
			and Time.get_ticks_msec() / 1000.0 - _death_time > 0.5 and not hud.over_hangar_hit(event.position):
		restart()

## The start screen: the world waits (nothing scrolls) behind it.
func _show_menu() -> void:
	screen = SCREEN_MENU
	alive = false
	hud.show_menu()

func _open_logbook() -> void:
	screen = SCREEN_LOGBOOK
	alive = false
	hud.show_logbook()

func _open_hangar() -> void:
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
