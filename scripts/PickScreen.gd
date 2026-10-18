class_name PickScreen
extends CanvasLayer
## The pick screen: while the game is paused, three cards slide in and the player taps one. Created once,
## drawn during the start-up pre-warm, only shown / hidden after that. It keeps running while the game is
## paused (process_mode ALWAYS) and animates with real time, never with a time scale.

signal chosen(index: int)

const CARDS := 3
const CARD_W := 960.0
const CARD_H := 330.0
const FRAME := 10.0        # the coloured frame: gold = PERK, blue = BOOST, green = SUPPLY
const BANNER_H := 62.0
const KIND_COLORS := {"perk": Color(1.0, 0.78, 0.2), "boost": Color(0.3, 0.62, 1.0), "supply": Color(0.3, 0.85, 0.45)}
const KIND_NAMES := {"perk": "PERK", "boost": "BOOST", "supply": "SUPPLY"}
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
			sb.set_border_width_all(FRAME)
			b.add_theme_stylebox_override(state, sb)   # (colours are set per card kind in show_cards)
		b.pressed.connect(func(): _on_card(i))
		_root.add_child(b)
		_cards.append(b)
		# The banner across the top: PERK / BOOST / SUPPLY on the kind's colour, with its own facts on the right.
		var banner := Panel.new()
		var bsb := StyleBoxFlat.new()
		bsb.corner_radius_top_left = 20
		bsb.corner_radius_top_right = 20
		banner.add_theme_stylebox_override("panel", bsb)
		banner.position = Vector2(FRAME, FRAME)
		banner.size = Vector2(CARD_W - 2.0 * FRAME, BANNER_H)
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(banner)
		var kind_label := _label("PERK", 46, 28, 0, 300, BANNER_H, HORIZONTAL_ALIGNMENT_LEFT)
		banner.add_child(kind_label)
		var pips: Array[Panel] = []
		for k in 3:
			var pip := Panel.new()
			var psb := StyleBoxFlat.new()
			psb.set_corner_radius_all(16)
			psb.set_border_width_all(3)
			psb.border_color = Color(0, 0, 0, 0.6)
			pip.add_theme_stylebox_override("panel", psb)
			pip.position = Vector2(CARD_W - 2.0 * FRAME - 40.0 - 50.0 * (2 - k) - 32.0, (BANNER_H - 32.0) * 0.5)
			pip.size = Vector2(32, 32)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			banner.add_child(pip)
			pips.append(pip)
		# a stopwatch (boosts) with the time it lasts, and INSTANT (supplies)
		var watch := Control.new()
		watch.position = Vector2(CARD_W - 2.0 * FRAME - 250.0, (BANNER_H - 44.0) * 0.5)
		watch.size = Vector2(44, 44)
		watch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var face := Panel.new()
		var fsb := StyleBoxFlat.new()
		fsb.set_corner_radius_all(22)
		fsb.bg_color = Color(1, 1, 1, 0.15)
		fsb.set_border_width_all(5)
		fsb.border_color = Color.WHITE
		face.add_theme_stylebox_override("panel", fsb)
		face.position = Vector2(0, 6)
		face.size = Vector2(44, 40)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		watch.add_child(face)
		for hand in [[Vector2(20, 12), Vector2(4, 14)], [Vector2(20, 24), Vector2(12, 4)], [Vector2(15, 0), Vector2(14, 6)]]:   # minute hand, hour hand, the button on top
			var hp := Panel.new()
			var hsb := StyleBoxFlat.new()
			hsb.bg_color = Color.WHITE
			hp.add_theme_stylebox_override("panel", hsb)
			hp.position = hand[0]
			hp.size = hand[1]
			hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			watch.add_child(hp)
		banner.add_child(watch)
		var tag := _label("", 44, CARD_W - 2.0 * FRAME - 200.0, 0, 180, BANNER_H, HORIZONTAL_ALIGNMENT_RIGHT)   # "20 s" / "INSTANT"
		banner.add_child(tag)
		# the one-line explainer under the banner (the first time each kind shows up)
		var explain := _label("", 34, 28, BANNER_H + FRAME, CARD_W - 56.0, 44, HORIZONTAL_ALIGNMENT_LEFT)
		explain.add_theme_color_override("font_color", Color(1.0, 0.97, 0.8))
		b.add_child(explain)
		var icon := Panel.new()
		var isb := StyleBoxFlat.new()
		isb.set_corner_radius_all(75)
		icon.add_theme_stylebox_override("panel", isb)
		icon.position = Vector2(30, 138)
		icon.size = Vector2(150, 150)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(icon)
		var glyph := _label("", 90, 30, 138, 150, 150, HORIZONTAL_ALIGNMENT_CENTER)
		b.add_child(glyph)
		var nm := _label("", 62, 205, 112, 520, 90, HORIZONTAL_ALIGNMENT_LEFT)
		b.add_child(nm)
		var line := _label("", 44, 205, 198, CARD_W - 230.0, 60, HORIZONTAL_ALIGNMENT_LEFT)
		line.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
		b.add_child(line)
		var level_up := _label("", 52, 205, 250, 600, 62, HORIZONTAL_ALIGNMENT_LEFT)   # "LEVEL UP 2 -> 3"
		level_up.add_theme_color_override("font_color", Color(1.0, 0.6, 0.15))
		b.add_child(level_up)
		var combo := _label("COMBO!", 44, CARD_W - 270.0, 118, 240, 70, HORIZONTAL_ALIGNMENT_CENTER)
		var csb := StyleBoxFlat.new()   # a pill: it reads even before the word does
		csb.bg_color = Color(1.0, 0.85, 0.2)
		csb.set_corner_radius_all(30)
		combo.add_theme_stylebox_override("normal", csb)
		combo.add_theme_color_override("font_color", Color(0.25, 0.1, 0.0))
		combo.add_theme_constant_override("outline_size", 0)
		combo.visible = false
		b.add_child(combo)
		var tag_unused := _label("", 1, 0, 0, 1, 1, HORIZONTAL_ALIGNMENT_LEFT)   # (kept so the card parts stay the same; unused)
		tag_unused.visible = false
		b.add_child(tag_unused)
		_parts.append({"icon": icon, "isb": isb, "glyph": glyph, "name": nm, "tag": tag, "pips": pips, "line": line, "combo": combo,
				"banner": banner, "bsb": bsb, "kind": kind_label, "watch": watch, "explain": explain, "level_up": level_up})

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

## The one-line explanation of each kind of card (shown the first time that kind appears).
static func explainer(kind: String) -> String:
	match kind:
		"perk":
			return "Lasts this run"
		"boost":
			return "Lasts %d seconds" % int(Tuning.boost_time)
	return "Used instantly"

## Fill the cards from a roll (see Perks.roll) and slide them in. `combos` marks cards that would complete a combo.
## `first_time`: kinds explained so far are remembered in the save (the prewarm passes false and shows every explainer).
func show_cards(cards: Array[Dictionary], combos: Array = [], remember: bool = true) -> void:
	for i in CARDS:
		var b := _cards[i]
		b.visible = i < cards.size()
		if i >= cards.size():
			continue
		var c := cards[i]
		var p := _parts[i]
		var kind: String = c["kind"]
		var kc: Color = KIND_COLORS[kind]
		(p["isb"] as StyleBoxFlat).bg_color = c["color"]
		(p["glyph"] as Label).text = c["glyph"]
		(p["name"] as Label).text = c["name"]
		(p["line"] as Label).text = c["line"]
		# the kind, readable at a glance: frame, banner and its facts
		(p["bsb"] as StyleBoxFlat).bg_color = kc.darkened(0.15)
		(p["kind"] as Label).text = KIND_NAMES[kind]
		var is_combo: bool = i < combos.size() and combos[i] != ""
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb := b.get_theme_stylebox(state) as StyleBoxFlat
			var base := kc.darkened(0.78)
			sb.bg_color = base.lightened(0.12) if state == "hover" else (base.lightened(0.25) if state == "pressed" else base)
			sb.border_color = Color(1.0, 1.0, 0.7) if is_combo else kc
		for k in 3:
			var pip := (p["pips"] as Array)[k] as Panel
			pip.visible = kind == "perk"
			(pip.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color.WHITE if k < int(c["level"]) else kc.darkened(0.55)
		(p["watch"] as Control).visible = kind == "boost"
		var tag := p["tag"] as Label
		tag.visible = kind != "perk"
		tag.text = ("%d s" % int(Tuning.boost_time)) if kind == "boost" else "INSTANT"
		var level_up := p["level_up"] as Label
		level_up.visible = kind == "perk" and bool(c["owned"])
		level_up.text = "LEVEL UP %d -> %d" % [int(c["level"]) - 1, int(c["level"])] if level_up.visible else ""
		var explain := p["explain"] as Label
		var show_it: bool = not remember or not Save.was_explained(kind)
		explain.visible = show_it
		explain.text = explainer(kind) if show_it else ""
		if remember and show_it:
			Save.mark_explained(kind)
		(p["combo"] as Label).visible = is_combo
		(p["combo"] as Label).text = "COMBO!" if is_combo else ""
		b.position = Vector2(1200.0, 400.0 + (CARD_H + 30.0) * i)
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
	show_cards(sample, ["Combo", "", ""], false)
	for b in _cards:
		b.position.x = (1080.0 - CARD_W) * 0.5
	_born_ms = -100000   # (skip the slide)

func is_shown() -> bool:
	return shown
