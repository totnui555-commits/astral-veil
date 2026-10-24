extends SceneTree
var sound_node: Node
var canvas: MediaCanvas

class MediaCanvas extends Node2D:
	var drawn: bool = false
	func _draw() -> void:
		PixelArt.draw_environment(self, {"id": 1, "theme": "forest", "props": [{"kind": "tree", "pos": [240, 260]}, {"kind": "water", "pos": [480, 500]}]}, 1.5)
		for i in range(4):
			PixelArt.draw_character(self, Vector2(100 + i * 50, 160), {"id": "c01"}, float(i) / 5.0, Vector2.LEFT if i % 2 else Vector2.RIGHT, i == 0)
		var kinds: Array = ["warden", "cartographer", "custodian", "leviathan", "choir", "sentinel", "architect"]
		for i in range(kinds.size()):
			PixelArt.draw_enemy(self, Vector2(100 + i * 90, 360), kinds[i], 1.5, i == 3, true)
		for i in range(6):
			PixelArt.draw_effect(self, Vector2(100 + i * 100, 480), ["slash", "lightning", "heal", "dodge", "burst", "ring"][i], 40.0, Color("a9d8cc"), 0.5)
		drawn = true

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	sound_node = root.get_node("Sound")
	canvas = MediaCanvas.new()
	root.add_child(canvas)
	for i in range(1, 31):
		assert(PixelArt.portrait_texture({"id": "c%02d" % i}) != null)
	for i in range(1, 9):
		assert(PixelArt.portrait_texture({"id": "n%02d" % i}) != null)
	var nodes: Array[Node2D] = PixelArt.create_environment_props(canvas, {"theme": "forest", "props": [{"kind": "tree", "pos": [240, 260]}, {"kind": "water", "pos": [480, 500]}]})
	assert(nodes.size() == 2)
	assert(nodes[0].z_index == 260 and nodes[1].z_index == 0)
	canvas.queue_redraw()
	for mood in ["title", "village", "explore", "dungeon", "boss", "ending"]:
		sound_node.play_music(mood)
		var stream: AudioStreamWAV = sound_node.get("_music_streams")[mood]
		assert(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)
		assert(stream.loop_end == int(round(stream.get_length() * stream.mix_rate)))
		assert(stream.get_length() > 10)
	for cue in ["attack", "heavy", "skill", "ultimate", "hurt", "heal", "chest", "boss", "dodge", "defeat", "switch", "quest", "victory"]:
		sound_node.sfx(cue)
	assert(sound_node.get("_effect_players").size() == 12)
	sound_node.set_levels(0.0, 0.25, 0.75)
	assert(AudioServer.is_bus_mute(0))
	assert(absf(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("AstralMusic"))) - 0.25) < 0.001)
	sound_node.set_levels(0.85, 0.65, 0.8)
	await create_timer(0.8).timeout
	assert(canvas.drawn)
	print("MEDIA_SMOKE_OK: 38 portraits, four hero frames, seven bosses, six effects, cached props, six looped scores, 12 pooled voices and volume buses")
	sound_node.stop_all()
	await create_timer(0.1).timeout
	quit(0)
