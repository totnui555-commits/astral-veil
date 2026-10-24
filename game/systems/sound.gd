extends Node
## Original synthesized score with seamless WAV loops and a bounded effects pool.

const MUSIC_BUS: String = "AstralMusic"
const EFFECTS_BUS: String = "AstralEffects"
const EFFECT_VOICES: int = 12
const MOODS: Array[String] = ["title", "village", "explore", "dungeon", "boss", "ending"]
const EFFECT_ALIASES: Dictionary = {"quest": "sigil", "victory": "chest", "select": "ui", "cancel": "ui", "error": "hurt"}

var current_mood: String = ""
var _music_players: Array[AudioStreamPlayer] = []
var _effect_players: Array[AudioStreamPlayer] = []
var _music_streams: Dictionary = {}
var _effects: Dictionary = {}
var _last_effect: Dictionary = {}
var _active_music: int = 0
var _next_effect: int = 0
var _fade: Tween
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 739137
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(EFFECTS_BUS)
	for index in range(2):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = MUSIC_BUS
		player.volume_db = -60.0
		add_child(player)
		_music_players.append(player)
	for index in range(EFFECT_VOICES):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = EFFECTS_BUS
		add_child(player)
		_effect_players.append(player)
	set_levels(0.85, 0.65, 0.8)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")


func _exit_tree() -> void:
	stop_all()


func stop_all() -> void:
	# Useful before a controlled shutdown; AudioServer releases playback on its next tick.
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
	for player in _music_players + _effect_players:
		player.stop()
		player.stream = null
		player.bus = "Master"
	_music_streams.clear()
	_effects.clear()


func _stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("Original audio asset unavailable: " + path)
		return null
	return load(path) as AudioStream


func play_music(mood: String) -> void:
	if not MOODS.has(mood):
		mood = "explore"
	if current_mood == mood and not _music_players.is_empty() and _music_players[_active_music].playing:
		return
	if _music_players.is_empty():
		return
	if not _music_streams.has(mood):
		var score: AudioStream = _stream("res://audio/music_" + mood + ".wav")
		if score == null:
			# This supports existing builds while an atlas regeneration is pending.
			score = _stream("res://audio/" + ("dungeon" if mood == "boss" else mood) + ".wav")
		if score == null:
			return
		var loop: AudioStreamWAV = score.duplicate() as AudioStreamWAV
		if loop != null:
			loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
			loop.loop_begin = 0
			loop.loop_end = int(round(loop.get_length() * loop.mix_rate))
			score = loop
		_music_streams[mood] = score
	if _fade != null and _fade.is_valid():
		_fade.kill()
	var previous: AudioStreamPlayer = _music_players[_active_music]
	_active_music = 1 - _active_music
	var player: AudioStreamPlayer = _music_players[_active_music]
	player.stop()
	player.stream = _music_streams[mood]
	player.volume_db = -60.0
	player.play()
	current_mood = mood
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(player, "volume_db", 0.0, 0.65)
	_fade.tween_property(previous, "volume_db", -60.0, 0.65)
	_fade.chain().tween_callback(previous.stop)


func sfx(kind: String) -> void:
	if _effect_players.is_empty():
		return
	var cue: String = str(EFFECT_ALIASES.get(kind, kind))
	var now: int = Time.get_ticks_msec()
	# A hit on several targets produces one cue instead of multiplying its volume.
	if now - int(_last_effect.get(cue, -1000)) < (65 if cue in ["hurt", "attack"] else 30):
		return
	if not _effects.has(cue):
		var sample: AudioStream = _stream("res://audio/" + cue + ".wav")
		if sample == null:
			return
		_effects[cue] = sample
	_last_effect[cue] = now
	var player: AudioStreamPlayer = _effect_players[_next_effect]
	_next_effect = (_next_effect + 1) % EFFECT_VOICES
	player.stop()
	player.stream = _effects[cue]
	player.pitch_scale = _rng.randf_range(0.95, 1.05) if cue in ["attack", "heavy", "hurt", "step"] else 1.0
	player.volume_db = -3.0 if cue == "hurt" else 0.0
	player.play()


func set_levels(master: float, music: float, effects: float) -> void:
	_set_level("Master", master)
	_set_level(MUSIC_BUS, music)
	_set_level(EFFECTS_BUS, effects)


func _set_level(bus_name: String, value: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var volume: float = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_mute(index, volume <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, volume)))
