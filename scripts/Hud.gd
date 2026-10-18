extends CanvasLayer
## Score label while flying; "crashed" panel with the final score and restart hint.

var _score: Label
var _over: Label
var _mult: Label
var _punch_start_ms := -10000      # when the multiplier label last "punched"
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
const POPUP_TIME := 0.9

func _ready() -> void:
	_score = _make_label(72)
	_score.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_score.offset_top = 80
	_mult = _make_label(64)
	_mult.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_mult.offset_top = 170
	set_multiplier(1, false)
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

## Fuel gauge under the multiplier: dark trough + a fill that shrinks, green -> amber -> red.
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

func set_score(points: int) -> void:
	_score.text = "%d" % points

## Show "x2" etc. in the tier colour; `punch` = pop the label bigger and settle back.
func set_multiplier(m: int, punch: bool) -> void:
	_mult.text = "x%d" % m
	var c := Color(1, 1, 1, 0.6)
	if m >= 2:
		c = Tuning.near_miss_colors[Tuning.tier_index(m, Tuning.near_miss_colors.size())]
	_mult.add_theme_color_override("font_color", c)
	_mult.pivot_offset = Vector2(_mult.size.x * 0.5, 32.0)
	if punch:
		_punch_start_ms = Time.get_ticks_msec()

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

func _process(delta: float) -> void:
	_update_perf(delta)
	var now := Time.get_ticks_msec()
	_update_fuel_look(now)
	# Multiplier punch: 1.6x -> 1x with ease-out.
	var pt := clampf((now - _punch_start_ms) / 1000.0 / PUNCH_TIME, 0.0, 1.0)
	_mult.scale = Vector2.ONE * lerpf(1.6, 1.0, 1.0 - pow(1.0 - pt, 3.0))
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
func show_game_over(points: int, header: String, reason: String) -> void:
	_over.text = _game_over_text(points, header, reason)
	_over.visible = true

func _game_over_text(points: int, header: String, reason: String) -> String:
	return "%s\n%s\n\nScore: %d\n\nTap to restart" % [header, reason, points]

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
		for t in Tuning.near_miss_texts.size():
			var l := _make_label(Tuning.near_miss_sizes[mini(t, Tuning.near_miss_sizes.size() - 1)])
			l.text = Tuning.near_miss_texts[t]
			l.position = Vector2(20.0, 120.0 + 90.0 * t)
			l.set_meta("prewarm", true)
	# Both end screens' glyphs, so neither is first drawn when a run ends.
	_over.text = _game_over_text(1234567890, Main.HEADER_CRASH, Main.REASON_OBSTACLE) + "\n" \
			+ _game_over_text(1234567890, Main.HEADER_FUEL, Main.REASON_FUEL)
	_over.visible = true
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
		var t := i % Tuning.near_miss_texts.size()
		popup(Tuning.near_miss_texts[t], Tuning.near_miss_sizes[mini(t, Tuning.near_miss_sizes.size() - 1)],
				Tuning.near_miss_colors[mini(t, Tuning.near_miss_colors.size() - 1)], Vector2(vp.x * 0.5, vp.y * (0.25 + 0.1 * i)))

## Back to a fresh run (restart in place): hide the crash screen and popups, zero the score.
## Every label stays alive; nothing is created or freed.
func reset_for_run() -> void:
	_over.visible = false
	for i in POPUP_POOL:
		_pop_labels[i].visible = false
		_pop_born[i] = 0
	_nm_frames_left = 0
	_fuel_pulse_ms = -10000
	set_fuel(1.0)
	set_score(0)
	set_multiplier(1, false)

func end_prewarm() -> void:
	for i in POPUP_POOL:
		_pop_labels[i].visible = false
		_pop_born[i] = 0
	for c in get_children():
		if c.has_meta("prewarm"):
			c.queue_free()
	_over.visible = false
	if is_instance_valid(_splash):
		_splash.queue_free()
