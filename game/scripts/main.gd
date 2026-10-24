extends Node

const WorldScene = preload("res://scripts/world.gd")
const Menus = preload("res://scripts/menu_panels.gd")
const Widgets = preload("res://scripts/fantasy_widgets.gd")
var world: Node2D
var ui: CanvasLayer
var root: Control
var title_layer: Control
var hud: Control
var overlay: Control
var dialogue_layer: Control
var toast_label: Label
var menus
var activities
var story_camera_tween: Tween
var playing = false
var panel_name = ""
var selected_hero = "c01"
var hud_cards: Array = []
var hud_obstructions: Array[Control] = []
var objective_label: Label
var region_label: Label
var threat_label: Label
var skill_button: Button
var relay_label: Label
var ultimate_button: Button
var dialogue: Array = []
var dialogue_index = 0
var dialogue_data: Dictionary = {}
var dialogue_finish = Callable()
var last_speaker = ""
var dialogue_focus: Vector2 = Vector2.INF
var refresh_timer = 0.0
var toast_timer = 0.0
var title_time = 0.0
var config = {"master":0.7,"music":0.55,"effects":0.75,"touch":false,"shake":true,"language":"th","difficulty":"normal"}
var touch_layer: Control
var touch_origin = Vector2.ZERO
var joystick_id = -1
var transition_busy = false
var qa_enabled = false
var save_pending: Dictionary = {}
var queued_saves: Dictionary = {}
var save_results: Dictionary = {}
var joystick_pad: Control
var qa_save_file_cache: Dictionary = {}

func _ready() -> void:
	_setup_input()
	qa_enabled = OS.get_cmdline_user_args().has("--qa")
	if OS.has_feature("web"):
		qa_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('qa')"))
	_load_config()
	ui = CanvasLayer.new()
	add_child(ui)
	root = Control.new()
	root.name = "Interface"
	root.theme = VeilUI.theme()
	VeilUI.fill(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	menus = Menus.new(self)
	activities = CityActivities.new(self)
	State.notification.connect(toast)
	State.changed.connect(_on_state_changed)
	Sound.set_levels(float(config.master),float(config.music),float(config.effects))
	show_title()

func _setup_input() -> void:
	var keys = {"move_left":[KEY_A,KEY_LEFT],"move_right":[KEY_D,KEY_RIGHT],"move_up":[KEY_W,KEY_UP],"move_down":[KEY_S,KEY_DOWN],"attack":[KEY_J],"heavy":[KEY_K],"skill":[KEY_Q],"ultimate":[KEY_R],"dodge":[KEY_SPACE],"switch_next":[KEY_TAB],"interact":[KEY_E]}
	for action in keys:
		if not InputMap.has_action(action): InputMap.add_action(action)
		for key in keys[action]:
			var event = InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action,event)
	for pair in [["attack",JOY_BUTTON_X],["heavy",JOY_BUTTON_Y],["dodge",JOY_BUTTON_A],["interact",JOY_BUTTON_B],["skill",JOY_BUTTON_LEFT_SHOULDER],["switch_next",JOY_BUTTON_RIGHT_SHOULDER],["ultimate",JOY_BUTTON_BACK]]:
		var event = InputEventJoypadButton.new()
		event.button_index = pair[1]
		InputMap.action_add_event(pair[0],event)
	for pair in [["move_left",JOY_AXIS_LEFT_X,-1.0],["move_right",JOY_AXIS_LEFT_X,1.0],["move_up",JOY_AXIS_LEFT_Y,-1.0],["move_down",JOY_AXIS_LEFT_Y,1.0]]:
		var event = InputEventJoypadMotion.new()
		event.axis = pair[1]
		event.axis_value = pair[2]
		InputMap.action_add_event(pair[0],event)

func t(key: String) -> String:
	return DB.text(key)

func tx(value) -> String:
	return DB.localized(value)

func clear_ui() -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()
	title_layer = null
	hud = null
	overlay = null
	dialogue_layer = null
	toast_label = null
	touch_layer = null
	joystick_pad = null
	panel_name = ""

func show_title() -> void:
	playing = false
	if is_instance_valid(world):
		world.queue_free()
		world = null
	clear_ui()
	Sound.play_music("title")
	title_layer = Control.new()
	VeilUI.fill(title_layer)
	root.add_child(title_layer)
	if ResourceLoader.exists("res://art/vertical/title/sanctuary.png"):
		var bg = TextureRect.new()
		bg.texture = load("res://art/vertical/title/sanctuary.png")
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		VeilUI.fill(bg)
		title_layer.add_child(bg)
	var shade = TextureRect.new()
	var gradient = Gradient.new()
	gradient.set_color(0,Color(0.025,0.05,0.08,0.98))
	gradient.set_color(1,Color(0.025,0.05,0.08,0.07))
	gradient.add_point(0.45,Color(0.025,0.05,0.08,0.72))
	var texture = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 1152
	texture.height = 1
	shade.texture = texture
	VeilUI.fill(shade)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_layer.add_child(shade)
	# The three original illustrations match the playable hero sprites.
	for entry in [["c01",Vector2(455,152),Vector2(240,480)],["c04",Vector2(674,116),Vector2(256,512)],["c07",Vector2(898,152),Vector2(240,480)]]:
		var illustration=TextureRect.new()
		illustration.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		illustration.texture=PortraitLibrary.full_texture(DB.character(entry[0]))
		illustration.position=entry[1]
		illustration.size=entry[2]
		illustration.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		illustration.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		illustration.mouse_filter=Control.MOUSE_FILTER_IGNORE
		title_layer.add_child(illustration)
	var eyebrow = VeilUI.label("A WORLD REMEMBERS. THIRTY WILL ANSWER.",13,VeilUI.GOLD)
	eyebrow.position = Vector2(66,90)
	title_layer.add_child(eyebrow)
	var title = VeilUI.heading("ASTRAL\nVEIL",78,VeilUI.WHITE)
	if ResourceLoader.exists("res://art/fonts/NotoSerif-Regular.ttf"): title.add_theme_font_override("font",load("res://art/fonts/NotoSerif-Regular.ttf"))
	title.add_theme_constant_override("line_spacing",-18)
	title.position = Vector2(60,119)
	title_layer.add_child(title)
	var subtitle = VeilUI.label("T H E   S U M M O N E D   T H I R T Y",15,VeilUI.GOLD)
	subtitle.position = Vector2(67,323)
	title_layer.add_child(subtitle)
	var blurb = VeilUI.prose(t("title_blurb"),17,VeilUI.MUTED)
	blurb.position = Vector2(67,370)
	blurb.size = Vector2(420,65)
	title_layer.add_child(blurb)
	var actions = VBoxContainer.new()
	actions.position = Vector2(66,436)
	actions.size = Vector2(322,174)
	actions.add_theme_constant_override("separation",8)
	title_layer.add_child(actions)
	var begin = VeilUI.button("✦  " + t("new_game"),new_game,322)
	begin.custom_minimum_size.y=52
	begin.add_theme_stylebox_override("normal",VeilUI.button_style("selected"))
	actions.add_child(begin)
	var row = HBoxContainer.new()
	actions.add_child(row)
	for entry in [["continue","saves"],["settings","settings"]]:
		var destination = str(entry[1])
		var secondary = VeilUI.button(t(str(entry[0])),func(): open_panel(destination),156)
		secondary.custom_minimum_size.y=48
		row.add_child(secondary)
	var language = VeilUI.button("ไทย / EN",toggle_language,108)
	language.position = Vector2(978,32)
	title_layer.add_child(language)
	var memories = VeilUI.button(t("chronicle"),func(): open_panel("chronicle"),320)
	memories.custom_minimum_size.y=44
	actions.add_child(memories)
	var version = VeilUI.label("ROYAL SUMMONING & RELAY  ·  v0.3  /  " + t("offline"),12,VeilUI.MUTED)
	version.position = Vector2(66,620)
	title_layer.add_child(version)
	var credit = VeilUI.button(t("credits"),func(): open_panel("credits"),100)
	credit.position = Vector2(984,578)
	title_layer.add_child(credit)
	begin.grab_focus()
	_create_toast()

func new_game() -> void:
	State.new_game()
	State.language = str(config.language)
	State.difficulty = str(config.difficulty)
	start_game(0,true)

func start_game(stage: int, show_intro: bool = true) -> void:
	playing = true
	clear_ui()
	if is_instance_valid(world): world.queue_free()
	world = WorldScene.new()
	add_child(world)
	move_child(world,0)
	world.interacted.connect(_on_interaction)
	world.party_defeated.connect(_on_defeat)
	world.message.connect(toast)
	world.stage_ready.connect(func(): toast(t("gate_open")))
	if stage == State.respite_next(): State.flags.erase("respite_next")
	State.stage = stage
	State.recruit_through(stage)
	world.load_map(stage)
	_build_hud()
	_create_toast()
	var map = world.map_data
	Sound.play_music("village" if map.get("safe",false) else "dungeon" if not map.get("boss",{}).is_empty() else "explore")
	world.paused = true
	if show_intro and not str(map.get("intro","")) in State.flags:
		show_story(str(map.get("intro","")),func():
			State.flags[str(map.get("intro",""))] = true
			world.paused = false
			save_game(0,false))
	else:
		world.paused = false
	_refresh_hud()

func _build_hud() -> void:
	hud_obstructions.clear()
	hud = Control.new()
	VeilUI.fill(hud)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	hud_cards.clear()
	var squad = HBoxContainer.new()
	squad.position = Vector2(228,544)
	squad.size = Vector2(510,64)
	squad.add_theme_constant_override("separation",8)
	hud.add_child(squad)
	hud_obstructions.append(squad)
	for i in range(3):
		var panel = PanelContainer.new()
		panel.custom_minimum_size = Vector2(168,78)
		var card_style=VeilUI.box(Color("0b1c27ed"),VeilUI.GOLD if i == State.active_index else Color("334d58"))
		card_style.set_content_margin_all(6)
		panel.add_theme_stylebox_override("panel",card_style)
		squad.add_child(panel)
		var row = HBoxContainer.new()
		panel.add_child(row)
		var id = str(State.party[i]) if i < State.party.size() else "c01"
		var portrait_frame = VeilUI.framed_portrait(DB.character(id),44)
		var portrait = portrait_frame.get_child(0)
		row.add_child(portrait_frame)
		var info = VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation",3)
		row.add_child(info)
		var label = VeilUI.label("",16)
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		info.add_child(label)
		var health = VeilUI.bar(100,100,VeilUI.TEAL,100,8)
		info.add_child(health)
		var mana = VeilUI.bar(50,50,Color("788fcf"),100,4)
		info.add_child(mana)
		var details = VeilUI.label("",12,VeilUI.MUTED)
		details.visible = true
		details.clip_text = true
		details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		info.add_child(details)
		hud_cards.append({"panel":panel,"label":label,"health":health,"mana":mana,"details":details,"portrait":portrait})
		var click = Button.new()
		VeilUI.fill(click)
		click.flat = true
		click.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		for state in ["normal","pressed","disabled"]: click.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		for state in ["hover","focus"]: click.add_theme_stylebox_override(state,VeilUI.surface(Color(0,0,0,0.04),VeilUI.TEAL,0,4))
		click.tooltip_text = t("switch")
		click.pressed.connect(func():
			if panel_name == "" and not is_instance_valid(dialogue_layer): world.switch_to(i))
		panel.add_child(click)
	var quest_panel = PanelContainer.new()
	quest_panel.position = Vector2(20,146)
	quest_panel.custom_minimum_size = Vector2(252,84)
	quest_panel.add_theme_stylebox_override("panel",VeilUI.surface(Color("0b1924f5"),Color("405252"),12,8))
	hud.add_child(quest_panel)
	hud_obstructions.append(quest_panel)
	var quest_box = VBoxContainer.new()
	quest_panel.add_child(quest_box)
	quest_box.add_child(VeilUI.label("✧  " + t("current_objective"),12,VeilUI.GOLD))
	objective_label = VeilUI.prose("",17)
	objective_label.custom_minimum_size.x = 228
	objective_label.max_lines_visible = 3
	objective_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	quest_box.add_child(objective_label)
	threat_label = VeilUI.label("",12,VeilUI.MUTED)
	quest_box.add_child(threat_label)
	var map_frame=PanelContainer.new()
	map_frame.position=Vector2(20,20)
	map_frame.size=Vector2(196,114)
	map_frame.add_theme_stylebox_override("panel",VeilUI.card_style())
	hud.add_child(map_frame)
	hud_obstructions.append(map_frame)
	var minimap=Widgets.MiniMap.new()
	minimap.world=world
	minimap.custom_minimum_size=Vector2(164,86)
	minimap.mouse_filter=Control.MOUSE_FILTER_IGNORE
	map_frame.add_child(minimap)
	var boss_banner=Widgets.BossBanner.new()
	boss_banner.world=world
	boss_banner.position=Vector2(326,12)
	boss_banner.size=Vector2(500,76)
	boss_banner.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud.add_child(boss_banner)
	var tools = HBoxContainer.new()
	tools.position = Vector2(864,20)
	tools.add_theme_constant_override("separation",6)
	hud.add_child(tools)
	hud_obstructions.append(tools)
	for entry in [["party",""],["inventory",""],["pause","Esc"]]:
		var key = str(entry[0])
		var tool = VeilUI.button(t(key)+( " "+str(entry[1]) if not (DisplayServer.is_touchscreen_available() or bool(config.touch)) and not str(entry[1]).is_empty() else ""),func(): open_panel(key),74)
		tool.add_theme_font_size_override("font_size",16)
		tools.add_child(tool)
	region_label = VeilUI.label("",16,VeilUI.GOLD)
	region_label.add_theme_stylebox_override("normal",VeilUI.surface(Color("0b1924ed"),Color("405252"),8,8))
	region_label.position = Vector2(320,24)
	region_label.size = Vector2(510,28)
	region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(region_label)
	var skills = Control.new()
	skills.position = Vector2(832,346)
	skills.size = Vector2(306,294)
	skills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	hud.add_child(skills)
	skills.visible = not bool(world.map_data.get("safe",false))
	hud_obstructions.append(skills)
	if not bool(world.map_data.get("safe",false)):
		var tactics = VeilUI.button(activities.local_text("Tactics", "วางแผน") if DisplayServer.is_touchscreen_available() or bool(config.touch) else activities.local_text("F · Tactics", "F · วางแผน"),func(): open_panel("tactics"),160)
		tactics.position = Vector2(20,302)
		tactics.set_meta("qa_action", "tactics")
		hud.add_child(tactics)
		hud_obstructions.append(tactics)
		relay_label = VeilUI.label("",16,VeilUI.GOLD)
		relay_label.position = Vector2(270,96)
		hud.add_child(relay_label)
	var attack = Widgets.action("J","weapon",func(): if_can_act("attack"),"attack")
	attack.position = Vector2(176,150)
	attack.size = Vector2(124,124)
	attack.caption = t("attack")
	attack.action_kind = "attack"
	skills.add_child(attack)
	var heavy = Widgets.action("K","armor",func(): if_can_act("heavy"),"heavy")
	heavy.position = Vector2(84,188)
	heavy.size = Vector2(84,92)
	heavy.caption = activities.local_text("Heavy", "โจมตีหนัก")
	heavy.action_kind = "heavy"
	skills.add_child(heavy)
	skill_button = Widgets.action("Q","relic",func(): if_can_act("skill"),"skill")
	skill_button.position = Vector2(84,82)
	skill_button.size = Vector2(88,96)
	skill_button.caption = activities.local_text("Skill", "สกิล")
	skill_button.action_kind = "skill"
	skills.add_child(skill_button)
	ultimate_button = Widgets.action("R","accessory",func(): if_can_act("ultimate"),"ultimate")
	ultimate_button.position = Vector2(188,20)
	ultimate_button.size = Vector2(96,104)
	ultimate_button.caption = activities.local_text("Ultimate", "ท่าไม้ตาย")
	ultimate_button.action_kind = "ultimate"
	skills.add_child(ultimate_button)
	var dodge = Widgets.action("␣","material",func(): if_can_act("dodge"),"dodge")
	dodge.position = Vector2(-8,186)
	dodge.size = Vector2(84,92)
	dodge.caption = activities.local_text("Dodge", "หลบ")
	dodge.action_kind = "dodge"
	skills.add_child(dodge)
	var interact = Widgets.action("E","map",func(): if_can_act("interact"),"interact")
	interact.tooltip_text=t("interact")
	interact.caption=t("interact")
	interact.position = Vector2(1058,232)
	interact.size=Vector2(70,76)
	hud.add_child(interact)
	hud_obstructions.append(interact)
	var potion = Widgets.action("H","consumable",use_potion,"potion")
	potion.tooltip_text=t("potion")
	potion.caption=activities.local_text("Potion", "ยา")
	potion.position = Vector2(748,434)
	potion.size=Vector2(70,76)
	hud.add_child(potion)
	potion.visible = not bool(world.map_data.get("safe",false))
	hud_obstructions.append(potion)
	var hint = VeilUI.label(t("controls_hint"),11,VeilUI.MUTED)
	hint.position = Vector2(22,620)
	hint.visible = not (DisplayServer.is_touchscreen_available() or bool(config.touch))
	hud.add_child(hint)
	for control in hud.find_children("*","Button",true,false):
		if control is Widgets.ActionOrb:
			control.show_shortcut = not (DisplayServer.is_touchscreen_available() or bool(config.touch))
	_build_touch()

func if_can_act(action: String) -> void:
	if not playing or not is_instance_valid(world) or world.paused: return
	match action:
		"heavy": world.attack(true)
		"attack": world.attack(false)
		"skill": world.skill()
		"ultimate": world.ultimate()
		"dodge": world.dodge()
		"interact": world.interact()

func _build_touch() -> void:
	touch_origin = Vector2.ZERO
	joystick_id = -1
	if not (DisplayServer.is_touchscreen_available() or bool(config.touch)): return
	touch_layer = Control.new()
	VeilUI.fill(touch_layer)
	touch_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(touch_layer)
	var pad = Control.new()
	pad.position = Vector2(36,416)
	pad.size = Vector2(164,164)
	joystick_pad=pad
	pad.draw.connect(func():
		pad.draw_circle(Vector2(82,82),77,Color("07181dc9"))
		pad.draw_arc(Vector2(82,82),76,0,TAU,64,Color("bda67a"),2)
		pad.draw_arc(Vector2(82,82),68,0,TAU,64,Color("376258"),1)
		for angle in [0.0,PI/2,PI,PI*1.5]:
			var direction=Vector2.from_angle(angle)
			pad.draw_line(Vector2(82,82)+direction*50,Vector2(82,82)+direction*61,VeilUI.GOLD,2)
		var stick = Vector2(82,82)+touch_origin*48
		pad.draw_circle(stick,25,Color("326c63"))
		pad.draw_arc(stick,25,0,TAU,32,Color("d0c19a"),1))
	pad.gui_input.connect(func(event):
		if event is InputEventScreenTouch:
			if event.pressed and joystick_id == -1:
				joystick_id=event.index
				touch_origin = (event.position-Vector2(82,82)).limit_length(62)/62.0
				world.set_input_vector(touch_origin)
				pad.queue_redraw()
			elif joystick_id==event.index:
				joystick_id=-1
				touch_origin=Vector2.ZERO
				pad.queue_redraw()
				world.set_input_vector(Vector2.ZERO)
		if event is InputEventScreenDrag and event.index==joystick_id:
			touch_origin = (event.position-Vector2(82,82)).limit_length(62)/62.0
			world.set_input_vector(touch_origin)
			pad.queue_redraw())
	touch_layer.add_child(pad)

func _refresh_hud() -> void:
	if is_instance_valid(relay_label) and is_instance_valid(world):
		relay_label.text = (activities.local_text("RELAY · switch ally  ", "ส่งต่อ · สลับเพื่อน  ")+"%.1fs" % world.relay_time) if world.relay_time > 0 else ""
	if not playing or not is_instance_valid(world) or not is_instance_valid(hud): return
	for i in range(mini(hud_cards.size(),world.actors.size())):
		var actor = world.actors[i]
		var card = hud_cards[i]
		var definition = DB.character(actor.id)
		card.label.text = tx(definition.get("name",actor.id)).split(" ")[0] + "  ·  " + str(int(State.hero(actor.id).get("level",1)))
		card.health.max_value = actor.max_hp
		card.health.value = actor.hp
		card.mana.max_value = actor.max_mp
		card.mana.value = actor.mp
		card.details.text = str(int(actor.hp))+" / "+str(int(actor.max_hp))+" HP"
		card.portrait.texture = PortraitLibrary.texture(definition)
		var card_style=VeilUI.box(Color("0b1c27ed"),VeilUI.GOLD if i==State.active_index else Color("334d58"))
		card_style.set_content_margin_all(6)
		card.panel.add_theme_stylebox_override("panel",card_style)
	var map = DB.map(State.stage)
	objective_label.text = world.objective_text()
	if DisplayServer.is_touchscreen_available() or bool(config.touch): objective_label.text=objective_label.text.replace(" · E","")
	region_label.text = t("act") + " " + str(int(map.get("act",1))) + "    /    " + tx(map.get("name",""))
	region_label.visible = not world.enemies.any(func(foe): return foe.boss and foe.boss_engaged and not foe.defeated)
	var threat = float(State.threat.get(map.get("region","verdant"),0.0))
	threat_label.visible = not bool(map.get("safe",false))
	threat_label.text = t("threat") + " " + str(int(threat)) + "%   ·   " + str(world.enemies.size()) + " " + t("enemies")
	var actor = world.active_actor()
	if actor:
		var screen_position: Vector2 = root.get_global_transform_with_canvas().affine_inverse() * actor.get_global_transform_with_canvas().origin
		var silhouettes: Array[Rect2] = [Rect2(screen_position-Vector2(35,70),Vector2(70,82))]
		for foe in world.enemies:
			if foe.boss and foe.boss_engaged and not foe.defeated:
				var boss_screen: Vector2 = root.get_global_transform_with_canvas().affine_inverse() * foe.get_global_transform_with_canvas().origin
				silhouettes.append(Rect2(boss_screen-Vector2(64,112),Vector2(128,124)))
		for group in hud_obstructions:
			var obscured=false
			for silhouette in silhouettes:
				if group.get_global_rect().intersects(silhouette): obscured=true
			group.modulate.a=.78 if obscured else 1.0
		skill_button.text = "%.1f" % actor.skill_cooldown if actor.skill_cooldown > 0 else "Q"
		skill_button.unavailable = actor.mp < 18 or actor.defeated
		skill_button.caption = activities.local_text("Low mana", "มานาไม่พอ") if actor.mp < 18 else activities.local_text("Skill", "สกิล")
		skill_button.tooltip_text = activities.local_text("Needs 18 mana", "ต้องใช้มานา 18") if actor.mp < 18 else ""
		skill_button.tooltip_text=tx(DB.character(actor.id).get("skill_name","Q"))+ (activities.local_text(" · Needs 18 mana", " · ต้องใช้มานา 18") if actor.mp < 18 else "")
		ultimate_button.text = str(int(actor.ultimate_charge)) + "%"
		ultimate_button.unavailable = actor.ultimate_charge < 100 or actor.defeated
		ultimate_button.caption = activities.local_text("Ready!", "พร้อมใช้") if actor.ultimate_charge >= 100 else activities.local_text("Ultimate", "ท่าไม้ตาย")
		ultimate_button.tooltip_text=t("ultimate")
		skill_button.cooldown_fraction = clampf(actor.skill_cooldown / (maxf(3.2,6.5-int(State.derived(actor.id).get("skill_rank",1))*0.5)),0,1)
		ultimate_button.cooldown_fraction = 1.0-clampf(actor.ultimate_charge/100.0,0,1)
		skill_button.queue_redraw()
		ultimate_button.queue_redraw()

func _process(delta: float) -> void:
	if activities != null: activities.tick(delta)
	refresh_timer -= delta
	if refresh_timer <= 0:
		refresh_timer=0.12
		_refresh_hud()
		_update_qa_snapshot()
	if toast_timer>0:
		toast_timer-=delta
		if is_instance_valid(toast_label): toast_label.modulate.a = minf(1,toast_timer)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE and panel_name == "activity" and activities.mode == "music":
		activities.hit_beat()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_ESCAPE and not is_instance_valid(dialogue_layer):
		if panel_name!="": close_panel()
		elif playing: open_panel("pause")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch and not event.pressed and event.index==joystick_id:
		joystick_id=-1
		touch_origin=Vector2.ZERO
		if is_instance_valid(joystick_pad): joystick_pad.queue_redraw()
		if is_instance_valid(world): world.set_input_vector(Vector2.ZERO)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.pressed and event.index==joystick_id:
		joystick_id=-1
		touch_origin=Vector2.ZERO
		if is_instance_valid(joystick_pad): joystick_pad.queue_redraw()
		if is_instance_valid(world): world.set_input_vector(Vector2.ZERO)
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index==JOY_BUTTON_START:
			if playing: open_panel("pause") if panel_name=="" else close_panel()
			get_viewport().set_input_as_handled()
		elif is_instance_valid(dialogue_layer) and event.button_index==JOY_BUTTON_A:
			advance_dialogue()
	if not event is InputEventKey or not event.pressed or event.echo: return
	if is_instance_valid(dialogue_layer):
		if event.physical_keycode in [KEY_E,KEY_ENTER,KEY_SPACE]:
			advance_dialogue()
			get_viewport().set_input_as_handled()
		return
	if event.physical_keycode==KEY_ESCAPE:
		if panel_name!="": close_panel()
		elif playing: open_panel("pause")
		return
	if not playing: return
	if event.physical_keycode==KEY_F5:
		save_game(1)
	elif event.physical_keycode==KEY_F9:
		load_game(1)
	elif panel_name=="":
		match event.physical_keycode:
			KEY_C: open_panel("party")
			KEY_F: open_panel("tactics")
			KEY_I: open_panel("inventory")
			KEY_L: open_panel("journal")
			KEY_M: open_panel("map")
			KEY_H: use_potion()
			KEY_1: world.switch_to(0)
			KEY_2: world.switch_to(1)
			KEY_3: world.switch_to(2)

func _on_interaction(kind: String, data: Dictionary) -> void:
	match kind:
		"puzzle": activities.open("chest", data)
		"seal": activities.open("seal", data)
		"return": fast_travel(int(data.stage))
		"exit": advance_stage()
		"clue": show_story(str(data.get("story","")))
		"npc":
			if activities.request_npc(data): return
			var activity: String = str(data.get("activity", ""))
			if not activity.is_empty():
				if activity == "shop": open_panel("shop")
				else: activities.open(activity, data)
				return
			var story = str(data.get("story",""))
			if State.stage == 1 and str(data.get("id","")) == "n01" and 3 in State.cleared: story = "town_return"
			if not story.is_empty():
				show_story(story, func():
					var flag: String = str(data.get("visit_flag", ""))
					var newly_visited: bool = not flag.is_empty() and not State.flags.get(flag,false)
					if newly_visited: State.flags[flag] = true
					world._check_objectives()
					world.paused = false
					if newly_visited: save_game(0,false),world.npc_position(data))
		"camp":
			save_game(0,false)
			open_panel("camp")
		"chest": toast(t("treasure_found"))

func advance_stage() -> void:
	if transition_busy: return
	# The forest is a saved phase of stage zero, not a renumbered campaign map.
	# Do not award stage completion or unlock town until its exit is reached.
	if State.stage == 0 and not State.flags.get("royal_forest", false):
		transition_busy = true
		world.paused = true
		world.sync_to_state()
		show_story("m00_outro", func():
			State.flags["royal_forest"] = true
			transition_busy = false
			start_game(0, true))
		return
	if State.stage == 1 and State.respite_next() > 0:
		var destination: int = State.respite_next()
		world.sync_to_state()
		start_game(destination,true)
		return
	transition_busy=true
	world.paused=true
	world.sync_to_state()
	State.complete_stage(State.stage)
	var map = world.map_data
	show_story(str(map.get("outro","")),func():
		transition_busy=false
		if State.stage==DB.maps.size()-1:
			finish_campaign()
		else:
			var completed: int = State.stage
			var next=completed+1
			if State.schedule_respite(completed):
				start_game(1,false)
				world.heal_party()
				show_story("respite_"+str(completed),func():
					world.paused=false
					save_game(0,false), Vector2(530,540))
				return
			start_game(next,true)
			world.heal_party()
			if not is_instance_valid(dialogue_layer): save_game(0,false))

func replay_story(key: String) -> void:
	close_panel()
	show_story(key,func(): open_panel("chronicle"))
	dialogue_data = dialogue_data.duplicate(true)
	dialogue_data.erase("choice")

func show_story(key: String, after: Callable = Callable(), focus: Vector2 = Vector2.INF) -> void:
	var data = DB.story(key)
	if data.is_empty():
		if after.is_valid(): after.call()
		else: world.paused=false
		return
	dialogue_focus=focus
	dialogue_data=data
	dialogue=data.get("lines",[]).duplicate(true)
	dialogue_index=0
	dialogue_finish=after
	if is_instance_valid(world): world.paused=true
	_draw_dialogue()

func _draw_dialogue() -> void:
	if is_instance_valid(hud): hud.hide()
	if is_instance_valid(dialogue_layer):
		root.remove_child(dialogue_layer)
		dialogue_layer.queue_free()
	dialogue_layer=Control.new()
	VeilUI.fill(dialogue_layer)
	root.add_child(dialogue_layer)
	var cinematic: String = str(dialogue[dialogue_index].get("cinematic", "")) if dialogue_index < dialogue.size() else ""
	var cinematic_paths: Dictionary = {"skyfall":"skyfall", "royal_summoning":"royal_summoning", "forest_arrival":"forest_arrival", "court_breach":"court_breach"}
	if cinematic_paths.has(cinematic):
		var scene := TextureRect.new()
		scene.texture = load("res://art/vertical/environment/" + str(cinematic_paths[cinematic]) + ".png")
		scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		scene.size = Vector2(1200, 675)
		scene.position = Vector2(-24, -14)
		scene.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dialogue_layer.add_child(scene)
		var pan := scene.create_tween()
		pan.tween_property(scene, "position", Vector2(-4, -4), 7.0)
		for y in [0, 620]:
			var letterbox := ColorRect.new()
			letterbox.position = Vector2(0, y)
			letterbox.size = Vector2(1152, 28)
			letterbox.color = Color("050b13")
			letterbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dialogue_layer.add_child(letterbox)
	elif dialogue_index < dialogue.size() and is_instance_valid(world) and (dialogue_focus.is_finite() or dialogue[dialogue_index].has("focus")):
		if story_camera_tween != null: story_camera_tween.kill()
		var focus: Vector2 = dialogue_focus
		if dialogue[dialogue_index].has("focus"):
			var point: Array = dialogue[dialogue_index].focus
			focus = Vector2(point[0],point[1])
		story_camera_tween = world.create_tween()
		story_camera_tween.tween_property(world.camera, "position", focus, 0.6)
	var dim=ColorRect.new()
	VeilUI.fill(dim)
	dim.color=Color(0.01,0.025,0.05,0.3)
	dialogue_layer.add_child(dim)
	var panel=PanelContainer.new()
	panel.position=Vector2(340,410)
	panel.size=Vector2(748,214)
	panel.add_theme_stylebox_override("panel",VeilUI.panel_style())
	dialogue_layer.add_child(panel)
	var row=HBoxContainer.new()
	row.add_theme_constant_override("separation",20)
	panel.add_child(row)
	if dialogue_index < dialogue.size():
		var line = dialogue[dialogue_index]
		var speaker=str(line.get("speaker","narrator"))
		var definition=DB.character(speaker)
		if not definition.is_empty():
			if PortraitLibrary.is_illustrated(definition):
				var illustration=TextureRect.new()
				illustration.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
				illustration.texture=PortraitLibrary.full_texture(definition)
				illustration.position=Vector2(34,158)
				illustration.size=Vector2(296,464)
				illustration.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				illustration.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
				illustration.mouse_filter=Control.MOUSE_FILTER_IGNORE
				dialogue_layer.add_child(illustration)
			else:
				var portrait=VeilUI.framed_portrait(definition,156)
				portrait.position=Vector2(82,422)
				dialogue_layer.add_child(portrait)
		else:
			var seal=TextureRect.new()
			seal.texture=VeilUI.action_icon("ultimate")
			seal.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			seal.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			seal.size=Vector2(120,120)
			seal.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
			seal.mouse_filter=Control.MOUSE_FILTER_IGNORE
			seal.position=Vector2(104,456)
			dialogue_layer.add_child(seal)
		var name_plate=PanelContainer.new()
		name_plate.position=Vector2(364,354)
		name_plate.custom_minimum_size=Vector2(320,56)
		name_plate.add_theme_stylebox_override("panel",VeilUI.card_style())
		name_plate.add_child(VeilUI.heading(tx(line.get("display_name",definition.get("name",t("narrator")))),22))
		dialogue_layer.add_child(name_plate)
		var body=VBoxContainer.new()
		body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(body)
		var text=VeilUI.prose(tx(line.get("text","")),20)
		text.size_flags_vertical=Control.SIZE_EXPAND_FILL
		body.add_child(text)
		var footer=HBoxContainer.new()
		body.add_child(footer)
		var next_hint = activities.local_text("Tap Next to continue", "แตะถัดไปเพื่ออ่านต่อ") if DisplayServer.is_touchscreen_available() or bool(config.touch) else activities.local_text("Space / Enter", "Space / Enter · อ่านต่อ")
		var counter=VeilUI.label(next_hint,14,VeilUI.MUTED)
		counter.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		footer.add_child(counter)
		var next=VeilUI.button(t("next")+"  →",advance_dialogue,135)
		footer.add_child(next)
		next.grab_focus()
	elif dialogue_data.has("choice"):
		panel.position=Vector2(160,350)
		panel.size=Vector2(832,276)
		var body=VBoxContainer.new()
		body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(body)
		var choice=dialogue_data.choice
		body.add_child(VeilUI.prose(tx(choice.get("prompt","")),20,VeilUI.GOLD))
		for option in choice.get("options",[]):
			body.add_child(VeilUI.button(tx(option.get("text","")),func():
				State.flags[str(option.get("flag",option.get("id","")))]=true
				if str(option.get("id","")).begins_with("ending_"):
					State.ending_choice=str(option.id).trim_prefix("ending_")
				_end_dialogue()))
	else: _end_dialogue()

func advance_dialogue() -> void:
	if dialogue_index >= dialogue.size(): return
	dialogue_index+=1
	_draw_dialogue()

func _end_dialogue() -> void:
	if story_camera_tween != null: story_camera_tween.kill()
	if is_instance_valid(world) and world.active_actor() != null:
		world.camera.position = world.active_actor().position
	if is_instance_valid(dialogue_layer):
		root.remove_child(dialogue_layer)
		dialogue_layer.queue_free()
	dialogue_layer=null
	if is_instance_valid(hud): hud.show()
	var callback=dialogue_finish
	dialogue_finish=Callable()
	if callback.is_valid(): callback.call()
	elif is_instance_valid(world): world.paused=false

func finish_campaign() -> void:
	State.flags["campaign_complete"]=true
	var choice=str(State.ending_choice).trim_prefix("ending_")
	if choice not in ["restore","open"]: choice="restore"
	State.ending_choice=choice
	save_game(0,false)
	Sound.play_music("ending")
	show_story("ending_"+choice,func(): open_panel("ending"))

func open_panel(which: String) -> void:
	if is_instance_valid(dialogue_layer): return
	if is_instance_valid(overlay):
		root.remove_child(overlay)
		overlay.queue_free()
	panel_name=which
	if is_instance_valid(world):
		world.paused=true
		world.set_input_vector(Vector2.ZERO)
		joystick_id=-1
		touch_origin=Vector2.ZERO
		if is_instance_valid(joystick_pad): joystick_pad.queue_redraw()
		world.sync_to_state()
	overlay=Control.new()
	VeilUI.fill(overlay)
	root.add_child(overlay)
	var dim=ColorRect.new()
	VeilUI.fill(dim)
	dim.color=Color(0.01,0.025,0.04,0.85)
	overlay.add_child(dim)
	menus.render(which,overlay)
	_position_toast()
	if is_instance_valid(toast_label): root.move_child(toast_label,root.get_child_count()-1)

func close_panel() -> void:
	if is_instance_valid(overlay):
		root.remove_child(overlay)
		overlay.queue_free()
	overlay=null
	panel_name=""
	_position_toast()
	if is_instance_valid(world): world.paused=false

func refresh_party() -> void:
	if is_instance_valid(world):
		if world.has_method("refresh_party"): world.refresh_party()
		else: world.load_map(State.stage)
		world.paused=panel_name!=""
	_refresh_hud()

func _on_state_changed() -> void:
	pass

func _on_defeat() -> void:
	world.paused=true
	open_panel("defeat")

func recover() -> void:
	State.gold=maxi(0,State.gold-10)
	var stage=State.stage
	start_game(stage,false)
	world.heal_party()
	toast(t("recovered"))

func use_potion() -> void:
	if playing and is_instance_valid(world) and not world.paused:
		world.use_consumable("potion")

func save_game(slot: int, announce: bool = true) -> void:
	if not playing: return
	if save_pending.has(slot):
		queued_saves[slot] = announce or bool(queued_saves.get(slot,false))
		while save_pending.has(slot) or queued_saves.has(slot):
			await get_tree().process_frame
		return
	world.sync_to_state()
	if State.save_slot(slot):
		var durable = true
		if OS.has_feature("web"):
			save_pending[slot] = true
			save_results[slot] = false
			if announce: toast(t("save_pending"))
			durable = await State.await_browser_save(slot,30.0 if slot == 0 else 15.0)
			save_pending.erase(slot)
			save_results[slot] = durable
		if not durable: toast(t("save_failed"))
		elif announce: toast(t("saved"))
		if panel_name == "saves": open_panel("saves")
	elif announce: toast(t("save_failed"))
	if queued_saves.has(slot):
		var announce_queued = bool(queued_saves[slot])
		queued_saves.erase(slot)
		save_game(slot,announce_queued)

func load_game(slot: int) -> void:
	if State.load_slot(slot):
		config.language=State.language
		start_game(State.stage,false)
		if State.flags.get("campaign_complete",false) and State.stage==DB.maps.size()-1:
			Sound.play_music("ending")
			open_panel("ending")
		toast(t("loaded"))
	else: toast(t("load_failed"))

func fast_travel(stage: int) -> void:
	if not stage in State.cleared and stage!=State.unlocked_stage: return
	world.sync_to_state()
	start_game(stage,false)
	world.heal_party()
	save_game(0,false)

func toggle_language() -> void:
	State.language="en" if State.language=="th" else "th"
	config.language=State.language
	_save_config()
	if playing:
		var current=panel_name
		if is_instance_valid(hud):
			root.remove_child(hud)
			hud.queue_free()
		_build_hud()
		if current!="": open_panel(current)
	else: show_title()

func _load_config() -> void:
	var cfg=ConfigFile.new()
	if cfg.load("user://settings.cfg")==OK:
		for key in config: config[key]=cfg.get_value("settings",key,config[key])
	State.language=str(config.language)
	State.difficulty=str(config.difficulty)

func _save_config() -> void:
	var cfg=ConfigFile.new()
	for key in config: cfg.set_value("settings",key,config[key])
	cfg.save("user://settings.cfg")

func _create_toast() -> void:
	toast_label=VeilUI.label("",16,VeilUI.GOLD)
	toast_label.size=Vector2(512,50)
	toast_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	toast_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	toast_label.add_theme_constant_override("shadow_offset_x",1)
	toast_label.add_theme_constant_override("shadow_offset_y",2)
	root.add_child(toast_label)
	_position_toast()

func _position_toast() -> void:
	if not is_instance_valid(toast_label): return
	# Menu notices use the header gap; combat notices sit below navigation,
	# outside the boss banner and central fighting lane.
	toast_label.position=Vector2(322,96) if panel_name!="" else (Vector2(322,158) if playing else Vector2(450,90))

func toast(text: String) -> void:
	if not is_instance_valid(toast_label): return
	_position_toast()
	toast_label.text=text
	toast_label.modulate.a=1
	toast_timer=3.5

func _update_qa_snapshot() -> void:
	# Read-only observability, enabled explicitly for QA; no gameplay shortcuts.
	if not qa_enabled or not OS.has_feature("web"): return
	var snapshot = {"playing":playing,"stage":State.stage,"language":State.language,"panel":panel_name,"dialogue":is_instance_valid(dialogue_layer),"dialogue_index":dialogue_index,"dialogue_size":dialogue.size(),"flags":State.flags,"party":State.party}
	snapshot["pending_saves"] = save_pending.keys()
	snapshot["save_results"] = save_results
	snapshot["selected_hero"] = selected_hero
	snapshot["activity"] = {"mode":activities.mode,"angles":activities.angles,"beats":activities.beats,"clock":activities.clock}
	snapshot["recruited"] = State.recruited
	snapshot["lantern_step"] = State.lantern_step()
	snapshot["inventory"] = State.inventory
	snapshot["respite_next"] = State.respite_next()
	snapshot["actor_texture_bytes"] = VisualAnimation.resident_texture_bytes()
	snapshot["combat_atlases"] = VisualAnimation._textures.keys()
	if is_instance_valid(world):
		snapshot["relay_time"] = world.relay_time
		snapshot["map_intro"] = str(world.map_data.get("intro",""))
	snapshot["cinematic"] = str(dialogue[dialogue_index].get("cinematic","")) if is_instance_valid(dialogue_layer) and dialogue_index < dialogue.size() else ""
	var hud_groups=[]
	for group in hud_obstructions:
		if is_instance_valid(group):
			var bounds=group.get_global_rect()
			hud_groups.append({"rect":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"opacity":group.modulate.a})
	snapshot["hud_groups"]=hud_groups
	snapshot["save_error"] = State.last_error
	var save_files=[]
	for slot in State._browser_save_payloads:
		var path=ProjectSettings.globalize_path(State._slot_path(slot))
		var expected=str(State._browser_save_payloads[slot])
		var generation=int(State._browser_save_generations.get(slot,0))
		if not qa_save_file_cache.has(slot) or qa_save_file_cache[slot].generation!=generation:
			var actual=FileAccess.get_file_as_string(path)
			qa_save_file_cache[slot]={"generation":generation,"slot":slot,"path":path,"length":actual.length(),"sha256":actual.sha256_text(),"expected_length":expected.length(),"expected_sha256":expected.sha256_text()}
		save_files.append(qa_save_file_cache[slot])
	snapshot["save_files"]=save_files
	snapshot["save_verify"] = JavaScriptBridge.eval("JSON.stringify(window.AstralVeilPersistence?.diagnostic || {})",true)
	if is_instance_valid(dialogue_layer) and dialogue_index < dialogue.size():
		snapshot["dialogue_speaker"] = str(dialogue[dialogue_index].get("speaker","narrator"))
	if is_instance_valid(joystick_pad):
		var pad_rect=joystick_pad.get_global_rect()
		snapshot["touch_pad_rect"]=[pad_rect.position.x,pad_rect.position.y,pad_rect.size.x,pad_rect.size.y]
	if is_instance_valid(world):
		snapshot["paused"] = world.paused
		snapshot["enemies"] = world.enemies.size()
		var enemy_health = 0.0
		for foe in world.enemies: enemy_health += foe.hp
		snapshot["enemy_health"] = enemy_health
		snapshot["ready"] = world.ready_emitted
		var actor = world.active_actor()
		if actor:
			snapshot["actor"] = {"id":actor.id,"pos":[actor.position.x,actor.position.y],"hp":actor.hp,"mp":actor.mp,"cooldown":actor.skill_cooldown,"dodge":actor.dodge_cooldown,"ultimate":actor.ultimate_charge}
		var visuals = []
		for unit in world.actors + world.enemies:
			unit.set_meta("qa_track_visual",true)
			var frame = VisualAnimation.frame_for_actor(unit)
			if frame.is_empty(): continue
			var atlas = VisualAnimation.atlas_texture(str(frame.id))
			var region: Rect2 = frame.region
			visuals.append({"id":unit.id,"pos":[unit.position.x,unit.position.y],"enemy_kind":unit.enemy_kind,"boss":unit.boss,"engaged":unit.boss_engaged,"hp":unit.hp,"max_hp":unit.max_hp,"guard_active":unit.enemy and world.guard_active(unit),"guard_open":unit.guard_open,"recovery":unit.recovery,"pattern":unit.attack_pattern,"windup":unit.windup,"action":frame.action,"frame":frame.frame,"direction":frame.direction,"region":[region.position.x,region.position.y,region.size.x,region.size.y],"atlas_size":[atlas.get_width(),atlas.get_height()],"resource_path":atlas.resource_path,"drawn_actions":unit.get_meta("qa_drawn_actions",{})})
		snapshot["visual_actors"] = visuals
		var effect_kinds = []
		for effect in world.effects: effect_kinds.append(str(effect.kind))
		snapshot["effect_kinds"] = effect_kinds
		snapshot["effect_count"] = world.effects.size()
	var text_edits = []
	for edit in root.find_children("*","TextEdit",true,false):
		if edit.is_visible_in_tree():
			var rect = edit.get_global_rect()
			text_edits.append({"name":edit.name,"focused":edit.has_focus(),"text_length":edit.text.length(),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
	snapshot["text_edits"] = text_edits
	var textures = []
	for control in root.find_children("*","TextureRect",true,false):
		if control.is_visible_in_tree() and control.texture != null:
			var rect = control.get_global_rect()
			var path = control.texture.resource_path
			if control.texture is AtlasTexture: path = control.texture.atlas.resource_path
			textures.append({"resource_path":path,"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"size":[control.texture.get_width(),control.texture.get_height()],"filter":control.texture_filter})
	snapshot["texture_controls"] = textures
	snapshot["boss_banner"] = false
	for control in root.get_children():
		for child in control.get_children():
			if child is Widgets.BossBanner and child.is_visible_in_tree(): snapshot["boss_banner"] = true
	var buttons = []
	for button in root.find_children("*","Button",true,false):
		if button.is_visible_in_tree():
			var rect = button.get_global_rect()
			buttons.append({"text":button.text,"focused":button.has_focus(),"disabled":button.disabled,"action":str(button.get_meta("qa_action","")),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
	snapshot["buttons"] = buttons
	snapshot["ui_size"] = [root.size.x,root.size.y]
	JavaScriptBridge.eval("window.ASTRAL_QA=" + JSON.stringify(snapshot) + ";",true)
