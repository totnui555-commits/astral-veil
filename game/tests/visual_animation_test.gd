extends SceneTree
## Contract / action integration checks for the existing gameplay actor. This
## does not inject a new movement or combat system into the visual slice.

const ActorScript = preload("res://scripts/actor.gd")
const AnimationArt = preload("res://scripts/visual_animation.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("VISUAL_ANIMATION_CHECK: " + label)

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/vertical/sprites/manifest.json"))
	check(int(manifest.total_decoded_rgba_bytes) <= 400 * 1024 * 1024, "complete cast atlas decode budget")
	var count: int = 0
	var expected_frames: int = 0
	for id in manifest.assets:
		var record: Dictionary = manifest.assets[id]
		for action in record.actions: expected_frames += int(record.actions[action].frames) * 4
		var actor: Node2D = ActorScript.new()
		root.add_child(actor)
		actor.id = id
		actor.definition = {"id": id}
		actor.enemy = id in AnimationArt.ENEMY_IDS
		actor.enemy_kind = id
		actor.boss = id == "warden"
		var texture: Texture2D = AnimationArt.atlas_texture(id)
		check(texture != null, id + " resource resolves")
		check(texture.get_size() == Vector2(record.atlas_size[0],record.atlas_size[1]), id + " atlas exact dimensions")
		check(texture.get_width() <= 2048 and texture.get_height() <= 2048, id + " web-safe maximum dimensions")
		var directions: Array[Vector2] = [Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT,Vector2.UP]
		for di in range(4):
			actor.facing = directions[di]
			for action in record.actions:
				var frames: int = int(record.actions[action].frames)
				for fr in range(frames):
					actor.presentation_state = ""
					actor.presentation_duration = 0.0
					actor.set_presentation_state(action,1.0)
					actor.presentation_elapsed = (float(fr)+0.1)/frames
					var selected: Dictionary = AnimationArt.frame_for_actor(actor)
					check(selected.action == action and int(selected.frame) == fr and selected.direction == AnimationArt.DIRECTIONS[di], id + " " + str(di) + " " + action + " " + str(fr))
					check(Rect2(Vector2.ZERO,texture.get_size()).encloses(selected.region), id + " frame in texture bounds")
					count += 1
				var variation: Dictionary = record.frame_variation[AnimationArt.DIRECTIONS[di]+"/"+action]
				check(int(variation.distinct) == frames, id + " poses differ " + action)
		actor.presentation_state = ""
		actor.presentation_duration = 0.0
		actor.velocity = Vector2.RIGHT*120
		check(AnimationArt.frame_for_actor(actor).action == "walk", id + " existing velocity selects walk")
		actor.statuses["freeze"] = 1.0
		check(AnimationArt.frame_for_actor(actor).action == "idle", id + " freeze does not show running")
		actor.statuses.clear()
		actor.set_presentation_state("hit",0.2)
		actor.set_presentation_state("attack",0.3)
		check(actor.presentation_state == "hit", id + " hit presentation priority")
		actor.tick(0.25)
		check(actor.presentation_state.is_empty() and actor.presentation_duration == 0.0, id + " action exits without stuck pose")
		var snapshot: Array = [actor.hp,actor.max_hp,actor.mp,actor.ultimate_charge,actor.attack_cooldown,actor.skill_cooldown,actor.dodge_cooldown,actor.position,actor.velocity,actor.facing]
		actor.set_presentation_state("cast",0.5)
		check(snapshot == [actor.hp,actor.max_hp,actor.mp,actor.ultimate_charge,actor.attack_cooldown,actor.skill_cooldown,actor.dodge_cooldown,actor.position,actor.velocity,actor.facing], id + " presentation setter preserves combat and movement")
		if actor.enemy:
			actor.presentation_state = ""
			actor.presentation_duration = 0.0
			actor.windup_total = 1.0
			for anticipation in range(3):
				actor.windup = 1.0-(float(anticipation)+0.1)/3.0
				check(int(AnimationArt.frame_for_actor(actor).frame) == anticipation, id + " enemy anticipation pose")
		actor.queue_free()
	check(count == expected_frames, "all committed directional frames exercised")
	var legacy: Node2D = ActorScript.new()
	legacy.id = "c06"
	check(not AnimationArt.frame_for_actor(legacy).is_empty(), "new full-cast heroes use integrated renderer")
	legacy.free()
	await process_frame
	print("VISUAL_ANIMATION_TEST: %d checks, %d failures; %d frame selections across full cast, four actual directions, action lifetime, presentation isolation, memory bounds." % [checks,failures,count])
	root.get_node("Sound").stop_all()
	await create_timer(0.1).timeout
	quit(0 if failures == 0 else 1)
