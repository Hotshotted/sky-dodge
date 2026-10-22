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
	dim.color = Color(Style.SCRIM, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_title = _label("PICK ONE", 96, 0, 150, 1080, 120, HORIZONTAL_ALIGNMENT_CENTER)
	_root.add_child(_title)
	_build = BuildStrip.new()
	_build.size = Vector2(1080, 150)
	_build.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_build)
	for i in CARDS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.size = Vector2(CARD_W, CARD_H)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(state, Style.box(Style.SURFACE_DARK, Style.PRIMARY, Style.R_M + 4, 6, true))   # (colours are set per card kind in show_cards)
		b.pressed.connect(func(): _on_card(i))
		_root.add_child(b)
		_cards.append(b)
		# The banner across the top: PERK / BOOST / SUPPLY on the kind's colour, with its own facts on the right.
		var banner := Panel.new()
		var bsb := StyleBoxFlat.new()
		bsb.corner_radius_top_left = Style.R_M - 2
		bsb.corner_radius_top_right = Style.R_M - 2
		bsb.anti_aliasing = true
		banner.add_theme_stylebox_override("panel", bsb)
		banner.position = Vector2(FRAME, FRAME)
		banner.size = Vector2(CARD_W - 2.0 * FRAME, BANNER_H)
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(banner)
		var kind_label := _label("PERK", 40, 28, 0, 300, BANNER_H, HORIZONTAL_ALIGNMENT_LEFT)
		banner.add_child(kind_label)
		var pips: Array[Panel] = []
		for k in 3:
			var pip := Panel.new()
			var psb := StyleBoxFlat.new()
			psb.set_corner_radius_all(16)
			psb.set_border_width_all(3)
			psb.border_color = Style.INK
			pip.add_theme_stylebox_override("panel", psb)
			pip.position = Vector2(CARD_W - 2.0 * FRAME - 40.0 - 50.0 * (2 - k) - 32.0, (BANNER_H - 32.0) * 0.5)
			pip.size = Vector2(32, 32)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			banner.add_child(pip)
			pips.append(pip)
		# a stopwatch (boosts) with the time it lasts, and INSTANT (supplies)
		var watch := IconView.new()
		watch.icon = "clock"
		watch.position = Vector2(CARD_W - 2.0 * FRAME - 250.0, (BANNER_H - 44.0) * 0.5)
		watch.size = Vector2(44, 44)
		banner.add_child(watch)
		var tag := _label("", 40, CARD_W - 2.0 * FRAME - 200.0, 0, 180, BANNER_H, HORIZONTAL_ALIGNMENT_RIGHT)   # "20 s" / "INSTANT"
		banner.add_child(tag)
		# the one-line explainer under the banner (the first time each kind shows up)
		var explain := _label("", 30, 28, BANNER_H + FRAME, CARD_W - 56.0, 44, HORIZONTAL_ALIGNMENT_LEFT)
		explain.add_theme_color_override("font_color", Style.TEXT_SOFT)
		b.add_child(explain)
		var icon := IconView.new()
		icon.position = Vector2(30, 138)
		icon.size = Vector2(150, 150)
		b.add_child(icon)
		var nm := _label("", 62, 205, 112, 520, 90, HORIZONTAL_ALIGNMENT_LEFT)
		b.add_child(nm)
		var line := _label("", 40, 205, 198, CARD_W - 230.0, 60, HORIZONTAL_ALIGNMENT_LEFT)
		line.add_theme_color_override("font_color", Style.TEXT_SOFT)
		b.add_child(line)
		var level_up := _label("", 48, 205, 250, 600, 62, HORIZONTAL_ALIGNMENT_LEFT)   # "LEVEL UP 2 -> 3"
		level_up.add_theme_color_override("font_color", Style.WARNING)
		b.add_child(level_up)
		var combo := _label("COMBO!", 44, CARD_W - 270.0, 118, 240, 70, HORIZONTAL_ALIGNMENT_CENTER)
		var csb := Style.box(Style.ACCENT, Color(1, 1, 1, 0.9), Style.R_PILL, 3, true)   # a pill: it reads even before the word does
		csb.content_margin_left = 12
		csb.content_margin_right = 12
		combo.add_theme_stylebox_override("normal", csb)
		combo.add_theme_color_override("font_color", Style.TEXT_ON_LIGHT)
		combo.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.0))
		combo.visible = false
		b.add_child(combo)
		_parts.append({"icon": icon, "glyph": icon, "name": nm, "tag": tag, "pips": pips, "line": line, "combo": combo,
				"banner": banner, "bsb": bsb, "kind": kind_label, "watch": watch, "explain": explain, "level_up": level_up})
	relayout()
	get_viewport().size_changed.connect(relayout)

## The cards sit in the middle of the view (whatever its height), the title above them, below the safe area.
func relayout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var block := 3.0 * CARD_H + 2.0 * 30.0
	_top = maxf((vp.y - block) * 0.5 + 50.0, Style.safe_top + 300.0)
	_title.position.y = _top - 190.0
	if _build != null:
		_build.position = Vector2((vp.x - 1080.0) * 0.5, maxf(_top - 345.0, Style.safe_top + 6.0))

var _title: Label
var _build: BuildStrip

## The build held so far, shown above the title (Main calls it before show_cards).
func set_build(levels: Dictionary) -> void:
	if _build != null:
		_build.set_build(levels)
var _top := 400.0

func _label(text: String, size: int, x: float, y: float, w: float, h: float, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	Style.style_label(l, size)
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
		(p["icon"] as IconView).plate = c["color"]
		(p["icon"] as IconView).icon = c["glyph"]
		(p["name"] as Label).text = c["name"]
		(p["line"] as Label).text = c["line"]
		# the kind, readable at a glance: frame, banner and its facts
		(p["bsb"] as StyleBoxFlat).bg_color = kc.darkened(0.15)
		(p["kind"] as Label).text = "RARE PERK" if c.get("rare", false) else KIND_NAMES[kind]
		var is_combo: bool = i < combos.size() and combos[i] != ""
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb := b.get_theme_stylebox(state) as StyleBoxFlat
			var base := Style.SURFACE_DARK
			sb.bg_color = base.lightened(0.08) if state == "hover" else (base.lightened(0.16) if state == "pressed" else base)
			sb.border_color = Style.ACCENT if is_combo else kc
		for k in 3:
			var pip := (p["pips"] as Array)[k] as Panel
			pip.visible = kind == "perk"
			(pip.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Style.ACCENT if k < int(c["level"]) else Color(Style.INK, 0.6)
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
		b.position = Vector2(1200.0, _top + (CARD_H + 30.0) * i)
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
		{"kind": "perk", "id": "x", "name": "Lucky Whiskers", "glyph": "lucky_whiskers", "color": Color(1.0, 0.4, 0.85), "line": "50% can on Whisker closes 0123456789", "level": 2, "owned": true},
		{"kind": "boost", "id": "x", "name": "Magnet Storm", "glyph": "magnet_storm", "color": Color(0.8, 0.5, 1.0), "line": "Cans fly to you, 20 s", "level": 0, "owned": false},
		{"kind": "supply", "id": "x", "name": "Coin Bag", "glyph": "coin_bag", "color": Color(1.0, 0.8, 0.2), "line": "+1.5K coins now", "level": 0, "owned": false},
	]
	show_cards(sample, ["Combo", "", ""], false)
	for b in _cards:
		b.position.x = (1080.0 - CARD_W) * 0.5
	_born_ms = -100000   # (skip the slide)

func is_shown() -> bool:
	return shown
