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
var speed_ramp := 0.2
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
## Where the very first row of a run sits (above the screen, so you get a moment to settle).
var first_row_distance := 26.0

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
var fuel_drain := 3.4
## Fuel one can gives back.
var fuel_refill := 20.0
## Chance (0-1) that a new row gets a fuel can (rows with no risky spot get none).
var fuel_can_chance := 0.16
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

# ---------- Near miss & multiplier ----------
## A row counts as a near miss if the plane passed it with less than this gap (units) between the
## plane's hit box and the closest obstacle edge (0 = touching = crash).
var near_miss_distance := 0.5
## Highest score multiplier reachable.
var multiplier_max := 5
## Seconds after a near miss before the multiplier starts to decay.
var multiplier_hold_time := 4.0
## Once decaying, the multiplier drops one step every this many seconds (down to 1x).
var multiplier_decay_step := 1.5
## If true, score accrues at (distance x multiplier); if false, the multiplier is cosmetic.
var score_uses_multiplier := true

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
## "Close!" popup tiers, indexed by multiplier: 2x = first entry, 3x = second, 4x+ = last.
## Text, colour (warmer each tier) and font size (px in the 1080-wide base viewport).
var near_miss_texts: Array[String] = ["Close!", "Closer!", "Whisker Close!"]
var near_miss_colors: Array[Color] = [Color(1.0, 0.95, 0.55), Color(1.0, 0.62, 0.2), Color(1.0, 0.28, 0.12)]
var near_miss_sizes: Array[int] = [64, 84, 108]
## Trail ribbon colour per multiplier tier (2x, 3x, 4x, 5x+); it appears at 2x and fades at 1x.
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

# ---------- Plane movement (relative drag) ----------
## The plane follows how far the finger MOVES, not where it is. Light momentum: it tracks the
## finger closely and carries only a little after the finger stops.
## World units the plane is asked to move per pixel of finger movement.
var drag_sensitivity := 0.014
## Fastest the plane can slide in either direction (units/second).
var max_move_speed := 16.0
## How quickly velocity builds toward the finger's motion (units/second^2). Higher = tighter follow.
var move_accel := 160.0
## Smoothing of the raw finger speed (higher = snappier, lower = smoother but laggier).
var input_smoothing := 30.0
## Exponential velocity damping while the finger is still or lifted (per second). Higher = stops sooner.
var move_damping := 10.0
## Reversing direction: old velocity decays to ~nothing over this many seconds before the new
## direction takes over. 0 = off (reverse as fast as move_accel allows).
var reversal_decay_time := 0.0
## Plane stays this far (units) inside the left/right screen edges (wing half-width is 1.1).
var plane_edge_margin := 1.1
## Forward/back range: the plane may use the bottom this fraction of the screen height.
var plane_zone_fraction := 0.4
## Gap (units) kept between the plane and the bottom screen edge.
var plane_bottom_margin := 1.5

# ---------- Soft snap (after the finger lifts, sideways only) ----------
## Spring strength pulling the plane toward the nearest column centre. 0 disables snapping.
var snap_strength := 7.0
## Spring damping; roughly 2*sqrt(snap_strength) is critically damped (no overshoot).
var snap_damping := 5.5

# ---------- Visual banking ----------
## Roll (radians) per unit of sideways velocity.
var bank_amount := 0.06
## Yaw (radians): nose turns toward the sideways motion, so banking reads from above.
var yaw_amount := 0.025
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
## Index into a per-tier array for a multiplier: 2x -> 0, 3x -> 1, ... clamped to the array.
func tier_index(multiplier: int, count: int) -> int:
	return clampi(multiplier - 2, 0, count - 1)

func column_width() -> float:
	return ortho_size / column_count

## World x of the centre of column i (0 = leftmost).
func column_center(i: int) -> float:
	return (i - (column_count - 1) * 0.5) * column_width()
