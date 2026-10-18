extends SceneTree
## Headless smoke test:  godot --headless --path . --script res://tests/smoke_test.gd
## Exits with code 1 if anything below fails (CI runs this before exporting).
##   1. boot: the splash pre-warm draws every effect on screen, lasts long enough, then cleans up
##   2. three consecutive runs, each with near misses, ended by a crash and restarted IN PLACE by a
##      tap: the game-over UI shows the reason and score, the run resets, and NO new nodes,
##      materials or resources are created after start-up (pooled effects stay alive and warm)
##   2b. fuel: it drains, a can refills it (with a pooled pop), empty fuel ends the run with "Out of fuel"
##   2c. fuel can placement: only in open columns, never on the safe path, risk-biased
##   2d. tuning panel (?tune): opens over the paused game, sliders edit Tuning live and apply, Copy and
##       Reset work, closing resumes, and none of it allocates anything; absent without ?tune
##   2e. the opening: the first row reaches the plane after ~opening_seconds, and never starts on screen
##   2f. a tap on the TUNE button doesn't restart the game; a tap elsewhere does
##   2g. controls: the plane moves 1:1 with the finger (no momentum), clamps to the play area, banks from
##       its real velocity, snap and visual smoothing work; a fast flick through a cube still crashes and
##       through a can still collects it (swept collision)
##   2h. clouds (free-floating bundles): none before cloud_start_time, more of them with speed, varied
##       sizes, off the column grid, drifting; never cover every open column's centre line (thousands of
##       generated rows, checked every step), fade in late, sit above obstacles/cans but below the plane,
##       hide cans more often, ?nofx=clouds disables them, restart clears them, nothing new is allocated
##   2i. bonus: step-table streak bonus, cap (gold glowing label), steps coming off one by one, number-only text, reset on crash, huge caps
##   2p. frame time: clamp, stall dropping, resume skipping, pause / background accounting, the ?perf hitch log\n##   2o. crates (shapes, contents, ram rules, rewards, Crate Shower) and milestones\n##   2n. combos: each of the seven triggers (perk 3 + partner) and its effect, the banner, the Logbook\n##   2m. in-run picks: prices, pause + three cards, card odds, every perk / boost / supply effect\n##   2l. maps: unlocks, medals, palettes, gulls / wind gusts / lightning and their fairness rules
##   2k. Whisker close: doubled step, popup/burst, decay, cap, detection by clearance
##   2j. progression: save file round trip (versioned), coin award, Hangar purchases apply, ?tune save buttons
##   3. ?debug flags parse, and switching an effect off really skips it
##   4. plane collision capsules: span matches the wings, rounded corners graze past a cube corner
##   5. closest-approach near-miss detection reports the right side
##   7. Countryside kit: models, hit shapes, close calls for every kind (moving ones too), hay rules, nothing allocated
##   8. Countryside patterns (data, mirroring, every pattern flyable at its speeds, chaining, ?pattern=) and the intensity waves

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures.append(what)

## One pass of a kit thing by a plane that stays put at (0, kpz): the thing is placed `d` to the side (or off-line),
## the carrier scrolls by (crows and dusters fly on their own). Returns {hit, event}.
func _kit_pass(kit, carrier: Node3D, kind: int, d: float, kpz: float, kcaps: PackedFloat32Array) -> Dictionary:
	kit.release_all()
	kit.plane_x = 0.0
	kit.plane_z = kpz
	var moving := kind != 3
	carrier.position.z = (-30.0 if kind == 6 else kpz - 9.0) if moving else -8.0
	var vscroll := 7.0 if kind == 6 else 14.0
	kit.scroll_speed = vscroll
	match kind:
		0: kit.spawn(kind, carrier, 2.0 + d, 0.0, 1.2)
		9: kit.spawn(0, carrier, 3.2 + d, 0.0, 0.6, 1.0)   # a fly-through barn: pass beside it
		1:
			var k_tr = kit.spawn(kind, carrier, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0)   # a tractor, already driving
			k_tr.state = 2
			k_tr.solid = true
			k_tr.drops = 99
			k_tr.state_age = 0.47 - d * 0.2
		5: kit.spawn(kind, carrier, -5.0, 0.0, -d - 1.5); kit.spawn(kind, carrier, d + 1.5, 0.0, 5.0)
		3: kit.spawn(kind, carrier, 0.0, 0.0, 0.0, 0.0, d)
		6: kit.spawn(kind, carrier, 0.0, 0.0, d * 0.15 + 1.35, 0.0, 0.0, 0.0, 0.0, 1.0)
		4: kit.spawn(kind, carrier, 2.5 + d, 0.0, 0.0, 0.0, 1.0, 0.8, 0.0)
		2: kit.spawn(kind, carrier, 3.2 + d, 0.0, 0.0, 0.0, 0.0, 0.0, 0.7, 1.0)
		8: kit.spawn(kind, carrier, 1.4 + d, 0.0, 0.0, 1.0)
		_: kit.spawn(kind, carrier, 1.4 + d, 0.0, 0.0, 0.0, 0.5, 1.5, 0.3)
	var tn: Node = root.get_node("/root/Tuning")
	var hit := false
	var ev := false
	var events: Array[Dictionary] = []
	var behind := 0.0
	for o in range(0, kcaps.size(), 5):
		behind = maxf(behind, maxf(kcaps[o + 1], kcaps[o + 3]) + kcaps[o + 4])
	var steps := 0
	while steps < 600 and not hit:
		steps += 1
		if moving:
			carrier.position.z += vscroll / 60.0
		kit.update(1.0 / 60.0)
		if kit.hits(Vector2(0.0, kpz), kcaps):
			hit = true
		events.clear()
		kit.update_near_misses(Vector2(0.0, kpz), kcaps, tn.near_miss_distance, behind, events, tn.whisker_close_distance)
		if not events.is_empty():
			ev = true
		if moving and carrier.position.z > kpz + 9.0:
			break
	kit.release_all()
	return {"hit": hit, "event": ev}

func _cards_of(list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in list:
		out.append(c)
	return out

func real_wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		await process_frame

## Everything that exists in the game right now: node ids, material ids, and engine counters.
func snapshot(main: Node) -> Dictionary:
	var nodes := {}
	var mats := {}
	_walk(main, nodes, mats)
	# (materials built at start-up that only show up in this walk while something uses them: gulls, golden cans, crates)
	for pm in [main.spawner._gull_mat, main.spawner._golden_can_mat, main.spawner._crate_mat] + main.spawner._crate_glow_mats + main.spawner.kit.glow_mats + [main.spawner.kit.arrow_mat] + main.ground._field_mats:
		mats.erase(pm.get_instance_id())
	return {
		"nodes": nodes, "mats": mats,
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
	}

func _walk(n: Node, nodes: Dictionary, mats: Dictionary) -> void:
	nodes[n.get_instance_id()] = true
	var found: Array = []
	if n is GeometryInstance3D:
		found.append(n.material_override)
		found.append(n.material_overlay)
	if n is MeshInstance3D or n is CPUParticles3D:
		var mesh: Mesh = n.mesh
		if mesh is PrimitiveMesh:
			found.append(mesh.material)
		elif mesh != null:
			for i in mesh.get_surface_count():
				found.append(mesh.surface_get_material(i))
	for m in found:
		while m != null:
			mats[m.get_instance_id()] = true
			m = m.next_pass if m is BaseMaterial3D else null

	for c in n.get_children():
		_walk(c, nodes, mats)

func same_world(a: Dictionary, b: Dictionary) -> bool:
	return a["nodes"].hash() == b["nodes"].hash() and a["mats"].hash() == b["mats"].hash() \
			and a["node_count"] == b["node_count"] and a["resource_count"] == b["resource_count"]

func describe(a: Dictionary) -> String:
	return "%d nodes, %d materials, %d engine nodes, %d resources" % [a["nodes"].size(), a["mats"].size(), a["node_count"], a["resource_count"]]

## Feed the player a finger drag of `rel` viewport pixels (straight to its _input, in viewport units).
func drag_by(pl: Node, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	ev.position = Vector2(500.0, 900.0)
	ev.relative = rel
	pl._input(ev)

func get_paused() -> bool:
	return paused

func paused_ok(want: bool) -> bool:
	return paused == want

func tap() -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = true
	Input.parse_input_event(ev)

## Put an obstacle right on the plane, then let the next frame crash into it.
func force_crash(main: Node) -> void:
	var pl: Node = main.player
	main.spawner._rows_make_for_test(pl.position.z, [pl.position.x])
	main.score = 1234.0   # a known score to look for in the game-over text

## Fire n near misses through the real handler (sparks, streaks, flash, popup, trail, haptic, punch).
func do_near_misses(main: Node, n: int) -> void:
	for i in n:
		var row = main.spawner._rows_make_for_test(-5.0, [1.0])
		main._on_near_miss({"side": 1, "node": row.obs[0], "outline": row.outlines[0]})
		await real_wait(0.05)
		main.spawner._release_row(row)

func count_visible(nodes: Array) -> int:
	var c := 0
	for n in nodes:
		if n.visible:
			c += 1
	return c

func _initialize() -> void:
	var tuning := root.get_node("Tuning")
	tuning.blocked_columns_min = 4   # crowded rows: easy to crash on purpose
	tuning.blocked_columns_max = 4
	var save := root.get_node("Save")
	save.path = "user://smoke_test_save.json"   # never touch a real save
	save.reset_all()
	DebugFlags.parse(["tune"])   # the whole run has the tuning panel, so it is part of the "nothing new" baseline

	print("1. boot and the visible pre-warm")
	var t_boot := Time.get_ticks_msec()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main.picks.enabled = false   # (the tests set scores by hand; the pick tests switch it back on)
	tuning.crate_chance = 0.0    # (no random crates in the older tests; the crate tests switch them on)
	await process_frame
	await process_frame
	main.spawner.kit_enabled = false   # (the older tests count cubes on the Countryside; the kit tests switch the kit back on)
	main.spawner.kit_on = false
	await process_frame
	check(main._warming, "pre-warm is running at boot")
	check(is_instance_valid(main.hud._splash), "splash screen is shown during the pre-warm")
	var emitting := 0
	for e in main.fx._emitters:
		if e.emitting and e.visible:
			emitting += 1
	check(emitting == main.fx.SPARK_EMITTERS, "both spark emitters are drawing during the pre-warm (%d)" % emitting)
	check(count_visible(main.fx._streak_nodes) == main.fx.STREAK_POOL, "every pooled streak is visible during the pre-warm")
	check(main.trail._pts.size() >= 60 and main.trail._alpha > 0.0, "full-length trail ribbon is drawing (%d points)" % main.trail._pts.size())
	check(count_visible(main.hud._pop_labels) == main.hud.POPUP_POOL, "every pooled popup label is visible during the pre-warm")
	check(main.hud._over.visible, "game-over text is drawn during the pre-warm (font glyphs)")
	var cubes: Array = []
	for r in main.spawner._all_rows:
		cubes.append_array(r.cubes)
	check(cubes.size() == main.spawner.POOL_ROWS * tuning.column_count and count_visible(cubes) == cubes.size(),
			"every pooled obstacle cube (%d) is drawn during the pre-warm" % cubes.size())
	check(main.tune_panel != null and main.tune_panel._panel.visible and main.tune_panel._panel_layer.layer == 0,
			"?tune: the panel is drawn during the pre-warm, under the splash (layer 0)")
	check(not main.tune_panel._button.visible, "?tune: the TUNE button stays hidden while starting up")
	var cans: Array = []
	for r in main.spawner._all_rows:
		cans.append(r.can)
	check(count_visible(cans) == main.spawner.POOL_ROWS, "every pooled fuel can (%d) is drawn during the pre-warm" % cans.size())
	var blobs: Array = []
	for cl in main.spawner._all_clouds:
		blobs.append_array(cl.puffs)
	check(blobs.size() == main.spawner.CLOUD_POOL * main.spawner.PUFFS_PER_CLOUD and count_visible(blobs) == blobs.size(),
			"every pooled cloud puff (%d) is drawn during the pre-warm" % blobs.size())
	check(count_visible(main.fx._pickup_emitters) == main.fx.PICKUP_EMITTERS, "both fuel-pickup emitters are drawing during the pre-warm")
	check(count_visible(main.spawner.hazards._all_gusts) == main.spawner.hazards.GUST_POOL and count_visible(main.spawner.hazards._bolts) == main.spawner.hazards.BOLT_POOL, "every pooled wind gust and lightning strip is drawn during the pre-warm")
	check(main.pick_screen.is_shown() and count_visible(main.pick_screen._cards) == 3, "the pick cards are drawn during the pre-warm")
	check(main.hud._combo_label.visible and main.hud._logbook.visible, "the combo banner and the Logbook are drawn during the pre-warm")
	check(count_visible(main.fx._crate_emitters) == main.fx.CRATE_EMITTERS and count_visible(main.fx._coin_emitters) == main.fx.COIN_EMITTERS, "every crate-break and coin burst emitter is drawing during the pre-warm")
	check(count_visible(main.fx._whisker_emitters) == main.fx.WHISKER_EMITTERS, "both Whisker-close burst emitters are drawing during the pre-warm")
	var whisker_popup_drawn := false
	for pl_ in main.hud._pop_labels:
		whisker_popup_drawn = whisker_popup_drawn or (pl_.visible and pl_.text.begins_with(tuning.whisker_text) and pl_.get_theme_font_size("font_size") == tuning.whisker_size)
	check(whisker_popup_drawn, "the Whisker close popup is drawn at its own size during the pre-warm")
	var waited := 0.0
	while main._warming and waited < 12.0:
		await real_wait(0.1)
		waited += 0.1
	var boot_s := (Time.get_ticks_msec() - t_boot) / 1000.0
	check(not main._warming, "pre-warm finished (%.1f s)" % boot_s)
	check(boot_s >= tuning.prewarm_min_seconds, "pre-warm ran at least prewarm_min_seconds (%.1f s >= %.1f s)" % [boot_s, tuning.prewarm_min_seconds])
	await process_frame
	check(not is_instance_valid(main.hud._splash) or main.hud._splash.is_queued_for_deletion(), "splash removed afterwards")
	check(main.hud._bonus_label.text == "" and not main.hud._over.visible, "HUD back to normal (x1, no game-over text)")
	var in_play := 0   # cubes legitimately visible: the live game has started spawning its first row(s)
	for r in main.spawner._rows:
		in_play += r.xs.size()
	var cans_in_play := 0
	for r in main.spawner._rows:
		cans_in_play += int(r.has_can)
	check(count_visible(cans) == cans_in_play and count_visible(main.fx._pickup_emitters) == 0, "no pre-warm cans or pickup puffs left behind")
	check(count_visible(blobs) == 0, "no pre-warm cloud puffs left behind (no clouds in the first %.0f s)" % tuning.cloud_start_time)
	check(count_visible(cubes) == in_play and count_visible(main.fx._streak_nodes) == 0 and main.trail._pts.is_empty()
			and count_visible(main.fx._emitters) == 0 and count_visible(main.fx._whisker_emitters) == 0 and count_visible(main.fx._crate_emitters) == 0, "no pre-warm effects left behind (only the live game's own cubes are showing: %d)" % in_play)
	check(main.screen == main.SCREEN_MENU and main.hud._menu.visible and not main.alive and not main.hud._hangar.visible,
			"after start-up the start screen is showing and the world waits")
	main.hud.play_pressed.emit()   # PLAY
	check(main.alive and main.screen == main.SCREEN_PLAY and not main.hud._menu.visible, "PLAY starts a run")
	check(not main.tune_panel._panel.visible and main.tune_panel._button.visible, "?tune: panel hidden and TUNE button shown once started")

	print("1b. pre-warm length adapts to frame times")
	var saved_min: float = tuning.prewarm_min_seconds
	var saved_max: float = tuning.prewarm_max_seconds
	var saved_ms: float = tuning.prewarm_stable_ms
	tuning.prewarm_min_seconds = 0.3
	tuning.prewarm_max_seconds = 1.2
	tuning.prewarm_stable_ms = 0.0001     # no frame is ever "calm": must stop at the hard cap
	var t1 := Time.get_ticks_msec()
	await main._prewarm()
	var never_calm_s := (Time.get_ticks_msec() - t1) / 1000.0
	check(never_calm_s >= 1.15 and never_calm_s < 1.6, "frames never settle -> stops at prewarm_max_seconds (%.2f s, cap 1.2)" % never_calm_s)
	tuning.prewarm_stable_ms = 100000.0   # every frame is calm: stops as soon as the minimum has passed
	t1 = Time.get_ticks_msec()
	await main._prewarm()
	var calm_s := (Time.get_ticks_msec() - t1) / 1000.0
	check(calm_s >= 0.3 and calm_s < 0.7, "frames calm -> stops soon after prewarm_min_seconds (%.2f s, min 0.3)" % calm_s)
	tuning.prewarm_min_seconds = saved_min
	tuning.prewarm_max_seconds = saved_max
	tuning.prewarm_stable_ms = saved_ms
	check(not main._warming and count_visible(main.fx._streak_nodes) == 0, "repeat pre-warm cleans up after itself")
	main.hud.play_pressed.emit()   # (the pre-warm ends on the start screen)

	print("2. three runs, restarted in place")
	await process_frame
	var base := snapshot(main)
	print("  start-up world: " + describe(base))
	var first_instance := main
	for run in [1, 2, 3]:
		print("  -- run %d --" % run)
		check(main.score < 100.0 and main.bonus == 1 and main.alive and main.fuel > tuning.fuel_start - 5.0,
				"run %d starts fresh (score %d, x%.1f, fuel %.0f)" % [run, int(main.score), main.bonus, main.fuel])
		check(not main.hud._over.visible, "game-over UI hidden while playing")
		await do_near_misses(main, 3)
		check(is_equal_approx(main.bonus, tuning.streak_bonus(3)) and main.hud._bonus_label.text == "x%.1f" % main.bonus, "three close calls give x%.1f (%s)" % [main.bonus, main.hud._bonus_label.text])
		check(count_visible(main.hud._pop_labels) >= 1 and count_visible(main.fx._emitters) >= 1, "popup and sparks are showing")
		# fuel: drains; a can refills it with a pooled pop
		var f0: float = main.fuel
		await real_wait(0.4)
		check(main.fuel < f0 and absf((f0 - main.fuel) - tuning.fuel_drain * 0.4) < tuning.fuel_drain * 0.25,
				"fuel drains at about fuel_drain (%.2f in 0.4 s, expect ~%.2f)" % [f0 - main.fuel, tuning.fuel_drain * 0.4])
		main.fuel = 40.0
		var can_row = main.spawner._rows_make_for_test(main.player.position.z, [])
		main.spawner._place_can_for_test(can_row, main.player.position.x)
		await real_wait(0.1)
		check(not can_row.has_can and not can_row.can.visible, "driving into a can collects it")
		check(absf(main.fuel - (40.0 + tuning.fuel_refill)) < 1.5, "a can refills fuel_refill (%.1f -> %.1f)" % [40.0, main.fuel])
		check(count_visible(main.fx._pickup_emitters) >= 1 and main.hud._fuel_pulse_ms > 0, "the pickup pop (emitter + gauge flash) is showing")
		main.fuel = tuning.fuel_start - 5.0
		var cap_row = main.spawner._rows_make_for_test(main.player.position.z, [])
		main.spawner._place_can_for_test(cap_row, main.player.position.x)
		await real_wait(0.1)
		check(main.fuel <= tuning.fuel_start + 0.001, "a refill never goes above a full tank (%.1f)" % main.fuel)
		var snap := snapshot(main)
		check(same_world(base, snap), "near misses created nothing new  [%s]" % describe(snap))
		if run == 3:
			break
		var header: String = main.HEADER_CRASH
		var reason: String = main.REASON_OBSTACLE
		if run == 2:   # this run ends by running dry instead
			header = main.HEADER_FUEL
			reason = main.REASON_FUEL
			main.score = 1234.0
			main.fuel = 0.05
			await real_wait(0.3)
		else:
			force_crash(main)
			await real_wait(0.2)
		check(not main.alive, "run %d ends (%s)" % [run, header])
		check(main.hud._over.visible, "game-over UI is visible")
		var shown: String = main.hud._over.text
		var other_header: String = main.HEADER_FUEL if run != 2 else main.HEADER_CRASH
		check(shown.begins_with(header + "\n") and shown.contains(reason) and shown.contains("+1.2K coins") and not shown.contains(other_header),
				"game-over header is \"%s\" with \"%s\" and the score, not \"%s\"  (\"%s\")" % [header, reason, other_header, shown.replace("\n", " | ")])
		check(run != 2 or main.fuel <= 0.0, "out-of-fuel run ended with an empty tank")
		await real_wait(0.6)   # Main ignores PLAY AGAIN for 0.4 s after a crash
		main.hud.play_again_pressed.emit()
		await real_wait(0.3)
		check(main == first_instance and current_scene == first_instance, "PLAY AGAIN restarted the run IN PLACE (same scene instance)")
		check(main.alive and main.score < 100.0 and main.bonus == 1, "restart reset score and bonus")
		check(main.fuel > tuning.fuel_start - tuning.fuel_drain, "restart refilled the tank (%.1f / %.0f)" % [main.fuel, tuning.fuel_start])
		check(absf(main.hud._fuel_frac - main.fuel / tuning.fuel_start) < 0.05, "fuel gauge shows the full tank again")
		check(not main.hud._over.visible and main.hud._bonus_label.text == "", "game-over UI hidden, bonus label reset")
		check(count_visible(main.hud._pop_labels) == 0 and main.trail._pts.is_empty(), "old popups and trail cleared")
		check(main.player.active and absf(main.player.position.x) < 0.01 and main.player.velocity == Vector2.ZERO, "plane is back at the start")
		var stale_rows := 0   # anything near the plane would be left over from the previous run
		for r in main.spawner._rows:
			if r.position.z > -4.0:   # a leftover would be near the plane; the new run's first row is far above
				stale_rows += 1
		check(stale_rows == 0, "previous run's obstacles are gone (%d rows, new run's own rows are far above)" % main.spawner._rows.size())
		var after := snapshot(main)
		check(same_world(base, after), "restart created nothing new  [%s]" % describe(after))

	print("2d. tuning panel")
	var panel = main.tune_panel   # (untyped: naming the class would compile it before the autoloads exist)
	var defaults := {}
	for e in panel.ENTRIES:
		defaults[e[0]] = tuning.get(e[0])
	for t in panel.TOGGLES:
		defaults[t[0]] = tuning.get(t[0])
	check(panel.ENTRIES.size() == 26 and panel._sliders.size() == 26 and panel._toggles.size() == 1, "26 sliders and 1 on/off switch for the tuned values")
	var all_match := true
	for e in panel.ENTRIES:
		if not is_equal_approx(panel._sliders[e[0]].value, tuning.get(e[0])):
			all_match = false
	check(all_match, "each slider starts at the current Tuning value")
	var events: Array[String] = []
	panel.changed.connect(func(property: String) -> void: events.append(property))
	panel.open()
	check(paused and panel.is_open and panel._panel.visible and panel._panel_layer.layer == 19 and panel._button.text == "CLOSE",
			"opening the panel pauses the game and shows it over everything")
	var score_open: float = main.score
	await real_wait(0.3)
	check(main.score == score_open, "the game is really paused while the panel is open")
	panel._sliders["fuel_drain"].value = 4.0
	check(is_equal_approx(tuning.fuel_drain, 4.0) and events.has("fuel_drain"), "dragging a slider edits Tuning live (fuel_drain = %.1f)" % tuning.fuel_drain)
	check(panel._value_labels["fuel_drain"].text.contains("4.0") and panel._value_labels["fuel_drain"].text.contains("default"), "the label shows the value and the default (\"%s\")" % panel._value_labels["fuel_drain"].text)
	var live_row = main.spawner._rows_make_for_test(-5.0, [1.0])
	panel._sliders["obstacle_scale"].value = 0.5
	check(absf(live_row.obs[0].scale.x - tuning.column_width() * 0.5) < 0.001, "obstacle scale applies to rows already on screen")
	panel._sliders["plane_tip_radius"].value = 0.30
	panel._sliders["base_speed"].value = 9.0
	panel._sliders["sensitivity"].value = 1.5
	panel._toggles["snap_enabled"].button_pressed = true
	check(tuning.snap_enabled and events.has("snap_enabled") and is_equal_approx(tuning.sensitivity, 1.5), "the sensitivity slider and the snap switch edit Tuning live")
	panel.copy_values()
	var copied: String = panel.last_copied_text
	check(copied.contains("fuel_drain = 4.0") and copied.contains("obstacle_scale = 0.50") and copied.contains("plane_tip_radius = 0.30")
			and copied.contains("base_speed = 9.0") and copied.contains("sensitivity = 1.50") and copied.contains("snap_enabled = true")
			and not copied.contains("fuel_refill"),
			"Copy values lists only what changed  (\"%s\")" % copied.replace("\n", "; "))
	check(panel._out.text.begins_with("Copied"), "the copied text is also shown on screen")
	panel.reset_defaults()
	var back := true
	for e in panel.ENTRIES:
		if not is_equal_approx(tuning.get(e[0]), defaults[e[0]]) or not is_equal_approx(panel._sliders[e[0]].value, defaults[e[0]]):
			back = false
	back = back and not tuning.snap_enabled and not panel._toggles["snap_enabled"].button_pressed
	check(back and panel.changed_text() == "(no changes)", "Reset restores every default (sliders and the snap switch)")
	check(absf(live_row.obs[0].scale.x - tuning.column_width() * tuning.obstacle_scale) < 0.001, "...including the obstacle size on screen")
	panel._sliders["plane_tip_radius"].value = 0.30   # leave one visual change to check after resuming
	panel.close()
	check(not paused and not panel.is_open and not panel._panel.visible and panel._button.text == "TUNE", "closing the panel resumes the game")
	await real_wait(0.2)
	check(main.score > score_open, "...and it is running again")
	check(main.player._wing_built_for == 0.30, "the visible wing was reshaped for the new tip radius")
	var panel_tip := 1.0
	var caps2: PackedFloat32Array = main.player.hit_capsules()
	for o in range(0, caps2.size() - 5, 5):
		panel_tip = minf(panel_tip, caps2[o + 4])
	check(absf(panel_tip - 0.30 * tuning.plane_hit_scale) < 0.02, "...and the collision follows it (tip circle %.3f)" % panel_tip)
	panel.reset_defaults()
	main.spawner.reset(-30.0)
	await real_wait(0.1)
	var after_panel := snapshot(main)
	check(same_world(base, after_panel), "opening, editing, copying, resetting and closing created nothing new  [%s]" % describe(after_panel))

	print("2e. the opening")
	main.restart()
	main.set_process(false)   # step the game by hand
	var plane_z: float = main.player.position.z
	var first_row_z: float = main._first_row_z(main._half_height())
	check(first_row_z <= -(main._half_height() + 1.0) + 0.001, "the first row starts above the screen (z %.1f, screen top %.1f)" % [first_row_z, -main._half_height()])
	var saved_blk_a: int = tuning.blocked_columns_min   # no cubes, so the plane can't crash into the row we're timing
	var saved_blk_b: int = tuning.blocked_columns_max
	tuning.blocked_columns_min = 0
	tuning.blocked_columns_max = 0
	main.spawner.reset(first_row_z)
	var open_t := 0.0
	var arrived := -1.0
	while open_t < 6.0 and arrived < 0.0:
		main._process(1.0 / 60.0)
		open_t += 1.0 / 60.0
		for r in main.spawner._rows:
			if arrived < 0.0 and r.position.z >= main.player.position.z:
				arrived = open_t
	check(arrived > 0.0 and absf(arrived - tuning.opening_seconds) < 0.25 + (0.0 if first_row_z < -(main._half_height() + 1.0) + 0.01 else 1.0),
			"the first row reaches the plane after %.2f s (opening_seconds %.1f)" % [arrived, tuning.opening_seconds])
	tuning.blocked_columns_min = saved_blk_a
	tuning.blocked_columns_max = saved_blk_b
	var z_short: float = main._first_row_z(3.0)
	var z_tall: float = main._first_row_z(25.0)
	var travel: float = tuning.base_speed * tuning.opening_seconds + 0.5 * tuning.speed_ramp * tuning.opening_seconds * tuning.opening_seconds
	check(absf(z_short - (plane_z - travel)) < 0.001, "on a short screen the row starts exactly opening_seconds away")
	check(z_tall <= -26.0 + 0.001, "on a very tall screen it never starts on screen (z %.1f)" % z_tall)
	main.restart()

	print("2f. the TUNE button doesn't restart the game")
	await real_wait(0.3)   # let the button's rect settle
	force_crash(main)
	main.set_process(true)
	await real_wait(0.2)
	check(not main.alive, "crashed")
	await real_wait(0.6)
	var press := InputEventScreenTouch.new()
	press.pressed = true
	press.position = panel._button_rect.get_center()
	main._input(press)
	check(not main.alive and panel.button_hit(press.position), "a tap on the TUNE button is ignored by the game (still on the game-over screen)")
	var elsewhere := InputEventScreenTouch.new()
	elsewhere.pressed = true
	elsewhere.position = Vector2(100.0, 900.0)
	main._input(elsewhere)
	check(not main.alive, "a tap on the results screen only skips its build-up")
	main.hud.play_again_pressed.emit()
	check(main.alive, "PLAY AGAIN restarts")

	main.set_process(false)   # freeze the game loop: no real obstacles or near misses while the rest pokes at things

	print("2g. controls: 1:1 follow, no momentum, swept collision")
	var saved_ctl := {"blocked_a": tuning.blocked_columns_min, "blocked_b": tuning.blocked_columns_max, "chance": tuning.fuel_can_chance,
			"sens": tuning.sensitivity, "smooth": tuning.visual_smoothing, "snap": tuning.snap_enabled}
	tuning.blocked_columns_min = 0
	tuning.blocked_columns_max = 0
	tuning.fuel_can_chance = 0.0
	tuning.sensitivity = 1.0
	tuning.visual_smoothing = 0.0
	tuning.snap_enabled = false
	main.restart()
	var pc = main.player
	var spc = main.spawner
	spc.reset(-200.0)   # nothing near the plane unless the test puts it there
	var wpp: float = pc.world_per_pixel()
	var stretch: float = 1.0 / cos(deg_to_rad(tuning.camera_tilt_deg))
	var dt := 1.0 / 60.0
	var x_start: float = pc.position.x
	var z_start: float = pc.position.z
	drag_by(pc, Vector2(120.0, 0.0))
	main._process(dt)
	check(absf((pc.position.x - x_start) - 120.0 * wpp) < 0.0001, "a 120 px drag moves the plane exactly 120 px of screen (%.4f units, expect %.4f)" % [pc.position.x - x_start, 120.0 * wpp])
	drag_by(pc, Vector2(0.0, -60.0))
	main._process(dt)
	check(absf((pc.position.z - z_start) - (-60.0 * wpp * stretch)) < 0.0001, "up/down drags follow 1:1 on screen too (tilt-corrected)")
	var x_now: float = pc.position.x
	var v_move: float = pc.velocity.length()
	main._process(dt)
	main._process(dt)
	check(pc.position.x == x_now and pc.velocity.length() < 0.0001 and v_move > 1.0, "no momentum: the plane stops the instant the finger does")
	drag_by(pc, Vector2(60.0, 0.0))
	main._process(dt)
	check(absf(pc.velocity.x - 60.0 * wpp / dt) < 0.01, "velocity is the plane's actual movement (%.2f u/s)" % pc.velocity.x)
	tuning.sensitivity = 0.5
	x_now = pc.position.x
	drag_by(pc, Vector2(100.0, 0.0))
	main._process(dt)
	check(absf((pc.position.x - x_now) - 50.0 * wpp) < 0.0001, "sensitivity 0.5 moves the plane half as far")
	tuning.sensitivity = 1.0
	drag_by(pc, Vector2(100000.0, 0.0))
	main._process(dt)
	var x_limit: float = tuning.ortho_size * 0.5 - tuning.plane_edge_margin
	check(absf(pc.position.x - x_limit) < 0.0001, "a huge drag is clamped to the play area (x = %.2f)" % pc.position.x)
	check(main.alive, "...and flying into the screen edge doesn't crash")
	drag_by(pc, Vector2(0.0, 100000.0))
	main._process(dt)
	check(absf(pc.position.z - pc.z_max) < 0.0001, "...and so is the forward/back range")
	# banking and yaw follow the real velocity, smoothed, and stay bounded
	pc.position.x = -2.0
	for i in 8:
		drag_by(pc, Vector2(80.0, 0.0))
		main._process(dt)
	var roll: float = pc._model.rotation.z
	var yaw: float = pc._model.rotation.y
	check(roll < -0.05 and roll >= -tuning.bank_max - 0.001 and yaw < 0.0 and yaw >= -tuning.yaw_max - 0.001,
			"moving right banks and yaws the plane, within limits (roll %.2f, yaw %.2f)" % [roll, yaw])
	for i in 60:
		main._process(dt)
	check(absf(pc._model.rotation.z) < 0.02, "it levels out again once it stops")
	# soft snap: off by default, eases to the nearest column centre when on, never while the finger is down
	pc.position.x = 0.8
	pc.touching = false
	for i in 90:
		main._process(dt)
	check(absf(pc.position.x - 0.8) < 0.0001, "snap off: the plane stays exactly where the finger left it")
	tuning.snap_enabled = true
	pc.touching = true
	for i in 30:
		main._process(dt)
	check(absf(pc.position.x - 0.8) < 0.0001, "snap on, finger down: no snapping")
	pc.touching = false
	for i in 120:
		main._process(dt)
	check(absf(pc.position.x - 0.0) < 0.01, "snap on, finger lifted: eases to the nearest column centre (x = %.3f)" % pc.position.x)
	tuning.snap_enabled = false
	# visual smoothing lags only the DRAWN plane, never the collision position
	tuning.visual_smoothing = 0.1
	x_now = pc.position.x
	drag_by(pc, Vector2(200.0, 0.0))
	main._process(dt)
	check(absf((pc.position.x - x_now) - 200.0 * wpp) < 0.0001 and pc._model.position.length() > 0.2,
			"visual smoothing: true position jumps, the drawn plane trails (%.2f behind)" % pc._model.position.length())
	for i in 60:
		main._process(dt)
	check(pc._model.position.length() < 0.05, "...and catches up")
	tuning.visual_smoothing = 0.0
	drag_by(pc, Vector2(200.0, 0.0))
	main._process(dt)
	check(pc._model.position == Vector3.ZERO, "smoothing 0: the drawn plane is exactly on the true position")

	# swept collision: a flick of 6 units in ONE frame
	main.restart()
	spc.reset(-200.0)
	pc.position.x = -3.0
	var cube_row = spc._rows_make_for_test(pc.position.z, [0.0])
	var end_x := 3.0
	var end_clear: bool = not spc.hits(Vector2(end_x, pc.position.z), pc.hit_capsules())
	drag_by(pc, Vector2((end_x - pc.position.x) / wpp, 0.0))
	main._process(dt)
	check(end_clear, "(setup) the flick's END point alone is clear of the cube, so only a swept test can see it")
	check(not main.alive and main.hud._over.text.contains(main.HEADER_CRASH), "a fast flick through a cube crashes")
	var touch_x: float = -(spc._obstacle_half().x + pc.collision_half_span())   # wingtip meets the cube's left edge
	check(absf(pc.position.x - touch_x) < 0.02, "...stopping exactly where it first touched, not inside it or on the far side (x = %.3f, touch at %.3f)" % [pc.position.x, touch_x])
	main.restart()
	spc.reset(-200.0)
	pc.position.x = -3.0
	spc._rows_make_for_test(pc.position.z, [])   # an empty row: nothing to hit
	drag_by(pc, Vector2(6.0 / wpp, 0.0))
	main._process(dt)
	check(main.alive and absf(pc.position.x - 3.0) < 0.0001, "the same flick through empty space is fine")
	# ...and through a fuel can
	main.restart()
	spc.reset(-200.0)
	pc.position.x = -3.0
	main.fuel = 50.0
	var can_row = spc._rows_make_for_test(pc.position.z, [])
	spc._place_can_for_test(can_row, 0.0)
	var cans_caps: PackedFloat32Array = pc.hit_capsules()
	var closest := INF
	for o in range(0, cans_caps.size(), 5):
		closest = minf(closest, Vector2(end_x + cans_caps[o], pc.position.z + cans_caps[o + 1]).distance_to(Vector2(0.0, can_row.position.z)) - cans_caps[o + 4])
	drag_by(pc, Vector2((end_x - pc.position.x) / wpp, 0.0))
	main._process(dt)
	check(closest > tuning.fuel_pickup_radius, "(setup) the flick's end point alone would miss the can (%.2f away)" % closest)
	check(not can_row.has_can and main.fuel > 50.0 + tuning.fuel_refill - 1.0, "a fast flick through a fuel can collects it (fuel %.1f)" % main.fuel)
	check(main.alive, "...without crashing")
	tuning.blocked_columns_min = saved_ctl["blocked_a"]
	tuning.blocked_columns_max = saved_ctl["blocked_b"]
	tuning.fuel_can_chance = saved_ctl["chance"]
	tuning.sensitivity = saved_ctl["sens"]
	tuning.visual_smoothing = saved_ctl["smooth"]
	tuning.snap_enabled = saved_ctl["snap"]
	main.restart()
	main.set_process(false)
	await real_wait(1.2)      # let the last popup / streaks / flash expire
	var sp: Node = main.spawner
	var pl: Node = main.player

	print("2c. fuel can placement")
	var saved_chance: float = tuning.fuel_can_chance
	var saved_bias: float = tuning.fuel_risk_bias
	var saved_blk_min: int = tuning.blocked_columns_min   # the test's "crowded" rows leave one open column: no risky spot
	var saved_blk_max: int = tuning.blocked_columns_max
	tuning.blocked_columns_min = 2
	tuning.blocked_columns_max = 3
	tuning.fuel_can_chance = 1.0
	tuning.fuel_risk_bias = 1.0     # strict: risky spots only
	var n: int = tuning.column_count
	var bad_open := 0
	var on_safe := 0
	var not_risky := 0
	var placed := 0
	var rows := 4000
	var prev: Array[bool] = []
	for i in n:
		prev.append(true)
	var safe := n / 2
	for i in rows:
		var open: Array[bool] = sp._generate_open_columns(prev)
		var next_open: Array[bool] = sp._generate_open_columns(open)
		safe = sp._pick_safe_col(open, safe)
		var c: int = sp._choose_can_column(open, next_open, safe)
		if c >= 0:
			placed += 1
			if not open[c]:
				bad_open += 1
			if c == safe:
				on_safe += 1
			var beside := (c > 0 and not open[c - 1]) or (c < n - 1 and not open[c + 1])
			if not (beside or not next_open[c]):
				not_risky += 1
		prev = open
	check(placed > rows * 0.5, "cans are placed in most rows when chance is 1 (%d of %d)" % [placed, rows])
	check(bad_open == 0, "a can is never inside an obstacle column")
	check(on_safe == 0, "with risk bias 1 a can is never on the main safe path")
	check(not_risky == 0, "with risk bias 1 every can is next to an obstacle or in a column that closes next row")
	# bias 0: any open column, so some cans land on the safe path
	tuning.fuel_risk_bias = 0.0
	var any_on_safe := 0
	var any_placed := 0
	prev = []
	for i in n:
		prev.append(true)
	for i in rows:
		var open2: Array[bool] = sp._generate_open_columns(prev)
		var next2: Array[bool] = sp._generate_open_columns(open2)
		safe = sp._pick_safe_col(open2, safe)
		var c2: int = sp._choose_can_column(open2, next2, safe)
		if c2 >= 0:
			any_placed += 1
			if c2 == safe:
				any_on_safe += 1
		prev = open2
	check(any_on_safe > any_placed * 0.15, "with bias 0 cans also land on the safe path (%d of %d)" % [any_on_safe, any_placed])
	# lookahead: the "next row" the can placement saw is the row that really spawns next
	tuning.fuel_can_chance = 0.0
	sp.reset()
	sp._spawn_row(-30.0)
	var predicted: Array[bool] = sp._pending_open.duplicate()
	sp._spawn_row(-40.0)
	var actual_xs: Array[float] = sp._rows[-1].xs.duplicate()
	var matches := true
	for i in n:
		var blocked_in_row := actual_xs.any(func(x): return absf(x - tuning.column_center(i)) < 0.01)
		if blocked_in_row == predicted[i]:
			matches = false
	check(matches, "can placement looks at the real next row (lookahead matches the row that spawns)")
	sp.reset()
	tuning.fuel_can_chance = saved_chance
	tuning.fuel_risk_bias = saved_bias
	tuning.blocked_columns_min = saved_blk_min
	tuning.blocked_columns_max = saved_blk_max

	print("2h. clouds")
	var cl_saved := {"start": tuning.cloud_start_time, "freq": tuning.cloud_frequency, "chance": tuning.fuel_can_chance,
			"under": tuning.fuel_can_under_cloud_chance, "bias": tuning.fuel_risk_bias, "bmin": tuning.blocked_columns_min, "bmax": tuning.blocked_columns_max}
	tuning.blocked_columns_min = 2
	tuning.blocked_columns_max = 3
	var ncol: int = tuning.column_count
	sp.reset()
	var step := 1.5
	sp.plane_z = 4.0
	# (a) nothing before cloud_start_time
	tuning.cloud_start_time = 25.0
	tuning.cloud_frequency = 1.0
	sp.run_time = 5.0
	sp.scroll_speed = 12.0
	var early := 0
	for i in 400:
		sp.advance(step)
		early += sp._clouds.size()
	check(early == 0, "no clouds before cloud_start_time (%d bundle-steps in 400 steps)" % early)
	# (b) the frequency grows with speed (average bundles alive over the same distance)
	tuning.cloud_frequency = 0.3
	sp.run_time = 30.0
	var at_start_speed: float = tuning.base_speed + tuning.speed_ramp * tuning.cloud_start_time
	var alive := []
	for spd in [at_start_speed, tuning.max_speed]:
		sp.scroll_speed = spd
		sp.reset()
		var total := 0
		for i in 3000:
			sp.advance(step)
			total += sp._clouds.size()
		alive.append(float(total) / 3000.0)
	check(alive[0] > 0.5 and alive[1] > alive[0] * 1.4, "clouds come more often at speed: %.1f bundles alive at start speed, %.1f at top speed" % [alive[0], alive[1]])
	# (c) fairness over thousands of rows, with clouds as frequent as possible, checked at EVERY step:
	# every row ahead of the plane keeps an open column whose centre line no visible puff covers now
	# or while it drifts to the plane.
	tuning.cloud_frequency = 1.5
	sp.scroll_speed = tuning.max_speed
	sp.run_time = 100.0
	tuning.fuel_can_chance = 0.18
	tuning.fuel_can_under_cloud_chance = 0.45
	tuning.fuel_risk_bias = 1.0
	sp.reset()
	sp.puffs_removed = 0
	var rows_n := 3000
	var seen_rows := 0
	var cloud_rows := 0
	var covered_gaps := 0
	var covered_cubes := 0
	var unfair := 0
	var eligible := 0
	var can_under := 0
	var can_on_safe := 0
	var last_row = null
	var rmin := INF
	var rmax := 0.0
	var off_grid := 0
	var bundles := 0
	var sizes := {}
	var max_alive := 0
	var st := {"bundles": 0, "rmin": INF, "rmax": 0.0, "off": 0}
	var on_spawn := func(cl):
		st["bundles"] += 1
		var used := 0
		for k in cl.puffs.size():
			used += int(cl.on[k])
			if cl.on[k]:
				st["rmin"] = minf(st["rmin"], cl.rad[k])
				st["rmax"] = maxf(st["rmax"], cl.rad[k])
		sizes[clampi(used, 1, 7)] = true
		var nearest := INF
		for c in ncol:
			nearest = minf(nearest, absf(cl.position.x - tuning.column_center(c)))
		st["off"] += int(nearest > 0.3)
	sp.cloud_spawned.connect(on_spawn)
	while seen_rows < rows_n:
		sp.advance(step)
		max_alive = maxi(max_alive, sp._clouds.size())
		for r in sp._rows:
			if r.open.is_empty() or r.position.z > sp.plane_z:
				continue
			if sp._clear_column(r) < 0:
				unfair += 1
		var fr = sp._rows[-1]
		if fr != last_row:
			last_row = fr
			seen_rows += 1
			var safe_c: int = sp._safe_col
			var any_cov := false
			var cov_open_not_safe := false
			for c in ncol:
				if fr.cloud_cov[c]:
					any_cov = true
					covered_gaps += 1
					if c != safe_c:
						cov_open_not_safe = true
				elif fr.open[c] == false and sp._covered(fr.position.z, tuning.column_center(c)):
					covered_cubes += 1
			cloud_rows += int(any_cov)
			if cov_open_not_safe:
				eligible += 1
				if fr.has_can:
					for c in ncol:
						if fr.cloud_cov[c] and absf(fr.can_x - tuning.column_center(c)) < 0.01:
							can_under += 1
			if fr.has_can and absf(fr.can_x - tuning.column_center(safe_c)) < 0.01:
				can_on_safe += 1
	sp.cloud_spawned.disconnect(on_spawn)
	bundles = st["bundles"]
	rmin = st["rmin"]
	rmax = st["rmax"]
	off_grid = st["off"]
	check(unfair == 0, "FAIRNESS: over %d generated rows (%d with open gaps under cloud) no row ever lost every open column's centre line to cloud" % [seen_rows, cloud_rows])
	check(covered_gaps > 500 and covered_cubes > 300 and sp.puffs_removed > 50,
			"(not vacuous) clouds covered %d open gaps and %d cubes, and the rule had to remove %d puffs" % [covered_gaps, covered_cubes, sp.puffs_removed])
	check(bundles > 300 and rmin < 1.2 and rmax > 2.0 and sizes.size() >= 5,
			"bundles vary: %d of them, puff radius %.1f to %.1f, %d different puff counts" % [bundles, rmin, rmax, sizes.size()])
	check(float(off_grid) / bundles > 0.5, "they are not snapped to the columns (%.0f%% sit more than 0.3 from a column centre)" % (100.0 * off_grid / bundles))
	check(max_alive <= sp.CLOUD_POOL, "never more bundles than the pool (%d <= %d)" % [max_alive, sp.CLOUD_POOL])
	check(eligible > 300 and float(can_under) / eligible > 0.35, "cans are placed under clouds %.0f%% of the time they can be (chance %.2f) (%d of %d rows)" % [100.0 * can_under / maxf(eligible, 1.0), tuning.fuel_can_under_cloud_chance, can_under, eligible])
	check(can_on_safe == 0, "...and still never on the safe path")
	# (c2) coverage at the normal tuning, for the record
	tuning.cloud_frequency = cl_saved["freq"]
	var cov_report := []
	for spd in [at_start_speed, tuning.max_speed]:
		sp.scroll_speed = spd
		sp.reset()
		var any_rows := 0
		var n_rows := 0
		var lr = null
		while n_rows < 1500:
			sp.advance(step)
			var cr2 = sp._rows[-1]
			if cr2 != lr:
				lr = cr2
				n_rows += 1
				any_rows += int(cr2.cloud_cov.has(true))
		cov_report.append(100.0 * any_rows / n_rows)
	print("   (coverage at default tuning: %.0f%% of rows have a gap under cloud at start speed, %.0f%% at top speed)" % [cov_report[0], cov_report[1]])
	# (c3) drift: a bundle moves with the scroll (z) and sideways by slope per unit scrolled
	sp.reset()
	sp._spawn_cloud(-10.0)
	var dc = sp._clouds[-1]
	dc.slope = 0.1
	var x_before: float = dc.position.x
	var z_before: float = dc.position.z
	sp._advance_clouds(10.0)
	check(is_equal_approx(dc.position.z, z_before + 10.0) and is_equal_approx(dc.position.x, x_before + 1.0), "a bundle scrolls with the world and drifts sideways (slope 0.1 x 10 units = 1.0)")
	# (d) late reveal
	sp.reset()
	sp.plane_z = 3.0
	sp._spawn_cloud(-10.0)
	var cr = sp._clouds[-1]
	var reveal: float = tuning.cloud_reveal_distance
	var alphas := []
	for z in [sp.plane_z - reveal - 10.0, sp.plane_z - reveal, sp.plane_z - reveal * 0.5, sp.plane_z, sp.plane_z + 8.0]:
		cr.position.z = z - cr.oz[0]
		sp._update_cloud_alpha(cr)
		alphas.append(cr.mats[0].albedo_color.a)
	check(is_equal_approx(alphas[0], tuning.cloud_max_opacity) and is_equal_approx(alphas[1], tuning.cloud_max_opacity),
			"far from the plane a cloud is nearly opaque (%.2f)" % alphas[0])
	check(alphas[2] < alphas[1] and alphas[2] > alphas[3], "it fades as it approaches (%.2f at half the reveal distance)" % alphas[2])
	check(is_equal_approx(alphas[3], tuning.cloud_min_opacity) and is_equal_approx(alphas[4], tuning.cloud_min_opacity),
			"at the plane (and after passing it) it is at cloud_min_opacity (%.2f)" % alphas[3])
	sp.reset()
	# (e) vertical layering: above obstacles and cans, below the plane
	var puff_aabb: AABB = sp._cloud_mesh.get_aabb()
	var cloud_bottom: float = sp.CLOUD_Y + puff_aabb.position.y
	var cloud_top: float = sp.CLOUD_Y + 0.03 + puff_aabb.end.y   # (+0.03: each puff sits a hair higher or lower)
	var obstacle_top: float = tuning.column_width() * tuning.obstacle_scale * 0.5 + tuning.outline_thickness
	var can_top: float = 0.25 + 0.12 + tuning.fuel_can_size * 0.5
	var plane_bottom := INF
	for part in pl._model.get_children():
		if not part is MeshInstance3D:   # (the perk and gear marks are Node3D roots, hidden unless held)
			continue
		var pa: AABB = part.global_transform * part.mesh.get_aabb()
		plane_bottom = minf(plane_bottom, pa.position.y)
	check(cloud_bottom >= obstacle_top and cloud_bottom >= can_top - 0.001, "clouds sit above the obstacles (top %.2f) and cans (top %.2f): slab starts at %.2f" % [obstacle_top, can_top, cloud_bottom])
	check(cloud_top < plane_bottom, "...and below the plane (cloud top %.2f < plane bottom %.2f), so the plane always draws on top" % [cloud_top, plane_bottom])
	# (f) ?nofx=clouds
	DebugFlags.parse(["nofx=clouds"])
	sp.reset()
	var none := 0
	for i in 600:
		sp.advance(step)
		none += sp._clouds.size()
	DebugFlags.parse([])
	check(none == 0, "?nofx=clouds: no clouds at all")
	# (g) restart clears them and nothing new was allocated by any of that
	sp.scroll_speed = tuning.max_speed
	tuning.cloud_frequency = 1.5
	for i in 200:
		sp.advance(step)
	check(sp._clouds.size() > 0, "clouds exist before the restart")
	main.restart()
	var shown := 0
	for cl in sp._all_clouds:
		shown += int(cl.visible)
		for pf in cl.puffs:
			shown += int(pf.visible)
	check(shown == 0 and sp._clouds.is_empty(), "an in-place restart clears every cloud")
	tuning.cloud_start_time = cl_saved["start"]
	tuning.cloud_frequency = cl_saved["freq"]
	tuning.fuel_can_chance = cl_saved["chance"]
	tuning.fuel_can_under_cloud_chance = cl_saved["under"]
	tuning.fuel_risk_bias = cl_saved["bias"]
	tuning.blocked_columns_min = cl_saved["bmin"]
	tuning.blocked_columns_max = cl_saved["bmax"]
	sp.run_time = 0.0
	main.set_process(false)
	var after_clouds := snapshot(main)
	check(same_world(base, after_clouds), "generating thousands of cloud rows created nothing new  [%s]" % describe(after_clouds))

	print("2i. bonus: step table with a cap")
	var bsaved := {"cap": tuning.bonus_cap, "steps": tuning.bonus_steps.duplicate(), "tail": tuning.bonus_step_tail}
	tuning.bonus_cap = 10.0
	var expect := [1.0, 1.5, 1.9, 2.2, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 3.0, 3.1]
	var table_ok := true
	for ni in expect.size():
		table_ok = table_ok and is_equal_approx(tuning.streak_bonus(ni), expect[ni])
	check(table_ok, "bonus = 1 + steps [0.5 0.4 0.3 0.2 0.1] then 0.1 each: x1.5 x1.9 x2.2 x2.4 x2.5 x2.6 ...")
	tuning.bonus_steps = [1.0, 0.5] as Array[float]
	tuning.bonus_step_tail = 0.25
	check(is_equal_approx(tuning.streak_bonus(1), 2.0) and is_equal_approx(tuning.streak_bonus(2), 2.5) and is_equal_approx(tuning.streak_bonus(4), 3.0), "the steps and the tail are Tuning values (custom table: x2.0 x2.5 x2.75 x3.0)")
	tuning.bonus_steps = bsaved["steps"] as Array[float]
	tuning.bonus_step_tail = bsaved["tail"]
	tuning.bonus_cap = 3.0
	check(tuning.streak_bonus(1000) == 3.0 and tuning.streak_at_cap() == 10 and is_equal_approx(tuning.streak_bonus(10), 3.0), "clamped to bonus_cap (3.0), reached at close call %d" % tuning.streak_at_cap())
	main._reset_bonus()
	main.set_process(false)
	var brow = sp._rows_make_for_test(-5.0, [1.0])
	var bev := {"side": 1, "node": brow.obs[0], "outline": brow.outlines[0]}
	DebugFlags.parse(["nofx=sparks,streaks,popup,flash,trail,haptic"])
	var seen_bonus := []
	for i in 14:
		main._on_near_miss(bev)
		seen_bonus.append(main.bonus)
	var rising := true
	for i in range(1, seen_bonus.size()):
		rising = rising and seen_bonus[i] >= seen_bonus[i - 1]
	check(rising and main.bonus == 3.0 and main.streak == 10, "fourteen close calls rise and stop at the cap; the streak is held at %d" % main.streak)
	var shown_text: String = main.hud._bonus_label.text
	check(shown_text == "x3.0" and main.hud._bonus_label.get_theme_color("font_color").is_equal_approx(tuning.bonus_gold)
			and not main.hud._bonus_label.get_theme_color("font_outline_color").is_equal_approx(Color.BLACK) and shown_text.replace("x", "").is_valid_float(),
			"at the cap the label is just \"%s\", gold with a glow (no word)" % shown_text)
	# popups: number only, tiers keyed to bonus thresholds
	check(tuning.popup_text(1.9) == "x1.9" and tuning.popup_text(2.4) == "x2.4", "popups show only the number (\"x1.9\")")
	check(tuning.popup_tier(1.8) == 0 and tuning.popup_tier(2.0) == 1 and tuning.popup_tier(2.79) == 1 and tuning.popup_tier(2.8) == 2 and tuning.popup_tier(50.0) == 2,
			"popup tiers escalate at x2.0 and x2.8 (size and colour)")
	main._reset_bonus()
	main.hud.clear_bonus()
	main._on_near_miss(bev)
	main._on_near_miss(bev)
	check(main.bonus == 1.9 and main.hud._bonus_label.text == "x1.9", "two close calls: x1.9, label \"%s\"" % main.hud._bonus_label.text)
	# decay: holds, then steps come off one at a time, newest first
	main._reset_bonus()
	for i in 6:
		main._on_near_miss(bev)
	check(is_equal_approx(main.bonus, 2.6), "six close calls: x2.6")
	var hold: float = tuning.bonus_hold_time
	var t_el := 0.0
	var seq := [main.bonus]
	var times := []
	var held := true
	while main.streak > 0 and t_el < 60.0:
		var before: float = main.bonus
		main._decay_bonus(0.05)
		t_el += 0.05
		if main.bonus != before:
			seq.append(main.bonus)
			times.append(t_el)
		if t_el < hold - 0.06 and main.bonus != before:
			held = false
	var seq_ok: bool = seq.size() == 7
	var expect_seq := [2.6, 2.5, 2.4, 2.2, 1.9, 1.5, 1.0]
	for i in mini(seq.size(), expect_seq.size()):
		seq_ok = seq_ok and is_equal_approx(seq[i], expect_seq[i])
	check(seq_ok and held, "after the %.1f s hold the steps come off newest first: %s" % [hold, str(seq)])
	var gap_ok: bool = times.size() == 6 and times[0] >= hold - 0.1 and times[0] <= hold + 0.2
	for i in range(1, times.size()):
		gap_ok = gap_ok and absf((times[i] - times[i - 1]) - 1.0 / tuning.bonus_decay_rate) < 0.12
	check(gap_ok, "one step every 1/bonus_decay_rate = %.2f s (first at %.2f s)" % [1.0 / tuning.bonus_decay_rate, times[0] if times.size() > 0 else -1.0])
	check(main.bonus == 1.0 and main.streak == 0, "...down to x1")
	await real_wait(0.7)
	check(main.hud._bonus_label.text == "", "the label shrinks away at x1")
	# a crash / the end of a run resets the streak
	main._on_near_miss(bev)
	main._on_near_miss(bev)
	main._end_run(main.HEADER_CRASH, main.REASON_OBSTACLE)
	check(main.bonus == 1.0 and main.streak == 0 and main.hud._bonus_label.text == "", "a crash resets the streak and bonus")
	main.restart()
	main.set_process(false)
	# high caps: the maths and the looks stay sane (the cap will be raised by upgrades)
	tuning.bonus_cap = 1000.0
	check(tuning.streak_at_cap() == 5 + int(ceil((999.0 - 1.5) / 0.1 - 0.000001)) and is_equal_approx(tuning.streak_bonus(tuning.streak_at_cap()), 1000.0), "a cap of 1000 is reached at close call %d" % tuning.streak_at_cap())
	var okv := true
	for b in [1.0, 1.05, 2.0, 6.0, 50.0, 999.0, 1000.0]:
		var c: Color = tuning.bonus_color(b)
		okv = okv and c.r >= 0.0 and c.r <= 1.0 and c.g >= 0.0 and c.g <= 1.0 and c.b >= 0.0 and c.b <= 1.0 and tuning.bonus_swell(b) <= tuning.bonus_swell(tuning.bonus_visual_max) + 0.0001
	check(okv and tuning.at_cap(1000.0) and not tuning.at_cap(999.0), "colours and score swell are clamped visually for a cap of 1000")
	main._reset_bonus()
	for i in 40:
		main._on_near_miss(bev)
	main.hud.set_score(12345, main.bonus)
	main.hud._update_bonus_look(Time.get_ticks_msec())
	check(is_equal_approx(main.bonus, 1.0 + 1.5 + 0.1 * 35.0) and main.hud._score.scale.x <= tuning.bonus_swell(tuning.bonus_visual_max) + 0.11,
			"a long streak with a huge cap: x%.1f, score scale %.2f stays bounded" % [main.bonus, main.hud._score.scale.x])
	main.hud.set_bonus(1000.0, main.hud.BONUS_PUNCH)
	check(main.hud._bonus_label.text == "x1000.0", "the label copes with a four-digit bonus (\"%s\")" % main.hud._bonus_label.text)
	main._reset_bonus()
	main.hud.clear_bonus()
	DebugFlags.parse([])
	sp._release_row(brow)
	tuning.bonus_cap = bsaved["cap"]

	print("2k. Whisker close: doubled step")
	var wsaved := {"cap": tuning.bonus_cap, "whisker": tuning.whisker_close_distance}
	tuning.bonus_cap = 10.0
	main.restart()
	main.set_process(false)
	DebugFlags.parse([])
	var wrow = sp._rows_make_for_test(-5.0, [1.0])
	var rev := {"side": 1, "node": wrow.obs[0], "outline": wrow.outlines[0], "whisker": false}
	var wev := {"side": 1, "node": wrow.obs[0], "outline": wrow.outlines[0], "whisker": true}
	main._reset_bonus()
	main._on_near_miss(rev)
	check(is_equal_approx(main.bonus, 1.5) and main.streak == 1, "a regular first close call earns +0.5 (x1.5)")
	var reg_label: Label = main.hud._pop_labels[(main.hud._next_pop + main.hud.POPUP_POOL - 1) % main.hud.POPUP_POOL]
	check(reg_label.text == "x1.5" and reg_label.get_theme_font_size("font_size") < tuning.whisker_size, "a regular close call's popup is only the number (\"%s\")" % reg_label.text)
	main._reset_bonus()
	main._on_near_miss(wev)
	check(is_equal_approx(main.bonus, 2.0) and main.streak == 1, "a Whisker close as the first call doubles the +0.5 step: x2.0, still one step in the streak")
	var w_label: Label = main.hud._pop_labels[(main.hud._next_pop + main.hud.POPUP_POOL - 1) % main.hud.POPUP_POOL]
	check(w_label.text == "Whisker close!\nx2.0" and w_label.get_theme_font_size("font_size") == tuning.whisker_size
			and w_label.get_theme_color("font_color").is_equal_approx(tuning.whisker_color) and tuning.whisker_size > tuning.near_miss_sizes.max()
			and not tuning.whisker_color.is_equal_approx(tuning.near_miss_colors[-1]),
			"its popup says \"Whisker close!\" with the number, bigger than every other tier and in its own colour (\"%s\")" % w_label.text.replace("\n", " "))
	check(count_visible(main.fx._whisker_emitters) >= 1, "...with its own burst")
	main._reset_bonus()
	main._on_near_miss(rev)   # +0.5
	main._on_near_miss(rev)   # +0.4
	main._on_near_miss(wev)   # next step is 0.3 -> +0.6
	check(is_equal_approx(main.bonus, 1.0 + 0.5 + 0.4 + 0.6) and main.streak == 3, "regular, regular, Whisker: +0.5 +0.4 +0.6 = x2.5 after three steps (a +0.3 step became +0.6)")
	main._on_near_miss(rev)   # step 4 is 0.2
	check(is_equal_approx(main.bonus, 2.7) and main.streak == 4, "the streak carries on with the next table step (x2.7)")
	main._bonus_timer = 0.0
	main._decay_acc = 1.0
	main._decay_bonus(0.0)
	check(is_equal_approx(main.bonus, 2.5), "decay removes the newest step (x2.7 -> x2.5)")
	main._decay_acc = 1.0
	main._decay_bonus(0.0)
	check(is_equal_approx(main.bonus, 1.9) and main.streak == 2, "...then the Whisker step removes its doubled amount (x2.5 -> x1.9)")
	# the cap still applies
	tuning.bonus_cap = 3.0
	main._reset_bonus()
	for i in 6:
		main._on_near_miss(wev)
	check(is_equal_approx(main.bonus, 3.0) and main._steps.size() == 3 and is_equal_approx(main._steps_sum(), 2.0), "the cap still applies: Whisker steps +1.0 +0.8 +0.2 (clipped) stop at x3.0 (%s)" % str(main._steps))
	main._bonus_timer = 0.0
	main._decay_acc = 1.0
	main._decay_bonus(0.0)
	check(is_equal_approx(main.bonus, 2.8), "decay from the cap removes the clipped step's real amount (x3.0 -> x2.8)")
	# detection: the clearance decides
	var wcaps: PackedFloat32Array = pl.hit_capsules()
	var wp := Vector2(0.0, 0.0)
	var wtip: float = pl.collision_half_span()
	var whalf: Vector2 = sp._obstacle_half()
	var res := {}
	for off in [0.04, 0.2, 0.5]:
		sp.reset()
		var drow = sp._rows_make_for_test(-4.0, [wtip + whalf.x + off])
		var evs: Array[Dictionary] = []
		var zz := -4.0
		while zz < 6.0:
			drow.position.z = zz
			evs.append_array(sp.update_near_misses(wp, wcaps))
			zz += 0.1
		res[off] = evs
	check(res[0.04].size() == 1 and res[0.04][0]["whisker"] == true and res[0.04][0]["clearance"] <= tuning.whisker_close_distance,
			"a pass within whisker_close_distance (0.10) is a Whisker close (clearance %.3f)" % (res[0.04][0]["clearance"] if res[0.04].size() > 0 else -1.0))
	check(res[0.2].size() == 1 and res[0.2][0]["whisker"] == false and res[0.2][0]["clearance"] < tuning.near_miss_distance,
			"a pass at ~0.2 is a regular close call, not a Whisker")
	check(res[0.5].is_empty(), "a pass at ~0.5 is neither")
	tuning.whisker_close_distance = 0.0
	sp.reset()
	var zrow = sp._rows_make_for_test(-4.0, [wtip + whalf.x + 0.04])
	var zevs: Array[Dictionary] = []
	var z2 := -4.0
	while z2 < 6.0:
		zrow.position.z = z2
		zevs.append_array(sp.update_near_misses(wp, wcaps))
		z2 += 0.1
	check(zevs.size() == 1 and zevs[0]["whisker"] == false, "whisker_close_distance is a live Tuning value (0 turns Whisker closes off)")
	main.fx.clear()
	main.restart()
	main.set_process(false)
	sp._release_row(wrow)
	tuning.bonus_cap = wsaved["cap"]
	tuning.whisker_close_distance = wsaved["whisker"]

	print("2j. economy: score is coins, big numbers, upgrades, gear")
	var tsave := root.get_node("Save")
	tsave.reset_all()
	# (a) save/load round trip, versioned, tolerant of damage, v1 migration
	tsave.high_score = 777.0
	tsave.coins = 55.0
	tsave.levels["fuel_tank"] = 3
	tsave.levels["nine_lives"] = 2
	tsave.slots = 2
	tsave.loadout = ["nine_lives", "", ""]
	tsave.save_game()
	var raw = JSON.parse_string(FileAccess.get_file_as_string(tsave.path))
	check(raw is Dictionary and int(raw["version"]) == tsave.VERSION and tsave.VERSION >= 2 and int(raw["high_score"]) == 777, "the save file is JSON and carries a format version (%d)" % tsave.VERSION)
	tsave.high_score = 0.0
	tsave.coins = 0.0
	tsave.levels = {}
	tsave.slots = 1
	tsave.loadout = ["", "", ""]
	tsave.load_game()
	check(tsave.high_score == 777.0 and tsave.coins == 55.0 and tsave.level("fuel_tank") == 3 and tsave.level("nine_lives") == 2 and tsave.slots == 2 and tsave.loadout[0] == "nine_lives",
			"save/load round trip keeps high score, coins, levels, slots and loadout")
	var bad := FileAccess.open(tsave.path, FileAccess.WRITE)
	bad.store_string("{ not json")
	bad.close()
	tsave.load_game()
	check(tsave.high_score == 0.0 and tsave.coins == 0.0 and tsave.level("fuel_tank") == 0, "a corrupt save file starts fresh instead of crashing")
	var old := FileAccess.open(tsave.path, FileAccess.WRITE)
	old.store_string(JSON.stringify({"version": 1, "high_score": 42, "coins": 9, "levels": {"fuel_tank": 99, "magnet": 5, "bonus_cap": 3}, "future_field": true}))
	old.close()
	tsave.load_game()
	check(tsave.high_score == 42.0 and tsave.coins == 9.0 and tsave.level("fuel_tank") == 12 and tsave.level("bonus_cap") == 3 and tsave.level("magnet") == 2 and tsave.loadout[0] == "magnet" and tsave.slots == 1,
			"a v1 save migrates: levels clamped, the old plane Can Magnet becomes equipped gear")
	tsave.reset_all()
	# (b) big-number formatting
	var fm := [[0, "0"], [999, "999"], [1000, "1K"], [1234, "1.2K"], [45000, "45K"], [999499, "999K"], [999999, "1M"], [3100000, "3.1M"], [2400000000, "2.4B"], [1.1e12, "1.1T"], [12345678, "12M"]]
	var fm_ok := true
	var fm_bad := ""
	for pair in fm:
		if tuning.fmt(float(pair[0])) != pair[1]:
			fm_ok = false
			fm_bad = "%s -> %s" % [pair[0], tuning.fmt(float(pair[0]))]
	check(fm_ok, "big numbers: 999, 1.2K, 45K, 3.1M, 2.4B, 1.1T %s" % fm_bad)
	# (c) score IS coins: distance x bonus x multipliers; a crash keeps every coin
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)   # nothing near the plane
	main.score = 0.0
	main.elapsed = 0.0
	main.coin_mult = 1.0
	main._process(0.05)
	var spd: float = tuning.base_speed + tuning.speed_ramp * 0.05
	check(absf(main.score - spd * 0.05 * tuning.coins_per_unit * (1.0 - tuning.bonus_pay_offset)) < 0.001, "at x1 distance pays only %.1f per unit (bonus - %.1f): %.3f coins for %.3f units" % [1.0 - tuning.bonus_pay_offset, tuning.bonus_pay_offset, main.score, spd * 0.05])
	main._steps.append(0.5)
	main._refresh_bonus()
	main.coin_mult = 3.0
	var s0: float = main.score
	main._process(0.05)
	spd = tuning.base_speed + tuning.speed_ramp * 0.10
	check(absf((main.score - s0) - spd * 0.05 * (1.5 - tuning.bonus_pay_offset) * 3.0) < 0.001, "...at x1.5 it pays 0.7 per unit, times the multiplier (x3)")
	main.score = 1234.6
	main._end_run(main.HEADER_CRASH, main.REASON_OBSTACLE)
	check(tsave.coins == 1234.0 and tsave.high_score == 1234.0 and main.last_was_best and main.hud._over.text.contains("+1.2K coins") and main.hud._over.text.contains("NEW BEST!"),
			"a crash keeps every coin earned (+1.2K), shows NEW BEST!, and the score is the coins (no separate conversion)")
	main.restart()
	main.set_process(false)
	main.score = 300.0
	main._end_run(main.HEADER_FUEL, main.REASON_FUEL)
	check(not main.last_was_best and tsave.coins == 1534.0 and main.hud._over.text.contains("Best: 1.2K") and not main.hud._over.text.contains("NEW BEST"), "a lower run is not a new best (shows Best: 1.2K); coins add up")
	check(not tuning.get("coins_per_score") and not tuning.get("coins_per_can"), "the old coin conversion is gone")
	# (d) the upgrade table: three tabs, costs, doubling, caps
	check(tuning.upgrades_in_tab("earnings").size() == 4 and tuning.upgrades_in_tab("plane").size() == 3 and tuning.upgrades_in_tab("gear").size() == 6, "EARNINGS (4), PLANE (3) and GEAR (6) upgrades")
	var cost_ok := true
	for u in tuning.upgrades_in_tab("earnings"):
		cost_ok = cost_ok and tuning.max_level(u["id"]) == -1 and absf(tuning.upgrade_cost(u["id"], 10) / tuning.upgrade_cost(u["id"], 9) - 1.12) < 0.01
	for u in tuning.upgrades_in_tab("plane"):
		cost_ok = cost_ok and tuning.max_level(u["id"]) >= 10 and tuning.max_level(u["id"]) <= 15 and absf(tuning.upgrade_cost(u["id"], 5) / tuning.upgrade_cost(u["id"], 4) - 1.5) < 0.01
	for u in tuning.upgrades_in_tab("gear"):
		var cs: Array = u["costs"]
		cost_ok = cost_ok and cs.size() == tuning.max_level(u["id"]) and tuning.max_level(u["id"]) <= 3
		for i in range(1, cs.size()):
			cost_ok = cost_ok and cs[i] / cs[i - 1] >= 20.0 and cs[i] / cs[i - 1] <= 50.0
	check(cost_ok, "EARNINGS endless at x1.12 per level; PLANE 10-15 levels at x1.5; GEAR 1-3 levels, each 20-50x the last")
	check(is_equal_approx(tuning.upgrade_value("coin_value", 1), 1.3) and is_equal_approx(tuning.upgrade_value("coin_value", 2), 1.54) and is_equal_approx(tuning.upgrade_value("coin_value", 24), 1.0 + 0.1 * 29.05)
			and is_equal_approx(tuning.upgrade_value("coin_value", 25), 1.0 + 0.1 * 30.05 * 2.0) and is_equal_approx(tuning.upgrade_value("coin_value", 50), 1.0 + 0.1 * 55.05 * 4.0),
			"Coin Value: the first levels are big (+30%%, +24%% ...), then +10%% each; the effect doubles at level 25 and again at 50 (x%.1f at 24, x%.1f at 25)" % [tuning.upgrade_value("coin_value", 24), tuning.upgrade_value("coin_value", 25)])
	check(is_equal_approx(tuning.upgrade_value("bonus_cap", 1), tuning.bonus_cap + 1.0) and is_equal_approx(tuning.upgrade_value("bonus_cap", 2), tuning.bonus_cap + 1.8) and is_equal_approx(tuning.upgrade_value("bonus_cap", 25), tuning.bonus_cap + 27.0), "Bonus Cap: +1.0, +0.8 ... then +0.5 per level, endless, doubling too")
	var dim_ok := true
	for id in ["fuel_tank", "efficiency", "refill"]:
		var g1: float = absf(tuning.upgrade_value(id, 2) - tuning.upgrade_value(id, 1))
		var g9: float = absf(tuning.upgrade_value(id, 10) - tuning.upgrade_value(id, 9))
		dim_ok = dim_ok and g9 < g1
	check(dim_ok, "PLANE gains diminish with level")
	check(tuning.upgrade_line("fuel_tank", 0).begins_with("Hold 30 more fuel (100 -> 130)") and tuning.upgrade_line("fuel_tank", 0).contains("You'll notice: +"), "plain-language line with a before -> after and a \"you'll notice\": \"%s\"" % tuning.upgrade_line("fuel_tank", 0).replace("\n", " | "))
	var first_gain_ok := true
	for id in ["fuel_tank", "efficiency", "refill"]:
		first_gain_ok = first_gain_ok and absf(tuning.upgrade_value(id, 1) - tuning.upgrade_value(id, 0)) > 1.8 * absf(tuning.upgrade_value(id, 8) - tuning.upgrade_value(id, 7))
	check(first_gain_ok, "the first level of each PLANE upgrade is at least 1.8x the level 8 gain (big early, small later)")
	var notice_ok := true
	for u in tuning.upgrades:
		notice_ok = notice_ok and tuning.upgrade_notice(u["id"], 0).begins_with("You'll notice:")
	check(notice_ok, "every upgrade has a \"You'll notice\" line")
	# (e) the Hangar: tabs, rows, buying
	main.hud.hangar_pressed.emit()
	check(main.screen == main.SCREEN_HANGAR and main.hud._hangar.visible, "the Hangar opens")
	var tab_ok := true
	for t in ["earnings", "plane", "gear"]:
		main.hud._select_tab(t)
		var vis := 0
		for row in main.hud._upg_rows:
			if (row["title"] as Label).visible:
				vis += 1
				tab_ok = tab_ok and row["tab"] == t and (row["line"] as Label).text.contains("->") or (row["line"] as Label).text.contains("MAX")
		tab_ok = tab_ok and vis == tuning.upgrades_in_tab(t).size()
	check(tab_ok, "three tabs, each showing only its own upgrades, each with a current -> next line")
	tsave.reset_all()
	tsave.add_coins(50.0)
	main.hud._select_tab("earnings")
	var cv_row: Dictionary = main.hud._upg_rows[0]
	check((cv_row["buy"] as Button).disabled and (cv_row["buy"] as Button).text == "280", "Coin Value costs 280 and is greyed out with 50 coins")
	tsave.add_coins(1000000.0)
	check(main.hud._hangar_coins.text == "Coins: 1M" and not (cv_row["buy"] as Button).disabled, "balance shows with suffixes (Coins: 1M)")
	(cv_row["buy"] as Button).pressed.emit()
	check(tsave.level("coin_value") == 1 and is_equal_approx(tuning.coin_value_mult(), 1.3) and tsave.coins == 1000050.0 - 280.0 and (cv_row["title"] as Label).text.contains("Lv 1"), "buying Coin Value: level 1, coins x1.3, cost deducted")
	for id in ["can_bounty", "close_call_pay", "bonus_cap", "fuel_tank", "efficiency", "refill"]:
		tsave.buy(id)
	check(is_equal_approx(tuning.can_bounty_pay(), 24.0) and is_equal_approx(tuning.close_call_pay(), 12.0) and is_equal_approx(tuning.bonus_cap_now(), 4.0)
			and is_equal_approx(tuning.fuel_max(), 130.0) and is_equal_approx(tuning.drain_rate(), 6.5 * 0.91) and is_equal_approx(tuning.refill_amount(), 27.0), "each upgrade applies its effect at level 1")
	tsave.levels["fuel_tank"] = 11
	tsave.add_coins(1e9)
	check(tsave.buy("fuel_tank") and tsave.is_maxed("fuel_tank") and not tsave.buy("fuel_tank") and (main.hud._upg_rows[4]["buy"] as Button).text == "MAX", "a PLANE upgrade stops at its last level and shows MAX")
	tsave.levels["coin_value"] = 300
	check(not tsave.is_maxed("coin_value") and tsave.can_buy("coin_value") == (tsave.coins >= tsave.cost_of_next("coin_value")), "an EARNINGS upgrade never maxes out (level 300 is still buyable in principle)")
	tsave.levels["coin_value"] = 1
	# (f) gear: slots, loadout, effects
	tsave.reset_all()
	tsave.add_coins(1e9)
	tsave.buy("nine_lives")
	check(tsave.is_equipped("nine_lives") and tsave.loadout[0] == "nine_lives" and tsave.gear_level("nine_lives") == 1, "the first gear bought goes into the free slot")
	tsave.buy("magnet")
	check(not tsave.is_equipped("magnet") and tsave.gear_level("magnet") == 0 and tuning.pickup_reach() == 0.0, "with one slot a second piece of gear is owned but not equipped (no effect)")
	main.hud._select_tab("gear")
	main.hud._sel_slot = 0
	tsave.equip("magnet", 0)
	check(tsave.loadout[0] == "magnet" and tsave.gear_level("nine_lives") == 0 and tuning.pickup_reach() == 1.5, "owned gear swaps freely (Can Magnet level 1: 1.5 units)")
	check(tsave.slots == 1 and not tsave.equip("nine_lives", 1), "slot 2 is locked at the start")
	var slot_cost: float = tsave.next_slot_cost()
	check(slot_cost == tuning.gear_slot_costs[1] and tsave.buy_slot() and tsave.slots == 2 and tsave.equip("nine_lives", 1) and tsave.loadout == ["magnet", "nine_lives", ""], "the 2nd slot is a purchase; then both are equipped")
	tsave.equip("nine_lives", 0)
	check(tsave.loadout == ["nine_lives", "magnet", ""], "equipping into an occupied slot swaps places")
	main.hud.hide_menus()
	# Nine Lives
	main.restart()
	main.set_process(false)
	check(main.lives == 1 and main.hud._lives_pips[0].visible and not main.hud._lives_pips[1].visible, "Nine Lives: the run starts with 1 life (shown as a pip)")
	sp.reset(-500.0)
	var lrow = sp._rows_make_for_test(main.player.position.z, [main.player.position.x])
	main._process(0.02)
	check(main.alive and main.lives == 0 and main._invuln > 0.0 and lrow.passed, "a hit with a life left: the plane sputters on (no crash), the obstacle gives no close-call credit")
	main._process(0.02)
	check(main.alive, "...and is invulnerable for a moment")
	main._invuln = 0.0
	main._process(0.02)
	check(not main.alive, "the next hit with no life left crashes")
	# Reserve Tank
	tsave.levels["reserve_tank"] = 2
	tsave.loadout = ["reserve_tank", "", ""]
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	main.fuel = 0.01
	main._process(0.05)
	check(main.alive and main.reserve_left == 1 and main.fuel > tuning.fuel_max() * 0.5, "Reserve Tank: the empty tank refills itself (%.0f)" % main.fuel)
	main.fuel = 0.01
	main._process(0.05)
	main.fuel = 0.01
	main._process(0.05)
	check(not main.alive and main.reserve_left == 0, "...twice at level 2, then the run ends on fuel")
	# Can Magnet pulls a can the plane could not reach
	tsave.levels["magnet"] = 3
	tsave.loadout = ["magnet", "", ""]
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	var mrow2 = sp._rows_make_for_test(main.player.position.z - 2.0, [])
	sp._place_can_for_test(mrow2, main.player.position.x + 3.3)
	for i in 14:
		main._process(0.03)
	check(main.run_cans == 1, "Can Magnet (3.5 units) pulled in a can 3.3 units to the side (cans %d)" % main.run_cans)
	tsave.loadout = ["", "", ""]
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	var mrow3 = sp._rows_make_for_test(main.player.position.z - 2.0, [])
	sp._place_can_for_test(mrow3, main.player.position.x + 3.3)
	for i in 14:
		main._process(0.03)
	check(main.run_cans == 0, "...but not without the gear equipped")
	# Cloud Eye: a frame over an obstacle under a cloud
	tsave.levels["cloud_eye"] = 1
	tsave.loadout = ["cloud_eye", "", ""]
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	var erow = sp._rows_make_for_test(-5.0, [0.0])
	sp.run_time = 100.0
	sp._spawn_cloud(-5.0)
	var ecl = sp._clouds[-1]
	ecl.position = Vector3(0.0, 0.0, -5.0)
	ecl.ox[0] = 0.0
	ecl.oz[0] = 0.0
	ecl.rad[0] = 2.0
	ecl.on[0] = true
	sp._update_cloud_eye()
	check(erow.obs_ghosts[0].visible, "Cloud Eye: an obstacle under a cloud gets a faint outline frame")
	ecl.position.x = 9.0
	sp._update_cloud_eye()
	check(not erow.obs_ghosts[0].visible, "...and not once the cloud has moved off it")
	ecl.position.x = 0.0
	tsave.loadout = ["", "", ""]
	sp._update_cloud_eye()
	check(not erow.obs_ghosts[0].visible, "...nor when the gear is not equipped")
	# Steady Nerves + Head Start
	tsave.levels["steady_nerves"] = 1
	tsave.levels["head_start"] = 2
	tsave.slots = 3
	tsave.loadout = ["steady_nerves", "head_start", ""]
	main.restart()
	main.set_process(false)
	check(is_equal_approx(main.bonus, 2.0) and main.hud._bonus_label.text == "x2.0", "Head Start level 2: the run begins at x2.0")
	main._reset_bonus()
	for i in 4:
		main._steps.append(0.2)
	main._refresh_bonus()
	main._absorb_hit(Vector2.ZERO, main.player.hit_capsules())
	check(main.streak == 2, "Steady Nerves level 1: a hit keeps half of the close-call streak (4 -> %d)" % main.streak)
	tsave.levels["steady_nerves"] = 2
	main.lives = 2
	main._absorb_hit(Vector2.ZERO, main.player.hit_capsules())
	check(main.streak == 2, "...level 2 keeps all of it")
	# Close Call Pay and Can Bounty pay coins (times the multiplier)
	tsave.loadout = ["", "", ""]
	tsave.levels["close_call_pay"] = 2
	tsave.levels["can_bounty"] = 1
	main.restart()
	main.set_process(false)
	main.coin_mult = 2.0
	main.score = 0.0
	var prow = sp._rows_make_for_test(-5.0, [1.0])
	DebugFlags.parse([])
	main._on_near_miss({"side": 1, "node": prow.obs[0], "outline": prow.outlines[0], "whisker": false})
	check(is_equal_approx(main.score, 4.0 * 5.4 * 2.0), "Close Call Pay level 2 pays 21.6 coins x the multiplier (%.0f)" % main.score)
	var coin_pop_text := ""
	for cl_ in main.hud._coin_pops:
		if cl_.visible:
			coin_pop_text = cl_.text
	check(coin_pop_text == "+43", "...with a coin pop (\"%s\")" % coin_pop_text)
	main.score = 0.0
	main._on_pickup(Vector3(0, 0.4, -3))
	check(is_equal_approx(main.score, 24.0 * 2.0), "Can Bounty level 1 pays 24 coins x the multiplier per can")
	sp._release_row(prow)
	# (g) ?tune debug buttons
	var add_btn: Button = null
	var reset_btn: Button = null
	for bt in main.tune_panel.find_children("*", "Button", true, false):
		if bt.get_meta("debug", "") == "add_coins":
			add_btn = bt
		elif bt.get_meta("debug", "") == "reset_save":
			reset_btn = bt
	check(add_btn != null and reset_btn != null, "?tune has \"Add 1M coins\" and \"Reset save\" buttons")
	tsave.coins = 0.0
	add_btn.pressed.emit()
	check(tsave.coins == 1000000.0, "Add 1M coins adds 1,000,000")
	reset_btn.pressed.emit()
	check(tsave.coins == 0.0 and tsave.level("nine_lives") == 0 and tsave.slots == 1 and tuning.fuel_max() == 100.0, "Reset save wipes coins, levels and slots")
	# (h) none of this created anything
	main.hud.play_pressed.emit()
	main.set_process(false)
	main.fx.clear()
	var snap_prog := snapshot(main)
	check(same_world(base, snap_prog), "buying, saving, the Hangar and gear created nothing new  [%s]" % describe(snap_prog))

	print("2l. maps: unlocks, medals, palettes, gulls, wind gusts, lightning")
	tsave.reset_all()
	# (a) the map table
	var mm: Array = tuning.maps
	check(mm.size() == 4 and mm[0]["name"] == "Countryside" and mm[1]["name"] == "Coast" and mm[2]["name"] == "Mountains" and mm[3]["name"] == "Stormfront", "four maps: Countryside, Coast, Mountains, Stormfront")
	check(tuning.map_coin_mult[0] == 1.0 and tuning.map_coin_mult[1] == 2.0 and tuning.map_coin_mult[2] == 4.0 and tuning.map_coin_mult[3] == 8.0, "coin multipliers x1, x2, x4, x8")
	check(mm[1]["unlock_from"] == 0 and mm[1]["unlock_meters"] == 3000.0 and mm[2]["unlock_from"] == 1 and mm[2]["unlock_meters"] == 4000.0 and mm[3]["unlock_from"] == 2 and mm[3]["unlock_meters"] == 5000.0,
			"unlocks: 3,000 m in Countryside, 4,000 m in Coast, 5,000 m in Mountains")
	check(mm[1]["gull_share"] > 0.0 and mm[0]["gull_share"] == 0.0 and mm[2]["gust_chance"] > 0.0 and mm[1]["gust_chance"] == 0.0 and mm[3]["lightning_interval"] > 0.0 and mm[2]["lightning_interval"] == 0.0,
			"each map brings its own hazard: gulls (Coast), gusts (Mountains), lightning (Stormfront)")
	var pal_ok := true
	for i in 4:
		for j in range(i + 1, 4):
			pal_ok = pal_ok and not mm[i]["sky"].is_equal_approx(mm[j]["sky"]) and not mm[i]["obstacle"].is_equal_approx(mm[j]["obstacle"])
		pal_ok = pal_ok and mm[i]["medals"].size() == 3 and mm[i]["medals"][0][0] < mm[i]["medals"][1][0] and mm[i]["medals"][1][0] < mm[i]["medals"][2][0] and mm[i]["medals"][0][1] < mm[i]["medals"][2][1]
	check(pal_ok, "every map has its own palette and three medal goals with rising rewards")
	check(tuning.meters(100.0) == 100.0 * tuning.meters_per_unit and tuning.fmt_m(3120.0) == "3,120 m" and tuning.fmt_m(999.0) == "999 m" and tuning.fmt_m(1234567.0) == "1,234,567 m", "meters are a Tuning conversion of world units (%.1f m per unit); 3,120 m formatting" % tuning.meters_per_unit)
	check(is_equal_approx(tuning.map_speed(1, 0.0), tuning.base_speed * 1.1) and tuning.map_speed(3, 1000.0) <= tuning.max_speed * 1.3 + 0.001 and tuning.map_speed(3, 0.0) > tuning.map_speed(0, 0.0), "harder maps start faster")
	# (b) saves: per-map bests, medals (paid once), unlocks, migration from v2
	var r1: Dictionary = tsave.record_map_run(0, 1600.0, 500.0)
	check(r1["medals"] == [0] and r1["reward"] == mm[0]["medals"][0][1] and r1["unlocked"].is_empty() and r1["new_best_distance"], "1,600 m on Countryside: bronze medal and its coins, no unlock yet")
	var coins_before: float = tsave.coins
	var r2: Dictionary = tsave.record_map_run(0, 1600.0, 400.0)
	check(r2["medals"].is_empty() and tsave.coins == coins_before and not r2["new_best_distance"], "the same medal is not paid twice")
	var r3: Dictionary = tsave.record_map_run(0, 3100.0, 900.0)
	check(r3["medals"] == [1] and r3["unlocked"] == [1] and tsave.map_unlocked(1) and not tsave.map_unlocked(2), "3,100 m: silver medal and Coast unlocks")
	check(tsave.map_stat(0)["best_distance"] == 3100.0 and tsave.map_stat(0)["best_score"] == 900.0 and tsave.map_stat(1)["best_distance"] == 0.0, "bests are kept per map")
	check(not tsave.select_map(2) and tsave.select_map(1) and tsave.selected_map == 1, "a locked map can't be selected; Coast can")
	var r4: Dictionary = tsave.record_map_run(1, 3999.0, 5000.0)
	check(r4["unlocked"].is_empty() and not tsave.map_unlocked(2), "3,999 m on Coast does not unlock Mountains")
	var r5: Dictionary = tsave.record_map_run(1, 4000.0, 5000.0)
	check(r5["unlocked"] == [2], "4,000 m on Coast unlocks Mountains")
	tsave.save_game()
	tsave.load_game()
	check(tsave.map_unlocked(2) and tsave.selected_map == 1 and tsave.map_stat(0)["medals"] == 2, "map progress survives save and load")
	var v2 := FileAccess.open(tsave.path, FileAccess.WRITE)
	v2.store_string(JSON.stringify({"version": 2, "high_score": 8000, "coins": 70, "levels": {}, "slots": 1, "loadout": ["", "", ""]}))
	v2.close()
	tsave.load_game()
	check(tsave.map_stat(0)["best_score"] == 8000.0 and tsave.map_unlocked(0) and not tsave.map_unlocked(1) and tsave.coins == 70.0, "a v2 save migrates: the old high score becomes the Countryside best")
	tsave.reset_all()
	# (c) the start screen: map cards, locks, selection, PLAY uses the selected map
	main.hud.show_menu()
	var cards: Array = main.hud._map_cards
	check(cards.size() == 4 and not (cards[0] as Button).disabled and (cards[1] as Button).disabled and (cards[1] as Button).text.contains("Reach 3,000 m on Countryside") and (cards[0] as Button).text.contains("x1 coins"),
			"start screen: four map cards, the locked ones say how to unlock (\"%s\")" % (cards[1] as Button).text.replace("\n", " / "))
	tsave.record_map_run(0, 3000.0, 100.0)
	check(not (cards[1] as Button).disabled and (cards[1] as Button).text.contains("x2 coins") and (cards[2] as Button).disabled and main.hud._map_dots[0][1].get_theme_stylebox("panel").bg_color.is_equal_approx(Color(0.82, 0.86, 0.92)),
			"Coast opens (x2 coins) and the Countryside silver medal dot lights up")
	(cards[1] as Button).pressed.emit()
	check(tsave.selected_map == 1, "tapping a card selects that map")
	main.hud.play_pressed.emit()
	main.set_process(false)
	check(main.map == 1 and main.coin_mult == 2.0 * tuning.coin_value_mult() and sp.map == 1 and sp._obs_color.is_equal_approx(mm[1]["obstacle"]) and main._base_sky.is_equal_approx(mm[1]["sky"]) and main._env.background_color.is_equal_approx(main._base_sky.lerp(tuning.tod_tint[0], tuning.tod_mix[0])),
			"PLAY starts on the selected map: x2 coins, the Coast palette, the Coast sky (at morning)")
	check(sp._ground_mat.albedo_color.is_equal_approx(mm[1]["ground"]) and sp._cloud_color.is_equal_approx(mm[1]["cloud"]), "...ground and clouds recoloured too")
	# (d) distance on the HUD and the result screen
	sp.reset(-500.0)
	main.run_distance = 0.0
	main._process(0.05)
	check(main.hud._distance_label.text.ends_with(" m") and main.run_distance > 0.0, "the HUD shows the distance in meters (\"%s\")" % main.hud._distance_label.text)
	tsave.reset_all()
	tsave.unlock_all_maps()
	tsave.select_map(0)
	main.restart()
	main.set_process(false)
	main.run_distance = 3300.0 / tuning.meters_per_unit
	main.score = 777.0
	main._end_run(main.HEADER_CRASH, main.REASON_OBSTACLE)
	var over_txt: String = main.hud._over.text
	check(over_txt.contains("3,300 m  NEW BEST!") and over_txt.contains("Bronze medal!") and over_txt.contains("Silver medal!") and not over_txt.contains("Gold medal"), "the game-over screen shows the distance and the medals earned")
	check(tsave.map_stat(0)["best_distance"] == 3300.0 and tsave.map_stat(0)["best_score"] == 777.0, "...and per-map bests update")
	main.hud.hide_menus()
	# (e) GULLS (Coast): drifting obstacles that never close the safe path
	tsave.reset_all()
	tsave.unlock_all_maps()
	sp.apply_map(1)
	sp.run_time = 0.0
	sp.reset(-500.0)
	var n_obs := 0
	var n_gulls := 0
	var gull_ok := true
	var gull_mat_ok := true
	var hw: float = tuning.column_width() * tuning.obstacle_scale * 0.5 + tuning.outline_thickness
	for i in 1500:
		sp._spawn_row(-30.0)
		var gr = sp._rows[-1]
		n_obs += gr.obs.size()
		n_gulls += gr.gull_k.size()
		var keep_x: float = tuning.column_center(gr.safe_col)
		for gi in gr.gull_k.size():
			var k: int = gr.gull_k[gi]
			gull_mat_ok = gull_mat_ok and gr.obs[k].material_override == sp._gull_mat
			var x0: float = gr.xs[k]
			var need: float = hw + 1.1 + 0.15
			var worst: float = minf(absf(keep_x - gr.gull_lo[gi]), absf(keep_x - gr.gull_hi[gi]))
			gull_ok = gull_ok and worst >= minf(absf(keep_x - x0), need) - 0.0001
		sp._release_row(gr)
	check(n_gulls > 0 and absf(float(n_gulls) / n_obs - 0.5) < 0.08 and gull_mat_ok, "Coast: about half the obstacles are gulls (%.0f%%), drawn in their own white material" % (100.0 * n_gulls / maxf(n_obs, 1.0)))
	check(gull_ok, "FAIRNESS: over 1500 rows no gull's drift range ever intrudes on the safe-path column")
	sp.reset(-500.0)
	var grow = null
	while grow == null or grow.gull_k.is_empty() or grow.gull_hi[0] - grow.gull_lo[0] < 0.5:
		if grow != null:
			sp._release_row(grow)
		sp._spawn_row(-30.0)
		grow = sp._rows[-1]
	var gk: int = grow.gull_k[0]
	var gx0: float = grow.xs[gk]
	grow.gull_v[0] = absf(tuning.gull_speed) if grow.gull_hi[0] > gx0 + 0.01 else -absf(tuning.gull_speed)
	sp.update_hazards(0.2)
	check(absf(grow.xs[gk] - gx0) > 0.1 and absf(grow.xs[gk] - gx0) < 0.4 and is_equal_approx(grow.obs[gk].position.x, grow.xs[gk]), "a gull drifts sideways slowly (%.2f units in 0.2 s) and its block moves with it" % (grow.xs[gk] - gx0))
	for i in 600:
		sp.update_hazards(0.05)
	check(grow.xs[gk] >= grow.gull_lo[0] - 0.001 and grow.xs[gk] <= grow.gull_hi[0] + 0.001, "...and turns around at the end of its range")
	sp._release_row(grow)
	# (f) WIND GUSTS (Mountains)
	sp.apply_map(2)
	sp.run_time = 0.0
	sp.plane_z = 4.0
	sp.reset(-40.0)
	var hz = sp.hazards
	var gust_seen := 0
	var gust_clear_ok := true
	var gust_max := 0
	for i in 900:
		sp.advance(1.5)
		gust_max = maxi(gust_max, hz.gusts_in_play().size())
		for g in hz.gusts_in_play():
			gust_seen += 1
			for r in sp._rows:
				gust_clear_ok = gust_clear_ok and absf(r.position.z - g.position.z) - g.length * 0.5 >= tuning.gust_clear - 0.001
	check(gust_seen > 100 and gust_max <= hz.GUST_POOL, "Mountains: gusts appear between rows (pool of %d, never more)" % hz.GUST_POOL)
	check(gust_clear_ok, "FAIRNESS: a gust is never closer than %.0f units to any row of obstacles" % tuning.gust_clear)
	hz.configure(1.0, 0.0)
	hz.on_row_spawned(-30.0)
	check(hz.gusts_in_play().size() == 1, "a gust spawns")
	var gu = hz.gusts_in_play()[0]
	gu.position.z = -30.0
	sp.plane_z = 4.0
	hz.update(0.01)
	var far_alpha: float = gu.mat.albedo_color.a
	gu.position.z = 2.0
	hz.update(0.01)
	check(not hz.is_lit(hz.gusts_in_play()[0]) == false and gu.mat.albedo_color.a > far_alpha + 0.2, "a gust is faint from far away (%.2f) and lights up when close (%.2f): telegraphed" % [far_alpha, gu.mat.albedo_color.a])
	gu.x0 = -4.0
	gu.x1 = 4.0
	gu.dir = 1.0
	check(is_equal_approx(hz.push_at(0.0, 2.0), tuning.gust_push) and hz.push_at(0.0, 30.0) == 0.0 and hz.push_at(9.0, 2.0) == 0.0, "the gust pushes sideways only inside its zone (%.1f units/s)" % tuning.gust_push)
	tsave.select_map(2)
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	sp.hazards.configure(1.0, 0.0)
	sp.hazards.on_row_spawned(-30.0)
	var gu2 = sp.hazards.gusts_in_play()[0]
	gu2.x0 = -5.0
	gu2.x1 = 5.0
	gu2.dir = -1.0
	var px0: float = main.player.position.x
	gu2.position.z = main.player.position.z
	main._process(0.05)
	check(is_equal_approx(main.player.position.x, px0 - tuning.gust_push * 0.05), "in a run the wind moves the plane sideways (%.3f -> %.3f)" % [px0, main.player.position.x])
	sp.hazards.reset()
	# (g) LIGHTNING (Stormfront)
	tsave.select_map(3)
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	sp.run_time = 30.0
	sp.plane_z = main.player.position.z
	sp.plane_x = 0.0
	sp.scroll_speed = 10.0
	hz = sp.hazards
	check(hz.lightning_interval > 0.0, "Stormfront has lightning")
	var struck := {"n": 0}
	hz.lightning_struck.connect(func(): struck["n"] += 1)
	hz._next_strike = 0.0
	hz.update(0.01)
	var bolt = null
	for b in hz.bolts_in_play():
		if b.state == 1:
			bolt = b
	check(bolt != null and bolt.visible, "a strike starts as a visible warning on one column")
	var bcol: int = bolt.col
	var bx: float = tuning.column_center(bcol)
	var elapsed_w := 0.0
	var struck_early := false
	while bolt.state == 1 and elapsed_w < 3.0:
		struck_early = struck_early or hz.hit(bx)
		hz.update(0.05)
		elapsed_w += 0.05
	check(not struck_early and absf(elapsed_w - tuning.lightning_warn) < 0.12 and bolt.state == 2 and struck["n"] == 1, "...about %.1f s later it strikes (warned %.2f s, nothing hurt before that)" % [tuning.lightning_warn, elapsed_w])
	check(hz.hit(bx) and hz.hit(bx + 0.5) and not hz.hit(bx + tuning.column_width() * 1.0 + 0.9), "the strike hurts the plane in that column only")
	var strike_t := 0.0
	while bolt.state == 2 and strike_t < 2.0:
		hz.update(0.05)
		strike_t += 0.05
	check(absf(strike_t - tuning.lightning_strike) < 0.12 and not hz.hit(bx), "the strike lasts %.1f s, then the bolt fades" % tuning.lightning_strike)
	for i in 20:
		hz.update(0.05)
	check(bolt.state == 0 and not bolt.visible, "...and goes back to the pool")
	# lightning fairness: random rows near the plane, picks never break the rule
	var lf_ok := true
	var lf_picks := 0
	var lf_none := 0
	for trial in 600:
		sp.reset(-500.0)
		hz.reset()
		for k in randi_range(1, 3):
			var lr = sp._rows_make_for_test(main.player.position.z - randf_range(-2.0, 18.0), [])
			var cnt := 0
			for c in tuning.column_count:
				var is_open := randf() < 0.5
				lr.open.append(is_open)
				cnt += int(is_open)
			if cnt == 0:
				lr.open[randi() % tuning.column_count] = true
			var opens: Array[int] = []
			for c in tuning.column_count:
				if lr.open[c]:
					opens.append(c)
			lr.safe_col = opens.pick_random()
		var pick: int = hz._pick_column()
		if pick < 0:
			lf_none += 1
			continue
		lf_picks += 1
		for lr2 in hz._rows_in_window():
			var other := false
			for c in tuning.column_count:
				if lr2.open[c] and c != pick:
					other = true
			lf_ok = lf_ok and lr2.safe_col != pick and other
	check(lf_ok and lf_picks > 100, "FAIRNESS: in %d random situations lightning never picked the safe path or the last open column of a passing row (%d picks, %d held back)" % [lf_picks + lf_none, lf_picks, lf_none])
	# a row arrives whose only way is the warned column: the strike fizzles
	sp.reset(-500.0)
	hz.reset()
	hz._begin(hz.bolts_in_play()[0], 2)
	var trap = sp._rows_make_for_test(main.player.position.z - 4.0, [])
	for c in tuning.column_count:
		trap.open.append(c == 2)
	trap.safe_col = 2
	struck["n"] = 0
	for i in 40:
		hz.update(0.05)
	check(struck["n"] == 0 and not hz.hit(tuning.column_center(2)), "if a row arrives whose only way is the warned column, the strike is cancelled")
	sp.reset(-500.0)
	hz.reset()
	# lightning damages the plane in a run: crash, or a life
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	main.lives = 0
	var pb = hz.bolts_in_play()[0]
	hz._begin(pb, roundi(main.player.position.x / tuning.column_width() + (tuning.column_count - 1) * 0.5))
	pb.state = 2
	main._process(0.02)
	check(not main.alive and main.hud._over.text.begins_with(main.HEADER_STRUCK), "standing in a strike ends the run (STRUCK)")
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	main.lives = 1
	pb = hz.bolts_in_play()[0]
	hz._begin(pb, roundi(main.player.position.x / tuning.column_width() + (tuning.column_count - 1) * 0.5))
	pb.state = 2
	main._process(0.02)
	check(main.alive and main.lives == 0 and main._invuln > 0.0, "...unless a life absorbs it")
	hz.reset()
	# (h) the ?tune debug button, pre-warm drew the hazard pools, nothing new allocated
	var um: Button = null
	for bt in main.tune_panel.find_children("*", "Button", true, false):
		if bt.get_meta("debug", "") == "unlock_maps":
			um = bt
	tsave.reset_all()
	um.pressed.emit()
	check(tsave.map_unlocked(1) and tsave.map_unlocked(2) and tsave.map_unlocked(3), "?tune: Unlock all maps")
	tsave.reset_all()
	tsave.select_map(0)
	main.hud.play_pressed.emit()
	main.set_process(false)
	main.fx.clear()
	sp.apply_map(0)
	var snap_maps := snapshot(main)
	snap_maps["mats"].erase(sp._gull_mat.get_instance_id())   # (pre-built at start-up; it only shows up in the walk while a gull is on screen)
	check(same_world(base, snap_maps), "maps, gulls, gusts and lightning created nothing new  [%s]" % describe(snap_maps))

	print("2m. in-run picks: perks, boosts, supplies, the paused pick screen")
	tsave.reset_all()
	tsave.select_map(0)
	var pk = main.picks
	pk.enabled = true
	# (a) prices: pick_first x permanent multiplier, +20% each
	pk.start_run(1.0)
	check(is_equal_approx(pk.next_pick, 40.0), "the first pick (inside its time window) needs a score of 40 x the multiplier")
	var pr1: float = tuning.pick_price(1, 10.0, 1.0)
	var pr_fast: float = tuning.pick_price(1, 40.0, 1.0)
	var pr_slow: float = tuning.pick_price(1, 2.0, 1.0)
	check(is_equal_approx(pr1, 10.0 * tuning.pick_gap_seconds) and pr_fast / 40.0 < pr_slow / 2.0 and tuning.pick_price(3, 10.0, 1.0) > tuning.pick_price(2, 10.0, 1.0),
			"later picks cost about %.0f s of what you earn (%.0f at 10 coins/s); a slower earner waits longer (%.0f s vs %.0f s); each pick costs a bit more (x%.2f)" % [tuning.pick_gap_seconds, pr1, pr_slow / 2.0, pr_fast / 40.0, tuning.pick_growth])
	pk.advance(100.0, 20.0)
	check(pk.next_pick > 100.0 and is_equal_approx(pk.next_pick, 100.0 + tuning.pick_price(1, 5.0, 1.0)), "...priced from your earning rate this run (100 coins in 20 s): the next pick at %.0f" % pk.next_pick)
	pk.start_run(2.2)
	check(is_equal_approx(pk.next_pick, 88.0), "with a x2.2 permanent multiplier the first pick is at 88")
	tsave.levels["coin_value"] = 5
	tsave.select_map(0)
	main.restart()
	main.set_process(false)
	check(is_equal_approx(main.coin_mult, 2.005) and is_equal_approx(pk.next_pick, 80.2) and main.hud._next_label.text == "Next: 80", "in a run: multiplier = map x Coin Value (x2.0) -> first pick at 80, shown as \"%s\"" % main.hud._next_label.text)
	tsave.levels["coin_value"] = 0
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	check(main.hud._next_label.text == "Next: 40", "the HUD shows \"Next: 40\" under the score")
	# (b) reaching it pauses the game completely and deals three cards
	# the first pick lives in a time window
	check(tuning.first_pick_min_seconds == 15.0 and tuning.first_pick_max_seconds == 20.0, "first_pick_min_seconds 15 and first_pick_max_seconds 20 are Tuning values")
	main.elapsed = 3.0
	main.score = 1000000.0
	main._process(0.02)
	check(not main.get_tree().paused and not main._picking, "the first pick never comes before 15 s, however high the score (3 s, score 1M)")
	main.elapsed = 15.0
	main.score = 1000000.0
	main._process(0.02)
	check(main.get_tree().paused and main._picking, "...it comes at 15 s once the score is there")
	main.pick_screen.hide_cards()
	main.get_tree().paused = false
	main._picking = false
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	pk.enabled = true
	pk.start_run(1.0)
	main.elapsed = 17.0
	main.score = 0.0
	main._process(0.02)
	check(not main._picking, "with a low score nothing happens at 17 s")
	main.elapsed = 19.99
	main._process(0.02)
	check(main.get_tree().paused and main._picking and not main._pick_is_extra, "...but it is guaranteed by 20 s regardless of score")
	await real_wait(0.55)
	main.pick_screen._on_card(0)
	check(not main.get_tree().paused and pk.picks_taken == 1 and pk.next_pick > 0.0, "(it counts as a normal pick; the next one is a full price away: %.0f)" % pk.next_pick)
	main.elapsed = 60.0
	main._process(0.02)
	check(not main._picking, "later picks are score-based only: 60 s in with a low score, no pick")
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	pk.enabled = true
	pk.start_run(1.0)
	var elapsed0: float = main.elapsed
	main.elapsed = 16.0
	main.score = 40.0
	main._process(0.02)
	check(main.get_tree().paused and main.pick_screen.is_shown() and main._pick_cards.size() == 3, "reaching the score pauses the game and shows three cards")
	var ids := {}
	for c in main._pick_cards:
		ids[c["kind"] + c["id"]] = true
	check(ids.size() == 3, "three different cards (%s)" % ", ".join(main._pick_cards.map(func(c): return c["name"])))
	await real_wait(0.05)
	main.pick_screen._on_card(0)
	check(main.get_tree().paused, "a tap in the first instant is ignored (the one already on its way)")
	await real_wait(0.3)
	check(is_equal_approx(main.elapsed, 16.02) and absf(main.pick_screen._cards[0].position.x - 60.0) < 1.0, "while paused nothing advances, and the cards have slid into place")
	var first_card: Dictionary = main._pick_cards[0]
	main.pick_screen._on_card(0)
	check(not main.get_tree().paused and not main.pick_screen.is_shown() and pk.next_pick > 40.0, "ONE tap on a card picks it at once: the game resumes and the next pick is set (%.0f)" % pk.next_pick)
	check(main.hud._next_label.text == "Next: " + tuning.fmt(pk.next_pick), "...shown as \"%s\"" % main.hud._next_label.text)
	if first_card["kind"] == "perk":
		check(pk.level(first_card["id"]) == 1, "a picked perk is owned at level 1")
	pk.start_run(1.0)
	# (c) card odds
	tsave.milestones = {}
	var starting := {}
	var seen_kinds := {}
	var dup := false
	for i in 1500:
		var cs: Array[Dictionary] = pk.roll(1.0, 3)
		var local := {}
		for c in cs:
			starting[c["id"]] = true
			seen_kinds[c["kind"]] = true
			dup = dup or local.has(c["id"])
			local[c["id"]] = true
	var want := ["glide", "cloud_diver", "lucky_whiskers", "fuel_miser", "hot_streak", "scavenger", "tailwind", "daredevil",
			"double_coins", "shield", "magnet_storm", "whisker_window", "fuel_freeze", "full_tank", "patch", "coin_bag", "crate_shower"]
	var pool_ok := starting.size() == want.size()
	for w in want:
		pool_ok = pool_ok and starting.has(w)
	check(pool_ok and not dup, "starting pool: perks 1, 2, 3, 6, 7, 8, 9, 10 + all five boosts + all four supplies; never the same card twice (%d kinds)" % starting.size())
	check(not starting.has("prop_wash") and not starting.has("battering_ram") and not starting.has("second_wind") and not starting.has("golden_touch"),
			"Prop Wash, Battering Ram, Second Wind and Golden Touch are locked until their milestones")
	tuning.crates_enabled = false
	var no_crates_seen := false
	for i in 400:
		for c in pk.roll(1.0, 3):
			no_crates_seen = no_crates_seen or c["id"] == "crate_shower"
	tuning.crates_enabled = true
	check(not no_crates_seen, "(the Crate Shower is only dealt while crates exist)")
	tsave.unlock_milestone("prop_wash")
	tsave.unlock_milestone("second_wind")
	var unlocked_seen := {}
	for i in 600:
		for c in pk.roll(1.0, 3):
			unlocked_seen[c["id"]] = true
	check(unlocked_seen.has("prop_wash") and unlocked_seen.has("second_wind") and not unlocked_seen.has("battering_ram"), "a milestone puts its perk in the pool")
	tsave.milestones = {}
	pk.start_run(1.0)
	pk.set_perk("glide", 1)
	var n_owned := 0
	var n_new := 0
	for i in 4000:
		for c in pk.roll(1.0, 3):
			if c["id"] == "glide":
				n_owned += 1
			elif c["id"] == "cloud_diver":
				n_new += 1
	check(float(n_owned) / n_new > 2.6 and float(n_owned) / n_new < 5.0, "an owned perk is offered more often: Glide %d vs Cloud Diver %d (about %.1fx)" % [n_owned, n_new, float(n_owned) / n_new])
	pk.set_perk("glide", 3)
	var maxed_seen := false
	for i in 500:
		for c in pk.roll(1.0, 3):
			maxed_seen = maxed_seen or c["id"] == "glide"
	check(not maxed_seen, "a level-3 perk is never offered again")
	pk.set_perk("glide", 0)
	var tank_low := 0
	var tank_full := 0
	for i in 3000:
		for c in pk.roll(0.1, 3):
			tank_low += int(c["id"] == "full_tank")
		for c in pk.roll(1.0, 3):
			tank_full += int(c["id"] == "full_tank")
	check(tank_low > tank_full * 1.5, "Full Tank is offered more when the tank is low (%d vs %d)" % [tank_low, tank_full])
	pk.set_perk("scavenger", 2)
	var two_cards: Array[Dictionary] = [pk.perk_card(tuning.perk_def("scavenger"), 3, true), pk.roll(1.0, 3)[0]]
	main.pick_screen.show_cards(two_cards, ["Combo", ""])
	var pips_lit := 0
	for pip in main.pick_screen._parts[0]["pips"]:
		pips_lit += int((pip.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.is_equal_approx(Color.WHITE))
	check(pips_lit == 3 and main.pick_screen._parts[0]["line"].text == "Cans pay 250 and add a bonus step" and main.pick_screen._parts[0]["combo"].visible and not main.pick_screen._parts[1]["combo"].visible,
			"a card is a big icon, a name, ONE short line (\"%s\") and level pips; a combo card is highlighted" % main.pick_screen._parts[0]["line"].text)
	main.pick_screen.hide_cards()
	pk.start_run(1.0)
	# (d) perk effects
	var fresh := func():
		main.restart()
		main.set_process(false)
		sp.reset(-500.0)
		pk.enabled = false
		pk.next_pick = INF
	fresh.call()
	# Glide
	pk.set_perk("glide", 1)
	main.fuel = 0.001
	for i in 30:
		main._process(0.05)
	check(main.alive and main._gliding and main.fuel == 0.0, "Glide level 1: with an empty tank the plane glides on (alive after 1.5 s)")
	for i in 60:
		main._process(0.05)
	check(not main.alive and main.hud._over.text.begins_with(main.HEADER_FUEL), "...and the run ends when the 4 s glide is over")
	fresh.call()
	pk.set_perk("glide", 3)
	main.fuel = 0.001
	for i in 40:
		main._process(0.05)
	main._on_pickup(Vector3(0, 0.4, -3))
	main._process(0.05)
	check(main.alive and not main._gliding and main.fuel > 10.0, "picking up a can during the glide ends it (level 3 = 6 s)")
	# Cloud Diver
	fresh.call()
	pk.set_perk("cloud_diver", 3)
	sp.run_time = 100.0
	sp._spawn_cloud(main.player.position.z)
	var dcl = sp._clouds[-1]
	dcl.position = Vector3(main.player.position.x, 0.0, main.player.position.z)
	dcl.ox[0] = 0.0
	dcl.oz[0] = 0.0
	dcl.rad[0] = 3.0
	dcl.on[0] = true
	main.fuel = 50.0
	main._process(0.05)
	check(absf(main.fuel - (50.0 - tuning.drain_rate() * 0.05 + 12.0 * 0.05)) < 0.01, "Cloud Diver level 3: flying under a cloud refunds fuel (%.3f after 0.05 s; a plain frame would give %.3f)" % [main.fuel, 50.0 - tuning.drain_rate() * 0.05])
	sp.reset(-500.0)
	# Lucky Whiskers
	fresh.call()
	pk.set_perk("lucky_whiskers", 3)
	var lrow2 = sp._rows_make_for_test(main.player.position.z - 12.0, [])
	for c in tuning.column_count:
		lrow2.open.append(c != 1)
	check(sp.drop_can_ahead(0.0) and lrow2.has_can and lrow2.can_x != tuning.column_center(1), "a can can be dropped in an open column of a row ahead")
	check(not sp.drop_can_ahead(0.0), "...but not where a row already has one")
	lrow2.has_can = false
	var drops := 0
	var wdrow = sp._rows_make_for_test(-3.0, [1.0])
	for i in 400:
		lrow2.has_can = false
		lrow2.can.visible = false
		main._on_near_miss({"side": 1, "node": wdrow.obs[0], "outline": wdrow.outlines[0], "whisker": true})
		drops += int(lrow2.has_can)
	check(drops > 400 * 0.97, "Lucky Whiskers level 3: every Whisker close drops a can (%d of 400)" % drops)
	main.hud.reset_for_run()
	# Prop Wash
	tsave.unlock_milestone("prop_wash")
	fresh.call()
	pk.set_perk("prop_wash", 1)
	var pwrow = sp._rows_make_for_test(-5.0, [-2.0, 0.0])
	main.score = 0.0
	var evw := {"side": 1, "node": pwrow.obs[0], "outline": pwrow.outlines[0], "whisker": false, "row": pwrow, "k": 0}
	main._on_near_miss(evw)
	for i in 30:
		sp.update_hazards(0.05)
	check(pwrow.xs[0] > -2.0 and is_equal_approx(main.score, 0.5 * 1.0 * 0.0 + 8.0 + 0.0) or main.score >= 8.0, "Prop Wash: the obstacle you passed is shoved sideways, bumps its neighbour and pays coins (%.0f)" % main.score)
	check(pwrow.xs[0] > -2.0 and pwrow.xs[0] <= 0.0 - 0.01 and pwrow.nudge_k.is_empty(), "...and stops there (moved %.2f)" % (pwrow.xs[0] + 2.0))
	tsave.milestones = {}
	# Fuel Miser / Hot Streak / Scavenger / Tailwind / Daredevil / Second Wind
	fresh.call()
	pk.set_perk("fuel_miser", 3)
	main.fuel = 100.0
	main._process(0.05)
	check(is_equal_approx(main.fuel, 100.0 - tuning.drain_rate() * 0.35 * 0.05), "Fuel Miser level 3: 65%% less fuel burned (%.3f in 0.05 s)" % (100.0 - main.fuel))
	main._steps.append(0.5)
	main._refresh_bonus()
	main._bonus_timer = 0.0
	main._decay_acc = 0.0
	pk.set_perk("hot_streak", 2)
	main._decay_bonus(0.1)
	check(is_equal_approx(main._decay_acc, tuning.bonus_decay_rate / 2.5 * 0.1), "Hot Streak level 2: the bonus fades 150%% slower (2.5x)")
	fresh.call()
	pk.set_perk("scavenger", 2)
	main.coin_mult = 2.0
	main.score = 0.0
	main._on_pickup(Vector3(0, 0.4, -3))
	check(is_equal_approx(main.score, 90.0 * 2.0), "Scavenger level 2: each can pays 90 extra coins (x the multiplier)")
	fresh.call()
	pk.set_perk("tailwind", 3)
	main.coin_mult = 1.0
	main.elapsed = 0.0
	main.score = 0.0
	main.run_distance = 0.0
	main._process(0.05)
	var sp1: float = tuning.map_speed(0, 0.05)
	check(absf(main.run_distance - sp1 * 1.3 * 0.05) < 0.001 and absf(main.score - sp1 * 1.3 * 0.05 * (1.0 - tuning.bonus_pay_offset) * 1.9) < 0.001, "Tailwind level 3: +30%% speed and +90%% coins")
	fresh.call()
	pk.set_perk("daredevil", 3)
	var ddrow = sp._rows_make_for_test(-4.0, [main.player.position.x + tuning.pickup_reach() + 0.0])
	var wing: float = main.player.collision_half_span()
	var dd_half: Vector2 = sp._obstacle_half()
	ddrow.xs[0] = main.player.position.x + wing + dd_half.x + 0.35
	var found_dd: Array[Dictionary] = []
	var found_no: Array[Dictionary] = []
	var pcaps: PackedFloat32Array = main.player.hit_capsules()
	var ppos := Vector2(main.player.position.x, 0.0)
	sp.near_miss_scale = 1.3
	var zz2 := -4.0
	while zz2 < 6.0:
		ddrow.position.z = zz2
		found_dd.append_array(sp.update_near_misses(ppos, pcaps))
		zz2 += 0.1
	ddrow.passed = false
	ddrow.entered = false
	ddrow.min_clear = INF
	sp.near_miss_scale = 1.0
	zz2 = -4.0
	while zz2 < 6.0:
		ddrow.position.z = zz2
		found_no.append_array(sp.update_near_misses(ppos, pcaps))
		zz2 += 0.1
	check(found_dd.size() == 1 and found_no.is_empty(), "Daredevil level 3: a pass 0.35 clear counts as a close call (normally 0.30)")
	fresh.call()
	pk.set_perk("second_wind", 2)
	main.fuel = 10.0
	main._process(0.05)
	check(main.fuel > 75.0 and main.fuel < 85.0 and main._second_wind_count == 1, "Second Wind level 2: under 15%% fuel it refills 70%% of the tank (%.0f)" % main.fuel)
	main.fuel = 10.0
	main._process(0.05)
	check(main.fuel < 12.0, "...once per run")
	pk.set_perk("second_wind", 0)
	# (e) boosts
	fresh.call()
	pk.take({"kind": "boost", "id": "double_coins"})
	check(is_equal_approx(main.earn_mult(), 2.0) and pk.has_boost("double_coins") and is_equal_approx(pk.boost_left("double_coins"), tuning.boost_time), "Double Coins: everything pays double for %.0f s" % tuning.boost_time)
	main._process(0.05)
	check(main.hud._effect_labels[0].visible and main.hud._effect_labels[0].text == "DOUBLE COINS  20s", "...with a countdown on the HUD (\"%s\")" % main.hud._effect_labels[0].text)
	pk.update(tuning.boost_time + 0.1)
	check(not pk.has_boost("double_coins") and is_equal_approx(main.earn_mult(), 1.0), "...and it ends after about 20 s")
	fresh.call()
	pk.take({"kind": "boost", "id": "shield"})
	var shrow = sp._rows_make_for_test(main.player.position.z, [main.player.position.x])
	main._process(0.02)
	check(main.alive and not pk.has_boost("shield") and main._invuln > 0.0 and main.lives == 0, "Shield: one free hit, then it is gone")
	fresh.call()
	pk.take({"kind": "boost", "id": "magnet_storm"})
	var msrow = sp._rows_make_for_test(main.player.position.z - 2.0, [])
	sp._place_can_for_test(msrow, main.player.position.x + 5.0)
	for i in 20:
		main._process(0.03)
	check(main.run_cans == 1, "Magnet Storm: a can 5 units away flies to the plane")
	fresh.call()
	pk.take({"kind": "boost", "id": "whisker_window"})
	var wwrow = sp._rows_make_for_test(-5.0, [1.0])
	main._on_near_miss({"side": 1, "node": wwrow.obs[0], "outline": wwrow.outlines[0], "whisker": false})
	check(is_equal_approx(main.bonus, 2.0), "Whisker Window: a plain close call earns the doubled step (x2.0)")
	fresh.call()
	pk.take({"kind": "boost", "id": "fuel_freeze"})
	main.fuel = 50.0
	main._process(0.1)
	check(main.fuel == 50.0, "Fuel Freeze: no fuel burns")
	# (f) supplies
	fresh.call()
	main.fuel = 10.0
	main._apply_card({"kind": "supply", "id": "full_tank"})
	check(main.fuel == tuning.fuel_max(), "Full Tank fills the tank")
	main._apply_card({"kind": "supply", "id": "patch"})
	check(main.lives == 1 and main.hud._lives_pips[0].visible, "Patch: +1 hit you can survive")
	pk.start_run(1.0)
	main.score = 0.0
	var bag: float = pk.coin_bag_amount()
	main._apply_card({"kind": "supply", "id": "coin_bag"})
	check(is_equal_approx(bag, floorf(0.3 * pk.price(1))) and is_equal_approx(main.score, bag), "Coin Bag: instant coins, %.0f%% of the next pick's price (%.0f)" % [tuning.coin_bag_fraction * 100.0, bag])
	# HUD: perk icons
	fresh.call()
	pk.set_perk("glide", 2)
	pk.set_perk("tailwind", 1)
	var icons_on := 0
	for ic in main.hud._perk_icons:
		icons_on += int(ic["panel"].visible)
	check(icons_on == 2, "the run's perks show as small icons on the HUD (%d)" % icons_on)
	pk.set_perk("glide", 0)
	pk.set_perk("tailwind", 0)
	# (g) ?tune: grant any perk at any level
	var btns := {}
	for bt in main.tune_panel.find_children("*", "Button", true, false):
		if bt.get_meta("debug", "") != "":
			btns[bt.get_meta("debug")] = bt
	fresh.call()
	for i in 3:   # Glide -> Cloud Diver -> Lucky Whiskers -> Prop Wash
		btns["perk_cycle"].pressed.emit()
	btns["level_cycle"].pressed.emit()   # level 3 -> 0
	btns["level_cycle"].pressed.emit()   # 1
	btns["level_cycle"].pressed.emit()   # 2
	btns["grant_perk"].pressed.emit()
	check(pk.level("prop_wash") == 2 and pk.debug_grants.get("prop_wash", 0) == 2 and main.hud._perk_icons[0]["panel"].visible, "?tune: Grant gives any perk at any level (Prop Wash 2, even though it is locked)")
	main.restart()
	main.set_process(false)
	check(pk.level("prop_wash") == 2, "...and it is there at the start of every run")
	pk.debug_grants.clear()
	pk.set_perk("prop_wash", 0)
	# (h) none of it allocated anything
	pk.enabled = false
	main.hud.play_pressed.emit()
	main.set_process(false)
	main.fx.clear()
	var snap_picks := snapshot(main)
	snap_picks["mats"].erase(sp._gull_mat.get_instance_id())
	check(same_world(base, snap_picks), "picks, perks, boosts and supplies created nothing new  [%s]" % describe(snap_picks))
	tsave.reset_all()

	print("2n. combos and the Logbook")
	tsave.reset_all()
	var cb: Array = tuning.combos
	var pairs := {"deadstick": ["glide", "magnet"], "cloud_surfer": ["cloud_diver", "cloud_eye"], "barnstormer": ["hot_streak", "steady_nerves"], "fuel_overflow": ["fuel_miser", "reserve_tank"],
			"golden_whiskers": ["lucky_whiskers", "head_start"], "cats_cradle": ["battering_ram", "nine_lives"], "wingwalker": ["prop_wash", "daredevil"]}
	var pairs_ok := cb.size() == 7
	for c in cb:
		pairs_ok = pairs_ok and pairs.has(c["id"]) and c["perk"] == pairs[c["id"]][0] and c["partner"] == pairs[c["id"]][1] and c["line"] != "" and c["hint"] != ""
	check(pairs_ok and cb[6]["partner_kind"] == "perk" and cb[0]["partner_kind"] == "gear", "seven combos with their partners: Deadstick, Cloud Surfer, Barnstormer, Fuel Overflow, Golden Whiskers, Cat's Cradle, Wingwalker (the last is perk + perk)")
	var fresh2 := func():
		main.restart()
		main.set_process(false)
		sp.reset(-500.0)
		pk.enabled = false
		pk.next_pick = INF
	tsave.add_coins(1e12)
	for g in ["magnet", "cloud_eye", "steady_nerves", "reserve_tank", "head_start", "nine_lives"]:
		tsave.buy(g)
	tsave.buy_slot()
	tsave.buy_slot()
	check(tsave.slots == 3, "(setup: all gear owned, three slots)")
	# (a) triggering: level 3 + the partner, either order; a banner and a Logbook entry
	tsave.loadout = ["magnet", "", ""]
	fresh2.call()
	pk.set_perk("glide", 2)
	main._check_combos()
	check(not main.combo_on("deadstick") and not main.hud._combo_label.visible, "Glide level 2 with the magnet: no combo yet")
	var cardG: Dictionary = pk.perk_card(tuning.perk_def("glide"), 3, true)
	check(pk.would_complete(cardG) == "deadstick", "a card that would complete a combo is recognised (so the pick screen can highlight it)")
	main._apply_card(cardG)
	main._check_combos()
	check(main.combo_on("deadstick") and main.hud._combo_label.visible and main.hud._combo_label.text == "DEADSTICK" and main.hud._combo_sub.text == "COMBO!"
			and main.hud._combo_label.get_theme_color("font_color").is_equal_approx(cb[0]["color"]), "Glide reaches level 3 with the Can Magnet equipped: the DEADSTICK banner")
	check(count_visible(main.fx._whisker_emitters) >= 1 and tsave.combos_found.has("deadstick"), "...with its own burst, and the Logbook records it")
	var hints2: Array = []
	var cardsG: Array[Dictionary] = [pk.perk_card(tuning.perk_def("cloud_diver"), 1, false)]
	for c in cardsG:
		hints2.append(pk.would_complete(c))
	check(hints2 == [""], "an ordinary card is not marked")
	fresh2.call()
	check(not main.combo_on("deadstick"), "combos reset with each run")
	tsave.loadout = ["", "", ""]
	pk.set_perk("glide", 3)
	main._check_combos()
	check(not main.combo_on("deadstick"), "level 3 without the partner gear equipped: nothing")
	tsave.loadout = ["magnet", "", ""]
	main._check_combos()
	check(main.combo_on("deadstick"), "...equip it and the combo is there (either order works)")
	main.pick_screen.show_cards(pk.roll(1.0, 3), ["wingwalker", "", ""])
	check(main.pick_screen._parts[0]["combo"].visible and not main.pick_screen._parts[1]["combo"].visible, "on the pick screen a combo-completing card shows COMBO!")
	main.pick_screen.hide_cards()
	# (b) Deadstick
	fresh2.call()
	pk.set_perk("glide", 3)
	main._check_combos()
	main.fuel = 0.001
	for i in 3:
		main._process(0.05)
	var droww = sp._rows_make_for_test(main.player.position.z - 1.0, [])
	sp._place_can_for_test(droww, 4.3)
	var glide0: float = main._glide_left
	var cans0: int = main.run_cans
	for i in 25:
		main._process(0.03)
	check(main.run_cans == cans0 + 1 and main.fuel == 0.0 and main._gliding and main._glide_left > glide0 - 1.0 + 1.5, "Deadstick: while gliding a can far across the screen is pulled in, and it ADDS to the glide (+%.0f s) instead of refuelling" % tuning.deadstick_extend)
	# (c) Cloud Surfer
	tsave.loadout = ["cloud_eye", "", ""]
	fresh2.call()
	pk.set_perk("cloud_diver", 3)
	main._check_combos()
	check(main.combo_on("cloud_surfer"), "Cloud Diver 3 + Cloud Eye: CLOUD SURFER")
	var csrow = sp._rows_make_for_test(-5.0, [1.0])
	var evc := {"side": 1, "node": csrow.obs[0], "outline": csrow.outlines[0], "whisker": false}
	main._on_near_miss(evc)
	check(is_equal_approx(main.bonus, 1.5), "a close call out in the open: a plain step (x1.5)")
	main._reset_bonus()
	sp.run_time = 100.0
	sp._spawn_cloud(main.player.position.z)
	var scl = sp._clouds[-1]
	scl.position = Vector3(main.player.position.x, 0.0, main.player.position.z)
	scl.ox[0] = 0.0
	scl.oz[0] = 0.0
	scl.rad[0] = 3.0
	scl.on[0] = true
	main._on_near_miss(evc)
	check(is_equal_approx(main.bonus, 2.0), "...under a cloud it counts as a Whisker close (x2.0)")
	sp.reset(-500.0)
	# (d) Barnstormer
	tsave.loadout = ["steady_nerves", "", ""]
	fresh2.call()
	pk.set_perk("hot_streak", 3)
	main._check_combos()
	main._steps.clear()
	for v in [0.5, 0.4, 0.3, 0.2]:
		main._steps.append(v)
	main._refresh_bonus()
	main._bonus_timer = 0.0
	main._decay_acc = 5.0
	for i in 20:
		main._decay_bonus(0.5)
	check(main.combo_on("barnstormer") and is_equal_approx(main.bonus, 2.4), "Barnstormer: above x2 the bonus never fades (still x%.1f after 10 s)" % main.bonus)
	main._steps.clear()
	for v in [0.5, 0.4]:
		main._steps.append(v)
	main._refresh_bonus()
	main._decay_acc = 1.0
	main._decay_bonus(0.01)
	check(main.bonus < 1.9, "...at x2 or below it fades as usual (x%.1f)" % main.bonus)
	# (e) Fuel Overflow
	tsave.loadout = ["reserve_tank", "", ""]
	fresh2.call()
	pk.set_perk("fuel_miser", 3)
	main._check_combos()
	main.coin_mult = 2.0
	main.score = 0.0
	main.fuel = tuning.fuel_max()
	main._on_pickup(Vector3(0, 0.4, -3))
	check(main.combo_on("fuel_overflow") and is_equal_approx(main.score, tuning.refill_amount() * tuning.overflow_coin_rate * 2.0), "Fuel Overflow: a can on a full tank turns its fuel into coins (%.0f)" % main.score)
	main.score = 0.0
	main.fuel = tuning.fuel_max() - 5.0
	main._on_pickup(Vector3(0, 0.4, -3))
	check(is_equal_approx(main.score, (tuning.refill_amount() - 5.0) * tuning.overflow_coin_rate * 2.0) and main.fuel == tuning.fuel_max(), "...only the part beyond a full tank")
	# (f) Golden Whiskers
	tsave.loadout = ["head_start", "", ""]
	fresh2.call()
	pk.set_perk("lucky_whiskers", 3)
	main._check_combos()
	check(main.combo_on("golden_whiskers"), "Lucky Whiskers 3 + Head Start: GOLDEN WHISKERS")
	var gwrow = sp._rows_make_for_test(main.player.position.z - 12.0, [])
	for c in tuning.column_count:
		gwrow.open.append(true)
	check(sp.drop_can_ahead(0.0, true) and gwrow.can_golden and gwrow.can.material_override == sp._golden_can_mat, "a Whisker-dropped can is golden (its own material)")
	main.coin_mult = 1.0
	main.score = 0.0
	main.hud.reset_for_run()
	var gcans: Array[Vector3] = [Vector3(gwrow.can_x, 0.4, gwrow.position.z)]
	main._on_pickup(gcans[0], true)
	check(is_equal_approx(main.score, tuning.golden_can_coins) and main.run_cans == 1, "collecting a golden can pays fuel plus %.0f coins" % tuning.golden_can_coins)
	gwrow.can_golden = false
	# (g) Cat's Cradle
	tsave.loadout = ["nine_lives", "", ""]
	fresh2.call()
	pk.set_perk("battering_ram", 3)
	main._check_combos()
	var lives0: int = main.lives
	for i in 9:
		main._on_crate_broken()
	check(main.combo_on("cats_cradle") and main.lives == lives0, "Cat's Cradle: nine crates give nothing yet")
	main._on_crate_broken()
	check(main.lives == lives0 + 1 and main.hud._lives_pips[lives0].visible, "...the tenth restores a life")
	# (h) Wingwalker (perk + perk)
	tsave.loadout = ["", "", ""]
	fresh2.call()
	pk.set_perk("prop_wash", 3)
	main._check_combos()
	check(not main.combo_on("wingwalker"), "Prop Wash 3 alone: no combo")
	pk.set_perk("daredevil", 1)
	main._check_combos()
	check(main.combo_on("wingwalker"), "Prop Wash 3 + any Daredevil: WINGWALKER (a perk partner counts)")
	var wwr = sp._rows_make_for_test(-5.0, [-4.0, -2.0, 0.0, 2.0])
	var pays: Array[float] = []
	var bump_cb := func(_pos, depth): pays.append(depth)
	sp.bump.connect(bump_cb)
	main.score = 0.0
	sp.nudge_obstacle(wwr, 0, 1, tuning.prop_wash_push, 0)
	for i in 60:
		main._process(0.02)
		wwr.position.z = -5.0
	check(pays.size() >= 3 and pays[0] == 0 and pays[1] == 1 and pays[2] == 2, "Wingwalker: the shoved obstacle bumps the next, which bumps the next (chain depths %s)" % str(pays))
	var expect_pay: float = 0.0
	for d in pays:
		expect_pay += tuning.perk_value("prop_wash", 3) * (1.0 + d)
	check(main.score >= expect_pay and main.score - expect_pay < 30.0 and expect_pay > tuning.perk_value("prop_wash", 3) * pays.size(), "...and each link pays more (%.0f coins for %d links)" % [main.score, pays.size()])
	sp.bump.disconnect(bump_cb)
	pk.set_perk("daredevil", 0)
	# (i) the Logbook
	tsave.reset_all()
	main.hud.show_menu()
	check(main.hud._logbook != null and not main.hud._logbook.visible, "the Logbook starts closed")
	main.hud.logbook_pressed.emit()
	check(main.screen == main.SCREEN_LOGBOOK and main.hud._logbook.visible and not main.hud._menu.visible, "the start screen's LOGBOOK button opens it")
	var r0: Dictionary = main.hud._logbook_rows[0]
	check((r0["title"] as Label).text == "???" and (r0["line"] as Label).text.begins_with("Hint: "), "an undiscovered combo is a silhouette with a hint (\"%s\")" % (r0["line"] as Label).text)
	tsave.discover_combo("deadstick")
	main.hud.refresh_logbook()
	check((r0["title"] as Label).text == "Deadstick" and (r0["line"] as Label).text.contains("glid") and not (main.hud._logbook_rows[1]["title"] as Label).text == "Cloud Surfer", "a discovered one shows its name and what it does; the others stay hidden")
	tsave.save_game()
	tsave.combos_found = {}
	tsave.load_game()
	check(tsave.combos_found.has("deadstick") and not tsave.combos_found.has("wingwalker"), "discovered combos are saved")
	var v4 := FileAccess.open(tsave.path, FileAccess.WRITE)
	v4.store_string(JSON.stringify({"version": 4, "high_score": 1, "coins": 5, "levels": {}, "slots": 1, "loadout": ["", "", ""], "milestones": {"prop_wash": true}}))
	v4.close()
	tsave.load_game()
	check(tsave.VERSION == 5 and tsave.milestones.has("prop_wash") and tsave.combos_found.is_empty() and tsave.coins == 5.0, "a v4 save migrates to v5 (milestones kept, no combos yet)")
	main.hud.back_pressed.emit()
	check(main.screen == main.SCREEN_MENU and not main.hud._logbook.visible, "BACK returns to the start screen")
	tsave.reset_all()
	# (j) none of it allocated anything
	tsave.loadout = ["", "", ""]
	main.hud.play_pressed.emit()
	main.set_process(false)
	main.fx.clear()
	pk.enabled = false
	var snap_combo := snapshot(main)
	snap_combo["mats"].erase(sp._gull_mat.get_instance_id())
	snap_combo["mats"].erase(sp._golden_can_mat.get_instance_id())
	check(same_world(base, snap_combo), "combos, banners and the Logbook created nothing new  [%s]" % describe(snap_combo))
	tsave.reset_all()

	print("2o. crates and milestones")
	tsave.reset_all()
	tuning.crate_chance = 0.5
	# (a) crates take blocked cells only, in the right colours
	sp.apply_map(0)
	sp.reset(-500.0)
	sp.run_time = 1.0
	var early_crates := 0
	for i in 200:
		sp._spawn_row(-30.0)
		var er2 = sp._rows[-1]
		for kcr in er2.crate_kind:
			early_crates += int(kcr != 0)
		sp._release_row(er2)
	check(early_crates == 0, "no crates in the first %.0f s of a run" % tuning.crate_start_time)
	sp.run_time = 30.0
	var n_cr := 0
	var n_blk := 0
	var kinds := [0, 0, 0]
	var layout_ok := true
	for i in 1500:
		sp._spawn_row(-30.0)
		var cr2 = sp._rows[-1]
		var blocked_n := 0
		for c in cr2.open:
			blocked_n += int(not c)
		layout_ok = layout_ok and cr2.obs.size() == blocked_n and cr2.crate_kind.size() == cr2.obs.size()
		for k in cr2.obs.size():
			n_blk += 1
			if cr2.crate_kind[k] != 0:
				n_cr += 1
				kinds[cr2.crate_kind[k] - 1] += 1
				layout_ok = layout_ok and cr2.obs[k].material_override == sp._crate_mat and cr2.crate_glows[cr2.obs_cols[k]].visible and cr2.crate_glows[cr2.obs_cols[k]].material_override == sp._crate_glow_mats[cr2.crate_kind[k] - 1]
			else:
				layout_ok = layout_ok and not cr2.crate_glows[cr2.obs_cols[k]].visible
		sp._release_row(cr2)
	check(layout_ok, "FAIRNESS: a crate takes a blocked cell, never an open one (every row: obstacles = blocked columns), with its own wood body and a glow plate")
	check(absf(float(n_cr) / n_blk - 0.5) < 0.04 and absf(kinds[0] / float(n_cr) - 0.60) < 0.05 and absf(kinds[1] / float(n_cr) - 0.32) < 0.05 and absf(kinds[2] / float(n_cr) - 0.08) < 0.03,
			"crate_chance %.2f of blocked cells; contents about 60%% gold / 32%% green / 8%% purple (the extra pick is rare) (%d / %d / %d)" % [tuning.crate_chance, kinds[0], kinds[1], kinds[2]])
	check(tuning.crate_colors[0] != tuning.crate_colors[1] and tuning.crate_colors[1] != tuning.crate_colors[2] and tuning.crate_colors[2] != tuning.crate_colors[0], "glow colours: gold, green, purple")
	# (b) the crate rules: the front face breaks it, the sides crash
	tuning.crate_chance = 0.0
	var crate_run := func():
		main.restart()
		main.set_process(false)
		sp.reset(-500.0)
		pk.enabled = false
		pk.next_pick = INF
	crate_run.call()
	var pz: float = main.player.position.z
	var px: float = main.player.position.x
	var chalf: Vector2 = sp._obstacle_half()
	var ccaps: PackedFloat32Array = main.player.hit_capsules()
	check(is_equal_approx(tuning.ram_speed, 0.0) and tuning.crate_front_forgive > 0.0, "no speed requirement any more (ram_speed %.0f), and the front face is more forgiving (+%.2f)" % [tuning.ram_speed, tuning.crate_front_forgive])
	var crow = sp._rows_make_for_test(pz - 0.6, [px])   # a crate scrolling in on a plane that just holds position
	crow.crate_kind[0] = 1
	main.score = 0.0
	main._process(0.02)
	check(main.alive and crow.crate_kind[0] == 0 and crow.xs[0] > 1000.0 and not crow.obs[0].visible and main.score >= tuning.crate_coins,
			"a crate that scrolls into the plane's nose head-on breaks (no flick needed), pays and the plane flies on (coins %.0f)" % main.score)
	check(count_visible(main.fx._crate_emitters) >= 1, "...with a break effect")
	check(not sp.hits(Vector2(px, pz), ccaps), "a broken crate is gone for good")
	crate_run.call()
	pz = main.player.position.z
	px = main.player.position.x
	crow = sp._rows_make_for_test(pz, [px + 1.5])   # beside the wing
	crow.crate_kind[0] = 1
	main._process(0.02)
	check(not main.alive and main.hud._over.text.contains(main.REASON_CRATE), "a crate touched from the SIDE crashes the plane (\"%s\")" % main.REASON_CRATE)
	crate_run.call()
	pz = main.player.position.z
	px = main.player.position.x
	crow = sp._rows_make_for_test(pz + 0.4, [px])   # the plane is level with / above its centre: not a front hit
	crow.crate_kind[0] = 1
	main._process(0.02)
	check(not main.alive, "...and so does one the plane is already beside or above")
	# forgiveness: the front face counts wider than the crate, the sides do not
	var inside_front: float = chalf.x + tuning.crate_front_forgive - 0.05
	var outside_front: float = chalf.x + tuning.crate_front_forgive + 0.1
	crate_run.call()
	pz = main.player.position.z
	px = main.player.position.x
	crow = sp._rows_make_for_test(pz - 0.6, [px + inside_front])
	crow.crate_kind[0] = 1
	main._process(0.02)
	check(main.alive and crow.crate_kind[0] == 0, "a head-on touch just off the crate's width (%.2f from its centre, its half-width is %.2f) still breaks it" % [inside_front, chalf.x])
	crate_run.call()
	pz = main.player.position.z
	px = main.player.position.x
	crow = sp._rows_make_for_test(pz - 0.6, [px + outside_front])
	crow.crate_kind[0] = 1
	main._process(0.02)
	check(not main.alive, "...but a touch further out (%.2f) is a side hit and crashes" % outside_front)
	# the optional speed rule still works when ram_speed is set
	tuning.ram_speed = 9.0
	crate_run.call()
	pz = main.player.position.z
	px = main.player.position.x
	crow = sp._rows_make_for_test(pz - 0.6, [px])
	crow.crate_kind[0] = 1
	main._process(0.02)
	check(not main.alive, "(with ram_speed 9 a plane that is not moving up crashes)")
	crate_run.call()
	pz = main.player.position.z
	px = main.player.position.x
	crow = sp._rows_make_for_test(pz - 0.6, [px])
	crow.crate_kind[0] = 1
	drag_by(main.player, Vector2(0.0, -160.0))
	main._process(0.05)
	check(main.alive and crow.crate_kind[0] == 0, "(...and one flying up fast enough breaks it)")
	tuning.ram_speed = 0.0
	# Battering Ram: any contact breaks it
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	pk.enabled = false
	pk.next_pick = INF
	pk.set_perk("battering_ram", 1)
	pz = main.player.position.z
	px = main.player.position.x
	crow = sp._rows_make_for_test(pz, [px])
	crow.crate_kind[0] = 1
	main.score = 0.0
	main._process(0.02)
	check(main.alive and crow.crate_kind[0] == 0 and main.score >= tuning.crate_coins, "Battering Ram: a crate breaks on any touch")
	# rewards: coins scale with Battering Ram level and Golden Touch; green = fuel; purple = an extra pick
	main.score = 0.0
	main.coin_mult = 1.0
	pk.set_perk("battering_ram", 3)
	main._on_crate_break(1, Vector3(0, 0.4, -3))
	check(is_equal_approx(main.score, tuning.crate_coins * 2.0), "Battering Ram level 3: crate coins x2 (%.0f)" % main.score)
	pk.set_perk("golden_touch", 3)
	main.score = 0.0
	main._on_crate_break(1, Vector3(0, 0.4, -3))
	check(is_equal_approx(main.score, tuning.crate_coins * 2.0 * 8.0), "Golden Touch level 3 pays x8 on top (%.0f)" % main.score)
	pk.set_perk("golden_touch", 1)
	main.fuel = 20.0
	main._on_crate_break(2, Vector3(0, 0.4, -3))
	check(main.fuel >= minf(tuning.fuel_max(), 20.0 + tuning.crate_fuel * 3.0 + 0.15 * tuning.fuel_max()) - 0.01, "a green crate gives fuel (x Golden Touch level 1 = x3, Battering Ram 3 adds 15%%: %.0f)" % main.fuel)
	pk.set_perk("golden_touch", 0)
	pk.set_perk("battering_ram", 0)
	pk.enabled = true
	pk.start_run(1.0)
	var taken0: int = pk.picks_taken
	var next0: float = pk.next_pick
	main.score = 1.0
	main._on_crate_break(3, Vector3(0, 0.4, -3))
	main._process(0.02)
	check(main.get_tree().paused and main.pick_screen.is_shown() and main._pick_is_extra, "a purple crate gives an instant extra pick (the game pauses)")
	await real_wait(0.55)
	main.pick_screen._on_card(0)
	check(not main.get_tree().paused and pk.picks_taken == taken0 and pk.next_pick == next0, "...and it does not use up the score for the next pick")
	pk.enabled = false
	pk.next_pick = INF
	# Crate Shower
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	var shower_len: int = tuning.crate_shower_rows
	tuning.crate_shower_rows = 40   # (a long shower, so the count is not a coin flip)
	main._apply_card({"kind": "supply", "id": "crate_shower"})
	tuning.crate_chance = 0.0
	sp.run_time = 30.0
	var shower_crates := 0
	var shower_blocked := 0
	for i in 40:
		sp._spawn_row(-30.0)
		var sr = sp._rows[-1]
		for k in sr.obs.size():
			shower_blocked += 1
			shower_crates += int(sr.crate_kind[k] != 0)
		sp._release_row(sr)
	check(sp.crate_shower_rows == 0 and float(shower_crates) / shower_blocked > 0.6, "Crate Shower: the next rows are full of crates (%d of %d blocked cells)" % [shower_crates, shower_blocked])
	tuning.crate_shower_rows = shower_len
	sp._spawn_row(-30.0)
	var after_sr = sp._rows[-1]
	var plain_after := 0
	for k in after_sr.obs.size():
		plain_after += int(after_sr.crate_kind[k] != 0)
	sp._release_row(after_sr)
	check(plain_after == 0, "...then back to normal")
	# Cat's Cradle through real crate breaks
	tsave.loadout = ["nine_lives", "", ""]
	tsave.levels["nine_lives"] = 1
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	pk.enabled = false
	pk.next_pick = INF
	pk.set_perk("battering_ram", 3)
	main._check_combos()
	var l0: int = main.lives
	var crates0: float = tsave.stat("crates")
	for i in 10:
		main._on_crate_break(1, Vector3(0, 0.4, -3))
	check(main.combo_on("cats_cradle") and main.lives == l0 + 1 and tsave.stat("crates") == crates0 + 10.0, "ten crate breaks restore a life with Cat's Cradle, and each counts toward the lifetime total")
	pk.set_perk("battering_ram", 0)
	tsave.loadout = ["", "", ""]
	# (c) milestones
	tsave.reset_all()
	check(tsave.milestones.is_empty() and not tsave.perk_unlocked("prop_wash") and tsave.perk_unlocked("glide"), "at the start only the starting perks are unlocked")
	tsave.stats["cans"] = 99.0
	main.restart()
	main.set_process(false)
	main.run_cans = 1
	main.score = 10.0
	main._end_run(main.HEADER_CRASH, main.REASON_OBSTACLE)
	check(tsave.milestones.has("prop_wash") and tsave.perk_unlocked("prop_wash") and main.hud._over.text.contains("Perk unlocked: Prop Wash!"), "collecting the 100th can unlocks Prop Wash (it says so on the game-over screen)")
	check(main.hud._combo_label.visible and main.hud._combo_label.text == "PROP WASH" and main.hud._combo_sub.text == "PERK UNLOCKED!", "...with an unlock popup")
	check(pk.perk_offered(tuning.perk_def("prop_wash")), "...and it is now offered on the pick screen")
	tsave.stats["whiskers"] = 10.0
	tsave.stats["crates"] = 49.0
	main.restart()
	main.set_process(false)
	main._on_crate_break(1, Vector3(0, 0.4, -3))
	main._end_run(main.HEADER_CRASH, main.REASON_OBSTACLE)
	check(tsave.milestones.has("second_wind") and tsave.milestones.has("battering_ram") and not tsave.milestones.has("golden_touch"), "10 Whisker closes unlock Second Wind; the 50th crate unlocks Battering Ram")
	tsave.unlock_all_maps()
	main.restart()
	main.set_process(false)
	main._end_run(main.HEADER_CRASH, main.REASON_OBSTACLE)
	check(tsave.milestones.has("golden_touch"), "reaching the Coast unlocks Golden Touch")
	tsave.save_game()
	tsave.milestones = {}
	tsave.load_game()
	check(tsave.milestones.size() == 4 and tsave.perk_unlocked("golden_touch"), "milestones are saved")
	tsave.reset_all()
	tsave.stats["cans"] = 42.0
	main.hud.refresh_logbook()
	check((main.hud._milestone_rows[0]["line"] as Label).text.contains("42 / 100") and (main.hud._milestone_rows[0]["title"] as Label).text.contains("locked"), "the Logbook shows each milestone and your progress (\"%s\")" % (main.hud._milestone_rows[0]["line"] as Label).text)
	tsave.unlock_milestone("prop_wash")
	main.hud.refresh_logbook()
	check((main.hud._milestone_rows[0]["title"] as Label).text.contains("unlocked"), "...and which are unlocked")
	var ubtn: Button = null
	for bt in main.tune_panel.find_children("*", "Button", true, false):
		if bt.get_meta("debug", "") == "unlock_milestones":
			ubtn = bt
	tsave.reset_all()
	ubtn.pressed.emit()
	check(tsave.milestones.size() == 4, "?tune: Unlock all milestones")
	tsave.reset_all()
	# (d) nothing new allocated
	tuning.crate_chance = 0.0
	main.hud.play_pressed.emit()
	main.set_process(false)
	main.fx.clear()
	var snap_crates := snapshot(main)
	check(same_world(base, snap_crates), "crates, their bursts, milestones and the Logbook created nothing new  [%s]" % describe(snap_crates))
	tsave.reset_all()

	print("2p. frame time: nothing fast-forwards")
	tsave.reset_all()
	tuning.crate_chance = 0.0
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	pk.enabled = false
	pk.next_pick = INF
	check(Engine.max_physics_steps_per_frame == 1, "physics catch-up is off (max_physics_steps_per_frame = %d)" % Engine.max_physics_steps_per_frame)
	var e0: float = main.elapsed
	main._process(0.2)
	check(is_equal_approx(main.elapsed - e0, tuning.max_frame_delta), "a long frame (0.2 s) advances the simulation by at most %.2f s" % tuning.max_frame_delta)
	e0 = main.elapsed
	main._process(2.0)
	check(main.elapsed == e0 and main._skip_frames == tuning.resume_skip_frames, "a stall (2 s: a tab switch, a hitch) is dropped: nothing is simulated")
	var skipped_ok := true
	for i in tuning.resume_skip_frames:
		main._process(0.016)
		skipped_ok = skipped_ok and main.elapsed == e0
	main._process(0.016)
	check(skipped_ok and is_equal_approx(main.elapsed - e0, 0.016), "...and the next %d frames are skipped too, then play resumes at normal speed (no catching up)" % tuning.resume_skip_frames)
	# a long random run with stalls: the simulation never gets ahead of the frames that really passed
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	pk.enabled = false
	pk.next_pick = INF
	var raw_sum := 0.0
	var max_step := 0.0
	var prev_sim := 0.0
	for i in 400:
		var rd := randf_range(0.008, 0.03)
		if i % 57 == 0:
			rd = randf_range(0.3, 2.5)   # a stall
		elif i % 23 == 0:
			rd = randf_range(0.06, 0.2)   # a hitch
		raw_sum += rd
		main._process(rd)
		max_step = maxf(max_step, main.sim_time - prev_sim)
		prev_sim = main.sim_time
		main.score = 0.0
		if not main.alive:
			main.restart()
			main.set_process(false)
			sp.reset(-500.0)
			pk.enabled = false
			prev_sim = 0.0
	check(max_step <= tuning.max_frame_delta + 0.0001 and main.sim_time <= raw_sum, "400 frames with stalls and hitches: no frame advanced more than %.2f s, and the simulation (%.1f s) never exceeded the real time (%.1f s)" % [tuning.max_frame_delta, main.sim_time, raw_sum])
	# a pause (the pick screen) does not accumulate time, and resuming skips frames
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	pk.enabled = true
	pk.start_run(1.0)
	main.elapsed = 16.0
	main.score = 600.0
	main._process(0.02)
	check(main.get_tree().paused, "(a pick is up)")
	var wall0: float = main.run_wall_time()
	await real_wait(0.6)
	main.pick_screen._on_card(0)
	check(main._skip_frames == tuning.resume_skip_frames and main.run_wall_time() - wall0 < 0.25, "resuming from the pick: the pause is not counted as run time, and frames are skipped (nothing catches up)")
	pk.enabled = false
	pk.next_pick = INF
	var e1: float = main.elapsed
	main._process(0.016)
	check(main.elapsed == e1, "...the first frame after the pick does not move the world")
	# the window in the background
	main.restart()
	main.set_process(false)
	sp.reset(-500.0)
	pk.enabled = false
	pk.next_pick = INF
	main._notification(main.NOTIFICATION_APPLICATION_FOCUS_OUT)
	e1 = main.elapsed
	main._process(0.05)
	main._process(0.05)
	check(main._suspended and main.elapsed == e1, "with the window in the background the world stands still")
	main.player._pending_drag = Vector2(900.0, 900.0)
	main._notification(main.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not main._suspended and main._skip_frames == tuning.resume_skip_frames and main.player._pending_drag == Vector2.ZERO, "...and when it comes back frames are skipped and the finger drag that piled up is forgotten")
	main._skip_frames = 0
	# ?perf: frames over 50 ms are logged with what was happening
	DebugFlags.parse(["perf", "tune"])
	main.hud._hitch_log.clear()
	main.hud._hitch_count = 0
	main._note_event("pick resume")
	main.spawner.rows_spawned = 2
	main._process(0.3)
	check(main.hud._hitch_log.size() == 1 and main.hud._hitch_log[0].contains("300 ms") and main.hud._hitch_log[0].contains("simulated 0 ms") and main.hud._hitch_log[0].contains("stall dropped")
			and main.hud._hitch_log[0].contains("pick resume") and main.hud._hitch_log[0].contains("2 row(s) spawned"),
			"?perf logs a 300 ms frame and what was happening: \"%s\"" % (main.hud._hitch_log[0] if main.hud._hitch_log.size() > 0 else ""))
	main._skip_frames = 0
	main._process(0.08)
	check(main.hud._hitch_log.size() == 2 and main.hud._hitch_log[1].contains("80 ms") and main.hud._hitch_log[1].contains("simulated 50 ms") and main.hud._hitch_log[1].contains("clamped"), "...an 80 ms frame is logged as clamped to 50 ms")
	main._process(0.016)
	check(main.hud._hitch_log.size() == 2 and main.hud._clock_text.begins_with("sim ") and main.hud._clock_text.contains("wall"), "...a normal frame is not logged; the readout shows sim vs wall time (\"%s\")" % main.hud._clock_text)
	DebugFlags.parse(["tune"])

	print("3. debug flags")
	DebugFlags.parse(["nofx=sparks,bogus", "noprewarm", "perf", "v=abc1234"])
	check(DebugFlags.off("sparks") and not DebugFlags.off("streaks"), "nofx=sparks switches off only sparks")
	check(DebugFlags.noprewarm and DebugFlags.perf, "noprewarm and perf are read")
	check(DebugFlags.summary() == "nofx=sparks noprewarm perf ?bogus", "summary shown by the stamp: \"%s\"" % DebugFlags.summary())
	DebugFlags.parse(["nofx=all"])
	check(DebugFlags.EFFECTS.all(func(e): return DebugFlags.off(e)), "nofx=all switches every effect off")
	check(DebugFlags.summary() == "nofx=" + ",".join(DebugFlags.EFFECTS), "summary lists them all")
	DebugFlags.parse(["nofx=Sparks%2CPopup"])   # URL-encoded comma, upper case
	check(DebugFlags.off("sparks") and DebugFlags.off("popup") and not DebugFlags.off("flash"), "names are case-insensitive and URL-decoded")
	DebugFlags.parse(["nofx=sparks,streaks,popup,flash,trail,haptic"])
	main._reset_bonus()
	for e in main.fx._emitters:
		e.emitting = false
		e.visible = false
	var row = sp._rows_make_for_test(-5.0, [1.0])
	main._on_near_miss({"side": 1, "node": row.obs[0], "outline": row.outlines[0]})
	check(main.bonus >= 1.5, "bonus still rises with every effect off")
	check(count_visible(main.fx._emitters) == 0 and count_visible(main.fx._streak_nodes) == 0
			and count_visible(main.hud._pop_labels) == 0 and sp._flashes.is_empty(),
			"no spark / streak / popup / flash with ?nofx")
	DebugFlags.parse([])
	sp._release_row(row)

	print("3b. ?perf near-miss log")
	main.hud._perf_label = Label.new()
	main.hud.add_child(main.hud._perf_label)
	main.hud.note_near_miss(0.4)
	for i in 5:
		main.hud._update_perf(0.07 if i == 2 else 0.02)
	check(main.hud._nm_log.size() >= 1 and main.hud._nm_log[-1].contains("code 0.4 ms") and main.hud._nm_log[-1].contains("worst 70 ms"),
			"perf readout logs handler time and the worst following frame (%s)" % str(main.hud._nm_log[-1] if main.hud._nm_log.size() > 0 else ""))
	main.hud._perf_label.queue_free()
	main.hud._perf_label = null
	# the rolling frame-time graph
	var fg := FrameGraph.new()
	for i in 200:
		fg.push(16.0)
	fg.push(80.0)
	fg.push(16.0)
	check(fg.worst == 80.0 and fg._ms.size() == FrameGraph.N, "?perf graph: keeps the last %d frames and shows the worst (%.0f ms)" % [FrameGraph.N, fg.worst])
	for i in FrameGraph.N:
		fg.push(10.0)
	check(fg.worst == 10.0, "...and the spike scrolls out of it")
	fg.free()
	DebugFlags.parse(["perf", "tune"])
	var perf_hud: Node = load("res://scripts/Hud.gd").new()
	root.add_child(perf_hud)
	await process_frame
	check(perf_hud._graph != null, "?perf builds the graph in the HUD")
	perf_hud.graph_push(33.0)
	perf_hud.queue_free()
	DebugFlags.parse(["tune"])

	print("4. rounded wings: visible model and collision stay in sync")
	var k: float = tuning.plane_hit_scale
	var caps: PackedFloat32Array = pl.hit_capsules()
	var half: Vector2 = sp._obstacle_half()
	var wing_tip: float = pl.collision_half_span()
	check(absf(wing_tip - pl.WING_HALF.x * k) < 0.01, "collision wingspan matches the visible wings (%.3f half-span)" % wing_tip)
	var fo := caps.size() - 5
	check(absf(caps[fo + 3] + caps[fo + 4] - (pl.BODY_Z + pl.BODY_HALF.y * k)) < 0.001, "fuselage capsule reaches the visible tail")
	var wing_mesh: Mesh = pl._model.get_child(1).mesh
	var aabb := wing_mesh.get_aabb()
	check(absf(aabb.size.x - 2.0 * pl.WING_HALF.x) < 0.01 and absf(aabb.size.y - pl.WING_THICKNESS) < 0.001,
			"visible wing mesh is %.2f wide, %.2f thick" % [aabb.size.x, aabb.size.y])
	# every point of the visible outline (scaled by plane_hit_scale) lies inside the collision circles
	var outline: PackedVector2Array = pl.wing_outline(tuning.plane_tip_radius)
	var worst := 0.0
	for v in outline:
		var sv := Vector2(v.x * k, pl.WING_Z + (v.y - pl.WING_Z) * k)
		var best := INF
		for o in range(0, caps.size() - 5, 5):
			best = minf(best, Vector2(caps[o], caps[o + 1]).distance_to(sv) - caps[o + 4])
		worst = maxf(worst, best)
	check(worst < 0.03, "collision covers the visible wing outline (worst gap %.3f)" % worst)
	# the wing tapers: the chord at the tip is much narrower than at the root
	var root_r := 0.0
	var tip_r := INF
	for o in range(0, caps.size() - 5, 5):
		root_r = maxf(root_r, caps[o + 4])
		tip_r = minf(tip_r, caps[o + 4])
	check(root_r > 0.3 and tip_r < 0.25 and tip_r < root_r * 0.8, "collision tapers toward the tips (root %.2f, tip %.2f)" % [root_r, tip_r])
	var p0 := Vector2(0.0, 0.0)
	sp.reset()
	var test_row = sp._rows_make_for_test(0.0, [wing_tip + half.x + 0.05])
	check(not sp.hits(p0, caps), "wingtip 0.05 clear of a cube survives")
	test_row.xs[0] = wing_tip + half.x - 0.02
	check(sp.hits(p0, caps), "wingtip 0.02 inside a cube crashes")
	# corner graze: a cube corner 0.05 inside the old BOX corner of the wing, but outside the rounded tip
	var box_x: float = wing_tip
	var box_z: float = pl.WING_Z + pl.WING_HALF.y * k
	test_row.xs[0] = box_x - 0.05 + half.x
	test_row.position.z = box_z - 0.05 + half.y
	check(not sp.hits(p0, caps), "rounded wingtip survives a cube-corner graze that a box would have crashed on")
	# how much of the box's corner zone does the rounded tip give back?
	var saved := 0
	var total := 0
	for ix in 11:
		for iz in 11:
			var cx: float = box_x - 0.25 * ix / 10.0
			var cz: float = box_z - 0.25 * iz / 10.0
			test_row.xs[0] = cx + half.x
			test_row.position.z = cz + half.y
			total += 1
			if not sp.hits(p0, caps):
				saved += 1
	var pct := 100.0 * saved / total
	check(pct > 40.0, "a cube corner anywhere in the old box's 0.25 x 0.25 tip corner survives %.0f%% of the time (a box: 0%%)" % pct)
	sp.reset()

	print("5. near-miss closest approach")
	var near_row = sp._rows_make_for_test(-4.0, [wing_tip + half.x + 0.3])   # passes 0.3 clear on the right
	var found: Array[Dictionary] = []
	var z := -4.0
	while z < 6.0:
		near_row.position.z = z
		found.append_array(sp.update_near_misses(p0, caps))
		z += 0.1
	check(found.size() == 1 and found[0]["side"] == 1, "a pass 0.3 clear on the right gives one near miss on the right")
	sp.reset()
	var far_row = sp._rows_make_for_test(-4.0, [wing_tip + half.x + 1.5])    # 1.5 clear: not a near miss
	found.clear()
	z = -4.0
	while z < 6.0:
		far_row.position.z = z
		found.append_array(sp.update_near_misses(p0, caps))
		z += 0.1
	check(found.is_empty(), "a pass 1.5 clear is not a near miss")

	print("6. players (no ?tune) get no panel")
	DebugFlags.parse([])
	var plain: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(plain)
	await process_frame
	await process_frame
	check(plain.tune_panel == null, "without ?tune there is no tuning panel at all")
	plain.queue_free()

	print("7. Countryside kit: models, colliders, close calls, hay, nothing allocated")
	DebugFlags.parse([])
	var ksp = main.spawner
	ksp.kit_enabled = true
	ksp.apply_map(0)
	ksp.reset(-500.0)
	check(ksp.kit_on, "the Countryside uses the kit")
	var kit = ksp.kit
	var kcaps: PackedFloat32Array = main.player.hit_capsules()
	var kpz: float = main.player.position.z
	var kp := Vector2(0.0, kpz)
	kit.screen_top_z = -9.0
	kit.plane_x = 0.0
	kit.plane_z = kpz
	var k_carrier := Node3D.new()
	main.add_child(k_carrier)
	for kind in 9:   # every kind has a model made of several outlined parts, and its pool
		var k_ent = kit.spawn(kind, k_carrier, 0.0, 0.0, 1.6 if kind == 0 else 0.0)
		check(k_ent != null and k_ent.parts.size() >= 1 and k_ent.outline != null, "%s: a pooled model with an outline" % kit.NAMES[kind])
		if k_ent != null:
			kit.release(k_ent)
	var kpool_ok := true
	for kind in 9:
		kpool_ok = kpool_ok and kit._free[kind].size() == kit.POOL[kind]
	check(kpool_ok, "released things go back to their pools")
	# hit shapes: standing in the middle of each static kind is a crash, far to the side is not
	for kind in [0, 2, 4, 7, 8]:
		k_carrier.position.z = kpz
		var k_ent2 = kit.spawn(kind, k_carrier, 0.0, 0.0, 1.6 if kind == 0 else 0.0)
		kit.update(0.0)
		check(kit.hits(kp, kcaps), "%s: the plane over it crashes" % kit.NAMES[kind])
		check(not kit.hits(Vector2(6.0, kpz), kcaps), "%s: a plane well to the side is clear" % kit.NAMES[kind])
		kit.release(k_ent2)
	# the wire: touching the wire between the poles crashes, the gap beside a pole is open
	k_carrier.position.z = kpz
	kit.spawn(5, k_carrier, -5.0, 0.0, -1.5)
	kit.spawn(5, k_carrier, 1.5, 0.0, 5.0)
	kit.update(0.0)
	check(kit.hits(Vector2(-3.0, kpz), kcaps) and kit.hits(Vector2(3.0, kpz), kcaps), "power line: the wire crashes")
	check(not kit.hits(Vector2(0.0, kpz), kcaps), "power line: the gap between the poles is open")
	kit.release_all()
	# close calls against every kind, moving ones included: some offset passes without touching and still scores a near miss
	var sweep_kinds := {0: "barn", 1: "tractor", 9: "fly-through barn", 2: "windmill", 4: "balloon", 7: "kite", 3: "crow", 6: "duster", 5: "powerline", 8: "hay"}
	for kind in sweep_kinds:
		var k_got_event := false
		var k_d := 4.0
		while k_d > -2.5 and not k_got_event:
			var k_r := _kit_pass(kit, k_carrier, kind, k_d, kpz, kcaps)
			if k_r["hit"]:
				break
			k_got_event = k_r["event"]
			k_d -= 0.05
		if kind != 8:   # (hay is a crate: it has its own rules)
			check(k_got_event, "%s: a pass closer than the near-miss distance without touching gives a close call" % sweep_kinds[kind])
	# a k_crow flies straight once it has swooped: the plane moving away changes nothing
	kit.release_all()
	k_carrier.position.z = -8.0
	var k_crow = kit.spawn(3, k_carrier, 2.0, 0.0, 0.0, 0.0, 0.0)
	kit.plane_x = 0.0
	var k_t_crow := 0.0
	while k_crow.state != 2 and k_t_crow < 3.0:
		kit.update(1.0 / 60.0)
		k_t_crow += 1.0 / 60.0
	check(k_crow.state == 2 and k_t_crow >= tuning.crow_telegraph - 0.05, "a k_crow hovers at the top edge for the telegraph time (%.2f s) before swooping" % k_t_crow)
	var k_vx0: float = k_crow.vx
	var k_vz0: float = k_crow.vz
	kit.plane_x = 4.0
	for i in 20:
		kit.update(1.0 / 60.0)
	check(k_crow.vx == k_vx0 and k_crow.vz == k_vz0 and k_vz0 > 0.0, "once swooping a k_crow keeps its line (never homes)")
	kit.release_all()
	# a duster is announced by an arrow first
	k_carrier.position.z = -8.0
	var k_dust = kit.spawn(6, k_carrier, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0)
	kit.update(1.0 / 60.0)
	check(k_dust.arrow.visible and not k_dust.solid, "a crop duster shows an arrow at the edge first and is not solid yet")
	var k_t_d := 0.0
	while not k_dust.solid and k_t_d < 3.0:
		kit.update(1.0 / 60.0)
		k_t_d += 1.0 / 60.0
	check(k_dust.solid and k_t_d >= tuning.duster_telegraph - 0.05 and not k_dust.arrow.visible, "...then crosses after %.2f s" % k_t_d)
	kit.release_all()
	# k_hay bales: the front face breaks them, rewards come from the same colour kinds
	k_carrier.position.z = kpz - 0.3
	var k_hay = kit.spawn(8, k_carrier, 0.0, 0.0, 0.0, 2.0)
	kit.update(0.0)
	check(k_hay.crate_kind == 2 and kit.glow_mats.size() == 3, "a k_hay bale carries a colour-coded crate kind")
	var k_br: Array[Dictionary] = kit.break_hay(kp, kcaps, false, true, kpz)
	check(k_br.size() == 1 and k_br[0]["kind"] == 2 and not k_hay.solid, "hay: the front face breaks it and pays out its kind")
	kit.release_all()
	k_carrier.position.z = kpz + 0.2
	var k_hay2 = kit.spawn(8, k_carrier, 0.0, 0.0, 0.0, 1.0)
	kit.update(0.0)
	var k_br2: Array[Dictionary] = kit.break_hay(kp, kcaps, false, true, kpz)
	check(k_br2.is_empty() and kit.hits(kp, kcaps) and kit.last_hit_hay, "hay: hitting it from the side crashes (a crate crash)")
	kit.release_all()
	# the fly-through barn: walls crash, the doorway is clear, flying straight through is a Barnstormer
	kit.release_all()
	k_carrier.position.z = kpz
	var k_barn = kit.spawn(0, k_carrier, 0.0, 0.0, 1.0, 1.0)
	kit.update(0.0)
	check(kit.hits(Vector2(-2.2, kpz), kcaps) and kit.hits(Vector2(2.2, kpz), kcaps), "a fly-through barn: its walls crash the plane")
	check(not kit.hits(Vector2(0.0, kpz), kcaps), "...and the doorway between them (%.1f wide) is clear" % tuning.barn_door_width)
	check(kit.col_count == 2, "...two wall shapes, no roof over the doorway")
	var k_ev: Array[Dictionary] = []
	var k_behind := 0.0
	for o in range(0, kcaps.size(), 5):
		k_behind = maxf(k_behind, maxf(kcaps[o + 1], kcaps[o + 3]) + kcaps[o + 4])
	k_carrier.position.z = kpz - 5.0
	while k_carrier.position.z < kpz + 6.0:
		k_carrier.position.z += 0.2
		kit.update(0.0)
		kit.update_near_misses(Vector2(0.0, kpz), kcaps, tuning.near_miss_distance, k_behind, k_ev, tuning.whisker_close_distance)
	check(k_ev.size() == 1 and k_ev[0].get("special", "") == "barnstormer" and k_ev[0]["whisker"], "flying straight through gives one Barnstormer (a Whisker close)")
	kit.release_all()
	k_ev.clear()
	var k_barn2 = kit.spawn(0, k_carrier, 3.6, 0.0, 1.0, 1.0)   # flying past the outside is only an ordinary close call or nothing
	k_carrier.position.z = kpz - 5.0
	while k_carrier.position.z < kpz + 6.0:
		k_carrier.position.z += 0.2
		kit.update(0.0)
		kit.update_near_misses(Vector2(0.0, kpz), kcaps, tuning.near_miss_distance, k_behind, k_ev, tuning.whisker_close_distance)
	check(k_ev.is_empty() or k_ev[0].get("special", "") != "barnstormer", "going around a barn is not a Barnstormer")
	kit.release_all()
	# windmill variants: standard 4 blades, large 3, small 2 (fast); the colliders follow the blades
	var blade_counts := []
	for k_v in 3:
		kit.release_all()
		k_carrier.position.z = kpz - 6.0
		var k_wm = kit.spawn(2, k_carrier, 0.0, 0.0, float(k_v), 0.0, 0.0, 0.0, 0.0, 1.0)
		kit.update(0.0)
		blade_counts.append(kit.col_count - 1)
		var longest := 0.0
		for ci in kit.col_count:
			longest = maxf(longest, kit.col[ci * kit.STRIDE + 3])
		check(absf(longest - maxf(tuning.windmill_blade[k_v] * 0.5, tuning.windmill_hub[k_v])) < 0.001, "windmill variant %d: blade shapes are the blade length (%.1f)" % [k_v, tuning.windmill_blade[k_v]])
	check(blade_counts == [4, 3, 2], "windmills: standard 4 blades, large 3, small 2 (%s)" % str(blade_counts))
	check(tuning.windmill_blade[0] >= 3.0 and tuning.windmill_blade[1] > tuning.windmill_blade[0] - 0.01 and tuning.windmill_speed[2] > tuning.windmill_speed[0] * 2.0, "the blades span most of the lane; the small one is much faster")
	# the blades show their `phase` when the windmill reaches the plane's row (the start angle is set once, at spawn)
	var angle_err := 0.0
	for k_spd in [7.0, 13.0, 26.0]:
		kit.release_all()
		kit.scroll_speed = k_spd
		kit.plane_z = kpz
		k_carrier.position.z = kpz - 30.0
		var k_wm2 = kit.spawn(2, k_carrier, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.1, 1.0)
		while k_carrier.position.z < kpz:
			k_carrier.position.z += k_spd / 60.0
			kit.update(1.0 / 60.0)
		angle_err = maxf(angle_err, absf(wrapf(k_wm2.ang - 1.1, -PI, PI)))
	check(angle_err < 0.06, "windmill blades are at their pattern phase when they reach the plane, at every speed (error %.3f rad)" % angle_err)
	# ...and moving the plane never changes how fast they turn: a constant angular speed on the simulation clock
	kit.release_all()
	kit.scroll_speed = 10.0
	k_carrier.position.z = kpz - 20.0
	var k_wm3 = kit.spawn(2, k_carrier, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.3, 1.0)   # the large windmill
	var k_prev: float = k_wm3.ang
	var k_steady := true
	var k_rate_seen := 0.0
	for i in 120:
		kit.plane_x = 4.0 * sin(i * 0.9)   # the plane swings from side to side and up and down, hard
		kit.plane_z = kpz + 3.0 * sin(i * 1.7)
		k_carrier.position.z += 10.0 / 60.0
		kit.update(1.0 / 60.0)
		var k_rate: float = (k_wm3.ang - k_prev) * 60.0
		k_rate_seen = k_rate
		k_steady = k_steady and absf(k_rate - tuning.windmill_speed[1]) < 0.0001
		k_prev = k_wm3.ang
	check(k_steady, "swinging the plane about never changes the blades' angular speed (%.3f rad/s, set %.3f)" % [k_rate_seen, tuning.windmill_speed[1]])
	kit.plane_x = 0.0
	kit.plane_z = kpz
	kit.scroll_speed = 7.0
	kit.release_all()
	kit.scroll_speed = 7.0
	kit.release_all()
	# the tractor: dust plume first, then it drives across (solid), dropping hay bales behind it
	k_carrier.position.z = -10.0
	var k_tractor = kit.spawn(1, k_carrier, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0)
	kit.update(1.0 / 60.0)
	check(k_tractor.state == 1 and k_tractor.arrow.visible and not k_tractor.solid, "a tractor first shows a dust plume at the edge (not solid yet)")
	var t_tr := 0.0
	while k_tractor.state < 2 and t_tr < 3.0:
		kit.update(1.0 / 60.0)
		t_tr += 1.0 / 60.0
	check(k_tractor.state == 2 and k_tractor.solid and not k_tractor.arrow.visible and t_tr >= tuning.tractor_telegraph - 0.05, "...then drives in after %.1f s" % t_tr)
	var x_a: float = k_tractor.px
	for i in 60:
		kit.update(1.0 / 60.0)
	check(absf((k_tractor.px - x_a) - tuning.tractor_speed) < 0.05, "it crosses slowly: %.1f units/second" % tuning.tractor_speed)
	var hay_n := 0
	for i in 240:
		kit.update(1.0 / 60.0)
	for e2 in kit.active:
		hay_n += int(e2.kind == 8)
	check(hay_n >= 2 and hay_n <= tuning.tractor_drops, "it drops hay bales behind it (%d so far)" % hay_n)
	check(kit.dropped == 0, "...and the pools had room")
	kit.release_all()
	# the crop duster's warning: the edge glows and pulses, a red line marks its row, and it stays until the duster enters
	kit.scroll_speed = 8.0
	kit.plane_z = kpz
	k_carrier.position.z = kpz - 30.0
	var k_dwarn = kit.spawn(6, k_carrier, 0.0, 0.0, 0.7, 0.0, 0.0, 0.0, 0.0, 1.0)
	var warned_at := -1.0
	var entered_at := -1.0
	var glow_pulses: Array[float] = []
	var line_ok := true
	var t_d2 := 0.0
	while t_d2 < 8.0 and entered_at < 0.0:
		k_carrier.position.z += 8.0 / 60.0
		kit.update(1.0 / 60.0)
		t_d2 += 1.0 / 60.0
		if k_dwarn.state == 1:
			if warned_at < 0.0:
				warned_at = t_d2
			glow_pulses.append(kit.warn_mat.albedo_color.a)
			var edge_node: Node3D = k_dwarn.arrow.get_node("edge")
			var line_node: Node3D = k_dwarn.arrow.get_node("line")
			line_ok = line_ok and k_dwarn.arrow.visible and edge_node.position.x < -3.0 and absf(line_node.position.z - k_dwarn.pz) < 0.001
		if k_dwarn.state == 2 and entered_at < 0.0:
			entered_at = t_d2
	var pmin := 1.0
	var pmax := 0.0
	for pa in glow_pulses:
		pmin = minf(pmin, pa)
		pmax = maxf(pmax, pa)
	check(warned_at > 0.0 and entered_at - warned_at >= tuning.duster_telegraph - 0.03, "the duster's warning runs %.2f s before it enters (set %.1f s)" % [entered_at - warned_at, tuning.duster_telegraph])
	check(line_ok and pmax - pmin > 0.2 and not k_dwarn.arrow.visible, "the edge glow pulses (%.2f..%.2f), the red row line follows the row, and both stay until it enters" % [pmin, pmax])
	kit.release_all()
	kit.scroll_speed = 7.0
	# a long kit run allocates nothing
	ksp.reset(-14.0)
	main.set_process(false)
	var k_base_kit := snapshot(main)
	for i in 900:
		ksp.advance(0.25)
		ksp.update_hazards(1.0 / 30.0)
		var k_rr = ksp.update_near_misses(kp, kcaps)
		ksp.hits(kp, kcaps)
		if i % 7 == 0:
			ksp.break_crates(kp, kcaps, false, true, kpz)
	var k_after_kit := snapshot(main)
	check(same_world(k_base_kit, k_after_kit), "900 steps of a random Countryside run created nothing new  [%s]" % describe(k_after_kit))
	ksp.reset()
	ksp.kit_enabled = false
	k_carrier.queue_free()

	print("8. Countryside patterns: data, mirroring, flyable at their speeds, chaining")
	var P = load("res://scripts/Patterns.gd")
	var pz_pats: Array = P.all()
	var pz_names_seen := {}
	var pz_data_ok := true
	var kinds_ok := ["barn", "tractor", "windmill", "balloon", "kite", "powerline", "crow", "duster"]
	for vpt in pz_pats:
		pz_data_ok = pz_data_ok and not pz_names_seen.has(vpt["name"]) and int(vpt["diff"]) >= 1 and int(vpt["diff"]) <= 5 and int(vpt["rows"]) >= 2 and int(vpt["rows"]) <= 6
		pz_data_ok = pz_data_ok and float(vpt["speed"][0]) < float(vpt["speed"][1]) and (vpt["tags"] as Array).size() >= 1
		pz_names_seen[vpt["name"]] = true
		for it in vpt["items"]:
			pz_data_ok = pz_data_ok and kinds_ok.has(it["t"]) and int(it["r"]) >= 0 and int(it["r"]) < int(vpt["rows"])
		for slot in (vpt.get("cans", []) as Array) + (vpt.get("hay", []) as Array):
			pz_data_ok = pz_data_ok and int(slot["r"]) >= 0 and int(slot["r"]) < int(vpt["rows"]) and absf(float(slot["x"])) <= 4.5
	check(pz_data_ok, "every pattern has a unique name, difficulty 1-5, 2-6 rows, speeds, tags, valid items and slots")
	check(pz_pats.size() >= 25, "at least 25 patterns (%d)" % pz_pats.size())
	var pz_wanted := ["slalom", "windmill", "crow", "balloon", "powerline", "duster", "funnel", "barn_maze", "bait", "combo"]
	var pz_missing: Array[String] = []
	for w in pz_wanted:
		var found_tag := false
		for vpt in pz_pats:
			found_tag = found_tag or P.has_tag(vpt, w)
		if not found_tag:
			pz_missing.append(w)
	check(pz_missing.is_empty(), "the required kinds of pattern are all there (missing: %s)" % str(pz_missing))
	var pz_diffs := {}
	for vpt in pz_pats:
		pz_diffs[int(vpt["diff"])] = true
	check(pz_diffs.size() == 5, "all five difficulty levels are used")
	# mirroring
	var pz_mir_ok := true
	for vpt in pz_pats:
		for it in vpt["items"]:
			var m1: Dictionary = P.mirror_item(it)
			var m2: Dictionary = P.mirror_item(m1)
			pz_mir_ok = pz_mir_ok and str(m2) == str(it)
			if it.has("x"):
				pz_mir_ok = pz_mir_ok and absf(float(m1["x"]) + float(it["x"])) < 0.0001
	check(pz_mir_ok, "mirroring twice gives the pattern back; x is negated")
	# the checker itself: an empty sky is flyable, a solid wall is not
	var wall_pat := {"name": "wall", "diff": 5, "rows": 2, "tags": [], "speed": [7.0, 8.0], "items": [{"t": "powerline", "r": 0, "gaps": []}, {"t": "barn", "r": 0, "x": -3.2, "hx": 1.6}, {"t": "barn", "r": 0, "x": 0.0, "hx": 1.6}, {"t": "barn", "r": 0, "x": 3.2, "hx": 1.6}], "cans": [], "hay": []}
	var vcarriers: Array = []
	for i in 8:
		var vn := Node3D.new()
		main.add_child(vn)
		vcarriers.append(vn)
	var vcaps: PackedFloat32Array = P.simple_caps(main.player.hit_capsules())
	var vlim: float = tuning.ortho_size * 0.5 - tuning.plane_edge_margin
	var vkit = main.spawner.kit
	check(not P.check(vkit, wall_pat, false, 10.0, 7.6, -9.1, vcaps, vlim, vcarriers)["ok"], "the checker rejects a wall across the whole lane")
	check(P.check(vkit, P.find("open_sky"), false, 10.0, 7.6, -9.1, vcaps, vlim, vcarriers)["ok"], "...and accepts an empty sky")
	# FAIRNESS: every pattern can be flown at the speeds it is built for (mirrored too, on a short and a tall screen, plane high and low)
	var t_pat := Time.get_ticks_msec()
	var pz_unflyable: Array[String] = []
	for vpt in pz_pats:
		var lo2: float = vpt["speed"][0]
		var hi2: float = vpt["speed"][1]
		var pz_speeds2: Array[float] = [lo2, lo2 + (hi2 - lo2) * 0.25, (lo2 + hi2) * 0.5, lo2 + (hi2 - lo2) * 0.75, hi2]
		for mir2 in [false, true]:
			for sp2 in pz_speeds2:
				for cfg2 in [[-9.1, 7.6], [-10.4, 8.9], [-9.1, 2.0], [-10.4, 2.4]]:
					var vres: Dictionary = P.check(vkit, vpt, mir2, sp2, cfg2[1], cfg2[0], vcaps, vlim, vcarriers)
					if not vres["ok"]:
						pz_unflyable.append("%s (%s, v=%.1f, plane z %.1f): %s" % [vpt["name"], "mirrored" if mir2 else "plain", sp2, cfg2[1], vres["why"]])
	check(pz_unflyable.is_empty(), "FAIRNESS: all %d patterns can be flown at every speed they are built for, mirrored or not (%d s)  %s" % [pz_pats.size(), (Time.get_ticks_msec() - t_pat) / 1000, str(pz_unflyable.slice(0, 3))])
	for vn in vcarriers:
		vn.queue_free()
	# chaining: rows of one pattern come in order, then another pattern; ?pattern= repeats one; nothing runs dry
	var pz_gsp = main.spawner
	DebugFlags.parse([])
	pz_gsp.kit_enabled = true
	pz_gsp.apply_map(0)
	pz_gsp.reset(-14.0)
	pz_gsp.run_time = 60.0
	pz_gsp.scroll_speed = 10.0
	pz_gsp.kit.dropped = 0
	var pz_seen_names := {}
	var pz_chain_ok := true
	var pz_last_name := ""
	for i in 300:
		pz_gsp._spawn_row(-30.0)
		pz_seen_names[pz_gsp.pattern_name] = true
		var rr2 = pz_gsp._rows[-1]
		pz_gsp._release_row(rr2)
		pz_gsp.kit.update(0.0)
		if i % 6 == 0:
			pz_gsp.kit.release_all()
	check(pz_seen_names.size() >= 8 and pz_gsp.kit.dropped == 0, "300 rows chain %d different patterns and the kit pools never ran dry (%d dropped)" % [pz_seen_names.size(), pz_gsp.kit.dropped])
	DebugFlags.parse(["pattern=funnel"])
	check(DebugFlags.pattern == "funnel" and DebugFlags.summary().contains("pattern=funnel"), "?pattern=<name> is read and shown in the summary")
	pz_gsp.reset(-14.0)
	var pz_only_funnel := true
	for i in 40:
		pz_gsp._spawn_row(-30.0)
		pz_only_funnel = pz_only_funnel and pz_gsp.pattern_name == "funnel"
		pz_gsp._release_row(pz_gsp._rows[-1])
		pz_gsp.kit.release_all()
	check(pz_only_funnel, "with ?pattern=funnel the Countryside plays only that pattern")
	DebugFlags.parse([])
	# intensity waves: CALM -> BUILD -> PEAK -> BREATHER, repeating, lengths from Tuning
	pz_gsp.reset(-14.0)
	pz_gsp.scroll_speed = 10.0
	var wv_seq: Array[int] = []
	var wv_starts: Array[float] = []
	var wv_last := -1
	var t_w := 0.0
	while t_w < 130.0:
		pz_gsp.run_time = t_w
		pz_gsp._pat = {}
		pz_gsp._choose_pattern()
		if pz_gsp.wave_phase != wv_last:
			wv_seq.append(pz_gsp.wave_phase)
			wv_starts.append(t_w)
			wv_last = pz_gsp.wave_phase
		t_w += 0.5
	var wv_order := wv_seq.size() >= 8
	for i in wv_seq.size():
		wv_order = wv_order and wv_seq[i] == i % 4
	check(wv_order, "the waves run CALM, BUILD, PEAK, BREATHER, CALM ... (%s)" % str(wv_seq))
	var wv_len_ok := true
	for i in range(1, mini(wv_starts.size(), 6)):
		wv_len_ok = wv_len_ok and absf((wv_starts[i] - wv_starts[i - 1]) - tuning.wave_seconds[wv_seq[i - 1]]) < 0.51
	check(wv_len_ok, "...each phase lasts its wave_seconds %s" % str(tuning.wave_seconds))
	var wv_mean := {}
	for cyc in [0, 4]:
		for ph in 4:
			pz_gsp.wave_cycle = cyc
			pz_gsp.wave_phase = ph
			pz_gsp.run_time = 100.0   # (past the gentle first minute)
			pz_gsp._wave_start = 100.0
			var tot := 0.0
			var calm_n := 0
			for i in 300:
				pz_gsp._pat = {}
				pz_gsp._pat_last = ""
				var chosen: Dictionary = pz_gsp._choose_pattern()
				tot += float(chosen["diff"])
				calm_n += int(P.has_tag(chosen, "calm"))
			wv_mean[cyc * 10 + ph] = tot / 300.0
			if ph == 3 and cyc == 0:
				check(calm_n > 150, "the BREATHER is nearly empty (%d of 300 picks are calm patterns)" % calm_n)
	check(wv_mean[0] < wv_mean[1] and wv_mean[1] < wv_mean[2] and wv_mean[3] < wv_mean[1], "difficulty climbs CALM < BUILD < PEAK, and the BREATHER is easy (%.1f %.1f %.1f %.1f)" % [wv_mean[0], wv_mean[1], wv_mean[2], wv_mean[3]])
	check(wv_mean[41] > wv_mean[1] + 0.3 and wv_mean[42] > wv_mean[2] + 0.2 and wv_mean[40] > wv_mean[0], "every phase gets harder over the run (BUILD %.1f -> %.1f, PEAK %.1f -> %.1f)" % [wv_mean[1], wv_mean[41], wv_mean[2], wv_mean[42]])
	pz_gsp.reset(-14.0)
	check(pz_gsp.wave_can_mult == tuning.wave_can[0] and tuning.wave_can[0] > tuning.wave_can[2] and tuning.wave_can[3] > tuning.wave_can[1], "CALM and the BREATHER give more cans / hay, the PEAK fewer")
	# ?tune: the wave button and the status line
	pz_gsp.run_time = 3.0
	pz_gsp.cycle_wave()
	check(pz_gsp.wave_phase == 1 and pz_gsp._pat.is_empty(), "the ?tune button jumps to the next phase and drops the current pattern")
	for i in 3:
		pz_gsp.cycle_wave()
	check(pz_gsp.wave_phase == 0 and pz_gsp.wave_cycle == 1, "...four presses make a full cycle")
	pz_gsp.apply_map(0)
	pz_gsp._pat = {}
	pz_gsp._spawn_row(-30.0)
	main.tune_panel.set_available(true)
	main.tune_panel._process(0.0)
	check(main.tune_panel._status.text == "%s | %s" % [pz_gsp.pattern_name, pz_gsp.wave_name()] and pz_gsp.pattern_name != "", "the ?tune status shows the pattern and the wave phase: \"%s\"" % main.tune_panel._status.text)
	pz_gsp._release_row(pz_gsp._rows[-1])
	pz_gsp.kit.release_all()
	# speed only steps up while a BREATHER passes, toward the top speed in about 4-5 minutes
	pz_gsp.reset(-14.0)
	pz_gsp.plane_z = 7.6
	var st_t := 0.0
	var st_speed: float = tuning.base_speed
	var st_top_t := -1.0
	var st_band_ok := true
	var st_last_pat := ""
	var st_mid_wave := 0
	var st_prev_steps := 0
	while st_t < 330.0:
		pz_gsp.run_time = st_t
		pz_gsp.scroll_speed = st_speed
		pz_gsp.advance(st_speed * 0.05)
		if pz_gsp.speed_steps != st_prev_steps:
			st_prev_steps = pz_gsp.speed_steps
			var near_breather := false
			for rr in pz_gsp._rows:
				near_breather = near_breather or rr.breather
			st_mid_wave += int(not near_breather)
		st_speed = pz_gsp.stepped_speed(pz_gsp.speed_steps)
		if pz_gsp.pattern_name != st_last_pat:
			st_last_pat = pz_gsp.pattern_name
			var sp_pat: Dictionary = P.find(st_last_pat)
			var planned: float = maxf(st_speed, pz_gsp.stepped_speed(pz_gsp.speed_steps_planned))
			st_band_ok = st_band_ok and planned >= float(sp_pat["speed"][0]) - 0.01 and planned <= float(sp_pat["speed"][1])
		if st_top_t < 0.0 and st_speed >= tuning.max_speed - 0.001:
			st_top_t = st_t
		st_t += 0.05
	check(st_top_t > 230.0 and st_top_t < 300.0, "speed reaches the top in steps after %.0f s (about 4-5 minutes)" % st_top_t)
	check(pz_gsp.speed_steps >= 6 and st_mid_wave == 0, "one step per wave cycle, each applied while a BREATHER row is on screen (%d steps, %d mid-wave)" % [pz_gsp.speed_steps, st_mid_wave])
	check(st_band_ok, "every chosen pattern is inside its speed band at the speed step it will be flown at")
	pz_gsp.reset()
	pz_gsp.kit_enabled = false

	print("9. speed changes are always explained on screen")
	var sc_main = main
	var sc_tun = tuning
	# the audit: only the listed sources may change the speed; any other effect that mentions speed must be added to the cues
	var sc_bad: Array[String] = []
	var sc_all: Array = []
	sc_all.append_array(sc_tun.perks)
	sc_all.append_array(sc_tun.boosts)
	sc_all.append_array(sc_tun.supplies)
	sc_all.append_array(sc_tun.combos)
	sc_all.append_array(sc_tun.upgrades)
	for d9 in sc_all:
		var txt9: String = (String(d9.get("line", "")) + " " + String(d9.get("name", ""))).to_lower()
		if txt9.contains("speed") and not sc_tun.speed_cue_sources.has(d9["id"]):
			sc_bad.append(d9["id"])
	check(sc_bad.is_empty(), "no effect changes speed without an on-screen cue (uncued: %s)" % str(sc_bad))
	check(sc_tun.speed_cue_sources.has("tailwind") and sc_tun.speed_cue_sources.has("breather_step") and sc_tun.speed_cue_sources.has("map_ramp") and sc_tun.speed_cue_sources.has("map_multiplier"), "cued sources: Tailwind, BREATHER steps, map ramp, map multiplier")
	# Tailwind's card
	check(sc_tun.pick_short["tailwind"] == "Fly faster, earn more", "the Tailwind card says \"Fly faster, earn more\"")
	var tw_card := {"kind": "perk", "id": "tailwind", "name": "Tailwind", "glyph": "T", "color": Color.WHITE, "line": "", "level": 1, "owned": false}
	sc_main.last_cue = ""
	sc_main._apply_card(tw_card)
	check(sc_main.last_cue == "Tailwind! +10% speed", "picking Tailwind shows \"%s\"" % sc_main.last_cue)
	tw_card["level"] = 2
	sc_main._apply_card(tw_card)
	check(sc_main.last_cue == "Tailwind! +20% speed", "levelling it shows \"%s\"" % sc_main.last_cue)
	# while it is held the wind flows past the plane; without it there is none
	var sc_fx = sc_main.fx
	for i in 5:
		sc_fx.wind_update(0.05, sc_main.player.position, true)
	var wind_vis := 0
	for wn in sc_fx._wind_nodes:
		wind_vis += int(wn.visible)
	check(wind_vis == sc_tun.wind_streaks, "wind streaks flow past the plane while Tailwind is held (%d)" % wind_vis)
	var wind_moves := true
	var wz0: float = sc_fx._wind_nodes[0].position.z
	sc_fx.wind_update(0.05, sc_main.player.position, true)
	wind_moves = sc_fx._wind_nodes[0].position.z > wz0 or not sc_fx._wind_nodes[0].visible
	check(wind_moves, "...flowing down the screen, past the plane")
	for i in 3:
		sc_fx.wind_update(0.05, sc_main.player.position, false)
	wind_vis = 0
	for wn in sc_fx._wind_nodes:
		wind_vis += int(wn.visible)
	check(wind_vis == 0, "...and gone without it")
	# the HUD icon pulses when Tailwind applies
	sc_main.picks.set_perk("tailwind", 1)
	sc_main.hud.set_perks(sc_main.picks.levels)
	var pulse_i: int = sc_main.hud._perk_ids.find("tailwind")
	sc_main.hud.pulse_perk("tailwind")
	sc_main.hud._perk_pulse_ms[pulse_i] -= 150   # (a moment into the pulse)
	sc_main.hud._process(0.016)
	var pulse_scale: float = (sc_main.hud._perk_icons[pulse_i]["panel"] as Panel).scale.x
	check(pulse_i >= 0 and pulse_scale > 1.05, "the Tailwind icon pulses when it applies (scale %.2f)" % pulse_scale)
	sc_main.picks.set_perk("tailwind", 0)
	sc_main.hud.set_perks(sc_main.picks.levels)
	# a Countryside speed step: banner, whoosh (every streak), haptic path
	var sp9 = sc_main.spawner
	sp9.kit_enabled = true
	sp9.apply_map(0)
	sc_main.last_cue = ""
	sc_main._seen_steps = 0
	sp9.speed_steps = 1
	sc_main._speed_cues(7.0, 0.016)
	check(sc_main.last_cue == "SPEED UP", "a BREATHER speed step shows the SPEED UP banner")
	sc_fx.wind_update(0.016, sc_main.player.position, false)
	wind_vis = 0
	for wn in sc_fx._wind_nodes:
		wind_vis += int(wn.visible)
	check(wind_vis == sc_fx.WIND_POOL, "...with a whoosh of wind streaks (%d)" % wind_vis)
	sc_main.last_cue = ""
	sc_main._speed_cues(7.0, 0.016)
	check(sc_main.last_cue == "", "...once per step")
	sc_fx.stop_wind()
	sp9.speed_steps = 0
	sp9.kit_enabled = false
	sp9.apply_map(0)
	# the other maps: the ramp is announced in tiers, a faster map when the run starts
	sc_main.map = 1
	sp9.apply_map(1)
	sc_main.last_cue = ""
	sc_main._ramp_tier = 0
	sc_main._speed_cues(sc_tun.base_speed * 1.1 + sc_tun.speed_step + 0.1, 0.016)
	check(sc_main.last_cue == "SPEED UP", "on the other maps each tier of the ramp shows SPEED UP too")
	sc_fx.stop_wind()
	sc_main.map = 0
	sp9.apply_map(0)
	sc_main.last_cue = ""
	var wind_sig := snapshot(sc_main)
	for i in 300:
		sc_fx.wind_update(0.016, sc_main.player.position, true)
		if i % 50 == 0:
			sc_fx.whoosh()
	sc_fx.stop_wind()
	check(same_world(wind_sig, snapshot(sc_main)), "wind, whooshes and pulses created nothing new  [%s]" % describe(snapshot(sc_main)))

	print("10. hitches: pre-warm covers every new thing, work is spread over frames, motion never catches up")
	var hk = main.spawner.kit
	main.spawner.kit_enabled = true
	main.spawner.apply_map(0)
	hk.prewarm_show()
	var hk_total := 0
	var hk_ok := true
	var hk_kinds := {}
	var hk_barns := {}
	var hk_wm := {}
	var hk_glow := {}
	for h_e in hk._all:
		hk_total += 1
		hk_ok = hk_ok and h_e.in_use and h_e.visible and absf(h_e.position.x) <= 4.6 and h_e.position.z >= -7.5 and h_e.position.z <= 6.5
		hk_kinds[h_e.kind] = true
		if h_e.kind == 0:
			hk_barns["open" if h_e.b > 0.5 else "closed"] = true
			hk_barns[str(h_e.a)] = true
		if h_e.kind == 2:
			hk_wm[int(h_e.a)] = true
		if h_e.kind == 8:
			hk_glow[h_e.crate_kind] = true
	check(hk_total == 75 and hk_ok, "pre-warm: all %d pooled kit things are in use, visible and inside the view" % hk_total)
	check(hk_kinds.size() == 9 and hk_barns.has("open") and hk_barns.has("closed") and hk_barns.size() >= 7, "...every kind, closed and fly-through barns in every size (%d)" % hk_barns.size())
	check(hk_wm.size() == 3 and hk_glow.size() == 3, "...all three windmills and every hay colour")
	var hk_warn := false
	var hk_plume := false
	for h_e in hk._all:
		hk_warn = hk_warn or (h_e.kind == 6 and h_e.arrow.visible and h_e.edge_node.visible and h_e.line_node.visible)
		hk_plume = hk_plume or (h_e.kind == 1 and h_e.arrow.visible)
	check(hk_warn and hk_plume, "...the duster's edge warning and the tractor's dust plume")
	hk.release_all()
	check(not hk._all.any(func(h_e): return h_e.in_use or h_e.visible) , "...and the pre-warm puts everything back")
	# Patterns: mirrored copies and can slots are cached, not rebuilt for every row
	var hp = load("res://scripts/Patterns.gd")
	hp.warm()
	check(hp._cache.size() >= hp.all().size(), "every pattern's mirrored copy and can slots are built at start-up (%d)" % hp._cache.size())
	check(hp.can_slots(hp.all()[0], 0, true) == hp.can_slots(hp.all()[0], 0, true) and is_same(hp.can_slots(hp.all()[0], 0, false), hp.can_slots(hp.all()[0], 0, false)), "...can slots come out of the cache (the same array each time)")
	# spreading: after a slow frame (a big advance) only MAX_ROWS_PER_FRAME rows are h_built, the rest on the following frames
	var hs = main.spawner
	hs.reset(-14.0)
	hs.plane_z = 7.6
	hs.advance(0.0)
	var h_built: int = hs.rows_spawned
	hs.advance(40.0)
	check(hs.rows_spawned <= hs.MAX_ROWS_PER_FRAME, "a big step builds at most %d row(s) in one frame (%d)" % [hs.MAX_ROWS_PER_FRAME, hs.rows_spawned])
	var h_catch_frames := 0
	while hs.rows_spawned > 0 and h_catch_frames < 30:
		hs.advance(0.01)
		h_catch_frames += 1
	check(h_catch_frames >= 2 and h_catch_frames < 30, "...the rows that were due follow on the next frames (%d more)" % h_catch_frames)
	# the next pattern is chosen a frame before it is needed, not in the same frame as its first row
	hs.reset(-14.0)
	hs.run_time = 5.0
	hs.scroll_speed = 8.0
	var h_split_ok := false
	for i in 40:
		hs._spawn_row(-30.0)
		hs._release_row(hs._rows[-1])
		hs.kit.release_all()
		if hs._pat_row >= int(hs._pat["rows"]):   # that was the last row of the pattern
			var h_had_next: bool = not hs._pat_next.is_empty()
			hs.update_hazards(0.016)
			h_split_ok = not h_had_next and not hs._pat_next.is_empty()
			break
	check(h_split_ok, "the next pattern is chosen in the frame after a pattern's last row, not with the first row of the new one")
	hs.reset()
	# windmill patterns are never chosen while a speed step is under way (their blade timing must not span one)
	hs.kit_enabled = true
	hs.apply_map(0)
	hs.run_time = 100.0
	var wm_picked := 0
	var wm_picked_calm := 0
	hs.base_speed_now = 7.0
	hs.scroll_speed = 7.0
	for i in 400:
		hs.wave_phase = 1
		hs._pat_last = ""
		hs.speed_steps_planned = 1
		hs.speed_steps = 0   # a step is spawned but not applied yet
		wm_picked += int(P.has_tag(hs._choose_pattern(), "windmill"))
		hs.speed_steps_planned = 0
		hs.speed_steps = 0
		hs.wave_phase = 1
		hs._pat_last = ""
		wm_picked_calm += int(P.has_tag(hs._choose_pattern(), "windmill"))
	check(wm_picked == 0 and wm_picked_calm > 20, "no windmill pattern is chosen while a speed step is pending or under way (%d), and they are chosen otherwise (%d of 400)" % [wm_picked, wm_picked_calm])
	hs.base_speed_now = -1.0
	hs.reset()
	# nothing is driven by the wall clock: motion advances by the frame's own delta, so a slow frame is never caught up
	var clk0: float = hs.hazards._clock
	hs.hazards.update(0.016)
	hs.hazards.update(0.05)
	check(absf(hs.hazards._clock - clk0 - 0.066) < 0.0001, "wind stripes run on the simulation clock (%.3f s for 0.066 s of frames)" % (hs.hazards._clock - clk0))
	var hcar := Node3D.new()
	main.add_child(hcar)
	hk.scroll_speed = 8.0
	hk.plane_z = 6.0
	hcar.position.z = -2.0
	var h_tr = hk.spawn(1, hcar, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0)
	h_tr.state = 2
	h_tr.solid = true
	hk.update(0.016)
	var h_x0: float = h_tr.px
	hk.update(0.05)
	check(absf((h_tr.px - h_x0) - tuning.tractor_speed * 0.05) < 0.001, "a tractor moves by exactly speed x the frame's delta (%.3f)" % (h_tr.px - h_x0))
	hk.release_all()
	var h_wm = hk.spawn(2, hcar, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.4, 1.0)
	hcar.position.z = 2.0
	hk.update(0.016)
	var h_a0: float = h_wm.ang
	hcar.position.z += 8.0 * 0.05
	hk.update(0.05)
	check(absf((h_wm.ang - h_a0) - tuning.windmill_speed[0] * 0.05) < 0.002, "windmill blades turn windmill_speed x the frame's delta (%.4f rad)" % (h_wm.ang - h_a0))
	hk.release_all()
	hcar.queue_free()
	# a slow frame is clamped or dropped and never made up afterwards
	var raw_used: Array[float] = []
	for h_raw in [0.016, 0.2, 0.016, 0.4, 0.016, 0.016, 0.016, 0.016]:
		raw_used.append(main._frame_delta(h_raw))
	check(raw_used[1] == tuning.max_frame_delta and raw_used[3] == 0.0 and raw_used[4] == 0.0 and raw_used[5] == 0.0 and raw_used[6] == 0.016,
			"slow frames are clamped (%.2f) or dropped, then the frames after a stall are skipped, never made up %s" % [tuning.max_frame_delta, str(raw_used)])
	main.spawner.kit_enabled = false
	main.spawner.apply_map(0)

	print("11. pick cards: perk / boost / supply read at a glance")
	var cs_pc = main.pick_screen
	var cs_save = root.get_node("Save")
	cs_save.explained = {}
	var cs_pk = main.picks
	cs_pk.set_perk("scavenger", 1)
	var cs_perk: Dictionary = cs_pk.perk_card(tuning.perk_def("scavenger"), 2, true)
	var cs_new: Dictionary = cs_pk.perk_card(tuning.perk_def("tailwind"), 1, false)
	var cs_boost: Dictionary = {"kind": "boost", "id": "shield", "name": "Shield", "glyph": "O", "color": Color(0.4, 0.8, 1.0), "line": "One free hit, 20 s", "level": 0, "owned": false}
	var cs_supply: Dictionary = {"kind": "supply", "id": "patch", "name": "Patch", "glyph": "+", "color": Color(1.0, 0.4, 0.4), "line": "+1 hit this run", "level": 0, "owned": false}
	cs_pc.show_cards(_cards_of([cs_perk, cs_boost, cs_supply]), ["Combo", "", ""])
	var cs_frames: Array[Color] = []
	for i in 3:
		cs_frames.append((cs_pc._cards[i].get_theme_stylebox("normal") as StyleBoxFlat).border_color)
	check(cs_frames[1] == cs_pc.KIND_COLORS["boost"] and cs_frames[2] == cs_pc.KIND_COLORS["supply"], "boost cards have a blue frame, supply cards a green one")
	check(cs_pc._parts[0]["kind"].text == "PERK" and cs_pc._parts[1]["kind"].text == "BOOST" and cs_pc._parts[2]["kind"].text == "SUPPLY", "each card has a PERK / BOOST / SUPPLY banner")
	var cs_hues := [cs_pc.KIND_COLORS["perk"], cs_pc.KIND_COLORS["boost"], cs_pc.KIND_COLORS["supply"]]
	check(cs_hues[0] != cs_hues[1] and cs_hues[1] != cs_hues[2] and cs_hues[0] != cs_hues[2] and absf(cs_hues[0].h - 0.12) < 0.06 and absf(cs_hues[1].h - 0.6) < 0.06 and absf(cs_hues[2].h - 0.38) < 0.06, "gold, blue and green are clearly different hues")
	cs_pc.show_cards(_cards_of([cs_new, cs_boost, cs_supply]), ["", "", ""])
	check((cs_pc._cards[0].get_theme_stylebox("normal") as StyleBoxFlat).border_color == cs_pc.KIND_COLORS["perk"], "a perk card has a gold frame (when it is not a combo)")
	var cs_pips := 0
	for pip in cs_pc._parts[0]["pips"]:
		cs_pips += int(pip.visible)
	check(cs_pips == 3 and not cs_pc._parts[1]["pips"][0].visible and not cs_pc._parts[2]["pips"][0].visible, "level pips only on perks")
	check(cs_pc._parts[1]["watch"].visible and cs_pc._parts[1]["tag"].text == "%d s" % int(tuning.boost_time) and not cs_pc._parts[0]["watch"].visible, "a boost shows a stopwatch and how long it lasts (%s)" % cs_pc._parts[1]["tag"].text)
	check(cs_pc._parts[2]["tag"].text == "INSTANT" and not cs_pc._parts[2]["watch"].visible, "a supply says INSTANT")
	cs_pc.show_cards(_cards_of([cs_perk, cs_boost, cs_supply]), ["", "", ""])
	check(cs_pc._parts[0]["level_up"].visible and cs_pc._parts[0]["level_up"].text == "LEVEL UP 1 -> 2" and not cs_pc._parts[1]["level_up"].visible, "an owned perk shows \"%s\"" % cs_pc._parts[0]["level_up"].text)
	cs_pc.show_cards(_cards_of([cs_new, cs_boost, cs_supply]), ["Combo", "", ""])
	check(cs_pc._parts[0]["combo"].visible and not cs_pc._parts[1]["combo"].visible and (cs_pc._cards[0].get_theme_stylebox("normal") as StyleBoxFlat).border_color != cs_pc.KIND_COLORS["perk"], "the COMBO! highlight is kept (and stands out from the gold frame)")
	# the explainers: once per kind, the first time it appears
	cs_save.explained = {}
	cs_pc.show_cards(_cards_of([cs_new, cs_boost, cs_supply]), ["", "", ""])
	check(cs_pc._parts[0]["explain"].text == "Lasts this run" and cs_pc._parts[1]["explain"].text == "Lasts 20 seconds" and cs_pc._parts[2]["explain"].text == "Used instantly", "the first time, each kind has its one-line explainer under the banner")
	cs_pc.show_cards(_cards_of([cs_new, cs_boost, cs_supply]), ["", "", ""])
	check(not cs_pc._parts[0]["explain"].visible and not cs_pc._parts[1]["explain"].visible and not cs_pc._parts[2]["explain"].visible, "...and never again")
	cs_save.explained = {}
	cs_pc.show_cards(_cards_of([cs_boost]), [""])
	cs_pc.show_cards(_cards_of([cs_new, cs_boost, cs_supply]), ["", "", ""])
	check(not cs_pc._parts[1]["explain"].visible and cs_pc._parts[0]["explain"].visible and cs_pc._parts[2]["explain"].visible, "...each kind on its own first appearance")
	cs_save.load_game()
	check(cs_save.was_explained("boost"), "...remembered in the save")
	cs_pc.hide_cards()
	# every set of three has a perk, and owned perks still come up more often
	cs_pk.reset_run() if cs_pk.has_method("reset_run") else null
	var cs_no_perk := 0
	var cs_owned_hits := 0
	var cs_other_hits := 0
	cs_pk.set_perk("scavenger", 1)
	for i in 4000:
		var roll_cards: Array[Dictionary] = cs_pk.roll(0.5, 3)
		var any_perk := false
		for c in roll_cards:
			any_perk = any_perk or c["kind"] == "perk"
			if c["id"] == "scavenger":
				cs_owned_hits += 1
			elif c["id"] == "daredevil":
				cs_other_hits += 1
		cs_no_perk += int(not any_perk)
	check(cs_no_perk == 0, "every set of 3 cards includes a perk (4000 rolls)")
	check(cs_owned_hits > cs_other_hits * 1.2, "a perk you own is offered more often (%d vs %d)" % [cs_owned_hits, cs_other_hits])
	cs_pk.set_perk("scavenger", 0)

	print("12. sound: synthesised files, pooled players, the mix follows speed and the wave phase, ?nofx=sound / music")
	DebugFlags.parse(["tune"])
	var so = main.sfx
	var so_ok := true
	for n12 in so.ONE_SHOTS:
		so_ok = so_ok and so._streams[n12] != null and so._streams[n12].get_length() > 0.01
	check(so_ok and so._pool.size() == so.POOL, "all %d one-shot sounds load (synthesised offline), in a pool of %d players" % [so.ONE_SHOTS.size(), so.POOL])
	var loops_ok := true
	for p12 in [so._engine, so._wind] + so._music:
		loops_ok = loops_ok and p12.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and p12.stream.loop_end > 1000
	check(loops_ok and so._music.size() == 3, "the engine, the wind and the three music layers are seamless loops")
	check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0, "a Music bus and a SFX bus carry the volume settings")
	var so_save = root.get_node("Save")
	so_save.audio_music = 0.5
	so_save.audio_sound = 0.25
	so.apply_volumes()
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.5)) < 0.01 and absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")) - linear_to_db(0.25)) < 0.01, "the start-screen volumes set the buses")
	var vol_seen := [-1.0, -1.0]
	main.hud.volume_changed.connect(func(m: float, sd: float):
		vol_seen[0] = m
		vol_seen[1] = sd)
	main.hud._volume_sliders[0].value = 0.3
	main.hud._volume_sliders[1].value = 0.9
	check(main.hud._volume_sliders.size() == 2 and absf(so_save.audio_music - 0.3) < 0.001 and absf(so_save.audio_sound - 0.9) < 0.001 and absf(vol_seen[0] - 0.3) < 0.001, "the start screen has a Music and a Sound slider that change the settings live")
	so_save.save_game()
	so_save.load_game()
	check(absf(so_save.audio_music - 0.3) < 0.001 and absf(so_save.audio_sound - 0.9) < 0.001, "...and they are saved")
	# the sounds fire from the game's events
	main.restart()
	var plays0: int = so.plays
	var nm_ev := {"side": 1, "node": null, "outline": ShaderMaterial.new(), "clearance": 0.1, "whisker": false, "row": null, "k": -1}
	main._on_near_miss(nm_ev)
	var s_plain: String = so.last_played
	nm_ev["whisker"] = true
	main._on_near_miss(nm_ev)
	var s_whisker: String = so.last_played
	nm_ev["special"] = "barnstormer"
	main._on_near_miss(nm_ev)
	check(s_plain == "whoosh" and s_whisker == "whoosh_big" and so.last_played == "barnstormer", "a close call whooshes; a Whisker close and a Barnstormer get bigger ones (%s, %s, %s)" % [s_plain, s_whisker, so.last_played])
	main._on_pickup(Vector3.ZERO)
	var s_pickup: String = so.last_played
	main._on_crate_break(1, Vector3.ZERO)
	var s_crunch: String = so.last_played
	main._speed_up_cue(0.4)
	var s_speed: String = so.last_played
	check(s_pickup == "pickup" and s_crunch == "crunch" and s_speed == "speed_whoosh" and so.plays - plays0 >= 6, "fuel can pickup, hay crunch and the speed-up whoosh each play their sound")
	main.hud.show_menu()
	so.last_played = ""
	var tap_btn: Button = main.hud._make_button("x", 20, Vector2(10, 10))
	tap_btn.pressed.emit()
	tap_btn.free()
	check(so.last_played == "tap", "UI buttons tap")
	# engine and wind follow the speed
	so.set_flight(true, 0.0)
	for i in 30:
		so._process(0.05)
	var eng_lo_pitch: float = so._engine.pitch_scale
	var eng_lo_db: float = so._engine.volume_db
	var wind_lo_db: float = so._wind.volume_db
	so.set_flight(true, 1.0)
	for i in 30:
		so._process(0.05)
	check(so._engine.playing and so._engine.pitch_scale > eng_lo_pitch * 2.0 and so._engine.volume_db > eng_lo_db and so._wind.volume_db > wind_lo_db + 6.0, "the engine's pitch and volume and the wind rise with speed (pitch x%.1f)" % (so._engine.pitch_scale / eng_lo_pitch))
	so.set_flight(false)
	for i in 30:
		so._process(0.05)
	check(not so._engine.playing, "...and fall silent when the run ends")
	# the music layers follow the wave phase
	for ph12 in 4:
		so.set_phase(ph12)
		for i in 60:
			so._process(0.05)
		var want_mix: Array = so.LAYER_MIX[ph12]
		var got_ok := true
		for i in 3:
			got_ok = got_ok and absf(so._layer_now[i] - float(want_mix[i])) < 0.01
		check(got_ok, "music layers in %s: %s" % [["CALM (base only)", "BUILD (+ rhythm)", "PEAK (full)", "BREATHER (back to base)"][ph12], str(so._layer_now)])
	check(so._music[0].volume_db > -20.0 and so._music[2].volume_db < -60.0, "...as volumes (base audible, lead silent in the BREATHER)")
	# ?nofx=sound and ?nofx=music
	DebugFlags.parse(["nofx=sound"])
	var p_before: int = so.plays
	so.play("crash")
	so.set_flight(true, 0.5)
	for i in 30:
		so._process(0.05)
	check(so.plays == p_before and not so._engine.playing, "?nofx=sound: no effects, no engine")
	DebugFlags.parse(["nofx=music"])
	so.set_phase(2)
	for i in 60:
		so._process(0.05)
	check(so._music[0].volume_db <= -79.0 and so._music[2].volume_db <= -79.0, "?nofx=music: the music is silent")
	DebugFlags.parse(["tune"])
	so.set_flight(false)
	so.set_phase(0)
	# nothing is created while playing
	var snd_base := snapshot(main)
	for i in 400:
		so.play(so.ONE_SHOTS[i % so.ONE_SHOTS.size()], 0.0)
		so.set_flight(i % 50 < 40, (i % 100) / 100.0)
		so.set_phase(i % 4)
		so._process(0.016)
	so.set_flight(false)
	check(same_world(snd_base, snapshot(main)), "400 sounds, engine and music changes created nothing new  [%s]" % describe(snapshot(main)))
	for p12 in so._pool:
		p12.stop()
	so_save.audio_music = 0.7
	so_save.audio_sound = 0.8
	so.apply_volumes()

	print("13. crash sequence and results screen")
	var cr_save = root.get_node("Save")
	main.set_process(false)
	main.spawner.kit_enabled = true
	main.spawner.apply_map(0)
	cr_save.reset_all()
	cr_save.map_stats[tuning.maps[0]["id"]]["best_distance"] = 1000.0
	cr_save.coins = 500.0
	main.restart()
	main.picks.enabled = false
	var cr_base := snapshot(main)
	main.spawner.kit.last_hit_kind = 3   # a crow flock
	main.score = 777.0
	main.run_distance = 920.0 / tuning.meters_per_unit
	main.player.position.x = 2.0
	main._end_run(main.HEADER_CRASH, main.REASON_OBSTACLE)
	check(main._crash_t == 0.0 and main.crash_fx.active and not main.hud.results_visible() and Engine.time_scale == 1.0, "a crash starts the crash sequence (no results yet, time scale untouched)")
	check(main._results["cause"] == "Clipped by a crow flock" and main.hud._over.text.contains("Clipped by a crow flock"), "the run says what ended it: \"%s\"" % main._results["cause"])
	var cr_h0: float = main.player.position.y
	for i in 8:   # 0.4 s
		main._update_crash(0.05)
	check(main.crash_fx._whiskers.visible and main.crash_fx._chute.visible, "Whiskers ejects (after about 0.2 s)")
	var cr_y_eject: float = main.crash_fx._whiskers.position.y
	for i in 12:   # 1.0 s in
		main._update_crash(0.05)
	check(main.player._model.rotation.y > 5.0 and main.player.position.y < cr_h0 - 0.3 and main.player._model.scale.x < 0.95, "the plane spins and falls (spin %.1f rad, down %.2f)" % [main.player._model.rotation.y, cr_h0 - main.player.position.y])
	check(main.crash_fx._chute.scale.x > 0.9 and main.crash_fx._whiskers.position.y > -1.7, "the parachute is open and he drifts down (y %.2f)" % main.crash_fx._whiskers.position.y)
	check(main.camera.size < tuning.ortho_size - 0.5 or main._cam_ease > 0.5, "the camera eases toward the plane (ease %.2f)" % main._cam_ease)
	main._update_camera()
	check(main.camera.size < tuning.ortho_size * 0.9, "...zooming in (%.2f of %.1f)" % [main.camera.size, tuning.ortho_size])
	check(not main.hud.results_visible(), "the results wait for the crash sequence (%.1f s)" % main.CRASH_TIME)
	for i in 12:
		main._update_crash(0.05)
	check(main.hud.results_visible() and not main.hud._over_hangar.visible and main.hud._over.modulate.a == 0.0, "then the results screen takes over")
	# the build-up: coins count up with ticks
	var cr_ticks := [0]
	main.hud.result_tick.connect(func(_p: float): cr_ticks[0] += 1)
	main.hud.show_results(main._results)
	var cr_prev := -1.0
	var cr_mono := true
	for i in 45:   # 2.25 s
		main.hud._update_results(0.05)
		var shown_coins: float = float(main.hud._res_nodes["coins"].text.trim_prefix("+").replace(",", "").replace("K", "000"))
		cr_mono = cr_mono and shown_coins >= cr_prev - 0.001
		cr_prev = shown_coins
	check(cr_mono and main.hud._res_nodes["coins"].text == "+" + tuning.fmt(floorf(main.last_earned)) and cr_ticks[0] >= 20, "coins count up to %s with ticks (%d)" % [main.hud._res_nodes["coins"].text, cr_ticks[0]])
	check(absf(float(main._results["pct"]) - 0.92) < 0.001 and main.hud._res_nodes["pct"].text.begins_with("92% of your best") and not main._results["new_best"], "distance against the best: \"%s\"" % main.hud._res_nodes["pct"].text)
	main.hud.skip_results()
	var cr_bar_w: float = main.hud._res_nodes["dist_bar_fill"].size.x
	check(absf(cr_bar_w - 900.0 * 0.92) < 2.0, "...with a progress bar to it (%.0f of 900 px)" % cr_bar_w)
	check(main._results["unlock_text"].contains("to the Coast") and main.hud._res_nodes["unlock"].visible, "progress to the next map: \"%s\"" % main._results["unlock_text"])
	check(main._results["medal_text"].contains("to Bronze"), "progress to the next medal: \"%s\"" % main._results["medal_text"])
	check(main._results.has("afford_id") and main.hud._res_nodes["afford_btn"].visible and main.hud._res_nodes["afford_btn"].text != "", "an upgrade you can afford is highlighted: \"%s\"" % main.hud._res_nodes["afford_btn"].text)
	var cr_again: Button = main.hud._res_nodes["again"]
	check(cr_again.visible and cr_again.size.x >= 800.0 and cr_again.size.y >= 200.0 and cr_again.text == "PLAY AGAIN", "a big PLAY AGAIN button")
	var goto_id: String = main._results["afford_id"]
	main.hud._res_nodes["afford_btn"].pressed.emit()
	check(main.screen == main.SCREEN_HANGAR and main.hud._hangar.visible and main.hud._tab == tuning.upgrade_def(goto_id)["tab"], "the upgrade button goes straight to its Hangar tab")
	main.restart()
	check(main.alive and not main.hud.results_visible() and main._crash_t < 0.0 and main._cam_ease == 0.0 and not main.crash_fx.active and main.player._model.scale.x == 1.0 and absf(main.player.position.y - 1.2) < 0.001, "PLAY AGAIN: a fresh run, camera and plane back to normal")
	# a new best reads differently
	main.run_distance = 1500.0 / tuning.meters_per_unit
	main._end_run(main.HEADER_CRASH, main.REASON_OBSTACLE)
	main.hud.show_results(main._results)
	check(main._results["new_best"] and main.hud._res_nodes["pct"].text == "NEW BEST!", "a new best distance says NEW BEST!")
	main.restart()
	# the debug buttons
	main.debug_crash()
	check(not main.alive and main._crash_t >= 0.0, "?tune: Crash now")
	main.restart()
	main.debug_results()
	main._update_crash(0.05)
	check(main.hud.results_visible(), "?tune: Preview results")
	main.restart()
	main.spawner.kit_enabled = false
	main.spawner.apply_map(0)
	check(same_world(cr_base, snapshot(main)), "crashing, the sequence and the results created nothing new  [%s]" % describe(snapshot(main)))
	cr_save.reset_all()
	main.restart()
	main.set_process(false)

	print("14. progress you can feel: perk level 3 behaviours, marks on the plane, callouts, in-world goals")
	var pf_save = root.get_node("Save")
	pf_save.reset_all()
	main.spawner.kit_enabled = false
	main.restart()
	main.set_process(false)
	var pf = main.picks
	pf.enabled = false
	# every perk and gear item has a visible mark on the plane
	var pl14 = main.player
	var pf_mark_ok := true
	for d in tuning.perks:
		pf_mark_ok = pf_mark_ok and pl14._items.has(d["id"])
	for u in tuning.upgrades_in_tab("gear"):
		pf_mark_ok = pf_mark_ok and pl14._items.has(u["id"])
	check(pf_mark_ok and pl14._items.size() == tuning.perks.size() + tuning.upgrades_in_tab("gear").size(), "every perk and gear item has a mark on the plane (%d)" % pl14._items.size())
	pl14.set_items({}, [])
	var pf_none_vis := 0
	for id in pl14._items:
		pf_none_vis += int(pl14._items[id]["root"].visible)
	pl14.set_items({"hot_streak": 1, "tailwind": 3}, ["magnet", "nine_lives"])
	var pf_vis_ids: Array[String] = []
	for id in pl14._items:
		if pl14._items[id]["root"].visible:
			pf_vis_ids.append(id)
	pf_vis_ids.sort()
	check(pf_none_vis == 0 and pf_vis_ids == ["hot_streak", "magnet", "nine_lives", "tailwind"], "only what you hold is drawn on the plane %s" % str(pf_vis_ids))
	check(pl14._items["tailwind"]["root"].scale.x > pl14._items["hot_streak"]["root"].scale.x and pl14._items["tailwind"]["mats"][0].emission_enabled and not pl14._items["hot_streak"]["mats"][0].emission_enabled, "a higher level makes the mark bigger, and level 3 glows")
	pf.set_perk("scavenger", 2)
	pf_save.loadout = ["reserve_tank", "", ""]
	pf_save.levels["reserve_tank"] = 1
	main._refresh_plane_items()
	check(pl14._items["scavenger"]["root"].visible and pl14._items["reserve_tank"]["root"].visible, "picking a perk or equipping gear puts its mark on the plane")
	pf.set_perk("scavenger", 0)
	pf_save.loadout = ["", "", ""]
	main._refresh_plane_items()
	# callouts
	main._callout_ms["nine_lives"] = -100000
	main.last_callout = ""
	main._callout("nine_lives", "Nine Lives!")
	var pf_call_vis := 0
	for cn in main.hud._call_nodes:
		pf_call_vis += int(cn["holder"].visible)
	check(main.last_callout == "Nine Lives!" and pf_call_vis == 1, "a callout pops (%d on screen)" % pf_call_vis)
	main._callout("nine_lives", "Nine Lives! again")
	check(main.last_callout == "Nine Lives!", "...and the same item does not repeat within a moment")
	tuning.crate_chance = 0.0
	pf_save.levels["nine_lives"] = 1
	pf_save.loadout = ["nine_lives", "", ""]
	main.restart()
	main.set_process(false)
	main._callout_ms["nine_lives"] = -100000
	main.last_callout = ""
	main._absorb_hit(Vector2(main.player.position.x, main.player.position.z), main.player.hit_capsules())
	check(main.last_callout == "Nine Lives!", "Nine Lives acting says \"Nine Lives!\"")
	pf_save.levels["reserve_tank"] = 1
	pf_save.loadout = ["reserve_tank", "", ""]
	main.restart()
	main.set_process(false)
	main._callout_ms["reserve_tank"] = -100000
	main.fuel = 0.0
	main._check_fuel(0.05)
	check(main.last_callout == "Reserve Tank saved you!", "Reserve Tank acting says \"%s\"" % main.last_callout)
	pf_save.loadout = ["", "", ""]
	main.restart()
	main.set_process(false)
	# level 3 behaviours
	pf.set_perk("hot_streak", 3)
	main._steps.clear()
	for v in [0.5, 0.4, 0.3]:
		main._steps.append(v)
	main._refresh_bonus()
	main._bonus_timer = 0.0
	main._decay_acc = 50.0
	main._decay_bonus(0.1)
	check(main.bonus >= 2.0 and main.bonus < 2.3, "Hot Streak 3: the bonus never drops below x2 (x%.1f after a long fade)" % main.bonus)
	pf.set_perk("hot_streak", 0)
	pf.set_perk("fuel_miser", 3)
	main._steps.clear()
	for v in [0.5, 0.5, 0.5, 0.5]:
		main._steps.append(v)
	main._refresh_bonus()
	main.fuel = 100.0
	main._process(0.05)
	check(is_equal_approx(main.fuel, 100.0), "Fuel Miser 3: nothing burns at bonus x3 or more (%.2f)" % main.fuel)
	pf.set_perk("fuel_miser", 0)
	main._steps.clear()
	main._refresh_bonus()
	pf.set_perk("scavenger", 3)
	main._steps.clear()
	main._refresh_bonus()
	main._on_pickup(Vector3(0, 0.4, -3))
	check(main._steps.size() == 1, "Scavenger 3: each can adds a bonus step")
	pf.set_perk("scavenger", 0)
	main._steps.clear()
	main._refresh_bonus()
	main.restart()
	main.set_process(false)
	pf.set_perk("daredevil", 3)
	main._process(0.01)
	check(main.spawner.whisker_scale == 2.0, "Daredevil 3: Whisker closes count from twice as far")
	pf.set_perk("daredevil", 0)
	pf.set_perk("tailwind", 3)
	main.fuel = 50.0
	var pf_tw_row = main.spawner._rows_make_for_test(-5.0, [1.0])
	main._on_near_miss({"side": 1, "node": pf_tw_row.obs[0], "outline": pf_tw_row.outlines[0], "whisker": true})
	check(main.fuel >= 50.0 + 0.04 * tuning.fuel_max() - 0.01, "Tailwind 3: a Whisker close refuels 4%% (%.1f)" % main.fuel)
	main.spawner._release_row(pf_tw_row)
	pf.set_perk("tailwind", 0)
	pf.set_perk("second_wind", 3)
	main.fuel = 10.0
	main._process(0.05)
	var pf_sw1: float = main.fuel
	main.fuel = 10.0
	main._process(0.05)
	check(pf_sw1 > 90.0 and main.fuel > 90.0, "Second Wind 3: works twice a run (%.0f, %.0f)" % [pf_sw1, main.fuel])
	pf.set_perk("second_wind", 0)
	# upgrades are big at first
	var pf_first_ok := true
	for id in ["coin_value", "can_bounty", "close_call_pay", "bonus_cap"]:
		var g1: float = tuning.upgrade_value(id, 1) - tuning.upgrade_value(id, 0)
		var g8: float = tuning.upgrade_value(id, 9) - tuning.upgrade_value(id, 8)
		pf_first_ok = pf_first_ok and g1 > 1.5 * g8
	check(pf_first_ok, "the first level of each EARNINGS upgrade is worth more than 1.5x a level-9 one")
	# in-world goals
	pf_save.reset_all()
	pf_save.map_stats[tuning.maps[0]["id"]]["best_distance"] = 1000.0
	main.restart()
	main.set_process(false)
	var pf_gl = main.goals
	check(pf_gl.count == 3, "a run puts three goals in the world: your best, the next medal, the next map unlock (%d)" % pf_gl.count)
	check(pf_gl._goals[0]["kind"] == "best" and pf_gl._goals[0]["meters"] == 1000.0 and pf_gl._gates[0]["label"].text == "BEST  1,000 m", "the first is a flag at your best: \"%s\"" % pf_gl._gates[0]["label"].text)
	check(pf_gl._goals[1]["kind"] == "medal" and pf_gl._goals[1]["meters"] == 1500.0 and pf_gl._goals[2]["kind"] == "unlock" and pf_gl._goals[2]["meters"] == 3000.0, "...then Bronze at 1,500 m and the Coast at 3,000 m")
	var pf_gz: float = main.player.position.z
	pf_gl.update(0.0, pf_gz, -9.0)
	check(not pf_gl._gates[0]["root"].visible, "far away the gates are out of sight")
	var reached_kinds: Array[String] = []
	pf_gl.reached.connect(func(kind: String, _t: String, _c: Color): reached_kinds.append(kind))
	pf_gl.update(950.0, pf_gz, -9.0)
	check(pf_gl._gates[0]["root"].visible and pf_gl._gates[0]["root"].position.z < pf_gz and reached_kinds.is_empty(), "as you near it the gate scrolls into view, ahead of the plane")
	pf_gl.update(1002.0, pf_gz, -9.0)
	pf_gl.update(1010.0, pf_gz, -9.0)
	check(reached_kinds == ["best"] and main.last_cue == "NEW BEST!", "passing it celebrates once (%s)" % main.last_cue)
	pf_gl.update(1600.0, pf_gz, -9.0)
	check(reached_kinds == ["best", "medal"] and main.last_cue == "BRONZE MEDAL!", "...and the medal gate: %s" % main.last_cue)
	main.restart()
	main.set_process(false)
	check(not pf_gl._gates[0]["root"].visible, "the next run starts with fresh gates")
	pf_save.reset_all()
	main.restart()
	main.set_process(false)
	check(main.goals.count == 2, "with no best yet there is no BEST flag (medal and unlock only)")

	print("15. world and pacing: ground, shadow, takeoff, time of day, a gentle first minute, Whiskers' mood")
	var wd_save = root.get_node("Save")
	wd_save.reset_all()
	main.spawner.kit_enabled = false
	main.restart()
	main.set_process(false)
	var wd_gw = main.ground
	check(wd_gw._chunks.size() == wd_gw.CHUNKS and wd_gw._chunks[0].fields.size() == wd_gw.FIELD_COLS * wd_gw.FIELD_ROWS, "the ground world has %d recycled chunks of fields, roads, river, and houses" % wd_gw.CHUNKS)
	var wd_no_outline := true
	for c in wd_gw._chunks:
		for f in c.fields:
			wd_no_outline = wd_no_outline and f.material_overlay == null
		for seg in c.river:
			wd_no_outline = wd_no_outline and seg.material_overlay == null
	check(wd_no_outline, "scenery has no outlines")
	var wd_natural_green := Color(0.36, 0.6, 0.28)
	check(wd_gw._field_mats[0].albedo_color.s < wd_natural_green.s - 0.05, "...and is faded toward the haze (saturation %.2f < %.2f)" % [wd_gw._field_mats[0].albedo_color.s, wd_natural_green.s])
	var wd_z_before: float = wd_gw._chunks[0].position.z
	wd_gw.scroll(10.0)
	check(absf((wd_gw._chunks[0].position.z - wd_z_before) - 10.0 * wd_gw.parallax) < 0.001 and wd_gw.parallax < 1.0, "the ground scrolls slower than the obstacles: parallax x%.2f" % wd_gw.parallax)
	var wd_base := snapshot(main)
	for i in 400:
		wd_gw.scroll(2.0)
	var wd_span_ok := true
	for c in wd_gw._chunks:
		wd_span_ok = wd_span_ok and c.position.z > -wd_gw.LEN * wd_gw.CHUNKS and c.position.z < 14.0 + wd_gw.LEN
	check(wd_span_ok and same_world(wd_base, snapshot(main)), "chunks are recycled as they scroll off, creating nothing new  [%s]" % describe(snapshot(main)))
	# the plane's shadow
	main.player.position = Vector3(1.5, 1.2, 4.0)
	wd_gw.update_shadow(main.player.position, true)
	var shadow_high_scale: float = wd_gw.shadow.scale.x
	main.player.position = Vector3(1.5, -1.5, 4.0)
	wd_gw.update_shadow(main.player.position, true)
	check(wd_gw.shadow.visible and absf(wd_gw.shadow.position.x - 1.5) < 0.001 and absf(wd_gw.shadow.position.z - (4.0 + root.get_node("/root/Tuning").shadow_offset * 0.6)) < 0.001 and wd_gw.shadow.scale.x < shadow_high_scale, "the plane casts a soft shadow that follows it and tightens when it is low")
	main.player.position = Vector3(0, 1.2, 4.0)
	# takeoff
	DebugFlags.god = true   # (nothing in the way matters here)
	main.restart()
	main.set_process(true)
	await real_wait(0.2)
	main.set_process(false)
	check(main.player.position.y < 0.6 and wd_gw.airstrip_active and wd_gw.airstrip.visible and main._takeoff_t > 0.0, "a run starts with a takeoff from Rusty's airstrip (plane at height %.2f)" % main.player.position.y)
	for i in 50:
		main._process(0.05)
	check(absf(main.player.position.y - main.player.PLANE_Y) < 0.001 and main._takeoff_t >= tuning.takeoff_seconds and tuning.opening_seconds >= tuning.takeoff_seconds, "...and is flying by %.1f s, before the first obstacles" % tuning.takeoff_seconds)
	for i in 200:
		main._process(0.05)
	check(not wd_gw.airstrip_active and not wd_gw.airstrip.visible, "the airstrip scrolls away")
	DebugFlags.god = false
	# time of day
	main.tod_override = 0.0
	main._apply_time_of_day(0.0)
	var wd_sky_morning: Color = main._env.background_color
	var wd_sun_morning: float = main.sun.light_energy
	main._apply_time_of_day(0.7)
	var wd_sky_sunset: Color = main._env.background_color
	main._apply_time_of_day(1.0)
	var wd_sky_dusk: Color = main._env.background_color
	check(wd_sky_sunset.r > wd_sky_sunset.b and wd_sky_dusk.get_luminance() < wd_sky_morning.get_luminance() and main.sun.light_energy < wd_sun_morning and not wd_sky_morning.is_equal_approx(wd_sky_sunset), "the sky shifts from morning through a warm sunset to a dark dusk")
	main.tod_override = -1.0
	main.debug_cycle_tod()
	var wd_tod1: float = main.tod_override
	main.debug_cycle_tod()
	main.debug_cycle_tod()
	main.debug_cycle_tod()
	var wd_tod4: float = main.tod_override
	main.debug_cycle_tod()
	check(wd_tod1 == 0.0 and wd_tod4 == 1.0 and main.tod_override == -1.0, "?tune: the time-of-day button jumps morning, day, sunset, dusk, then follows the run again")
	main.elapsed = 0.0
	var wd_tod_a: float = main._current_tod()
	main.elapsed = tuning.tod_seconds * 0.7
	var wd_tod_b: float = main._current_tod()
	check(wd_tod_a < 0.01 and absf(wd_tod_b - 0.7) < 0.01, "following the run, the day passes over %.0f s" % tuning.tod_seconds)
	# a gentle first minute
	var wd_gs = main.spawner
	wd_gs.kit_enabled = true
	wd_gs.apply_map(0)
	wd_gs.reset(-14.0)
	wd_gs.run_time = 10.0
	wd_gs.scroll_speed = 7.0
	var gentle_hard := 0
	var gentle_calm := 0
	for i in 300:
		wd_gs._pat = {}
		var gp: Dictionary = wd_gs._choose_pattern()
		gentle_hard += int(float(gp["diff"]) > 1.0)
		gentle_calm += int(P.has_tag(gp, "calm"))
		wd_gs._pat_last = gp["name"]
	check(gentle_hard == 0 and gentle_calm > 100, "the first %.0f s offers only the easiest patterns, with empty stretches between (%d above difficulty 1, %d of 300 calm)" % [tuning.gentle_seconds, gentle_hard, gentle_calm])
	wd_gs.run_time = 100.0
	wd_gs._wave_start = 100.0
	wd_gs.wave_phase = 2
	var later_hard := 0
	for i in 300:
		wd_gs._pat = {}
		wd_gs._pat_last = ""
		later_hard += int(float(wd_gs._choose_pattern()["diff"]) > tuning.gentle_max_diff)
	check(later_hard > 100, "after that the waves bring harder ones (%d of 300)" % later_hard)
	var wd_steps_ok := true
	for i in range(1, 7):
		wd_steps_ok = wd_steps_ok and wd_gs.stepped_speed(i) > wd_gs.stepped_speed(i - 1)
	check(is_equal_approx(wd_gs.stepped_speed(1) - wd_gs.stepped_speed(0), 2.0) and is_equal_approx(wd_gs.stepped_speed(2) - wd_gs.stepped_speed(1), 2.5) and wd_steps_ok and wd_gs.stepped_speed(6) == tuning.max_speed, "speed steps start small and grow: +2, +2.5, +3 ... to the top in 6 steps (%.1f, %.1f, %.1f)" % [wd_gs.stepped_speed(1), wd_gs.stepped_speed(2), wd_gs.stepped_speed(3)])
	wd_gs.reset()
	wd_gs.kit_enabled = false
	wd_gs.apply_map(0)
	# Whiskers in the cockpit
	main.restart()
	main.set_process(false)
	var pl15 = main.player
	check(pl15._cat.visible and pl15.mood == pl15.Mood.NEUTRAL, "Whiskers sits in the cockpit")
	var wd_eye_neutral: float = pl15._cat_eyes[0].scale.x
	var wd_wm_row = main.spawner._rows_make_for_test(-5.0, [1.0])
	main._on_near_miss({"side": 1, "node": wd_wm_row.obs[0], "outline": wd_wm_row.outlines[0], "whisker": false, "row": null})
	main._process(0.016)
	check(pl15.mood == pl15.Mood.STARTLED and pl15._cat_eyes[0].scale.x > wd_eye_neutral * 1.3, "a close call startles him (wide eyes, an \"o\")")
	await real_wait(0.75)
	main._steps.clear()
	for v in [0.5, 0.5]:
		main._steps.append(v)
	main._refresh_bonus()
	main._process(0.016)
	check(pl15.mood == pl15.Mood.GRIN and pl15._cat_eyes[0].scale.z < 0.5, "on a streak he grins (squinting)")
	main.spawner._release_row(wd_wm_row)
	main._end_run(main.HEADER_CRASH, main.REASON_OBSTACLE)
	check(not pl15._cat.visible, "on a crash he leaves the cockpit (he ejects)")
	main.restart()
	main.set_process(false)
	check(pl15._cat.visible and pl15.mood == pl15.Mood.NEUTRAL, "...and is back in the next run")
	wd_save.reset_all()
	var parents_ok := true
	for key in main.hud._res_nodes:
		var rn: Node = main.hud._res_nodes[key]
		parents_ok = parents_ok and (rn.get_parent() == main.hud._res)
	for cn in main.hud._call_nodes:
		parents_ok = parents_ok and cn["glyph"].get_parent() == cn["holder"] and cn["text"].get_parent() == cn["holder"]
	check(parents_ok and not main.hud._res.visible, "the results screen and the callouts hold their own parts (hiding them hides everything)")

	print("16. background readability and the screen audit")
	var sa_save := root.get_node("Save")
	sa_save.reset_all()
	main.set_process(true)
	main.restart()
	main.picks.enabled = false
	main.spawner.kit_enabled = true
	# -- the countryside is a small blurred picture, muted, no outlines
	var sa_g: Node3D = main.ground
	var sa_view: Vector2 = main.get_viewport().get_visible_rect().size
	await process_frame
	check(sa_g.vp.size.x <= int(sa_view.x / tuning.ground_blur_div) + 1 and sa_g.vp.size.x >= 8 and sa_g.vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "the countryside is drawn at 1/%d size (%s) and blurred on the ground plane" % [tuning.ground_blur_div, str(sa_g.vp.size)])
	check(main.spawner.ground_mi.material_override == sa_g.backdrop_mat and sa_g.backdrop_mat.get_shader_parameter("use_tex") == 1.0, "the ground plane shows the blurred picture")
	var sa_sat := 0.0
	for m in sa_g._all_mats:
		sa_sat = maxf(sa_sat, m.albedo_color.s)
	var sa_obs_sat: float = main.spawner._obstacle_mat.albedo_color.s
	check(sa_sat < 0.3 and sa_sat < sa_obs_sat, "ground colours are muted (max saturation %.2f vs obstacles %.2f)" % [sa_sat, sa_obs_sat])
	var sa_outlined := 0
	for mi in sa_g.world.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_overlay != null:
			sa_outlined += 1
	check(sa_outlined == 0 and sa_g.world.find_children("*", "Label3D", true, false).is_empty(), "no outlines and no text anywhere in the background")
	for tod in [0.0, 0.35, 0.7, 1.0]:   # every time of day keeps the ground muted and darker or equal in saturation than the obstacles
		main._apply_time_of_day(tod)
		var mx := 0.0
		for m in sa_g._all_mats:
			mx = maxf(mx, m.albedo_color.s)
		check(mx < 0.35, "time of day %.2f: ground saturation stays low (%.2f)" % [tod, mx])
	main._apply_time_of_day(0.35)
	# -- obstacle shadows
	var sa_row = main.spawner._rows_make_for_test(main.player.position.z - 6.0, [-2.0, 2.0])
	main.shadows.update_from(main.spawner, 0.0, true)
	check(main.shadows.count >= 2 and main.shadows._mm.visible_instance_count == main.shadows.count, "each obstacle gets a soft shadow on the ground (%d blobs)" % main.shadows.count)
	DebugFlags.parse(["tune", "nofx=shadows"])
	main.shadows.update_from(main.spawner, 0.0, true)
	check(main.shadows.count == 0 and main.shadows._mm.visible_instance_count == 0, "?nofx=shadows hides them")
	DebugFlags.parse(["tune", "nofx=ground"])
	sa_g.apply_debug()
	check(sa_g.vp.render_target_update_mode == SubViewport.UPDATE_DISABLED and sa_g.backdrop_mat.get_shader_parameter("use_tex") == 0.0, "?nofx=ground hides the countryside (flat colour, nothing drawn)")
	DebugFlags.parse(["tune"])
	sa_g.apply_debug()
	main.spawner._release_row(sa_row)
	# -- every screen: only the expected ones show after each transition
	var sa_names := func(extra: Array) -> String:
		var a: Array = Array(main.visible_screens())
		a = a.filter(func(n): return not ["popup", "coin_pop", "callout", "combo", "flash"].has(n) or extra.has(n))
		a.sort()
		return ",".join(a)
	main._show_menu()
	check(sa_names.call([]) == "menu", "menu: only the start screen shows [%s]" % sa_names.call([]))
	main._open_hangar()
	check(sa_names.call([]) == "hangar", "hangar: only the Hangar shows [%s]" % sa_names.call([]))
	main._show_menu()
	main._open_logbook()
	check(sa_names.call([]) == "logbook", "logbook: only the Logbook shows [%s]" % sa_names.call([]))
	main._show_menu()
	main.hud.play_pressed.emit()
	check(sa_names.call([]) == "airstrip" or sa_names.call([]) == "", "play: nothing but the world shows [%s]" % sa_names.call([]))
	check(not main.hud._menu.visible and not main.hud._hangar.visible and not main.hud._logbook.visible and not main.hud.results_visible() and not main.pick_screen.is_shown(), "play: no screen is up")
	# a run with callouts, popups and a combo banner up, then a crash
	main._callout("steady_nerves", "Steady Nerves kept your streak!")
	main.hud.popup("x2", 64, Color.WHITE, Vector2(540, 800))
	main.hud.show_combo("TEST", Color.WHITE, "COMBO!")
	var sa_now: Array = Array(main.visible_screens())
	check(sa_now.has("callout") and sa_now.has("popup") and sa_now.has("combo"), "a run shows its callout, popup and combo banner [%s]" % ",".join(sa_now))
	main.score = 500.0
	main._end_run(main.HEADER_CRASH, main.REASON_OBSTACLE)
	check(sa_names.call(["callout", "popup", "combo"]).contains("crash") and not main.hud.results_visible() and not main.hud._menu.visible, "crash: the crash sequence plays, no results yet [%s]" % sa_names.call(["callout", "popup", "combo"]))
	for i in 40:
		main._update_crash(0.05)
	check(sa_names.call([]) == "results" or sa_names.call([]) == "airstrip,results" or sa_names.call([]).begins_with("crash,results") or sa_names.call([]) == "results,crash", "results: the results screen shows over the finished crash [%s]" % sa_names.call([]))
	check(main.hud._res.mouse_filter == Control.MOUSE_FILTER_STOP and main.hud._menu.mouse_filter == Control.MOUSE_FILTER_STOP and main.hud._hangar.mouse_filter == Control.MOUSE_FILTER_STOP and main.hud._logbook.mouse_filter == Control.MOUSE_FILTER_STOP and main.pick_screen._root.mouse_filter == Control.MOUSE_FILTER_STOP, "every screen swallows touches (nothing leaks to the game behind)")
	# results -> hangar (the upgrade button) -> menu -> play
	main.hud.hangar_goto.emit(tuning.upgrades[0]["id"])
	check(sa_names.call([]) == "hangar" and not main.crash_fx.active and main._cam_ease == 0.0 and main._crash_t < 0.0, "results -> Hangar: only the Hangar shows, the crash and camera are cleared [%s]" % sa_names.call([]))
	main.hud.back_pressed.emit()
	check(sa_names.call([]) == "menu", "Hangar -> back: only the start screen [%s]" % sa_names.call([]))
	main.hud.play_pressed.emit()
	check(main.alive and not main.hud._menu.visible and not main.hud.results_visible() and not main.crash_fx.active, "...and PLAY starts a clean run")
	# results -> play again, with callouts and popups still up
	main._callout("steady_nerves", "again")
	main.hud.popup("x3", 64, Color.WHITE, Vector2(540, 800))
	main._end_run(main.HEADER_CRASH, main.REASON_OBSTACLE)
	for i in 40:
		main._update_crash(0.05)
	main._death_time -= 1.0
	main.hud.play_again_pressed.emit()
	var sa_after: String = sa_names.call([])
	check(main.alive and (sa_after == "" or sa_after == "airstrip"), "results -> PLAY AGAIN: a clean run, nothing left over [%s]" % sa_after)
	# restart while popups, callouts and a combo banner are active
	main._callout("steady_nerves", "again")
	main.hud.popup("x3", 64, Color.WHITE, Vector2(540, 800))
	main.hud.show_combo("TEST", Color.WHITE, "COMBO!")
	main.restart()
	check(not Array(main.visible_screens()).has("callout") and not Array(main.visible_screens()).has("popup") and not Array(main.visible_screens()).has("combo"), "restart clears every active popup, callout and banner [%s]" % ",".join(main.visible_screens()))
	# the pick screen opening and closing
	main.picks.enabled = true
	main._callout("steady_nerves", "pick")
	main._begin_pick()
	check(sa_names.call(["callout"]).contains("pick") and paused_ok(true), "pick: the cards show and the game is paused [%s]" % sa_names.call(["callout"]))
	main._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)   # the tab loses focus with the pick screen up
	main._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	check(main.pick_screen.is_shown() and get_paused(), "the tab losing focus over the pick screen changes nothing")
	main._on_pick_chosen(0)
	check(not main.pick_screen.is_shown() and not get_paused() and not main._picking, "choosing a card closes the pick screen and resumes")
	main._begin_pick()
	main._end_run(main.HEADER_CRASH, main.REASON_OBSTACLE)   # (a hit can never come while paused, but make sure a menu closes it)
	main._open_hangar()
	check(sa_names.call([]) == "hangar" and not get_paused() and not main._picking, "a menu opening over a pick screen closes it and unpauses [%s]" % sa_names.call([]))
	main._show_menu()
	main.hud.play_pressed.emit()
	main.picks.enabled = false
	# the tab losing focus mid-run: the world stands still and the audio is muted
	var sa_t0: float = main.elapsed
	main._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	main._process(0.016)
	main._process(0.016)
	check(main._suspended and AudioServer.is_bus_mute(0) and main.elapsed == sa_t0, "focus lost mid-run: the sim stands still and the sound is muted")
	main._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not main._suspended and not AudioServer.is_bus_mute(0), "focus back: sound is back")
	# the tuning panel
	main.tune_panel.open()
	check(sa_names.call([]) == "tune" and get_paused(), "the tuning panel shows alone and pauses the game")
	main.tune_panel.close()
	check(sa_names.call([]) == "" or sa_names.call([]) == "airstrip", "...and closing it leaves nothing behind [%s]" % sa_names.call([]))
	# the goal gates and the airstrip never survive into a menu
	main.goals.prewarm_show(1.0)
	main.ground.start_airstrip(1.0)
	main._show_menu()
	check(sa_names.call([]) == "menu", "goal gates and the airstrip are gone behind the start screen [%s]" % sa_names.call([]))
	main.hud.play_pressed.emit()
	main.set_process(false)
	sa_save.reset_all()

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://smoke_test_save.json"))
	print("")
	if failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		print("SMOKE TEST FAILED: %d check(s)" % failures.size())
		quit(1)
