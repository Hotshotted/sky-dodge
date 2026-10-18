extends Node
## Every "feel" value of the game lives here, in one place.
## Registered as the autoload `Tuning`, so any script can read `Tuning.some_value`.
## They are plain vars (not consts) so a future on-screen tuning panel can edit them live.
## Distances are world units. The camera looks (almost) straight down: screen-right = +x,
## screen-down = +z, and the plane flies toward -z (screen-up).

# ---------- Camera / screen ----------
## Camera tilt away from straight-down, in degrees, so cube front faces (toward the bottom of
## the screen) show and shade. 0 = exactly top-down.
var camera_tilt_deg := 12.0
## World units visible across the screen WIDTH (orthographic camera size, width locked).
## The visible height follows from the device aspect ratio (about 17.8 units on 9:16).
var ortho_size := 10.0

# ---------- Hidden columns ----------
## Number of hidden columns across the screen width (never shown to the player).
var column_count := 5
## Obstacle width as a fraction of a column. Collision uses the visible size (cube + outline), so
## smaller = wider gaps. 0.6 keeps one-column corridors passable now the hitbox matches the wings.
var obstacle_scale := 0.6
## Obstacle length along the flight direction (z).
var obstacle_depth := 1.4

# ---------- Forward speed ----------
## Scroll speed at the start of a run (units/second).
## It climbs by speed_ramp each second until max_speed: (26 - 7) / 0.2 = 95 s to reach top speed.
var base_speed := 7.0
## How much scroll speed grows each second.
var speed_ramp := 0.10
## Scroll speed never exceeds this.
var max_speed := 26.0

# ---------- Obstacle spawning ----------
## Distance between spawn rows (units). Bigger = more time to react.
var spawn_spacing := 10.0
## How many columns each row blocks (random between min and max, inclusive).
## A row always keeps at least one open column, so max is clamped to column_count - 1.
var blocked_columns_min := 2
var blocked_columns_max := 3
## A new row is created once the last one has scrolled past -spawn_distance (must be above the
## top of the screen, ~9-11 units on phones).
var spawn_distance := 24.0
## The opening: the first row of a run reaches the plane after about this many seconds, at the
## start speed and ramp. (It never starts on screen: on a very tall phone it begins just above the
## top edge instead, so it can take a little longer there.)
var opening_seconds := 2.0

# ---------- Obstacle look ----------
## Obstacle colour (single colour; outlines separate overlapping shapes).
var obstacle_color := Color(1.0, 0.3, 0.12)
## Black outline width around each obstacle, in world units.
var outline_thickness := 0.07
## Direction the sun's light travels. The camera sees top and front faces; this lights the
## top brightest and the front a clearly different, darker tone.
var light_direction := Vector3(0.3, -0.8, -0.5)

# ---------- Fuel ----------
## Starting fuel, which is also the size of the tank (refills never go above it).
var fuel_start := 100.0
## Fuel burned per second. With no cans at all a run lasts fuel_start / fuel_drain seconds (29 s).
## Balance check (tests/fuel_balance_sim.gd, autopilots, 12 runs each): a player who only flies the
## widest gaps ran dry at 29 s every time; random gaps median 41 s; a can-chasing player's lowest fuel
## averaged ~38 and 9 of 12 runs ended on an obstacle, 3 on fuel (can chance 0.18: 1 of 12).
var fuel_drain := 6.5
## Fuel one can gives back.
var fuel_refill := 20.0
## Chance (0-1) that a new row gets a fuel can (rows with no risky spot get none).
var fuel_can_chance := 0.18
## How strongly cans prefer RISKY spots (0-1). A can is placed in a risky spot with this
## probability, otherwise in any open column. Risky = off the main safe path AND either next to an
## obstacle or in a column that closes in the next row. Cans are never put on the main safe path
## when this is 1, so only taking the safe gaps never refuels.
var fuel_risk_bias := 0.95
## Can size (cube edge) and how close the plane must get to its centre to collect it.
var fuel_can_size := 0.8
var fuel_pickup_radius := 0.75
## Pickup burst: particles, and the gauge flashes below this fraction of the tank.
var fuel_pop_count := 14
var fuel_low_fraction := 0.25
var fuel_can_color := Color(0.2, 0.95, 0.45)

# ---------- Clouds (hide obstacles and fuel cans) ----------
## No clouds until the run has lasted this many seconds (the first rows with clouds then appear a
## few seconds later, since rows are made ahead of the screen).
var cloud_start_time := 20.0
## Free-floating cloud bundles created per row, measured at the speed the run has when clouds begin
## (they come up to 3x as often at top speed). Sizes run from small wisps to large banks.
var cloud_frequency := 0.4
## Reveal: a cloud is nearly opaque (cloud_max_opacity) while it is farther than this many units
## above the plane, then fades as it approaches, so what is under it shows up late...
var cloud_reveal_distance := 12.0
## ...down to this opacity (0 = invisible, 1 = solid) when it reaches the plane, and it stays that
## faint as it passes.
var cloud_min_opacity := 0.2
var cloud_max_opacity := 0.95
## Sideways drift of a bundle: up to this many units sideways per unit it scrolls (either direction).
var cloud_max_drift := 0.12
## Chance that a row with cloud over some of its open columns gets a fuel can UNDER the cloud (off the
## safe path), on top of the normal fuel_can_chance. Entering a cloud blind can pay off.
var fuel_can_under_cloud_chance := 0.45
var cloud_color := Color(1.0, 1.0, 1.0)

# ---------- Economy: score is coins ----------
## Coins per world unit flown, before the close-call bonus, the map multiplier and Coin Value. The run
## total on screen IS the coins you earn (a crash keeps them all).
var coins_per_unit := 1.0
## Multiplier on everything earned, per map (Countryside, Coast, Mountains, Stormfront).
var map_coin_mult: Array[float] = [1.0, 2.0, 4.0, 8.0]

## Distance shown to the player in meters = world units x this (maps unlock at 3,000 m / 4,000 m / 5,000 m).
var meters_per_unit := 5.0

## EARNINGS upgrades have no cap and double their effect at every Nth level (25, 50, 75 ...).
var double_every := 25
## Costs: EARNINGS cost base * earn_cost_growth^level, PLANE upgrades base * plane_cost_growth^level.
var earn_cost_growth := 1.12
var plane_cost_growth := 1.5
## Gear slots: the first is free; buying the others is a milestone. Cost of slot 2 and slot 3.
var gear_slot_costs: Array[float] = [0.0, 40000.0, 2500000.0]
## Reserve Tank refills the tank to this fraction of its size.
var reserve_refill_fraction := 0.6
## Nine Lives: after a survived hit the plane is invulnerable (sputtering) for this many seconds.
var hit_invulnerable_time := 1.6
## Magnet: cans inside the radius fly toward the plane at this speed (units/second).
var magnet_pull_speed := 16.0

## THE UPGRADE TABLE: one place for every upgrade. Fields:
##   id, tab (earnings / plane / gear), name, glyph + color (the placeholder icon), line (the one-line
##   description; {a} = now, {b} = next level, {d} = the difference), fmt (how numbers show),
##   max (levels; -1 = endless), cost_base (earnings and plane), costs (gear: the price of each level),
##   per / falloff (the effect per level; plane upgrades shrink by `falloff` each level),
##   steps (gear: the value at level 0, 1, 2 ...).
var upgrades: Array[Dictionary] = [
	{"id": "coin_value", "tab": "earnings", "name": "Coin Value", "glyph": "$", "color": Color(1.0, 0.8, 0.2),
			"line": "Every coin worth more: {a} -> {b}", "fmt": "x", "max": -1, "cost_base": 400.0, "per": 0.10},
	{"id": "can_bounty", "tab": "earnings", "name": "Can Bounty", "glyph": "C", "color": Color(0.35, 0.85, 0.45),
			"line": "Each fuel can pays {a} -> {b} coins", "fmt": "big", "max": -1, "cost_base": 600.0, "per": 8.0},
	{"id": "close_call_pay", "tab": "earnings", "name": "Close Call Pay", "glyph": "!", "color": Color(1.0, 0.55, 0.2),
			"line": "Each close call pays {a} -> {b} coins", "fmt": "big", "max": -1, "cost_base": 800.0, "per": 4.0},
	{"id": "bonus_cap", "tab": "earnings", "name": "Bonus Cap", "glyph": "^", "color": Color(1.0, 0.4, 0.6),
			"line": "Close-call bonus can reach {a} -> {b}", "fmt": "x1", "max": -1, "cost_base": 1200.0, "per": 0.5},
	{"id": "fuel_tank", "tab": "plane", "name": "Fuel Tank", "glyph": "F", "color": Color(0.3, 0.7, 1.0),
			"line": "Hold {d} more fuel ({a} -> {b})", "fmt": "int", "max": 12, "cost_base": 80.0, "per": 15.0, "falloff": 0.92},
	{"id": "efficiency", "tab": "plane", "name": "Efficiency", "glyph": "E", "color": Color(0.4, 0.9, 0.8),
			"line": "Burn fuel slower: {a}/s -> {b}/s", "fmt": "dec1", "max": 10, "cost_base": 100.0, "per": 0.06, "falloff": 0.9},
	{"id": "refill", "tab": "plane", "name": "Refill", "glyph": "R", "color": Color(0.6, 0.8, 0.3),
			"line": "Each can gives {d} more fuel ({a} -> {b})", "fmt": "dec1", "max": 12, "cost_base": 120.0, "per": 4.0, "falloff": 0.92},
	{"id": "nine_lives", "tab": "gear", "name": "Nine Lives", "glyph": "9", "color": Color(1.0, 0.35, 0.35),
			"line": "Survive hits per run: {a} -> {b}", "fmt": "int", "max": 3, "costs": [2000.0, 60000.0, 2400000.0], "steps": [0, 1, 2, 3]},
	{"id": "reserve_tank", "tab": "gear", "name": "Reserve Tank", "glyph": "T", "color": Color(0.5, 0.6, 1.0),
			"line": "Refill the tank when empty: {a} -> {b} times", "fmt": "int", "max": 2, "costs": [3000.0, 120000.0], "steps": [0, 1, 2]},
	{"id": "magnet", "name": "Can Magnet", "tab": "gear", "glyph": "M", "color": Color(0.8, 0.5, 1.0),
			"line": "Pull cans from {a} -> {b} units away", "fmt": "dec1", "max": 3, "costs": [1500.0, 45000.0, 1800000.0], "steps": [0.0, 1.5, 2.5, 3.5]},
	{"id": "cloud_eye", "tab": "gear", "name": "Cloud Eye", "glyph": "O", "color": Color(0.8, 0.9, 1.0),
			"line": "Outlines show obstacles under clouds: {a} -> {b}", "fmt": "onoff", "max": 1, "costs": [5000.0], "steps": [0, 1]},
	{"id": "steady_nerves", "tab": "gear", "name": "Steady Nerves", "glyph": "S", "color": Color(0.95, 0.75, 0.5),
			"line": "A hit keeps {a} -> {b} of your close-call bonus", "fmt": "pct", "max": 2, "costs": [4000.0, 120000.0], "steps": [0.0, 0.5, 1.0]},
	{"id": "head_start", "tab": "gear", "name": "Head Start", "glyph": "H", "color": Color(1.0, 0.9, 0.3),
			"line": "Begin each run at bonus {a} -> {b}", "fmt": "x1", "max": 2, "costs": [2500.0, 75000.0], "steps": [1.0, 1.5, 2.0]},
]

func upgrade_def(id: String) -> Dictionary:
	for u in upgrades:
		if u["id"] == id:
			return u
	return {}

func upgrades_in_tab(tab: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in upgrades:
		if u["tab"] == tab:
			out.append(u)
	return out

## Levels an upgrade has (-1 = no end).
func max_level(id: String) -> int:
	return int(upgrade_def(id)["max"])

## EARNINGS effects double at every `double_every`th level: 2 ^ (level / 25).
func doubling(level: int) -> float:
	return pow(2.0, floor(float(level) / double_every))

## Sum of per * falloff^i for i < level (each level of a PLANE upgrade gives a bit less).
func _diminishing(per: float, falloff: float, level: int) -> float:
	var total := 0.0
	var step := per
	for i in level:
		total += step
		step *= falloff
	return total

## The stat an upgrade controls at a level (what the game uses, and what the Hangar shows).
func upgrade_value(id: String, level: int) -> float:
	var u := upgrade_def(id)
	var m := int(u["max"])
	var l := level if m < 0 else clampi(level, 0, m)
	match id:
		"coin_value":
			return 1.0 + u["per"] * l * doubling(l)
		"can_bounty", "close_call_pay":
			return u["per"] * l * doubling(l)
		"bonus_cap":
			return bonus_cap + u["per"] * l * doubling(l)
		"fuel_tank":
			return fuel_start + _diminishing(u["per"], u["falloff"], l)
		"efficiency":
			return fuel_drain * (1.0 - _diminishing(u["per"], u["falloff"], l))
		"refill":
			return fuel_refill + _diminishing(u["per"], u["falloff"], l)
	return float(u["steps"][l])   # gear

## The price of the next level (going from `level` to level + 1).
func upgrade_cost(id: String, level: int) -> float:
	var u := upgrade_def(id)
	match u["tab"]:
		"earnings":
			return ceil(float(u["cost_base"]) * pow(earn_cost_growth, level))
		"plane":
			return ceil(float(u["cost_base"]) * pow(plane_cost_growth, level))
	return float(u["costs"][mini(level, u["costs"].size() - 1)])

## Big numbers everywhere: 999, 1.2K, 45K, 3.1M, 2.4B, 1.1T ...
func fmt(n: float) -> String:
	const UNITS := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]
	var neg := n < 0.0
	var v := floorf(absf(n) + 0.0000001)
	var i := 0
	while v >= 1000.0 and i < UNITS.size() - 1:
		v /= 1000.0
		i += 1
	var out := ""
	if i == 0:
		out = "%d" % int(v)
	else:
		out = ("%.1f" % v) if v < 10.0 else ("%d" % int(round(v)))
		if out == "1000" and i < UNITS.size() - 1:   # 999.96K rounds up to a whole next unit
			out = "1"
			i += 1
		if out.ends_with(".0"):
			out = out.substr(0, out.length() - 2)
		out += UNITS[i]
	return ("-" if neg else "") + out

func _fmt_val(kind: String, v: float) -> String:
	match kind:
		"int":
			return "%d" % int(round(v))
		"dec1":
			return "%.1f" % v
		"big":
			return fmt(v)
		"x":
			return "x%.2f" % v
		"x1":
			return "x%.1f" % v
		"pct":
			return "%d%%" % int(round(v * 100.0))
		"onoff":
			return "on" if v > 0.5 else "off"
	return str(v)

## The one plain-language line for an upgrade at `level`: current -> next ("Hold 15 more fuel (100 -> 115)").
func upgrade_line(id: String, level: int) -> String:
	var u := upgrade_def(id)
	var m := int(u["max"])
	var maxed := m >= 0 and level >= m
	var a := upgrade_value(id, level)
	var b := a if maxed else upgrade_value(id, level + 1)
	var out: String = u["line"]
	out = out.replace("{a}", _fmt_val(u["fmt"], a)).replace("{b}", _fmt_val(u["fmt"], b)).replace("{d}", _fmt_val(u["fmt"], absf(b - a)))
	if maxed:
		out += "  (MAX)"
	elif u["tab"] == "earnings" and (level + 1) % int(double_every) == 0:
		out += "  Milestone: doubles!"
	return out

## What the game uses, upgrades included (the plain tuning values are the level-0 numbers).
func fuel_max() -> float:
	return upgrade_value("fuel_tank", Save.level("fuel_tank"))

func drain_rate() -> float:
	return upgrade_value("efficiency", Save.level("efficiency"))

func refill_amount() -> float:
	return upgrade_value("refill", Save.level("refill"))

func bonus_cap_now() -> float:
	return upgrade_value("bonus_cap", Save.level("bonus_cap"))

func coin_value_mult() -> float:
	return upgrade_value("coin_value", Save.level("coin_value"))

func can_bounty_pay() -> float:
	return upgrade_value("can_bounty", Save.level("can_bounty"))

func close_call_pay() -> float:
	return upgrade_value("close_call_pay", Save.level("close_call_pay"))

## Gear only counts while it is equipped in an unlocked slot.
func gear_value(id: String) -> float:
	return upgrade_value(id, Save.gear_level(id))

func pickup_reach() -> float:
	return gear_value("magnet")

# ---------- Near miss & bonus ----------
## A row counts as a near miss if the plane passed it with less than this gap (units) between the
## plane's hit box and the closest obstacle edge (0 = touching = crash).
var near_miss_distance := 0.30
## A close call with this much clearance or less is a "Whisker close": the step it earns is doubled
## (a +0.3 step becomes +0.6; the streak still advances one step, and decay removes the doubled amount).
## It gets its own bigger popup (colour and size below) and a gold burst.
var whisker_close_distance := 0.10
var whisker_text := "Whisker close!"
var whisker_color := Color(1.0, 0.3, 0.85)
var whisker_size := 124
## The points bonus grows with the streak of close calls. Each close call in the streak adds the next
## entry of bonus_steps, and every close call after the table runs out adds bonus_step_tail:
##   bonus = 1 + (sum of the steps earned), never above bonus_cap.
## With the defaults: x1.5, x1.9, x2.2, x2.4, x2.5, then +0.1 each (x2.6, x2.7 ... the cap at 10 in a row).
var bonus_steps: Array[float] = [0.5, 0.4, 0.3, 0.2, 0.1]
var bonus_step_tail := 0.1
## The bonus ceiling (an upgrade will raise it later). The streak is held at the value that just
## reaches it, so the bonus starts easing down as soon as the timeout ends.
var bonus_cap := 3.0
## Seconds after a close call before the streak starts to drop.
var bonus_hold_time := 4.0
## Once dropping, steps come off one at a time, the most recent first, this many per second
## (x2.6 -> x2.5 -> x2.4 -> x2.2 ...), down to x1.
var bonus_decay_rate := 0.8
## Looks only: colours and the score swell stop growing at this bonus, so a very high cap can't break the layout.
var bonus_visual_max := 6.0
var bonus_gold := Color(1.0, 0.84, 0.15)   # the label and score at the cap
## If true, score accrues at (distance x bonus); if false, the bonus is cosmetic.
var score_uses_bonus := true

# ---------- Near-miss feedback ----------
## Sparks in the burst from the wingtip nearest the obstacle (kept small: cheap on phones),
## and how long each lives (seconds).
var spark_count := 14
var spark_lifetime := 0.45
## Speed streaks flashed past the plane (max 24), and their speed (units/second).
var streak_count := 6
var streak_speed := 70.0
## How long the passed obstacle's outline stays white (seconds).
var near_miss_flash_time := 0.25
## Haptic pulse length in milliseconds (ignored where unsupported).
var haptic_ms := 25
## Near-miss popup tiers: the first applies below the first value of near_miss_tier_bonus, the second
## from it up to the next, the last from the final value up. A popup shows only the new bonus number
## ("x1.9"); the tier sets its colour (warmer each tier) and font size (px in the 1080-wide base viewport).
var near_miss_tier_bonus: Array[float] = [2.0, 2.8]
var near_miss_colors: Array[Color] = [Color(1.0, 0.95, 0.55), Color(1.0, 0.62, 0.2), Color(1.0, 0.28, 0.12)]
var near_miss_sizes: Array[int] = [64, 84, 108]
## Trail ribbon colour per bonus tier (x1-x2, x2-x3, x3-x4, x4+); it shows while there is a bonus and fades at x1.
var trail_colors: Array[Color] = [Color(0.5, 0.9, 1.0), Color(0.5, 1.0, 0.6), Color(1.0, 0.85, 0.3), Color(1.0, 0.4, 0.7)]
var trail_width := 0.5
## How far behind the plane the trail reaches (units), and how long it takes to fade out.
var trail_length := 12.0
var trail_fade_time := 0.6

# ---------- Start-up pre-warm (splash screen) ----------
## At boot every effect is drawn for real behind a splash screen so shaders, buffers and font
## glyphs are set up before play. Phones may compile shaders in the background, so it keeps going
## until frame times settle. It never ends before this many seconds...
var prewarm_min_seconds := 1.5
## ...ends when this many frames in a row each took less than this many milliseconds...
var prewarm_stable_frames := 10
var prewarm_stable_ms := 45.0
## ...and never runs longer than this, whatever the frame times are.
var prewarm_max_seconds := 6.0

# ---------- Plane movement (relative drag, 1:1, no momentum) ----------
## The plane follows the finger directly: every frame it moves by how far the finger moved,
## converted to world units. No acceleration, no damping, no carry after the finger stops.
## 1.0 = the plane moves exactly as far across the screen as the finger does; 2.0 = twice as far.
var sensitivity := 1.0
## Visual polish only: seconds the DRAWN plane takes to catch up with its true position (0 = none,
## exactly on the finger). Collision always uses the true position, so keep this tiny.
var visual_smoothing := 0.0
## Plane stays this far (units) inside the left/right screen edges (wing half-width is 1.1).
var plane_edge_margin := 1.1
## Forward/back range: the plane may use the bottom this fraction of the screen height.
var plane_zone_fraction := 0.4
## Gap (units) kept between the plane and the bottom screen edge.
var plane_bottom_margin := 1.5

# ---------- Soft snap (after the finger lifts, sideways only) ----------
## On: once the finger lifts, the plane eases sideways to the nearest column centre. Off by default.
var snap_enabled := false
## How fast it eases when snap is on (higher = quicker; 7 is about a third of a second).
var snap_strength := 7.0

# ---------- Visual banking ----------
## Roll (radians) per unit of sideways velocity (the plane's actual velocity, from how far it moved).
var bank_amount := 0.06
## Yaw (radians): nose turns toward the sideways motion, so banking reads from above.
var yaw_amount := 0.025
## The most the plane may roll / yaw, in radians, however hard it is flicked.
var bank_max := 0.9
var yaw_max := 0.45
## How quickly the visual tilt follows (higher = snappier).
var tilt_smoothing := 10.0

# ---------- Collision ----------
## The plane's collision is built from its visible parts: the wing (a tapered outline with round
## tips, as a row of circles that follow the chord) and the fuselage (one rounded capsule). The span
## and length match the visible plane, but the tips are rounded off so a wingtip grazing a cube
## corner usually survives. Obstacles collide as their visible cube + outline.
## Wing tips: radius (units) of the round tip of the tapered wing. The visible wing and its
## collision are both built from this one outline, so they always match. Small (0.05) = a pointed
## taper that is easy to clip; large = a blunt, round tip; 0.35 = the full chord (a stadium).
## A rounder tip also cuts away more of the corner, so a wingtip grazing a cube corner is
## more likely to slip past.
var plane_tip_radius := 0.22
## Fuselage rounding: radius of its rounded nose and tail (capped at the body's half width, 0.225).
var plane_hit_radius := 0.3
## Capsule size as a fraction of the visible parts. 0.95 = a little forgiveness on top.
var plane_hit_scale := 0.95

# ---------- Helpers ----------
## Index into a per-tier array for a bonus: below x2 -> 0, x2 -> 1, x3 -> 2, ... clamped to the array.
func tier_index(bonus: float, count: int) -> int:
	return clampi(int(bonus) - 1, 0, count - 1)

## The points bonus for a streak of `n` close calls: 1 + the first n steps (then the tail step each).
func streak_bonus(n: int) -> float:
	var total := 1.0
	for i in maxi(n, 0):
		total += bonus_steps[i] if i < bonus_steps.size() else bonus_step_tail
	return clampf(total, 1.0, maxf(bonus_cap_now(), 1.0))

## The bonus step the (index+1)th close call of a streak earns (before any Whisker doubling).
func step_for(index: int) -> float:
	return bonus_steps[index] if index < bonus_steps.size() else bonus_step_tail

## The bonus for a sum of earned steps, clamped to the cap.
func bonus_for_sum(total: float) -> float:
	return clampf(1.0 + total, 1.0, maxf(bonus_cap_now(), 1.0))

## The smallest streak that reaches the cap (the streak is never counted above it, so the bonus
## starts easing down as soon as the hold time ends).
func streak_at_cap() -> int:
	var need := bonus_cap_now() - 1.0
	if need <= 0.0:
		return 0
	var sum := 0.0
	for i in bonus_steps.size():
		sum += bonus_steps[i]
		if sum >= need - 0.000001:
			return i + 1
	if bonus_step_tail <= 0.0:
		return bonus_steps.size()
	return bonus_steps.size() + int(ceil((need - sum) / bonus_step_tail - 0.000001))

## The text of a popup / the label: just the number.
func popup_text(bonus: float) -> String:
	return "x%.1f" % bonus

## Is there a bonus worth showing? (The label disappears as the bonus eases down to x1.)
func bonus_active(bonus: float) -> bool:
	return bonus >= 1.05

func at_cap(bonus: float) -> bool:
	return bonus_cap_now() > 1.0 and bonus >= bonus_cap_now() - 0.001

## Which popup tier (index into near_miss_sizes / near_miss_colors) a bonus belongs to.
func popup_tier(bonus: float) -> int:
	var t := 0
	for thr in near_miss_tier_bonus:
		if bonus >= thr:
			t += 1
	return mini(t, near_miss_sizes.size() - 1)

## Colour for a bonus: warms along near_miss_colors up to bonus_visual_max, gold at the cap.
func bonus_color(bonus: float) -> Color:
	if at_cap(bonus):
		return bonus_gold
	var t := clampf((bonus - 1.0) / maxf(bonus_visual_max - 1.0, 0.1), 0.0, 1.0) * (near_miss_colors.size() - 1)
	var i := mini(int(t), near_miss_colors.size() - 2)
	return near_miss_colors[i].lerp(near_miss_colors[i + 1], t - i)

## How much bigger the score is drawn at this bonus (clamped at bonus_visual_max).
func bonus_swell(bonus: float) -> float:
	return 1.0 + 0.06 * (minf(bonus, bonus_visual_max) - 1.0)

func column_width() -> float:
	return ortho_size / column_count

## World x of the centre of column i (0 = leftmost).
func column_center(i: int) -> float:
	return (i - (column_count - 1) * 0.5) * column_width()
