class_name Logo
extends RefCounted
## The studio: Clear Prop Games. Its mark is a bold three-blade propeller (gold blades with an ink outline and a shine, a blue
## hub); its wordmark is the name in the display face. The same mark is drawn on the web loading page (web/shell.html, made by
## tools/make_studio_mark.py), the start-up screen and the logo intro.

const NAME := "Clear Prop Games"
const GOLD := Color("ffc933")
const INK := Color("0a1020")
const BLUE := Color("3d8bff")

static var _blade := PackedVector2Array()
static var _shine := PackedVector2Array()

static func _bez(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, n: int, out: PackedVector2Array) -> void:
	for i in n:
		var t := float(i) / n
		var u := 1.0 - t
		out.append(u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3)

static func _build() -> void:
	if not _blade.is_empty():
		return
	_bez(Vector2(0, 0), Vector2(-17, -22), Vector2(-17, -62), Vector2(0, -86), 14, _blade)
	_bez(Vector2(0, -86), Vector2(17, -62), Vector2(17, -22), Vector2(0, 0), 14, _blade)
	_bez(Vector2(-4, -26), Vector2(-8, -40), Vector2(-8, -56), Vector2(-3, -68), 8, _shine)

## The propeller, `r` = about the radius of the box it fits in, turned by `angle` radians.
static func draw_mark(ci: CanvasItem, c: Vector2, r: float, angle: float = 0.0, alpha: float = 1.0) -> void:
	_build()
	var k := r / 90.0
	for b in 3:
		ci.draw_set_transform(c, angle + b * TAU / 3.0, Vector2(k, k))
		var closed := _blade.duplicate()
		closed.append(_blade[0])
		ci.draw_colored_polygon(_blade, Color(GOLD, alpha))
		ci.draw_polyline(closed, Color(INK, alpha), 7.0, true)
		ci.draw_polyline(_shine, Color(1, 1, 1, 0.55 * alpha), 5.0, true)
	ci.draw_set_transform(c, 0.0, Vector2(k, k))
	ci.draw_circle(Vector2.ZERO, 24.0, Color(INK, alpha))
	ci.draw_circle(Vector2.ZERO, 17.0, Color(BLUE, alpha))
	ci.draw_circle(Vector2.ZERO, 6.0, Color(GOLD, alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## The wordmark centred on x = cx, baseline y.
static func draw_wordmark(ci: CanvasItem, cx: float, y: float, size_px: int, alpha: float = 1.0) -> void:
	var s := NAME.to_upper()
	var w := Style.text_width(s, size_px)
	Style.draw_text(ci, s, Vector2(cx - w * 0.5, y), size_px, Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_LEFT, w + 8.0)
