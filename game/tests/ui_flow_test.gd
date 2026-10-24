extends SceneTree
## Production UI flow; campaign combat is covered by the separate campaign runner.
var checks = 0
var failures: Array[String] = []
var app
var state
var db

func _initialize() -> void:
	call_deferred("run")
	create_timer(20).timeout.connect(func(): quit(2))

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)

func run() -> void:
	state=root.get_node("State")
	db=root.get_node("DB")
	state.save_directory="user://ui_test_%d" % Time.get_ticks_usec()
	app=load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	check(is_instance_valid(app.title_layer) and not app.playing,"title screen starts")
	app.open_panel("settings")
	await process_frame
	check(app.panel_name=="settings" and is_instance_valid(app.overlay),"title settings opens")
	app.close_panel()
	app.toggle_language()
	check(state.language=="en","language switches to English")
	app.toggle_language()
	check(state.language=="th","language switches to Thai")
	app.new_game()
	await process_frame
	check(app.playing and state.stage==0,"new game starts classroom")
	check(app.world.actors.size()==3,"three deployed heroes appear")
	check(is_instance_valid(app.dialogue_layer) and app.world.paused,"opening story pauses combat")
	check(app.dialogue.size()>0,"opening contains actual dialogue")
	await drain_dialogue()
	check(not is_instance_valid(app.dialogue_layer) and not app.world.paused,"opening dialogue yields player control")
	check(state.flags.has(str(db.map(0).intro)),"opening scene flag recorded")
	var start: Vector2=app.world.active_actor().position
	app.world.set_input_vector(Vector2.RIGHT)
	for index in range(60):
		await physics_frame
	app.world.set_input_vector(Vector2.ZERO)
	check(app.world.active_actor().position.distance_to(start)>80,"movement responds in actual scene")
	for panel in ["party","inventory","journal","map","pause","camp","craft","shop","settings","saves","save_io","credits"]:
		app.open_panel(panel)
		await process_frame
		check(is_instance_valid(app.overlay) and app.world.paused,"panel opens and pauses: "+panel)
		app.close_panel()
		check(not app.world.paused,"panel closes and resumes: "+panel)
	app.save_game(1,false)
	check(state.slot_info(1).get("valid",false),"main saves validated slot")
	var expected: String=state.export_save()
	app.load_game(1)
	await process_frame
	check(app.playing and state.stage==0,"main restores saved game")
	check(not is_instance_valid(app.dialogue_layer),"seen introduction does not replay after load")
	app.world.heal_party()
	app.save_game(2,false)
	app.show_title()
	await process_frame
	check(not app.playing and not is_instance_valid(app.world),"return to title frees gameplay")
	app.load_game(2)
	await process_frame
	check(app.playing and app.world.actors.size()==3,"title load restores playable party")
	# The legacy ending representation is normalized only when rendering an ending.
	check(db.story("ending_open").get("lines",[]).size()>0,"open ending contains dialogue")
	check(db.story("ending_restore").get("lines",[]).size()>0,"restored barrier ending contains dialogue")
	print(JSON.stringify({"suite":"ui_flow","checks":checks,"failures":failures}))
	app.queue_free()
	root.get_node("Sound").stop_all()
	await create_timer(0.15).timeout
	quit(0 if failures.is_empty() else 1)

func drain_dialogue() -> void:
	var guard=0
	while is_instance_valid(app.dialogue_layer) and guard<100:
		if app.dialogue_index<app.dialogue.size():
			app.advance_dialogue()
		else:
			var buttons: Array[Node]=app.dialogue_layer.find_children("*","Button",true,false)
			if buttons.is_empty(): break
			buttons[0].pressed.emit()
		await process_frame
		guard+=1
