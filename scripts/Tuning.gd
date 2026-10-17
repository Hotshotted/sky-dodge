extends Node
## Every "feel" value of the game lives here, in one place.
## Registered as the autoload `Tuning`, so any script can read `Tuning.some_value`.
## They are plain vars (not consts) so a future on-screen tuning panel can edit them live.
## Distances are world units. The camera looks straight down: screen-right = +x,
## screen-down = +z, and the plane flies toward -z (screen-up).

# ---------- Camera / screen ----------
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
## Direction the sun's light travels. The camera sees mostly top faces, so this is mainly
## "from above, slightly from the left/front" to give the tops a pleasant tone.
var light_direction := Vector3(0.3, -0.9, -0.3)

# ---------- Plane movement (relative drag) ----------
## World units the plane is asked to move per pixel of finger movement.
var drag_sensitivity := 0.014
## Fastest the plane can slide in either direction (units/second).
var max_move_speed := 16.0
## How quickly velocity builds toward the finger's motion (units/second^2). Lower = heavier/floatier.
var move_accel := 80.0
## Smoothing of the raw finger speed (higher = snappier, lower = smoother but laggier).
var input_smoothing := 22.0
## Exponential velocity damping while the finger is still or lifted (per second). Higher = stops sooner.
var move_damping := 5.0
## Reversing direction: old velocity decays to ~nothing over this many seconds
## before the new direction takes over (0.15-0.25 feels like a short "penalty").
var reversal_decay_time := 0.2
## Plane stays this far (units) inside the left/right screen edges.
var plane_edge_margin := 0.7
## Forward/back range: the plane may use the bottom this fraction of the screen height.
var plane_zone_fraction := 0.4
## Gap (units) kept between the plane and the bottom screen edge.
var plane_bottom_margin := 1.5

# ---------- Soft snap (after finger lifts, sideways only) ----------
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
func column_width() -> float:
	return ortho_size / column_count

## World x of the centre of column i (0 = leftmost).
func column_center(i: int) -> float:
	return (i - (column_count - 1) * 0.5) * column_width()
