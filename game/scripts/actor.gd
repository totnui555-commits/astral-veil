extends Node2D

const Art = preload("res://scripts/pixel_art.gd")
const AnimationArt = preload("res://scripts/visual_animation.gd")

var chain_count: int = 0
var chain_window: float = 0.0
var counter_window: float = 0.0
var id: String = ""
var definition: Dictionary = {}
var hp: float = 100.0
var max_hp: float = 100.0
var mp: float = 50.0
var max_mp: float = 50.0
var attack_power: float = 25.0
var magic_power: float = 30.0
var defense: float = 5.0
var speed: float = 160.0
var crit: float = 0.05
var level: int = 1
var skill_cooldown: float = 0.0
var ultimate_charge: float = 0.0
var attack_cooldown: float = 0.0
var dodge_cooldown: float = 0.0
var hurt_flash: float = 0.0
var invulnerable: float = 0.0
var statuses: Dictionary = {}
var defeated: bool = false
var facing: Vector2 = Vector2.DOWN
var velocity: Vector2 = Vector2.ZERO
var active: bool = false
var enemy: bool = false
var enemy_kind: String = "stalker"
var boss: bool = false
var boss_phase: int = 1
var boss_engaged: bool = false
var phase_count: int = 3
var attack_timer: float = 1.0
var windup: float = 0.0
var windup_total: float = 1.0
var target_point: Vector2 = Vector2.ZERO
var attack_pattern: int = 0
var ai_timer: float = 0.0
var animation_time: float = 0.0
var source_actor: Node2D = null
var periodic_tick: float = 0.0
var attack_variant: int = 0
var ward_life: float = 0.0
var guard_open: float = 0.0
var recovery: float = 0.0
## Transient drawing state. It does not participate in gameplay or persistence.
var presentation_state: String = ""
var presentation_elapsed: float = 0.0
var presentation_duration: float = 0.0

func set_presentation_state(state: String, duration: float = 0.3) -> void:
	if not AnimationArt.STATE_PRIORITY.has(state) or duration <= 0.0:
		return
	if presentation_duration > 0.0 and int(AnimationArt.STATE_PRIORITY[state]) < int(AnimationArt.STATE_PRIORITY.get(presentation_state, 0)):
		return
	presentation_state = state
	presentation_elapsed = 0.0
	presentation_duration = duration
	queue_redraw()

func tick(delta: float) -> void:
	if not enemy: texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	guard_open = maxf(0, guard_open - delta)
	recovery = maxf(0, recovery - delta)
	chain_window = maxf(0,chain_window-delta)
	counter_window = maxf(0,counter_window-delta)
	if chain_window <= 0: chain_count = 0
	animation_time += delta
	if presentation_duration > 0.0:
		presentation_elapsed += delta
		if presentation_elapsed >= presentation_duration:
			presentation_state = ""
			presentation_elapsed = 0.0
			presentation_duration = 0.0
	skill_cooldown = maxf(0.0, skill_cooldown - delta)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	dodge_cooldown = maxf(0.0, dodge_cooldown - delta)
	hurt_flash = maxf(0.0, hurt_flash - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	ai_timer -= delta
	for key in statuses.keys():
		statuses[key] = float(statuses[key]) - delta
		if float(statuses[key]) <= 0.0:
			statuses.erase(key)
	if not defeated and not enemy:
		mp = minf(max_mp, mp + delta * (2.8 if active else 2.0))
		ultimate_charge = minf(100.0, ultimate_charge + delta * 0.45)
	periodic_tick += delta
	queue_redraw()

func _draw() -> void:
	if defeated:
		if not enemy:
			draw_circle(Vector2(0, -4), 14, Color(0.3, 0.3, 0.4, 0.42))
			draw_line(Vector2(-7, -10), Vector2(7, 4), Color(0.9, 0.6, 0.5), 3)
			draw_line(Vector2(7, -10), Vector2(-7, 4), Color(0.9, 0.6, 0.5), 3)
		return
	if statuses.has("invisible"):
		modulate.a = 0.4
	else:
		modulate.a = 1.0
	if enemy:
		if not AnimationArt.draw_actor(self, self):
			Art.draw_enemy(self, Vector2.ZERO, enemy_kind, animation_time, hurt_flash > 0.0, boss)
		if enemy_kind == "brute" and guard_open <= 0 and not statuses.has("stun") and not statuses.has("freeze"):
			# The shield faces the same direction used by the damage test.
			draw_arc(Vector2(0,-15), 30, facing.angle()-1.15, facing.angle()+1.15, 20, Color("152e3d"), 7)
			draw_arc(Vector2(0,-15), 30, facing.angle()-1.15, facing.angle()+1.15, 20, Color("edce8b"), 3)
		if guard_open > 0 and enemy_kind == "brute":
			draw_arc(Vector2(0,-15), 30, 0, TAU, 24, Color("9ce3d6",0.6), 1.5)
		if bool(definition.get("elite",false)):
			draw_arc(Vector2(0,-20),25,0,TAU,24,Color("eac076"),1.5)
			draw_colored_polygon(PackedVector2Array([Vector2(-5,-58),Vector2(0,-64),Vector2(5,-58),Vector2(0,-52)]),Color("edca89"))
		if hp < max_hp or boss or bool(definition.get("elite",false)):
			var width: float = 54.0 if boss else 30.0
			var top: float = -104.0 if boss else -47.0
			draw_rect(Rect2(-width / 2.0, top, width, 4), Color("172331"))
			draw_rect(Rect2(-width / 2.0, top, width * clampf(hp / max_hp, 0, 1), 4), Color("fb776f") if not boss else Color("d695ff"))
	else:
		if not AnimationArt.draw_actor(self, self):
			Art.draw_character(self, Vector2.ZERO, definition, animation_time * (1.8 if velocity.length() > 5 else 0.25), facing, active)
		if hurt_flash > 0.0:
			draw_arc(Vector2(0, -13), 17, 0, TAU, 20, Color(1, 0.45, 0.45, 0.8), 2)
	if statuses.has("shield") or invulnerable > 0.0:
		draw_arc(Vector2(0, -12), 22 if not boss else 42, 0, TAU, 24, Color(0.35, 0.8, 1.0, 0.65), 2)
	if statuses.has("poison"):
		draw_circle(Vector2(-12, -27), 3, Color("a5df72"))
	if statuses.has("freeze") or statuses.has("root"):
		draw_arc(Vector2(0, -4), 20, 0, TAU, 6, Color("99e6ff"), 2)
	if statuses.has("empower") or statuses.has("frenzy"):
		draw_arc(Vector2(0, -6), 18, animation_time, animation_time + PI * 1.4, 20, Color("ffc47e"), 2)
