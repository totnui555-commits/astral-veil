extends Node2D
class_name CombatPresentation
## Presentation only. Combat authority remains in World and CombatSkills.
## One small cached atlas, bounded drawing, no particles or shader requirements.

const SIGNATURE: Texture2D = preload("res://art/vertical/vfx/signature.png")
const SIGNATURE_ROWS = {"crescent":0,"nova":1,"aegis":2,"skybreak":3}
const CELLS: Texture2D = preload("res://art/vertical/vfx/combat_cels.png")
const ROWS: Dictionary = {"slash": 0, "impact": 1, "burst": 2, "ring": 3, "heal": 4, "dodge": 5, "lightning": 6, "bolt": 7, "arrow": 8, "hostile": 9}
const INK: Color = Color("11171e")
const DANGER: Color = Color("f58461")
const DANGER_EDGE: Color = Color("ffd4a2")
const MAX_EFFECT_DRAWS: int = 64
var world: Node2D


func _ready() -> void:
	name = "AstralCombatPresentation"
	z_index = 4095
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world = get_parent() as Node2D
	var signature_layer := SignatureLayer.new()
	signature_layer.z_index = -1
	add_child(signature_layer)


func _process(_delta: float) -> void:
	if is_instance_valid(world):
		queue_redraw()


static func cel(canvas: CanvasItem, kind: String, point: Vector2, diameter: float, frame: int, tint: Color, angle: float = 0.0, stretch: Vector2 = Vector2.ONE) -> void:
	var row: int = int(ROWS.get(kind, 3))
	var size: Vector2 = Vector2.ONE * maxf(2.0, diameter) * stretch
	canvas.draw_set_transform(point.round(), angle)
	canvas.draw_texture_rect_region(CELLS, Rect2(-size * 0.5, size), Rect2(clampi(frame, 0, 7) * 64, row * 64, 64, 64), tint)
	canvas.draw_set_transform(Vector2.ZERO)


static func draw_floor(canvas: CanvasItem, stage: Node2D) -> void:
	# A restrained inset pattern identifies friendly ground. The edge matches
	# the gameplay radius; ornamental bits never imply an additional hit area.
	for zone in stage.zones:
		var colour: Color = Color("ebbd73")
		match str(zone.kind):
			"poison", "roots": colour = Color("9cdc91")
			"frost": colour = Color("9ee9ef")
			"gravity", "glyph": colour = Color("c4a5ef")
		var radius: float = float(zone.radius)
		canvas.draw_circle(zone.pos, radius, Color("081b20", 0.34))
		canvas.draw_circle(zone.pos, radius - 3, Color(colour, 0.09))
		canvas.draw_arc(zone.pos, radius, 0, TAU, 48, Color("102626", 0.82), 5)
		canvas.draw_arc(zone.pos, radius - 1, 0, TAU, 48, Color(colour, 0.66), 2)
		cel(canvas, "ring", zone.pos, radius * 1.75, int(stage.elapsed * 8) % 8, Color(colour, 0.25))
	for enemy in stage.enemies:
		if not is_instance_valid(enemy) or enemy.defeated:
			continue
		if enemy.boss and enemy.boss_engaged:
			var pulse: float = 0.12 + sin(stage.elapsed * 1.8) * 0.035
			cel(canvas, "ring", enemy.position, 116.0, int(stage.elapsed * 4) % 8, Color("a5c9bc", pulse))
		if stage.seal_active(enemy):
			canvas.draw_arc(enemy.position,72,0,TAU,64,Color("b394f4"),4)
			for i in range(3):
				_diamond(canvas,enemy.position+Vector2.from_angle(stage.elapsed+i*TAU/3)*72,8,Color("fff1b5"))
			canvas.draw_string(stage.draw_font,enemy.position+Vector2(-85,-88),"E · "+stage._t("Unseal core","แก้ผนึกแกนกลาง"),HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("fff1b5"))
		if enemy.windup > 0:
			draw_telegraph(canvas, enemy, stage._attack_radius(enemy), stage.elapsed)


static func _diamond(canvas: CanvasItem, point: Vector2, size: float, colour: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([point + Vector2(0, -size), point + Vector2(size, 0), point + Vector2(0, size), point + Vector2(-size, 0)]), colour)


static func _lane(canvas: CanvasItem, start: Vector2, end: Vector2, width: float, progress: float, phase: float) -> void:
	var direction: Vector2 = start.direction_to(end)
	var normal: Vector2 = direction.orthogonal()
	var vertices: PackedVector2Array = PackedVector2Array([start + normal * width * 0.5, end + normal * width * 0.5, end - normal * width * 0.5, start - normal * width * 0.5])
	canvas.draw_colored_polygon(vertices, Color("180e14", 0.68))
	canvas.draw_colored_polygon(vertices, Color(DANGER, 0.15 + progress * 0.22))
	var border: PackedVector2Array = vertices.duplicate()
	border.append(vertices[0])
	canvas.draw_polyline(border, Color(INK, 0.95), 5)
	canvas.draw_polyline(border, Color(DANGER_EDGE, 0.82 + sin(phase * 12) * 0.12), 2)
	var distance: float = start.distance_to(end)
	for i in range(1, maxi(2, int(distance / 48))):
		var centre: Vector2 = start + direction * (i * 48)
		var size: float = minf(7, width * 0.25)
		canvas.draw_polyline(PackedVector2Array([centre - direction * 4 + normal * size, centre + direction * 4, centre - direction * 4 - normal * size]), Color(DANGER_EDGE, 0.40 + progress * 0.36), 2)


static func draw_telegraph(canvas: CanvasItem, enemy: Node2D, radius: float, time: float) -> void:
	var progress: float = clampf(1.0 - enemy.windup / maxf(0.001, enemy.windup_total), 0, 1)
	var point: Vector2 = enemy.target_point
	var edge: Color = Color(DANGER_EDGE, 0.83 + sin(time * 12) * 0.12)
	match int(enemy.attack_pattern):
		0:
			canvas.draw_circle(point, radius, Color("1c0e14", 0.65))
			canvas.draw_circle(point, radius - 3, Color(DANGER, 0.16 + progress * 0.22))
			canvas.draw_arc(point, radius, 0, TAU, 64, Color(INK, 0.95), 7)
			canvas.draw_arc(point, radius, 0, TAU, 64, edge, 3)
			canvas.draw_arc(point, radius - 5, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, Color(DANGER, 0.85), 3)
			cel(canvas, "ring", point, radius * 1.52, int(time * 8) % 8, Color(DANGER, 0.28))
			for i in range(4):
				var direction: Vector2 = Vector2.from_angle(i * PI * 0.5)
				canvas.draw_line(point + direction * (radius - 11), point + direction * (radius - 4), edge, 3)
			_diamond(canvas, point, 6, Color(INK, 0.95))
			_diamond(canvas, point, 3, edge)
		1:
			_lane(canvas, enemy.position, point, 18, progress, time)
			cel(canvas, "hostile", enemy.position + Vector2(0, -14), 38, int(time * 12) % 8, Color(DANGER, 0.5 + progress * 0.4), enemy.position.direction_to(point).angle())
		2:
			canvas.draw_circle(enemy.position, 52, Color("1c0e14", 0.55))
			canvas.draw_arc(enemy.position, 52, 0, TAU, 48, Color(INK, 0.95), 7)
			canvas.draw_arc(enemy.position, 52, 0, TAU, 48, edge, 3)
			cel(canvas, "ring", enemy.position, 92, int(time * 10) % 8, Color(DANGER, 0.35 + progress * 0.25))
			var count: int = 8 + enemy.boss_phase * 2 if enemy.boss else 6
			for i in range(count):
				var direction: Vector2 = Vector2.from_angle(TAU * i / count + enemy.attack_variant * 0.35)
				_lane(canvas, enemy.position + direction * 53, enemy.position + direction * 108, 10, progress, time)
		3:
			_lane(canvas, point - Vector2(0, 210), point + Vector2(0, 210), 52, progress, time)
			_lane(canvas, point - Vector2(210, 0), point + Vector2(210, 0), 52, progress, time)
			_diamond(canvas, point, 9, INK)
			_diamond(canvas, point, 5, edge)
		5:
			canvas.draw_line(enemy.position, point, Color("16112c",0.9), 7)
			canvas.draw_line(enemy.position, point, Color("bd9aff",0.7), 3)
			canvas.draw_arc(point, 38, 0, TAU, 40, Color("bd9aff"), 3)
			canvas.draw_arc(enemy.position, 30, -PI/2, -PI/2 + TAU*progress, 40, Color("e9dbff"), 4)
			_diamond(canvas, enemy.position + Vector2(0,-56), 8, Color("bd9aff"))
		4:
			var direction: Vector2 = enemy.position.direction_to(point)
			_lane(canvas, enemy.position, enemy.position + direction * 370, 72, progress, time)


func _draw() -> void:
	if not is_instance_valid(world) or world.map_data.is_empty():
		return
	var start: int = maxi(0, world.effects.size() - MAX_EFFECT_DRAWS)
	for index in range(start, world.effects.size()):
		_draw_effect(world.effects[index])
	for bolt in world.projectiles:
		_draw_projectile(bolt)
	for summon in world.summons:
		var point: Vector2 = summon.pos
		if summon.kind == "turret":
			cel(self, "ring", point, 36, int(world.elapsed * 5) % 8, Color("dfc893", 0.7))
			draw_rect(Rect2(point - Vector2(7, 10), Vector2(14, 18)), INK)
			draw_rect(Rect2(point - Vector2(5, 8), Vector2(10, 14)), Color("658ca0"))
			_diamond(self, point + Vector2(0, -11), 5, Color("e8ddaf"))
		else:
			point.y -= 17 + sin(world.elapsed * 5 + summon.offset) * 4
			cel(self, "bolt", point, 31, int(world.elapsed * 9) % 8, Color("afefe4"), -PI * 0.5)
	for loot in world.pickups:
		var point: Vector2 = loot.pos + Vector2(0, -6 + sin(world.elapsed * 4) * 3)
		var awarded: bool = bool(loot.get("awarded",false))
		var hue: Color = Color("c193f2") if str(DB.item(loot.item).get("rarity","")) == "epic" else Color("8cdec9")
		if awarded:
			draw_line(point,point+Vector2(0,-72),Color(hue,0.35),8)
			draw_line(point,point+Vector2(0,-72),Color(hue,0.85),2)
			cel(self,"ring",point,34,int(world.elapsed*8)%8,hue)
			var label: String = DB.localized(DB.item(loot.item).get("name",loot.item))
			var font: Font = world.draw_font
			var tw: float = font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
			draw_style_box(_loot_style(),Rect2(point+Vector2(-tw/2-7,-99),Vector2(tw+14,23)))
			draw_string(font,point+Vector2(-tw/2,-82),label,HORIZONTAL_ALIGNMENT_LEFT,-1,15,hue)
		_diamond(self, point, 7, INK)
		_diamond(self, point + Vector2(0, -1), 5, Color("b48c48"))
		_diamond(self, point + Vector2(-1, -2), 3, Color("f5df9f"))
	for entry in world.floating_text:
		if world.draw_font != null:
			var alpha: float = minf(1, float(entry.life) * 4)
			var width: float = world.draw_font.get_string_size(entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			var point: Vector2 = entry.pos - Vector2(width * 0.5, 0)
			draw_string_outline(world.draw_font, point, entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 3, Color("111019", alpha))
			draw_string(world.draw_font, point, entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(entry.color, alpha))


func _draw_effect(entry: Dictionary) -> void:
	var progress: float = clampf(1.0 - float(entry.life) / maxf(0.001, float(entry.total)), 0, 1)
	var kind: String = str(entry.kind)
	var colour: Color = entry.color
	var radius: float = float(entry.radius)
	var angle: float = float(entry.get("angle", 0))
	var point: Vector2 = entry.pos
	var size: float = radius * 2.15
	var stretch: Vector2 = Vector2.ONE
	if kind == "slash":
		point.y -= 12
		size = radius * 2.3
	elif kind == "heal":
		point.y -= 15
		size = maxf(44, radius * 1.8)
	elif kind == "dodge":
		point.y -= 12
		size = radius * 2.4
	elif kind == "lightning":
		point.y -= radius * 0.25
		size = radius * 1.55
		stretch = Vector2(0.46, 1.0)
	elif kind == "impact":
		point.y -= 10
		size = maxf(30, radius * 2)
	colour.a *= minf(1.0, float(entry.life) * 8)
	if SIGNATURE_ROWS.has(kind):
		for i in range(8):
			var direction: Vector2 = Vector2.from_angle(TAU*i/8+angle)
			var end: Vector2 = point+direction*radius*(0.3+progress*0.65)
			draw_line(end-direction*8*(1-progress),end,Color(colour,colour.a*(1-progress)),2)
	else:
		cel(self, kind, point, size, mini(7, int(progress * 8)), colour, angle, stretch)


func _draw_projectile(bolt: Dictionary) -> void:
	var direction: Vector2 = bolt.velocity.normalized()
	var colour: Color = DANGER if bool(bolt.enemy) else Color(bolt.color).lerp(Color("d6eed3"), 0.16)
	var kind: String = "hostile" if bool(bolt.enemy) else "bolt"
	if not bolt.enemy and is_instance_valid(bolt.source) and str(bolt.source.definition.get("weapon", "")) == "ranged":
		kind = "arrow"
		colour = Color("efda9b")
	# Tail, ink edge and white centre preserve clarity against bright terrain.
	draw_line(bolt.pos - direction * 20, bolt.pos, Color(INK, 0.7), 6)
	draw_line(bolt.pos - direction * 18, bolt.pos, Color(colour, 0.45), 3)
	cel(self, kind, bolt.pos - direction * 5, 38 if bolt.enemy else 33, int(world.elapsed * 14) % 8, colour, direction.angle())

static func _loot_style() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color("0c1925e8")
	box.set_corner_radius_all(3)
	return box

class SignatureLayer extends Node2D:
	## A separate canvas material feathers only the painted FX, never HUD/text.
	var host
	func _ready() -> void:
		host = get_parent()
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var shader := Shader.new()
		shader.code = """shader_type canvas_item;
render_mode unshaded;
void fragment() {
	vec2 local_uv = fract(UV * 4.0);
	float radius = length(local_uv * 2.0 - 1.0);
	COLOR.a *= 1.0 - smoothstep(0.55, 0.86, radius);
}
"""
		var blend := ShaderMaterial.new()
		blend.shader = shader
		material = blend
	func _process(_delta: float) -> void: queue_redraw()
	func _draw() -> void:
		if not is_instance_valid(host) or not is_instance_valid(host.world): return
		var stage = host.world
		for index in range(maxi(0,stage.effects.size()-CombatPresentation.MAX_EFFECT_DRAWS),stage.effects.size()):
			var entry: Dictionary = stage.effects[index]
			var kind: String = str(entry.kind)
			if not CombatPresentation.SIGNATURE_ROWS.has(kind): continue
			var progress: float = clampf(1.0-float(entry.life)/maxf(0.001,float(entry.total)),0,1)
			var diameter: float = float(entry.radius)*2.15*(0.65+0.35*sin(progress*PI))
			var colour: Color = entry.color
			var alpha: float = colour.a*minf(1.0,float(entry.life)*8)
			draw_set_transform(entry.pos,float(entry.get("angle",0)))
			draw_texture_rect_region(CombatPresentation.SIGNATURE,Rect2(Vector2.ONE*(-diameter/2),Vector2.ONE*diameter),Rect2(mini(3,int(progress*4))*192,int(CombatPresentation.SIGNATURE_ROWS[kind])*192,192,192),Color(1,1,1,alpha))
			draw_set_transform(Vector2.ZERO)
