extends SceneTree
var checks: int = 0
var failures: Array[String] = []
var app
var state
var world
func _initialize() -> void: call_deferred("run")
func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func finish_dialogue() -> void:
	for i in range(50):
		if not is_instance_valid(app.dialogue_layer): return
		if app.dialogue_index < app.dialogue.size(): app.advance_dialogue()
		else:
			choose(app.dialogue_layer)
			return
func choose(node: Node) -> bool:
	for child in node.get_children():
		if child is Button:
			child.pressed.emit()
			return true
		if choose(child): return true
	return false
func run() -> void:
	state = root.get_node("State")
	state.save_directory = "user://town_pass_test"
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.new_game()
	world = app.world
	world.set_physics_process(false)
	verify(app.dialogue.size() >= 12, "new game contains the complete classroom prologue")
	finish_dialogue()
	state.complete_stage(0)
	app.start_game(1,true)
	world = app.world
	world.set_physics_process(false)
	finish_dialogue()
	verify(world.enemies.is_empty(), "town is safe and precedes first combat")
	verify(not world.ready_emitted, "town exit waits for orientation and supplies")
	world.active_actor().position = Vector2(425,460)
	world.interact()
	verify(is_instance_valid(app.dialogue_layer), "Sera opens real portrait dialogue")
	finish_dialogue()
	verify(state.flags.get("town_sera",false) and state.flags.get("promise_together",false), "dialogue completion and player promise persist")
	world.active_actor().position = Vector2(650,505)
	world.interact()
	verify(state.flags.get("chest_m01_cache",false), "town supplies collected through real chest interaction")
	verify(not world.ready_emitted, "supplies alone do not bypass route conversation")
	world.active_actor().position = Vector2(1120,515)
	world.interact()
	finish_dialogue()
	verify(world.ready_emitted and state.flags.get("town_ilyen",false), "Ilyen completes town loop and opens gate")
	var saved: String = state.export_save()
	verify(state.import_save(saved) and state.flags.get("promise_together",false), "new town flags round-trip through production save validation")
	state.complete_stage(1)
	world.load_map(2)
	world.paused = false
	var captain = world.enemies.filter(func(e): return bool(e.definition.get("elite",false)))[0]
	verify(captain.max_hp > 200, "field captain has elite threat tier")
	var hero = world.active_actor()
	captain.windup = 0.6
	world._break_windup(captain,hero)
	verify(captain.windup == 0 and captain.statuses.has("weakness"), "heavy break cancels windup and creates punish window")
	var before: int = state.inventory.size()
	world._kill_enemy(captain,hero)
	verify(world.pickups.any(func(v): return bool(v.get("awarded",false))), "elite emits equipment reveal in world")
	var reveal = world.pickups.filter(func(v): return bool(v.get("awarded",false)))[0]
	var count: int = int(state.inventory.get(reveal.item,0))
	verify(count > 0, "valuable drop granted before save or map change")
	world._tick_pickups(8)
	verify(int(state.inventory.get(reveal.item,0)) == count, "reveal expiry cannot duplicate awarded item")
	state.flags["loot_pity"] = 3
	var target = world.enemies[0]
	world._drop_equipment(target)
	verify(int(state.flags.loot_pity) == 0, "fourth ordinary kill guarantees equipment and resets persistent pity")
	world._check_objectives()
	verify(not world.ready_emitted, "captain defeat alone does not skip Hana’s bag")
	world.active_actor().position = Vector2(360,660)
	world.interact()
	finish_dialogue()
	world.active_actor().position = Vector2(1060,340)
	world.interact()
	verify(world.ready_emitted and not world.enemies.is_empty(), "rescue clue and captain unlock road with optional patrols still alive")
	world.load_map(3)
	var boss = world.enemies.filter(func(e): return e.boss)[0]
	world._kill_enemy(boss,world.active_actor())
	verify(int(state.inventory.get("r01",0)) > 0, "Warden guarantees its own relic")
	state.equip(world.active_actor().id,"r01")
	hero = world.active_actor()
	hero.hp = hero.max_hp*0.5
	var hp: float = hero.hp
	hero.dodge_cooldown = 0
	world.dodge()
	verify(hero.hp > hp, "equipped Warden relic changes dodge behavior")
	for id in ["n01","n02"]:
		verify(PortraitLibrary.is_illustrated(root.get_node("DB").character(id)), id+" portrait registered")
		verify(VisualAnimation.atlas_texture(id) != null,id+" directional action atlas loads")
	print("TOWN_PASS_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()}))
	app.free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
