extends SceneTree
func _initialize():call_deferred("run")
func run():
 var state=root.get_node("State")
 state.new_game()
 for stage in range(11):
  state.stage=stage
  state.complete_stage(stage)
 state.recruit_through(11)
 state.stage=2
 state.party.assign(["c06","c14","c27"])
 state.active_index=0
 var text=state.export_save()
 var file=FileAccess.open("res://../qa/full-cast/fixture.json",FileAccess.WRITE)
 file.store_string(text);file.close()
 print("FULL_CAST_FIXTURE_VALID ",not state._decode_save(text).is_empty())
 root.get_node("Sound").stop_all();quit()
