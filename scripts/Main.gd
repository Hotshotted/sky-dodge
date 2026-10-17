extends Node3D
## Game loop: world streaming speed, score, collision, camera, restart.

@onready var player: Node3D = $Player
@onready var spawner: Node3D = $Spawner
@onready var camera: Camera3D = $Camera3D
@onready var hud: CanvasLayer = $Hud

var distance := 0.0     # total distance flown (units) = score
var elapsed := 0.0      # run time, drives the speed ramp
var alive := true
var _death_time := 0.0

func _ready() -> void:
	_setup_environment()
	# Portrait: lock the horizontal field of view so the whole grid always fits width-wise.
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = Tuning.camera_fov
	camera.far = 220.0
	camera.rotation = Vector3(-deg_to_rad(Tuning.camera_tilt_deg), 0, 0)

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	var px: float = player.position.x
	var py: float = player.position.y
	# Camera sits high behind the plane, tilted down, and drifts slightly with it.
	var cam_target := Vector3(px * Tuning.camera_follow_x, py * Tuning.camera_follow_y + Tuning.camera_height, Tuning.camera_distance)
	camera.position = camera.position.lerp(cam_target, 1.0 - exp(-6.0 * delta))
	camera.rotation.x = -deg_to_rad(Tuning.camera_tilt_deg)
	if not alive:
		return

	elapsed += delta
	var speed := minf(Tuning.base_speed + Tuning.speed_ramp * elapsed, Tuning.max_speed)
	var step := speed * delta
	distance += step
	spawner.advance(step)
	hud.set_score(int(distance))

	if spawner.hits(Vector2(px, py)):
		alive = false
		_death_time = Time.get_ticks_msec() / 1000.0
		player.crash()
		hud.show_game_over(int(distance))

func _input(event: InputEvent) -> void:
	# Tap to restart (small delay so the crash-causing drag can't restart instantly).
	if not alive and event is InputEventScreenTouch and event.pressed \
			and Time.get_ticks_msec() / 1000.0 - _death_time > 0.5:
		get_tree().reload_current_scene()

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.65, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.8)
	env.fog_enabled = true
	env.fog_light_color = Color(0.45, 0.65, 0.9)
	env.fog_density = 0.0
	# Fog hides rows popping in at the far end.
	env.fog_depth_begin = 70.0
	env.fog_depth_end = 140.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
