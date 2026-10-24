extends SceneTree
## Isolated visual-review fixture. This does not run or certify a campaign.
## tools/godot.sh --headless --path game --script tests/create_visual_fixture.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state = root.get_node("State")
	var db = root.get_node("DB")
	if not db.errors.is_empty():
		push_error("Cannot create visual fixture: " + str(db.errors))
		quit(1)
		return
	state.language = "th"
	state.difficulty = "story"
	state.new_game()
	var operations: Array = [{"api": "new_game", "scope": "isolated visual review"}]
	for stage_id in range(4):
		state.stage = stage_id
		state.recruit_through(stage_id)
		state.complete_stage(stage_id)
		operations.append({"api": "complete_stage", "stage": stage_id})
	var xp_to_six: int = -int(state.hero("c01").xp)
	for level in range(int(state.hero("c01").level), 6):
		xp_to_six += state.xp_required(level)
	state.award_xp(xp_to_six)
	operations.append({"api": "award_xp", "amount": xp_to_six})
	# Shop transactions populate the review inventory without duplicating items.
	for kind in ["weapon", "armor", "accessory", "relic"]:
		var cheapest: Dictionary = {}
		for item in db.items:
			if str(item.get("kind", "")) == kind and int(item.get("price", 0)) > 0:
				if cheapest.is_empty() or int(item.price) < int(cheapest.price):
					cheapest = item
		if not cheapest.is_empty() and state.buy(str(cheapest.id)):
			operations.append({"api": "buy", "item": str(cheapest.id)})
	state.stage = 0
	var exported: String = state.export_save()
	if not state.import_save(exported):
		push_error("Visual fixture failed production validation: " + state.last_error)
		quit(1)
		return
	var repository: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var fixture_path: String = repository.path_join("qa/visual-fixture.json")
	var fixture = FileAccess.open(fixture_path, FileAccess.WRITE)
	if fixture == null:
		push_error("Could not write isolated visual fixture.")
		quit(1)
		return
	fixture.store_string(exported)
	fixture.close()
	var party_levels: Dictionary = {}
	for id in state.party:
		party_levels[id] = int(state.hero(str(id)).level)
	var report: Dictionary = {"scope": "isolated production-State fixture for visual review; not a campaign playthrough",
		"fixture": fixture_path, "valid": true, "operations": operations, "party_levels": party_levels,
		"stage": state.stage, "cleared": state.cleared, "unlocked_stage": state.unlocked_stage,
		"recruited": state.recruited.size(), "story_flags": state.flags,
		"no_user_save_slots_written": true, "no_runtime_damage_or_hp_injection": true}
	var evidence = FileAccess.open(repository.path_join("qa/visual-fixture-evidence.json"), FileAccess.WRITE)
	evidence.store_string(JSON.stringify(report, "  "))
	evidence.close()
	print("VISUAL_FIXTURE_RESULT " + JSON.stringify(report))
	root.get_node("Sound").stop_all()
	await create_timer(0.1).timeout
	quit(0)
