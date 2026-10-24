extends Node
## Persistent campaign state. Runtime actors synchronize their hp/mp before saving.

signal changed
signal notification(message: String)

const SAVE_VERSION: int = 2
const SAVE_FORMAT: String = "astral-veil-save"
const MAX_LEVEL: int = 60
const MAX_COUNT: int = 9999
const MAX_GOLD: int = 99999999
const STAT_NAMES: Array[String] = ["strength", "dexterity", "intelligence", "vitality", "agility", "spirit"]
const EQUIPMENT_SLOTS: Array[String] = ["weapon", "armor", "accessory", "relic"]
const REGIONS: Array[String] = ["verdant", "ember", "tide", "frost"]
const STARTERS: Array[String] = ["c01", "c04", "c07"]
const MAX_SAVE_BYTES: int = 2097152
## This uses browser IndexedDB directly for read-only confirmation. It does not
## access Emscripten's private FS objects or write another copy of the save.
const BROWSER_SAVE_VERIFIER: String = """
window.AstralVeilPersistence = {
  verify: function(path, expected, callback, timeoutMs) {
    const diagnostic = {path: path, expectedLength: expected.length, expectedType: typeof expected, attempts: 0};
    this.diagnostic = diagnostic;
    let db = null;
    let finished = false;
    let retryTimer = null;
    const timeoutTimer = setTimeout(function() {
      finish(false, 'Browser storage did not confirm this save before the timeout.');
    }, timeoutMs);
    function finish(success, message) {
      if (finished) return;
      finished = true;
      clearTimeout(timeoutTimer);
      if (retryTimer !== null) clearTimeout(retryTimer);
      if (db) db.close();
      callback(success, message);
    }
    function readCommittedSave() {
      diagnostic.attempts++;
      if (finished) return;
      try {
        const transaction = db.transaction('FILE_DATA', 'readonly');
        const request = transaction.objectStore('FILE_DATA').get(path);
        let matched = false;
        request.onsuccess = function() {
          const record = request.result;
          if (record && record.contents) {
            try {
              const actual = new TextDecoder('utf-8').decode(record.contents);
              diagnostic.actualLength = actual.length;
              matched = actual === expected;
              diagnostic.matched = matched;
              if (!matched) {
                let index = 0;
                while (index < actual.length && index < expected.length && actual[index] === expected[index]) index++;
                diagnostic.firstDifference = index;
              }
            } catch (error) {
              finish(false, 'Browser save data could not be decoded: ' + error.message);
            }
          }
        };
        transaction.oncomplete = function() {
          if (finished) return;
          db.close();
          db = null;
          if (matched) finish(true, '');
          else retryTimer = setTimeout(openDatabase, 200);
        };
        transaction.onerror = function() {
          finish(false, 'Browser storage read failed: ' + (transaction.error || 'unknown error'));
        };
        transaction.onabort = transaction.onerror;
      } catch (error) {
        finish(false, 'Browser storage read failed: ' + error.message);
      }
    }
    function openDatabase() { try {
      const open = indexedDB.open('/userfs');
      open.onupgradeneeded = function() {
        open.transaction.abort();
        finish(false, 'The game persistent storage database is unavailable.');
      };
      open.onerror = function() {
        finish(false, 'Browser storage could not be opened: ' + (open.error || 'unknown error'));
      };
      open.onblocked = function() {
        finish(false, 'Browser storage is blocked by another page.');
      };
      open.onsuccess = function() {
        db = open.result;
        if (finished) { db.close(); return; }
        if (!db.objectStoreNames.contains('FILE_DATA')) {
          finish(false, 'The game persistent file store is unavailable.');
          return;
        }
        db.onversionchange = function() {
          finish(false, 'Browser storage changed while confirming the save.');
        };
        readCommittedSave();
      };
    } catch (error) {
      finish(false, 'Browser storage is unavailable: ' + error.message);
    } }
    openDatabase();
  }
};
"""

var language: String = "th"
var difficulty: String = "story"
var stage: int = 0
var unlocked_stage: int = 0
var party: Array[String] = []
var active_index: int = 0
var recruited: Array[String] = []
var heroes: Dictionary = {}
var inventory: Dictionary = {}
var gold: int = 180
var cleared: Array[int] = []
var flags: Dictionary = {}
var quests: Dictionary = {}
var threat: Dictionary = {}
var play_seconds: float = 0.0
var ending_choice: String = ""
var last_error: String = ""
var save_directory: String = "user://saves"
var _browser_save_payloads: Dictionary = {}
var _browser_save_generations: Dictionary = {}
var _browser_save_requests: Dictionary = {}
var _browser_request_id: int = 0
var _browser_verifier_initialized: bool = false


func _ready() -> void:
	new_game()


func _db():
	return get_node_or_null("/root/DB")


func _say(english: String, thai: String) -> void:
	notification.emit(thai if language == "th" else english)


func new_game() -> void:
	stage = 0
	unlocked_stage = 0
	active_index = 0
	party.clear()
	recruited.clear()
	heroes.clear()
	inventory.clear()
	cleared.clear()
	flags.clear()
	quests.clear()
	threat = {"verdant": 0.0, "ember": 0.0, "tide": 0.0, "frost": 0.0}
	gold = 180
	play_seconds = 0.0
	ending_choice = ""
	last_error = ""
	if _db() == null:
		return
	for id in STARTERS:
		_recruit(id)
		if heroes.has(id):
			party.append(id)
	# Starter provisions are chosen by effect so content IDs remain data-driven.
	var provisioned: Dictionary = {}
	for item_data in _db().items:
		var effect: String = str(item_data.get("effect", ""))
		if item_data.get("kind", "") == "consumable" and effect in ["heal", "mana", "revive"] and not provisioned.has(effect):
			inventory[str(item_data.id)] = 5 if effect == "heal" else (3 if effect == "mana" else 1)
			provisioned[effect] = true
	recruit_through(0)
	_accept_quests()
	changed.emit()


func hero(id: String) -> Dictionary:
	return heroes.get(id, {})


func _recruit(id: String) -> bool:
	if id in recruited or _db().character(id).is_empty():
		return false
	var record: Dictionary = _db().character(id)
	var base_stats: Dictionary = {}
	for stat in STAT_NAMES:
		base_stats[stat] = int(record.get("stats", {}).get(stat, 8))
	# New allies match the team's lowest level to remain usable immediately.
	var join_level: int = MAX_LEVEL
	for existing_id in recruited:
		join_level = mini(join_level, int(heroes[existing_id].level))
	if recruited.is_empty():
		join_level = 1
	heroes[id] = {"level": join_level, "xp": 0, "points": (join_level - 1) * 3,
		"stats": base_stats, "equipment": {}, "skill_rank": 1}
	recruited.append(id)
	return true


func recruit_through(current_stage: int) -> void:
	if _db() == null:
		return
	var joined: bool = false
	for record in _db().characters:
		if int(record.get("recruit_at", 99)) <= current_stage:
			joined = _recruit(str(record.id)) or joined
	for id in _db().map(current_stage).get("recruits", []):
		joined = _recruit(str(id)) or joined
	if joined:
		changed.emit()


func derived(id: String) -> Dictionary:
	if not heroes.has(id):
		return {}
	var h: Dictionary = heroes[id]
	var stats: Dictionary = h.stats
	var level: int = int(h.level)
	var weapon: String = str(_db().character(id).get("weapon", "melee"))
	var attack_stat: float = float(stats.strength)
	if weapon == "ranged":
		attack_stat = float(stats.dexterity)
	elif weapon == "magic":
		attack_stat = float(stats.intelligence)
	var result: Dictionary = {
		"level": level, "skill_rank": int(h.skill_rank),
		"max_hp": 100.0 + float(stats.vitality) * 14.0 + level * 12.0,
		"max_mp": 30.0 + float(stats.spirit) * 7.0 + float(stats.intelligence) * 3.0 + level * 3.0,
		"attack": 12.0 + attack_stat * 2.2 + level * 3.0,
		"defense": 3.0 + float(stats.vitality) * 0.9 + level,
		"power": 16.0 + float(stats.intelligence) * 2.0 + float(stats.spirit) * 1.2 + level * 3.0,
		"speed": 145.0 + float(stats.agility) * 2.0,
		"crit": 0.04 + float(stats.dexterity) * 0.005,
	}
	for item_id in h.equipment.values():
		var bonuses: Dictionary = _db().item(str(item_id)).get("stats", {})
		for key in bonuses:
			if key in result and key not in ["level", "skill_rank"]:
				result[key] = float(result[key]) + float(bonuses[key])
	result.crit = clampf(float(result.crit), 0.0, 0.65)
	result.speed = clampf(float(result.speed), 80.0, 300.0)
	result.max_hp = maxf(float(result.max_hp), 1.0)
	result.max_mp = maxf(float(result.max_mp), 1.0)
	return result


func xp_required(level: int) -> int:
	return 80 + maxi(level, 1) * 45 + maxi(level - 1, 0) * maxi(level - 1, 0) * 8


func award_xp(amount: int) -> void:
	if amount <= 0:
		return
	var gained_level: bool = false
	for id in recruited:
		var h: Dictionary = heroes[id]
		if int(h.level) >= MAX_LEVEL:
			h.xp = 0
			continue
		h.xp = int(h.xp) + mini(amount, 10000000)
		while int(h.level) < MAX_LEVEL and int(h.xp) >= xp_required(int(h.level)):
			h.xp = int(h.xp) - xp_required(int(h.level))
			h.level = int(h.level) + 1
			h.points = int(h.points) + 3
			# Removing stored vitals grants a full recovery on the next actor rebuild.
			h.erase("hp")
			h.erase("mp")
			gained_level = true
		if int(h.level) == MAX_LEVEL:
			h.xp = 0
	if gained_level:
		_say("Level up! Allocate points in the party menu.", "เลเวลเพิ่ม! จัดสรรค่าสถานะได้ในเมนูปาร์ตี้")
	changed.emit()


func allocate(hero_id: String, stat: String) -> bool:
	if not heroes.has(hero_id) or stat not in STAT_NAMES or int(heroes[hero_id].points) < 1:
		return false
	var h: Dictionary = heroes[hero_id]
	h.stats[stat] = int(h.stats[stat]) + 1
	h.points = int(h.points) - 1
	changed.emit()
	return true


func upgrade_skill(hero_id: String) -> bool:
	if not heroes.has(hero_id):
		return false
	var h: Dictionary = heroes[hero_id]
	if int(h.points) < 2 or int(h.skill_rank) >= 5:
		return false
	h.points = int(h.points) - 2
	h.skill_rank = int(h.skill_rank) + 1
	changed.emit()
	return true


func respec_cost(hero_id: String) -> int:
	return 30 + int(heroes.get(hero_id, {}).get("level", 1)) * 10


func respec(hero_id: String) -> bool:
	if not heroes.has(hero_id) or gold < respec_cost(hero_id):
		return false
	var h: Dictionary = heroes[hero_id]
	if int(h.points) == (int(h.level) - 1) * 3 and int(h.skill_rank) == 1:
		return false
	gold -= respec_cost(hero_id)
	var record: Dictionary = _db().character(hero_id)
	for stat in STAT_NAMES:
		h.stats[stat] = int(record.stats[stat])
	h.points = (int(h.level) - 1) * 3
	h.skill_rank = 1
	changed.emit()
	return true


func add_item(id: String, count: int = 1) -> void:
	if count <= 0 or _db().item(id).is_empty():
		return
	inventory[id] = mini(int(inventory.get(id, 0)) + count, MAX_COUNT)
	changed.emit()


func _take_item(id: String, count: int = 1) -> bool:
	if count < 1 or int(inventory.get(id, 0)) < count:
		return false
	var left: int = int(inventory[id]) - count
	if left == 0:
		inventory.erase(id)
	else:
		inventory[id] = left
	return true


func equip(hero_id: String, item_id: String) -> bool:
	if not heroes.has(hero_id) or int(inventory.get(item_id, 0)) < 1:
		return false
	var item_data: Dictionary = _db().item(item_id)
	var slot: String = str(item_data.get("kind", ""))
	if slot not in EQUIPMENT_SLOTS:
		return false
	var equipment: Dictionary = heroes[hero_id].equipment
	var previous: String = str(equipment.get(slot, ""))
	if previous == item_id:
		return false
	if not previous.is_empty() and int(inventory.get(previous, 0)) >= MAX_COUNT:
		return false
	_take_item(item_id)
	if not previous.is_empty():
		inventory[previous] = int(inventory.get(previous, 0)) + 1
	equipment[slot] = item_id
	changed.emit()
	return true


func unequip(hero_id: String, slot: String) -> bool:
	if not heroes.has(hero_id) or not heroes[hero_id].equipment.has(slot):
		return false
	var item_id: String = str(heroes[hero_id].equipment[slot])
	if int(inventory.get(item_id, 0)) >= MAX_COUNT:
		return false
	heroes[hero_id].equipment.erase(slot)
	inventory[item_id] = int(inventory.get(item_id, 0)) + 1
	changed.emit()
	return true


func craft(recipe_id: String) -> bool:
	var item_data: Dictionary = _db().item(recipe_id)
	var recipe: Dictionary = item_data.get("recipe", {})
	if recipe.is_empty() or int(inventory.get(recipe_id, 0)) >= MAX_COUNT:
		return false
	for material in recipe:
		if int(recipe[material]) <= 0 or int(inventory.get(material, 0)) < int(recipe[material]):
			return false
	for material in recipe:
		_take_item(str(material), int(recipe[material]))
	inventory[recipe_id] = int(inventory.get(recipe_id, 0)) + 1
	record_event("craft", recipe_id)
	changed.emit()
	return true


func buy(item_id: String) -> bool:
	var item_data: Dictionary = _db().item(item_id)
	var price: int = int(item_data.get("price", 0))
	if item_data.is_empty() or item_data.get("quest_reward", false) or price < 1 or gold < price or int(inventory.get(item_id, 0)) >= MAX_COUNT:
		return false
	gold -= price
	inventory[item_id] = int(inventory.get(item_id, 0)) + 1
	changed.emit()
	return true


func sell(item_id: String) -> bool:
	var item_data: Dictionary = _db().item(item_id)
	if item_data.is_empty() or int(item_data.get("price", 0)) < 1:
		return false
	var proceeds: int = maxi(1, int(item_data.price) / 2)
	if gold > MAX_GOLD - proceeds or not _take_item(item_id):
		return false
	gold += proceeds
	changed.emit()
	return true


func use_item(item_id: String) -> bool:
	var item_data: Dictionary = _db().item(item_id)
	if item_data.get("kind", "") != "consumable" or not _take_item(item_id):
		return false
	changed.emit()
	return true


func set_party(slot: int, id: String) -> bool:
	if slot < 0 or slot >= 3 or slot >= party.size() or id not in recruited or id in party:
		return false
	party[slot] = id
	changed.emit()
	return true


func respite_next() -> int:
	var value = flags.get("respite_next", 0)
	if not (value is int or value is float): return 0
	var next: int = int(value)
	return next if next in [4,6,7,8,10,11] and next <= unlocked_stage and next - 1 in cleared else 0

func schedule_respite(completed_stage: int) -> bool:
	if completed_stage not in [3,5,6,7,9,10] or completed_stage not in cleared: return false
	var key: String = "respite_seen_" + str(completed_stage)
	if flags.get(key, false): return false
	flags[key] = true
	flags["respite_next"] = completed_stage + 1
	return true

func complete_stage(completed_stage: int) -> void:
	if completed_stage != stage or completed_stage < 0 or completed_stage > unlocked_stage or _db().map(completed_stage).is_empty():
		return
	if completed_stage not in cleared:
		cleared.append(completed_stage)
		unlocked_stage = maxi(unlocked_stage, mini(completed_stage + 1, _db().maps.size() - 1))
		gold = mini(gold + 60 + completed_stage * 20, MAX_GOLD)
		award_xp(50 + completed_stage * 30)
		record_event("stage", str(completed_stage))
		var region: String = str(_db().map(completed_stage).get("region", "verdant"))
		threat[region] = maxf(0.0, float(threat.get(region, 0.0)) - 15.0)
	recruit_through(completed_stage)
	_accept_quests()
	changed.emit()


func tick_threat(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var elapsed: float = minf(delta, 5.0)
	play_seconds += elapsed
	var map_data: Dictionary = _db().map(stage)
	var region: String = str(map_data.get("region", "verdant"))
	if region not in REGIONS:
		return
	var current: float = float(threat.get(region, 0.0))
	if map_data.get("safe", false):
		threat[region] = maxf(0.0, current - elapsed * 0.20)
	else:
		var multiplier: float = 0.55 if difficulty == "story" else (1.45 if difficulty == "hard" else 1.0)
		threat[region] = minf(100.0, current + elapsed * 0.035 * multiplier)


func _accept_quests() -> void:
	for record in _db().quests:
		var id: String = str(record.id)
		if int(record.get("unlock_stage", 0)) <= unlocked_stage and not quests.has(id):
			quests[id] = {"progress": 0, "claimed": false}


func record_event(kind: String, target: String, amount: int = 1) -> void:
	if amount < 1:
		return
	_accept_quests()
	var updated: bool = false
	for record in _db().quests:
		var id: String = str(record.id)
		if not quests.has(id) or quests[id].claimed or str(record.type) != kind:
			continue
		if str(record.get("target", "any")) not in ["any", target]:
			continue
		quests[id].progress = mini(int(record.required), int(quests[id].progress) + amount)
		updated = true
	if updated:
		changed.emit()


func claim_quest(id: String) -> bool:
	var record: Dictionary = _db().quest(id)
	if record.is_empty() or not quests.has(id) or bool(quests[id].claimed) or int(quests[id].progress) < int(record.required):
		return false
	var reward_item: String = str(record.get("reward_item", ""))
	if not reward_item.is_empty() and int(inventory.get(reward_item, 0)) >= MAX_COUNT:
		return false
	quests[id].claimed = true
	gold = mini(gold + int(record.get("reward_gold", 0)), MAX_GOLD)
	award_xp(int(record.get("reward_xp", 0)))
	if not reward_item.is_empty():
		add_item(reward_item)
	var character_id: String = str(record.get("character_id", ""))
	if not character_id.is_empty():
		_recruit(character_id)
	changed.emit()
	return true


func lantern_step() -> int:
	# Derive progress from existing flags; old saves need no migration and an
	# early-discovered parcel still counts once Tavi's request is accepted.
	if not flags.get("lantern_accepted", false): return 0
	if flags.has("lantern_reward"): return 5
	if flags.get("lantern_repaired", false): return 4
	if flags.get("lantern_delivered", false): return 3
	if flags.get("chest_courier_case", false): return 2
	return 1


func deliver_lantern_case() -> bool:
	if lantern_step() != 2: return false
	flags["lantern_delivered"] = true
	changed.emit()
	return true


func repair_lantern() -> bool:
	if lantern_step() != 3: return false
	flags["lantern_repaired"] = true
	changed.emit()
	return true


func claim_lantern_reward(item: String) -> bool:
	if lantern_step() != 4 or item not in ["r09", "r10"]: return false
	if int(inventory.get(item, 0)) >= MAX_COUNT: return false
	# Commit the choice before emitting inventory/XP signals to prevent double grants.
	flags["lantern_reward"] = item
	gold = mini(gold + 120, MAX_GOLD)
	add_item(item)
	award_xp(160)
	changed.emit()
	return true


func _payload() -> Dictionary:
	return {"language": language, "difficulty": difficulty, "stage": stage,
		"unlocked_stage": unlocked_stage, "party": party.duplicate(), "active_index": active_index,
		"recruited": recruited.duplicate(), "heroes": heroes.duplicate(true),
		"inventory": inventory.duplicate(true), "gold": gold, "cleared": cleared.duplicate(),
		"flags": flags.duplicate(true), "quests": quests.duplicate(true), "threat": threat.duplicate(true),
		"play_seconds": play_seconds, "ending_choice": ending_choice}


func export_save() -> String:
	var envelope: Dictionary = {"format": SAVE_FORMAT, "version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true), "data": _payload()}
	return JSON.stringify(envelope, "  ")


func import_save(text: String) -> bool:
	var validated: Dictionary = _decode_save(text)
	if validated.is_empty():
		return false
	_apply_payload(validated.data)
	last_error = ""
	changed.emit()
	return true


func _reject(message: String) -> Dictionary:
	last_error = message
	return {}


func _integer(value, low: int, high: int) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	return is_finite(number) and number == floor(number) and number >= low and number <= high


func _number(value, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high


func _decode_save(text: String) -> Dictionary:
	last_error = ""
	if text.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		return _reject("Save exceeds the 2 MiB limit.")
	var parser = JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return _reject("Save is not a JSON object.")
	var envelope: Dictionary = parser.data
	if envelope.get("format", "") != SAVE_FORMAT or not _integer(envelope.get("version"), 1, SAVE_VERSION):
		return _reject("Unknown save format or unsupported version.")
	if not envelope.get("data") is Dictionary:
		return _reject("Save data is missing.")
	var data: Dictionary = envelope.data.duplicate(true)
	if int(envelope.version) == 1:
		data = _migrate_v1(data)
	if not _validate_payload(data):
		return {}
	return {"data": data, "saved_at": str(envelope.get("saved_at", "")), "version": SAVE_VERSION}


func _migrate_v1(data: Dictionary) -> Dictionary:
	# Version 1 used the same identity/progression fields without regional danger
	# or skill upgrades. Defaults never invent missing identity or progression.
	if not data.has("threat"):
		data.threat = {"verdant": 0.0, "ember": 0.0, "tide": 0.0, "frost": 0.0}
	if not data.has("ending_choice"):
		data.ending_choice = ""
	if data.get("heroes") is Dictionary:
		for id in data.heroes:
			if data.heroes[id] is Dictionary and not data.heroes[id].has("skill_rank"):
				data.heroes[id].skill_rank = 1
	return data


func _invalid(message: String) -> bool:
	last_error = message
	return false


func _validate_payload(data: Dictionary) -> bool:
	var required_fields: Array = ["language", "difficulty", "stage", "unlocked_stage", "party", "active_index", "recruited", "heroes", "inventory", "gold", "cleared", "flags", "quests", "threat", "play_seconds", "ending_choice"]
	for field in required_fields:
		if not data.has(field):
			return _invalid("Missing save field: " + str(field))
	if data.language not in ["en", "th"] or data.difficulty not in ["story", "normal", "hard"]:
		return _invalid("Invalid language or difficulty.")
	var final_stage: int = _db().maps.size() - 1
	if not _integer(data.stage, 0, final_stage) or not _integer(data.unlocked_stage, 0, final_stage) or int(data.stage) > int(data.unlocked_stage):
		return _invalid("Invalid campaign stage.")
	if not _integer(data.gold, 0, MAX_GOLD) or not _number(data.play_seconds, 0.0, 315360000.0):
		return _invalid("Invalid gold or elapsed time.")
	if not data.ending_choice is String or data.ending_choice not in ["", "restore", "open", "ending_restore", "ending_open"]:
		return _invalid("Invalid ending choice.")
	if not data.recruited is Array or data.recruited.size() < 3 or data.recruited.size() > _db().characters.size():
		return _invalid("Invalid recruited roster.")
	var seen: Dictionary = {}
	for id in data.recruited:
		if not id is String or not _db()._characters.has(id) or seen.has(id):
			return _invalid("Unknown or duplicate recruited character.")
		seen[id] = true
	for id in STARTERS:
		if not seen.has(id):
			return _invalid("A starting character is missing.")
	if not data.party is Array or data.party.size() != 3 or not _integer(data.active_index, 0, 2):
		return _invalid("Invalid party.")
	var seen_party: Dictionary = {}
	for id in data.party:
		if not id is String or not seen.has(id) or seen_party.has(id):
			return _invalid("Party characters must be recruited and unique.")
		seen_party[id] = true
	if not data.heroes is Dictionary or data.heroes.size() != data.recruited.size():
		return _invalid("Hero data does not match the roster.")
	for id in data.heroes:
		if not seen.has(id) or not data.heroes[id] is Dictionary:
			return _invalid("Invalid hero record.")
		if not _validate_hero(str(id), data.heroes[id]):
			return false
	if not data.inventory is Dictionary or data.inventory.size() > _db().items.size():
		return _invalid("Invalid inventory.")
	for id in data.inventory:
		if _db().item(str(id)).is_empty() or not _integer(data.inventory[id], 1, MAX_COUNT):
			return _invalid("Unknown item or invalid quantity.")
	if not data.cleared is Array or data.cleared.size() > _db().maps.size():
		return _invalid("Invalid cleared-stage list.")
	var seen_stages: Dictionary = {}
	for value in data.cleared:
		if not _integer(value, 0, int(data.unlocked_stage)) or seen_stages.has(int(value)):
			return _invalid("Invalid or duplicate cleared stage.")
		seen_stages[int(value)] = true
	for previous in range(int(data.unlocked_stage)):
		if not seen_stages.has(previous):
			return _invalid("Unlocked stage lacks completed prerequisites.")
	if not data.flags is Dictionary or data.flags.size() > 4096:
		return _invalid("Invalid story flags.")
	for key in data.flags:
		if str(key).length() > 128 or not _valid_flag_value(data.flags[key]):
			return _invalid("Invalid story flag value.")
	if not data.quests is Dictionary or data.quests.size() > _db().quests.size():
		return _invalid("Invalid quest journal.")
	for id in data.quests:
		var record: Dictionary = _db().quest(str(id))
		var progress = data.quests[id]
		if record.is_empty() or not progress is Dictionary:
			return _invalid("Unknown quest.")
		if int(record.get("unlock_stage", 0)) > int(data.unlocked_stage) or not _integer(progress.get("progress"), 0, int(record.required)) or not progress.get("claimed") is bool:
			return _invalid("Invalid quest progress.")
		if progress.claimed and int(progress.progress) < int(record.required):
			return _invalid("Claimed quest is incomplete.")
	if not data.threat is Dictionary or data.threat.size() != REGIONS.size():
		return _invalid("Invalid regional threat.")
	for region in REGIONS:
		if not _number(data.threat.get(region), 0.0, 100.0):
			return _invalid("Regional threat is outside its bounds.")
	return true


func _valid_flag_value(value) -> bool:
	if value is bool:
		return true
	if value is String:
		return value.length() <= 512
	return _number(value, -10000000.0, 10000000.0)


func _validate_hero(id: String, h: Dictionary) -> bool:
	if not _integer(h.get("level"), 1, MAX_LEVEL) or not _integer(h.get("points"), 0, (MAX_LEVEL - 1) * 3) or not _integer(h.get("skill_rank"), 1, 5):
		return _invalid("Invalid hero level, points, or skill rank.")
	var level: int = int(h.level)
	if not _integer(h.get("xp"), 0, 0 if level == MAX_LEVEL else xp_required(level) - 1):
		return _invalid("Invalid experience remainder.")
	if not h.get("stats") is Dictionary or h.stats.size() != STAT_NAMES.size() or not h.get("equipment") is Dictionary:
		return _invalid("Invalid hero stats or equipment.")
	var base: Dictionary = _db().character(id).get("stats", {})
	var spent: int = (int(h.skill_rank) - 1) * 2
	for stat in STAT_NAMES:
		var initial: int = int(base.get(stat, 8))
		if not _integer(h.stats.get(stat), initial, initial + (MAX_LEVEL - 1) * 3):
			return _invalid("Invalid allocated stat.")
		spent += int(h.stats[stat]) - initial
	if spent + int(h.points) != (level - 1) * 3:
		return _invalid("Hero stat-point budget does not balance.")
	for slot in h.equipment:
		if slot not in EQUIPMENT_SLOTS or not h.equipment[slot] is String:
			return _invalid("Unknown equipment slot.")
		var equipped: Dictionary = _db().item(h.equipment[slot])
		if equipped.is_empty() or str(equipped.get("kind", "")) != str(slot):
			return _invalid("Item does not fit its equipment slot.")
	for vital in ["hp", "mp"]:
		if h.has(vital) and not _number(h[vital], 0.0, 100000.0):
			return _invalid("Invalid saved hero vitals.")
	if h.has("ultimate_charge") and not _number(h.ultimate_charge, 0.0, 100.0):
		return _invalid("Invalid saved ultimate charge.")
	if h.has("cooldowns"):
		if not h.cooldowns is Dictionary or h.cooldowns.size() > 16:
			return _invalid("Invalid saved cooldowns.")
		for key in h.cooldowns:
			if str(key).length() > 32 or not _number(h.cooldowns[key], 0.0, 3600.0):
				return _invalid("Invalid cooldown value.")
	return true


func _apply_payload(data: Dictionary) -> void:
	language = str(data.language)
	difficulty = str(data.difficulty)
	stage = int(data.stage)
	unlocked_stage = int(data.unlocked_stage)
	active_index = int(data.active_index)
	party.assign(data.party)
	recruited.assign(data.recruited)
	heroes = data.heroes.duplicate(true)
	inventory = data.inventory.duplicate(true)
	gold = int(data.gold)
	cleared.assign(data.cleared)
	flags = data.flags.duplicate(true)
	quests = data.quests.duplicate(true)
	threat = data.threat.duplicate(true)
	play_seconds = float(data.play_seconds)
	ending_choice = str(data.ending_choice)
	_accept_quests()


func _slot_path(slot: int) -> String:
	return save_directory.path_join("slot_%d.json" % slot)


func save_slot(slot: int) -> bool:
	if slot < 0 or slot > 3:
		last_error = "Save slot must be between 0 and 3."
		return false
	var text: String = export_save()
	if _decode_save(text).is_empty():
		return false
	var directory: String = ProjectSettings.globalize_path(save_directory)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		last_error = "Cannot create the save directory."
		return false
	var path: String = _slot_path(slot)
	var temporary: String = path + ".tmp"
	var backup: String = path + ".bak"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Cannot write the temporary save file."
		return false
	file.store_string(text)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or _read_valid_file(temporary).is_empty():
		last_error = "The temporary save failed verification."
		return false
	# Back up only a valid previous file, preserving a recovery copy on corruption.
	if FileAccess.file_exists(path) and not _read_valid_file(path).is_empty():
		var copy_error: Error = DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup))
		if copy_error != OK:
			last_error = "Cannot back up the previous save."
			return false
	var rename_error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if rename_error != OK:
		last_error = "Cannot replace the save file."
		return false
	if OS.has_feature("web"):
		_browser_save_payloads[slot] = text
		_browser_save_generations[slot] = int(_browser_save_generations.get(slot, 0)) + 1
		# Request synchronization after the final rename. FileAccess.close() also
		# schedules synchronization, but a successful write is not yet durable.
		JavaScriptBridge.force_fs_sync()
	last_error = ""
	return true


func await_browser_save(slot: int, timeout_seconds: float = 15.0) -> bool:
	if slot < 0 or slot > 3:
		last_error = "Save slot must be between 0 and 3."
		return false
	if not OS.has_feature("web"):
		return true
	if not OS.is_userfs_persistent():
		last_error = "Browser storage is not persistent. Export a save backup."
		return false
	if not _browser_save_payloads.has(slot):
		last_error = "No browser save write is waiting for confirmation."
		return false
	if not is_finite(timeout_seconds) or timeout_seconds <= 0.0 or timeout_seconds > 60.0:
		last_error = "Browser save confirmation timeout must be between 0 and 60 seconds."
		return false
	if not _browser_verifier_initialized:
		JavaScriptBridge.eval(BROWSER_SAVE_VERIFIER, true)
		_browser_verifier_initialized = true
	var interface = JavaScriptBridge.get_interface("AstralVeilPersistence")
	if interface == null:
		last_error = "Browser save confirmation could not be initialized."
		return false
	var deadline: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var generation: int = int(_browser_save_generations[slot])
		_browser_request_id += 1
		var request_id: int = _browser_request_id
		var callback = JavaScriptBridge.create_callback(_on_browser_save_confirmed.bind(request_id))
		_browser_save_requests[request_id] = {"done": false, "success": false, "message": "", "callback": callback}
		var remaining_ms: int = maxi(1, deadline - Time.get_ticks_msec())
		interface.verify(ProjectSettings.globalize_path(_slot_path(slot)), str(_browser_save_payloads[slot]), callback, remaining_ms)
		var next_sync: int = Time.get_ticks_msec() + 500
		while not bool(_browser_save_requests[request_id].done) and Time.get_ticks_msec() < deadline + 2000:
			# A write can land while Godot is already syncing another slot. Retry
			# the supported sync request until committed bytes are confirmed.
			if Time.get_ticks_msec() >= next_sync:
				JavaScriptBridge.force_fs_sync()
				next_sync = Time.get_ticks_msec() + 500
			await get_tree().process_frame
		var result: Dictionary = _browser_save_requests[request_id]
		_browser_save_requests.erase(request_id)
		# If a newer write replaced the same slot, only acknowledge that latest
		# payload. The shared deadline keeps repeated writes from waiting forever.
		if generation != int(_browser_save_generations[slot]):
			continue
		if bool(result.done) and bool(result.success):
			last_error = ""
			return true
		last_error = str(result.message) if not str(result.message).is_empty() else "Browser save confirmation timed out."
		return false
	last_error = "Browser save confirmation timed out while newer writes were queued."
	return false


func _on_browser_save_confirmed(arguments: Array, request_id: int) -> void:
	if not _browser_save_requests.has(request_id):
		return
	var request: Dictionary = _browser_save_requests[request_id]
	request.done = true
	request.success = arguments.size() >= 1 and bool(arguments[0])
	request.message = str(arguments[1]) if arguments.size() >= 2 else "Browser save confirmation returned no diagnostic."


func _read_valid_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _reject("Save file does not exist.")
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_SAVE_BYTES:
		return _reject("Save file cannot be read or is too large.")
	var text: String = file.get_as_text()
	file.close()
	return _decode_save(text)


func load_slot(slot: int) -> bool:
	if slot < 0 or slot > 3:
		last_error = "Save slot must be between 0 and 3."
		return false
	var path: String = _slot_path(slot)
	var validated: Dictionary = _read_valid_file(path)
	var recovered: bool = false
	if validated.is_empty():
		validated = _read_valid_file(path + ".bak")
		recovered = not validated.is_empty()
	if validated.is_empty():
		return false
	_apply_payload(validated.data)
	last_error = ""
	changed.emit()
	if recovered:
		_say("Recovered the previous valid save from backup.", "กู้คืนข้อมูลบันทึกก่อนหน้าจากไฟล์สำรองแล้ว")
	return true


func slot_info(slot: int) -> Dictionary:
	if slot < 0 or slot > 3:
		return {"exists": false, "valid": false}
	var previous_error: String = last_error
	var path: String = _slot_path(slot)
	var exists: bool = FileAccess.file_exists(path)
	var validated: Dictionary = _read_valid_file(path)
	var recovered: bool = false
	if validated.is_empty():
		validated = _read_valid_file(path + ".bak")
		recovered = not validated.is_empty()
	var result: Dictionary = {"exists": exists or recovered, "valid": not validated.is_empty(), "backup": recovered}
	if not validated.is_empty():
		var data: Dictionary = validated.data
		result.merge({"stage": int(data.stage), "unlocked_stage": int(data.unlocked_stage), "gold": int(data.gold), "play_seconds": float(data.play_seconds), "saved_at": validated.saved_at,
			"difficulty": str(data.difficulty), "level": int(data.heroes[data.party[0]].level), "recruited": data.recruited.size()})
	last_error = previous_error
	return result
