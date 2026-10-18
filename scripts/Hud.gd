extends CanvasLayer
## Score label while flying; "crashed" panel with the final score and restart hint.

var _score: Label
var _over: Label
var _bonus_label: Label
const BONUS_NONE := 0     # set_bonus() animations: just show the new value...
const BONUS_PUNCH := 1    # ...pop up bigger and settle (the bonus went UP)...
const BONUS_SHRINK := 2   # ...or shrink and settle (the bonus faded one step)
var _bonus_anim := BONUS_NONE
var _bonus_anim_ms := -10000         # when the bonus label's animation started
var _bonus_fading_out := false       # the bonus is back to x1: shrink the old label away, then clear it
var _bonus_shown := 1.0                # the bonus the label currently shows
var _score_bonus := 1.0                # drives the score label's tint, size and ticking
var _last_points := 0
var _score_tick_ms := -10000         # when the score number last ticked up while a bonus was active
## Menu buttons, wired up by Main.
signal play_pressed
signal hangar_pressed
signal back_pressed
signal upgrade_pressed(id: String)
var _menu: Control                   # start screen: title, best score, coins, PLAY, HANGAR
var _menu_best: Label
var _menu_coins: Label
var _hangar: Control                 # upgrade screen
var _hangar_coins: Label
var _hangar_rows: Array[Dictionary] = []   # per upgrade: {id, title, effect, buy}
var _over_hangar: Button             # small "Hangar" button on the game-over screen
const POPUP_POOL := 4            # labels reused for "Close!" popups
var _pop_labels: Array[Label] = []
var _pop_born := PackedInt64Array()   # real ms when started; 0 = idle
var _pop_base_y := PackedFloat32Array()
var _next_pop := 0
var _fuel_bg: ColorRect
var _fuel_fill: ColorRect
var _fuel_label: Label
var _fuel_frac := 1.0
var _fuel_pulse_ms := -10000        # when a pickup last made the gauge flash
const FUEL_BAR_W := 560.0
const FUEL_BAR_H := 30.0
const FUEL_BAR_TOP := 255.0
const FUEL_PULSE_TIME := 0.35
var _splash: Control
var _perf_label: Label
var _perf_worst := 0.0        # worst frame time (ms) in the current 3 s window
var _perf_window_start := 0
var _perf_shown := 0.0
var _nm_count := 0             # near misses seen (for the ?perf log)
var _nm_handler_ms := 0.0      # time the near-miss code took on the CPU (ms)
var _nm_frames_left := 0       # frames still being watched after a near miss
var _nm_worst := 0.0           # slowest of those frames (ms)
var _nm_log: Array[String] = []  # last few "#n code X ms, next frames worst Y ms" lines
const PUNCH_TIME := 0.28
const SHRINK_TIME := 0.6
const TICK_TIME := 0.12
const POPUP_TIME := 0.9

func _ready() -> void:
	_score = _make_label(72)
	_score.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_score.offset_top = 80
	_bonus_label = _make_label(64)
	_bonus_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bonus_label.offset_top = 170
	clear_bonus()
	_build_fuel_gauge()
	for i in POPUP_POOL:
		var l := _make_label(64)
		l.visible = false
		_pop_labels.append(l)
	_pop_born.resize(POPUP_POOL)
	_pop_base_y.resize(POPUP_POOL)
	_build_stamp()
	_over = _make_label(80)
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_over.visible = false
	_build_menus()
	Save.changed.connect(refresh_menus)
	refresh_menus()

# ---------- Start screen, Hangar, game-over button ----------
# All of it is created once here; screens are only shown / hidden afterwards.

func _make_button(text: String, font_size: int, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.custom_minimum_size = size
	b.size = size
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(24)
		sb.bg_color = {"normal": Color(0.2, 0.55, 0.9), "hover": Color(0.25, 0.6, 0.95), "pressed": Color(0.12, 0.4, 0.75),
				"disabled": Color(0.22, 0.26, 0.34), "focus": Color(0.2, 0.55, 0.9)}[state]
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_disabled_color", Color(0.6, 0.65, 0.75))
	b.focus_mode = Control.FOCUS_NONE
	return b

func _place(c: Control, x: float, y: float, w: float, h: float) -> void:
	c.position = Vector2(x, y)
	c.size = Vector2(w, h)

func _screen_label(parent: Control, text: String, font_size: int, x: float, y: float, w: float, h: float, align: HorizontalAlignment) -> Label:
	var l := _make_label(font_size)
	remove_child(l)
	parent.add_child(l)
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_place(l, x, y, w, h)
	return l

func _screen_root() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # taps on the screen don't reach the game
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.16, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	root.visible = false
	add_child(root)
	return root

func _build_menus() -> void:
	const W := 1080.0
	_menu = _screen_root()
	_screen_label(_menu, "SKY DODGE", 140, 0, 330, W, 180, HORIZONTAL_ALIGNMENT_CENTER)
	_menu_best = _screen_label(_menu, "", 56, 0, 600, W, 90, HORIZONTAL_ALIGNMENT_CENTER)
	_menu_coins = _screen_label(_menu, "", 56, 0, 690, W, 90, HORIZONTAL_ALIGNMENT_CENTER)
	var play := _make_button("PLAY", 84, Vector2(560, 170))
	_place(play, (W - 560.0) * 0.5, 920, 560, 170)
	play.pressed.connect(func(): play_pressed.emit())
	_menu.add_child(play)
	var hangar := _make_button("HANGAR", 64, Vector2(560, 140))
	_place(hangar, (W - 560.0) * 0.5, 1140, 560, 140)
	hangar.pressed.connect(func(): hangar_pressed.emit())
	_menu.add_child(hangar)

	_hangar = _screen_root()
	_screen_label(_hangar, "HANGAR", 100, 0, 70, W, 130, HORIZONTAL_ALIGNMENT_CENTER)
	_hangar_coins = _screen_label(_hangar, "", 56, 0, 200, W, 90, HORIZONTAL_ALIGNMENT_CENTER)
	for i in Tuning.upgrades.size():
		var id: String = Tuning.upgrades[i]["id"]
		var y := 320.0 + 250.0 * i
		var panel := ColorRect.new()
		panel.color = Color(1, 1, 1, 0.07)
		_place(panel, 40, y, W - 80.0, 230)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hangar.add_child(panel)
		var title := _screen_label(_hangar, "", 50, 70, y + 12, 600, 80, HORIZONTAL_ALIGNMENT_LEFT)
		var effect := _screen_label(_hangar, "", 42, 70, y + 100, 620, 110, HORIZONTAL_ALIGNMENT_LEFT)
		effect.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
		var buy := _make_button("", 50, Vector2(290, 150))
		_place(buy, W - 40.0 - 310.0, y + 40, 290, 150)
		buy.pressed.connect(func(): upgrade_pressed.emit(id))
		_hangar.add_child(buy)
		_hangar_rows.append({"id": id, "title": title, "effect": effect, "buy": buy})
	var back := _make_button("BACK", 56, Vector2(380, 120))
	_place(back, 70, 1720, 380, 120)
	back.pressed.connect(func(): back_pressed.emit())
	_hangar.add_child(back)
	var go := _make_button("PLAY", 56, Vector2(380, 120))
	_place(go, W - 70.0 - 380.0, 1720, 380, 120)
	go.pressed.connect(func(): play_pressed.emit())
	_hangar.add_child(go)

	_over_hangar = _make_button("Hangar", 48, Vector2(320, 100))
	_over_hangar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_over_hangar.offset_left = -160.0
	_over_hangar.offset_right = 160.0
	_over_hangar.offset_top = -330.0
	_over_hangar.offset_bottom = -230.0
	_over_hangar.visible = false
	_over_hangar.pressed.connect(func(): hangar_pressed.emit())
	add_child(_over_hangar)

## Re-read the save into the start screen and the Hangar (called whenever the save changes).
func refresh_menus() -> void:
	if _menu == null:
		return
	_menu_best.text = "Best: %d" % Save.high_score
	_menu_coins.text = "Coins: %d" % Save.coins
	_hangar_coins.text = "Coins: %d" % Save.coins
	for row in _hangar_rows:
		var id: String = row["id"]
		var lv := Save.level(id)
		var u := Tuning.upgrade_def(id)
		(row["title"] as Label).text = "%s   Lv %d/%d" % [u["name"], lv, u["max_level"]]
		(row["effect"] as Label).text = Tuning.upgrade_text(id, lv)
		var b := row["buy"] as Button
		b.text = "MAX" if Save.is_maxed(id) else "%d coins" % Save.cost_of_next(id)
		b.disabled = not Save.can_buy(id)

func show_menu() -> void:
	refresh_menus()
	_hangar.visible = false
	_over_hangar.visible = false
	_over.visible = false
	_menu.visible = true

func show_hangar() -> void:
	refresh_menus()
	_menu.visible = false
	_over_hangar.visible = false
	_over.visible = false
	_hangar.visible = true

func hide_menus() -> void:
	_menu.visible = false
	_hangar.visible = false
	_over_hangar.visible = false

## Is a touch at `pos` on the game-over "Hangar" button? (Main uses it so that tap doesn't restart.)
func over_hangar_hit(pos: Vector2) -> bool:
	return _over_hangar.visible and _over_hangar.get_global_rect().has_point(pos)

## The play-time readouts (score, bonus, fuel gauge) only show while a run is on screen.

## Fuel gauge under the bonus: dark trough + a fill that shrinks, green -> amber -> red.
func _build_fuel_gauge() -> void:
	_fuel_bg = ColorRect.new()
	_fuel_bg.color = Color(0, 0, 0, 0.45)
	_fuel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fuel_fill = ColorRect.new()
	_fuel_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in [_fuel_bg, _fuel_fill]:
		r.anchor_left = 0.5
		r.anchor_right = 0.5
		r.offset_top = FUEL_BAR_TOP
		r.offset_bottom = FUEL_BAR_TOP + FUEL_BAR_H
		add_child(r)
	_fuel_bg.offset_left = -FUEL_BAR_W * 0.5 - 4.0
	_fuel_bg.offset_right = FUEL_BAR_W * 0.5 + 4.0
	_fuel_bg.offset_top = FUEL_BAR_TOP - 4.0
	_fuel_bg.offset_bottom = FUEL_BAR_TOP + FUEL_BAR_H + 4.0
	_fuel_label = _make_label(26)
	_fuel_label.text = "FUEL"
	_fuel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fuel_label.anchor_left = 0.5
	_fuel_label.anchor_right = 0.5
	_fuel_label.offset_left = -FUEL_BAR_W * 0.5 - 140.0
	_fuel_label.offset_right = -FUEL_BAR_W * 0.5 - 16.0
	_fuel_label.offset_top = FUEL_BAR_TOP - 4.0
	set_fuel(1.0)

## Show the tank level (0..1).
func set_fuel(frac: float) -> void:
	_fuel_frac = clampf(frac, 0.0, 1.0)
	_fuel_fill.offset_left = -FUEL_BAR_W * 0.5
	_fuel_fill.offset_right = -FUEL_BAR_W * 0.5 + FUEL_BAR_W * _fuel_frac

## A pickup: the gauge flashes bright and swells for a moment.
func fuel_pulse() -> void:
	_fuel_pulse_ms = Time.get_ticks_msec()

func _update_fuel_look(now: int) -> void:
	var c: Color
	if _fuel_frac > 0.5:
		c = Color(0.25, 0.9, 0.35)
	elif _fuel_frac > Tuning.fuel_low_fraction:
		c = Color(1.0, 0.75, 0.15)
	else:
		c = Color(1.0, 0.2, 0.15)
		if int(now / 180) % 2 == 0:   # low fuel: blink
			c = c.lightened(0.45)
	var pt := clampf((now - _fuel_pulse_ms) / 1000.0 / FUEL_PULSE_TIME, 0.0, 1.0)
	c = c.lerp(Color.WHITE, 0.7 * (1.0 - pt))
	_fuel_fill.color = c
	var swell := 5.0 * (1.0 - pt)
	_fuel_fill.offset_top = FUEL_BAR_TOP - swell
	_fuel_fill.offset_bottom = FUEL_BAR_TOP + FUEL_BAR_H + swell

## The score. While a points bonus is active it takes the bonus colour (gold at the cap), swells with
## the bonus (clamped), and gives a little pulse every time the number ticks up, so the faster scoring
## is easy to see.
func set_score(points: int, bonus: float = 1.0) -> void:
	var active := Tuning.bonus_active(bonus)
	if active and points != _last_points:
		_score_tick_ms = Time.get_ticks_msec()
	_last_points = points
	var q := snappedf(bonus, 0.1)   # (the colour only changes in 0.1 steps: nothing is touched every frame)
	if q != _score_bonus:
		_score_bonus = q
		_score.add_theme_color_override("font_color", Tuning.bonus_color(q) if active else Color.WHITE)
	_score.text = "%d" % points

## The points bonus under the score: just the number ("x2.4") in the bonus colour, glowing gold at the
## cap (no word), empty at x1. `anim` says how it changed: BONUS_PUNCH = went up (pops bigger), BONUS_SHRINK = it started to
## fade (shrinks, then settles), BONUS_NONE = just update the number. Easing down to x1 shrinks it away.
func set_bonus(m: float, anim: int = BONUS_NONE) -> void:
	var was := Tuning.bonus_active(_bonus_shown)
	_bonus_shown = m
	if Tuning.bonus_active(m):
		_bonus_fading_out = false
		_bonus_label.text = Tuning.popup_text(m)
		_bonus_label.add_theme_color_override("font_color", Tuning.bonus_color(m))
		var capped := Tuning.at_cap(m)   # at the cap: gold text in a warm orange glow (a wide outline)
		_bonus_label.add_theme_color_override("font_outline_color", Color(1.0, 0.5, 0.05) if capped else Color.BLACK)
		_bonus_label.add_theme_constant_override("outline_size", 22 if capped else 12)
	elif was and not _bonus_fading_out:
		_bonus_fading_out = true   # keep the old text on screen while it shrinks away (see _update_bonus_look)
		anim = BONUS_SHRINK
	else:
		return
	if anim != BONUS_NONE:
		_bonus_anim = anim
		_bonus_anim_ms = Time.get_ticks_msec()

## No bonus, immediately (a new run, a crash, the end of the pre-warm).
func clear_bonus() -> void:
	_bonus_shown = 1.0
	_bonus_fading_out = false
	_bonus_anim = BONUS_NONE
	_bonus_label.text = ""
	_bonus_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_bonus_label.add_theme_constant_override("outline_size", 12)
	_bonus_label.scale = Vector2.ONE
	_bonus_label.modulate.a = 1.0

## Floating text ("Close!") that pops in at `pos` (screen px), rises and fades. Reuses a pooled
## label; real-time animated.
func popup(text: String, font_size: int, color: Color, pos: Vector2) -> void:
	var i := _next_pop
	_next_pop = (_next_pop + 1) % POPUP_POOL
	var l := _pop_labels[i]
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.reset_size()
	l.pivot_offset = l.size * 0.5
	var half_w := l.size.x * 0.5 * 1.25  # 1.25 = the pop-in overshoot scale
	var vp_w := get_viewport().get_visible_rect().size.x
	pos.x = clampf(pos.x, half_w + 16.0, vp_w - half_w - 16.0)  # keep long text on screen
	l.position = pos - l.size * 0.5
	l.modulate.a = 1.0
	l.visible = true
	_pop_base_y[i] = l.position.y
	_pop_born[i] = Time.get_ticks_msec()

## Animate the bonus label (punch up / shrink on a fade) and the score label (swell + tick).
func _update_bonus_look(now: int) -> void:
	var t := (now - _bonus_anim_ms) / 1000.0
	var s := 1.0
	var alpha := 1.0
	_bonus_label.pivot_offset = Vector2(_bonus_label.size.x * 0.5, 32.0)
	if _bonus_anim == BONUS_PUNCH:
		var pt := clampf(t / PUNCH_TIME, 0.0, 1.0)
		s = lerpf(1.6, 1.0, 1.0 - pow(1.0 - pt, 3.0))
	elif _bonus_anim == BONUS_SHRINK:
		var st := clampf(t / SHRINK_TIME, 0.0, 1.0)
		if _bonus_fading_out:   # back to x1: shrink the old label right away, fading as it goes
			s = lerpf(1.0, 0.15, st)
			alpha = 1.0 - st
			if st >= 1.0:
				_bonus_label.text = ""
				_bonus_fading_out = false
				_bonus_anim = BONUS_NONE
		else:                   # a step down: from the old, bigger size to smaller than normal, then settle
			s = lerpf(1.35, 0.72, 1.0 - pow(1.0 - minf(st / 0.5, 1.0), 2.0)) if st < 0.5 else lerpf(0.72, 1.0, (st - 0.5) / 0.5)
			alpha = 0.55 + 0.45 * st
	if Tuning.at_cap(_bonus_shown) and Tuning.bonus_active(_bonus_shown):
		s *= 1.0 + 0.05 * sin(now / 1000.0 * 7.0)   # the glow breathes
	_bonus_label.scale = Vector2.ONE * s
	_bonus_label.modulate.a = alpha
	# Score: swells with the bonus and pulses on each tick while a bonus is active.
	_score.pivot_offset = _score.size * 0.5
	var swell := 1.0
	if Tuning.bonus_active(_score_bonus):
		var pulse := clampf(1.0 - (now - _score_tick_ms) / 1000.0 / TICK_TIME, 0.0, 1.0)
		swell = Tuning.bonus_swell(_score_bonus) + 0.10 * pulse
	_score.scale = Vector2.ONE * swell

func _process(delta: float) -> void:
	_update_perf(delta)
	var now := Time.get_ticks_msec()
	_update_fuel_look(now)
	_update_bonus_look(now)
	# Popups.
	for i in POPUP_POOL:
		if _pop_born[i] == 0:
			continue
		var l := _pop_labels[i]
		var t := (now - _pop_born[i]) / 1000.0 / POPUP_TIME
		if t >= 1.0:
			l.visible = false
			_pop_born[i] = 0
			continue
		var pop := 0.5 + 0.75 * minf(t / 0.15, 1.0) if t < 0.15 else lerpf(1.25, 1.0, minf((t - 0.15) / 0.2, 1.0))
		l.scale = Vector2.ONE * pop
		l.position.y = _pop_base_y[i] - 150.0 * (1.0 - pow(1.0 - t, 2.0))  # rise, easing out
		l.modulate.a = 1.0 if t < 0.5 else 1.0 - (t - 0.5) / 0.5

## End-of-run screen: a header ("CRASHED" / "OUT OF FUEL"), what ended the run, the final score and
## the restart hint.
func show_game_over(points: int, header: String, reason: String, earned: int = 0, new_best: bool = false, best: int = 0) -> void:
	_over.text = _game_over_text(points, header, reason, earned, new_best, best)
	_over.visible = true
	_over_hangar.visible = true

func _game_over_text(points: int, header: String, reason: String, earned: int = 0, new_best: bool = false, best: int = 0) -> String:
	var best_line := "NEW BEST!" if new_best else "Best: %d" % best
	return "%s\n%s\n\nScore: %d\n%s\n+%d coins\n\nTap to restart" % [header, reason, points, best_line, earned]

func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", 12)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

## Small "commit . build time" tag in the bottom-left corner so you can tell which build you're on,
## with any active ?debug flags on a second line. BuildInfo.gd is rewritten by the GitHub Actions
## workflow at export time.
func _build_stamp() -> void:
	var l := _make_label(26)
	l.text = "%s  %s" % [BuildInfo.COMMIT, BuildInfo.TIME]
	var flags := DebugFlags.summary()
	if flags != "":
		l.text += "\n" + flags
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	l.offset_left = 14
	l.offset_top = -48 if flags == "" else -84
	l.modulate = Color(1, 1, 1, 0.55)
	l.add_theme_constant_override("outline_size", 6)
	if DebugFlags.perf_enabled():
		_perf_label = _make_label(26)
		_perf_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_perf_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_perf_label.offset_left = 14
		_perf_label.offset_top = 14
		_perf_label.modulate = Color(0.6, 1, 0.6, 0.9)
		_perf_label.add_theme_constant_override("outline_size", 6)

## ?perf: called by Main right after a near miss's effects fired. Starts watching the next 4 frames
## so the readout can say whether a hitch is in the near-miss code itself (CPU) or in the frames
## that follow (rendering / GPU / driver work triggered by the effects).
func note_near_miss(handler_ms: float) -> void:
	_nm_count += 1
	_nm_handler_ms = handler_ms
	_nm_frames_left = 4
	_nm_worst = 0.0

func _update_perf(delta: float) -> void:
	if _perf_label == null:
		return
	var ms := delta * 1000.0
	_perf_worst = maxf(_perf_worst, ms)
	if _nm_frames_left > 0:
		_nm_worst = maxf(_nm_worst, ms)
		_nm_frames_left -= 1
		if _nm_frames_left == 0:
			_nm_log.append("#%d code %.1f ms | next frames worst %.0f ms" % [_nm_count, _nm_handler_ms, _nm_worst])
			if _nm_log.size() > 5:
				_nm_log.pop_front()
	var now := Time.get_ticks_msec()
	if now - _perf_window_start > 3000:
		_perf_shown = _perf_worst
		_perf_worst = 0.0
		_perf_window_start = now
	_perf_label.text = "worst frame (3s): %.0f ms\nnear misses:\n%s" % [_perf_shown, "\n".join(_nm_log)]

## Startup pre-warm: a splash screen (nearly opaque, so the effects behind it are really drawn
## on screen and not skipped) while the game draws every popup tier at every font size and the
## game-over text, building the font glyph caches. end_prewarm() removes it all.
func begin_prewarm(with_popups: bool) -> void:
	if with_popups:
		prewarm_popups()
		# Also draw each tier text at each size, so no (text, size) pair is first seen mid-game.
		for t in Tuning.near_miss_sizes.size():
			var l := _make_label(Tuning.near_miss_sizes[mini(t, Tuning.near_miss_sizes.size() - 1)])
			l.text = Tuning.popup_text(2.0 + t) + "\n0123456789.x"   # (digits too: every bonus value shows up as popup text)
			l.position = Vector2(20.0, 120.0 + 90.0 * t)
			l.set_meta("prewarm", true)
	# Both end screens' glyphs, so neither is first drawn when a run ends.
	_over.text = _game_over_text(1234567890, Main.HEADER_CRASH, Main.REASON_OBSTACLE, 1234567890, true, 1234567890) + "\n" \
			+ _game_over_text(1234567890, Main.HEADER_FUEL, Main.REASON_FUEL, 1234567890, false, 1234567890)
	_over.visible = true
	refresh_menus()
	_menu.visible = true      # the start screen, Hangar and Hangar button are drawn too (under the splash)
	_hangar.visible = true
	_over_hangar.visible = true
	_splash = Control.new()
	_splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.16, 0.93)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash.add_child(bg)
	var title := Label.new()
	title.text = "SKY DODGE\nloading..."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 90)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash.add_child(title)
	add_child(_splash)  # last child = drawn on top

## Show every pooled popup label, cycling through every tier's text and size. The pre-warm calls
## this again every so often because popups fade out after a second.
func prewarm_popups() -> void:
	var vp := get_viewport().get_visible_rect().size
	for i in POPUP_POOL:
		var t := i % Tuning.near_miss_sizes.size()
		popup(Tuning.popup_text(2.0 + t), Tuning.near_miss_sizes[mini(t, Tuning.near_miss_sizes.size() - 1)],
				Tuning.near_miss_colors[mini(t, Tuning.near_miss_colors.size() - 1)], Vector2(vp.x * 0.5, vp.y * (0.25 + 0.1 * i)))

## Back to a fresh run (restart in place): hide the crash screen and popups, zero the score.
## Every label stays alive; nothing is created or freed.
func reset_for_run() -> void:
	_over.visible = false
	hide_menus()
	for i in POPUP_POOL:
		_pop_labels[i].visible = false
		_pop_born[i] = 0
	_nm_frames_left = 0
	_fuel_pulse_ms = -10000
	set_fuel(1.0)
	_score_bonus = 1
	_score.add_theme_color_override("font_color", Color.WHITE)
	set_score(0)
	clear_bonus()

func end_prewarm() -> void:
	for i in POPUP_POOL:
		_pop_labels[i].visible = false
		_pop_born[i] = 0
	for c in get_children():
		if c.has_meta("prewarm"):
			c.queue_free()
	_over.visible = false
	hide_menus()
	if is_instance_valid(_splash):
		_splash.queue_free()
