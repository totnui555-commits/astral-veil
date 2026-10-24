extends SceneTree
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run_checks")
func verify(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
func run_checks() -> void:
	var state: Node = root.get_node("State")
	var db: Node = root.get_node("DB")
	state.save_directory = "user://vertical_environment_test"
	state.new_game()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/vertical/environment/manifest.json"))
	var atlas: Texture2D = load("res://art/vertical/environment/prop_atlas.png")
	verify(atlas != null, "original atlas loads")
	for name in data.definitions:
		var entry: Dictionary = data.definitions[name]
		var rect: Array = entry.region
		verify(float(rect[0]) >= 0 and float(rect[1]) >= 0 and float(rect[0])+float(rect[2]) <= atlas.get_width() and float(rect[1])+float(rect[3]) <= atlas.get_height(), name + " atlas region inside source")
	for map_id in range(4):
		var world: Node2D = load("res://scripts/world.gd").new()
		root.add_child(world)
		world.set_physics_process(false)
		world.load_map(map_id)
		var map: Dictionary = db.map(map_id)
		var group: Node2D = world.get_node("AstralEnvironmentProps")
		verify(group != null, "map %d authored layer" % map_id)
		verify(world.obstacles.size() == map.obstacles.size(), "map %d collision count preserved" % map_id)
		var ground: Texture2D = load("res://art/vertical/environment/map_%d_ground.png" % map_id)
		verify(ground.get_size() == Vector2(800,500), "map %d native ground size" % map_id)
		for child in group.get_children():
			if child is Sprite2D:
				verify(child.texture != null, "map %d prop %s texture" % [map_id, child.name])
		# Every existing blocked prop retains a matching foot depth at the actual
		# collider's lower edge; decor adds no collision nodes or geometry.
		for prop in map.props:
			if prop.kind == "crystal": continue
			var foot_y: float = float(prop.pos[1])
			match str(prop.kind):
				"desk": foot_y += 16
				"pillar": foot_y += 26 if map_id == 3 else 24
				"tree": foot_y += 26
				"house": foot_y += 54
				"rock": foot_y += 18
			var matched: bool = false
			for child in group.get_children():
				if child is Sprite2D and child.texture is AtlasTexture and absf(child.position.x-float(prop.pos[0]))<0.1 and absf(child.position.y-foot_y)<0.1 and child.z_index == int(foot_y):
					matched = true
			verify(matched, "map %d real collider prop at %s" % [map_id, str(prop.pos)])
		verify(world.actors.size() == state.party.size(), "map %d party intact" % map_id)
		if not group.foliage.is_empty():
			var canopy: Sprite2D = group.foliage[0]
			world.actors[0].position = canopy.position - Vector2(0,30)
			group._process(0.5)
			verify(canopy.modulate.a < 0.5, "map %d party occlusion fade" % map_id)
			for actor in world.actors: actor.position = Vector2(800,500)
			group._process(0.5)
			verify(canopy.modulate.a > 0.9, "map %d occlusion recovers" % map_id)
		world.queue_free()
		await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(0.1).timeout
	print("VERTICAL_ENVIRONMENT_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
