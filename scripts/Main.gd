extends Node3D
## Game loop: scroll speed, score, collision, camera, restart.

@onready var player: Node3D = $Player
@onready var spawner: Node3D = $Spawner
@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var hud: CanvasLayer = $Hud

var distance := 0.0     # total distance flown (units) = score
var elapsed := 0.0      # run time, drives the speed ramp
var alive := true
var _death_time := 0.0

func _ready() -> void:
	_setup_environment()
	# Light from above (the camera mostly sees top faces).
	sun.look_at_from_position(Vector3.ZERO, Tuning.light_direction)
	sun.shadow_enabled = false
	# Straight-down orthographic camera, width locked so all columns always fit.
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = Tuning.ortho_size
	camera.near = 0.1
	camera.far = 100.0
	camera.position = Vector3(0, 30, 0)
	camera.rotation = Vector3(-PI / 2, 0, 0)  # looks down; screen-up = world -Z
	_update_plane_zone()

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	camera.size = Tuning.ortho_size
	_update_plane_zone()
	if not alive:
		return

	elapsed += delta
	var speed := minf(Tuning.base_speed + Tuning.speed_ramp * elapsed, Tuning.max_speed)
	var step := speed * delta
	distance += step
	spawner.advance(step)
	hud.set_score(int(distance))

	if spawner.hits(Vector2(player.position.x, player.position.z)):
		alive = false
		_death_time = Time.get_ticks_msec() / 1000.0
		player.crash()
		hud.show_game_over(int(distance))

## The plane may use the bottom `plane_zone_fraction` of the screen. The visible height
## depends on the device aspect (width is fixed), so work it out from the viewport.
func _update_plane_zone() -> void:
	var vp := get_viewport().get_visible_rect().size
	var half_h := Tuning.ortho_size * 0.5 * vp.y / vp.x  # screen spans z = -half_h .. +half_h
	var bottom := half_h - Tuning.plane_bottom_margin
	var top := half_h - 2.0 * half_h * Tuning.plane_zone_fraction
	player.set_zone(top, bottom)

func _input(event: InputEvent) -> void:
	# Tap to restart (small delay so the crash-causing drag can't restart instantly).
	if not alive and event is InputEventScreenTouch and event.pressed \
			and Time.get_ticks_msec() / 1000.0 - _death_time > 0.5:
		get_tree().reload_current_scene()

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.26, 0.34)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.9)
	env.ambient_light_energy = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
