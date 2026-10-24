extends Node
## Read-only campaign data. All localized records use {en, th} dictionaries.

var characters: Array = []
var items: Array = []
var maps: Array = []
var quests: Array = []
var stories: Dictionary = {}
var ui: Dictionary = {}
var court: Dictionary = {}
var forest_prologue: Dictionary = {}
var errors: Array[String] = []
var _characters: Dictionary = {}
var _items: Dictionary = {}
var _maps: Dictionary = {}
var _quests: Dictionary = {}


func _ready() -> void:
	reload_data()


func reload_data() -> bool:
	errors.clear()
	characters = _read_array("res://data/characters.json")
	items = _read_array("res://data/items.json")
	maps = _read_array("res://data/maps.json")
	quests = _read_array("res://data/quests.json")
	var loaded_stories = _read_json("res://data/story.json")
	stories = loaded_stories if loaded_stories is Dictionary else {}
	if not loaded_stories is Dictionary:
		errors.append("Expected a story dictionary: res://data/story.json")
	var loaded_ui = _read_json("res://localization/ui.json", false)
	ui = loaded_ui if loaded_ui is Dictionary else {}
	_characters = _index(characters, "character")
	court = _index(_read_array("res://data/court.json"), "court")
	var forest = _read_json("res://data/prologue_forest.json")
	forest_prologue = forest if forest is Dictionary else {}
	_items = _index(items, "item")
	_maps = _index(maps, "map")
	_quests = _index(quests, "quest")
	return errors.is_empty()


func _read_json(path: String, required: bool = true):
	if not FileAccess.file_exists(path):
		if required:
			errors.append("Missing data file: " + path)
		return null
	var parser = JSON.new()
	var error = parser.parse(FileAccess.get_file_as_string(path))
	if error != OK:
		errors.append("Invalid JSON: %s line %s" % [path, parser.get_error_line()])
		return null
	return parser.data


func _read_array(path: String) -> Array:
	var value = _read_json(path)
	if value is Array:
		return value
	errors.append("Expected an array: " + path)
	return []


func _index(records: Array, label: String) -> Dictionary:
	var result: Dictionary = {}
	for record in records:
		if not record is Dictionary or not record.has("id"):
			errors.append("Missing ID in " + label)
			continue
		var key = str(record.id)
		# JSON parses numeric IDs as floats, whose string form includes '.0'.
		# Campaign callers use integer stage IDs, so map keys must be normalized.
		if label == "map":
			if not (record.id is int or record.id is float) or not is_finite(float(record.id)) or float(record.id) != floor(float(record.id)) or float(record.id) < 0:
				errors.append("Invalid map ID: " + key)
				continue
			key = str(int(record.id))
		if result.has(key):
			errors.append("Duplicate %s ID: %s" % [label, key])
		result[key] = record
	return result


func character(id: String) -> Dictionary:
	return _characters.get(id, court.get(id, {}))


func item(id: String) -> Dictionary:
	return _items.get(id, {})


func map(id: int) -> Dictionary:
	return _maps.get(str(id), {})


func story(key: String) -> Dictionary:
	return stories.get(key, {})


func quest(id: String) -> Dictionary:
	return _quests.get(id, {})


func localized(value) -> String:
	if value is String:
		return value
	if not value is Dictionary:
		return ""
	var state = get_node_or_null("/root/State")
	var language: String = str(state.language) if state != null else "th"
	return str(value.get(language, value.get("en", value.get("th", ""))))


func text(key: String) -> String:
	# Both key-first and language-first dictionaries are accepted for UI text.
	if ui.has(key):
		return localized(ui[key])
	var state = get_node_or_null("/root/State")
	var language: String = str(state.language) if state != null else "th"
	if ui.get(language, {}) is Dictionary and ui.get(language, {}).has(key):
		return str(ui[language][key])
	return key
