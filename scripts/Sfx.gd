class_name Sfx
extends Node
## All the game's sound. The audio files in res://audio were synthesised offline (tools/make_audio.py: sines, saws and
## filtered noise, nothing downloaded). Everything here is created once at start-up: a pool of players for one-shots, an
## engine drone and a wind bed (pitch and volume follow the speed), and three music layers that loop in sync and fade in
## and out with the wave phase (CALM: base; BUILD: + rhythm; PEAK: + lead and arpeggio; BREATHER: back to the base).
## Two buses, "Music" and "SFX", carry the volume settings of the start screen. ?nofx=sound / ?nofx=music switch them off.

const ONE_SHOTS := ["whoosh", "whoosh_big", "barnstormer", "pickup", "crunch", "crash", "pick_open", "pick_select", "speed_whoosh", "tap", "tick", "coin", "screech", "honk", "caw", "whine", "alarm", "flak", "boom", "ding"]
const POOL := 10
const MUSIC_LAYERS := ["music_base", "music_rhythm", "music_full"]
## Which layers play in each wave phase (CALM, BUILD, PEAK, BREATHER) and in the menu.
const LAYER_MIX := [[1.0, 0.0, 0.0], [1.0, 1.0, 0.0], [1.0, 1.0, 1.0], [1.0, 0.0, 0.0]]
const FADE_SECONDS := 1.2
const MIN_DB := -60.0

var plays := 0                     # one-shots actually started (the tests count them)
var last_played := ""
var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _engine: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _music: Array[AudioStreamPlayer] = []
var _layer_now := PackedFloat32Array([0.0, 0.0, 0.0])   # current layer volumes (0..1)
var _layer_goal := PackedFloat32Array([1.0, 0.0, 0.0])
var _flying := false
var _speed_frac := 0.0
var _duck := 1.0                   # the music steps back while the pick screen is up
var _duck_goal := 1.0
var _flight_now := 0.0             # how much of the engine / wind is faded in (0..1)
var music_started := false
var unlocked := false             # the first tap has happened (browsers keep the sound off until one)

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps fading while the game is paused (the pick screen)

func _ready() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	for n in ONE_SHOTS:
		_streams[n] = load("res://audio/%s.wav" % n)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(p)
		_pool.append(p)
	_engine = _loop_player("engine", "SFX")
	_wind = _loop_player("wind", "SFX")
	for n in MUSIC_LAYERS:
		_music.append(_loop_player(n, "Music"))
	apply_volumes()

func _loop_player(stream_name: String, bus: String) -> AudioStreamPlayer:
	var s: AudioStreamWAV = load("res://audio/%s.wav" % stream_name)
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = s.data.size() / 2   # (16 bit mono: samples)
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	p.volume_db = -80.0
	add_child(p)
	return p

## The start screen's volume settings (0..1 each) onto the buses.
func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(Save.audio_music, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(Save.audio_sound, 0.0001)))

## A one-shot. `volume` 0..1 (linear), `pitch` 1 = as recorded.
func play(sound: String, volume: float = 1.0, pitch: float = 1.0) -> void:
	if DebugFlags.off("sound") or not _streams.has(sound):
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = _streams[sound]
	p.volume_db = linear_to_db(maxf(volume, 0.0001))
	p.pitch_scale = pitch
	p.play()
	plays += 1
	last_played = sound

## The first tap of the session: browsers only let a page make sound after one. The audio context wakes up with it, so the
## music that was started behind the start-up screen is started again here (in sync), with a soft click.
func unlock() -> void:
	if unlocked:
		return
	unlocked = true
	if music_started and not DebugFlags.off("music"):
		for p in _music:
			p.stop()
		for p in _music:
			p.play()
	play("tap", 0.5)

## The flight sounds: the engine and the wind follow the speed (`speed_frac` 0 = start speed, 1 = top speed).
func set_flight(flying: bool, speed_frac: float = 0.0) -> void:
	_flying = flying
	_speed_frac = clampf(speed_frac, 0.0, 1.0)

## Music follows the wave phase (0 CALM .. 3 BREATHER); -1 = the menu (base layer only).
func set_phase(phase: int) -> void:
	var mix: Array = LAYER_MIX[clampi(phase, 0, 3)]
	for i in 3:
		_layer_goal[i] = mix[i]

func duck(on: bool) -> void:
	_duck_goal = 0.4 if on else 1.0

func start_music() -> void:
	if music_started or DebugFlags.off("music"):
		return
	music_started = true
	for p in _music:   # (started together so the layers stay in sync)
		p.play()

func stop_music() -> void:
	music_started = false
	for p in _music:
		p.stop()

func stop_run() -> void:
	_flying = false

func _process(delta: float) -> void:
	var step := delta / FADE_SECONDS
	_duck = move_toward(_duck, _duck_goal, delta * 3.0)
	for i in 3:
		_layer_now[i] = move_toward(_layer_now[i], _layer_goal[i], step)
		var amp: float = _layer_now[i] * _duck
		_music[i].volume_db = linear_to_db(amp) if amp > 0.001 and not DebugFlags.off("music") else -80.0
	var want := 1.0 if (_flying and not DebugFlags.off("sound")) else 0.0
	_flight_now = move_toward(_flight_now, want, delta * 4.0)
	if _flight_now > 0.001:
		if not _engine.playing:
			_engine.play()
			_wind.play()
		_engine.pitch_scale = lerpf(0.75, 2.1, _speed_frac)
		_engine.volume_db = linear_to_db(_flight_now * lerpf(0.16, 0.34, _speed_frac))
		_wind.pitch_scale = lerpf(0.8, 1.5, _speed_frac)
		_wind.volume_db = linear_to_db(_flight_now * lerpf(0.05, 0.4, _speed_frac * _speed_frac))
	elif _engine.playing:
		_engine.stop()
		_wind.stop()

## Pre-warm: start every sound once, silently, so decoding and mixing are set up before play.
func prewarm_start() -> void:
	for n in ONE_SHOTS:
		var p := _pool[_next]
		_next = (_next + 1) % POOL
		p.stream = _streams[n]
		p.volume_db = -80.0
		p.play()
	_engine.volume_db = -80.0
	_wind.volume_db = -80.0
	_engine.play()
	_wind.play()

func prewarm_end() -> void:
	for p in _pool:
		p.stop()
	_engine.stop()
	_wind.stop()
