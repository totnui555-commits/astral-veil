extends RefCounted
class_name VisualEnvironment
## Four authored opening-map compositions. Gameplay geometry remains in maps.json.
## Backgrounds are 800x500 artwork drawn at exactly 2x nearest; prop regions are
## cached from one original atlas. No per-frame loads, texture edits or shaders.

const ROOT: String = "res://art/vertical/environment/"
static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}
static var _regions: Dictionary = {}


class EnvironmentLayer extends Node2D:
	var world: Node2D
	var foliage: Array[Sprite2D] = []
	var lamps: Array[Sprite2D] = []
	var clock: float = 0.0
	var sample_clock: float = 0.0

	func _process(delta: float) -> void:
		clock += delta
		sample_clock -= delta
		# Fade only canopy/building silhouettes that hide a live party member.
		# This is presentation-only: no actor/collision/state property is changed.
		if sample_clock <= 0.0:
			sample_clock = 0.065
			var party: Array = world.get("actors") if is_instance_valid(world) else []
			for prop in foliage:
				var covered: bool = false
				for actor in party:
					if not is_instance_valid(actor) or actor.get("defeated"):
						continue
					var feet: Vector2 = actor.global_position
					if feet.y > prop.global_position.y + 8.0:
						continue
					# Also test the hero's upper body, not only its foot anchor.
					if prop.get_rect().grow(12.0).has_point(prop.to_local(feet - Vector2(0, 23))):
						covered = true
						break
				prop.set_meta("veil_cover", covered)
		for prop in foliage:
			var target: float = 0.35 if bool(prop.get_meta("veil_cover", false)) else 1.0
			prop.modulate.a = move_toward(prop.modulate.a, target, delta * 4.2)
		for index in range(lamps.size()):
			var lamp: Sprite2D = lamps[index]
			lamp.modulate.a = 0.38 + sin(clock * 1.8 + index * 2.7) * 0.025 + sin(clock * 5.1 + index) * 0.012


static func supports(map_data: Dictionary) -> bool:
	return int(map_data.get("id", -1)) in [0, 1, 2, 3]


static func _data() -> Dictionary:
	if _manifest.is_empty():
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
		if raw is Dictionary:
			_manifest = raw
	return _manifest


static func texture(path: String) -> Texture2D:
	if not _textures.has(path):
		var image: Texture2D = load(path) as Texture2D
		if image != null:
			_textures[path] = image
	return _textures.get(path, null)


static func _region(kind: String) -> AtlasTexture:
	if _regions.has(kind):
		return _regions[kind]
	var definition: Dictionary = _data().get("definitions", {}).get(kind, {})
	if definition.is_empty():
		return null
	var area: Array = definition.get("region", [0, 0, 1, 1])
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = texture(ROOT + "prop_atlas.png")
	atlas.region = Rect2(float(area[0]), float(area[1]), float(area[2]), float(area[3]))
	atlas.filter_clip = true
	_regions[kind] = atlas
	return atlas


static func create_props(world: Node2D, map_data: Dictionary) -> Array[Node2D]:
	var group: EnvironmentLayer = EnvironmentLayer.new()
	group.name = "AstralEnvironmentProps"
	group.world = world
	world.add_child(group)
	var nodes: Array[Node2D] = []
	var map_id: int = int(map_data.get("id", 0))
	var visual_id: int = int(map_data.get("visual_map", map_id))
	var entries: Array = [] if map_id == 1 or map_data.get("theme", "") == "throne" else _data().get("placements", {}).get(str(visual_id), [])
	for value in entries:
		var entry: Dictionary = value
		var kind: String = str(entry.get("kind", "rock"))
		var definition: Dictionary = _data().get("definitions", {}).get(kind, {})
		var atlas: AtlasTexture = _region(kind)
		if atlas == null:
			continue
		var sprite: Sprite2D = Sprite2D.new()
		sprite.name = kind + "_" + str(nodes.size())
		sprite.texture = atlas
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.centered = false
		var anchor: Array = definition.get("anchor", [0, 0])
		sprite.offset = -Vector2(float(anchor[0]), float(anchor[1]))
		var point: Array = entry.get("pos", [0, 0])
		sprite.position = Vector2(float(point[0]), float(point[1])).round()
		var factor: float = float(entry.get("scale", definition.get("scale", 0.3)))
		sprite.scale = Vector2.ONE * factor
		# Low flowers/fern beds are ground decoration. Solid prop and canopy feet
		# share the exact same integer foot depth as the existing hero actors.
		sprite.z_index = 1 if kind in ["flowers", "ferns", "fallen"] else int(sprite.position.y)
		group.add_child(sprite)
		nodes.append(sprite)
		if bool(entry.get("fade", false)):
			group.foliage.append(sprite)
		if kind in ["lamp", "crystal"]:
			var glow: Sprite2D = Sprite2D.new()
			glow.texture = texture(ROOT + "light_pool.png")
			glow.position = sprite.position + Vector2(0, -52 if kind == "lamp" else -12)
			glow.scale = Vector2(1.0, 0.63) * (1.35 if kind == "lamp" else 1.05)
			glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			glow.z_index = 2
			glow.modulate = Color("f6cc86") if kind == "lamp" else Color("75dacf")
			glow.modulate.a = 0.38
			var material: CanvasItemMaterial = CanvasItemMaterial.new()
			material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			glow.material = material
			group.add_child(glow)
			group.lamps.append(glow)
	return nodes


static func draw_ground(canvas: CanvasItem, map_data: Dictionary, time: float) -> void:
	var map_id: int = int(map_data.get("id", 0))
	var ground: Texture2D = texture(ROOT + str(map_data.get("ground", "map_%d_ground.png" % map_id)))
	if ground != null:
		canvas.draw_texture_rect(ground, Rect2(0, 0, 1600, 1000), false)
	if map_id == 1:
		var district: Texture2D = texture(ROOT+"market_ground.png")
		if district != null: canvas.draw_texture_rect(district,Rect2(1600,0,1600,1000),false)
	# Sparse slow motes match the map's light, while combat remains high contrast.
	var color: Color = Color("e2d6a9") if map_id in [0, 1, 2] else Color("87c7b8")
	color.a = 0.20
	for index in range(16):
		var x: float = fposmod(float(index * 173 + 81) + sin(time * 0.24 + index) * 22, 1480) + 60
		var y: float = fposmod(float(index * 101 + 53) - time * 2.4, 870) + 65
		canvas.draw_rect(Rect2(Vector2(x, y).snapped(Vector2(2, 2)), Vector2(2, 2)), color)
