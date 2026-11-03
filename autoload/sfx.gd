extends Node
## Plays the synthesised sounds in assets/audio. Files ship as raw WAV bytes.

const LOOPS := ["music_space", "music_surface", "wind", "engine", "rover"]
var _streams: Dictionary = {}
var _music: AudioStreamPlayer
var _music_name := ""
var _loops: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ready_quit_handling()
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)

func _ready_quit_handling() -> void:
	get_tree().auto_accept_quit = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()

## Silence audio, give the audio thread a moment to let go of its streams, then exit.
func quit_game() -> void:
	_stop_all()
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()

## Stop everything before shutdown: a stream still playing would otherwise outlive the audio server.
func _exit_tree() -> void:
	_stop_all()

func _stop_all() -> void:
	_music.stop()
	_music.stream = null
	for p in _pool:
		p.stop()
		p.stream = null
	for k: String in _loops:
		var lp: AudioStreamPlayer = _loops[k]
		lp.stop()
		lp.stream = null
	_streams.clear()

func _stream(sound: String) -> AudioStreamWAV:
	if _streams.has(sound):
		return _streams[sound]
	var path := "res://assets/audio/%s.wavdata" % sound
	if not FileAccess.file_exists(path):
		return null
	var s := AudioStreamWAV.load_from_buffer(FileAccess.get_file_as_bytes(path))
	if sound in LOOPS:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = s.data.size() / 2
	_streams[sound] = s
	return s

func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var s := _stream(sound)
	if s == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

func music(track: String) -> void:
	if track == _music_name:
		return
	_music_name = track
	var s := _stream(track)
	if s == null:
		_music.stop()
		return
	_music.stream = s
	_music.volume_db = -60.0
	_music.play()
	create_tween().tween_property(_music, "volume_db", -6.0, 2.5)

## Set a looping sound's level, 0 to 1. Pass 0 to fade it out.
func loop(sound: String, level: float, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = _loops.get(sound)
	if p == null:
		var s := _stream(sound)
		if s == null:
			return
		p = AudioStreamPlayer.new()
		p.bus = "SFX"
		p.stream = s
		add_child(p)
		_loops[sound] = p
	if level <= 0.001:
		if p.playing:
			p.stop()
		return
	if not p.playing:
		p.play()
	p.volume_db = linear_to_db(level)
	p.pitch_scale = maxf(pitch, 0.1)

func stop_loops() -> void:
	for k: String in _loops:
		(_loops[k] as AudioStreamPlayer).stop()
