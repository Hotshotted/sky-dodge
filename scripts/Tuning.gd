extends Node
## Every "feel" value of the game lives here, in one place.
## Registered as the autoload `Tuning`, so any script can read `Tuning.some_value`.
## They are plain vars (not consts) so a future on-screen tuning panel can edit them live.
## Distances are world units. The camera looks (almost) straight down: screen-right = +x,
## screen-down = +z, and the plane flies toward -z (screen-up).

# ---------- Frame time ----------
## The simulation never advances more than this per frame (seconds), whatever the real frame took.
var max_frame_delta := 0.05
## A frame longer than this (a tab switch, a long hitch) is a stall: it is not simulated at all.
var stall_delta := 0.25
## Frames skipped (no simulation) after a pick, a stall or the window coming back, so nothing catches up.
var resume_skip_frames := 2

# ---------- Camera / screen ----------
## Camera tilt away from straight-down, in degrees, so cube front faces (toward the bottom of
## the screen) show and shade. 0 = exactly top-down.
var camera_tilt_deg := 12.0
## World units visible across the screen WIDTH (orthographic camera size, width locked).
## The visible height follows from the device aspect ratio (about 17.8 units on 9:16).
var ortho_size := 12.0

# ---------- Hidden columns ----------
## Number of hidden columns across the screen width (never shown to the player).
var column_count := 7
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
## Countryside: speed does not ramp. It steps up by speed_step once per wave cycle, while a BREATHER passes the plane
## (eased in at speed_step_rate units/s per second), toward max_speed: (26 - 7) / 3.2 = 6 steps, about 4.5 minutes.
var speed_step := 3.2
## The Countryside's steps are small at first and grow: step n adds speed_step_table[n-1] (then the last entry), up to max_speed.
var speed_step_table: Array[float] = [2.0, 2.5, 3.0, 3.5, 4.0, 4.5]
var speed_step_rate := 2.0

# ---------- Obstacle spawning ----------
## Distance between spawn rows (units). Bigger = more time to react.
var spawn_spacing := 10.0
## How many columns each row blocks (random between min and max, inclusive).
## A row always keeps at least one open column, so max is clamped to column_count - 1.
var blocked_columns_min := 3
var blocked_columns_max := 4
## A new row is created once the last one has scrolled past -spawn_distance (must be above the
## top of the screen, ~9-11 units on phones).
var spawn_distance := 24.0
## The opening: the first row of a run reaches the plane after about this many seconds, at the
## start speed and ramp. (It never starts on screen: on a very tall phone it begins just above the
## top edge instead, so it can take a little longer there.)
var opening_seconds := 3.0

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

# ---------- Countryside obstacle kit ----------
## Windmill blades turn this fast (radians/second) and reach this far from the hub (units).
## Windmills come in three variants [standard, large, small]: blades (count), blade length (from the hub), blade half width,
## turning speed (radians/second) and hub radius. The standard and large ones span most of the lane.
var windmill_blades: Array[int] = [4, 3, 2]
var windmill_blade: Array[float] = [3.4, 3.8, 1.9]
var windmill_width: Array[float] = [0.3, 0.36, 0.22]
var windmill_speed: Array[float] = [1.2, 0.4, 3.2]
var windmill_hub: Array[float] = [0.85, 1.0, 0.6]
## Barn: the doorway between the walls is this wide (the plane is about 2.3 wide); flying through is a "Barnstormer!".
var barn_door_width := 3.2
var barnstormer_text := "Barnstormer!"
var barnstormer_color := Color(1.0, 0.55, 0.15)
## Tractor: drives sideways at tractor_speed, starts tractor_lead units before the top of the screen after a dust plume of
## tractor_telegraph seconds, and drops a bale every tractor_drop_every seconds (tractor_drops at most).
var tractor_speed := 2.6
var tractor_telegraph := 1.0
var tractor_lead := 10.0
var tractor_drop_every := 0.9
var tractor_drops := 4
## Crows: they hover at the top edge for crow_telegraph seconds (flapping, in view), then swoop toward where the
## plane IS at that moment at crow_speed (units/second) and fly straight on: never homing after the swoop starts.
var crow_telegraph := 1.0
var crow_speed := 11.0
## Crop duster: an arrow at the screen edge for duster_telegraph seconds, then the plane crosses at duster_speed.
var duster_telegraph := 1.5
## ...the edge it comes from glows red, a faint red line marks its row, until it enters. The pattern checker gives the plane
## duster_react seconds of human reaction time after the warning starts.
var duster_react := 0.4
var duster_speed := 9.0
## Balloons drift sideways (amplitude units, angular speed); kites wiggle the same way, smaller and quicker.
var balloon_amp := 2.2
var balloon_rate := 0.55
var kite_amp := 0.9
var kite_rate := 1.6
## Patterns: chance that a can slot of a pattern row gets a can, and the factor that turns crate_chance into the chance of a
## hay bale in each hay slot (0.10 x 4 = 0.4).
var pattern_can_chance := 0.3
## Coin trails: what a coin of a pattern's trail pays into the run score (x the run's coin multiplier), and how close the
## plane has to be to collect it (a bit more generous than the coin itself).
var trail_coin_value := 3.0
var coin_pickup_radius := 0.5
var hay_slot_factor := 4.0
## Intensity waves (Countryside): CALM -> BUILD -> PEAK -> BREATHER, repeating. Per phase: how long it lasts (seconds),
## the pattern difficulty range it draws from, and how many cans / hay bales its slots give (a multiplier). Every finished
## cycle adds wave_rise to the difficulty range of CALM, BUILD and PEAK (the BREATHER stays almost empty).
var wave_seconds: Array[float] = [14.0, 14.0, 12.0, 4.0]
var wave_diff_lo: Array[float] = [1.0, 2.0, 3.0, 1.0]
var wave_diff_hi: Array[float] = [2.0, 3.0, 4.0, 1.0]
var wave_rise := 0.5
var wave_can: Array[float] = [1.8, 1.0, 0.6, 2.5]
var wave_hay: Array[float] = [1.8, 1.0, 0.5, 2.5]

# ---------- World and pacing ----------
## Takeoff from Rusty's airstrip: the plane lifts off over this many seconds at the start of a run.
var takeoff_seconds := 2.2
## The opening of a Countryside run (its first opening_seconds): easy but busy. Only the "opening" patterns and the easy ones next
## to them (difficulty up to opening_max_diff by the end of the opening), no empty stretches between: plenty of obstacles
## and rewards, wide gaps, more than one route through each. The "opening" patterns are favoured by opening_weight.
var gentle_seconds := 60.0
var gentle_max_diff := 2.2
var opening_weight := 3.0
## Time of day: morning at the start of a run, midday-ish (the map's own look), sunset, then dusk, over tod_seconds.
var tod_seconds := 300.0
## Per keyframe (morning, day, sunset, dusk): the colour the sky and ambient light are pulled toward, how far, the sun's
## colour and strength, and the ambient strength.
var tod_stops: Array[float] = [0.0, 0.35, 0.7, 1.0]
var tod_tint: Array[Color] = [Color(1.0, 0.82, 0.62), Color(1.0, 1.0, 1.0), Color(0.95, 0.4, 0.22), Color(0.16, 0.12, 0.3)]
var tod_mix: Array[float] = [0.22, 0.0, 0.5, 0.7]
var tod_sun: Array[Color] = [Color(1.0, 0.9, 0.75), Color(1.0, 1.0, 1.0), Color(1.0, 0.6, 0.35), Color(0.55, 0.55, 0.95)]
var tod_sun_energy: Array[float] = [0.9, 1.0, 0.85, 0.45]
var tod_ambient_energy: Array[float] = [0.45, 0.45, 0.4, 0.3]

# ---------- Background readability ----------
## The countryside is told apart from the obstacles by colour only: muted, desaturated, pulled toward the haze, with soft
## faded edges. (The obstacles in front keep saturated colours and black outlines.)
var ground_haze := 0.62                # how far the ground colours are pulled toward the haze (1 = all haze)
var ground_saturation := 0.5           # colour strength of the ground (1 = natural)
## Shadows on the ground. Things standing on the ground (barns, windmills, power lines, tractors, hay) get a contact shadow
## directly beneath them. Flying things (the plane, crows, balloons, kites, the crop duster, fuel cans) cast a shadow offset
## toward the bottom of the screen by their altitude x shadow_per_altitude, so they read as airborne.
var shadow_alpha := 0.34
var shadow_per_altitude := 0.14
var shadow_grow := 1.3                 # a flying thing's shadow is this much bigger than it (a contact shadow only 1.08)
## The altitude of each kit thing above the ground, in the order of Kit.NAMES (0 = it stands on the ground).
var shadow_altitude: Array[float] = [0.0, 0.0, 0.0, 2.4, 3.0, 0.0, 2.4, 3.0, 0.0]
var shadow_altitude_can := 2.0         # a fuel can
var shadow_altitude_cube := 1.5        # the plain floating cubes of the other maps

# ---------- Speed cues ----------
## Every source of a speed change shows itself on screen. The audit (see the smoke test): Tailwind (perk), the BREATHER
## steps of the Countryside, the continuous ramp of the other maps (cued in tiers of speed_step), and each map's speed
## multiplier (cued when the run starts). Boosts, supplies, combos and gear change no speed; the test fails if one ever
## mentions speed without being listed here.
var speed_cue_sources: Array[String] = ["tailwind", "breather_step", "map_ramp", "map_multiplier"]
var speed_up_text := "SPEED UP"
var speed_up_color := Color(0.55, 0.9, 1.0)
var tailwind_color := Color(0.5, 0.8, 1.0)
var whoosh_seconds := 1.2          # the wind rush when a speed step begins
var wind_streaks := 10             # streaks flowing past the plane while Tailwind is held (pool: Fx.WIND_POOL)
var perk_pulse_seconds := 0.45     # a held perk's HUD icon pulses this long when it applies

# ---------- Maps ----------
## Four maps, each a separate run chosen on the start screen. Fields: id, name, unlock_from (the map whose
## best distance unlocks it, -1 = open) and unlock_meters, coin multiplier (map_coin_mult, below), the
## difficulty curve (speed_mult scales the start and top speed, ramp_mult the climb, blocked_add adds
## blocked columns per row), the obstacle/hazard mix (gull_share = share of obstacles that are drifting
## gulls, gust_chance = chance a gap between two rows gets a wind gust, lightning_interval = seconds
## between lightning strikes at the start of a run, 0 = none), cloud_mult (how many clouds), the palette
## (sky, ground, stripe, obstacle, cloud, ambient), and the medals: [distance in meters, coin reward].
var maps: Array[Dictionary] = [
	{"id": "countryside", "name": "Countryside", "unlock_from": -1, "unlock_meters": 0.0,
			"speed_mult": 1.0, "ramp_mult": 1.0, "blocked_add": 0, "gull_share": 0.0, "gust_chance": 0.0, "lightning_interval": 0.0, "cloud_mult": 1.0,
			"sky": Color(0.2, 0.26, 0.34), "ground": Color(0.2, 0.26, 0.34), "stripe": Color(0.3, 0.38, 0.5),
			"obstacle": Color(1.0, 0.3, 0.12), "cloud": Color(1.0, 1.0, 1.0), "ambient": Color(0.75, 0.78, 0.9),
			"medals": [[1500.0, 3000.0], [3000.0, 20000.0], [6000.0, 120000.0]]},
	{"id": "coast", "name": "Coast", "unlock_from": 0, "unlock_meters": 3000.0,
			"speed_mult": 1.1, "ramp_mult": 1.1, "blocked_add": 0, "gull_share": 0.5, "gust_chance": 0.0, "lightning_interval": 0.0, "cloud_mult": 1.0,
			"sky": Color(0.16, 0.36, 0.5), "ground": Color(0.1, 0.42, 0.56), "stripe": Color(0.3, 0.62, 0.74),
			"obstacle": Color(1.0, 0.45, 0.2), "cloud": Color(1.0, 0.98, 0.95), "ambient": Color(0.85, 0.9, 1.0),
			"medals": [[2000.0, 25000.0], [4000.0, 160000.0], [7000.0, 900000.0]]},
	{"id": "mountains", "name": "Mountains", "unlock_from": 1, "unlock_meters": 4000.0,
			"speed_mult": 1.2, "ramp_mult": 1.2, "blocked_add": 1, "gull_share": 0.3, "gust_chance": 0.4, "lightning_interval": 0.0, "cloud_mult": 1.3,
			"sky": Color(0.3, 0.28, 0.38), "ground": Color(0.32, 0.3, 0.36), "stripe": Color(0.5, 0.47, 0.56),
			"obstacle": Color(0.95, 0.62, 0.2), "cloud": Color(0.92, 0.9, 1.0), "ambient": Color(0.8, 0.78, 0.95),
			"medals": [[2500.0, 150000.0], [5000.0, 1000000.0], [8000.0, 6000000.0]]},
	{"id": "stormfront", "name": "Stormfront", "unlock_from": 2, "unlock_meters": 5000.0,
			"speed_mult": 1.3, "ramp_mult": 1.3, "blocked_add": 1, "gull_share": 0.3, "gust_chance": 0.3, "lightning_interval": 5.0, "cloud_mult": 1.8,
			"sky": Color(0.09, 0.1, 0.16), "ground": Color(0.12, 0.13, 0.2), "stripe": Color(0.22, 0.24, 0.36),
			"obstacle": Color(0.9, 0.2, 0.45), "cloud": Color(0.5, 0.53, 0.62), "ambient": Color(0.6, 0.62, 0.8),
			"medals": [[3000.0, 1000000.0], [6000.0, 7000000.0], [9000.0, 45000000.0]]},
]
## GULLS: white obstacles that drift sideways slowly (units/second), at most this fraction of a column
## each way. A gull never drifts toward the main safe-path column unless it is far from it.
var gull_speed := 1.3
var gull_drift := 0.35
## WIND GUSTS: a zone `gust_width` wide (x) and `gust_length` long (z) sitting between two rows (never
## closer than gust_clear to either). It shows faintly from far off and lights up when its front edge
## is within gust_telegraph units of the plane; the plane inside it is pushed sideways at gust_push u/s.
var gust_width := 6.0
var gust_length := 4.0
var gust_clear := 3.0
var gust_telegraph := 12.0
var gust_push := 3.0
## LIGHTNING: a column strip is shown for lightning_warn seconds, then strikes for lightning_strike
## seconds: the plane inside it is hit. Strikes come every lightning_interval seconds (x0.8-1.2) at the
## start of a run, faster as it goes (lightning_ramp = fewer seconds per minute), never before
## lightning_start seconds, and never on the safe path of a row that is passing the plane.
var lightning_warn := 1.0
var lightning_strike := 0.3
var lightning_start := 6.0
var lightning_ramp := 1.0
var lightning_aim := 0.6     # chance a strike is aimed at the plane's own column

func map_def(i: int) -> Dictionary:
	return maps[clampi(i, 0, maps.size() - 1)]

## Scroll speed on a map `t` seconds into a run.
func map_speed(map: int, t: float) -> float:
	var m := map_def(map)
	return minf(base_speed * m["speed_mult"] + speed_ramp * m["ramp_mult"] * t, max_speed * m["speed_mult"])

## Meters shown to the player for a distance in world units.
func meters(units: float) -> float:
	return units * meters_per_unit

## "3,120 m"
func fmt_m(meters_value: float) -> String:
	var n := int(meters_value)
	var txt := str(n)
	var out := ""
	while txt.length() > 3:
		out = "," + txt.substr(txt.length() - 3) + out
		txt = txt.substr(0, txt.length() - 3)
	return txt + out + " m"

# ---------- In-run picks ----------
## The first pick comes at pick_first x your permanent multiplier (map multiplier x Coin Value, see pick_scale) in score,
## or on the timer below. After that each pick is priced as described under pick_gap_seconds. The game pauses, three cards slide in, you choose.
var pick_first := 40.0
var pick_growth := 1.1
## Later picks are priced in SECONDS of your own earning: the next pick costs about pick_gap_seconds of the coins per
## second you are making this run (x pick_growth for each pick already taken), so the spacing stays about the same
## however much you earn. It is nudged by how well you earn: a slower earner waits somewhat longer
## (the gap scales with relative_rate ^ -pick_rate_exponent; relative_rate = coins/s / (pick_rate_ref x multiplier)),
## so engaged players get picks noticeably faster than passive ones.
var pick_gap_seconds := 44.0
var pick_rate_exponent := 0.4
var pick_rate_ref := 10.0
## The permanent multiplier that scales the prices also counts the flat coin upgrades (Can Bounty + Close Call
## Pay), so that picks keep their pace as those grow: scale = map x Coin Value x (1 + weight x (bounty + close-call pay) / ref).
var pick_flat_weight := 0.15
var pick_flat_ref := 12.0
## The FIRST pick of every run comes inside this window (seconds into the run): never before the minimum, whatever
## the score, and guaranteed by the maximum, whatever the score. Later picks are purely score-based.
var first_pick_min_seconds := 15.0
var first_pick_max_seconds := 20.0
var pick_cards := 3
## How much more often a perk you already own is offered (a card for each owned perk at 1.0 + this).
var perk_owned_weight := 3.0
## Offer odds of the other card kinds, relative to one new perk (1.0). Full Tank gets a boost when the tank is low.
var boost_weight := 0.8
var supply_weight := 0.7
var full_tank_low_weight := 3.0
## Boosts last this many seconds.
var boost_time := 20.0
## Magnet Storm's pull radius (units), and the Coin Bag's size as a fraction of the NEXT pick's price.
var storm_radius := 6.0
var coin_bag_fraction := 0.3
## Under 15% fuel Second Wind fires; Glide / Cloud Diver / Prop Wash push their effects in the tables below.
var second_wind_below := 0.15
var prop_wash_push := 7.0          # how hard (units/second at first) a close call shoves an obstacle sideways
var prop_wash_friction := 5.0

## PERKS last the run (levels 1-3, `vals` = the effect at each level). `unlock`: "" = in the starting pool,
## otherwise the milestone that unlocks it. `needs`: "crates" = only offered once crates exist.
var perks: Array[Dictionary] = [
	{"id": "glide", "name": "Glide", "glyph": "G", "color": Color(0.6, 0.85, 1.0), "unlock": "", "vals": [4.0, 8.0, 14.0],
			"line": "Fuel runs out? Glide {v} s instead of ending."},
	{"id": "cloud_diver", "name": "Cloud Diver", "glyph": "D", "color": Color(0.9, 0.95, 1.0), "unlock": "", "vals": [3.0, 7.0, 12.0],
			"line": "Fly under a cloud: get {v} fuel back every second."},
	{"id": "lucky_whiskers", "name": "Lucky Whiskers", "glyph": "W", "color": Color(1.0, 0.4, 0.85), "unlock": "", "vals": [40, 75, 100],
			"line": "A Whisker close drops a fuel can {v}% of the time."},
	{"id": "prop_wash", "name": "Prop Wash", "glyph": "P", "color": Color(0.6, 0.9, 0.7), "unlock": "prop_wash", "vals": [25, 60, 120],
			"line": "Close calls shove obstacles aside. Ones that bump others pay {v} coins."},
	{"id": "battering_ram", "name": "Battering Ram", "glyph": "B", "color": Color(0.85, 0.6, 0.35), "unlock": "battering_ram", "needs": "crates", "vals": [1.5, 2.5, 4.0],
			"line": "Crates break on any touch, not just rams. Crate coins x{v}."},
	{"id": "fuel_miser", "name": "Fuel Miser", "glyph": "M", "color": Color(0.4, 0.9, 0.5), "unlock": "", "vals": [25, 45, 65],
			"line": "Burn {v}% less fuel."},
	{"id": "hot_streak", "name": "Hot Streak", "glyph": "H", "color": Color(1.0, 0.55, 0.2), "unlock": "", "vals": [60, 150, 300],
			"line": "Your close-call bonus fades {v}% slower."},
	{"id": "scavenger", "name": "Scavenger", "glyph": "S", "color": Color(1.0, 0.85, 0.3), "unlock": "", "vals": [30, 90, 250],
			"line": "Each fuel can pays {v} extra coins."},
	{"id": "tailwind", "name": "Tailwind", "glyph": "T", "color": Color(0.5, 0.8, 1.0), "unlock": "", "vals": [30, 60, 90],
			"line": "Fly faster, earn more: +{v}% coins (and a little speed)."},
	{"id": "daredevil", "name": "Daredevil", "glyph": "!", "color": Color(1.0, 0.35, 0.35), "unlock": "", "vals": [30, 60, 100],
			"line": "Close calls count from {v}% farther away."},
	{"id": "second_wind", "name": "Second Wind", "glyph": "2", "color": Color(0.5, 1.0, 0.8), "unlock": "second_wind", "vals": [40, 70, 100],
			"line": "Once a run, refill {v}% of the tank when it runs low."},
	{"id": "golden_touch", "name": "Golden Touch", "glyph": "$", "color": Color(1.0, 0.8, 0.1), "unlock": "golden_touch", "needs": "crates", "vals": [3, 5, 8],
			"line": "Crates pay x{v}."},
]
## BOOSTS (boost_time seconds) and SUPPLIES (instant).
var boosts: Array[Dictionary] = [
	{"id": "double_coins", "name": "Double Coins", "glyph": "x", "color": Color(1.0, 0.85, 0.2), "line": "Everything you earn pays double."},
	{"id": "shield", "name": "Shield", "glyph": "O", "color": Color(0.4, 0.8, 1.0), "line": "One free hit."},
	{"id": "magnet_storm", "name": "Magnet Storm", "glyph": "M", "color": Color(0.8, 0.5, 1.0), "line": "Fuel cans fly to you from far away."},
	{"id": "whisker_window", "name": "Whisker Window", "glyph": "W", "color": Color(1.0, 0.4, 0.85), "line": "Every close call counts as a Whisker close."},
	{"id": "fuel_freeze", "name": "Fuel Freeze", "glyph": "*", "color": Color(0.7, 0.95, 1.0), "line": "No fuel burns."},
]
var supplies: Array[Dictionary] = [
	{"id": "full_tank", "name": "Full Tank", "glyph": "F", "color": Color(0.3, 0.9, 0.4), "line": "Fill the tank right now."},
	{"id": "patch", "name": "Patch", "glyph": "+", "color": Color(1.0, 0.4, 0.4), "line": "+1 hit you can survive this run."},
	{"id": "crate_shower", "name": "Crate Shower", "glyph": "C", "color": Color(0.9, 0.7, 0.3), "needs": "crates", "line": "The next rows are full of crates."},
	{"id": "coin_bag", "name": "Coin Bag", "glyph": "$", "color": Color(1.0, 0.8, 0.2), "line": "Instant coins: {v}."},
]
## COMBOS: a combo switches on the moment its perk reaches level 3 AND its partner is there (partner gear
## equipped, or partner perk held). A banner announces it. `partner_kind` is "gear" or "perk".
var deadstick_extend := 3.0        # Deadstick: seconds a can adds to the glide
var overflow_coin_rate := 6.0      # Fuel Overflow: coins per unit of fuel gained beyond a full tank
var golden_can_coins := 40.0       # Golden Whiskers: coins a golden can pays (x the earn multiplier) on top of fuel
var cradle_crates := 10            # Cat's Cradle: crates broken per life restored
var chain_max := 4                 # Wingwalker: how many obstacles a nudge can chain through
var combo_banner_time := 2.4
var combos: Array[Dictionary] = [
	{"id": "deadstick", "name": "Deadstick", "perk": "glide", "partner_kind": "gear", "partner": "magnet", "color": Color(0.6, 0.85, 1.0),
			"line": "While gliding, cans fly to you from anywhere and each one adds seconds to the glide.",
			"hint": "A glider that never gives up, with a magnet on board."},
	{"id": "cloud_surfer", "name": "Cloud Surfer", "perk": "cloud_diver", "partner_kind": "gear", "partner": "cloud_eye", "color": Color(0.85, 0.95, 1.0),
			"line": "Close calls made under clouds count as Whisker closes.",
			"hint": "Ride the clouds, and see through them."},
	{"id": "barnstormer", "name": "Barnstormer", "perk": "hot_streak", "partner_kind": "gear", "partner": "steady_nerves", "color": Color(1.0, 0.55, 0.2),
			"line": "Your close-call bonus never fades while it is above x2.",
			"hint": "A streak that will not cool, and nerves of steel."},
	{"id": "fuel_overflow", "name": "Fuel Overflow", "perk": "fuel_miser", "partner_kind": "gear", "partner": "reserve_tank", "color": Color(0.4, 0.9, 0.5),
			"line": "Fuel you gain beyond a full tank turns into coins.",
			"hint": "Sip the fuel, and keep a spare tank."},
	{"id": "golden_whiskers", "name": "Golden Whiskers", "perk": "lucky_whiskers", "partner_kind": "gear", "partner": "head_start", "color": Color(1.0, 0.8, 0.2),
			"line": "Cans dropped by Whisker closes are golden: fuel plus a big burst of coins.",
			"hint": "Luck on the whiskers, and a flying start."},
	{"id": "cats_cradle", "name": "Cat's Cradle", "perk": "battering_ram", "partner_kind": "gear", "partner": "nine_lives", "color": Color(0.85, 0.6, 0.35),
			"line": "Every 10 crates you break restores a life.",
			"hint": "Break crates like a ram, with lives to spare."},
	{"id": "wingwalker", "name": "Wingwalker", "perk": "prop_wash", "partner_kind": "perk", "partner": "daredevil", "color": Color(0.6, 0.9, 0.7),
			"line": "Shoved obstacles chain-react, and every link in the chain pays more.",
			"hint": "Blow obstacles around, and fly close enough to do it."},
]

func combo_def(id: String) -> Dictionary:
	for c in combos:
		if c["id"] == id:
			return c
	return {}

## CRATES: breakable blocks that take a blocked cell of a row (so fairness treats them as blocked). A glow on
## top shows what is inside: gold = coins, green = fuel, purple = an instant extra pick. Touching a crate's
## FRONT (bottom) face head-on breaks it, which includes just holding position as it scrolls in; touching it
## from the side crashes (unless Battering Ram). The front face is a bit more forgiving than the side edges.
var crates_enabled := true
var crate_chance := 0.10           # chance a blocked cell is a crate
var crate_shower_chance := 0.8     # ...in the rows after a Crate Shower
var crate_start_time := 5.0        # none in the first seconds of a run
var ram_speed := 0.0               # extra rule: you must also be moving up the screen this fast (units/second); 0 = none
var crate_front_forgive := 0.35    # a crate's front (bottom) face counts this much wider than the crate itself; the sides get no slack
var crate_coins := 30.0            # gold crate: coins (x the earn multiplier, Battering Ram level, Golden Touch)
var crate_fuel := 30.0             # green crate: fuel (x Golden Touch)
var crate_weights: Array[float] = [0.60, 0.32, 0.08]   # gold, green, purple (purple = the extra pick: rare)
var crate_colors: Array[Color] = [Color(1.0, 0.8, 0.15), Color(0.25, 1.0, 0.45), Color(0.75, 0.35, 1.0)]
var crate_wood := Color(0.55, 0.38, 0.2)
## Crate coins per Battering Ram level (the perk's own value is this multiplier) and the Crate Shower's length.
var crate_shower_rows := 6

## MILESTONES unlock the perks that are not in the starting pool. Fields: id (also the perk's `unlock`), perk, name of the
## goal, kind (stat = a lifetime counter in the save, map = reach a map), stat / target, shown in the Logbook.
var milestones: Array[Dictionary] = [
	{"id": "prop_wash", "perk": "prop_wash", "goal": "Collect 100 fuel cans", "kind": "stat", "stat": "cans", "target": 100.0},
	{"id": "second_wind", "perk": "second_wind", "goal": "Make 10 Whisker closes", "kind": "stat", "stat": "whiskers", "target": 10.0},
	{"id": "battering_ram", "perk": "battering_ram", "goal": "Break 50 crates", "kind": "stat", "stat": "crates", "target": 50.0},
	{"id": "golden_touch", "perk": "golden_touch", "goal": "Reach the Coast", "kind": "map", "map": 1},
]

## The ONE short line shown on a pick card (max ~6 words; {v} = the value at that level). The long descriptions
## above live in the Logbook.
## Tailwind's speed bonus by level (%): the coins it pays are in the perk's vals. The speed is capped at max_speed.
var tailwind_speed_pct: Array[float] = [0.0, 10.0, 20.0, 30.0]
## Level 3 changes how a perk behaves, not just its numbers. The pick card shows this line at level 3 instead of the usual one.
var pick_l3 := {
	"glide": "Glide {v} s, then refill 20% of the tank",
	"cloud_diver": "+{v} fuel/s; close calls under clouds are Whiskers",
	"lucky_whiskers": "Every Whisker close drops a can",
	"prop_wash": "Bumped obstacles pay {v}, and bump chains pay more",
	"battering_ram": "Crates break on touch, +15% fuel each",
	"fuel_miser": "{v}% less burn; none at bonus x3+",
	"hot_streak": "Bonus never drops below x2",
	"scavenger": "Cans pay {v} and add a bonus step",
	"tailwind": "Fly faster, earn more; Whiskers refuel",
	"daredevil": "Close calls from {v}% farther; Whisker range doubled",
	"second_wind": "Refill {v}% of the tank, twice a run",
	"golden_touch": "Crates pay x{v} and drop a can",
}
var pick_short := {
	"glide": "Glide {v} s when empty", "cloud_diver": "+{v} fuel/s under clouds", "lucky_whiskers": "{v}% can on Whisker closes",
	"prop_wash": "Bumped obstacles pay {v}", "battering_ram": "Crates break on touch", "fuel_miser": "{v}% less fuel burn",
	"hot_streak": "Bonus fades {v}% slower", "scavenger": "+{v} coins per can", "tailwind": "Fly faster, earn more",
	"daredevil": "Close calls from {v}% farther", "second_wind": "Refill {v}% once when low", "golden_touch": "Crates pay x{v}",
	"double_coins": "Double coins, 20 s", "shield": "One free hit, 20 s", "magnet_storm": "Cans fly to you, 20 s",
	"whisker_window": "Every close call Whisker", "fuel_freeze": "No fuel burn, 20 s",
	"full_tank": "Fill the tank", "patch": "+1 hit this run", "crate_shower": "Next rows full of crates", "coin_bag": "+{v} coins now",
}

func perk_def(id: String) -> Dictionary:
	for d in perks:
		if d["id"] == id:
			return d
	return {}

## The effect of a perk at a level (0 = none).
func perk_value(id: String, level: int) -> float:
	if level <= 0:
		return 0.0
	var d := perk_def(id)
	return float(d["vals"][clampi(level, 1, 3) - 1])

# ---------- Economy: score is coins ----------
## Coins per world unit flown, before the close-call bonus, the map multiplier and Coin Value. The run
## total on screen IS the coins you earn (a crash keeps them all).
var coins_per_unit := 1.0
## Distance pays coins_per_unit x (bonus - bonus_pay_offset): x1 pays 0.2, x2 pays 1.2, x3 pays 2.2. So the
## close-call bonus is what earns; flying without close calls pays very little.
var bonus_pay_offset := 0.8
## Multiplier on everything earned, per map (Countryside, Coast, Mountains, Stormfront).
var map_coin_mult: Array[float] = [1.0, 2.0, 4.0, 8.0]   # (Countryside x1, Coast x2, Mountains x4, Stormfront x8)

## Distance shown to the player in meters = world units x this (maps unlock at 3,000 m / 4,000 m / 5,000 m).
var meters_per_unit := 5.0

## EARNINGS upgrades have no cap and double their effect at every Nth level (25, 50, 75 ...).
var double_every := 25
## Costs: EARNINGS cost base * earn_cost_growth^level, PLANE upgrades base * plane_cost_growth^level.
var earn_cost_growth := 1.12
var plane_cost_growth := 1.5
## Gear slots: the first is free; buying the others is a milestone. Cost of slot 2 and slot 3.
var gear_slot_costs: Array[float] = [0.0, 28000.0, 1750000.0]
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
			"line": "Every coin worth more: {a} -> {b}", "fmt": "x", "max": -1, "cost_base": 280.0, "per": 0.10, "notice": "Every coin is worth more, everywhere."},
	{"id": "can_bounty", "tab": "earnings", "name": "Can Bounty", "glyph": "C", "color": Color(0.35, 0.85, 0.45),
			"line": "Each fuel can pays {a} -> {b} coins", "fmt": "big", "max": -1, "cost_base": 420.0, "per": 8.0, "notice": "Every fuel can is a little jackpot."},
	{"id": "close_call_pay", "tab": "earnings", "name": "Close Call Pay", "glyph": "!", "color": Color(1.0, 0.55, 0.2),
			"line": "Each close call pays {a} -> {b} coins", "fmt": "big", "max": -1, "cost_base": 560.0, "per": 4.0, "notice": "Skimming obstacles pays right away."},
	{"id": "bonus_cap", "tab": "earnings", "name": "Bonus Cap", "glyph": "^", "color": Color(1.0, 0.4, 0.6),
			"line": "Close-call bonus can reach {a} -> {b}", "fmt": "x1", "max": -1, "cost_base": 840.0, "per": 0.5, "front": [2.0, 1.6, 1.3, 1.1, 1.0], "notice": "Long streaks keep climbing."},
	{"id": "fuel_tank", "tab": "plane", "name": "Fuel Tank", "glyph": "F", "color": Color(0.3, 0.7, 1.0),
			"line": "Hold {d} more fuel ({a} -> {b})", "fmt": "int", "max": 12, "cost_base": 80.0, "per": 30.0, "falloff": 0.9, "notice": "You fly longer between cans."},
	{"id": "efficiency", "tab": "plane", "name": "Efficiency", "glyph": "E", "color": Color(0.4, 0.9, 0.8),
			"line": "Burn fuel slower: {a}/s -> {b}/s", "fmt": "dec1", "max": 10, "cost_base": 100.0, "per": 0.09, "falloff": 0.88, "notice": "The tank lasts noticeably longer."},
	{"id": "refill", "tab": "plane", "name": "Refill", "glyph": "R", "color": Color(0.6, 0.8, 0.3),
			"line": "Each can gives {d} more fuel ({a} -> {b})", "fmt": "dec1", "max": 12, "cost_base": 120.0, "per": 7.0, "falloff": 0.9, "notice": "Each can buys more time in the air."},
	{"id": "nine_lives", "tab": "gear", "name": "Nine Lives", "glyph": "9", "color": Color(1.0, 0.35, 0.35),
			"line": "Survive hits per run: {a} -> {b}", "fmt": "int", "max": 3, "costs": [1400.0, 42000.0, 1680000.0], "steps": [0, 1, 2, 3], "notice": "A crash costs a life, not the run."},
	{"id": "reserve_tank", "tab": "gear", "name": "Reserve Tank", "glyph": "T", "color": Color(0.5, 0.6, 1.0),
			"line": "Refill the tank when empty: {a} -> {b} times", "fmt": "int", "max": 2, "costs": [2100.0, 84000.0], "steps": [0, 1, 2], "notice": "Run dry? The tank refills itself."},
	{"id": "magnet", "name": "Can Magnet", "tab": "gear", "glyph": "M", "color": Color(0.8, 0.5, 1.0),
			"line": "Pull cans from {a} -> {b} units away", "fmt": "dec1", "max": 3, "costs": [1050.0, 31500.0, 1260000.0], "steps": [0.0, 1.5, 2.5, 3.5], "notice": "Cans drift toward you."},
	{"id": "cloud_eye", "tab": "gear", "name": "Cloud Eye", "glyph": "O", "color": Color(0.8, 0.9, 1.0),
			"line": "Outlines show obstacles under clouds: {a} -> {b}", "fmt": "onoff", "max": 1, "costs": [3500.0], "steps": [0, 1], "notice": "See what hides in the clouds."},
	{"id": "steady_nerves", "tab": "gear", "name": "Steady Nerves", "glyph": "S", "color": Color(0.95, 0.75, 0.5),
			"line": "A hit keeps {a} -> {b} of your close-call bonus", "fmt": "pct", "max": 2, "costs": [2800.0, 84000.0], "steps": [0.0, 0.5, 1.0], "notice": "A hit no longer wipes your streak."},
	{"id": "head_start", "tab": "gear", "name": "Head Start", "glyph": "H", "color": Color(1.0, 0.9, 0.3),
			"line": "Begin each run at bonus {a} -> {b}", "fmt": "x1", "max": 2, "costs": [1750.0, 52500.0], "steps": [1.0, 1.5, 2.0], "notice": "Every run starts already hot."},
]

## Name, glyph and colour of anything with an icon (a perk, gear, an upgrade, a boost, a supply).
func icon_def(id: String) -> Dictionary:
	for list in [perks, upgrades, boosts, supplies]:
		for d in list:
			if d["id"] == id:
				return d
	return {"name": id, "glyph": "?", "color": Color.WHITE}

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
## The first levels of an earnings upgrade are the biggest: level n is worth the sum of the first n entries of "front"
## (default 3.0, 2.4, 1.9, 1.5, 1.25 levels' worth), then one level's worth each.
var front_default: Array[float] = [3.0, 2.4, 1.9, 1.5, 1.25]
func _front(u: Dictionary, level: int) -> float:
	var f: Array = u.get("front", front_default)
	var total := 0.0
	for i in level:
		total += float(f[i]) if i < f.size() else 1.0
	return total

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
			return 1.0 + u["per"] * _front(u, l) * doubling(l)
		"can_bounty", "close_call_pay":
			return u["per"] * _front(u, l) * doubling(l)
		"bonus_cap":
			return bonus_cap + u["per"] * _front(u, l) * doubling(l)
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
	return out + "\n" + upgrade_notice(id, level)

## "You'll notice ..." under a Hangar upgrade: what the next level does for the player, in the player's terms.
func upgrade_notice(id: String, level: int) -> String:
	var u := upgrade_def(id)
	var m := int(u["max"])
	if m >= 0 and level >= m:
		return ""
	var note: String = u.get("notice", "")
	match id:
		"fuel_tank":
			var extra := upgrade_value(id, level + 1) - upgrade_value(id, level)
			return "You'll notice: +%d s of flying. %s" % [int(round(extra / maxf(drain_rate(), 0.1))), note]
		"efficiency":
			var secs := fuel_max() / maxf(upgrade_value(id, level + 1), 0.1) - fuel_max() / maxf(upgrade_value(id, level), 0.1)
			return "You'll notice: +%d s per tank. %s" % [int(round(secs)), note]
		"refill":
			var extra2 := upgrade_value(id, level + 1) - upgrade_value(id, level)
			return "You'll notice: +%d s per can. %s" % [int(round(extra2 / maxf(drain_rate(), 0.1))), note]
	return "You'll notice: " + note

## What the game uses, upgrades included (the plain tuning values are the level-0 numbers).
func fuel_max() -> float:
	return upgrade_value("fuel_tank", Save.level("fuel_tank"))

func drain_rate() -> float:
	return upgrade_value("efficiency", Save.level("efficiency"))

func refill_amount() -> float:
	return upgrade_value("refill", Save.level("refill"))

func bonus_cap_now() -> float:
	return upgrade_value("bonus_cap", Save.level("bonus_cap"))

## What pick number k (1 = the second pick of the run) costs, given the coins per second made so far this run.
func pick_price(k: int, rate: float, perm: float) -> float:
	var r := clampf(rate / (pick_rate_ref * maxf(perm, 0.0001)), 0.05, 50.0)
	return pick_gap_seconds * pow(pick_growth, k - 1) * pow(r, -pick_rate_exponent) * rate

## What the pick prices are multiplied by: the permanent multiplier (map x Coin Value), with the flat upgrades' share.
func pick_scale(map: int) -> float:
	return map_coin_mult[map] * coin_value_mult() * (1.0 + pick_flat_weight * (can_bounty_pay() + close_call_pay()) / pick_flat_ref)

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
