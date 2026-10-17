class_name StickView
extends Control
## Draws the floating analog stick (base ring + knob). Semi-transparent so obstacles stay visible.

var _active := false
var _base := Vector2.ZERO
var _knob := Vector2.ZERO

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_stick(active: bool, base: Vector2, knob: Vector2) -> void:
	_active = active
	_base = base
	_knob = knob
	queue_redraw()

func _draw() -> void:
	if not _active:
		return
	var r := Tuning.stick_max_radius
	draw_circle(_base, r, Color(1, 1, 1, 0.10))
	draw_arc(_base, r, 0.0, TAU, 48, Color(1, 1, 1, 0.30), 4.0, true)
	draw_circle(_knob, r * 0.4, Color(1, 1, 1, 0.30))
