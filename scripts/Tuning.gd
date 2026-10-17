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
## Obstacle width as a fraction of a column (visual AND collision). Smaller = clearer gaps.
var obstacle_scale := 0.7
## Obstacle length along the flight direction (z).
var obstacle_depth := 1.4

# ---------- Forward speed ----------
## Scroll speed at the start of a run (units/second).
var base_speed := 10.0
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
## Hitstop (a brief slow-down) fires only when a near miss raises the multiplier into a NEW tier
## (1x->2x, 2x->3x, 3x->4x), not on every near miss. Turn it off entirely with false.
var hitstop_enabled := true
## Engine.time_scale during the freeze, and how long it lasts in REAL seconds.
var hitstop_scale := 0.5
var hitstop_duration := 0.05
## Sparks in the burst from the wingtip nearest the obstacle, and how long each lives (seconds).
var spark_count := 24
var spark_lifetime := 0.45
## Speed streaks flashed past the plane, and their speed (units/second).
var streak_count := 10
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
## Half-size of the plane's hit box in x/z (smaller than the model = more forgiving).
var plane_hit_half := Vector2(0.6, 0.6)

# ---------- Helpers ----------
## Index into a per-tier array for a multiplier: 2x -> 0, 3x -> 1, ... clamped to the array.
func tier_index(multiplier: int, count: int) -> int:
	return clampi(multiplier - 2, 0, count - 1)

func column_width() -> float:
	return ortho_size / column_count

## World x of the centre of column i (0 = leftmost).
func column_center(i: int) -> float:
	return (i - (column_count - 1) * 0.5) * column_width()
