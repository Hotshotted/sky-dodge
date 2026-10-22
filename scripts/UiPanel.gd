class_name UiPanel
extends Control
## A raised panel in the style: rounded fill, a light border, a soft drop shadow, and the highlight across the top. Flat
## things (no shadow) pass shadow = false. Children are laid out by the caller.

var fill := Style.SURFACE_DARK:
	set(v):
		fill = v
		_rebuild()
var border := Color(Style.LINE, 0.55):
	set(v):
		border = v
		_rebuild()
var radius := Style.R_M:
	set(v):
		radius = v
		_rebuild()
var border_w := 3
var shadow := true
var sheen_alpha := 0.10
var _sb: StyleBoxFlat

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rebuild()

func _rebuild() -> void:
	_sb = Style.box(fill, border, radius, border_w, shadow)
	queue_redraw()

func _draw() -> void:
	if _sb == null:
		_rebuild()
	Style.draw_panel(self, _sb, Rect2(Vector2.ZERO, size), sheen_alpha)
