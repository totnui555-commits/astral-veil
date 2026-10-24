extends SceneTree
## Run: godot --headless --path game --script tests/state_test.gd
## Exercises the same production DB/State autoloads used by the campaign.

var checks: int = 0
var failures: Array[String] = []
var db
var state


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)


func _same_campaign(before: Dictionary) -> bool:
	return JSON.stringify(before) == JSON.stringify(JSON.parse_string(state.export_save()).data)


func _invalid_save(base: Dictionary, label: String, mutate: Callable) -> void:
	var malformed: Dictionary = base.duplicate(true)
	mutate.call(malformed)
	var before: Dictionary = JSON.parse_string(state.export_save()).data
	_check(not state.import_save(JSON.stringify(malformed)), label + " rejected")
	_check(_same_campaign(before), label + " leaves campaign untouched")


func _run() -> void:
	db = root.get_node_or_null("DB")
	state = root.get_node_or_null("State")
	_check(db != null and state != null, "production autoloads instantiate")
	if db == null or state == null:
		_finish()
		return
	_check(db.errors.is_empty(), "all campaign JSON parses: " + str(db.errors))
	_check(db.characters.size() == 38, "38 playable character definitions")
	_check(db.maps.size() == 12, "12 connected campaign stages")
	_check(not db.items.is_empty() and not db.quests.is_empty(), "item and quest data is present")
	if not db.errors.is_empty() or db.characters.size() != 38 or db.items.is_empty():
		_finish()
		return
	state.save_directory = "user://automated_state_test_%d" % Time.get_ticks_usec()
	state.language = "en"
	state.new_game()
	_test_story_links()
	_check(state.party == ["c01", "c04", "c07"], "three initial heroes in party")
	_check(state.derived("c01").max_hp > 0, "derived stats are functional")
	_check(db.localized({"en": "Hello", "th": "สวัสดี"}) == "Hello", "English localization")
	state.language = "th"
	_check(db.localized({"en": "Hello", "th": "สวัสดี"}) == "สวัสดี", "Thai localization")
	state.language = "en"
	var original: String = state.export_save()
	_check(state.import_save(original), "fresh campaign export imports: " + state.last_error)
	var fresh: Dictionary = JSON.parse_string(original)
	_check(_same_campaign(fresh.data), "fresh save roundtrip preserves all fields")

	# XP carries across multiple levels; allocating and upgrading share one budget.
	var xp_to_three: int = state.xp_required(1) + state.xp_required(2)
	state.award_xp(xp_to_three + 17)
	for id in state.recruited:
		_check(int(state.hero(id).level) == 3 and int(state.hero(id).xp) == 17, "multi-level XP remainder " + str(id))
	_check(state.hero("c01").points == 6, "three stat points per level")
	var strength: int = int(state.hero("c01").stats.strength)
	var attack: float = float(state.derived("c01").attack)
	_check(state.allocate("c01", "strength"), "allocate strength")
	_check(state.hero("c01").stats.strength == strength + 1 and state.derived("c01").attack > attack, "allocated strength changes combat attack")
	_check(state.upgrade_skill("c01") and state.hero("c01").skill_rank == 2 and state.hero("c01").points == 3, "skill rank consumes two points")
	_check(not state.allocate("c01", "unknown"), "unknown stat rejected")
	state.gold = 1000
	var before_gold: int = state.gold
	var cost: int = state.respec_cost("c01")
	_check(state.respec("c01"), "respec succeeds")
	_check(state.gold == before_gold - cost and state.hero("c01").points == 6 and state.hero("c01").stats.strength == strength and state.hero("c01").skill_rank == 1, "respec restores exact budget and charges once")
	_check(not state.respec("c01"), "empty respec does not charge")

	_test_inventory()
	_test_quests()
	_test_validation()
	_test_campaign()
	await _test_persistence()
	_finish()


func _test_story_links() -> void:
	for stage_id in range(db.maps.size()):
		_check(not db.map(stage_id).is_empty() and int(db.map(stage_id).get("id", -1)) == stage_id, "numeric JSON stage ID resolves " + str(stage_id))
	for map_data in db.maps:
		for phase in ["intro", "outro"]:
			var key: String = str(map_data.get(phase, ""))
			var record: Dictionary = db.story(key)
			_check(not key.is_empty() and record.get("lines", []) is Array and not record.get("lines", []).is_empty(), "stage " + str(map_data.id) + " " + phase + " resolves to dialogue")
	for ending in ["ending_restore", "ending_open"]:
		var record: Dictionary = db.story(ending)
		_check(record.get("lines", []) is Array and not record.get("lines", []).is_empty(), "ending dialogue exists: " + ending)
	for key in db.stories:
		var record: Dictionary = db.story(str(key))
		for line in record.get("lines", []):
			var localized = line.get("text", {})
			_check(localized is Dictionary and not str(localized.get("en", "")).is_empty() and not str(localized.get("th", "")).is_empty(), "story line has both languages: " + str(key))


func _test_inventory() -> void:
	var weapons: Array[String] = []
	var craft_id: String = ""
	var consumable: String = ""
	for item_data in db.items:
		if item_data.get("kind", "") == "weapon":
			weapons.append(str(item_data.id))
		if not item_data.get("recipe", {}).is_empty() and craft_id.is_empty():
			craft_id = str(item_data.id)
		if item_data.get("kind", "") == "consumable" and consumable.is_empty():
			consumable = str(item_data.id)
	_check(weapons.size() >= 2, "at least two equippable weapons")
	if weapons.size() >= 2:
		var weapon_a: String = weapons[0]
		var weapon_b: String = weapons[1]
		state.inventory.clear()
		state.add_item(weapon_a)
		state.add_item(weapon_b)
		var base_attack: float = float(state.derived("c01").attack)
		var bonus: float = float(db.item(weapon_a).get("stats", {}).get("attack", 0))
		_check(state.equip("c01", weapon_a), "equip owned weapon")
		_check(not state.inventory.has(weapon_a) and is_equal_approx(float(state.derived("c01").attack), base_attack + bonus), "equipment transfers item and changes stats exactly")
		_check(not state.equip("c04", weapon_a), "equipped unique item cannot duplicate across heroes")
		_check(not state.sell(weapon_a), "equipped item cannot be sold")
		_check(state.equip("c01", weapon_b), "replace equipped weapon")
		_check(int(state.inventory.get(weapon_a, 0)) == 1 and not state.inventory.has(weapon_b), "replacement returns previous weapon exactly once")
		_check(state.unequip("c01", "weapon") and not state.unequip("c01", "weapon"), "unequip works once")
		_check(int(state.inventory.get(weapon_b, 0)) == 1, "unequip cannot duplicate item")
		state.gold = 100000
		var initial_gold: int = state.gold
		var initial_count: int = int(state.inventory.get(weapon_a, 0))
		_check(state.buy(weapon_a), "shop purchase succeeds")
		_check(state.gold == initial_gold - int(db.item(weapon_a).price) and int(state.inventory[weapon_a]) == initial_count + 1, "purchase charges exact price for one item")
		_check(state.sell(weapon_a) and int(state.inventory[weapon_a]) == initial_count, "sale removes exactly one item")
		_check(state.gold < initial_gold, "buy/sell cannot generate gold")
		state.gold = 0
		var frozen_inventory: Dictionary = state.inventory.duplicate(true)
		_check(not state.buy(weapon_a) and frozen_inventory == state.inventory, "insufficient gold has no side effects")
	_check(not consumable.is_empty(), "consumable definitions exist")
	if not consumable.is_empty():
		state.inventory.clear()
		state.add_item(consumable)
		_check(state.use_item(consumable) and not state.use_item(consumable), "consumable can be used once")
	_check(not craft_id.is_empty(), "crafting recipe exists")
	if not craft_id.is_empty():
		state.inventory.clear()
		_check(not state.craft(craft_id), "crafting without materials rejected")
		var recipe: Dictionary = db.item(craft_id).recipe
		for material in recipe:
			state.add_item(str(material), int(recipe[material]))
		_check(state.craft(craft_id), "craft using actual recipe")
		_check(int(state.inventory.get(craft_id, 0)) == 1 and not state.craft(craft_id), "craft consumes material once, no duplicate output")
	_check(not state.equip("c01", "not-an-item") and not state.buy("not-an-item") and not state.sell("not-an-item"), "unknown inventory IDs rejected")


func _test_quests() -> void:
	state.new_game()
	var tested: bool = false
	for record in db.quests:
		if int(record.get("unlock_stage", 0)) != 0:
			continue
		var id: String = str(record.id)
		_check(not state.claim_quest(id), "incomplete quest cannot claim " + id)
		var target: String = "test_target" if str(record.target) == "any" else str(record.target)
		state.record_event(str(record.type), target, int(record.required))
		_check(int(state.quests[id].progress) == int(record.required), "quest event reaches target " + id)
		var old_gold: int = state.gold
		_check(state.claim_quest(id), "completed quest can claim " + id)
		_check(state.gold == old_gold + int(record.reward_gold), "quest reward credited once " + id)
		var after_reward: String = state.export_save()
		_check(not state.claim_quest(id), "quest cannot claim twice " + id)
		_check(_same_campaign(JSON.parse_string(after_reward).data), "repeated claim has no effects " + id)
		tested = true
		break
	_check(tested, "at least one starting quest is playable")


func _test_validation() -> void:
	state.new_game()
	var base: Dictionary = JSON.parse_string(state.export_save())
	var before: Dictionary = base.data.duplicate(true)
	_check(not state.import_save("{broken"), "malformed JSON rejected")
	_check(_same_campaign(before), "malformed JSON cannot mutate state")
	_invalid_save(base, "future schema", func(v): v.version = 999)
	_invalid_save(base, "wrong format", func(v): v.format = "another-game")
	_invalid_save(base, "missing field", func(v): v.data.erase("heroes"))
	_invalid_save(base, "negative gold", func(v): v.data.gold = -1)
	_invalid_save(base, "fractional gold", func(v): v.data.gold = 1.5)
	_invalid_save(base, "boolean gold", func(v): v.data.gold = true)
	_invalid_save(base, "locked campaign stage", func(v): v.data.stage = 11)
	_invalid_save(base, "unearned stage unlock", func(v): v.data.unlocked_stage = 5)
	_invalid_save(base, "duplicate party", func(v): v.data.party[1] = v.data.party[0])
	_invalid_save(base, "unrecruited party", func(v): v.data.party[1] = "n08")
	_invalid_save(base, "duplicate roster", func(v): v.data.recruited.append(v.data.recruited[0]))
	_invalid_save(base, "unknown hero", func(v): v.data.heroes["evil"] = v.data.heroes["c01"].duplicate(true))
	_invalid_save(base, "free stat points", func(v): v.data.heroes.c01.points = 177)
	_invalid_save(base, "invalid XP remainder", func(v): v.data.heroes.c01.xp = 999999)
	_invalid_save(base, "invalid stat", func(v): v.data.heroes.c01.stats.strength = -1)
	_invalid_save(base, "free skill rank", func(v): v.data.heroes.c01.skill_rank = 5)
	_invalid_save(base, "invalid saved health", func(v): v.data.heroes.c01.hp = -1)
	_invalid_save(base, "invalid ultimate charge", func(v): v.data.heroes.c01.ultimate_charge = 101)
	_invalid_save(base, "nonnumeric ultimate charge", func(v): v.data.heroes.c01.ultimate_charge = "full")
	_invalid_save(base, "invalid saved cooldown", func(v): v.data.heroes.c01.cooldowns = {"skill": -1})
	_invalid_save(base, "unknown equipment", func(v): v.data.heroes.c01.equipment.weapon = "fake_sword")
	_invalid_save(base, "unknown inventory item", func(v): v.data.inventory.fake_sword = 1)
	var item_id: String = str(db.items[0].id)
	_invalid_save(base, "negative item quantity", func(v): v.data.inventory[item_id] = -3)
	_invalid_save(base, "oversized quantity", func(v): v.data.inventory[item_id] = 10000)
	_invalid_save(base, "invalid threat", func(v): v.data.threat.verdant = 101)
	_invalid_save(base, "unknown quest", func(v): v.data.quests.fake_quest = {"progress": 1, "claimed": true})
	_invalid_save(base, "nested story flag", func(v): v.data.flags.bad = {"bad": [1, 2, 3]})
	_invalid_save(base, "invalid ending", func(v): v.data.ending_choice = "unknown")
	var legacy: Dictionary = base.duplicate(true)
	legacy.version = 1
	legacy.data.erase("threat")
	legacy.data.erase("ending_choice")
	for id in legacy.data.heroes:
		legacy.data.heroes[id].erase("skill_rank")
	_check(state.import_save(JSON.stringify(legacy)), "supported v1 save migrates: " + state.last_error)
	_check(state.threat.size() == 4 and state.hero("c01").skill_rank == 1 and int(JSON.parse_string(state.export_save()).version) == 2, "migration fills defaults and writes current schema")


func _test_campaign() -> void:
	state.new_game()
	state.stage = 5
	var locked_campaign: Dictionary = JSON.parse_string(state.export_save()).data
	state.complete_stage(5)
	_check(_same_campaign(locked_campaign), "locked stage cannot award progression or first-clear rewards")
	state.stage = 0
	for stage_id in range(db.maps.size()):
		state.stage = stage_id
		state.recruit_through(stage_id)
		state.complete_stage(stage_id)
		var first_gold: int = state.gold
		var first_xp: int = int(state.hero("c01").xp)
		state.complete_stage(stage_id)
		_check(state.gold == first_gold and int(state.hero("c01").xp) == first_xp, "stage reward cannot duplicate " + str(stage_id))
		_check(state.import_save(state.export_save()), "stage save roundtrip " + str(stage_id) + ": " + state.last_error)
	_check(state.recruited.size() == 38 and state.heroes.size() == 38, "all 38 characters recruit through the playable 12-stage campaign")
	_check(state.cleared.size() == 12 and state.unlocked_stage == 11, "all stages clear through normal progression methods")
	for ending in ["restore", "open"]:
		state.ending_choice = ending
		state.flags["campaign_complete"] = true
		state.flags["ending_" + ending] = true
		var completed_campaign: Dictionary = JSON.parse_string(state.export_save()).data
		_check(state.import_save(state.export_save()) and _same_campaign(completed_campaign), "completed campaign preserves ending " + ending)
	_check(state.set_party(1, "n08") and state.party[1] == "n08", "late optional character is playable in party")
	_check(not state.set_party(2, "n08"), "duplicate party selection blocked")
	state.stage = 2
	var region: String = str(db.map(2).region)
	var danger: float = float(state.threat[region])
	state.tick_threat(5.0)
	_check(float(state.threat[region]) > danger and state.play_seconds > 0, "unsafe exploration raises threat and playtime")
	state.threat[region] = 100.0
	state.tick_threat(5.0)
	_check(float(state.threat[region]) <= 100.0, "threat remains bounded")
	state.award_xp(10000000)
	_check(state.hero("c01").level == 60 and state.hero("c01").xp == 0, "level cap keeps valid XP remainder")
	_check(state.import_save(state.export_save()), "max-level roster roundtrip remains valid")


func _test_persistence() -> void:
	state.new_game()
	state.hero("c01").hp = 42.0
	state.hero("c01").mp = 17.0
	state.hero("c01").ultimate_charge = 67.0
	state.hero("c01").cooldowns = {"skill": 1.2, "attack": 0.3, "dodge": 0.8}
	for slot in range(4):
		state.gold = 200 + slot
		_check(state.save_slot(slot), "atomic save slot " + str(slot) + ": " + state.last_error)
		_check(await state.await_browser_save(slot), "native save confirmation is immediate for slot " + str(slot))
		_check(state.slot_info(slot).get("valid", false), "slot metadata validated " + str(slot))
	state.gold = 999
	_check(state.load_slot(2) and state.gold == 202, "slots preserve independent data")
	_check(float(state.hero("c01").hp) == 42.0 and float(state.hero("c01").mp) == 17.0 and float(state.hero("c01").ultimate_charge) == 67.0 and state.hero("c01").cooldowns == {"skill": 1.2, "attack": 0.3, "dodge": 0.8}, "runtime vitals, ultimate charge, and cooldowns roundtrip")
	state.gold = 250
	_check(state.save_slot(2), "second write creates backup")
	var corrupt = FileAccess.open(state.save_directory.path_join("slot_2.json"), FileAccess.WRITE)
	corrupt.store_string("{truncated")
	corrupt.close()
	_check(state.slot_info(2).get("backup", false), "metadata detects backup recovery")
	_check(state.load_slot(2) and state.gold == 202, "corrupt primary recovers previous validated backup")
	_check(not state.save_slot(4) and not state.load_slot(-1), "out-of-range slots rejected")
	_check(not await state.await_browser_save(4), "out-of-range save confirmation rejected")
	var invalid_file = FileAccess.open(state.save_directory.path_join("slot_3.json"), FileAccess.WRITE)
	invalid_file.store_string("{}")
	invalid_file.close()
	var before: Dictionary = JSON.parse_string(state.export_save()).data
	_check(not state.load_slot(3) and _same_campaign(before), "invalid disk save without backup leaves active campaign untouched")
	# Test-only storage is isolated and removed; user saves are never touched.
	var directory: String = ProjectSettings.globalize_path(state.save_directory)
	for filename in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)


func _finish() -> void:
	print("STATE_TEST_RESULT " + JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
