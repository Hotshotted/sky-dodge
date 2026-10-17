extends CanvasLayer
## Score label while flying; "crashed" panel with the final score and restart hint.

var _score: Label
var _over: Label
var _mult: Label
var _punch_start_ms := -10000      # when the multiplier label last "punched"
var _popups: Array[Dictionary] = []  # {label, born_ms, base_y}
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

## Floating text ("Close!") that pops in at `pos` (screen px), rises and fades. Real-time animated.
func popup(text: String, font_size: int, color: Color, pos: Vector2) -> void:
	var l := _make_label(font_size)
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.reset_size()
	l.pivot_offset = l.size * 0.5
	var half_w := l.size.x * 0.5 * 1.25  # 1.25 = the pop-in overshoot scale
	var vp_w := get_viewport().get_visible_rect().size.x
	pos.x = clampf(pos.x, half_w + 16.0, vp_w - half_w - 16.0)  # keep long text on screen
	l.position = pos - l.size * 0.5
	_popups.append({"label": l, "born": Time.get_ticks_msec(), "base_y": l.position.y})

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	# Multiplier punch: 1.6x -> 1x with ease-out.
	var pt := clampf((now - _punch_start_ms) / 1000.0 / PUNCH_TIME, 0.0, 1.0)
	_mult.scale = Vector2.ONE * lerpf(1.6, 1.0, 1.0 - pow(1.0 - pt, 3.0))
	# Popups.
	for i in range(_popups.size() - 1, -1, -1):
		var d: Dictionary = _popups[i]
		var l := d["label"] as Label
		var t := (now - int(d["born"])) / 1000.0 / POPUP_TIME
		if t >= 1.0:
			l.queue_free()
			_popups.remove_at(i)
			continue
		var pop := 0.5 + 0.75 * minf(t / 0.15, 1.0) if t < 0.15 else lerpf(1.25, 1.0, minf((t - 0.15) / 0.2, 1.0))
		l.scale = Vector2.ONE * pop
		l.position.y = float(d["base_y"]) - 150.0 * (1.0 - pow(1.0 - t, 2.0))  # rise, easing out
		l.modulate.a = 1.0 if t < 0.5 else 1.0 - (t - 0.5) / 0.5

func show_game_over(points: int) -> void:
	_over.text = "CRASHED\n%d\n\nTap to restart" % points
	_over.visible = true

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
