class_name SplashView
extends Control
## The start-up screen (while the pre-warm runs) and, later, the logo intro: the studio's colours, its spinning propeller, the
## wordmark and a progress bar, edge to edge and fully opaque (nothing of the pre-warm shows through). Same look as the web
## loading page, so the hand-over is seamless.

var progress := 0.0:
	set(v):
		progress = clampf(v, 0.0, 1.0)
		queue_redraw()
var show_bar := true
var spin := 0.0
var _bg := TextureRect.new()

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.texture = Style.screen_gradient()
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

func _process(delta: float) -> void:
	spin += delta * 2.6
	queue_redraw()

func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.42)
	Logo.draw_mark(self, c, 190.0, spin)
	Logo.draw_wordmark(self, c.x, c.y + 330.0, 74)
	if show_bar:
		var w := 640.0
		var r := Rect2(c.x - w * 0.5, c.y + 420.0, w, 30.0)
		draw_style_box(Style.box(Color(Style.INK, 0.85), Color(Style.LINE, 0.35), 15, 2, true), r)
		var f := Rect2(r.position + Vector2(5, 5), Vector2(maxf((w - 10.0) * progress, 20.0), r.size.y - 10.0))
		draw_style_box(Style.box(Style.ACCENT, Style.ACCENT, 10, 0, false), f)
