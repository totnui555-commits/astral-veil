extends SceneTree
var checks: int = 0
var failures: Array = []
var app
var state
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
 checks += 1
 if not ok: failures.append(label); push_error(label)
func drain():
 for i in range(80):
  if not is_instance_valid(app.dialogue_layer): return
  app.advance_dialogue()
func run():
 state=root.get_node("State")
 state.save_directory="user://royal_relay_%d" % Time.get_ticks_usec()
 app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
 app.new_game();app.world.set_physics_process(false)
 check(app.world.map_data.theme=="throne" and app.dialogue[0].cinematic=="royal_summoning","new game first appears in royal summoning, never classroom")
 var students: Array=state.party.duplicate()
 var court_count: int=0
 for npc in app.world.map_data.npcs:
  if str(npc.character_id).begins_with("c") and str(npc.character_id).length()==3:students.append(npc.character_id)
  else:court_count+=1
 check(students.size()==30 and court_count>=15,"exactly thirty student identities plus king, mage and populated court")
 drain();app.advance_stage();drain()
 check(state.stage==0 and state.unlocked_stage==0 and state.cleared.is_empty(),"court evacuation does not prematurely reward or unlock the campaign")
 check(app.world.map_data.intro=="forest_arrival" and app.world.enemies.is_empty(),"cutscene leads to actual safe playable forest")
 app.save_game(1,false);app.load_game(1)
 check(app.world.map_data.intro=="forest_arrival" and not is_instance_valid(app.dialogue_layer),"save/load retains forest phase without repeating its introduction")
 app.advance_stage();drain()
 check(state.stage==1 and state.cleared.has(0),"forest exit reaches existing town and completes stage zero once")
 app.world.set_physics_process(false)
 var flags=state.flags.duplicate(true);var gold=state.gold
 app.replay_story("royal_summoning");drain()
 check(state.flags==flags and state.gold==gold,"royal replay does not modify saves or rewards")
 app.close_panel();app.start_game(2,false);app.world.set_physics_process(false)
 var w=app.world;w.obstacles.clear()
 var hero=w.active_actor();hero.position=Vector2(400,500);hero.crit=0
 var foe=w._spawn_enemy({"kind":"brute","pos":[500,500],"hp":10000});foe.facing=Vector2.LEFT
 w._break_windup(foe,hero)
 check(w.relay_time==3 and w.relay_from==hero.id,"active hero guard break opens relay")
 var next=w.actors[1];next.mp=0;next.skill_cooldown=5;next.crit=0
 app.open_panel("tactics")
 var clock: float=w.elapsed
 for i in range(3):await physics_frame
 check(w.paused and w.elapsed==clock and w.relay_time==3,"tactical menu freezes simulation and relay timer")
 app.close_panel()
 foe.defeated=true
 w.switch_to(1)
 check(w.relay_time==0 and next.mp==12,"earned relay survives target death before the switch")
 foe.defeated=false
 check(w.relay_time==0 and next.mp==12 and next.skill_cooldown==2,"relay consumes once, refunds mana and recovers skill")
 var boosted: float=w.damage_enemy(foe,100,next)
 var normal: float=w.damage_enemy(foe,100,next)
 check(is_equal_approx(boosted,normal*1.5),"relay boosts exactly one damage event by fifty percent")
 w.switch_to(2);w.switch_to(1)
 check(next.mp==12,"repeated switching cannot farm relay resources")
 foe.guard_open=0;foe.statuses.clear();w._break_windup(foe,next)
 check(w.relay_time==0,"same enemy cannot immediately regenerate relay")
 w.elapsed+=9;foe.guard_open=0;foe.statuses.clear();w._break_windup(foe,next)
 check(w.relay_time==3,"enemy relay cooldown eventually expires")
 w.relay_time=0;var partner=w.actors[2];foe.guard_open=0;foe.statuses.clear();w.elapsed+=9;w._break_windup(foe,partner)
 check(w.relay_time==0,"autonomous ally cannot grant active-player relay")
 for definition in root.get_node("DB").characters:
  check(VisualAnimation.supports(definition.id),definition.id+" detailed animation registry")
  var tex=VisualAnimation.atlas_texture(definition.id)
  check(tex!=null and tex.get_size()==Vector2(1536,1536),definition.id+" combat atlas")
  check(PortraitLibrary.is_illustrated(definition) and PortraitLibrary.full_texture(definition)!=null,definition.id+" matching portrait")
  VisualAnimation.release_unused([])
 check(PortraitLibrary._full_views.size()<=2,"full portrait cache remains bounded across whole cast")
 print(JSON.stringify({"suite":"royal_prologue_and_tactical_relay","checks":checks,"failures":failures}))
 app.free();await process_frame;root.get_node("Sound").stop_all();quit(0 if failures.is_empty() else 1)
