extends RefCounted
class_name VisualAnimation
## Directional pixel animation for the verified visual slice. This adapter only
## selects / draws pixels. It never changes movement, damage, targeting or saves.

const HERO_IDS: Array[String] = ["c01","c04","c07","n01","n02","c02","c03","c05","c06","c08","c09","c10","c11","c12","c13","c14","c15","c16","c17","c18","c19","c20","c21","c22","c23","c24","c25","c26","c27","c28","c29","c30","n03","n04","n05","n06","n07","n08"]
const ENEMY_IDS: Array[String] = ["stalker", "archer", "brute", "mage", "warden"]
const HERO_ACTIONS: Array[String] = ["idle", "walk", "attack", "hit", "cast", "dodge"]
const ENEMY_ACTIONS: Array[String] = ["idle", "walk", "attack", "hit"]
const FRAME_COUNTS: Dictionary = {"idle": 4, "walk": 6, "attack": 6, "hit": 3, "cast": 6, "dodge": 4}
const DIRECTIONS: Array[String] = ["down", "left", "right", "up"]
const STATE_PRIORITY: Dictionary = {"": 0, "idle": 0, "walk": 0, "windup": 1, "attack": 2, "cast": 3, "dodge": 4, "hit": 5}
const DRAW_SCALE: float = 0.9
static var _textures: Dictionary = {}
static var _npc_textures: Dictionary = {}


static func supports(id: String) -> bool:
	return HERO_IDS.has(id.trim_suffix("_festival")) or ENEMY_IDS.has(id)

static func resident_texture_bytes() -> int:
	var total: int = 0
	for cache in [_textures, _npc_textures]:
		for texture in cache.values():
			if texture != null: total += texture.get_width() * texture.get_height() * 4
	return total


static func release_unused(needed: Array) -> void:
	for key in _textures.keys():
		if not needed.has(str(key).trim_suffix("_festival")): _textures.erase(key)
	_npc_textures.clear()


static func facing_index(facing: Vector2) -> int:
	if absf(facing.x) > absf(facing.y):
		return 1 if facing.x < 0.0 else 2
	return 3 if facing.y < 0.0 else 0


static func atlas_texture(id: String) -> Texture2D:
	if not supports(id):
		return null
	if not _textures.has(id):
		var path: String = "res://art/vertical/sprites/" + id + ".png"
		if not ResourceLoader.exists(path):
			push_warning("Vertical-slice atlas unavailable: " + path)
			return null
		_textures[id] = load(path) as Texture2D
	return _textures[id] as Texture2D


static func frame_for_actor(actor: Node2D) -> Dictionary:
	var id: String = str(actor.enemy_kind) if actor.enemy else costume_id(str(actor.id))
	if not supports(id):
		return {}
	var actions: Array[String] = ENEMY_ACTIONS if actor.enemy else HERO_ACTIONS
	var action: String = str(actor.presentation_state)
	var progress: float = float(actor.presentation_elapsed) / maxf(0.001, float(actor.presentation_duration))
	var frame: int = 0
	if actor.enemy and actor.windup > 0.0 and (action.is_empty() or action == "cast"):
		# An actual enemy anticipation uses the first three attack key poses. The
		# attack hook begins the full six-pose motion when damage resolves.
		action = "attack"
		var anticipation: float = clampf(1.0 - actor.windup / maxf(0.001, actor.windup_total), 0.0, 1.0)
		frame = mini(2, int(floor(anticipation * 3.0)))
	elif not action.is_empty() and float(actor.presentation_duration) > 0.0:
		if not actions.has(action):
			action = "attack" if actor.enemy and action == "cast" else "idle"
		frame = mini(int(FRAME_COUNTS[action]) - 1, int(floor(clampf(progress, 0.0, 1.0) * int(FRAME_COUNTS[action]))))
	else:
		action = "walk" if actor.velocity.length_squared() > 25.0 else "idle"
		if actor.statuses.has("freeze") or actor.statuses.has("stun"):
			action = "idle"
			frame = 0
		else:
			frame = posmod(int(floor(actor.animation_time * (10.0 if action == "walk" else 4.0))), int(FRAME_COUNTS[action]))
	var direction: int = facing_index(actor.facing)
	var size: int = 128 if id == "warden" or HERO_IDS.has(id.trim_suffix("_festival")) else 64
	return {"id": id, "action": action, "frame": frame, "direction": DIRECTIONS[direction],
		"region": Rect2((frame + (direction / 2) * 6 if not actor.enemy else frame) * size, (((direction % 2) * actions.size() + actions.find(action)) if not actor.enemy else (direction * actions.size() + actions.find(action))) * size, size, size),
		"size": size, "anchor": Vector2(size * 0.5, size - (12 if size == 128 else 6))}


static func _draw_shadow(canvas: CanvasItem, pos: Vector2, boss: bool, scale_factor: float) -> void:
	var radius: float = (36.0 if boss else 15.0) * scale_factor
	canvas.draw_set_transform(pos.round() + Vector2(0, 2), 0, Vector2(1, 0.29))
	canvas.draw_circle(Vector2.ZERO, radius, Color(0.008, 0.022, 0.033, 0.42))
	canvas.draw_circle(Vector2.ZERO, radius * 0.64, Color(0.003, 0.014, 0.026, 0.28))
	canvas.draw_set_transform(Vector2.ZERO)


static func _draw_frame(canvas: CanvasItem, pos: Vector2, texture: Texture2D, region: Rect2, anchor: Vector2, scale_factor: float, tint: Color = Color.WHITE) -> void:
	var hero_highres: bool = region.size.x == 128 and (texture.get_width() == 1536 or texture.get_height() == 512)
	var scale: float = (0.60 if hero_highres else DRAW_SCALE) * scale_factor
	canvas.draw_texture_rect_region(texture, Rect2(pos.round() - anchor * scale, region.size * scale), region, tint)


static func draw_actor(canvas: CanvasItem, actor: Node2D) -> bool:
	var frame: Dictionary = frame_for_actor(actor)
	if frame.is_empty():
		return false
	var texture: Texture2D = atlas_texture(str(frame.id))
	if texture == null:
		return false
	_draw_shadow(canvas, Vector2.ZERO, actor.boss, 1.0)
	if actor.active and not actor.enemy:
		canvas.draw_arc(Vector2(0, 1), 17.0, 0.0, TAU, 32, Color(0.28, 0.80, 0.72, 0.6), 1.0)
		canvas.draw_arc(Vector2(0, 1), 19.0, PI * 0.1, PI * 0.9, 16, Color(0.91, 0.77, 0.46, 0.6), 1.0)
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(0, -58), Vector2(-3, -62), Vector2(3, -62)]), Color("f2d89b"))
	var tint: Color = Color(1.55, 1.32, 1.20, 1.0) if actor.hurt_flash > 0.0 else Color.WHITE
	if actor.statuses.has("freeze"):
		tint = tint * Color(0.70, 0.91, 1.0, 1.0)
	_draw_frame(canvas, Vector2.ZERO, texture, frame.region, frame.anchor, 1.0, tint)
	# Explicit QA records actual draw calls, so a short pose can be verified even
	# if it recovers between two observer snapshots. This never drives gameplay.
	if bool(actor.get_meta("qa_track_visual", false)):
		var samples: Dictionary = actor.get_meta("qa_drawn_actions", {})
		var sequence: int = int(actor.get_meta("qa_draw_sequence", 0)) + 1
		actor.set_meta("qa_draw_sequence", sequence)
		var r: Rect2 = frame.region
		samples[str(frame.action)] = {"sequence":sequence,"action":frame.action,"frame":frame.frame,"direction":frame.direction,"region":[r.position.x,r.position.y,r.size.x,r.size.y],"drawn_at_msec":Time.get_ticks_msec()}
		actor.set_meta("qa_drawn_actions", samples)
	return true


static func draw_definition(canvas: CanvasItem, pos: Vector2, definition: Dictionary, time: float, facing: Vector2, scale_factor: float = 1.0, active: bool = false) -> bool:
	## NPCs use the same pixel art and costumes as their playable counterparts.
	var base_id: String = str(definition.get("id", ""))
	if definition.get("court", false):
		if not _npc_textures.has(base_id): _npc_textures[base_id] = load("res://art/vertical/court/"+base_id+".png")
		_draw_shadow(canvas, pos, false, scale_factor)
		canvas.draw_texture_rect(_npc_textures[base_id], Rect2(pos-Vector2(64,116)*0.60*scale_factor,Vector2(128,128)*0.60*scale_factor), false)
		return true
	var id: String = costume_id(base_id)
	if not HERO_IDS.has(base_id):
		return false
	var direction: int = facing_index(facing)
	var walking: bool = bool(definition.get("_walking",false))
	var cache_key: String = id + ("_walk" if walking else "_idle")
	if not _npc_textures.has(cache_key):
		_npc_textures[cache_key] = load("res://art/vertical/npc/" + cache_key + ".png")
	var texture: Texture2D = _npc_textures[cache_key]
	if texture == null: return false
	var frame: int = posmod(int(floor(time * (9.0 if walking else 4.0))), 6 if walking else 4)
	var region: Rect2 = Rect2(frame * 128, direction * 128, 128, 128)
	_draw_shadow(canvas, pos, false, scale_factor)
	if active:
		canvas.draw_arc(pos + Vector2(0, 1), 17.0 * scale_factor, 0.0, TAU, 24, Color("8bdac8"), 1.0)
	_draw_frame(canvas, pos, texture, region, Vector2(64, 116), scale_factor)
	return true

static func costume_id(id: String) -> String:
	if id in ["c02","c03","c05"]:
		var state = Engine.get_main_loop().root.get_node_or_null("State")
		if state != null and state.flags.get("festival_unlocked",false) and state.flags.get("outfit_"+id,"") == "festival": return id+"_festival"
	return id
