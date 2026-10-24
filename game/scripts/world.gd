extends Node2D

signal stage_ready
signal interacted(kind: String, data: Dictionary)
signal boss_defeated(id: String)
signal party_defeated
signal message(text: String)

const Actor = preload("res://scripts/actor.gd")
const Art = preload("res://scripts/pixel_art.gd")
const Skills = preload("res://scripts/combat_skills.gd")
const Presentation = preload("res://scripts/visual_combat.gd")
const InteractableArt = preload("res://scripts/visual_interactables.gd")

var actors: Array = []
var enemies: Array = []
var map_data: Dictionary = {}
var activated_sigils: Array = []
var camera: Camera2D
var paused: bool = false
var elapsed: float = 0.0
var obstacles: Array = []
var effects: Array = []
var projectiles: Array = []
var zones: Array = []
var summons: Array = []
var floating_text: Array = []
var pickups: Array = []
var opened_chests: Array = []
var input_vector: Vector2 = Vector2.ZERO
var camp_position: Vector2 = Vector2.ZERO
var ready_emitted: bool = false
var defeat_emitted: bool = false
var reinforcement_timer: float = 0.0
var reward_scale: float = 1.0
var combat_intent: float = 0.0
var relay_time: float = 0.0
var relay_from: String = ""
var relay_target: Node2D
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var draw_font: Font
var screen_shake: float = 0.0
var _consumable_timer: float = 0.0
var _mouse_attack_held: bool = false
var _combat_presentation: Node2D

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rng.randomize()
	if OS.get_cmdline_user_args().has("--qa"):
		rng.seed = 739137
	draw_font = VeilUI.theme().default_font
	_combat_presentation = Presentation.new()
	add_child(_combat_presentation)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 9.0
	camera.zoom = Vector2(1.25, 1.25)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = 1600
	camera.limit_bottom = 1000
	add_child(camera)
	camera.make_current()
	State.changed.connect(_refresh_live_stats)

func _t(en: String, th: String) -> String:
	return th if State.language == "th" else en

func _present(actor: Node2D, state: String, duration: float) -> void:
	# Optional art adapter: presentation never controls an approved action.
	if is_instance_valid(actor) and actor.has_method("set_presentation_state"):
		actor.set_presentation_state(state, duration)

func load_map(id: int) -> void:
	if not actors.is_empty():
		sync_to_state()
	for actor in actors + enemies:
		if is_instance_valid(actor):
			remove_child(actor)
			actor.queue_free()
	actors.clear()
	enemies.clear()
	projectiles.clear()
	effects.clear()
	zones.clear()
	summons.clear()
	pickups.clear()
	floating_text.clear()
	activated_sigils.clear()
	opened_chests.clear()
	obstacles.clear()
	_mouse_attack_held = false
	input_vector = Vector2.ZERO
	var old_props: Node = get_node_or_null("AstralEnvironmentProps")
	if old_props != null:
		remove_child(old_props)
		old_props.queue_free()
	map_data = DB.map(id)
	if id == 0 and State.flags.get("royal_forest", false):
		map_data = DB.forest_prologue
	camera.limit_right = int(map_data.get("width",1600))
	camera.limit_bottom = int(map_data.get("height",1000))
	var needed_art: Array = State.party.duplicate()
	 # NPC poses use a separate compact cache; retain only active combat atlases.
	for foe in map_data.get("enemies",[]): needed_art.append(str(foe.get("kind","")))
	needed_art.append(str(map_data.get("boss",{}).get("kind","")))
	VisualAnimation.release_unused(needed_art)
	State.stage = id
	ready_emitted = false
	defeat_emitted = false
	reinforcement_timer = 0.0
	elapsed = 0.0
	combat_intent = 0.0
	relay_time = 0.0
	relay_from = ""
	relay_target = null
	for obstacle in map_data.get("obstacles", []):
		obstacles.append(Rect2(float(obstacle[0]), float(obstacle[1]), float(obstacle[2]), float(obstacle[3])))
	Art.create_environment_props(self, map_data)
	var spawn: Vector2 = _vec(map_data.get("spawn", [160, 500]))
	if id == 1 and State.respite_next() > 0: spawn = Vector2(530,470)
	camp_position = _vec(map_data.get("camp", [spawn.x, spawn.y + 85]))
	if blocked(camp_position, 14):
		camp_position = spawn + Vector2(70, 0)
	InteractableArt.create_layers(self)
	for i in range(State.party.size()):
		var actor: Node2D = _make_hero(str(State.party[i]))
		actor.position = spawn + Vector2(-float(i) * 22, float(i) * 23)
		actors.append(actor)
	State.active_index = clampi(State.active_index, 0, maxi(0, actors.size() - 1))
	for entry in map_data.get("enemies", []):
		_spawn_enemy(entry)
	var boss_data: Dictionary = map_data.get("boss", {})
	if not boss_data.is_empty():
		_spawn_enemy(boss_data, true)
	for chest in map_data.get("chests", []):
		if State.flags.get("chest_" + str(chest.get("id", "")), false):
			opened_chests.append(str(chest.get("id", "")))
	if camera != null:
		camera.position = spawn
		camera.reset_smoothing()
	_update_active()
	_check_objectives()
	queue_redraw()

func _vec(value) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

func _make_hero(id: String) -> Node2D:
	var actor: Node2D = Actor.new()
	actor.id = id
	actor.definition = DB.character(id)
	add_child(actor)
	_refresh_stats(actor)
	var record: Dictionary = State.hero(id)
	actor.hp = clampf(float(record.get("hp", actor.max_hp)), 0, actor.max_hp)
	actor.mp = clampf(float(record.get("mp", actor.max_mp)), 0, actor.max_mp)
	actor.ultimate_charge = clampf(float(record.get("ultimate_charge", 0)), 0, 100)
	var cooldowns: Dictionary = record.get("cooldowns", {})
	actor.attack_cooldown = maxf(0, float(cooldowns.get("attack", 0)))
	actor.skill_cooldown = maxf(0, float(cooldowns.get("skill", 0)))
	actor.dodge_cooldown = maxf(0, float(cooldowns.get("dodge", 0)))
	actor.defeated = actor.hp <= 0
	return actor

func _refresh_stats(actor: Node2D) -> void:
	var stats: Dictionary = State.derived(actor.id)
	actor.level = int(stats.get("level", 1))
	actor.max_hp = float(stats.get("max_hp", 180))
	actor.max_mp = float(stats.get("max_mp", 80))
	actor.attack_power = float(stats.get("attack", 32))
	actor.magic_power = float(stats.get("power", 38))
	actor.defense = float(stats.get("defense", 9))
	actor.speed = float(stats.get("speed", 165))
	actor.crit = float(stats.get("crit", 0.08))
	actor.hp = minf(actor.hp, actor.max_hp)
	actor.mp = minf(actor.mp, actor.max_mp)

func _refresh_live_stats() -> void:
	# Equipment, allocated points and earned levels take effect in the current
	# encounter. A level grants the same recovery as rebuilding the saved hero.
	for actor in actors:
		if not is_instance_valid(actor) or State.hero(actor.id).is_empty():
			continue
		var previous_level: int = actor.level
		_refresh_stats(actor)
		if actor.level > previous_level:
			actor.hp = actor.max_hp
			actor.mp = actor.max_mp
			actor.defeated = false
			actor.statuses.clear()
			effect(actor.position, "heal", 40, Color("9aedbf"), 0.8)
	_update_active()

func refresh_party() -> void:
	sync_to_state()
	var needed: Array = State.party.duplicate()
	for foe in enemies:
		if is_instance_valid(foe): needed.append(str(foe.enemy_kind))
	VisualAnimation.release_unused(needed)
	var origin: Vector2 = active_actor().position if active_actor() != null else camp_position
	var previous: Array = actors.duplicate()
	actors = []
	for id in State.party:
		var retained: Node2D = null
		for actor in previous:
			if actor.id == str(id):
				retained = actor
				break
		if retained == null:
			retained = _make_hero(str(id))
			retained.position = origin + Vector2(-20 * actors.size(), 22 * actors.size())
		else:
			_refresh_stats(retained)
		actors.append(retained)
	for actor in previous:
		if not actors.has(actor):
			actor.queue_free()
	State.active_index = clampi(State.active_index, 0, maxi(0, actors.size() - 1))
	_update_active()

func _spawn_enemy(entry: Dictionary, is_boss: bool = false) -> Node2D:
	var actor: Node2D = Actor.new()
	actor.enemy = true
	actor.id = str(entry.get("id", entry.get("kind", "stalker")))
	actor.enemy_kind = str(entry.get("kind", "stalker"))
	actor.definition = entry
	actor.boss = is_boss
	actor.position = _vec(entry.get("pos", [800, 500]))
	var stage: int = int(map_data.get("id", 0))
	var factor: float = 0.78 if State.difficulty == "story" else (1.22 if State.difficulty == "hard" else 1.0)
	actor.max_hp = float(entry.get("hp", 88 + stage * 22)) * factor
	if is_boss:
		actor.max_hp = float(entry.get("hp", 800 + stage * 125)) * factor
	else:
		if actor.enemy_kind == "brute":
			actor.max_hp *= 1.8
	if bool(entry.get("elite", false)):
		actor.max_hp *= 1.6
	actor.hp = actor.max_hp
	actor.attack_power = (18.0 + stage * 3.3) * factor * (1.5 if is_boss else 1.0)
	if bool(entry.get("elite", false)):
		actor.attack_power *= 1.25
	actor.defense = 1.5 + stage * 0.65
	actor.speed = (78.0 if actor.enemy_kind == "brute" else 142.0 if actor.enemy_kind == "stalker" else 100.0) + stage * 1.1
	if is_boss:
		actor.speed = 67.0
	actor.phase_count = maxi(1, int(entry.get("phases", 3)))
	actor.attack_timer = rng.randf_range(0.9, 2.5)
	actor.z_index = int(actor.position.y)
	add_child(actor)
	enemies.append(actor)
	return actor

func active_actor() -> Node2D:
	if actors.is_empty():
		return null
	return actors[clampi(State.active_index, 0, actors.size() - 1)]

func switch_to(index: int) -> void:
	if paused or index == State.active_index or index < 0 or index >= actors.size() or actors[index].defeated:
		return
	State.active_index = index
	_update_active()
	var next: Node2D = actors[index]
	if relay_time > 0 and next.id != relay_from:
		relay_time = 0.0
		next.mp = minf(next.max_mp, next.mp + 12)
		next.skill_cooldown = maxf(0, next.skill_cooldown - 3)
		next.set_meta("relay_until", elapsed + 6.0)
		effect(next.position, "skybreak", 65, Color("f3db99"), 0.7)
		message.emit(_t("RELAY · +12 mana · skill recovery · next hit +50%", "ส่งต่อ! +12 มานา · ลดเวลารอสกิล · ครั้งถัดไปแรงขึ้น 50%"))
	Sound.sfx("switch")
	State.changed.emit()

func _update_active() -> void:
	for i in range(actors.size()):
		actors[i].active = i == State.active_index
	if active_actor() != null and active_actor().defeated:
		for i in range(actors.size()):
			if not actors[i].defeated:
				State.active_index = i
				_update_active()
				return

func set_input_vector(value: Vector2) -> void:
	input_vector = value.limit_length(1.0)

func _input(event: InputEvent) -> void:
	# A release over a HUD control must still stop a hold that began in the world.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_mouse_attack_held = false

func _unhandled_input(event: InputEvent) -> void:
	# Only presses that survive GUI handling can start combat. Polling a mapped
	# mouse button would also attack when the player clicks menus and dialogue.
	if paused or not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_attack_held = true
		attack()
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		attack(true)
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if paused or map_data.is_empty() or actors.is_empty() or defeat_emitted:
		_mouse_attack_held = false
		return
	elapsed += delta
	relay_time = maxf(0, relay_time - delta)
	_consumable_timer = maxf(0, _consumable_timer - delta)
	var leader: Node2D = active_actor()
	var movement: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length_squared() > 0.01:
		movement = input_vector
	if not leader.defeated and not leader.statuses.has("stun"):
		var speed: float = leader.speed * _speed_factor(leader)
		leader.velocity = movement * speed
		move_actor(leader, leader.velocity * delta)
		if movement.length_squared() > 0.01:
			leader.facing = movement.normalized()
	if Input.is_action_pressed("attack") or _mouse_attack_held:
		attack()
	if Input.is_action_just_pressed("heavy"):
		attack(true)
	if Input.is_action_just_pressed("skill"):
		skill()
	if Input.is_action_just_pressed("ultimate"):
		ultimate()
	if Input.is_action_just_pressed("dodge"):
		dodge()
	if Input.is_action_just_pressed("switch_next"):
		for offset in range(1, actors.size() + 1):
			var index: int = (State.active_index + offset) % actors.size()
			if not actors[index].defeated:
				switch_to(index)
				break
	if Input.is_action_just_pressed("interact"):
		interact()
	combat_intent = maxf(0.0,combat_intent-delta)
	for actor in actors:
		actor.tick(delta)
		_tick_statuses(actor)
		if not actor.active and not actor.defeated:
			_ally_ai(actor, delta)
		actor.z_index = int(actor.position.y)
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy) or enemy.defeated:
			continue
		enemy.tick(delta)
		_tick_statuses(enemy)
		if enemy.defeated:
			continue
		_enemy_ai(enemy, delta)
		enemy.z_index = int(enemy.position.y)
	_tick_projectiles(delta)
	_tick_zones(delta)
	_tick_summons(delta)
	_tick_effects(delta)
	_tick_pickups(delta)
	State.tick_threat(delta)
	if not map_data.get("safe", false) and not ready_emitted:
		reinforcement_timer += delta
		if reinforcement_timer > 75.0:
			reinforcement_timer = 0.0
			_spawn_reinforcement()
	if camera != null:
		camera.position = active_actor().position
		screen_shake = maxf(0, screen_shake - delta * 18)
		camera.offset = Vector2(rng.randf_range(-screen_shake, screen_shake), rng.randf_range(-screen_shake, screen_shake))
	_check_objectives()
	queue_redraw()

func _speed_factor(actor: Node2D) -> float:
	if actor.statuses.has("root") or actor.statuses.has("freeze") or actor.statuses.has("stun"):
		return 0.0
	var factor: float = 1.0
	if actor.statuses.has("slow"):
		factor *= 0.48
	if actor.statuses.has("haste"):
		factor *= 1.4
	if actor.statuses.has("frenzy"):
		factor *= 1.2
	return factor

func blocked(pos: Vector2, radius: float = 11.0) -> bool:
	if pos.x < 28 + radius or pos.y < 28 + radius or pos.x > float(map_data.get("width",1600)) - 28 - radius or pos.y > float(map_data.get("height",1000)) - 28 - radius:
		return true
	for obstacle in obstacles:
		if obstacle.grow(radius).has_point(pos):
			return true
	return false

func move_actor(actor: Node2D, displacement: Vector2) -> void:
	var steps: int = maxi(1, int(ceil(displacement.length() / 8.0)))
	var step: Vector2 = displacement / float(steps)
	for i in range(steps):
		var next: Vector2 = actor.position + Vector2(step.x, 0)
		if not blocked(next, 15.0 if actor.boss else 10.0):
			actor.position.x = next.x
		next = actor.position + Vector2(0, step.y)
		if not blocked(next, 15.0 if actor.boss else 10.0):
			actor.position.y = next.y

func _has_line(from: Vector2, to: Vector2) -> bool:
	var steps: int = maxi(1, int(ceil(from.distance_to(to) / 6.0)))
	for i in range(1, steps):
		if blocked(from.lerp(to, float(i) / steps), 0.0):
			return false
	return true

func nearest_enemy(pos: Vector2) -> Node2D:
	var result: Node2D = null
	var closest: float = INF
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.defeated:
			continue
		var distance: float = pos.distance_squared_to(enemy.position)
		if distance < closest:
			closest = distance
			result = enemy
	return result

func _nearest_ally(pos: Vector2) -> Node2D:
	var result: Node2D = null
	var distance: float = INF
	for actor in actors:
		if actor.defeated or actor.statuses.has("invisible"):
			continue
		var next: float = pos.distance_squared_to(actor.position)
		if actor.active:
			next *= 0.72
		if next < distance:
			distance = next
			result = actor
	return result

func attack(heavy: bool = false) -> void:
	var actor: Node2D = active_actor()
	if paused or actor == null or actor.defeated:
		return
	combat_intent = 5.0
	_attack_actor(actor, heavy)

func _attack_actor(actor: Node2D, heavy: bool = false) -> void:
	if actor.attack_cooldown > 0.0 or actor.statuses.has("stun") or actor.statuses.has("freeze"):
		return
	var heavy_cost: float = 4.0 if _relic_effect(actor) == "breaker" else 8.0
	if heavy and actor.mp < heavy_cost:
		if actor.active:
			message.emit(_t("Not enough mana", "มานาไม่พอ"))
		return
	if heavy:
		actor.mp -= heavy_cost
	actor.attack_cooldown = (0.78 if heavy else 0.36) if actor.active else 0.95
	if actor.statuses.has("frenzy"):
		actor.attack_cooldown *= 0.62
	if actor.statuses.has("haste"):
		actor.attack_cooldown *= 0.8
	var target: Node2D = nearest_enemy(actor.position)
	var direction: Vector2 = actor.facing
	if target != null and actor.position.distance_to(target.position) < 520:
		direction = actor.position.direction_to(target.position)
	actor.facing = direction
	_present(actor, "attack", 0.38 if heavy else 0.30)
	var finisher: bool = actor.active and not heavy and actor.chain_count >= 2
	if actor.active:
		actor.chain_count = 0 if heavy or finisher else actor.chain_count+1
		actor.chain_window = 1.25
	var weapon: String = str(actor.definition.get("weapon", "melee"))
	var damage: float = actor.attack_power * (1.9 if heavy else 1.0)
	if finisher: damage *= 1.65
	if actor.counter_window > 0:
		damage *= 1.6
		actor.counter_window = 0
		effect(actor.position,"skybreak",55,Color("b4efff"),0.5)
	if heavy and _relic_effect(actor) == "breaker": damage *= 1.25
	var color: Color = Color(actor.definition.get("color", "83d9ce"))
	if weapon != "melee":
		projectile(actor.position + direction * 16, direction, damage, actor, color, 460.0 if weapon == "ranged" else 350.0, heavy, heavy or finisher)
		if heavy:
			projectile(actor.position + direction * 16, direction.rotated(-0.16), damage * 0.55, actor, color, 410.0)
			projectile(actor.position + direction * 16, direction.rotated(0.16), damage * 0.55, actor, color, 410.0)
	else:
		var radius: float = 100.0 if heavy else 69.0
		effect(actor.position + direction * 24, "crescent" if finisher or heavy else "slash", radius * 0.7, color, 0.38 if finisher or heavy else 0.19, direction.angle())
		for enemy in enemies.duplicate():
			var toward: Vector2 = enemy.position - actor.position
			if toward.length() < radius + (16 if enemy.boss else 5) and toward.normalized().dot(direction) > (-0.2 if heavy else 0.15) and _has_line(actor.position, enemy.position):
				if heavy or finisher: _break_windup(enemy, actor)
				damage_enemy(enemy, damage, actor, direction * (27 if heavy else 7))
	Sound.sfx("heavy" if heavy else "attack")
	actor.statuses.erase("invisible")

func skill() -> void:
	var actor: Node2D = active_actor()
	if paused or actor == null or actor.defeated:
		return
	combat_intent = 5.0
	_cast_skill(actor)

func _cast_skill(actor: Node2D) -> void:
	if actor.skill_cooldown > 0 or actor.statuses.has("stun") or actor.statuses.has("freeze"):
		return
	var cost: float = 18.0
	if actor.mp < cost:
		if actor.active:
			message.emit(_t("Need 18 mana", "ต้องใช้มานา 18 หน่วย"))
		return
	actor.mp -= cost
	var rank: int = int(State.derived(actor.id).get("skill_rank", 1))
	actor.skill_cooldown = maxf(3.2, 6.5 - rank * 0.5) * (1.0 if actor.active else 1.8)
	_present(actor, "cast", 0.48)
	effect(actor.position, "ring", 34, Color("b7e5d4"), 0.46)
	Skills.cast(self, actor, false)
	actor.ultimate_charge = minf(100, actor.ultimate_charge + 5)
	Sound.sfx("skill")

func ultimate() -> void:
	var actor: Node2D = active_actor()
	if paused or actor == null or actor.defeated or actor.statuses.has("stun") or actor.statuses.has("freeze"):
		return
	if actor.ultimate_charge < 100:
		message.emit(_t("Ultimate is still charging", "พลังท่าไม้ตายยังไม่เต็ม"))
		return
	actor.ultimate_charge = 0
	actor.invulnerable = 0.85
	_present(actor, "cast", 0.60)
	effect(actor.position, "ring", 65, Color("f4daa5"), 0.65)
	Skills.cast(self, actor, true)
	screen_shake = 4
	message.emit(DB.localized(actor.definition.get("ultimate_name", {"en": "Astral awakening", "th": "พลังดวงดาวตื่นขึ้น"})))
	Sound.sfx("ultimate")

func dodge() -> void:
	var actor: Node2D = active_actor()
	if paused or actor == null or actor.defeated or actor.dodge_cooldown > 0 or actor.statuses.has("stun") or actor.statuses.has("freeze"):
		return
	var direction: Vector2 = actor.facing
	var movement: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length() > 0.1:
		movement = input_vector
	if movement.length() > 0.1:
		direction = movement.normalized()
	for foe in enemies:
		if foe.windup > 0 and foe.windup < 0.25 and _inside_warning(actor.position,foe):
			actor.counter_window = 2.0
			actor.skill_cooldown = maxf(0,actor.skill_cooldown-2.0)
			actor.mp = minf(actor.max_mp,actor.mp+8)
			if _relic_effect(actor) == "hearthlight": heal_actor(actor, actor.max_hp * 0.08)
			_float(actor.position+Vector2(0,-60),_t("PERFECT · COUNTER!","หลบพอดี · สวนกลับ!"),Color("a9f6ef"))
			break
	actor.dodge_cooldown = 1.1
	actor.invulnerable = 0.42
	actor.statuses.erase("root")
	actor.statuses.erase("slow")
	_present(actor, "dodge", 0.24)
	effect(actor.position, "dodge", 27, Color(0.7, 0.9, 1, 0.7), 0.3, direction.angle())
	move_actor(actor, direction * 108)
	if _relic_effect(actor) == "second_wind":
		heal_actor(actor, actor.max_hp * 0.06)
		actor.mp = minf(actor.max_mp, actor.mp + 4)
	Sound.sfx("dodge")

func _relic_effect(actor: Node2D) -> String:
	return str(DB.item(str(State.hero(actor.id).get("equipment", {}).get("relic", ""))).get("effect", ""))

func _break_windup(enemy: Node2D, source: Node2D) -> void:
	if enemy.defeated or seal_active(enemy): return
	if enemy.windup <= 0 and not guard_active(enemy): return
	var hits: int = int(enemy.get_meta("poise_hits", 0)) + 1
	enemy.set_meta("poise_hits", hits)
	if enemy.boss and hits < 3: return
	enemy.set_meta("poise_hits", 0)
	enemy.windup = 0
	enemy.guard_open = 2.5
	enemy.recovery = 1.25
	enemy.attack_timer = 2.0
	apply_status(enemy, "stun", 0.65 if enemy.boss else 1.25)
	apply_status(enemy, "weakness", 2.5)
	source.mp = minf(source.max_mp, source.mp + 5)
	effect(enemy.position, "burst", 46, Color("9ce3d6"), 0.45)
	_float(enemy.position + Vector2(0,-52), _t("BREAK", "เสียหลัก"), Color("9ce3d6"))
	if source.active and elapsed >= float(enemy.get_meta("relay_ready_at", -1.0)) and not seal_active(enemy):
		enemy.set_meta("relay_ready_at", elapsed + 8.0)
		relay_time = 3.0
		relay_from = source.id
		relay_target = enemy
		message.emit(_t("BREAK → switch ally to RELAY! [Tab / 1–3]  ·  [F] Tactics", "เสียหลัก → สลับเพื่อนส่งต่อคอมโบ! [Tab / 1–3] · [F] วางแผน"))

func _drop_equipment(enemy: Node2D) -> void:
	var item: String = ""
	var boss_loot: Dictionary = {"warden":"r01","cartographer":"r02","custodian":"r03","leviathan":"r04","choir":"r05","sentinel":"r06","architect":"r07"}
	if enemy.boss:
		item = str(boss_loot.get(enemy.enemy_kind,"r01"))
	elif bool(enemy.definition.get("elite",false)) or int(State.flags.get("loot_pity",0)) >= 3 or rng.randf() < 0.14:
		var choices: Array = ["w05","x02","a02"] if enemy.enemy_kind == "archer" else ["w04","x04","a03"] if enemy.enemy_kind == "mage" else ["w01","a01","x01"]
		item = str(choices[rng.randi_range(0,choices.size()-1)])
		State.flags["loot_pity"] = 0
	else:
		State.flags["loot_pity"] = int(State.flags.get("loot_pity",0)) + 1
	if item.is_empty(): return
	# Award valuable drops immediately: death, saving or crossing maps cannot lose them.
	# The ground beam is the reward reveal, never a second inventory grant.
	State.add_item(item,1)
	pickups.append({"pos":enemy.position+Vector2(15,0),"item":item,"count":1,"life":5.0,"awarded":true})
	message.emit(_t("Obtained · ","ได้รับ · ") + DB.localized(DB.item(item).get("name",item)) + _t("  [I] Inspect / equip", "  [I] ดู / สวมใส่"))
	Sound.sfx("chest")

func guard_active(enemy: Node2D) -> bool:
	return enemy.enemy_kind == "brute" and not enemy.boss and enemy.guard_open <= 0 and not enemy.statuses.has("stun") and not enemy.statuses.has("freeze")

func damage_enemy(enemy: Node2D, amount: float, source: Node2D, knockback: Vector2 = Vector2.ZERO) -> float:
	if not is_instance_valid(enemy) or enemy.defeated:
		return 0.0
	if seal_active(enemy): return 0.0
	var multiplier: float = 1.0
	if source != null and not source.active:
		multiplier = 0.62
	if source != null and source.statuses.has("empower"):
		multiplier *= 1.4
	if source != null and source.statuses.has("frenzy"):
		multiplier *= 1.22
	var critical: bool = source != null and rng.randf() < float(source.crit)
	if critical:
		multiplier *= 1.65
	var dealt: float = maxf(1, amount * multiplier - enemy.defense * 0.65)
	if source != null and source.active and float(source.get_meta("relay_until", -1.0)) > elapsed:
		dealt *= 1.5
		source.remove_meta("relay_until")
		_float(enemy.position + Vector2(0,-70), _t("RELAY STRIKE", "โจมตีส่งต่อ"), Color("f3db99"))
	if enemy.statuses.has("weakness"):
		dealt *= 1.25
		if source != null and _relic_effect(source) == "skyglass": dealt *= 1.20
	if enemy.definition.get("sky_seal",false) and not State.flags.get("seal_"+enemy.id,false):
		dealt = minf(dealt, maxf(0, enemy.hp-enemy.max_hp*0.5))
	if source != null and guard_active(enemy) and enemy.position.direction_to(source.position).dot(enemy.facing) > 0.35:
		dealt *= 0.30
		if not enemy.has_meta("guard_hint"):
			enemy.set_meta("guard_hint", true)
			message.emit(_t("Front guard · heavy attack / third hit to break, or flank", "เกราะด้านหน้า · โจมตีหนัก / คอมโบครั้งที่ 3 ให้แตก หรืออ้อมด้านหลัง"))
		effect(enemy.position, "aegis", 48, Color("edce8b"), 0.25)
	var health_removed: float = minf(enemy.hp, dealt)
	enemy.hp = maxf(0, enemy.hp - dealt)
	enemy.hurt_flash = 0.13
	_present(enemy, "hit", 0.20)
	effect(enemy.position, "impact", 28 if critical else 19, Color("ffe4ad") if critical else Color("c9eade"), 0.26)
	if source != null and source.active and critical:
		screen_shake = maxf(screen_shake, 1.0)
	if source != null:
		source.ultimate_charge = minf(100, source.ultimate_charge + minf(4, dealt * 0.05))
	if knockback.length_squared() > 0:
		move_actor(enemy, knockback * (0.18 if enemy.boss else 1.0))
	_float(enemy.position + Vector2(0, -28), str(int(dealt)) + ("!" if critical else ""), Color("ffe0a3") if critical else Color("f4f0e6"))
	if enemy.hp <= 0:
		_kill_enemy(enemy, source)
	return health_removed

func _hurt_actor(actor: Node2D, amount: float, status: String = "") -> void:
	combat_intent = 5.0
	if actor.defeated or actor.invulnerable > 0:
		return
	var dealt: float = maxf(2, amount - actor.defense * 0.48)
	if actor.statuses.has("shield"):
		dealt *= 0.35
	if actor.statuses.has("weakness"):
		dealt *= 1.2
	actor.hp = maxf(0, actor.hp - dealt)
	actor.hurt_flash = 0.22
	_present(actor, "hit", 0.20)
	effect(actor.position, "impact", 24, Color("ffad92"), 0.3)
	actor.invulnerable = 0.18
	actor.ultimate_charge = minf(100, actor.ultimate_charge + 2)
	_float(actor.position + Vector2(0, -28), str(int(dealt)), Color("ff9f94"))
	if not status.is_empty():
		apply_status(actor, status, 1.4)
	if actor.active:
		screen_shake = 2.0
		Sound.sfx("hurt")
	if actor.hp <= 0:
		actor.defeated = true
		actor.statuses.clear()
		_update_active()
		var alive: bool = false
		for ally in actors:
			if not ally.defeated:
				alive = true
		if not alive and not defeat_emitted:
			defeat_emitted = true
			sync_to_state()
			party_defeated.emit()
		else:
			message.emit(_t("An ally has fallen. Use a revive or return to camp.", "เพื่อนล้มลง ใช้ยาชุบชีวิตหรือกลับค่ายพัก"))

func _kill_enemy(enemy: Node2D, source: Node2D) -> void:
	enemy.defeated = true
	enemies.erase(enemy)
	var stage: int = int(map_data.get("id", 0))
	State.record_event("kill", enemy.id)
	State.award_xp((38 + stage * 14) * (5 if enemy.boss else 1))
	State.gold += (12 + stage * 4) * (8 if enemy.boss else 1)
	_drop_equipment(enemy)
	var loot: String = "core" if enemy.boss else (["iron", "crystal", "fiber"][rng.randi_range(0, 2)])
	pickups.append({"pos": enemy.position, "item": loot, "count": 2 if enemy.boss else 1, "life": 60.0})
	if enemy.boss:
		boss_defeated.emit(enemy.id)
		Sound.sfx("victory")
		Sound.play_music("dungeon" if str(map_data.get("theme", "forest")) in ["tower", "archive", "void"] else "explore")
		effect(enemy.position, "burst", 140, Color("dfaeff"), 1.4)
		for actor in actors:
			if not actor.defeated:
				heal_actor(actor, actor.max_hp * 0.25)
	else:
		effect(enemy.position, "burst", 24, Color("ffe3a5"), 0.3)
	if source != null:
		source.ultimate_charge = minf(100, source.ultimate_charge + 5)
	enemy.queue_free()
	State.changed.emit()

func heal_actor(actor: Node2D, amount: float) -> void:
	if actor.defeated:
		return
	var healed: float = minf(amount, actor.max_hp - actor.hp)
	actor.hp += healed
	if healed > 1:
		_float(actor.position + Vector2(0, -30), "+" + str(int(healed)), Color("96eab1"))
		effect(actor.position, "heal", 27, Color("99ffc5"), 0.55)

func apply_status(actor: Node2D, status: String, duration: float) -> void:
	if not is_instance_valid(actor) or actor.defeated:
		return
	if actor.boss and ["stun", "freeze", "root"].has(status):
		duration = minf(0.9, duration * 0.35)
	actor.statuses[status] = maxf(float(actor.statuses.get(status, 0.0)), duration)

func _tick_statuses(actor: Node2D) -> void:
	if actor.periodic_tick < 1 or actor.defeated:
		return
	actor.periodic_tick = 0
	if actor.statuses.has("poison"):
		if actor.enemy:
			damage_enemy(actor, maxf(4, actor.max_hp * (0.009 if actor.boss else 0.045)), null)
		else:
			_hurt_actor(actor, actor.max_hp * 0.035)
	if actor.statuses.has("regen") and not actor.enemy:
		heal_actor(actor, actor.max_hp * 0.045)

func area_damage(pos: Vector2, radius: float, amount: float, source: Node2D, status: String = "", status_duration: float = 0.0) -> void:
	for enemy in enemies.duplicate():
		if enemy.position.distance_to(pos) <= radius + (20 if enemy.boss else 8) and _has_line(pos, enemy.position):
			damage_enemy(enemy, amount, source)
			if is_instance_valid(enemy) and not enemy.defeated and not status.is_empty():
				apply_status(enemy, status, status_duration)

func projectile(from: Vector2, direction: Vector2, damage: float, source: Node2D, color: Color, speed: float = 420.0, piercing: bool = false, breaker: bool = false) -> void:
	projectiles.append({"pos": from, "velocity": direction.normalized() * speed, "damage": damage, "source": source, "color": color, "life": 1.55, "enemy": false, "piercing": piercing, "breaker": breaker, "hit": []})

func _enemy_projectile(from: Vector2, direction: Vector2, damage: float, speed: float = 260.0, status: String = "") -> void:
	projectiles.append({"pos": from, "velocity": direction.normalized() * speed, "damage": damage, "source": null, "color": Color("ff997c"), "life": 3.3, "enemy": true, "piercing": false, "status": status, "hit": []})

func _tick_projectiles(delta: float) -> void:
	for bolt in projectiles.duplicate():
		var previous: Vector2 = bolt.pos
		bolt.pos += bolt.velocity * delta
		bolt.life -= delta
		if bolt.life <= 0 or blocked(bolt.pos, 3) or not _has_line(previous, bolt.pos):
			projectiles.erase(bolt)
			continue
		var targets: Array = actors if bolt.enemy else enemies.duplicate()
		for target in targets:
			if not is_instance_valid(target) or target.defeated or bolt.hit.has(target.get_instance_id()):
				continue
			var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(target.position + Vector2(0, -9), previous, bolt.pos)
			if nearest.distance_to(target.position + Vector2(0, -9)) < (28 if target.boss else 15):
				bolt.hit.append(target.get_instance_id())
				if bolt.enemy:
					_hurt_actor(target, bolt.damage, bolt.get("status", ""))
				else:
					var source: Node2D = bolt.source if is_instance_valid(bolt.source) else null
					if bolt.get("breaker", false) and source != null: _break_windup(target, source)
					damage_enemy(target, bolt.damage, source)
				effect(bolt.pos, "burst", 13, bolt.color, 0.15)
				if not bolt.piercing:
					projectiles.erase(bolt)
					break

func add_zone(pos: Vector2, radius: float, duration: float, damage: float, source: Node2D, kind: String = "fire") -> void:
	zones.append({"pos": pos, "radius": radius, "life": duration, "total": duration, "damage": damage, "source": source, "kind": kind, "tick": 0.0})

func _tick_zones(delta: float) -> void:
	for zone in zones.duplicate():
		zone.life -= delta
		zone.tick -= delta
		if zone.life <= 0 or not is_instance_valid(zone.source):
			zones.erase(zone)
			continue
		if zone.tick <= 0:
			zone.tick = 0.7
			area_damage(zone.pos, zone.radius, zone.damage, zone.source)
			for enemy in enemies.duplicate():
				if enemy.position.distance_to(zone.pos) < float(zone.radius):
					match str(zone.kind):
						"poison": apply_status(enemy, "poison", 2.0)
						"roots": apply_status(enemy, "root", 0.75)
						"frost": apply_status(enemy, "slow", 1.2)
						"gravity": move_actor(enemy, enemy.position.direction_to(zone.pos) * 22)
						"glyph": apply_status(enemy, "weakness", 1.2)

func add_summon(pos: Vector2, source: Node2D, kind: String = "spirit", duration: float = 10.0) -> void:
	var matching: int = 0
	for summon in summons:
		if summon.source == source:
			matching += 1
	if matching >= 5:
		return
	summons.append({"pos": pos, "source": source, "kind": kind, "life": duration, "tick": 0.2, "offset": rng.randf_range(0, TAU)})

func _tick_summons(delta: float) -> void:
	for summon in summons.duplicate():
		summon.life -= delta
		summon.tick -= delta
		if summon.life <= 0 or not is_instance_valid(summon.source) or summon.source.defeated:
			summons.erase(summon)
			continue
		var source: Node2D = summon.source
		if summon.kind != "turret":
			var orbit: Vector2 = source.position + Vector2.from_angle(elapsed * 0.7 + summon.offset) * 55
			summon.pos = summon.pos.move_toward(orbit, delta * 210)
		if summon.tick <= 0:
			summon.tick = 1.2 if summon.kind == "turret" else 1.55
			var target: Node2D = nearest_enemy(summon.pos)
			if target != null and target.position.distance_to(summon.pos) < 440 and _has_line(summon.pos, target.position):
				projectile(summon.pos, summon.pos.direction_to(target.position), source.magic_power * 0.42, source, Color("acddff"), 330)

func _ally_ai(actor: Node2D, delta: float) -> void:
	var leader: Node2D = active_actor()
	if leader == actor or leader == null:
		return
	var target: Node2D = nearest_enemy(actor.position)
	var destination: Vector2 = leader.position + Vector2(-34 if actors.find(actor) % 2 == 0 else 34, 36)
	var engage: bool = target != null and target.position.distance_to(leader.position) < 310 and target.position.distance_to(actor.position) < 350 and (combat_intent > 0.0 or target.position.distance_to(leader.position) < 130)
	if engage:
		var weapon: String = str(actor.definition.get("weapon", "melee"))
		var desired: float = 48.0 if weapon == "melee" else 190.0
		var offset: Vector2 = target.position.direction_to(actor.position)
		if offset.length_squared() < 0.1:
			offset = Vector2.LEFT
		destination = target.position + offset * desired
		actor.facing = actor.position.direction_to(target.position)
		if actor.position.distance_to(target.position) < (82 if weapon == "melee" else 340) and _has_line(actor.position, target.position):
			_attack_actor(actor)
		if actor.ai_timer <= 0 and actor.skill_cooldown <= 0 and actor.mp >= 27:
			actor.ai_timer = 4.0
			_cast_skill(actor)
	var direction: Vector2 = actor.position.direction_to(destination)
	if actor.position.distance_to(destination) > 20:
		actor.velocity = direction * actor.speed * 0.94 * _speed_factor(actor)
		_move_navigating(actor, actor.velocity * delta, destination)
	else:
		actor.velocity = Vector2.ZERO
	# Catch up when a companion is separated by geometry; only outside combat.
	if actor.position.distance_to(leader.position) > 540 and not engage:
		var catchup: Vector2 = leader.position + Vector2(-28, 35)
		if not blocked(catchup):
			actor.position = catchup

func _move_navigating(actor: Node2D, displacement: Vector2, destination: Vector2) -> void:
	var before: Vector2 = actor.position
	move_actor(actor, displacement)
	if before.distance_to(actor.position) < displacement.length() * 0.25 and displacement.length() > 0.01:
		var options: Array = [displacement.rotated(PI / 2), displacement.rotated(-PI / 2)]
		options.sort_custom(func(a, b): return (actor.position + a * 20).distance_to(destination) < (actor.position + b * 20).distance_to(destination))
		for option in options:
			if not blocked(actor.position + option * 3):
				move_actor(actor, option)
				break

func _enemy_ai(enemy: Node2D, delta: float) -> void:
	if seal_active(enemy):
		enemy.windup = 0
		return
	if enemy.statuses.has("freeze") or enemy.statuses.has("stun"):
		return
	var target: Node2D = _nearest_ally(enemy.position)
	if target == null:
		return
	var distance: float = enemy.position.distance_to(target.position)
	if enemy.boss:
		var phase: int = mini(enemy.phase_count, 1 + int((1.0 - enemy.hp / enemy.max_hp) * enemy.phase_count))
		if phase > enemy.boss_phase:
			enemy.boss_phase = phase
			enemy.attack_timer = 0.5
			message.emit(DB.localized(enemy.definition.get("name", enemy.id)) + _t(" · Phase ", " · ระยะที่ ") + str(phase))
			effect(enemy.position, "ring", 100, Color("f6a0db"), 0.8)
			effect(enemy.position, "burst", 78, Color("e9bd85"), 0.55)
			_present(enemy, "cast", 0.6)
			Sound.sfx("boss")
	if enemy.recovery > 0:
		enemy.velocity = Vector2.ZERO
		return
	if enemy.windup > 0:
		enemy.windup -= delta
		if enemy.windup <= 0:
			_resolve_enemy_attack(enemy)
			if not enemy.boss:
				enemy.recovery = 1.15 if enemy.enemy_kind in ["stalker", "brute"] else 0.55
				if enemy.enemy_kind == "brute": enemy.guard_open = 1.9
			enemy.attack_timer = (1.8 - enemy.boss_phase * 0.2) if enemy.boss else rng.randf_range(1.3, 2.2)
		return
	if distance > (640 if enemy.boss else 445):
		return
	if enemy.boss and not enemy.boss_engaged:
		enemy.boss_engaged = true
		effect(enemy.position, "ring", 100, Color("a5d4bd"), 1.0)
		Sound.play_music("boss")
	enemy.attack_timer -= delta
	var ranged: bool = enemy.enemy_kind in ["archer", "mage", "cartographer", "choir", "architect"]
	var desired: float = 215 if ranged else (110 if enemy.boss else 53)
	if ranged and distance < 135 and not enemy.boss:
		var retreat: Vector2 = target.position.direction_to(enemy.position)
		enemy.facing = -retreat
		enemy.velocity = retreat * enemy.speed * 0.75
		_move_navigating(enemy, enemy.velocity * delta, enemy.position + retreat * 100)
	elif distance > desired:
		var direction: Vector2 = enemy.position.direction_to(target.position)
		enemy.facing = direction
		enemy.velocity = direction * enemy.speed * _speed_factor(enemy)
		_move_navigating(enemy, enemy.velocity * delta, target.position)
	else:
		enemy.velocity = Vector2.ZERO
	if enemy.attack_timer <= 0 and distance < (400 if ranged or enemy.boss else 260 if enemy.enemy_kind == "stalker" else 90):
		enemy.target_point = target.position
		enemy.attack_variant += 1
		enemy.attack_pattern = _choose_enemy_pattern(enemy)
		if not enemy.boss and enemy.enemy_kind == "mage":
			var wounded: Node2D = null
			for ally in enemies:
				if ally != enemy and not ally.defeated and not seal_active(ally) and ally.hp < ally.max_hp * 0.8 and ally.position.distance_to(enemy.position) < 340 and _has_line(enemy.position, ally.position):
					if wounded == null or ally.hp / ally.max_hp < wounded.hp / wounded.max_hp: wounded = ally
			if wounded != null:
				enemy.attack_pattern = 5
				enemy.target_point = wounded.position
				enemy.set_meta("mend_target", wounded.get_instance_id())
				message.emit(_t("Mender channeling · interrupt with heavy / third hit", "ผู้เยียวยากำลังร่าย · ขัดด้วยโจมตีหนัก / คอมโบครั้งที่ 3"))
		enemy.windup_total = (1.15 if enemy.boss else (0.95 if ranged else 0.7))
		if State.difficulty == "story":
			enemy.windup_total += 0.18
		if enemy.attack_pattern == 5: enemy.windup_total = 1.4
		enemy.facing = enemy.position.direction_to(target.position)
		enemy.velocity = Vector2.ZERO
		enemy.windup = enemy.windup_total

func _choose_enemy_pattern(enemy: Node2D) -> int:
	# 0 circle, 1 aimed bolt, 2 ring volley, 3 cross, 4 line sweep.
	if not enemy.boss:
		if enemy.enemy_kind == "stalker": return 4 if enemy.attack_variant % 2 == 1 else 0
		if enemy.enemy_kind == "mage": return 3 if enemy.attack_variant % 2 == 1 else 2
		if enemy.enemy_kind == "brute": return 4 if enemy.attack_variant % 2 == 0 else 0
		return 1 if enemy.enemy_kind == "archer" else 0
	match enemy.enemy_kind:
		"warden": return 4 if enemy.attack_variant % 3 == 0 else 0
		"cartographer": return 3 if enemy.attack_variant % 2 == 0 else 1
		"custodian": return 0 if enemy.attack_variant % 2 == 0 else 2
		"leviathan": return 4 if enemy.attack_variant % 2 == 0 else 2
		"choir": return 3 if enemy.attack_variant % 3 == 0 else 2
		"sentinel": return 4 if enemy.attack_variant % 2 == 0 else 0
		"architect": return enemy.attack_variant % 5
	return 0

func _resolve_enemy_attack(enemy: Node2D) -> void:
	_present(enemy, "attack", 0.38)
	var damage: float = enemy.attack_power * (1.0 + 0.14 * (enemy.boss_phase - 1))
	var point: Vector2 = enemy.target_point
	var radius: float = _attack_radius(enemy)
	match int(enemy.attack_pattern):
		0:
			effect(point, "burst", radius, Color("ff927a"), 0.34)
			for actor in actors:
				if actor.position.distance_to(point) < radius:
					_hurt_actor(actor, damage * 1.2, "slow" if enemy.enemy_kind == "brute" else "")
		1:
			var direction: Vector2 = enemy.position.direction_to(point)
			_enemy_projectile(enemy.position, direction, damage, 290, "slow" if enemy.enemy_kind == "mage" else "")
			if enemy.boss:
				for offset in [-0.22, 0.22]:
					_enemy_projectile(enemy.position, direction.rotated(offset), damage * 0.85, 270)
		2:
			var count: int = 8 + enemy.boss_phase * 2 if enemy.boss else 6
			var offset: float = float(enemy.attack_variant) * 0.35
			for i in range(count):
				_enemy_projectile(enemy.position, Vector2.from_angle(TAU * i / count + offset), damage * 0.85, 210 + enemy.boss_phase * 16)
			effect(enemy.position, "ring", 65, Color("ffbd94"), 0.5)
		3:
			effect(point, "lightning", 160, Color("e9acff"), 0.45)
			for actor in actors:
				var difference: Vector2 = actor.position - point
				if (absf(difference.x) < 26 and absf(difference.y) < 210) or (absf(difference.y) < 26 and absf(difference.x) < 210):
					_hurt_actor(actor, damage * 1.15)
		5:
			var target = instance_from_id(int(enemy.get_meta("mend_target", 0)))
			if is_instance_valid(target) and not target.defeated and not seal_active(target) and target.position.distance_to(enemy.position) < 380 and _has_line(enemy.position, target.position):
				target.hp = minf(target.max_hp, target.hp + target.max_hp * 0.18)
				effect(target.position, "heal", 56, Color("b6a6fa"), 0.65)
				_float(target.position + Vector2(0,-45), _t("MENDED", "ฟื้นฟู"), Color("b6a6fa"))
		4:
			var direction: Vector2 = enemy.position.direction_to(point)
			var end: Vector2 = enemy.position + direction * 370
			effect(point, "slash", 90, Color("ffac90"), 0.45, direction.angle())
			for actor in actors:
				if Geometry2D.get_closest_point_to_segment(actor.position, enemy.position, end).distance_to(actor.position) < 36 and _has_line(enemy.position,actor.position):
					_hurt_actor(actor, damage * 1.35)
			if enemy.enemy_kind in ["warden", "sentinel", "stalker"]:
				move_actor(enemy, direction * minf(210, enemy.position.distance_to(point)))
	if enemy.boss:
		screen_shake = maxf(screen_shake, 1.5)

func _attack_radius(enemy: Node2D) -> float:
	return (83.0 + enemy.boss_phase * 10) if enemy.boss else (61.0 if enemy.enemy_kind == "brute" else 44.0)

func _spawn_reinforcement() -> void:
	var region: String = str(map_data.get("region", "verdant"))
	var threat: float = float(State.threat.get(region, 0))
	if threat < 35 or enemies.size() > 12 or ready_emitted:
		return
	var leader: Node2D = active_actor()
	for attempt in range(10):
		var pos: Vector2 = leader.position + Vector2.from_angle(rng.randf_range(0, TAU)) * 370
		if not blocked(pos, 25):
			_spawn_enemy({"kind": "stalker", "pos": [pos.x, pos.y]})
			message.emit(_t("Regional danger draws another hunter.", "ภัยคุกคามในภูมิภาคดึงดูดนักล่าอีกตัว"))
			break

func effect(pos: Vector2, kind: String, radius: float, color: Color, duration: float = 0.4, direction_angle: float = 0.0) -> void:
	effects.append({"pos": pos, "kind": kind, "radius": radius, "color": color, "life": duration, "total": duration, "angle": direction_angle})

func _float(pos: Vector2, value: String, color: Color) -> void:
	if floating_text.size() < 48:
		floating_text.append({"pos": pos, "text": value, "color": color, "life": 0.8})

func _tick_effects(delta: float) -> void:
	for entry in effects.duplicate():
		entry.life -= delta
		if entry.life <= 0:
			effects.erase(entry)
	for entry in floating_text.duplicate():
		entry.life -= delta
		entry.pos.y -= delta * 32
		if entry.life <= 0:
			floating_text.erase(entry)

func _tick_pickups(delta: float) -> void:
	var leader: Node2D = active_actor()
	for loot in pickups.duplicate():
		loot.life -= delta
		if not bool(loot.get("awarded",false)) and leader.position.distance_to(loot.pos) < 85:
			loot.pos = loot.pos.move_toward(leader.position, delta * 220)
		if (not bool(loot.get("awarded",false)) and leader.position.distance_to(loot.pos) < 24) or loot.life <= 0:
			if not bool(loot.get("awarded",false)): State.add_item(loot.item, int(loot.count))
			pickups.erase(loot)
			effect(loot.pos, "ring", 15, Color("f1cd8d"), 0.3)

func _check_objectives() -> void:
	if ready_emitted or map_data.is_empty():
		return
	if not town_ready(): return
	var required_chest: String = str(map_data.get("required_chest",""))
	if not required_chest.is_empty() and not State.flags.get("chest_"+required_chest,false): return
	var priority: String = str(map_data.get("priority_enemy",""))
	var enemies_done: bool = enemies.is_empty() if priority.is_empty() else not enemies.any(func(e): return e.id == priority)
	if enemies_done and activated_sigils.size() >= map_data.get("sigils", []).size():
		ready_emitted = true
		stage_ready.emit()
		if not map_data.get("safe", false):
			message.emit(_t("Path unlocked. Reach the golden gate.", "เส้นทางเปิดแล้ว ไปยังประตูสีทอง"))
			Sound.sfx("quest")

func interact() -> void:
	if paused or active_actor() == null or active_actor().defeated:
		return
	var pos: Vector2 = active_actor().position
	for foe in enemies:
		if seal_active(foe) and pos.distance_to(foe.position) < 165:
			interacted.emit("seal", {"id":foe.id})
			return
	var nearest: float = 78.0
	var selection: Dictionary = {}
	var return_gate: Dictionary = map_data.get("return_gate", {})
	if not return_gate.is_empty():
		var distance: float = pos.distance_to(_vec(return_gate.pos))
		if distance < nearest:
			nearest = distance
			selection = {"kind": "return", "data": return_gate}
	for npc in map_data.get("npcs", []):
		var distance: float = pos.distance_to(npc_position(npc))
		if distance < nearest:
			nearest = distance
			selection = {"kind": "npc", "data": npc}
	for chest in map_data.get("chests", []):
		if opened_chests.has(str(chest.id)):
			continue
		var distance: float = pos.distance_to(_vec(chest.pos))
		if distance < nearest:
			nearest = distance
			selection = {"kind": "chest", "data": chest}
	var sigils: Array = map_data.get("sigils", [])
	for index in range(sigils.size()):
		if activated_sigils.has(index):
			continue
		var distance: float = pos.distance_to(_vec(sigils[index]))
		if distance < nearest:
			nearest = distance
			selection = {"kind": "sigil", "data": {"index": index}}
	if pos.distance_to(_vec(map_data.get("exit", [1450, 500]))) < nearest:
		selection = {"kind": "exit", "data": {}}
	if selection.is_empty() and not map_data.get("no_camp", false) and pos.distance_to(camp_position) < 85:
		selection = {"kind": "camp", "data": {}}
	if selection.is_empty():
		message.emit(_t("Approach a chest, sigil, traveler, camp or gate and interact.", "เข้าใกล้หีบ รูน ผู้คน ค่ายพัก หรือประตู แล้วกดสำรวจ"))
		return
	match str(selection.kind):
		"return":
			sync_to_state()
			interacted.emit("return", selection.data)
		"chest":
			var chest: Dictionary = selection.data
			if chest.get("puzzle",false): interacted.emit("puzzle",chest)
			else: claim_chest(chest)
		"sigil":
			var index: int = int(selection.data.index)
			activated_sigils.append(index)
			State.record_event("sigil", str(int(map_data.id)))
			message.emit(_t("Astral sigil awakened", "อักขระดวงดาวตื่นขึ้นแล้ว"))
			effect(_vec(sigils[index]), "ring", 90, Color("a7dffe"), 0.9)
			Sound.sfx("skill")
			_check_objectives()
		"exit":
			if ready_emitted:
				sync_to_state()
				interacted.emit("exit", {})
			elif not town_ready():
				message.emit(objective_text())
			else:
				message.emit(_t("Defeat remaining enemies and awaken every sigil.", "กำจัดศัตรูที่เหลือและปลุกอักขระทุกจุด"))
		"npc":
			State.record_event("talk", str(selection.data.get("id", "any")))
			interacted.emit("npc", selection.data)
		"camp":
			var nearby: Node2D = nearest_enemy(pos)
			if nearby != null and nearby.position.distance_to(pos) < 240:
				message.emit(_t("Enemies are too close to rest.", "ศัตรูอยู่ใกล้เกินกว่าจะพักได้"))
			else:
				heal_party()
				sync_to_state()
				interacted.emit("camp", {})

func heal_party() -> void:
	for actor in actors:
		actor.defeated = false
		actor.hp = actor.max_hp
		actor.mp = actor.max_mp
		actor.statuses.clear()
		actor.skill_cooldown = 0
		actor.invulnerable = 1.2
		effect(actor.position, "heal", 40, Color("9aedbf"), 0.7)
	defeat_emitted = false
	_update_active()
	Sound.sfx("heal")

func use_consumable(item_id: String) -> bool:
	if actors.is_empty() or _consumable_timer > 0:
		return false
	var item: Dictionary = DB.item(item_id)
	var kind: String = str(item.get("effect", ""))
	var target: Node2D = active_actor()
	if kind == "revive":
		target = null
		for actor in actors:
			if actor.defeated:
				target = actor
				break
		if target == null:
			message.emit(_t("No fallen ally needs revival.", "ไม่มีเพื่อนที่ต้องชุบชีวิต"))
			return false
	elif target.defeated:
		return false
	elif kind == "heal" and target.hp >= target.max_hp:
		return false
	elif kind == "mana" and target.mp >= target.max_mp:
		return false
	elif kind in ["full", "elixir", "restore"] and target.hp >= target.max_hp and target.mp >= target.max_mp:
		return false
	elif not kind in ["heal", "mana", "revive", "full", "elixir", "restore"]:
		return false
	if not State.use_item(item_id):
		return false
	_consumable_timer = 0.4
	var value: float = float(item.get("value", 60))
	match kind:
		"heal": heal_actor(target, value)
		"mana": target.mp = minf(target.max_mp, target.mp + value)
		"revive":
			target.defeated = false
			target.hp = target.max_hp * clampf(value / 100.0, 0.1, 1.0)
			target.invulnerable = 2.0
			target.position = active_actor().position + Vector2(25, 25)
			defeat_emitted = false
			_update_active()
		_:
			target.hp = target.max_hp
			target.mp = target.max_mp
	effect(target.position, "heal", 40, Color("a8efcc"), 0.6)
	Sound.sfx("heal")
	sync_to_state()
	return true

func sync_to_state() -> void:
	for actor in actors:
		if not is_instance_valid(actor):
			continue
		var record: Dictionary = State.hero(actor.id)
		record["hp"] = actor.hp
		record["mp"] = actor.mp
		record["ultimate_charge"] = actor.ultimate_charge
		record["cooldowns"] = {"attack": actor.attack_cooldown, "skill": actor.skill_cooldown, "dodge": actor.dodge_cooldown}

func town_ready() -> bool:
	if int(map_data.get("id",-1)) != 1 or 1 in State.cleared: return true
	return bool(State.flags.get("town_sera",false)) and bool(State.flags.get("town_ilyen",false)) and bool(State.flags.get("chest_m01_cache",false))

func objective_text() -> String:
	if int(map_data.id) == 0: return DB.localized(map_data.objective)
	if int(map_data.id) == 1 and State.respite_next() > 0:
		return _t("Rest / shop / talk in town · E at gold gate to continue: ", "พัก · ซื้อของ · คุยในเมือง / E ที่ประตูทองเดินทางต่อ: ") + DB.localized(DB.map(State.respite_next()).name)
	if not town_ready():
		if not State.flags.get("town_sera",false): return _t("Speak with Sera by the west road · E", "คุยกับเซราข้างทางฝั่งตะวันตก · E")
		if not State.flags.get("chest_m01_cache",false): return _t("Collect the roadside supply chest · E", "รับเสบียงจากหีบข้างทาง · E")
		return _t("Ask Ilyen about the forest road · E", "ถามอิลเยนเรื่องทางเข้าป่า · E")
	var total: int = map_data.get("sigils", []).size()
	var required: String = str(map_data.get("required_chest",""))
	if not required.is_empty() and not State.flags.get("chest_"+required,false): return _t("Recover Hana’s bag by the south path · E", "เก็บกระเป๋าฮานะข้างทางทิศใต้ · E")
	var priority: String = str(map_data.get("priority_enemy",""))
	if not priority.is_empty() and enemies.any(func(e): return e.id == priority): return _t("Defeat the Thorn Captain. Other patrols are optional.", "กำจัดหัวหน้าหนาม · เลี่ยงหน่วยลาดตระเวนอื่นได้")
	if ready_emitted and int(map_data.id) == 1:
		if State.lantern_step() in [2, 3, 4]: return _t("Mira's lantern stall → eastern market · E", "กลับไปหามีรา ร้านโคมไฟฝั่งตลาดตะวันออก · E")
		return _t("Market / tailor / music → east · E at gate for forest", "ตลาด · ช่างตัดชุด · เกมดนตรี → ตะวันออก / E ที่ประตูไปป่า")
	if ready_emitted:
		return _t("Reach the golden gate · E", "ไปยังประตูสีทอง · E")
	var value: String = _t("Enemies ", "ศัตรู ") + str(enemies.size())
	if total > 0:
		value += " · " + _t("Sigils ", "อักขระ ") + str(activated_sigils.size()) + "/" + str(total)
	return value

func _draw() -> void:
	if map_data.is_empty():
		return
	Art.draw_environment(self, map_data, elapsed)
	_draw_interactables()
	Presentation.draw_floor(self, self)

func _draw_interactables() -> void:
	if int(map_data.get("id", -1)) in [0, 1, 2, 3]:
		InteractableArt.draw_objects(self, self)
	else:
		_draw_legacy_interactables()
	for npc in map_data.get("npcs", []):
		var pos: Vector2 = npc_position(npc)
		var definition: Dictionary = DB.character(str(npc.get("character_id", npc.get("id", "n01"))))
		if definition.is_empty():
			definition = {"color": "d0b58a", "skin": "e0b99a", "hair": "655267", "weapon": "magic"}
		definition = definition.duplicate()
		definition["_walking"] = bool(npc.get("wander",false))
		var facing: Vector2 = (Vector2.RIGHT if cos(elapsed*0.4)>0 else Vector2.LEFT) if npc.get("wander",false) else Vector2.DOWN
		Art.draw_character(self, pos, definition, elapsed, facing, false)
		var label: String = str(npc.get("activity",""))
		if not label.is_empty():
			var names: Dictionary = {"wardrobe":_t("Tailor","ช่างตัดชุด"),"music":_t("Music game","เกมดนตรี"),"shop":_t("Supplies","ร้านเสบียง")}
			draw_string(draw_font,pos+Vector2(-36,24),names.get(label,label),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("ffdf9a"))
		var quest_npc: bool = (str(npc.id) == "courier" and State.lantern_step() in [0, 1]) or (str(npc.id) == "lantern_child" and State.lantern_step() in [2, 3, 4])
		var near: bool = active_actor() != null and active_actor().position.distance_to(pos) < 100
		if quest_npc or near:
			draw_circle(pos + Vector2(0, -72), 8 if quest_npc else 6, Color("f3d68e") if quest_npc else Color("9caeab"))
			if draw_font != null:
				draw_string(draw_font, pos + Vector2(-3, -68), "!" if quest_npc else "·", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("282b40"))
	if int(map_data.id) == 1 and State.flags.get("lantern_repaired", false):
		var light_pos := Vector2(2330, 413)
		Presentation.cel(self, "ring", light_pos, 150, int(elapsed * 5) % 8, Color("f7d58e", 0.22))
		draw_string(draw_font, light_pos + Vector2(-66, -64), _t("The home light", "โคมไฟรอกลับบ้าน"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ffe5b2"))

func _draw_legacy_interactables() -> void:
	var exit_pos: Vector2 = _vec(map_data.get("exit", [1450, 500]))
	var gate_color: Color = Color("f1d398") if ready_emitted else Color("786b82")
	draw_arc(exit_pos, 35, 0, TAU, 32, Color(gate_color, 0.3), 10)
	draw_arc(exit_pos, 35, -PI, 0, 22, gate_color, 4)
	draw_line(exit_pos + Vector2(-35, -3), exit_pos + Vector2(-35, 25), gate_color, 5)
	draw_line(exit_pos + Vector2(35, -3), exit_pos + Vector2(35, 25), gate_color, 5)
	if ready_emitted:
		draw_circle(exit_pos + Vector2(0, -9), 7 + sin(elapsed * 3) * 2, Color("ffe9b4"))
	if draw_font != null:
		draw_string(draw_font, exit_pos + Vector2(-18, 50), "[E]", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, gate_color)
	var camp_color: Color = Color("a4cfbb")
	draw_circle(camp_position, 23, Color(0.3, 0.6, 0.5, 0.14))
	draw_line(camp_position + Vector2(-10, 6), camp_position + Vector2(11, -4), Color("98694d"), 4)
	draw_line(camp_position + Vector2(10, 6), camp_position + Vector2(-11, -4), Color("98694d"), 4)
	draw_colored_polygon(PackedVector2Array([camp_position + Vector2(-7, 0), camp_position + Vector2(1, -20 - sin(elapsed * 7) * 2), camp_position + Vector2(8, 0)]), Color("f5c278"))
	if draw_font != null:
		draw_string(draw_font, camp_position + Vector2(-17, 39), "[E]", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, camp_color)
	var sigils: Array = map_data.get("sigils", [])
	for index in range(sigils.size()):
		var pos: Vector2 = _vec(sigils[index])
		var color: Color = Color("a5e9e5") if activated_sigils.has(index) else Color("9a8fb8")
		draw_arc(pos, 26, 0, TAU, 6, color, 2)
		draw_arc(pos, 19, PI / 6, TAU + PI / 6, 3, color, 2)
		if activated_sigils.has(index):
			draw_circle(pos, 7, Color(color, 0.6))
		elif draw_font != null:
			draw_string(draw_font, pos + Vector2(-12, -34), "[E]", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
	for chest in map_data.get("chests", []):
		var pos: Vector2 = _vec(chest.pos)
		var opened: bool = opened_chests.has(str(chest.id))
		draw_rect(Rect2(pos - Vector2(13, 15), Vector2(26, 20)), Color("58413b"))
		draw_rect(Rect2(pos - Vector2(13, 18 if opened else 18), Vector2(26, 6)), Color("b79557") if not opened else Color("62554b"))
		draw_rect(Rect2(pos - Vector2(2, 11), Vector2(4, 7)), Color("e4c77a"))
		if not opened and draw_font != null:
			draw_string(draw_font, pos + Vector2(-12, -29), "[E]", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e8d6af"))

func _draw_telegraph(enemy: Node2D) -> void:
	Presentation.draw_telegraph(self, enemy, _attack_radius(enemy), elapsed)

func seal_active(enemy: Node2D) -> bool:
	return bool(enemy.definition.get("sky_seal",false)) and enemy.hp <= enemy.max_hp*0.5+0.01 and not State.flags.get("seal_"+enemy.id,false)

func claim_chest(chest: Dictionary) -> void:
	var key: String = str(chest.get("id",""))
	if key.is_empty() or State.flags.get("chest_"+key,false): return
	opened_chests.append(key)
	State.flags["chest_"+key] = true
	var item: String = str(chest.get("item","potion"))
	State.add_item(item,1)
	State.record_event("chest",key)
	message.emit(_t("Found: ","ได้รับ: ")+DB.localized(DB.item(item).get("name",item)))
	Sound.sfx("chest")
	_check_objectives()
	effect(_vec(chest.pos),"skybreak",40,Color("f4db92"),0.8)
	if not str(chest.get("story","")).is_empty(): interacted.emit("clue",chest)

func _inside_warning(pos: Vector2, foe: Node2D) -> bool:
	match foe.attack_pattern:
		0: return pos.distance_to(foe.target_point) < _attack_radius(foe)
		3:
			var d: Vector2 = pos-foe.target_point
			return (absf(d.x)<26 and absf(d.y)<210) or (absf(d.y)<26 and absf(d.x)<210)
		4:
			var end: Vector2 = foe.position+foe.position.direction_to(foe.target_point)*370
			return Geometry2D.get_closest_point_to_segment(pos,foe.position,end).distance_to(pos)<36
	return false

func npc_position(npc: Dictionary) -> Vector2:
	var pos: Vector2 = _vec(npc.pos)
	if npc.get("wander",false): pos.x += sin(elapsed*0.4)*36
	return pos
