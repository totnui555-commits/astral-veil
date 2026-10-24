extends RefCounted

var app
var selected_item = "potion"
var item_filter = "all"
var save_text = ""

func _init(controller) -> void:
	app=controller

func render(which: String, parent: Control) -> void:
	var panel=PanelContainer.new()
	panel.position=Vector2(32,20)
	panel.size=Vector2(1088,608)
	panel.add_theme_stylebox_override("panel",VeilUI.panel_style())
	parent.add_child(panel)
	var body=VBoxContainer.new()
	body.add_theme_constant_override("separation",8)
	panel.add_child(body)
	var header=HBoxContainer.new()
	body.add_child(header)
	header.add_child(VeilUI.emblem(which if which in ["party","journal","map","settings"] else "save" if which in ["saves","save_io"] else "relic",34))
	var heading=VeilUI.heading(app.activities.local_text("City activities","กิจกรรมในเมือง") if which == "activity" else app.t(which),25,VeilUI.GOLD)
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	if app.playing:
		header.add_child(VeilUI.label(str(State.gold)+"  "+app.t("gold"),17,VeilUI.GOLD))
	header.add_child(VeilUI.button(app.t("close")+" ×",app.close_panel,105))
	if app.playing and which in ["party","inventory","journal","map","saves","settings","pause"]:
		var navigation = HBoxContainer.new()
		navigation.add_theme_constant_override("separation",6)
		body.add_child(navigation)
		for destination in ["party","inventory","journal","map","saves","settings"]:
			var target: String = destination
			var tab = VeilUI.button(app.t(target),func(): app.open_panel(target))
			tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tab.custom_minimum_size.y = 46
			tab.set_meta("qa_action","nav_"+target)
			VeilUI.selected(tab,target == which)
			navigation.add_child(tab)
	var separator=app.Widgets.InlayDivider.new()
	body.add_child(separator)
	var content=VBoxContainer.new()
	content.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(content)
	match which:
		"activity": app.activities.render(content)
		"party": party(content)
		"tactics": tactics(content)
		"inventory": inventory(content,false)
		"shop": inventory(content,true)
		"journal": journal(content)
		"chronicle": chronicle(content)
		"map": atlas(content)
		"settings": settings(content)
		"saves": saves(content)
		"save_io": save_io(content)
		"camp": camp(content)
		"craft": crafting(content)
		"ending": ending(content)
		"credits": credits(content)
		"defeat": defeat(content)
		_: pause(content)

func scroll(parent: Control) -> VBoxContainer:
	var s=ScrollContainer.new()
	s.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	s.size_flags_vertical=Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	s.follow_focus=true
	s.mouse_force_pass_scroll_events=true
	parent.add_child(s)
	var box=VBoxContainer.new()
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	s.add_child(box)
	return box

func refresh() -> void:
	app.refresh_party()
	app.open_panel(app.panel_name)

func party(parent: Control) -> void:
	if not app.selected_hero in State.recruited: app.selected_hero=str(State.party[0])
	var id=str(app.selected_hero)
	var definition=DB.character(id)
	var hero=State.hero(id)
	var stats=State.derived(id)
	var split=HBoxContainer.new()
	split.size_flags_vertical=Control.SIZE_EXPAND_FILL
	parent.add_child(split)
	# A large matching illustration is the focal point; the roster and all
	# functional status controls remain separately scrollable beside it.
	var showcase=VBoxContainer.new()
	showcase.custom_minimum_size.x=234
	split.add_child(showcase)
	var name_label=VeilUI.heading(app.tx(definition.name),23)
	name_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	showcase.add_child(name_label)
	showcase.add_child(VeilUI.prose(app.tx(definition.class_name),15,VeilUI.TEAL))
	var portrait_frame=PanelContainer.new()
	portrait_frame.add_theme_stylebox_override("panel",VeilUI.card_style())
	portrait_frame.size_flags_vertical=Control.SIZE_EXPAND_FILL
	showcase.add_child(portrait_frame)
	var illustration=TextureRect.new()
	illustration.texture=PortraitLibrary.full_texture(definition)
	illustration.custom_minimum_size=Vector2(202,258)
	illustration.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	illustration.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	illustration.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR if PortraitLibrary.is_illustrated(definition) else CanvasItem.TEXTURE_FILTER_NEAREST
	illustration.mouse_filter=Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_child(illustration)
	showcase.add_child(VeilUI.prose(app.tx(definition.get("role","")),14,VeilUI.MUTED))
	var roster=VBoxContainer.new()
	roster.custom_minimum_size.x=230
	split.add_child(roster)
	roster.add_child(VeilUI.label(app.t("reunited")+"  "+str(State.recruited.size())+" / 38",13,VeilUI.TEAL))
	var roster_navigation=HBoxContainer.new()
	roster.add_child(roster_navigation)
	var list=scroll(roster)
	var roster_scroll: ScrollContainer = list.get_parent()
	for direction in [-1,1]:
		var step=direction
		var navigation=VeilUI.button("↑" if step<0 else "↓",func(): roster_scroll.scroll_vertical+=step*156,100)
		navigation.set_meta("qa_action","roster_up" if step<0 else "roster_down")
		roster_navigation.add_child(navigation)
	var ordered: Array = DB.characters.duplicate()
	ordered.sort_custom(func(a,b):
		var a_tier = 0 if str(a.id) in State.party else 1 if str(a.id) in State.recruited else 2
		var b_tier = 0 if str(b.id) in State.party else 1 if str(b.id) in State.recruited else 2
		return a_tier < b_tier if a_tier != b_tier else str(a.id) < str(b.id))
	for entry in ordered:
		var target=str(entry.id)
		var recruited=target in State.recruited
		var prefix="✦ " if target in State.party else ""
		var b=VeilUI.button(prefix+app.tx(entry.name)+"\n"+app.tx(entry.class_name),func():
			app.selected_hero=target
			app.open_panel("party"),212)
		b.alignment=HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text=true
		b.disabled=not recruited
		b.icon=PortraitLibrary.texture(entry)
		b.expand_icon=true
		b.add_theme_constant_override("icon_max_width",34)
		b.add_theme_font_size_override("font_size",15)
		b.custom_minimum_size.y=68
		VeilUI.selected(b,target==id)
		list.add_child(b)
		b.set_meta("qa_action","hero_"+target)
		if target == id: roster_scroll.call_deferred("ensure_control_visible",b)
	var detail=scroll(split)
	var status=PanelContainer.new()
	detail.add_child(status)
	var status_body=VBoxContainer.new()
	status.add_child(status_body)
	var level=HBoxContainer.new()
	status_body.add_child(level)
	var level_label=VeilUI.heading(app.t("level")+" "+str(int(hero.level)),23)
	level_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	level.add_child(level_label)
	level.add_child(VeilUI.label(app.t("points")+" "+str(int(hero.points)),14,VeilUI.TEAL))
	status_body.add_child(VeilUI.label("HP %d   MP %d   ATK %d   DEF %d" % [stats.max_hp,stats.max_mp,stats.attack,stats.defense],14))
	status_body.add_child(VeilUI.bar(hero.get("xp",0),State.xp_required(int(hero.level)),VeilUI.GOLD,390,8))
	status_body.add_child(VeilUI.label("XP "+str(int(hero.get("xp",0)))+" / "+str(State.xp_required(int(hero.level))),12,VeilUI.MUTED))
	var positions=HBoxContainer.new()
	detail.add_child(positions)
	for index in range(3):
		var slot=index
		var deploy=VeilUI.button(app.t("deploy")+" "+str(index+1),func():
			if State.set_party(slot,id): refresh(),124)
		deploy.add_theme_font_size_override("font_size",13)
		VeilUI.selected(deploy,State.party[index]==id)
		positions.add_child(deploy)
	detail.add_child(VeilUI.button(app.activities.local_text("Wardrobe", "แต่งตัว"),func(): app.activities.open("wardrobe"),240))
	detail.add_child(VeilUI.prose(app.tx(definition.get("bio","")),15,VeilUI.MUTED))
	if int(hero.points) < 1:
		detail.add_child(VeilUI.prose(app.activities.local_text("Earn attribute points when you level up.","เลเวลเพิ่มแล้วจะได้รับแต้มพัฒนาความสามารถ"),14,VeilUI.MUTED))
	var stat_grid=GridContainer.new()
	stat_grid.columns=2
	detail.add_child(stat_grid)
	for stat in ["strength","dexterity","intelligence","vitality","agility","spirit"]:
		var attribute=stat
		var b=VeilUI.button(app.t(stat)+" "+str(int(hero.stats.get(stat,0)))+"  +",func():
			if State.allocate(id,attribute): refresh(),195)
		b.add_theme_font_size_override("font_size",14)
		b.disabled=int(hero.points)<1
		stat_grid.add_child(b)
	var skill_card=PanelContainer.new()
	detail.add_child(skill_card)
	var skill_body=VBoxContainer.new()
	skill_card.add_child(skill_body)
	skill_body.add_child(VeilUI.prose(app.tx(definition.skill_name)+" · "+app.t("rank")+" "+str(int(hero.get("skill_rank",1))),17,VeilUI.TEAL))
	skill_body.add_child(VeilUI.prose(app.tx(definition.get("skill_description",definition.get("role",""))),14,VeilUI.MUTED))
	var upgrade=VeilUI.button(app.t("upgrade_skill")+" · 2 "+app.t("points"),func():
		if State.upgrade_skill(id): refresh())
	upgrade.disabled=int(hero.points)<2 or int(hero.get("skill_rank",1))>=5
	detail.add_child(upgrade)
	detail.add_child(VeilUI.button(app.t("respec")+" · "+str(State.respec_cost(id)),func():
		if State.respec(id): refresh()))
	detail.add_child(VeilUI.heading(app.t("equipment"),20))
	for slot in ["weapon","armor","accessory","relic"]:
		var equipped=str(hero.get("equipment",{}).get(slot,""))
		var row=HBoxContainer.new()
		detail.add_child(row)
		row.add_child(VeilUI.emblem(slot,36))
		var l=VeilUI.prose(app.t(slot)+": "+app.tx(DB.item(equipped).get("name","—")),13)
		row.add_child(l)
		if equipped!="":
			var equipment_slot=slot
			row.add_child(VeilUI.button(app.t("unequip"),func():
				if State.unequip(id,equipment_slot): refresh(),90))
	detail.add_child(VeilUI.prose(app.tx(definition.get("relationship","")),14,VeilUI.MUTED))

func inventory(parent: Control, shop_mode: bool) -> void:
	var tabs=HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation",8)
	parent.add_child(tabs)
	for entry in ["all","weapon","armor","accessory","relic","consumable","material"]:
		var key=entry
		var filter_button=VeilUI.button(app.t(key),func():
			item_filter=key
			app.open_panel("shop" if shop_mode else "inventory"),112)
		filter_button.add_theme_font_size_override("font_size",14)
		VeilUI.selected(filter_button,item_filter==entry)
		tabs.add_child(filter_button)
	var split=HBoxContainer.new()
	split.size_flags_vertical=Control.SIZE_EXPAND_FILL
	parent.add_child(split)
	var left=VBoxContainer.new()
	left.custom_minimum_size.x=415
	split.add_child(left)
	var list=scroll(left)
	var available=[]
	for item in DB.items:
		if item_filter!="all" and str(item.get("kind",""))!=item_filter: continue
		if not shop_mode and int(State.inventory.get(item.id,0))<=0: continue
		if shop_mode and int(item.get("price",0))<=0: continue
		if shop_mode and item.get("quest_reward",false): continue
		available.append(item)
	available.sort_custom(func(a,b): return str(a.get("kind",""))+str(a.id)<str(b.get("kind",""))+str(b.id))
	for item in available:
		var id=str(item.id)
		var suffix="  ·  "+str(int(item.get("price",0)))+" G" if shop_mode else "  ×"+str(int(State.inventory.get(id,0)))
		var b=VeilUI.button(app.tx(item.name)+suffix,func():
			selected_item=id
			app.open_panel("shop" if shop_mode else "inventory"),395)
		b.alignment=HORIZONTAL_ALIGNMENT_LEFT
		b.icon=VeilUI.texture("icon_"+str(item.get("kind","material")))
		b.expand_icon=true
		b.add_theme_constant_override("icon_max_width",38)
		b.custom_minimum_size.y=60
		b.add_theme_font_size_override("font_size",14)
		VeilUI.selected(b,id==selected_item)
		b.add_theme_color_override("font_color",rarity_color(str(item.get("rarity","common"))))
		list.add_child(b)
	if available.is_empty():
		list.add_child(VeilUI.prose(app.t("empty_inventory")))
		return
	var item=DB.item(selected_item)
	if item.is_empty() or not item in available:
		item=available[0]
		selected_item=str(item.id)
	var id=str(item.id)
	var detail=scroll(split)
	var item_header=HBoxContainer.new()
	detail.add_child(item_header)
	item_header.add_child(VeilUI.emblem(str(item.get("kind","material")),78))
	var item_title=VeilUI.heading(app.tx(item.name),25,rarity_color(str(item.get("rarity","common"))))
	item_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	item_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	item_header.add_child(item_title)
	detail.add_child(VeilUI.label(app.t(str(item.get("kind","")))+"  ·  "+app.t(str(item.get("rarity","common"))),16,VeilUI.MUTED))
	detail.add_child(VeilUI.prose(app.tx(item.get("description","")),17))
	for stat in item.get("stats",{}):
		detail.add_child(VeilUI.label(app.t(stat)+"  +"+str(item.stats[stat]),18,VeilUI.TEAL))
	if item.get("kind","")=="consumable":
		detail.add_child(VeilUI.label(app.t(str(item.get("effect","heal")))+"  +"+str(item.get("value",0)),18,VeilUI.TEAL))
	detail.add_child(VeilUI.label(app.t("owned")+": "+str(int(State.inventory.get(id,0))),16,VeilUI.MUTED))
	if shop_mode:
		var buy=VeilUI.button(app.t("buy")+"  ·  "+str(item.price)+" G",func():
			if State.buy(id): app.open_panel("shop"),280)
		buy.disabled=State.gold<int(item.price)
		detail.add_child(buy)
	else:
		if str(item.get("kind","")) in ["weapon","armor","accessory","relic"]:
			detail.add_child(VeilUI.label(app.t("equip_to"),16,VeilUI.GOLD))
			for hero_id in State.party:
				var target=str(hero_id)
				var stats=State.derived(target)
				var equipped=str(State.hero(target).equipment.get(str(item.kind),""))
				detail.add_child(VeilUI.prose(app.tx(DB.character(target).name)+" · "+app.tx(DB.item(equipped).get("name","—")),14,VeilUI.MUTED))
				var differences: PackedStringArray = []
				var previous: Dictionary = DB.item(equipped).get("stats",{})
				for attribute in item.get("stats",{}):
					var difference: float = float(item.stats[attribute]) - float(previous.get(attribute,0))
					differences.append(app.t(attribute)+" %+.1f" % difference)
				detail.add_child(VeilUI.prose(" · ".join(differences),13,VeilUI.TEAL))
				detail.add_child(VeilUI.button(app.t("equip")+" → "+app.tx(DB.character(target).name),func():
					if State.equip(target,id): refresh()))
		elif str(item.get("kind",""))=="consumable":
			detail.add_child(VeilUI.button(app.t("use"),func():
				app.world.use_consumable(id)
				app.open_panel("inventory"),280))
	var sell=VeilUI.button(app.t("sell")+" · "+str(maxi(1,int(item.get("price",0))/2))+" G",func():
		if State.sell(id): app.open_panel("shop" if shop_mode else "inventory"),280)
	sell.disabled=int(State.inventory.get(id,0))<1
	detail.add_child(sell)
	if item.has("recipe"):
		detail.add_child(VeilUI.prose(app.t("craft_at_camp"),14,VeilUI.MUTED))

func rarity_color(rarity: String) -> Color:
	match rarity.to_lower():
		"uncommon": return Color("91c793")
		"rare": return Color("82bde3")
		"epic": return Color("b2a2e9")
		"legendary": return Color("e6bb72")
		"ancient": return Color("79ddd0")
	return VeilUI.WHITE

func journal(parent: Control) -> void:
	parent.add_child(VeilUI.prose(app.activities.local_text("Lungers: dodge sideways, punish the landing. Guards: flank / K / third J hit. Menders: interrupt the violet tether before it heals.", "ตัวพุ่ง: หลบด้านข้าง แล้วสวนตอนลงพื้น · ตัวเกราะ: อ้อม / K / J ครั้งที่ 3 · ผู้เยียวยา: ขัดสายร่ายสีม่วงก่อนฟื้นพลัง"),14,VeilUI.MUTED))
	parent.add_child(VeilUI.button(app.t("chronicle"),func(): app.open_panel("chronicle"),400))
	parent.add_child(VeilUI.prose(app.world.objective_text(),21,VeilUI.GOLD))
	var list=scroll(parent)
	app.activities.request_journal(list)
	for quest in DB.quests:
		if int(quest.get("unlock_stage",0))>State.unlocked_stage: continue
		var id=str(quest.id)
		var progress=State.quests.get(id,{})
		if not progress is Dictionary: progress={"progress":progress}
		var count=int(progress.get("progress",progress.get("count",0)))
		var required=int(quest.get("required",1))
		var claimed=bool(progress.get("claimed",false))
		var card=PanelContainer.new()
		list.add_child(card)
		var body=VBoxContainer.new()
		card.add_child(body)
		var row=HBoxContainer.new()
		body.add_child(row)
		var title=VeilUI.label(("✓ " if claimed else "◇ ")+app.tx(quest.name),20,VeilUI.GOLD)
		title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(title)
		var claim=VeilUI.button(app.t("claimed") if claimed else app.t("claim") if count>=required else str(count)+" / "+str(required),func():
			if State.claim_quest(id): refresh(),132)
		claim.disabled=claimed or count<required
		row.add_child(claim)
		body.add_child(VeilUI.prose(app.tx(quest.description),16))
		body.add_child(VeilUI.label(str(quest.get("reward_gold",0))+" G  ·  "+str(quest.get("reward_xp",0))+" XP",14,VeilUI.TEAL))

func atlas(parent: Control) -> void:
	parent.add_child(VeilUI.prose(app.t("map_help"),16,VeilUI.MUTED))
	var grid=GridContainer.new()
	grid.columns=3
	var list=scroll(parent)
	list.add_child(grid)
	for map in DB.maps:
		var id=int(map.id)
		var unlocked=id<=State.unlocked_stage
		var card=PanelContainer.new()
		card.custom_minimum_size=Vector2(320,104)
		grid.add_child(card)
		var body=VBoxContainer.new()
		card.add_child(body)
		body.add_child(VeilUI.label(app.t("act")+" "+str(map.get("act",1))+"  /  "+str(id+1).pad_zeros(2),12,VeilUI.MUTED))
		var b=VeilUI.button(("✓ " if id in State.cleared else "◇ ")+app.tx(map.name),func(): app.fast_travel(id),286)
		b.disabled=not unlocked
		b.add_theme_font_size_override("font_size",16)
		body.add_child(b)

func settings(parent: Control) -> void:
	var box=scroll(parent)
	var language=HBoxContainer.new()
	box.add_child(language)
	language.add_child(VeilUI.label(app.t("language"),20,VeilUI.GOLD))
	language.add_child(VeilUI.button("ไทย / English",app.toggle_language,260))
	var difficulty=HBoxContainer.new()
	box.add_child(difficulty)
	difficulty.add_child(VeilUI.label(app.t("difficulty"),20,VeilUI.GOLD))
	for value in ["story","normal","hard"]:
		var mode=value
		var b=VeilUI.button(("✓ " if State.difficulty==mode else "")+app.t(mode),func():
			State.difficulty=mode
			app.config.difficulty=mode
			app._save_config()
			app.open_panel("settings"),190)
		difficulty.add_child(b)
	for channel in ["master","music","effects"]:
		var name=channel
		box.add_child(VeilUI.label(app.t(name),17,VeilUI.MUTED))
		var slider=HSlider.new()
		slider.min_value=0
		slider.max_value=1
		slider.step=0.05
		slider.value=float(app.config[name])
		slider.custom_minimum_size=Vector2(700,28)
		slider.value_changed.connect(func(value):
			app.config[name]=value
			Sound.set_levels(float(app.config.master),float(app.config.music),float(app.config.effects))
			app._save_config())
		box.add_child(slider)
	var options=HBoxContainer.new()
	box.add_child(options)
	options.add_child(VeilUI.button(app.t("touch_controls")+" · "+(app.t("on") if app.config.touch else app.t("off")),func():
		app.config.touch=not app.config.touch
		app._save_config()
		if app.playing:
			if is_instance_valid(app.hud):
				app.root.remove_child(app.hud)
				app.hud.queue_free()
			app._build_hud()
		app.open_panel("settings"),340))
	options.add_child(VeilUI.button(app.t("fullscreen"),func():
		var mode=DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN),260))
	box.add_child(VeilUI.prose(app.t("controls_full"),16,VeilUI.MUTED))
	box.add_child(VeilUI.prose(app.t("save_advice"),14,VeilUI.GOLD))

func saves(parent: Control) -> void:
	var list=scroll(parent)
	for slot in range(4):
		var index=slot
		var info=State.slot_info(slot)
		var panel=PanelContainer.new()
		list.add_child(panel)
		var row=HBoxContainer.new()
		panel.add_child(row)
		row.add_child(VeilUI.emblem("save",54))
		var description=VBoxContainer.new()
		description.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		description.add_theme_constant_override("separation",4)
		row.add_child(description)
		description.add_child(VeilUI.heading(app.t("autosave") if slot==0 else app.t("slot")+" "+str(slot),21))
		var summary=app.t("empty_slot")
		if not info.is_empty() and info.get("exists",true):
			var stage=int(info.get("stage",0))
			summary=app.tx(DB.map(stage).get("name",""))
		if app.save_pending.has(slot): summary=app.t("save_pending")
		description.add_child(VeilUI.prose(summary,15,VeilUI.TEAL if info.get("valid",false) else VeilUI.MUTED))
		if info.get("valid",false):
			description.add_child(VeilUI.label(app.t("level")+" "+str(info.get("level",1))+"  ·  "+str(int(float(info.get("play_seconds",0))/60))+" "+app.t("minutes")+"  ·  "+str(info.get("recruited",3))+" / 38",12,VeilUI.MUTED))
			description.add_child(VeilUI.label(str(info.get("saved_at","")),11,VeilUI.MUTED))
		var load_button=VeilUI.button(app.t("load"),func(): app.load_game(index),98)
		load_button.disabled=app.save_pending.has(slot) or info.is_empty() or not info.get("valid",false)
		row.add_child(load_button)
		if app.playing and slot>0:
			var save_button=VeilUI.button(app.t("save"),func():
				app.save_game(index)
				app.open_panel("saves"),98)
			save_button.disabled=app.save_pending.has(slot)
			row.add_child(save_button)
	list.add_child(VeilUI.button(app.t("backup_restore"),func(): app.open_panel("save_io"),400))
	list.add_child(VeilUI.prose(app.t("save_advice"),15,VeilUI.MUTED))

func save_io(parent: Control) -> void:
	parent.add_child(VeilUI.prose(app.t("backup_help"),16,VeilUI.MUTED))
	var text=TextEdit.new()
	text.custom_minimum_size=Vector2(990,250)
	text.size_flags_vertical=Control.SIZE_EXPAND_FILL
	text.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	text.text=save_text
	parent.add_child(text)
	var row=HBoxContainer.new()
	parent.add_child(row)
	var export_button=VeilUI.button(app.t("export_save"),func():
		app.world.sync_to_state()
		save_text=State.export_save()
		text.text=save_text
		if OS.has_feature("web"):
			JavaScriptBridge.download_buffer(save_text.to_utf8_buffer(),"astral-veil-save.json","application/json")
		else:
			var file=FileAccess.open("user://astral-veil-backup.json",FileAccess.WRITE)
			if file:
				file.store_string(save_text)
				app.toast(ProjectSettings.globalize_path("user://astral-veil-backup.json"))
		,310)
	export_button.disabled=not app.playing
	row.add_child(export_button)
	row.add_child(VeilUI.button(app.t("import_save"),func():
		save_text=text.text
		if State.import_save(save_text):
			app.start_game(State.stage,false)
			app.save_game(0,false)
			app.toast(app.t("loaded"))
		else: app.toast(app.t("load_failed")),310))
	row.add_child(VeilUI.button(app.t("back"),func(): app.open_panel("saves"),150))

func chronicle(parent: Control) -> void:
	parent.add_child(VeilUI.prose(app.activities.local_text("Replay illustrated story scenes. Replays do not change your save or choices.", "ย้อนดูฉากเล่าเรื่องแบบภาพประกอบ ไม่เปลี่ยนความคืบหน้าหรือตัวเลือกในเซฟ"),17,VeilUI.MUTED))
	var list=scroll(parent)
	for key in ["forest_arrival", "forest_departure"]:
		if State.flags.get("royal_forest",false) or State.unlocked_stage > 0:
			var story_key: String = key
			var button=VeilUI.button(app.activities.local_text("Prologue forest · ","ป่าในบทนำ · ")+app.activities.local_text("Arrival" if key == "forest_arrival" else "Departure","เมื่อมาถึง" if key == "forest_arrival" else "ก่อนออกเดินทาง"),func(): app.replay_story(story_key),960)
			button.set_meta("qa_action", "replay_"+story_key)
			list.add_child(button)
	for map in DB.maps:
		var stage: int = int(map.id)
		if stage > State.unlocked_stage and stage != 0: continue
		for kind in ["intro","outro"]:
			if kind == "outro" and stage not in State.cleared and stage != 0: continue
			var key: String = str(map.get(kind,""))
			if DB.story(key).is_empty(): continue
			var label: String = app.tx(map.name) + " · " + app.activities.local_text("Arrival" if kind == "intro" else "Departure", "เมื่อมาถึง" if kind == "intro" else "ก่อนออกเดินทาง")
			var button=VeilUI.button(label,func(): app.replay_story(key),960)
			button.set_meta("qa_action", "replay_"+key)
			list.add_child(button)
	for stage in [3,5,6,7,9,10]:
		if not State.flags.get("respite_seen_"+str(stage),false): continue
		var key: String = "respite_"+str(stage)
		list.add_child(VeilUI.button(app.activities.local_text("Homecoming · ","กลับบ้าน · ")+app.tx(DB.map(stage).name),func(): app.replay_story(key),960))

func pause(parent: Control) -> void:
	parent.add_child(VeilUI.prose(app.t("pause_help"),20,VeilUI.MUTED))
	var grid=GridContainer.new()
	grid.columns=3
	parent.add_child(grid)
	for which in ["party","inventory","journal","map","saves","settings"]:
		var key=which
		var navigation=VeilUI.button(app.t(key),func(): app.open_panel(key),326)
		var icon_key="relic" if key=="inventory" else "save" if key=="saves" else key
		navigation.icon=VeilUI.texture("icon_"+icon_key)
		navigation.expand_icon=true
		navigation.add_theme_constant_override("icon_max_width",36)
		navigation.custom_minimum_size.y=68
		grid.add_child(navigation)
	parent.add_child(VeilUI.button(app.t("chronicle"),func(): app.open_panel("chronicle"),400))
	parent.add_child(VeilUI.button(app.t("resume"),app.close_panel,400))
	parent.add_child(VeilUI.button(app.t("title"),func():
		await app.save_game(0)
		if OS.has_feature("web") and not app.save_results.get(0,false): return
		app.show_title(),400))

func camp(parent: Control) -> void:
	parent.add_child(VeilUI.prose(app.t("camp_help"),21,VeilUI.GOLD))
	var grid=GridContainer.new()
	grid.columns=3
	parent.add_child(grid)
	grid.add_child(VeilUI.button(app.t("rest"),func():
		app.world.heal_party()
		app.save_game(0,false)
		app.toast(app.t("rested")),326))
	for which in ["party","shop","craft","journal","saves"]:
		var key=which
		grid.add_child(VeilUI.button(app.t(key),func(): app.open_panel(key),326))
	parent.add_child(VeilUI.prose(app.t("camp_story"),18,VeilUI.MUTED))
	parent.add_child(VeilUI.button(app.t("chronicle"),func(): app.open_panel("chronicle"),400))
	parent.add_child(VeilUI.button(app.t("resume"),app.close_panel,400))

func crafting(parent: Control) -> void:
	parent.add_child(VeilUI.prose(app.t("craft_help"),17,VeilUI.MUTED))
	var list=scroll(parent)
	for item in DB.items:
		if not item.has("recipe") or item.recipe.is_empty(): continue
		var id=str(item.id)
		var card=PanelContainer.new()
		list.add_child(card)
		var row=HBoxContainer.new()
		card.add_child(row)
		row.add_child(VeilUI.emblem(str(item.get("kind","relic")),52))
		var info=VBoxContainer.new()
		info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(VeilUI.label(app.tx(item.name),19,rarity_color(str(item.rarity))))
		var requirements=[]
		var enough=true
		for material in item.recipe:
			var need=int(item.recipe[material])
			var count=int(State.inventory.get(material,0))
			requirements.append(app.tx(DB.item(material).get("name",material))+" "+str(count)+"/"+str(need))
			if count<need: enough=false
		info.add_child(VeilUI.prose(" · ".join(requirements),14,VeilUI.MUTED))
		var b=VeilUI.button(app.t("craft"),func():
			if State.craft(id): app.open_panel("craft"),150)
		b.disabled=not enough
		row.add_child(b)

func ending(parent: Control) -> void:
	parent.add_child(VeilUI.heading(app.t("ending_heading"),36,VeilUI.GOLD))
	parent.add_child(VeilUI.prose(app.t("ending_complete"),22))
	parent.add_child(VeilUI.prose(app.t("ending_postgame"),18,VeilUI.MUTED))
	parent.add_child(VeilUI.label(app.t("reunited")+" "+str(State.recruited.size())+" / 38  ·  "+str(int(State.play_seconds/60))+" "+app.t("minutes"),18,VeilUI.TEAL))
	var row=HBoxContainer.new()
	parent.add_child(row)
	row.add_child(VeilUI.button(app.t("credits"),func(): app.open_panel("credits"),320))
	row.add_child(VeilUI.button(app.t("explore_again"),func(): app.fast_travel(1),320))
	row.add_child(VeilUI.button(app.t("title"),app.show_title,320))

func credits(parent: Control) -> void:
	var list=scroll(parent)
	list.add_child(VeilUI.heading("ASTRAL VEIL",42,VeilUI.GOLD))
	list.add_child(VeilUI.label("THE SUMMONED THIRTY",16,VeilUI.TEAL))
	list.add_child(VeilUI.prose(app.t("credits_text"),20))
	var story=DB.story("credits")
	for line in story.get("lines",[]): list.add_child(VeilUI.prose(app.tx(line.get("text","")),17,VeilUI.MUTED))
	list.add_child(VeilUI.prose("Godot Engine · MIT License\nNoto Sans / Noto Sans Thai / Noto Serif · SIL Open Font License\nDejaVu Sans · Bitstream Vera / DejaVu font license\nOriginal code-generated pixel art and synthesized music.\nOpen source notices are bundled with the project.",16,VeilUI.MUTED))
	if app.playing:
		list.add_child(VeilUI.button(app.t("explore_again"),func(): app.fast_travel(1),350))
	else: list.add_child(VeilUI.button(app.t("back"),app.close_panel,350))

func defeat(parent: Control) -> void:
	parent.add_child(VeilUI.heading(app.t("defeat_heading"),36,VeilUI.RED))
	parent.add_child(VeilUI.prose(app.t("defeat_help"),22,VeilUI.MUTED))
	parent.add_child(VeilUI.button(app.t("recover"),app.recover,450))
	parent.add_child(VeilUI.button(app.t("load"),func(): app.open_panel("saves"),450))
	parent.add_child(VeilUI.button(app.t("settings"),func(): app.open_panel("settings"),450))

func tactics(parent: Control) -> void:
	if not is_instance_valid(app.world): return
	var world = app.world
	parent.add_child(VeilUI.heading(app.activities.local_text("Tactical command", "คำสั่งยุทธวิธี"),24))
	parent.add_child(VeilUI.prose(app.activities.local_text("Time is paused. Read the enemy, then commit one command. Break a guard or interrupt a cast to earn a 3-second relay; switch allies for mana and a stronger next hit.","เวลาหยุดอยู่ อ่านท่าศัตรูแล้วเลือกคำสั่ง ทำลายการ์ดหรือขัดจังหวะร่ายเพื่อเปิดช่วงส่งต่อ 3 วินาที สลับเพื่อนเพื่อฟื้นมานาและเพิ่มพลังโจมตีครั้งถัดไป"),17,VeilUI.MUTED))
	var list = scroll(parent)
	for foe in world.enemies:
		if foe.defeated or foe.position.distance_to(world.active_actor().position) > 520: continue
		var intent: String = app.activities.local_text("Recovering · attack now", "กำลังฟื้นตัว · เปิดช่องโจมตี") if foe.recovery > 0 else app.activities.local_text("Guarding · flank or heavy attack", "ตั้งการ์ด · อ้อมหลังหรือโจมตีหนัก") if world.guard_active(foe) else app.activities.local_text("Preparing attack · dodge / interrupt", "เตรียมโจมตี · หลบหรือขัดจังหวะ") if foe.windup > 0 else app.activities.local_text("Approaching", "กำลังเข้าประชิด")
		if foe.windup > 0 and foe.attack_pattern == 5: intent = app.activities.local_text("Mending · interrupt before the heal", "กำลังรักษา · ขัดจังหวะก่อนฟื้นเลือด")
		if world.seal_active(foe): intent = app.activities.local_text("Sealed · solve the rune with E", "มีผนึก · เข้าใกล้แล้วกด E แก้อักขระ")
		list.add_child(VeilUI.label(str(foe.enemy_kind).capitalize()+" · "+intent,16,VeilUI.GOLD))
	for i in range(world.actors.size()):
		var actor = world.actors[i]
		var index: int = i
		var row=HBoxContainer.new()
		list.add_child(row)
		row.add_child(VeilUI.framed_portrait(actor.definition,64))
		var info=VBoxContainer.new()
		info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(VeilUI.label(app.tx(actor.definition.name)+" · HP %d/%d · MP %d/%d" % [actor.hp,actor.max_hp,actor.mp,actor.max_mp],18))
		info.add_child(VeilUI.label(app.tx(actor.definition.skill_name)+" · %.1fs" % actor.skill_cooldown,15,VeilUI.MUTED))
		var swap=VeilUI.button(app.activities.local_text("Switch / relay", "สลับ / ส่งต่อ"),func():
			app.close_panel()
			world.switch_to(index),185)
		swap.disabled=actor.defeated or i==State.active_index
		swap.set_meta("qa_action","tactics_switch_"+str(i))
		row.add_child(swap)
		var cast=VeilUI.button(app.activities.local_text("Use skill", "ใช้สกิล"),func():
			app.close_panel()
			world.switch_to(index)
			world.skill(),145)
		cast.disabled=actor.defeated or actor.mp<18 or actor.skill_cooldown>0 or actor.statuses.has("stun") or actor.statuses.has("freeze")
		cast.set_meta("qa_action","tactics_cast_"+str(i))
		row.add_child(cast)
