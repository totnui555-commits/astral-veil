extends RefCounted
class_name FantasyWidgets
## Presentation-only controls. All actions use the existing world controller.

class ActionOrb extends Button:
	var emblem: Texture2D
	func _ready() -> void:
		for state in ["normal","hover","pressed","disabled","focus"]:
			add_theme_stylebox_override(state,StyleBoxEmpty.new())
		for state in ["font_color","font_hover_color","font_pressed_color","font_disabled_color","font_focus_color"]:
			add_theme_color_override(state,Color.TRANSPARENT)
		mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		clip_text=true
		custom_minimum_size=Vector2(70,76)
	var cooldown_fraction = 0.0
	var caption = ""
	var action_kind = ""
	var unavailable = false
	var show_shortcut = true
	func _draw() -> void:
		var radius = minf(size.x/2-4,(size.y-24)/2)
		var center = Vector2(size.x/2,radius+3)
		var bright = is_hovered() or has_focus()
		var accent = {"attack":Color("ebcf97"),"heavy":Color("e9a487"),"skill":Color("7de1d5"),"ultimate":Color("eec66a"),"dodge":Color("b2bdeb")}.get(action_kind,VeilUI.TEAL)
		var cooling = cooldown_fraction > 0.001
		draw_circle(center+Vector2(0,4),radius+3,Color("00000080"))
		draw_circle(center,radius,Color("0b1b29f5"))
		draw_arc(center,radius,-PI/2,TAU-PI/2,64,accent if not unavailable else Color("64747a"),2,true)
		if emblem != null:
			var extent = Vector2.ONE*(radius-8)
			draw_texture_rect(emblem,Rect2(center-extent,extent*2),false,Color(1,1,1,.35) if cooling or unavailable else Color.WHITE)
		if cooling:
			draw_circle(center,radius-3,Color("07131c77"))
			draw_arc(center,radius,-PI/2,-PI/2+TAU*(1-cooldown_fraction),64,accent,3,true)
		if bright or is_pressed():
			draw_circle(center,radius-3,Color(0.6,0.9,0.85,.2 if is_pressed() else .08))
		var font = get_theme_font("font","Label")
		if cooling or (action_kind == "ultimate" and unavailable):
			draw_string(font,Vector2(0,center.y+8),text,HORIZONTAL_ALIGNMENT_CENTER,size.x,22,VeilUI.WHITE)
		var footer = caption if not caption.is_empty() else text
		var plate = Rect2(0,size.y-26,size.x,26)
		draw_style_box(VeilUI.surface(Color("091723f5"),Color("091723f5"),0,2),plate)
		draw_string(font,Vector2(0,size.y-7),footer,HORIZONTAL_ALIGNMENT_CENTER,size.x,15,VeilUI.WHITE)
		if show_shortcut:
			var shortcut = {"attack":"J","heavy":"K","skill":"Q","ultimate":"R","dodge":"Space"}.get(action_kind,{"potion":"H","interact":"E"}.get(str(get_meta("qa_action","")),""))
			var key_size = Vector2(38 if shortcut == "Space" else 24,20)
			var key_rect = Rect2(Vector2(size.x-key_size.x,0),key_size)
			draw_style_box(VeilUI.surface(Color("1d3342"),Color("63777a"),0,4),key_rect)
			draw_string(font,key_rect.position+Vector2(0,15),shortcut,HORIZONTAL_ALIGNMENT_CENTER,key_size.x,11,VeilUI.WHITE)

class InlayDivider extends Control:
	func _ready() -> void:
		custom_minimum_size.y = 10
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var x = size.x/2
		draw_line(Vector2(0,5),Vector2(x-13,5),Color("655e4c"),1,true)
		draw_line(Vector2(x+13,5),Vector2(size.x,5),Color("655e4c"),1,true)
		draw_colored_polygon(PackedVector2Array([Vector2(x,0),Vector2(x+5,5),Vector2(x,10),Vector2(x-5,5)]),VeilUI.GOLD)

class MiniMap extends Control:
	var world: Node2D
	var refresh=0.0
	func _process(delta: float) -> void:
		refresh-=delta
		if refresh<=0:
			refresh=0.12
			queue_redraw()
	func _draw() -> void:
		if not is_instance_valid(world): return
		var area=Rect2(4,4,size.x-8,size.y-8)
		draw_rect(area,Color("07161be8"))
		var ratio=area.size/Vector2(world.map_data.get("width",1600),world.map_data.get("height",1000))
		if VisualEnvironment.supports(world.map_data):
			var ground: Texture2D = VisualEnvironment.texture("res://art/vertical/environment/" + str(world.map_data.get("ground", "map_%d_ground.png" % int(world.map_data.id))))
			var portion: Rect2 = Rect2(area.position,Vector2(1600,1000)*ratio)
			draw_texture_rect(ground,portion,false,Color(0.55,0.65,0.60,1))
			if int(world.map_data.id) == 1:
				var district: Texture2D = VisualEnvironment.texture("res://art/vertical/environment/market_ground.png")
				if district: draw_texture_rect(district,Rect2(area.position+Vector2(1600,0)*ratio,Vector2(1600,1000)*ratio),false,Color(0.55,0.65,0.60,1))
		else:
			for obstacle in world.obstacles:
				draw_rect(Rect2(area.position+obstacle.position*ratio,obstacle.size*ratio),Color("53776b"))
		for npc in world.map_data.get("npcs",[]):
			var location: Vector2 = area.position+world.npc_position(npc)*ratio
			var request_target: bool = (str(npc.id)=="courier" and State.lantern_step()==0) or (str(npc.id)=="lantern_child" and State.lantern_step() in [2,3,4])
			draw_circle(location,3.3 if request_target else 2,VeilUI.TEAL if request_target else VeilUI.GOLD)
		for chest in world.map_data.get("chests",[]):
			if not State.flags.get("chest_"+str(chest.id),false):
				var location: Vector2 = area.position+Vector2(chest.pos[0],chest.pos[1])*ratio
				draw_rect(Rect2(location-Vector2(2,2),Vector2(4,4)),VeilUI.TEAL if str(chest.id)=="courier_case" and State.lantern_step()==1 else Color("e2b87d"))
		var return_gate: Dictionary = world.map_data.get("return_gate",{})
		if not return_gate.is_empty():
			var p: Vector2 = area.position+Vector2(return_gate.pos[0],return_gate.pos[1])*ratio
			draw_colored_polygon(PackedVector2Array([p+Vector2(-4,0),p+Vector2(3,-4),p+Vector2(3,4)]),VeilUI.TEAL)
		var exit_point: Array=world.map_data.get("exit",[1450,500])
		var gate=area.position+Vector2(exit_point[0],exit_point[1])*ratio
		draw_colored_polygon(PackedVector2Array([gate+Vector2(0,-4),gate+Vector2(4,0),gate+Vector2(0,4),gate+Vector2(-4,0)]),VeilUI.GOLD)
		for sigil in world.map_data.get("sigils",[]):
			var p=area.position+Vector2(sigil[0],sigil[1])*ratio
			draw_arc(p,2,0,TAU,8,Color("b9a5ed"),1)
		for enemy in world.enemies:
			if is_instance_valid(enemy) and not enemy.defeated:
				draw_circle(area.position+enemy.position*ratio,3 if enemy.boss else 1.6,VeilUI.RED)
		for actor in world.actors:
			if is_instance_valid(actor) and not actor.defeated:
				draw_circle(area.position+actor.position*ratio,2.6 if actor.active else 1.5,Color("f5f0c9") if actor.active else VeilUI.TEAL)
		draw_rect(area,Color("b29b72"),false,1)

class BossBanner extends Control:
	var world: Node2D
	var boss_actor: Node2D
	func _process(_delta: float) -> void:
		boss_actor=null
		if is_instance_valid(world):
			for actor in world.enemies:
				if actor.boss and actor.boss_engaged and not actor.defeated:
					boss_actor=actor
					break
		visible=boss_actor!=null
		queue_redraw()
	func _draw() -> void:
		if not is_instance_valid(boss_actor): return
		draw_style_box(VeilUI.card_style(),Rect2(Vector2.ZERO,size))
		var font=get_theme_font("font","Label")
		var name=DB.localized(boss_actor.definition.get("name",boss_actor.id))
		draw_string(font,Vector2(20,28),name,HORIZONTAL_ALIGNMENT_CENTER,size.x-40,17,VeilUI.GOLD)
		var bar=Rect2(24,38,size.x-48,9)
		draw_rect(bar,Color("071217"))
		draw_rect(Rect2(bar.position,Vector2(bar.size.x*clampf(boss_actor.hp/boss_actor.max_hp,0,1),9)),Color("ce735f"))
		draw_line(bar.position+Vector2(0,1),bar.position+Vector2(bar.size.x*clampf(boss_actor.hp/boss_actor.max_hp,0,1),1),Color("f0c5a0"),1)
		for phase in range(1,boss_actor.phase_count):
			var x=bar.position.x+bar.size.x*float(phase)/boss_actor.phase_count
			draw_line(Vector2(x,38),Vector2(x,47),Color("132024"),2)
		var phase_text=("ระยะ " if State.language=="th" else "PHASE ")+str(boss_actor.boss_phase)+" / "+str(boss_actor.phase_count)
		draw_string(font,Vector2(12,64),phase_text,HORIZONTAL_ALIGNMENT_CENTER,size.x-24,11,VeilUI.MUTED)

static func action(text: String, icon: String, fn: Callable, action_id: String) -> Button:
	var button=ActionOrb.new()
	button.text=text
	button.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	button.emblem=VeilUI.action_icon(action_id)
	if button.emblem == null: button.emblem=VeilUI.texture("icon_"+icon)
	button.set_meta("qa_action",action_id)
	button.pressed.connect(func():
		var loop=Engine.get_main_loop()
		if loop is SceneTree:
			var sound=loop.root.get_node_or_null("Sound")
			if sound: sound.sfx("ui")
		fn.call())
	return button
