extends SceneTree
var failures: Array[String] = []
var checks = 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	root.get_node("State").new_game()
	app.config.touch = true
	app.start_game(2,false)
	await process_frame
	await process_frame
	var actions: Dictionary = {}
	for node in app.hud.find_children("*","Button",true,false):
		if node.has_meta("qa_action"): actions[str(node.get_meta("qa_action"))] = node
	for key in ["attack","heavy","skill","ultimate","dodge","interact","potion","tactics"]:
		check(actions.has(key),"missing action "+key)
	for a in actions:
		for b in actions:
			if a < b: check(not actions[a].get_global_rect().intersects(actions[b].get_global_rect()),a+" overlaps "+b)
	for card in app.hud_cards:
		for action in actions:
			check(not card.panel.get_global_rect().intersects(actions[action].get_global_rect()),"party card overlaps "+action)
	for key in ["attack","heavy","skill","ultimate","dodge","potion","interact"]:
		check(actions[key].emblem is AtlasTexture,"illustrated icon integrated for "+key)
		check(not actions[key].show_shortcut,"touch mode hides keyboard legend for "+key)
	check(actions.attack.size.x >= 120,"attack has large touch target")
	var actor = app.world.active_actor()
	var mana: float = actor.mp
	actions.skill.pressed.emit()
	check(actor.mp < mana and actor.skill_cooldown > 0,"skill button casts real skill")
	app._refresh_hud()
	check(actions.skill.cooldown_fraction > 0,"cooldown reflects cast")
	var touch = InputEventScreenTouch.new()
	touch.index = 3
	touch.pressed = true
	touch.position = Vector2(130,82)
	app.joystick_pad.gui_input.emit(touch)
	check(app.touch_origin.x > 0,"joystick follows touch")
	touch.pressed = false
	app._input(touch)
	check(app.touch_origin == Vector2.ZERO and app.joystick_id == -1,"global release resets joystick")
	actor.mp = 0
	app._refresh_hud()
	check(actions.skill.unavailable,"insufficient mana is visible")
	actor.mp = mana
	app._refresh_hud()
	if OS.get_cmdline_user_args().has("--capture"):
		await capture("res://../qa/ux-refresh-mobile.png" if OS.get_cmdline_user_args().has("--mobile") else "res://../qa/ux-refresh-touch.png")
		app.open_panel("party")
		await process_frame
		await capture("res://../qa/ux-refresh-party-mobile.png" if OS.get_cmdline_user_args().has("--mobile") else "res://../qa/ux-refresh-party.png")
		var navigation = app.overlay.find_children("*","Button",true,false).filter(func(button): return button.get_meta("qa_action","")=="nav_inventory")
		check(navigation.size()==1,"inventory navigation is accessible")
		if not navigation.is_empty(): navigation[0].pressed.emit()
		await process_frame
		check(app.panel_name=="inventory" and app.world.paused,"navigation switches menu and preserves pause")
		await capture("res://../qa/ux-refresh-inventory-mobile.png" if OS.get_cmdline_user_args().has("--mobile") else "res://../qa/ux-refresh-inventory.png")
		app.close_panel()
		check(not app.world.paused,"navigation menu closes and resumes gameplay")
		app.config.touch = false
		app.start_game(2,false)
		await process_frame
		await capture("res://../qa/ux-refresh-keyboard-mobile.png" if OS.get_cmdline_user_args().has("--mobile") else "res://../qa/ux-refresh-desktop.png")
		app.config.touch = true
		app.start_game(3,false)
		app.world.set_physics_process(false)
		var boss = app.world.enemies.filter(func(foe): return foe.boss)[0]
		boss.boss_engaged = true
		app.world.active_actor().position = boss.position-Vector2(160,0)
		app.world.camera.position = boss.position-Vector2(80,0)
		await process_frame
		app._refresh_hud()
		await capture("res://../qa/ux-refresh-boss-mobile.png" if OS.get_cmdline_user_args().has("--mobile") else "res://../qa/ux-refresh-boss.png")
		app.show_title()
		await process_frame
		var title_buttons = app.title_layer.find_children("*","Button",true,false)
		for a in title_buttons:
			for b in title_buttons:
				if a.get_instance_id() < b.get_instance_id():
					check(not a.get_global_rect().intersects(b.get_global_rect()),"title buttons do not overlap")
		await capture("res://../qa/ux-refresh-title-mobile.png" if OS.get_cmdline_user_args().has("--mobile") else "res://../qa/ux-refresh-title.png")
		app.start_game(0,true)
		await process_frame
		await capture("res://../qa/ux-refresh-dialogue-mobile.png" if OS.get_cmdline_user_args().has("--mobile") else "res://../qa/ux-refresh-dialogue.png")
	print(JSON.stringify({"suite":"combat_hud","checks":checks,"failures":failures}))
	app.queue_free()
	root.get_node("Sound").stop_all()
	await create_timer(0.2).timeout
	quit(0 if failures.is_empty() else 1)

func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
