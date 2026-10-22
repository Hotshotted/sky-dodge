class_name Style
extends RefCounted
## The visual identity in one place (the written version is docs/style.md): palette, type, radii, spacing, motion
## timings, shadows, safe areas. Nothing in here touches the autoloads, so any script can use it.
## Shared with Pattern Work (same tokens, same fonts); Sky Dodge's deviations are the "countryside" tokens below and in docs/style.md.

# ---- palette ----
const PRIMARY := Color("3d8bff")         # sky blue: the brand colour, links, selection
const PRIMARY_DARK := Color("2459c4")
const ACCENT := Color("ffc933")          # sun gold: coins, stars, rewards
const ACCENT_DARK := Color("c98a0b")
const SUCCESS := Color("35c98a")         # go / play / earned
const SUCCESS_DARK := Color("1a8a5a")
const WARNING := Color("ff9f2e")
const DANGER := Color("ff5c4d")
const DANGER_DARK := Color("b63227")
# neutrals and surfaces
const INK := Color("0a1020")             # outlines, deepest dark
const SURFACE_DARK := Color("14213d")    # cards and sheets on the dark UI
const SURFACE_DARK_2 := Color("1d3157")  # raised / selected dark surface
const SURFACE_LIGHT := Color("f3f7ff")   # light surface (popups on the light theme)
const SURFACE_LIGHT_2 := Color("d9e5f8")
const TEXT := Color("ffffff")
const TEXT_SOFT := Color("bcd0ec")
const TEXT_QUIET := Color("8497b8")
const TEXT_ON_LIGHT := Color("14213d")
const LINE := Color(0.62, 0.72, 0.9, 0.9)
# countryside accents (Sky Dodge only): the world behind the interface
const SKY := Color("7cc8ff")             # morning sky
const SKY_DEEP := Color("3d8bff")
const MEADOW := Color("6cc04a")          # fields
const BARN_RED := Color("d2483a")        # barns and the plane's red tail
const HAY := Color("f2c14e")             # hay, gold wheat
const CLOUD := Color("f4f9ff")
const SCRIM := Color("060b18")           # the shade behind screens and sheets

# ---- radii, spacing (px in the 1080 x 1920 viewport) ----
const R_S := 14
const R_M := 26                          # cards, chips
const R_L := 40                          # primary buttons, sheets
const R_PILL := 60                       # banners, pills
const SP_1 := 8
const SP_2 := 16
const SP_3 := 24
const SP_4 := 40
const SP_5 := 64
const GUTTER := 40                       # screen edge to content

# ---- shadows ----
const SHADOW_COLOR := Color(0.01, 0.03, 0.08, 0.45)
const SHADOW_SIZE := 16
const SHADOW_OFFSET := Vector2(0.0, 8.0)
const LIP := 10.0                        # the dark "thickness" under a chunky button

# ---- motion (seconds) ----
const T_FAST := 0.12                     # press / release
const T_BASE := 0.30                     # screen transitions, panels in
const T_SLOW := 0.5                      # celebrations
const STAGGER := 0.05                    # between cards animating in
const OVERSHOOT := 1.70158               # ease-out-back constant for popups
# Easing: ease-out-cubic for things arriving, ease-in-cubic for things leaving, ease-out-back for popups and stars.

# ---- type ----
const SZ_XL := 110
const SZ_M := 56
const SZ_S := 30
const WGHT := 2003265652                 # the OpenType 'wght' axis tag
const DISPLAY_WEIGHT := 600.0            # Fredoka SemiBold: titles and numbers
const TEXT_WEIGHT := 700.0               # Nunito Bold: everything else

static var _display: FontVariation
static var _text: FontVariation

static func display() -> Font:
	if _display == null:
		_display = FontVariation.new()
		_display.base_font = preload("res://assets/fonts/Fredoka.ttf")
		_display.variation_opentype = {WGHT: DISPLAY_WEIGHT}
	return _display

static func text() -> Font:
	if _text == null:
		_text = FontVariation.new()
		_text.base_font = preload("res://assets/fonts/Nunito.ttf")
		_text.variation_opentype = {WGHT: TEXT_WEIGHT}
	return _text

## The font for a string at a size: the display face for big text and for numbers, the text face for the rest.
static func font_for(s: String, size_px: int) -> Font:
	if size_px >= SZ_M:
		return display()
	if s.length() > 0:
		var c := s.unicode_at(0)
		if (c >= 48 and c <= 57) or c == 43 or c == 45 or c == 120:     # 0-9, +, -, x
			return display()
	return text()

# ---- safe areas (notch, rounded corners, home indicator), in viewport pixels ----
static var safe_top := 0.0
static var safe_bottom := 0.0
static var safe_left := 0.0
static var safe_right := 0.0

static func set_safe(top: float, bottom: float, left: float = 0.0, right: float = 0.0) -> void:
	safe_top = maxf(top, 0.0)
	safe_bottom = maxf(bottom, 0.0)
	safe_left = maxf(left, 0.0)
	safe_right = maxf(right, 0.0)

## Read the device's safe area (native) and fit it to the viewport; the web build asks the page for its env() insets.
static func detect_safe(viewport: Vector2) -> void:
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0 or viewport.x <= 0.0:
		return
	var k := viewport.x / float(win.x)       # window pixels -> viewport units (the stretch keeps the width)
	if OS.has_feature("web"):
		var js = JavaScriptBridge.eval("(function(){var d=document.createElement('div');d.style.cssText='position:fixed;left:0;top:0;width:0;height:0;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';document.body.appendChild(d);var s=getComputedStyle(d);var r=[parseFloat(s.paddingTop)||0,parseFloat(s.paddingBottom)||0,parseFloat(s.paddingLeft)||0,parseFloat(s.paddingRight)||0,window.innerWidth||1];document.body.removeChild(d);return r.join(',');})()")
		if js is String:
			var p: PackedStringArray = (js as String).split(",")
			if p.size() == 5 and float(p[4]) > 0.0:
				var kc := viewport.x / float(p[4])      # css px -> viewport units
				set_safe(float(p[0]) * kc, float(p[1]) * kc, float(p[2]) * kc, float(p[3]) * kc)
		return
	var sa := DisplayServer.get_display_safe_area()
	var scr := DisplayServer.screen_get_size()
	if sa.size.x > 0 and sa.size.y > 0 and scr.x > 0 and (sa.size.x < scr.x or sa.size.y < scr.y):
		set_safe(float(sa.position.y) * k, float(scr.y - sa.end.y) * k, float(sa.position.x) * k, float(scr.x - sa.end.x) * k)

# ---- style boxes ----

## A rounded panel: fill, a light inner border, and a soft drop shadow.
static func box(fill: Color, border: Color, radius: int, border_w: int = 3, shadow: bool = true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if shadow:
		sb.shadow_color = SHADOW_COLOR
		sb.shadow_size = SHADOW_SIZE
		sb.shadow_offset = SHADOW_OFFSET
	return sb

## The soft highlight across the top of a panel (a flat stand-in for a gradient): rounded on top only.
static func sheen(radius: int, alpha: float = 0.10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, alpha)
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.anti_aliasing = true
	return sb

static func ease_out_cubic(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)

static func ease_in_cubic(t: float) -> float:
	return pow(clampf(t, 0.0, 1.0), 3.0)

static func ease_out_back(t: float) -> float:
	var c3 := OVERSHOOT + 1.0
	var u := clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + c3 * u * u * u + OVERSHOOT * u * u

# ---- drawing helpers shared by the UI controls (Sky Dodge) ----

static var _gp := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
static var _gc := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
static var _sheens := {}

## The cached soft highlight for a corner radius and strength.
static func sheen_for(radius: int, alpha: float = 0.10) -> StyleBoxFlat:
	var key := "%d_%.2f" % [radius, alpha]
	if not _sheens.has(key):
		_sheens[key] = sheen(radius, alpha)
	return _sheens[key]

## A panel with its soft highlight: a rounded cap at the top fading down into the face (the style's gradient).
static func draw_panel(ci: CanvasItem, sb: StyleBoxFlat, r: Rect2, sheen_alpha: float = 0.10) -> void:
	ci.draw_style_box(sb, r)
	if sheen_alpha <= 0.0:
		return
	var rad := maxi(sb.corner_radius_top_left - sb.border_width_left - 2, 4)
	var sh := sheen_for(rad, sheen_alpha)
	var inset := float(sb.border_width_left) + 2.0
	var h := maxf(r.size.y * 0.5 - inset, float(rad) + 2.0)
	var x0 := r.position.x + inset
	var x1 := r.end.x - inset
	var y0 := r.position.y + inset
	if x1 - x0 < 2.0 * rad:
		return
	ci.draw_style_box(sh, Rect2(x0, y0, x1 - x0, rad))
	_gp[0] = Vector2(x0, y0 + rad)
	_gp[1] = Vector2(x1, y0 + rad)
	_gp[2] = Vector2(x1, y0 + h)
	_gp[3] = Vector2(x0, y0 + h)
	_gc[0] = Color(1, 1, 1, sheen_alpha)
	_gc[1] = _gc[0]
	_gc[2] = Color(1, 1, 1, 0.0)
	_gc[3] = _gc[2]
	ci.draw_polygon(_gp, _gc)

## Text with the style's outline (ink, size / 8, at least 4 px), the font picked by size and content.
static func draw_text(ci: CanvasItem, s: String, pos: Vector2, size_px: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var f := font_for(s, size_px)
	ci.draw_string_outline(f, pos, s, align, width, size_px, maxi(size_px / 8, 4), Color(INK, col.a))
	ci.draw_string(f, pos, s, align, width, size_px, col)

static func text_width(s: String, size_px: int) -> float:
	return font_for(s, size_px).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x

## Fit a Label to the style: the font for its size / content, an ink outline, a given colour.
static func style_label(l: Label, size_px: int, col: Color = Color.WHITE) -> void:
	l.add_theme_font_override("font", font_for(l.text, size_px))
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(size_px / 8, 4))

## Relative luminance contrast ratio of two colours (the style guide's 4.5:1 rule, checked by the smoke test).
static func contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

static func _lum(c: Color) -> float:
	var r := c.srgb_to_linear()
	return 0.2126 * r.r + 0.7152 * r.g + 0.0722 * r.b

# ---- slider knob, background gradient (made once, cached) ----
static var _knob: ImageTexture
static var _bg_tex: GradientTexture2D

## A round white knob with an ink rim, for sliders.
static func knob() -> ImageTexture:
	if _knob == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length()
				var col := Color(0, 0, 0, 0)
				if d < n * 0.5 - 1.0:
					col = Color(INK, 1.0) if d > n * 0.5 - 7.0 else Color.WHITE
					if d < n * 0.5 - 7.0 and y < n * 0.42:
						col = Color(1, 1, 1, 1)
					elif d < n * 0.5 - 7.0:
						col = Color(0.88, 0.93, 1.0, 1)
				img.set_pixel(x, y, col)
		_knob = ImageTexture.create_from_image(img)
	return _knob

## The vertical gradient behind full screens: a deep sky navy fading to the scrim.
static func screen_gradient() -> GradientTexture2D:
	if _bg_tex == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color("1d3157"), Color("14213d"), Color("0a1426")])
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		_bg_tex = GradientTexture2D.new()
		_bg_tex.gradient = g
		_bg_tex.fill_from = Vector2(0.5, 0.0)
		_bg_tex.fill_to = Vector2(0.5, 1.0)
		_bg_tex.width = 8
		_bg_tex.height = 256
	return _bg_tex

## A slider in the style: dark track, gold fill, round knob.
static func style_slider(sl: HSlider) -> void:
	var track := box(Color(INK, 0.85), Color(LINE, 0.25), 14, 2, false)
	track.content_margin_top = 14
	track.content_margin_bottom = 14
	var fill := box(ACCENT, ACCENT, 14, 0, false)
	fill.content_margin_top = 14
	fill.content_margin_bottom = 14
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	sl.add_theme_icon_override("grabber", knob())
	sl.add_theme_icon_override("grabber_highlight", knob())
	sl.add_theme_icon_override("grabber_disabled", knob())
