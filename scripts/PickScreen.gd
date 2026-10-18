class_name PickScreen
extends CanvasLayer
## The pick screen: while the game is paused, three cards slide in and the player taps one. Created once,
## drawn during the start-up pre-warm, only shown / hidden after that. It keeps running while the game is
## paused (process_mode ALWAYS) and animates with real time, never with a time scale.

signal chosen(index: int)

const CARDS := 3
const CARD_W := 960.0
const CARD_H := 300.0
const SLIDE_TIME := 0.15  # the cards slide in fast: all three are in place in about 0.19 s
const STAGGER := 0.02
const ARM_TIME := 0.22    # a tap this soon after they appear is ignored (the one that was already on its way); after that ONE tap picks

var _root: Control
var _cards: Array[Button] = []
var _parts: Array[Dictionary] = []      # per card: icon, glyph, name, tag, line, pips, combo
var _born_ms := 0
var shown := false

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30

func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.08, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var title := _label("PICK ONE", 90, 0, 170, 1080, 120, HORIZONTAL_ALIGNMENT_CENTER)
	_root.add_child(title)
	for i in CARDS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.size = Vector2(CARD_W, CARD_H)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(28)
			sb.bg_color = {"normal": Color(0.14, 0.2, 0.32), "hover": Color(0.18, 0.26, 0.4), "pressed": Color(0.24, 0.34, 0.52), "disabled": Color(0.14, 0.2, 0.32), "focus": Color(0.14, 0.2, 0.32)}[state]
			sb.border_width_left = 4
			sb.border_width_right = 4
			sb.border_width_top = 4
			sb.border_width_bottom = 4
			sb.border_color = Color(0.3, 0.4, 0.6)
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(func(): _on_card(i))
		_root.add_child(b)
		_cards.append(b)
		var icon := Panel.new()
		var isb := StyleBoxFlat.new()
		isb.set_corner_radius_all(85)
		icon.add_theme_stylebox_override("panel", isb)
		icon.position = Vector2(30, 65)
		icon.size = Vector2(170, 170)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(icon)
		var glyph := _label("", 100, 30, 65, 170, 170, HORIZONTAL_ALIGNMENT_CENTER)
		b.add_child(glyph)
		var nm := _label("", 66, 225, 40, 700, 100, HORIZONTAL_ALIGNMENT_LEFT)
		b.add_child(nm)
		var tag := _label("", 1, 0, 0, 1, 1, HORIZONTAL_ALIGNMENT_LEFT)   # (kept so the card parts stay the same; unused)
		tag.visible = false
		b.add_child(tag)
		var pips: Array[Panel] = []
		for k in 3:
			var pip := Panel.new()
			var psb := StyleBoxFlat.new()
			psb.set_corner_radius_all(16)
			psb.set_border_width_all(3)
			psb.border_color = Color(0, 0, 0, 0.6)
			pip.add_theme_stylebox_override("panel", psb)
			pip.position = Vector2(CARD_W - 70.0 - 52.0 * (3 - k), 30)
			pip.size = Vector2(32, 32)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(pip)
			pips.append(pip)
		var line := _label("", 44, 225, 155, CARD_W - 250.0, 90, HORIZONTAL_ALIGNMENT_LEFT)
		line.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
		b.add_child(line)
		var combo := _label("COMBO!", 44, CARD_W - 330.0, 90, 300, 60, HORIZONTAL_ALIGNMENT_RIGHT)
		combo.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		combo.add_theme_color_override("font_outline_color", Color(0.9, 0.3, 0.0))
		combo.visible = false
		b.add_child(combo)
		_parts.append({"icon": icon, "isb": isb, "glyph": glyph, "name": nm, "tag": tag, "pips": pips, "line": line, "combo": combo})

func _label(text: String, size: int, x: float, y: float, w: float, h: float, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = Vector2(x, y)
	l.size = Vector2(w, h)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Fill the cards from a roll (see Perks.roll) and slide them in. `combos` marks cards that would complete a combo.
func show_cards(cards: Array[Dictionary], combos: Array = []) -> void:
	for i in CARDS:
		var b := _cards[i]
		b.visible = i < cards.size()
		if i >= cards.size():
			continue
		var c := cards[i]
		var p := _parts[i]
		(p["isb"] as StyleBoxFlat).bg_color = c["color"]
		(p["glyph"] as Label).text = c["glyph"]
		(p["name"] as Label).text = c["name"]
		(p["line"] as Label).text = c["line"]
		for k in 3:
			var pip := (p["pips"] as Array)[k] as Panel
			pip.visible = c["kind"] == "perk"
			(pip.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color(1.0, 0.9, 0.35) if k < int(c["level"]) else Color(0.25, 0.3, 0.42)
		var is_combo: bool = i < combos.size() and combos[i] != ""
		(p["combo"] as Label).visible = is_combo
		(p["combo"] as Label).text = "COMBO!" if is_combo else ""
		var border := (b.get_theme_stylebox("normal") as StyleBoxFlat)
		border.border_color = Color(1.0, 0.85, 0.2) if is_combo else Color(0.3, 0.4, 0.6)
		b.position = Vector2(1200.0, 420.0 + (CARD_H + 30.0) * i)
	_born_ms = Time.get_ticks_msec()
	shown = true
	_root.visible = true

func hide_cards() -> void:
	shown = false
	_root.visible = false

func _process(_delta: float) -> void:
	if not shown:
		return
	var t := (Time.get_ticks_msec() - _born_ms) / 1000.0
	for i in CARDS:
		var k := clampf((t - STAGGER * i) / SLIDE_TIME, 0.0, 1.0)
		k = 1.0 - pow(1.0 - k, 3.0)   # ease out
		_cards[i].position.x = lerpf(1200.0, (1080.0 - CARD_W) * 0.5, k)

func _on_card(i: int) -> void:
	if (Time.get_ticks_msec() - _born_ms) / 1000.0 < ARM_TIME:
		return
	chosen.emit(i)

## Pre-warm: draw sample cards (every card kind) for a moment.
func prewarm_show() -> void:
	var sample: Array[Dictionary] = [
		{"kind": "perk", "id": "x", "name": "Lucky Whiskers", "glyph": "W", "color": Color(1.0, 0.4, 0.85), "line": "50% can on Whisker closes 0123456789", "level": 2, "owned": true},
		{"kind": "boost", "id": "x", "name": "Magnet Storm", "glyph": "M", "color": Color(0.8, 0.5, 1.0), "line": "Cans fly to you, 20 s", "level": 0, "owned": false},
		{"kind": "supply", "id": "x", "name": "Coin Bag", "glyph": "$", "color": Color(1.0, 0.8, 0.2), "line": "+1.5K coins now", "level": 0, "owned": false},
	]
	show_cards(sample, ["Combo", "", ""])
	for b in _cards:
		b.position.x = (1080.0 - CARD_W) * 0.5
	_born_ms = -100000   # (skip the slide)

func is_shown() -> bool:
	return shown
