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
var _cover: ColorRect
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

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
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

## Crash screen: what ended the run, the final score, and the restart hint.
func show_game_over(points: int, reason: String) -> void:
	_over.text = _game_over_text(points, reason)
	_over.visible = true

func _game_over_text(points: int, reason: String) -> String:
	return "CRASHED\n%s\n\nScore: %d\n\nTap to restart" % [reason, points]

func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", 12)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

## Small "commit . build time" tag in the bottom-left corner so you can tell which build you're on.
## BuildInfo.gd is rewritten by the GitHub Actions workflow at export time.
func _build_stamp() -> void:
	var l := _make_label(26)
	l.text = "%s  %s" % [BuildInfo.COMMIT, BuildInfo.TIME]
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	l.offset_left = 14
	l.offset_top = -48
	l.modulate = Color(1, 1, 1, 0.55)
	l.add_theme_constant_override("outline_size", 6)

## Startup pre-warm: draw every popup tier and the game-over text once (this builds the font
## glyph caches), under a black cover so nothing is seen. end_prewarm() undoes all of it.
func begin_prewarm() -> void:
	var vp := get_viewport().get_visible_rect().size
	for i in Tuning.near_miss_texts.size():
		popup(Tuning.near_miss_texts[i], Tuning.near_miss_sizes[mini(i, Tuning.near_miss_sizes.size() - 1)],
				Tuning.near_miss_colors[mini(i, Tuning.near_miss_colors.size() - 1)], Vector2(vp.x * 0.5, vp.y * (0.3 + 0.12 * i)))
	_over.text = _game_over_text(1234567890, "Hit an obstacle")  # same glyphs as the real screen
	_over.visible = true
	_cover = ColorRect.new()
	_cover.color = Color.BLACK
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)  # last child = drawn on top of the labels

func end_prewarm() -> void:
	for i in POPUP_POOL:
		_pop_labels[i].visible = false
		_pop_born[i] = 0
	_over.visible = false
	_cover.queue_free()
