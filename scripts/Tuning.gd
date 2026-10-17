extends Node
## Every "feel" value of the game lives here, in one place.
## Registered as the autoload `Tuning`, so any script can read `Tuning.some_value`.
## They are plain vars (not consts) so a future on-screen tuning panel can edit them live.
## Distances are world units (1 unit ~ 1 metre); the hidden lane grid is cell_size wide.

# ---------- Hidden lane grid ----------
## Width/height of one grid cell. The 3x3 grid is centred on the plane's start position.
var cell_size := 2.0
## Obstacle edge length as a fraction of a cell (visual AND collision). Smaller = clearer gaps.
var obstacle_scale := 0.7
## Obstacle depth along the flight direction.
var obstacle_depth := 1.5

# ---------- Forward speed ----------
## Forward speed at the start of a run (units/second).
var base_speed := 22.0
## How much forward speed grows each second.
var speed_ramp := 0.35
## Forward speed never exceeds this.
var max_speed := 60.0

# ---------- Obstacle spawning ----------
## Distance between spawn rows (units). Bigger = more time to react and more clearly separated rows.
var spawn_spacing := 26.0
## How many of the 9 cells each row blocks (random between min and max, inclusive).
## A row always keeps at least one open cell, so max is clamped to 8.
var blocked_cells_min := 3
var blocked_cells_max := 5
## Distance ahead of the plane where a row first appears / where the first row of a run sits.
var spawn_distance := 130.0
var first_row_distance := 50.0

# ---------- Camera ----------
## Camera height above the plane's centre line (units). Higher = see over near rows into the corridor.
var camera_height := 9.5
## Camera distance behind the plane (units).
var camera_distance := 9.0
## How far the camera pitches down, in degrees. Together with height this decides where the
## plane sits on screen (aim: lower third) - raise tilt to push the plane lower.
var camera_tilt_deg := 15.0
## Horizontal field of view in degrees (portrait: width is locked, height follows).
var camera_fov := 60.0
## How much the camera follows the plane's x / y movement (0 = fixed, 1 = locked to plane).
var camera_follow_x := 0.5
var camera_follow_y := 0.3

# ---------- Near-row fade ----------
## An obstacle row starts fading when it is this far ahead of the plane (units).
var fade_start_distance := 35.0
## Opacity (0 = invisible, 1 = solid) a row reaches at the plane and keeps while passing the camera.
## Collision is unaffected.
var fade_alpha := 0.25

# ---------- Plane movement (relative drag) ----------
## World units the plane is asked to move per pixel of finger movement.
var drag_sensitivity := 0.014
## Fastest the plane can slide sideways/vertically (units/second).
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
## Plane stays inside +/- (cell_size * this) on each axis.
var bounds_cells := 1.5

# ---------- Soft snap (after finger lifts) ----------
## Spring strength pulling the plane toward the nearest hidden grid point. 0 disables snapping.
var snap_strength := 7.0
## Spring damping; roughly 2*sqrt(snap_strength) is critically damped (no overshoot).
var snap_damping := 5.5

# ---------- Visual banking / pitching ----------
## Roll (radians) per unit of sideways velocity.
var bank_amount := 0.06
## Pitch (radians) per unit of vertical velocity.
var pitch_amount := 0.04
## How quickly the visual tilt follows (higher = snappier).
var tilt_smoothing := 10.0

# ---------- Collision ----------
## Half-size of the plane's hit box in x/y (smaller than the model = more forgiving).
var plane_hit_half := Vector2(0.6, 0.25)
## Half-depth of the plane's hit box along z.
var plane_hit_half_z := 0.6
