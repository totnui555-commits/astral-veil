extends SceneTree

var checks: int = 0
var failures: Array = []
var app
var state
var world

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok:
  failures.append(label)
  push_error(label)
func read_story() -> void:
 var limit: int = 0
 while is_instance_valid(app.dialogue_layer) and limit < 60:
  app.advance_dialogue()
  limit += 1

func run() -> void:
 state = root.get_node("State")
 state.save_directory = "user://counterplay_%d" % Time.get_ticks_usec()
 state.language = "en"
 state.new_game()
 app = load("res://scenes/main.tscn").instantiate()
 root.add_child(app)
 app.start_game(0,false)
 world = app.world
 world.set_physics_process(false)
 world.obstacles.clear()
 var hero = world.active_actor()
 hero.crit = 0
 hero.position = Vector2(400,500)
 var brute = world._spawn_enemy({"kind":"brute","pos":[500,500],"hp":1000})
 brute.facing = Vector2.LEFT
 var front: float = world.damage_enemy(brute,100,hero)
 hero.position = Vector2(600,500)
 var back: float = world.damage_enemy(brute,100,hero)
 check(front < back*0.31 and front > back*0.29,"frontal guard reduces damage; flanking bypasses it without inflating HP")
 hero.position = Vector2(400,500)
 world._break_windup(brute,hero)
 check(brute.guard_open > 0 and brute.statuses.has("weakness") and brute.windup == 0,"heavy breaks guard even outside windup and creates vulnerability")
 check(world.damage_enemy(brute,100,hero) > back,"open guard rewards attacks during weakness")
 brute.statuses.clear(); brute.guard_open = 0
 # Actual heavy projectile collision must use the same guard break as melee.
 world.projectile(hero.position + Vector2(0,-9),Vector2.RIGHT,100,hero,Color.WHITE,500,true,true)
 world._tick_projectiles(0.2)
 check(brute.guard_open > 0,"heavy projectile collision opens guard for ranged heroes")
 brute.statuses.clear(); brute.guard_open=0; brute.recovery=0; brute.attack_timer=0
 hero.position=Vector2(530,500)
 world._enemy_ai(brute,0.01)
 check(brute.windup>0,"guarded brute telegraphs its retaliation")
 world._enemy_ai(brute,2.0)
 check(brute.recovery>0 and brute.guard_open>0,"brute opens guard and stops after its attack")
 var timer: float=brute.attack_timer
 world._enemy_ai(brute,0.1)
 check(brute.attack_timer==timer,"recovery is a real punish window, not only a visual effect")
 var stalker=world._spawn_enemy({"kind":"stalker","pos":[750,500],"hp":1000})
 hero.position=Vector2(550,500)
 # Keep companions from becoming the nearest target in this isolated test.
 for actor in world.actors:
  if actor!=hero: actor.position=Vector2(1500,900)
 stalker.attack_timer=0
 world._enemy_ai(stalker,0.01)
 check(stalker.windup>0 and stalker.attack_pattern==4,"stalker starts a telegraphed lunge at 200 units, closing the old ranged safe spot")
 var before: Vector2=stalker.position
 hero.invulnerable=0
 world._enemy_ai(stalker,2.0)
 check(stalker.position.distance_to(before)>100 and stalker.recovery>0,"stalker lunge moves it and commits to recovery")
 var mage=world._spawn_enemy({"kind":"mage","pos":[800,600],"hp":1000})
 brute.position=Vector2(700,600);brute.hp=brute.max_hp*0.4
 stalker.hp=stalker.max_hp
 hero.position=Vector2(700,700)
 mage.attack_timer=0
 world._enemy_ai(mage,0.01)
 check(mage.attack_pattern==5 and mage.windup_total==1.4,"mender chooses a wounded ally and gives a 1.4-second interrupt window")
 var wounded: float=brute.hp
 world._enemy_ai(mage,2.0)
 check(brute.hp>wounded,"uninterrupted mending actually restores enemy HP")
 mage.recovery=0; mage.attack_timer=0
 world._enemy_ai(mage,0.01)
 world._break_windup(mage,hero)
 wounded=brute.hp
 world._enemy_ai(mage,2.0)
 check(mage.windup==0 and brute.hp==wounded,"heavy interrupt cancels the heal instead of resolving it later")
 # Fully healed allies should make the caster attack instead of channel forever.
 for e in world.enemies:e.hp=e.max_hp
 mage.statuses.clear();mage.recovery=0;mage.attack_timer=0
 world._enemy_ai(mage,0.01)
 check(mage.attack_pattern!=5,"mender falls back to offensive patterns with no wounded ally")
 # Sealed bosses must stay available for their mandatory interaction.
 var boss=world._spawn_enemy({"id":"sealed_fixture","kind":"warden","pos":[850,600],"hp":1000,"sky_seal":true},true)
 boss.hp=boss.max_hp*0.5
 mage.windup=0;mage.recovery=0;mage.attack_timer=0
 world._enemy_ai(mage,0.01)
 check(mage.attack_pattern!=5,"mending cannot heal the Warden out of its seal interaction")
 # Reach each intermission through the shipping transition callback.
 var visited: Array=[]
 for stage in range(11):
  state.stage=stage;state.unlocked_stage=maxi(state.unlocked_stage,stage)
  app.start_game(stage,false);app.world.set_physics_process(false)
  app.advance_stage();read_story()
  if stage == 0 and state.stage == 0:
   app.advance_stage();read_story()
  if stage in [3,5,6,7,9,10]:
   check(state.stage==1 and state.respite_next()==stage+1,"stage %d returns to safe town with a preserved itinerary" % stage)
   visited.append(stage)
   app.world.set_physics_process(false)
   check(app.world.map_data.safe and app.world.enemies.is_empty(),"town respite %d contains no enemies" % stage)
   check(app.world.active_actor().hp==app.world.active_actor().max_hp,"town respite %d restores party health" % stage)
   var result=state.save_slot(2)
   check(result and state.load_slot(2) and state.respite_next()==stage+1,"rest itinerary survives save/load %d" % stage)
   check(not state.schedule_respite(stage),"repeated tower clear cannot schedule duplicate respite %d" % stage)
   app.advance_stage();read_story()
   check(state.stage==stage+1 and state.respite_next()==0,"town gold gate resumes the right stage %d, not the first field" % stage)
  await process_frame
 check(visited.size()==6,"six tower intermissions are covered")
 # Replaying summoning from an old save must reveal the illustration without
 # replaying its progression callback or changing flags/choices/rewards.
 app.start_game(1,false);app.world.set_physics_process(false)
 var flags: Dictionary=state.flags.duplicate(true)
 var gold: int=state.gold
 var cleared: Array=state.cleared.duplicate()
 app.open_panel("chronicle")
 check(app.panel_name=="chronicle","story archive opens for an existing save")
 app.replay_story("m00_outro")
 var saw_skyfall: bool=false
 for i in range(20):
  if not is_instance_valid(app.dialogue_layer):break
  if app.dialogue_index<app.dialogue.size() and app.dialogue[app.dialogue_index].get("cinematic","")=="skyfall":saw_skyfall=true
  app.advance_dialogue()
 check(saw_skyfall and app.panel_name=="chronicle","replay renders the summoning scene and returns to archive")
 check(state.flags==flags and state.gold==gold and state.cleared==cleared and state.stage==1,"story replay has no reward, flag, choice or campaign side effects")
 app.replay_story("m11_outro");read_story()
 check(not is_instance_valid(app.dialogue_layer) and state.ending_choice.is_empty(),"replay strips ending choices instead of changing the campaign ending")
 app.close_panel();app.show_title();await process_frame
 app.open_panel("chronicle");app.replay_story("m00_outro");read_story()
 check(app.panel_name=="chronicle" and not app.playing,"illustrated replay also works from the title without a world")
 print(JSON.stringify({"suite":"counterplay_and_respite","checks":checks,"failures":failures}))
 app.free()
 await process_frame
 root.get_node("Sound").stop_all()
 quit(0 if failures.is_empty() else 1)
