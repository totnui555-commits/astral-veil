extends SceneTree
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	var state = root.get_node("State")
	state.save_directory = "user://living_city_test"
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	state.new_game()
	state.complete_stage(0)
	app.start_game(1,false)
	var world = app.world
	world.set_physics_process(false)
	check(world.map_data.width == 3200 and world.map_data.npcs.size() == 12,"city twice the area with twelve interactions")
	check(not world.blocked(Vector2(1600,500)) and not world.blocked(Vector2(2700,500)),"continuous connection to market")
	for id in ["c02","c03","c05"]:
		check(id in state.recruited,"new illustrated hero available in town "+id)
		check(VisualAnimation.atlas_texture(id).get_size()==Vector2(1536,1536),"high density atlas "+id)
		check(PortraitLibrary.is_illustrated(root.get_node("DB").character(id)),"portrait "+id)
	var leila_npc = world.map_data.npcs.filter(func(n):return n.id=="leila_square")[0]
	app._on_interaction("npc",leila_npc)
	check(app.dialogue_focus==world.npc_position(leila_npc),"dialogue camera targets the interacting NPC despite reused character art")
	while is_instance_valid(app.dialogue_layer): app.advance_dialogue()
	var chest: Dictionary = world.map_data.chests[-1]
	var before: int = int(state.inventory.get(chest.item,0))
	app.activities.open("chest",chest)
	app.activities.submit()
	check(int(state.inventory.get(chest.item,0)) == before and app.panel_name=="activity","wrong answer grants nothing")
	app.close_panel()
	check(not state.flags.get("chest_"+chest.id,false),"cancellation leaves chest available")
	app.activities.open("chest",chest)
	for i in range(3):
		while app.activities.angles[i] != app.activities.PATTERN[i]: app.activities.rotate(i)
	app.activities.submit()
	check(state.flags.get("festival_unlocked",false) and int(state.inventory.get(chest.item,0))==before+1,"puzzle unlocks outfit and one item")
	world.claim_chest(chest)
	check(int(state.inventory.get(chest.item,0))==before+1,"no duplicate chest grant")
	state.flags["outfit_c02"]="festival"
	check(VisualAnimation.costume_id("c02")=="c02_festival","outfit selects actual alternate atlas")
	check(PortraitLibrary.full_texture(root.get_node("DB").character("c02")).atlas.resource_path.ends_with("festival_portraits_living.png"),"outfit portrait matches alternate clothing")
	check(state.save_slot(2),"costume save succeeds")
	state.flags.erase("outfit_c02")
	check(state.load_slot(2) and state.flags.get("outfit_c02","")=="festival","outfit persists after load")
	app.activities.open("music")
	app.activities.clock=0
	app.activities.hit_beat()
	check(app.activities.beats==0,"missed rhythm beat not rewarded")
	for i in range(4):
		app.activities.clock=1.2
		app.activities.hit_beat()
	check(state.flags.get("music_reward",false) and app.panel_name=="","music completion awards once and resumes")
	app.start_game(3,false)
	world=app.world
	world.set_physics_process(false)
	var boss = world.enemies.filter(func(e): return e.boss)[0]
	var hero = world.active_actor()
	world.damage_enemy(boss,100000,hero)
	check(is_instance_valid(boss) and world.seal_active(boss),"lethal damage stops at Warden seal")
	var hp: float = boss.hp
	world.damage_enemy(boss,100000,hero)
	check(boss.hp==hp,"sealed boss immune until puzzle solved")
	hero.position=boss.position+Vector2(110,0)
	world.interact()
	check(app.panel_name=="activity" and app.activities.mode=="seal","real proximity interaction opens boss puzzle")
	for i in range(3):
		while app.activities.angles[i] != app.activities.PATTERN[i]: app.activities.rotate(i)
	app.activities.submit()
	check(not world.seal_active(boss) and boss.statuses.has("weakness"),"solved seal exposes boss")
	world.damage_enemy(boss,100000,hero)
	check(world.enemies.filter(func(e): return e.boss).is_empty(),"boss can be defeated after unsealing")
	app.start_game(2,false)
	world=app.world;world.set_physics_process(false);hero=world.active_actor()
	var foe=world.enemies[0]
	hero.position=Vector2(500,500);foe.position=Vector2(560,500)
	foe.target_point=hero.position;foe.attack_pattern=0;foe.windup=0.15
	hero.skill_cooldown=5;hero.dodge_cooldown=0
	world.dodge()
	check(hero.counter_window>0 and hero.skill_cooldown==3,"timed dodge earns counter and cooldown refund")
	for i in range(3):
		hero.attack_cooldown=0
		world.attack()
	check(hero.chain_count==0 and world.effects.any(func(e): return e.kind=="crescent"),"three attacks resolve finisher VFX")
	print("LIVING_CITY_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()}))
	app.activities.app=null
	app.menus.app=null
	app.free()
	await process_frame
	root.get_node("Sound").stop_all()
	quit(0 if failures.is_empty() else 1)
