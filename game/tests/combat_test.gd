extends SceneTree
## Production combat regressions and an input-driven full campaign run.
## Run: tools/godot.sh --headless --path game --script tests/combat_test.gd -- --qa
## Fixture setup changes HP only in isolated ability tests. The campaign below
## uses an unmodified new game, real navigation, damage, costs and progression.

const DELTA: float = 1.0 / 60.0
var World
var checks: int = 0
var failures: Array[String] = []
var db
var state
var world
var app
var boss_ids: Array[String] = []
var campaign_frames: int = 0
var grid: AStarGrid2D
var navigation_stage: int = -1
var path: PackedVector2Array = []
var path_target: Vector2 = Vector2(-999, -999)
var requested_ending: String = "restore"


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)


func _fixture() -> void:
	if is_instance_valid(world):
		world.free()
	state.new_game()
	world = World.new()
	root.add_child(world)
	world.set_physics_process(false)
	world.load_map(0)


func _run() -> void:
	db = root.get_node("DB")
	state = root.get_node("State")
	state.save_directory = "user://automated_combat_test_%d" % Time.get_ticks_usec()
	state.language = "en"
	state.difficulty = "normal"
	_check(db.errors.is_empty() and db.maps.size() == 12 and db.characters.size() == 38,
		"production campaign data loads: " + str(db.errors))
	if not failures.is_empty():
		_finish()
		return
	World = load("res://scripts/world.gd")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ending="):
			requested_ending = argument.trim_prefix("--ending=")
	for action in ["move_left", "move_right", "move_up", "move_down", "attack", "heavy", "skill", "ultimate", "dodge", "switch_next", "interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	if not OS.get_cmdline_user_args().has("--campaign-only"):
		_test_movement_and_state()
		_test_enemy_telegraphs()
		_test_thirty_classes()
		_test_siphon_damage()
		_test_consumables()
		world.free()
		world = null
	await _test_campaign()
	_finish()


func _test_movement_and_state() -> void:
	_fixture()
	var hero = world.active_actor()
	hero.position = Vector2(260, 500)
	world.obstacles = [Rect2(300, 450, 50, 100)]
	world.set_input_vector(Vector2.RIGHT)
	for index in range(30):
		world._physics_process(DELTA)
	_check(hero.position.x > 260 and hero.position.x <= 290, "input movement stops at obstacle")
	var before: Vector2 = hero.position
	world.dodge()
	_check(hero.position.x <= 290 and not world.blocked(hero.position, 10), "dodge cannot cross obstacle")
	_check(hero.invulnerable > 0 and hero.dodge_cooldown > 0, "dodge grants bounded invulnerability and cooldown")
	world.paused = true
	world.attack()
	world.skill()
	world._physics_process(1.0)
	_check(hero.position == before, "paused world blocks movement and actions")
	world.paused = false
	world.set_input_vector(Vector2.ZERO)
	hero.statuses["freeze"] = 2.0
	hero.dodge_cooldown = 0
	hero.ultimate_charge = 100
	world.dodge()
	world.ultimate()
	_check(hero.position == before and hero.ultimate_charge == 100, "freeze blocks dodge and ultimate")
	hero.statuses.clear()
	hero.attack_cooldown = 0
	var press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	world._unhandled_input(press)
	_check(world._mouse_attack_held, "unhandled mouse press starts attack hold")
	press.pressed = false
	world._input(press)
	_check(not world._mouse_attack_held, "mouse release clears hold before GUI handling")
	hero.hp = 123
	hero.mp = 45
	hero.ultimate_charge = 49
	hero.attack_cooldown = 0.2
	hero.skill_cooldown = 7.0
	hero.dodge_cooldown = 0.9
	world.sync_to_state()
	world.load_map(0)
	hero = world.active_actor()
	_check(hero.hp == 123 and hero.mp == 45 and hero.ultimate_charge == 49, "map rebuild preserves individual vitals and ultimate")
	_check(is_equal_approx(hero.attack_cooldown, 0.2) and hero.skill_cooldown == 7 and is_equal_approx(hero.dodge_cooldown, 0.9), "map rebuild preserves every action cooldown")
	world.switch_to(1)
	world.switch_to(0)
	_check(world.active_actor() == hero and hero.hp == 123 and hero.skill_cooldown == 7, "switching retains original actor resources")
	state.recruit_through(11)
	_check(state.set_party(0, "c02"), "recruited hero can replace active party member")
	world.refresh_party()
	_check(state.set_party(0, "c01"), "original hero can rejoin party")
	world.refresh_party()
	hero = world.active_actor()
	_check(hero.hp == 123 and hero.skill_cooldown == 7, "removing and readding hero preserves personal cooldown and HP")
	hero.hp = 0
	hero.defeated = true
	var old_level: int = hero.level
	state.award_xp(state.xp_required(old_level))
	_check(hero.level > old_level and hero.hp == hero.max_hp and hero.mp == hero.max_mp and not hero.defeated,
		"earned level immediately refreshes stats and recovers fallen hero")
	world.obstacles = [Rect2(330, 400, 12, 200)]
	hero.position = Vector2(280, 500)
	var enemy = world._spawn_enemy({"id": "wall_target", "kind": "stalker", "pos": [390, 500], "hp": 500})
	var hp: float = enemy.hp
	world.projectile(hero.position, Vector2.RIGHT, 100, hero, Color.WHITE, 1000)
	world._tick_projectiles(0.2)
	_check(enemy.hp == hp, "swept projectile collision prevents crossing thin walls")
	world.map_data = {"id": 0, "safe": false, "sigils": [[500, 500]], "exit": [600, 500]}
	world.ready_emitted = false
	world._check_objectives()
	_check(not world.ready_emitted, "enemy and sigil objectives keep exit closed")
	world.enemies.clear()
	world._check_objectives()
	_check(not world.ready_emitted, "clearing enemies alone does not skip sigils")
	world.activated_sigils.append(0)
	world._check_objectives()
	_check(world.ready_emitted, "exit unlocks only after enemies and all sigils")


func _test_enemy_telegraphs() -> void:
	_fixture()
	var hero = world.active_actor()
	hero.position = Vector2(800, 500)
	for kind in ["warden", "cartographer", "custodian", "leviathan", "choir", "sentinel", "architect"]:
		var enemy = world._spawn_enemy({"id": kind, "kind": kind, "pos": [900, 500], "hp": 2000, "phases": 3}, true)
		enemy.attack_timer = 0
		world._enemy_ai(enemy, DELTA)
		_check(root.get_node("Sound").current_mood == "boss", kind + " engagement starts boss music")
		_check(enemy.windup > 0 and enemy.target_point.distance_to(hero.position) < 80,
			kind + " announces a targeted windup before attack")
		enemy.hp = enemy.max_hp * 0.30
		world._enemy_ai(enemy, DELTA)
		_check(enemy.boss_phase == 3, kind + " enters third phase at low health")
		var patterns: Array[int] = []
		for variant in range(1, 7):
			enemy.attack_variant = variant
			var pattern: int = world._choose_enemy_pattern(enemy)
			if not patterns.has(pattern):
				patterns.append(pattern)
			enemy.attack_pattern = pattern
			enemy.target_point = hero.position
			hero.invulnerable = 0
			var health: float = hero.hp
			var bolt_count: int = world.projectiles.size()
			world._resolve_enemy_attack(enemy)
			_check(hero.hp < health or world.projectiles.size() > bolt_count,
				kind + " pattern " + str(pattern) + " resolves actual damage or projectiles")
			hero.hp = hero.max_hp
		_check(patterns.size() >= 2, kind + " has multiple attack patterns")
		world.enemies.erase(enemy)
		enemy.free()
		world.projectiles.clear()


func _test_thirty_classes() -> void:
	var distinct: Dictionary = {}
	for definition in db.characters:
		if not str(definition.id).begins_with("c"):
			continue
		_fixture()
		state.recruit_through(11)
		var id: String = str(definition.id)
		if id in state.party:
			state.active_index = state.party.find(id)
		else:
			state.set_party(0, id)
			state.active_index = 0
		world.refresh_party()
		world.switch_to(state.active_index)
		var hero = world.active_actor()
		hero.position = Vector2(800, 500)
		hero.facing = Vector2.RIGHT
		world.obstacles.clear()
		for index in range(3):
			world._spawn_enemy({"id": "ability_target_" + str(index), "kind": "stalker", "pos": [860 + index * 30, 500 + index * 15], "hp": 10000})
		var skill_id: String = str(definition.skill)
		distinct[skill_id] = true
		for empowered in [false, true]:
			for ally in world.actors:
				ally.hp = ally.max_hp * 0.45
				ally.statuses.clear()
			hero.skill_cooldown = 0
			hero.mp = hero.max_mp
			hero.ultimate_charge = 100 if empowered else 0
			var enemies_hp: float = _enemy_health()
			var hero_health: float = hero.hp
			if empowered:
				world.ultimate()
			else:
				world.skill()
			for frame in range(100):
				world._tick_summons(DELTA)
				world._tick_projectiles(DELTA)
				world._tick_zones(DELTA)
			var mechanical: bool = _enemy_health() < enemies_hp or not hero.statuses.is_empty() or hero.hp > hero_health
			if skill_id in ["heal", "spirits"]:
				mechanical = false
				for ally in world.actors:
					mechanical = mechanical or ally.hp > ally.max_hp * 0.45
			_check(mechanical, id + " " + skill_id + (" ultimate" if empowered else " skill") + " changes combat state")
			_check(hero.ultimate_charge < 100 if empowered else hero.mp < hero.max_mp,
				id + (" ultimate consumes charge" if empowered else " skill consumes mana"))
	_check(distinct.size() == 30, "thirty distinct student class mechanics verified")


func _enemy_health() -> float:
	var total: float = 0
	for enemy in world.enemies:
		total += enemy.hp
	return total


func _test_siphon_damage() -> void:
	_fixture()
	state.recruit_through(11)
	state.set_party(0, "c13")
	world.refresh_party()
	world.switch_to(0)
	var hero = world.active_actor()
	hero.position = Vector2(800, 500)
	hero.hp = hero.max_hp * 0.5
	var target = world._spawn_enemy({"id": "siphon_overkill", "kind": "stalker", "pos": [850, 500], "hp": 10})
	var health: float = hero.hp
	world.skill()
	_check(target.hp == 0 and is_equal_approx(hero.hp - health, 5.5),
		"siphon heals from health actually removed, capped by target remaining HP")


func _test_consumables() -> void:
	_fixture()
	var hero = world.active_actor()
	state.add_item("potion", 2)
	state.add_item("ether", 2)
	state.add_item("revive", 2)
	state.add_item("elixir", 2)
	var stock: int = int(state.inventory.potion)
	_check(not world.use_consumable("potion") and int(state.inventory.potion) == stock,
		"full-health potion is rejected without consuming inventory")
	hero.hp = 50
	_check(world.use_consumable("potion") and hero.hp == 190 and int(state.inventory.potion) == stock - 1,
		"potion restores its stated HP and consumes exactly one")
	_check(not world.use_consumable("ether"), "consumable cooldown blocks immediate second item")
	world._physics_process(0.5)
	hero.mp = 0
	stock = int(state.inventory.ether)
	_check(world.use_consumable("ether") and hero.mp == minf(hero.max_mp, 100) and int(state.inventory.ether) == stock - 1,
		"ether restores mana and consumes exactly one")
	world._physics_process(0.5)
	var fallen = world.actors[1]
	fallen.hp = 0
	fallen.defeated = true
	stock = int(state.inventory.revive)
	_check(world.use_consumable("revive") and not fallen.defeated and is_equal_approx(fallen.hp, fallen.max_hp * 0.4) and fallen.invulnerable == 2,
		"revive restores a fallen ally at stated health with a protected recovery")
	_check(int(state.inventory.revive) == stock - 1, "revive consumes exactly one item")
	world._physics_process(0.5)
	hero.hp = 30
	hero.mp = 0
	stock = int(state.inventory.elixir)
	_check(world.use_consumable("elixir") and hero.hp == hero.max_hp and hero.mp == hero.max_mp and int(state.inventory.elixir) == stock - 1,
		"elixir fully restores active hero HP and MP")
	world._physics_process(0.5)
	stock = int(state.inventory.elixir)
	_check(not world.use_consumable("elixir") and int(state.inventory.elixir) == stock,
		"full-resource elixir is rejected without inventory charge")
	for ally in world.actors:
		ally.hp = 0
		ally.defeated = true
	world.defeat_emitted = true
	_check(not world.use_consumable("elixir"), "elixir cannot silently consume on a fallen hero")
	_check(world.use_consumable("revive") and not world.defeat_emitted and not world.active_actor().defeated,
		"revive recovers active selection after total party defeat")


func _test_campaign() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.config.language = "en"
	app.config.difficulty = "normal"
	state.difficulty = "normal"
	app.new_game()
	var completed: Array[int] = []
	var stage_frames: int = 0
	var previous_stage: int = -1
	for frame in range(120000):
		campaign_frames = frame
		world = app.world
		world.set_physics_process(false)
		if state.stage != previous_stage:
			previous_stage = state.stage
			stage_frames = 0
			world.boss_defeated.connect(func(id): boss_ids.append(id))
			print("CAMPAIGN_STAGE_ENTER " + str(state.stage))
		if is_instance_valid(app.dialogue_layer):
			if app.dialogue_index < app.dialogue.size():
				app.advance_dialogue()
			else:
				var selected_text: String = ""
				for option in app.dialogue_data.get("choice", {}).get("options", []):
					if str(option.get("id", "")) == "ending_" + requested_ending:
						selected_text = db.localized(option.get("text", ""))
				var choice_button = _find_choice_button(app.dialogue_layer, selected_text)
				if choice_button != null:
					choice_button.pressed.emit()
			await process_frame
			continue
		if app.panel_name == "ending":
			_check(state.cleared.size() == 12 and state.stage == 11, "actual exits and story transitions clear all twelve stages")
			_check(boss_ids.size() == 7, "seven real boss encounters defeated without injected damage")
			_check(state.ending_choice == requested_ending, "final dialogue choice leads to completed " + requested_ending + " ending")
			_check(state.recruited.size() >= 30, "all thirty summoned students recruited through campaign progression")
			return
		if app.panel_name == "defeat" or world.defeat_emitted:
			_check(false, "normal campaign survives actual combat; defeated on stage " + str(state.stage))
			return
		if app.panel_name == "activity" and app.activities.mode == "seal":
			for i in range(3):
				while app.activities.angles[i] != app.activities.PATTERN[i]: app.activities.rotate(i)
			app.activities.submit()
			await process_frame
			continue
		if world.paused:
			await process_frame
			continue
		stage_frames += 1
		if stage_frames > 15000:
			_check(false, "campaign stage timeout " + str(state.stage) + " at " + str(world.active_actor().position) + " " + world.objective_text())
			return
		_drive_campaign_frame()
		world._physics_process(DELTA)
		if state.stage != previous_stage or world.ready_emitted and previous_stage not in completed:
			if world.ready_emitted:
				if previous_stage == 3:
					_check(state.quests.has("q04") and int(state.quests.q04.progress) == 2,
						"actual map 3 relay interactions complete the two-sigil quest")
				completed.append(previous_stage)
				print("CAMPAIGN_OBJECTIVES_READY " + str(previous_stage) + " frames=" + str(stage_frames))
		if frame % 180 == 0:
			await process_frame
	_check(false, "campaign total timeout")


func _find_choice_button(node: Node, requested_text: String = ""):
	for child in node.get_children():
		if child is Button and (requested_text.is_empty() or child.text == requested_text):
			return child
		var nested = _find_choice_button(child, requested_text)
		if nested != null:
			return nested
	return null


func _drive_campaign_frame() -> void:
	# Spellweaver leads from range; the initial Vanguard and Sanctifier run
	# their shipping AI. Resources regenerate at their real rates.
	if world.actors.size() > 1 and not world.actors[1].defeated:
		if state.active_index != 1:
			world.switch_to(1)
	var leader = world.active_actor()
	var target = world.nearest_enemy(leader.position)
	if target != null:
		if world.seal_active(target):
			_navigate(target.position,120)
			if leader.position.distance_to(target.position) < 160: world.interact()
			return
		var distance: float = leader.position.distance_to(target.position)
		if distance > 225 or not world._has_line(leader.position, target.position):
			_navigate(target.position, 150)
		elif distance < 135:
			world.set_input_vector(target.position.direction_to(leader.position))
		else:
			world.set_input_vector(Vector2.ZERO)
		world.attack()
		if leader.skill_cooldown <= 0 and leader.mp >= 18:
			world.skill()
		if leader.ultimate_charge >= 100:
			world.ultimate()
		if leader.hp < leader.max_hp * 0.35:
			world.use_consumable("potion")
		for enemy in world.enemies:
			if enemy.windup > 0 and enemy.windup < 0.25 and leader.position.distance_to(enemy.target_point) < 105 and leader.dodge_cooldown <= 0:
				var escape: Vector2 = enemy.target_point.direction_to(leader.position)
				if escape.length_squared() < 0.1:
					escape = enemy.position.direction_to(leader.position).orthogonal()
				for offset in [0.0, PI * 0.5, -PI * 0.5, PI]:
					var option: Vector2 = escape.rotated(offset)
					if not world.blocked(leader.position + option * 108, 10):
						world.set_input_vector(option)
						world.dodge()
						break
		return
	if state.stage == 1 and not world.town_ready():
		var destination: Vector2
		if not state.flags.get("town_sera",false): destination = Vector2(425,460)
		elif not state.flags.get("chest_m01_cache",false): destination = Vector2(650,505)
		else: destination = Vector2(1120,515)
		if leader.position.distance_to(destination) < 55:
			world.set_input_vector(Vector2.ZERO)
			world.interact()
		else: _navigate(destination,35)
		return
	var required_chest: String = str(world.map_data.get("required_chest",""))
	if not required_chest.is_empty() and not state.flags.get("chest_"+required_chest,false):
		for chest in world.map_data.get("chests",[]):
			if str(chest.id) == required_chest:
				var destination: Vector2 = world._vec(chest.pos)
				if leader.position.distance_to(destination) < 55:
					world.set_input_vector(Vector2.ZERO)
					world.interact()
				else: _navigate(destination,35)
				return
	var sigils: Array = world.map_data.get("sigils", [])
	for index in range(sigils.size()):
		if index not in world.activated_sigils:
			var point: Vector2 = world._vec(sigils[index])
			if leader.position.distance_to(point) < 55:
				world.set_input_vector(Vector2.ZERO)
				world.interact()
				if state.stage == 3:
					_check(state.quests.has("q04") and int(state.quests.q04.progress) == world.activated_sigils.size(),
						"actual map 3 sigil interaction records integer stage quest target " + str(world.activated_sigils.size()))
			else:
				_navigate(point, 35)
			return
	var exit: Vector2 = world._vec(world.map_data.exit)
	if leader.position.distance_to(exit) < 55:
		world.set_input_vector(Vector2.ZERO)
		world.interact()
	else:
		_navigate(exit, 35)


func _navigate(destination: Vector2, acceptable_distance: float) -> void:
	var leader = world.active_actor()
	if leader.position.distance_to(destination) <= acceptable_distance and world._has_line(leader.position, destination):
		world.set_input_vector(Vector2.ZERO)
		return
	if grid == null or navigation_stage != state.stage:
		navigation_stage = state.stage
		grid = AStarGrid2D.new()
		grid.region = Rect2i(0, 0, 80, 50)
		grid.cell_size = Vector2(20, 20)
		grid.offset = Vector2(10, 10)
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.update()
		for y in range(50):
			for x in range(80):
				grid.set_point_solid(Vector2i(x, y), world.blocked(Vector2(x * 20 + 10, y * 20 + 10), 15))
		path.clear()
	if path.is_empty() or path_target.distance_to(destination) > 40:
		path_target = destination
		var start: Vector2i = _nearest_open(leader.position)
		var goal: Vector2i = _nearest_open(destination)
		path = grid.get_point_path(start, goal)
	while not path.is_empty() and leader.position.distance_to(path[0]) < 18:
		path.remove_at(0)
	if path.is_empty():
		world.set_input_vector(leader.position.direction_to(destination))
	else:
		world.set_input_vector(leader.position.direction_to(path[0]))


func _nearest_open(point: Vector2) -> Vector2i:
	var center: Vector2i = Vector2i(floori(point.x / 20), floori(point.y / 20))
	for radius in range(10):
		for y in range(center.y - radius, center.y + radius + 1):
			for x in range(center.x - radius, center.x + radius + 1):
				var cell: Vector2i = Vector2i(x, y)
				if grid.is_in_boundsv(cell) and not grid.is_point_solid(cell):
					return cell
	return center


func _finish() -> void:
	if is_instance_valid(app):
		app.free()
	elif is_instance_valid(world):
		world.free()
	var directory: String = ProjectSettings.globalize_path(state.save_directory)
	if DirAccess.dir_exists_absolute(directory):
		for filename in DirAccess.get_files_at(directory):
			DirAccess.remove_absolute(directory.path_join(filename))
		DirAccess.remove_absolute(directory)
	root.get_node("Sound").stop_all()
	await create_timer(0.1).timeout
	print("COMBAT_TEST_RESULT " + JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty(), "bosses": boss_ids, "ending": requested_ending, "simulated_seconds": campaign_frames / 60.0}))
	quit(0 if failures.is_empty() else 1)
