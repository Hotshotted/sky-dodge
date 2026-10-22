class_name BuildStrip
extends Control
## The current build as a row of round icons with level pips (the pick screen shows it at the top). Drawn in code, no child nodes.

var levels := {}

const ICON := 38.0
const GAP := 18.0

func set_build(lv: Dictionary) -> void:
	levels = lv.duplicate()
	queue_redraw()

func _draw() -> void:
	var held: Array[Dictionary] = []
	for d in Tuning.perks:
		if int(levels.get(d["id"], 0)) > 0:
			held.append(d)
	var label_h := 30.0
	if held.is_empty():
		Style.draw_text(self, "YOUR BUILD: EMPTY", Vector2(0, label_h), 26, Style.TEXT_QUIET, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		return
	Style.draw_text(self, "YOUR BUILD", Vector2(0, label_h), 26, Style.TEXT_SOFT, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	var w := held.size() * (ICON * 2.0 + GAP) - GAP
	var x := (size.x - w) * 0.5 + ICON
	var y := label_h + ICON + 12.0
	for d in held:
		var lvl := int(levels[d["id"]])
		draw_circle(Vector2(x, y), ICON, Color(Style.INK, 0.9))
		draw_circle(Vector2(x, y), ICON - 4.0, d["color"])
		Icons.draw(self, d["glyph"], Vector2(x, y), ICON * 0.62, Color.WHITE)
		for k in 3:
			var c := Vector2(x + (k - 1) * 18.0, y + ICON + 12.0)
			draw_circle(c, 7.0, Color(Style.INK, 0.9))
			draw_circle(c, 5.0, Style.ACCENT if k < lvl else Color(Style.LINE, 0.35))
		x += ICON * 2.0 + GAP
