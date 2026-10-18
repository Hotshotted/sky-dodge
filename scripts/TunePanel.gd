class_name TunePanel
extends Node
## On-screen tuning panel, built ONLY when the page URL has ?tune (players never see it).
## A TUNE button (top-right) opens a panel over the paused game; closing it resumes. Each slider
## edits the matching Tuning value live. "Copy values" puts the values that differ from the
## defaults on the clipboard as text (and shows them), and "Reset" restores the defaults.
## Everything is created once at start-up, drawn during the pre-warm, and only shown / hidden after
## that, like every other pooled part of the game.

## Emitted after a value changed (by a slider or Reset), with the Tuning property name.
signal changed(property: String)

## [Tuning property, label, min, max, step]: the values tuned most.
const ENTRIES := [
	["base_speed", "Start speed", 3.0, 15.0, 0.5],
	["max_speed", "Top speed", 10.0, 50.0, 1.0],
	["speed_ramp", "Speed ramp (per s)", 0.0, 1.0, 0.01],
	["speed_step", "Countryside speed step", 0.0, 8.0, 0.1],
	["fuel_drain", "Fuel drain (per s)", 0.5, 8.0, 0.1],
	["fuel_refill", "Fuel refill (per can)", 5.0, 60.0, 1.0],
	["fuel_can_chance", "Fuel can chance", 0.0, 1.0, 0.01],
	["near_miss_distance", "Near-miss distance", 0.1, 1.5, 0.05],
	["whisker_close_distance", "Whisker-close distance", 0.0, 0.3, 0.01],
	["obstacle_scale", "Obstacle scale", 0.3, 0.9, 0.01],
	["plane_tip_radius", "Plane tip radius", 0.05, 0.35, 0.01],
	["first_pick_min_seconds", "First pick: not before (s)", 0.0, 30.0, 1.0],
	["first_pick_max_seconds", "First pick: by (s)", 1.0, 60.0, 1.0],
	["bonus_cap", "Bonus cap", 1.5, 10.0, 0.1],
	["cloud_start_time", "Cloud start time (s)", 0.0, 120.0, 1.0],
	["cloud_frequency", "Clouds per row", 0.0, 2.0, 0.05],
	["cloud_max_drift", "Cloud drift", 0.0, 0.4, 0.01],
	["cloud_reveal_distance", "Cloud reveal distance", 4.0, 24.0, 0.5],
	["cloud_min_opacity", "Cloud min opacity", 0.0, 1.0, 0.05],
	["fuel_can_under_cloud_chance", "Can-under-cloud chance", 0.0, 1.0, 0.01],
	["ground_haze", "Background haze", 0.0, 1.0, 0.02],
	["ground_saturation", "Background colour", 0.0, 1.0, 0.02],
	["ground_blur_radius", "Background blur", 0.0, 4.0, 0.1],
	["shadow_alpha", "Obstacle shadow", 0.0, 0.8, 0.02],
	["sensitivity", "Sensitivity (1.0 = 1:1)", 0.3, 2.5, 0.05],
	["visual_smoothing", "Visual smoothing (s)", 0.0, 0.1, 0.005],
]

## [Tuning property, label]: on/off switches.
const TOGGLES := [
	["snap_enabled", "Soft snap on release"],
]

## Screen rect of the TUNE button, so the game can ignore touches that land on it.
static var _button_rect := Rect2()

## True if a touch at `pos` (viewport coordinates) is on the TUNE button.
static func button_hit(pos: Vector2) -> bool:
	return _button_rect.has_point(pos)

var _grant_idx := 0                 # ?tune: which perk the Grant button gives
var _grant_level := 3               # ...and at which level
var is_open := false
var last_copied_text := ""          # what the Copy button last put on the clipboard
var _defaults := {}                 # property -> default value, captured at build time
var _sliders := {}                  # property -> HSlider
var _value_labels := {}             # property -> Label
var _toggles := {}                  # property -> CheckButton
var _button_layer: CanvasLayer
var _panel_layer: CanvasLayer
var _button: Button
var _panel: Control
var _out: Label
var _status: Label                # top-left: the pattern being played and the wave phase

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps working while the game is paused

## Create everything (called once by Main, only when ?tune is on).
func build() -> void:
	for e in ENTRIES:
		_defaults[e[0]] = Tuning.get(e[0])
	for t in TOGGLES:
		_defaults[t[0]] = Tuning.get(t[0])
	# Shared look for every slider: a thick track and a big round handle (the default is tiny on a phone).
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.22, 0.27, 0.36)
	track.set_corner_radius_all(8)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.25, 0.8, 0.5)
	fill.set_corner_radius_all(8)
	fill.content_margin_top = 8
	fill.content_margin_bottom = 8
	var knob := _circle_texture(52, Color(0.95, 0.97, 1.0))
	var tick_off := _ring_texture(52, Color(0.7, 0.75, 0.85))   # big, readable on/off icons for the switch
	var tick_on := _circle_texture(52, Color(0.25, 0.9, 0.5))
	# The panel: a dark overlay over the whole screen. Hidden until opened; layer 0 so that during
	# the start-up pre-warm it is drawn UNDER the splash screen.
	_panel_layer = CanvasLayer.new()
	_panel_layer.layer = 0
	add_child(_panel_layer)
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	_panel_layer.add_child(_panel)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.11, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	margin.add_theme_constant_override("margin_top", 110)   # leaves room for the TUNE / CLOSE button
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	column.add_child(_make_label("TUNING  (live)", 44, HORIZONTAL_ALIGNMENT_LEFT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	for e in ENTRIES:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var head := HBoxContainer.new()
		var name_label := _make_label(e[1], 32, HORIZONTAL_ALIGNMENT_LEFT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value_label := _make_label("", 32, HORIZONTAL_ALIGNMENT_RIGHT)
		value_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7))
		head.add_child(name_label)
		head.add_child(value_label)
		row.add_child(head)
		var slider := HSlider.new()
		slider.min_value = e[2]
		slider.max_value = e[3]
		slider.step = e[4]
		slider.custom_minimum_size = Vector2(0, 60)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.add_theme_stylebox_override("slider", track)
		slider.add_theme_stylebox_override("grabber_area", fill)
		slider.add_theme_stylebox_override("grabber_area_highlight", fill)
		for icon in ["grabber", "grabber_highlight", "grabber_disabled"]:
			slider.add_theme_icon_override(icon, knob)
		slider.value = Tuning.get(e[0])
		slider.value_changed.connect(_on_slider.bind(e[0]))
		row.add_child(slider)
		list.add_child(row)
		_sliders[e[0]] = slider
		_value_labels[e[0]] = value_label
		_show_value(e[0])
	for t in TOGGLES:
		var check := CheckButton.new()
		check.text = t[1]
		check.add_theme_font_size_override("font_size", 32)
		check.custom_minimum_size = Vector2(0, 76)
		check.button_pressed = Tuning.get(t[0])
		check.add_theme_icon_override("unchecked", tick_off)
		check.add_theme_icon_override("checked", tick_on)
		check.toggled.connect(_on_toggle.bind(t[0]))
		list.add_child(check)
		_toggles[t[0]] = check
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	var reset := _make_button("Reset", 36)
	reset.pressed.connect(reset_defaults)
	var copy := _make_button("Copy values", 36)
	copy.pressed.connect(copy_values)
	buttons.add_child(reset)
	buttons.add_child(copy)
	column.add_child(buttons)
	var save_buttons := HBoxContainer.new()
	save_buttons.add_theme_constant_override("separation", 20)
	var add_coins := _make_button("Add 1M coins", 36)
	add_coins.pressed.connect(func(): Save.add_coins(1000000.0); _out.text = "Coins: %s" % Tuning.fmt(Save.coins))
	var reset_save := _make_button("Reset save", 36)
	reset_save.pressed.connect(func(): Save.reset_all(); _out.text = "Save reset.")
	var unlock_maps := _make_button("Unlock all maps", 36)
	unlock_maps.pressed.connect(func(): Save.unlock_all_maps(); _out.text = "All maps unlocked.")
	unlock_maps.set_meta("debug", "unlock_maps")
	save_buttons.add_child(add_coins)
	save_buttons.add_child(reset_save)
	column.add_child(save_buttons)
	var save_buttons2 := HBoxContainer.new()
	save_buttons2.add_theme_constant_override("separation", 20)
	var unlock_ms := _make_button("Unlock all milestones", 30)
	unlock_ms.pressed.connect(func(): Save.unlock_all_milestones(); _out.text = "All milestones unlocked.")
	unlock_ms.set_meta("debug", "unlock_milestones")
	save_buttons2.add_child(unlock_maps)
	save_buttons2.add_child(unlock_ms)
	column.add_child(save_buttons2)
	# Grant any perk at any level (applies to this run and every run after, until the save is reset).
	var grant_row := HBoxContainer.new()
	grant_row.add_theme_constant_override("separation", 12)
	var perk_btn := _make_button("Perk: %s" % Tuning.perks[0]["name"], 30)
	perk_btn.pressed.connect(func():
		_grant_idx = (_grant_idx + 1) % Tuning.perks.size()
		perk_btn.text = "Perk: %s" % Tuning.perks[_grant_idx]["name"])
	perk_btn.set_meta("debug", "perk_cycle")
	var level_btn := _make_button("Level: %d" % _grant_level, 30)
	level_btn.pressed.connect(func():
		_grant_level = (_grant_level + 1) % 4
		level_btn.text = "Level: %d" % _grant_level)
	level_btn.set_meta("debug", "level_cycle")
	var grant_btn := _make_button("Grant", 30)
	grant_btn.pressed.connect(grant_perk)
	grant_btn.set_meta("debug", "grant_perk")
	grant_row.add_child(perk_btn)
	grant_row.add_child(level_btn)
	grant_row.add_child(grant_btn)
	column.add_child(grant_row)
	var wave_btn := _make_button("Next wave phase", 30)
	wave_btn.pressed.connect(cycle_wave)
	wave_btn.set_meta("debug", "wave_cycle")
	column.add_child(wave_btn)
	var crash_row := HBoxContainer.new()
	var crash_btn := _make_button("Crash now", 30)
	crash_btn.pressed.connect(func():
		close()
		get_parent().debug_crash())
	crash_btn.set_meta("debug", "crash_now")
	var results_btn := _make_button("Preview results", 30)
	results_btn.pressed.connect(func():
		close()
		get_parent().debug_results())
	results_btn.set_meta("debug", "preview_results")
	crash_row.add_child(crash_btn)
	crash_row.add_child(results_btn)
	var tod_btn := _make_button("Time of day", 30)
	tod_btn.pressed.connect(func():
		get_parent().debug_cycle_tod()
		_out.text = "Time of day: %s" % ["morning", "day", "sunset", "dusk", "follows the run"][[0.0, 0.35, 0.7, 1.0, -1.0].find(get_parent().tod_override)])
	tod_btn.set_meta("debug", "time_of_day")
	crash_row.add_child(tod_btn)
	column.add_child(crash_row)
	add_coins.set_meta("debug", "add_coins")
	reset_save.set_meta("debug", "reset_save")
	_out = _make_label("", 26, HORIZONTAL_ALIGNMENT_LEFT)
	_out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_out.custom_minimum_size = Vector2(0, 150)
	column.add_child(_out)
	# The TUNE / CLOSE button, always on top, top-right. Hidden until the game has finished starting.
	_button_layer = CanvasLayer.new()
	_button_layer.layer = 20
	add_child(_button_layer)
	_button = _make_button("TUNE", 32)
	_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_left = -190.0
	_button.offset_right = -20.0
	_button.offset_top = 20.0
	_button.offset_bottom = 96.0
	_button.pressed.connect(toggle)
	_status = _make_label("", 24, HORIZONTAL_ALIGNMENT_LEFT)
	_status.position = Vector2(20.0, 150.0)
	_status.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
	_button_layer.add_child(_status)
	_button.visible = false
	_button_layer.add_child(_button)

func _process(_delta: float) -> void:
	_button_rect = _button.get_global_rect() if _button.visible else Rect2()
	var sp = get_parent().spawner
	_status.text = ("%s | %s" % [sp.pattern_name, sp.wave_name()]) if (sp.kit_on and _button.visible) else ""

## Jump to the next intensity-wave phase (CALM, BUILD, PEAK, BREATHER) now.
func cycle_wave() -> void:
	var sp = get_parent().spawner
	sp.cycle_wave()
	_out.text = "Wave phase: %s" % sp.wave_name()

## Show or hide the TUNE button (hidden while the game is still starting up).
func set_available(on: bool) -> void:
	_button.visible = on

## Start-up pre-warm: draw the panel (under the splash) so its fonts and widgets are set up.
func prewarm_show(on: bool) -> void:
	_panel.visible = on

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

## Open the panel over the game and pause it.
func open() -> void:
	is_open = true
	_panel_layer.layer = 19
	_panel.visible = true
	_button.text = "CLOSE"
	_out.text = ""
	get_tree().paused = true

## Close the panel and resume the game.
func close() -> void:
	is_open = false
	_panel.visible = false
	_panel_layer.layer = 0
	_button.text = "TUNE"
	get_tree().paused = false

func _on_slider(value: float, property: String) -> void:
	Tuning.set(property, value)
	_show_value(property)
	changed.emit(property)

func _on_toggle(on: bool, property: String) -> void:
	Tuning.set(property, on)
	changed.emit(property)

## Give the chosen perk at the chosen level: now, and at the start of every run.
func grant_perk() -> void:
	var main := get_parent()
	var id: String = Tuning.perks[_grant_idx]["id"]
	if _grant_level <= 0:
		main.picks.debug_grants.erase(id)
	else:
		main.picks.debug_grants[id] = _grant_level
	main.picks.set_perk(id, _grant_level)
	_out.text = "%s at level %d." % [Tuning.perks[_grant_idx]["name"], _grant_level]

## Put every tuned value back to its default (as captured when the panel was built).
func reset_defaults() -> void:
	for t in TOGGLES:
		var name: String = t[0]
		Tuning.set(name, _defaults[name])
		_toggles[name].set_pressed_no_signal(_defaults[name])
		changed.emit(name)
	for e in ENTRIES:
		var property: String = e[0]
		Tuning.set(property, _defaults[property])
		_sliders[property].set_value_no_signal(_defaults[property])
		_show_value(property)
		changed.emit(property)
	_out.text = "Reset to defaults."

## The values that differ from the defaults, one "name = value" per line, ready to paste.
func changed_text() -> String:
	var lines: Array[String] = []
	for e in ENTRIES:
		var property: String = e[0]
		var v: float = Tuning.get(property)
		if not is_equal_approx(v, _defaults[property]):
			lines.append("%s = %s" % [property, _format(v, e[4])])
	for t in TOGGLES:
		var name: String = t[0]
		if bool(Tuning.get(name)) != bool(_defaults[name]):
			lines.append("%s = %s" % [name, str(bool(Tuning.get(name))).to_lower()])
	return "(no changes)" if lines.is_empty() else "\n".join(lines)

## Copy the changed values to the clipboard and show them on screen too (in case the browser
## doesn't allow clipboard access).
func copy_values() -> void:
	last_copied_text = changed_text()
	DisplayServer.clipboard_set(last_copied_text)
	_out.text = "Copied:\n" + last_copied_text

func _show_value(property: String) -> void:
	var step: float = 0.0
	for e in ENTRIES:
		if e[0] == property:
			step = e[4]
	var v: float = Tuning.get(property)
	var text := _format(v, step)
	if not is_equal_approx(v, _defaults.get(property, v)):
		text += "   (default %s)" % _format(_defaults[property], step)
	_value_labels[property].text = text

## A number with as many decimals as the slider's step has (0.5 -> 1, 0.01 -> 2, 5 -> 0).
func _format(v: float, step: float) -> String:
	var decimals := 0
	var s := step
	while decimals < 4 and absf(s - roundf(s)) > 0.0001:
		s *= 10.0
		decimals += 1
	return ("%." + str(decimals) + "f") % v   # keeps trailing zeros: 0.50, not 0.5

func _make_label(text: String, size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _make_button(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(170, 76)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b

## A hollow ring, used as the "off" icon of the switch.
func _ring_texture(diameter: int, color: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var c := (diameter - 1) * 0.5
	for y in diameter:
		for x in diameter:
			var d := Vector2(x - c, y - c).length()
			var edge := clampf(c + 0.5 - d, 0.0, 1.0) * clampf(d - (c - 6.5), 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, edge))
	return ImageTexture.create_from_image(img)

## A filled circle, used as the slider handle.
func _circle_texture(diameter: int, color: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var c := (diameter - 1) * 0.5
	for y in diameter:
		for x in diameter:
			var d := Vector2(x - c, y - c).length()
			img.set_pixel(x, y, Color(color.r, color.g, color.b, clampf(c + 0.5 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
