extends SceneTree
var checks: int = 0
var failures: Array[String] = []
var app
var state
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func read_lines() -> void:
	for i in range(30):
		if not is_instance_valid(app.dialogue_layer): return
		if app.dialogue_index >= app.dialogue.size(): return
		app.advance_dialogue()
func press(text: String) -> bool:
	for node in app.root.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and text in node.text and not node.disabled:
			node.pressed.emit()
			return true
	return false
func visit(id: String) -> void:
	var npc = app.world.map_data.npcs.filter(func(n): return n.id == id)[0]
	app.world.active_actor().position = app.world.npc_position(npc)
	app.world.interact()
func persist(step: int) -> void:
	var payload: String = state.export_save()
	check(state.import_save(payload) and state.lantern_step() == step, "validated save round-trip request step " + str(step))
func solve(pattern: Array) -> void:
	for i in range(3):
		for n in range(4):
			if app.activities.angles[i] == pattern[i]: break
			app.activities.rotate(i)
func run() -> void:
	state = root.get_node("State")
	state.save_directory = "user://lantern_request_test"
	state.new_game()
	state.complete_stage(0)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.start_game(1, false)
	app.world.set_physics_process(false)
	check(state.lantern_step() == 0, "old-save defaults contain no invented request progress")
	check(not state.claim_lantern_reward("r09"), "reward unavailable before acceptance")
	state.gold = 5000
	check(not state.buy("r09") and not state.buy("r10"), "unique request rewards cannot be bought from shops")
	visit("courier")
	check(is_instance_valid(app.dialogue_layer), "courier opens authored portrait dialogue through E")
	read_lines()
	check(press("เตรียมตัว"), "decline choice exists")
	check(state.lantern_step() == 0, "declining never accepts request")
	visit("courier"); read_lines()
	check(press("ทางใต้"), "accept choice exists")
	check(state.lantern_step() == 1, "accept records first request step")
	persist(1)
	app.open_panel("journal")
	check(app.panel_name == "journal", "request is integrated in real journal")
	app.close_panel()
	state.stage = 1; state.complete_stage(1)
	app.start_game(2, false); app.world.set_physics_process(false)
	app.world.active_actor().position = Vector2(870,700)
	app.world.interact(); read_lines()
	check(state.flags.get("chest_courier_case",false) and state.lantern_step() == 2, "field parcel recovered through world interaction")
	check(not app.world.ready_emitted, "optional parcel never bypasses main road objectives")
	persist(2)
	app.world.active_actor().position = Vector2(130,500)
	app.world.interact()
	app.world.set_physics_process(false)
	check(state.stage == 1, "western return gate travels to Hearthwell without clearing field")
	visit("lantern_child"); read_lines()
	check(state.lantern_step() == 3 and app.activities.mode == "lantern" and app.panel_name == "activity", "Mira hand-in opens calibration after story")
	persist(3)
	solve([0,1,2]); app.activities.submit()
	check(state.lantern_step() == 3, "old chest solution cannot solve lantern calibration")
	app.close_panel(); visit("lantern_child")
	check(app.activities.mode == "lantern", "cancelled calibration is retryable at Mira")
	solve([2,0,3]); app.activities.submit()
	check(state.lantern_step() == 4 and app.activities.mode == "reward", "correct pattern repairs lantern and opens reward choice")
	persist(4)
	check(not state.claim_lantern_reward("r01"), "reward choice rejects unrelated item IDs")
	state.inventory["r09"] = state.MAX_COUNT
	check(not state.claim_lantern_reward("r09") and state.lantern_step() == 4, "full inventory does not consume reward")
	state.inventory.erase("r09")
	var gold: int = state.gold
	check(press("เลือก · เงื่อนแสงเรือน"), "actual reward button chooses Hearthlight Knot")
	check(state.lantern_step() == 5 and state.flags.lantern_reward == "r09" and state.inventory.r09 == 1, "single chosen relic is granted")
	check(state.gold == gold + 120, "one-time gold reward is exact")
	persist(5)
	check(not state.claim_lantern_reward("r10") and not state.claim_lantern_reward("r09"), "repeat clicks and alternate choices cannot duplicate rewards")
	visit("guard_east")
	check(app.dialogue_data == root.get_node("DB").story("lantern_guard_after"), "guard acknowledges rescued families after request")
	read_lines()
	state.flags.erase("lantern_accepted")
	check(state.lantern_step() == 0, "found-before-accepting still waits for player consent")
	state.flags.erase("lantern_reward"); state.flags.erase("lantern_repaired"); state.flags.erase("lantern_delivered")
	state.flags.lantern_accepted = true
	check(state.lantern_step() == 2, "early-discovered case is credited on later acceptance")
	state.flags.lantern_delivered = true; state.flags.lantern_repaired = true
	check(state.claim_lantern_reward("r10"), "alternate relic reward path works")
	app.start_game(2,false); app.world.set_physics_process(false)
	state.equip("c01", "r09")
	var hero = app.world.active_actor()
	hero.hp = hero.max_hp * 0.5
	var hp: float = hero.hp
	var foe = app.world.enemies[0]
	foe.position = hero.position + Vector2(50,0)
	foe.target_point = hero.position
	foe.attack_pattern = 0; foe.windup = 0.4
	hero.dodge_cooldown = 0
	app.world.dodge()
	check(is_equal_approx(hero.hp, hp), "Hearthlight gives no healing for an early ordinary dodge")
	foe.target_point = hero.position; foe.windup = 0.15
	hero.dodge_cooldown = 0
	app.world.dodge()
	check(is_equal_approx(hero.hp - hp, hero.max_hp * 0.08), "perfect dodge restores exactly eight percent HP with Hearthlight")
	state.equip("c01", "r10")
	hero.crit = 0.0; foe.defense = 0; foe.hp = 10000; foe.max_hp = 10000; foe.statuses.clear()
	var normal: float = app.world.damage_enemy(foe,100,hero)
	app.world.apply_status(foe,"weakness",5.0)
	var exposed: float = app.world.damage_enemy(foe,100,hero)
	check(is_equal_approx(normal,100) and is_equal_approx(exposed,150), "Skyglass bonus applies only to weakness on top of base twenty-five percent")
	app.activities.open("music")
	state.flags.music_assist = true
	app.activities.clock = 1.8; app.activities.hit_beat()
	check(app.activities.beats == 1, "assist mode accepts slower timing window")
	app.activities.clock = 0; app.activities.hit_beat()
	check(app.activities.beats == 1, "assist misses preserve accumulated beats")
	for i in range(3):
		app.activities.clock = 1.8; app.activities.hit_beat()
	check(state.flags.get("music_reward",false), "assisted music earns the same reward")
	check(state.save_slot(2) and state.load_slot(2) and state.flags.music_assist, "assist and final reward choice persist on disk")
	print("LANTERN_REQUEST_RESULT " + JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()}))
	app.activities.app = null; app.menus.app = null
	app.queue_free()
	await process_frame
	await process_frame
	root.get_node("Sound").stop_all()
	quit(0 if failures.is_empty() else 1)
