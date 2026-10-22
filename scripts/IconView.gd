class_name IconView
extends Control
## An icon from the set (Icons.gd) as a control, optionally on a round coloured plate: how every perk, boost, gear item and
## upgrade shows up in the Hangar, the pick cards, the callouts and the HUD. Set `icon` (an id), `plate` (colour, alpha 0 = none).

var icon := "":
	set(v):
		if v != icon:
			icon = v
			queue_redraw()
var plate := Color(0, 0, 0, 0):
	set(v):
		plate = v
		queue_redraw()
var tint := Color.WHITE:
	set(v):
		tint = v
		queue_redraw()
var glow := 0.0:   # 0..1: a bright ring (an item that just acted)
	set(v):
		glow = v
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	if plate.a > 0.0:
		draw_circle(c + Vector2(0, r * 0.06), r, Color(Style.SHADOW_COLOR, 0.35))
		draw_circle(c, r, Color(Style.INK, plate.a))
		draw_circle(c, r - maxf(r * 0.07, 3.0), plate)
		draw_arc(c, r * 0.78, PI * 1.1, PI * 1.9, 14, Color(1, 1, 1, 0.28 * plate.a), maxf(r * 0.1, 3.0), true)
		if glow > 0.0:
			draw_arc(c, r + 2.0, 0.0, TAU, 28, Color(1, 1, 1, glow), maxf(r * 0.09, 3.0), true)
	Icons.draw(self, icon, c + Vector2(0, r * 0.02), r * (0.58 if plate.a > 0.0 else 0.95), tint)
