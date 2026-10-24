extends RefCounted
class_name CityActivities
## Production activity UI. All rewards pass through persistent State flags/items.
var app
var mode: String = ""
var target: Dictionary = {}
var angles: Array[int] = [1, 3, 2]
var rotations: int = 0
var beats: int = 0
var clock: float = 0.0
var rhythm_label: Label
var description: Label
var rune_buttons: Array[Button] = []
const PATTERN: Array[int] = [0, 1, 2]
func _init(controller) -> void:
	app = controller
func local_text(en: String, th: String) -> String:
	return th if State.language == "th" else en

func request_npc(data: Dictionary) -> bool:
	if State.stage != 1: return false
	var id: String = str(data.get("id", ""))
	var step: int = State.lantern_step()
	if id == "lantern_child" and step in [3, 4]:
		open("lantern" if step == 3 else "reward", data)
		return true
	if id == "lantern_child" and step == 2:
		app.show_story("lantern_delivery", func():
			State.deliver_lantern_case()
			open("lantern", data)
			app.save_game(0, false), app.world.npc_position(data))
		return true
	var story: String = ""
	if id == "courier": story = "lantern_request" if step == 0 else "lantern_wait" if step == 1 else "lantern_found"
	if id == "lantern_child" and step == 5: story = "lantern_after"
	if id == "guard_east" and step == 5: story = "lantern_guard_after"
	if story.is_empty(): return false
	app.show_story(story, func():
		app.world.paused = false
		app.save_game(0, false), app.world.npc_position(data))
	return true

func request_journal(parent: Control) -> void:
	if State.unlocked_stage < 1: return
	var step: int = State.lantern_step()
	var card := PanelContainer.new()
	parent.add_child(card)
	var body := VBoxContainer.new()
	card.add_child(body)
	body.add_child(VeilUI.heading(("✓ " if step == 5 else "✧ ") + local_text("A Light to Come Home To", "แสงไฟรอคนกลับบ้าน"), 23))
	var en: Array[String] = ["Speak to Tavi, the courier in the eastern market. An optional town request.", "Find Tavi's metal case on the southern path of Verdant Road. The western gate returns to Hearthwell; M opens travel.", "Bring the case to Mira's lantern stall in the eastern market, west of Tavi.", "Help Mira align the lantern at her stall. No timer or penalty for trying again.", "Return to Mira and choose one relic: healing after a perfect dodge, or stronger damage against weakened enemies.", "Mira's lantern guides families home. Your chosen relic is in your inventory; equip it in the relic slot."]
	var th: Array[String] = ["คุยกับทาวี คนส่งจดหมายในตลาดตะวันออก · ภารกิจชาวเมืองที่เลือกทำได้", "หากล่องเหล็กของทาวีตามทางใต้ของเส้นทางพงไพร ประตูฝั่งตะวันตกกลับฮาร์ธเวลได้ หรือกด M เปิดแผนที่เดินทาง", "นำกล่องไปให้มีราที่ร้านโคมไฟในตลาดตะวันออก ทางตะวันตกของทาวี", "ช่วยมีราปรับแสงโคมที่ร้าน ไม่มีเวลาจำกัด ลองใหม่ได้โดยไม่เสียของ", "กลับไปหามีรา เลือกเครื่องรางหนึ่งชิ้น: ฟื้นเลือดเมื่อหลบตรงจังหวะ หรือเพิ่มความเสียหายต่อศัตรูที่อ่อนแอ", "โคมมีราช่วยนำครอบครัวกลับบ้านแล้ว เครื่องรางที่เลือกอยู่ในกระเป๋า สวมในช่องเครื่องรางได้"]
	body.add_child(VeilUI.prose(th[step] if State.language == "th" else en[step], 18))
	body.add_child(VeilUI.label(local_text("120 gold · 160 XP · choose one unique relic", "120 ทอง · 160 XP · เลือกเครื่องรางพิเศษหนึ่งชิ้น"), 15, VeilUI.TEAL))
	if step in [1, 2]: body.add_child(VeilUI.button(app.t("map"), func(): app.open_panel("map"), 180))

func rune_pattern() -> Array[int]:
	var lantern: Array[int] = [2, 0, 3]
	return lantern if mode == "lantern" else PATTERN

func music_period() -> float:
	return 3.6 if State.flags.get("music_assist", false) else 2.4

func open(kind: String, data: Dictionary = {}) -> void:
	mode = kind
	target = data.duplicate(true)
	angles = [1, 3, 2]
	rotations = 0
	beats = 0
	clock = 0.0
	app.open_panel("activity")
func render(parent: Control) -> void:
	var box: VBoxContainer = app.menus.scroll(parent)
	if mode == "reward":
		box.add_child(VeilUI.heading(local_text("Mira's keepsakes · choose one", "ของฝากจากมีรา · เลือกหนึ่งชิ้น"), 26))
		box.add_child(VeilUI.prose(local_text("The lantern holds steady. Mira offers one of the spare charms from her mother's workbench. Both include 120 gold and 160 XP. Equip your choice in Inventory → relic.", "แสงโคมนิ่งแล้ว มีราให้เลือกของจากโต๊ะช่างของแม่หนึ่งชิ้น พร้อม 120 ทองและ 160 XP สวมเครื่องรางได้ในกระเป๋า → ช่องเครื่องราง"), 19))
		for id in ["r09", "r10"]:
			var reward_id: String = id
			var item: Dictionary = DB.item(id)
			var card := PanelContainer.new()
			box.add_child(card)
			var content := VBoxContainer.new()
			card.add_child(content)
			content.add_child(VeilUI.heading(DB.localized(item.name), 23))
			content.add_child(VeilUI.prose(DB.localized(item.description), 18))
			content.add_child(VeilUI.label(local_text("+24 HP · +12 mana", "+24 HP · +12 มานา") if id == "r09" else local_text("+4 attack · +4 spell power", "+4 โจมตี · +4 พลังเวท"), 16, VeilUI.TEAL))
			content.add_child(VeilUI.button(local_text("Choose · ", "เลือก · ") + DB.localized(item.name), func():
				if State.claim_lantern_reward(reward_id):
					Sound.sfx("chest")
					app.close_panel()
					app.world.effect(Vector2(2330,430), "aegis", 105, Color("ffe6a9"), 1.2)
					app.toast(local_text("Relic received. Equip it in Inventory.", "ได้รับเครื่องรางแล้ว สวมได้ในกระเป๋า"))
					app.save_game(0, false)
				else: app.toast(local_text("Make room in your inventory first.", "เคลียร์ที่ในกระเป๋าก่อนนะ")), 340))
		return
	if mode == "wardrobe":
		box.add_child(VeilUI.heading(local_text("The Lantern Tailor", "ร้านตัดชุดโคมไฟ"), 26))
		box.add_child(VeilUI.prose(local_text("Festival clothes change appearance only. No stats are lost. Win the rune chest or the music game to unlock them.", "ชุดเทศกาลเปลี่ยนเฉพาะรูปลักษณ์ ค่าสถานะคงเดิม ปลดล็อกด้วยหีบอักขระหรือเกมดนตรี"), 18))
		for id in ["c02", "c03", "c05"]:
			if not id in State.recruited: continue
			var hero_id: String = id
			var row := HBoxContainer.new()
			box.add_child(row)
			row.add_child(VeilUI.framed_portrait(DB.character(id), 78))
			row.add_child(VeilUI.prose(DB.localized(DB.character(id).name), 20))
			var preview := TextureRect.new()
			var view := AtlasTexture.new()
			view.atlas = VisualAnimation.atlas_texture(VisualAnimation.costume_id(id))
			view.region = Rect2(0,0,128,128)
			preview.texture = view
			preview.custom_minimum_size = Vector2(86,86)
			preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			row.add_child(preview)
			for outfit in ["default", "festival"]:
				var chosen: String = outfit
				var button := VeilUI.button(local_text("Travel clothes", "ชุดเดินทาง") if outfit == "default" else local_text("Lantern festival", "ชุดเทศกาลโคมไฟ"), func():
					State.flags["outfit_" + hero_id] = chosen
					app.open_panel("activity")
					app.save_game(0, false), 190)
				button.disabled = outfit == "festival" and not State.flags.get("festival_unlocked", false)
				VeilUI.selected(button, str(State.flags.get("outfit_" + id, "default")) == outfit)
				row.add_child(button)
		return
	if mode == "music":
		box.add_child(VeilUI.heading(local_text("Lantern rehearsal", "ซ้อมเพลงใต้โคมไฟ"), 26))
		box.add_child(VeilUI.prose(local_text("Press Space or the button when the note reaches the bracket. Four good beats unlock the festival clothes. Standard timing resets the streak on a miss. Enable timing assist for a wider window and to keep your progress.", "กด Space หรือปุ่มเมื่อโน้ตเข้าช่องวงเล็บ ทำให้ตรงจังหวะ 4 ครั้งเพื่อรับชุดเทศกาล โหมดปกติจะเริ่มนับใหม่เมื่อพลาด เปิดตัวช่วยเพื่อเพิ่มช่วงจังหวะและเก็บความคืบหน้าไว้ได้"), 20))
		box.add_child(VeilUI.button(local_text("Timing assist: ", "ช่วยจับจังหวะ: ") + (app.t("on") if State.flags.get("music_assist", false) else app.t("off")), func():
			State.flags["music_assist"] = not State.flags.get("music_assist", false)
			clock = 0.0
			app.open_panel("activity")
			app.save_game(0, false), 290))
		if State.flags.get("music_assist", false): box.add_child(VeilUI.prose(local_text("Slower notes, wider bracket. Misses keep your progress. Same reward.", "โน้ตช้าลง ช่องกว้างขึ้น พลาดแล้วไม่หักจังหวะที่ทำได้ ได้รางวัลเท่ากัน"), 17, VeilUI.TEAL))
		rhythm_label = VeilUI.heading("", 30)
		box.add_child(rhythm_label)
		description = VeilUI.prose("", 20)
		box.add_child(description)
		box.add_child(VeilUI.button(local_text("Play note", "เล่นโน้ต"), hit_beat, 260))
		return
	box.add_child(VeilUI.heading(local_text("Celestial lock", "ผนึกฟากฟ้า"), 28))
	box.add_child(VeilUI.prose(local_text("The carving reads: rise to the sky, follow dawn, descend to earth. Turn the three seals to UP → RIGHT → DOWN. Each click turns one quarter clockwise. No time limit; you may leave and try again.", "จารึกว่า ‘เงยสู่ฟ้า ตามรุ่งอรุณ แล้วกลับลงดิน’ หมุนผนึกให้ชี้ ขึ้น → ขวา → ลง แต่ละครั้งหมุนตามเข็ม 90 องศา ไม่จับเวลา ออกแล้วลองใหม่ได้"), 20))
	if mode == "lantern":
		box.get_child(0).text = local_text("Mira's lantern · quiet the glass", "โคมมีรา · ปรับแก้วให้เงียบ")
		box.get_child(1).text = local_text("Three sketches mark the safe light: falling ember, rising wick, setting sun. Align DOWN → UP → LEFT. Each tap turns a quarter clockwise; the marks differ from a celestial lock. No timer.", "ฐานโคมมีภาพสามรูป: ถ่านร่วง ไส้เทียนลุก ดวงตะวันตก จัดให้ชี้ ลง → ขึ้น → ซ้าย แตะเพื่อหมุนตามเข็มครั้งละ 90 องศา เครื่องหมายต่างจากผนึกฟากฟ้า ไม่จับเวลา")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	box.add_child(row)
	rune_buttons.clear()
	for i in range(3):
		var index: int = i
		var b := VeilUI.button("", func(): rotate(index), 170)
		b.custom_minimum_size.y = 115
		b.add_theme_font_size_override("font_size", 28)
		row.add_child(b)
		rune_buttons.append(b)
	description = VeilUI.prose("", 19)
	box.add_child(description)
	box.add_child(VeilUI.button(local_text("Unseal", "ปลดผนึก"), submit, 250))
	refresh_runes()
func refresh_runes() -> void:
	for i in range(rune_buttons.size()):
		rune_buttons[i].text = str(i+1) + " · " + ["↑", "→", "↓", "←"][angles[i]]
	description.text = local_text("Turns: ", "หมุนแล้ว: ") + str(rotations)
func rotate(index: int) -> void:
	if app.panel_name != "activity" or mode not in ["chest", "seal", "lantern"]: return
	angles[index] = (angles[index] + 1) % 4
	rotations += 1
	Sound.sfx("ui")
	refresh_runes()
func submit() -> void:
	if app.panel_name != "activity" or mode not in ["chest", "seal", "lantern"]: return
	if angles != rune_pattern():
		description.text = local_text("The stars remain apart. Follow the inscription.", "ดวงดาวยังไม่เรียงกัน ลองอ่านจารึกอีกครั้ง")
		Sound.sfx("hurt")
		return
	if mode == "lantern":
		if not State.repair_lantern(): return
		Sound.sfx("quest")
		open("reward", target)
		app.save_game(0, false)
		return
	if mode == "chest":
		app.world.claim_chest(target)
		State.flags["festival_unlocked"] = true
	else:
		State.flags["seal_" + str(target.id)] = true
		for enemy in app.world.enemies:
			if enemy.id == str(target.id):
				enemy.windup = 0
				app.world.apply_status(enemy, "stun", 4.0)
				app.world.apply_status(enemy, "weakness", 8.0)
				app.world.effect(enemy.position, "skybreak", 110, Color("b4efff"), 1.1)
	Sound.sfx("quest")
	app.close_panel()
	app.toast(local_text("The seal breaks. Your next opening is here.", "ผนึกแตกแล้ว! ใช้จังหวะนี้ให้ดี"))
	app.save_game(0, false)
func tick(delta: float) -> void:
	if app.panel_name != "activity" or mode != "music" or not is_instance_valid(rhythm_label): return
	clock += delta
	var cursor: int = int(fposmod(clock, music_period()) / music_period() * 20)
	var assist: bool = State.flags.get("music_assist", false)
	var bar: String = ""
	for i in range(20): bar += "●" if i == cursor else "[" if i == (5 if assist else 7) else "]" if i == (16 if assist else 13) else "·"
	rhythm_label.text = bar
	description.text = local_text("Good beats: ", "ตรงจังหวะ: ") + str(beats) + " / 4"
func hit_beat() -> void:
	if app.panel_name != "activity" or mode != "music": return
	var phase: float = fposmod(clock, music_period()) / music_period()
	var assist: bool = State.flags.get("music_assist", false)
	if phase >= (0.25 if assist else 0.35) and phase <= (0.80 if assist else 0.68):
		beats += 1
		clock = 0.0
		Sound.sfx("quest")
	else:
		if not assist: beats = 0
		Sound.sfx("hurt")
	if beats >= 4:
		State.flags["festival_unlocked"] = true
		if not State.flags.get("music_reward", false):
			State.flags["music_reward"] = true
			State.add_item("potion", 3)
		app.close_panel()
		app.toast(local_text("Festival clothes unlocked! Visit the tailor.", "ปลดล็อกชุดเทศกาลแล้ว! แวะร้านช่างตัดชุดได้เลย"))
		app.save_game(0, false)
