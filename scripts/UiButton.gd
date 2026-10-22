class_name UiButton
extends Button
## Sky Dodge's one button (docs/style.md): primary (big, green, chunky lip), secondary (dark surface), ghost (translucent
## round chip, icon only), gold (the one reward) and card (icon, a title, one line, something on the right). States: normal,
## pressed (the face squashes down into its lip and bounces back on release), disabled (flat, grey, no shadow), accent
## (selected / affordable: green fill). It is a real Button, so `text`, `disabled` and `pressed` work as usual; it draws itself.

enum Kind { PRIMARY, SECONDARY, GHOST, GOLD, CARD, TAB }

var kind: Kind = Kind.SECONDARY:
	set(v):
		kind = v
		queue_redraw()
var icon_id := "":              # a lead icon (left of the text) or the whole content of a ghost button
	set(v):
		icon_id = v
		queue_redraw()
var icon_plate := Color(0, 0, 0, 0):   # a card's round icon plate colour
	set(v):
		icon_plate = v
		queue_redraw()
var accent := false:            # selected / affordable
	set(v):
		accent = v
		queue_redraw()
var trail_text := "":           # a card's right-hand text (a price, "MAX") ...
	set(v):
		trail_text = v
		queue_redraw()
var trail_icon := "":           # ... with an icon before it (the coin)
	set(v):
		trail_icon = v
		queue_redraw()
var font_px := 44
var press_sound := true
var _down := 0.0                 # 0..1: how far the face is pushed in
var _target := 0.0
var _bounce_t := 99.0            # seconds since release (the overshoot)
var _sb_face: StyleBoxFlat
var _sb_key := ""

static var _boxes := {}

func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color", "font_hover_pressed_color"]:
		add_theme_color_override(c, Color(0, 0, 0, 0))   # (drawn by _draw: the text itself stays readable in `text`)
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
	button_down.connect(func():
		_target = 1.0
		_bounce_t = 99.0
		set_process(true))
	button_up.connect(func():
		_target = 0.0
		_bounce_t = 0.0
		set_process(true))
	set_process(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()
	elif what == NOTIFICATION_DISABLED or what == NOTIFICATION_ENTER_TREE:
		queue_redraw()

func _process(delta: float) -> void:
	var was := _down
	_down = move_toward(_down, _target, delta / Style.T_FAST)
	if _bounce_t < 99.0:
		_bounce_t += delta
	if _bounce_t > Style.T_BASE and _down == _target:
		_bounce_t = 99.0
		set_process(false)
	if _down != was or _bounce_t < 99.0:
		queue_redraw()

## 0..1 press amount including the little overshoot bounce after a release (the tests read it).
func squash() -> float:
	if _bounce_t < Style.T_BASE:
		return -0.4 * sin(PI * clampf(_bounce_t / Style.T_BASE, 0.0, 1.0)) * (1.0 - _bounce_t / Style.T_BASE)
	return _down

static func _box(key: String, fill: Color, border: Color, radius: int, border_w: int, shadow: bool) -> StyleBoxFlat:
	if not _boxes.has(key):
		_boxes[key] = Style.box(fill, border, radius, border_w, shadow)
	return _boxes[key]

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var sq := squash()
	var lip := Style.LIP if kind == Kind.PRIMARY or kind == Kind.GOLD else 0.0
	var dis := disabled and kind != Kind.GOLD   # (a maxed upgrade is a disabled gold button: it stays gold)
	if dis:
		sq = 0.0
	var push := sq * (5.0 if lip == 0.0 else lip * 0.8)
	var face := Rect2(r.position + Vector2(0, push), r.size - Vector2(0, lip))
	var rad := Style.R_L if (kind == Kind.PRIMARY) else (Style.R_PILL if (kind == Kind.GHOST or kind == Kind.TAB) else Style.R_M)
	rad = mini(rad, int(minf(size.x, size.y) * 0.5))
	var text_col := Color.WHITE
	var border_c := Color(Style.LINE, 0.55)
	var fill := Style.SURFACE_DARK
	var sheen := 0.10
	var shadow := true
	var bw := 3
	if dis:
		fill = Color(0.07, 0.09, 0.14, 0.9)
		border_c = Color(0.3, 0.33, 0.4, 0.7)
		text_col = Style.TEXT_QUIET
		sheen = 0.0
		shadow = false
	else:
		match kind:
			Kind.PRIMARY:
				fill = Style.SUCCESS
				border_c = Color(0.9, 1.0, 0.95, 0.95)
				bw = 5
				sheen = 0.16
				shadow = false
			Kind.GOLD:
				fill = Style.ACCENT
				border_c = Color(1.0, 0.97, 0.85, 0.95)
				bw = 5
				sheen = 0.16
				shadow = false
				text_col = Style.TEXT_ON_LIGHT
			Kind.GHOST:
				fill = Color(Style.SCRIM, 0.35)
				border_c = Color(Style.LINE, 0.35)
				bw = 2
				sheen = 0.0
				shadow = false
			Kind.TAB:
				fill = Style.SUCCESS_DARK if accent else Color(Style.SURFACE_DARK, 0.9)
				border_c = Color(0.75, 1.0, 0.85, 0.9) if accent else Color(Style.LINE, 0.4)
				shadow = false
			_:
				if accent:
					fill = Color(Style.SUCCESS_DARK, 0.97)
					border_c = Color(0.75, 1.0, 0.85, 0.9)
	var key := "%d_%d_%d_%d_%s_%s_%s" % [kind, rad, bw, int(shadow), fill.to_html(), border_c.to_html(), dis]
	if lip > 0.0 and not dis:
		var lip_col := Style.SUCCESS_DARK if kind == Kind.PRIMARY else Style.ACCENT_DARK
		draw_style_box(_box("lip_%d_%s" % [rad, lip_col.to_html()], lip_col, lip_col, rad, 0, true), Rect2(r.position + Vector2(0, lip), r.size - Vector2(0, lip)))
	Style.draw_panel(self, _box(key, fill, border_c, rad, bw, shadow), face, sheen)
	var cx := face.position.x + face.size.x * 0.5
	var cy := face.position.y + face.size.y * 0.5
	var lines := text.split("\n")
	var icon_r := minf(face.size.y * 0.3, float(font_px) * 0.6)
	if kind == Kind.CARD:
		var pad := face.size.y * 0.5
		if icon_id != "":
			var plate := icon_plate if icon_plate.a > 0.0 else Style.SURFACE_DARK_2
			_icon_plate(Vector2(face.position.x + pad, cy), face.size.y * 0.34, plate)
		var tx := face.position.x + pad * 2.0 + 6.0
		var tw := face.size.x - (tx - face.position.x) - 24.0
		var trail_w := 0.0
		if trail_text != "":
			trail_w = Style.text_width(trail_text, 40) + (60.0 if trail_icon != "" else 0.0) + 12.0
			var ty := cy + 14.0
			if trail_icon != "":
				Icons.draw(self, trail_icon, Vector2(face.end.x - 24.0 - Style.text_width(trail_text, 40) - 34.0, cy), 24.0, Color(1, 1, 1, 1.0 if not dis else 0.5))
			Style.draw_text(self, trail_text, Vector2(face.end.x - 24.0, ty), 40, Style.ACCENT if not dis else Style.TEXT_QUIET, HORIZONTAL_ALIGNMENT_RIGHT, trail_w)
		var avail := tw - trail_w
		var sizes := [font_px, int(font_px * 0.62)]
		var col_second := Style.TEXT_SOFT if not dis else Style.TEXT_QUIET
		var total_h := 0.0
		for i in mini(lines.size(), 2):
			total_h += float(sizes[i]) * 1.15
		var y := cy - total_h * 0.5
		for i in mini(lines.size(), 2):
			var s: int = sizes[i]
			y += float(s) * 0.95
			var txt := lines[i]
			if i == 1:
				Style.draw_text(self, txt, Vector2(tx, y), s, col_second, HORIZONTAL_ALIGNMENT_LEFT, avail)
			else:
				Style.draw_text(self, txt, Vector2(tx, y), s, text_col, HORIZONTAL_ALIGNMENT_LEFT, avail)
			y += float(s) * 0.2
		return
	if kind == Kind.GHOST:
		Icons.draw(self, icon_id, Vector2(cx, cy), minf(face.size.x, face.size.y) * 0.3, text_col)
		return
	if lines.size() > 1:   # a few short lines, centred, stacked ("IN SLOT" / "2")
		var fs := int(font_px * 0.78)
		var total_h2 := float(fs) * 1.1 * lines.size()
		var y2 := cy - total_h2 * 0.5
		for ln in lines:
			y2 += float(fs) * 0.9
			Style.draw_text(self, ln, Vector2(face.position.x + 8.0, y2), fs, text_col, HORIZONTAL_ALIGNMENT_CENTER, face.size.x - 16.0)
			y2 += float(fs) * 0.2
		return
	# centred text with an optional lead icon
	var s0 := lines[0] if lines.size() > 0 else ""
	var tw2 := Style.text_width(s0, font_px) if s0 != "" else 0.0
	var gap := font_px * 0.3
	var icon_w := icon_r * 2.0 if icon_id != "" else 0.0
	var total := tw2 + (icon_w + gap if icon_id != "" and s0 != "" else icon_w)
	var x := cx - total * 0.5
	if icon_id != "":
		Icons.draw(self, icon_id, Vector2(x + icon_r, cy), icon_r, text_col)
		x += icon_w + (gap if s0 != "" else 0.0)
	if s0 != "":
		var base := cy + float(font_px) * 0.34
		Style.draw_text(self, s0, Vector2(x, base), font_px, text_col, HORIZONTAL_ALIGNMENT_LEFT, tw2 + 4.0)

func _icon_plate(c: Vector2, rad: float, col: Color) -> void:
	draw_circle(c, rad, Color(Style.INK, 0.9))
	draw_circle(c, rad - maxf(rad * 0.07, 3.0), col)
	draw_arc(c, rad * 0.78, PI * 1.1, PI * 1.9, 14, Color(1, 1, 1, 0.28), maxf(rad * 0.1, 3.0), true)
	Icons.draw(self, icon_id, c + Vector2(0, rad * 0.02), rad * 0.58, Color.WHITE)
