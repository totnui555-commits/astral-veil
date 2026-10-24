extends RefCounted
class_name VisualInteractables
## Four opening maps only. Positions and interaction state are owned by World.
## An original imagegen atlas is packed at gameplay pixel size; source is retained outside runtime.

const ATLAS: Texture2D = preload("res://art/vertical/interactables/astral_objects.png")
const INK: Color = Color("10252b")
const GOLD: Color = Color("e9ce92")
const REGIONS: Dictionary = {
	"chest_closed": Rect2(0, 0, 128, 128),
	"chest_open": Rect2(128, 0, 128, 128),
	"fire_a": Rect2(256, 0, 128, 128),
	"fire_b": Rect2(384, 0, 128, 128),
	"rune_dormant": Rect2(0, 128, 128, 128),
	"rune_active": Rect2(128, 128, 128, 128),
	"gate_dormant": Rect2(256, 128, 128, 128),
	"gate_active": Rect2(384, 128, 128, 128),
}
const ANCHORS: Dictionary = {
	"chest_closed": Vector2(64, 120),
	"chest_open": Vector2(64, 120),
	"fire_a": Vector2(64, 120),
	"fire_b": Vector2(64, 120),
	"rune_dormant": Vector2(64, 120),
	"rune_active": Vector2(64, 120),
	"gate_dormant": Vector2(64, 120),
	"gate_active": Vector2(64, 120),
}

class ObjectLayer extends Node2D:
	var world: Node2D
	var kind: String
	var identity: String
	var index: int
	var refresh: float = 0.0
	func _process(delta: float) -> void:
		refresh-=delta
		if refresh<=0:
			refresh=0.1
			queue_redraw()
	func _draw() -> void:
		if not is_instance_valid(world): return
		draw_set_transform(Vector2(0,2),0,Vector2(1,.3))
		draw_circle(Vector2.ZERO,32 if kind=="gate" else 21,Color(.01,.025,.035,.34))
		draw_set_transform(Vector2.ZERO)
		var key: String
		var prompt: Vector2
		var colour=VisualInteractables.GOLD
		var show_prompt=true
		match kind:
			"return":
				key="gate_active"
				prompt=Vector2(0,38)
				colour=Color("a5e4dc")
			"gate":
				key="gate_active" if world.ready_emitted else "gate_dormant"
				prompt=Vector2(0,38)
				colour=VisualInteractables.GOLD if world.ready_emitted else Color("8d839e")
			"fire":
				key="fire_a" if int(world.elapsed*5)%2==0 else "fire_b"
				prompt=Vector2(0,35)
				colour=Color("b5d7ba")
			"rune":
				var active=world.activated_sigils.has(index)
				key="rune_active" if active else "rune_dormant"
				prompt=Vector2(0,-64)
				colour=Color("cfbfdd")
				show_prompt=not active
			_:
				var opened=world.opened_chests.has(identity)
				key="chest_open" if opened else "chest_closed"
				prompt=Vector2(0,-54)
				show_prompt=not opened
		VisualInteractables._object(self,key,Vector2.ZERO,1.0)
		if kind == "return" and world.draw_font != null:
			draw_string(world.draw_font, Vector2(-42,-94), world._t("To Hearthwell", "กลับฮาร์ธเวล"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, colour)
		if show_prompt: VisualInteractables._prompt(self,world,prompt,colour)

static func create_layers(world: Node2D) -> void:
	var previous=world.get_node_or_null("AstralInteractables")
	if previous:
		world.remove_child(previous)
		previous.queue_free()
	if not int(world.map_data.get("id",-1)) in [0,1,2,3]: return
	var group=Node2D.new()
	group.name="AstralInteractables"
	world.add_child(group)
	var records=[]
	var exit: Array=world.map_data.get("exit",[1450,500])
	records.append({"kind":"gate","pos":Vector2(exit[0],exit[1])+Vector2(0,12)})
	var return_gate: Dictionary = world.map_data.get("return_gate",{})
	if not return_gate.is_empty():
		records.append({"kind":"return","pos":Vector2(return_gate.pos[0],return_gate.pos[1])+Vector2(0,12)})
	if not world.map_data.get("no_camp", false):
		records.append({"kind":"fire","pos":world.camp_position+Vector2(0,4)})
	var sigils: Array=world.map_data.get("sigils",[])
	for index in range(sigils.size()):
		records.append({"kind":"rune","pos":Vector2(sigils[index][0],sigils[index][1])+Vector2(0,7),"index":index})
	for chest in world.map_data.get("chests",[]):
		records.append({"kind":"chest","pos":Vector2(chest.pos[0],chest.pos[1])+Vector2(0,5),"id":str(chest.id)})
	for entry in records:
		var layer=ObjectLayer.new()
		layer.world=world
		layer.kind=entry.kind
		layer.identity=entry.get("id","")
		layer.index=entry.get("index",0)
		layer.position=entry.pos
		layer.z_index=int(layer.position.y)
		group.add_child(layer)


static func _object(canvas: CanvasItem, key: String, point: Vector2, scale_factor: float, tint: Color = Color.WHITE) -> void:
	var region: Rect2 = REGIONS[key]
	var anchor: Vector2 = ANCHORS[key]
	canvas.draw_texture_rect_region(ATLAS, Rect2(point.round() - anchor * scale_factor, region.size * scale_factor), region, tint)


static func _prompt(canvas: CanvasItem, stage: Node2D, point: Vector2, colour: Color) -> void:
	if stage.draw_font == null:
		return
	var box: Rect2 = Rect2(point.round() - Vector2(10, 14), Vector2(20, 20))
	canvas.draw_rect(box.grow(2), Color(INK, 0.95))
	canvas.draw_rect(box, Color("243d3d", 0.92))
	canvas.draw_rect(box, Color(colour, 0.85), false, 1)
	canvas.draw_line(box.position + Vector2(4, -2), box.position + Vector2(16, -2), GOLD, 1)
	canvas.draw_string(stage.draw_font, point.round() + Vector2(-4, 1), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, colour)


static func draw_objects(canvas: CanvasItem, stage: Node2D) -> void:
	if stage.has_node("AstralInteractables"): return
	var exit_data: Array = stage.map_data.get("exit", [1450, 500])
	var exit_point: Vector2 = Vector2(float(exit_data[0]), float(exit_data[1]))
	var gate_colour: Color = GOLD if stage.ready_emitted else Color("8d839e")
	var gate_key: String = "gate_active" if stage.ready_emitted else "gate_dormant"
	_object(canvas, gate_key, exit_point + Vector2(0, 12), 1.0)
	_prompt(canvas, stage, exit_point + Vector2(0, 50), gate_colour)
	# Alternating authored fire silhouettes, no procedural triangle flame.
	var flame_key: String = "fire_a" if int(stage.elapsed * 5) % 2 == 0 else "fire_b"
	_object(canvas, flame_key, stage.camp_position + Vector2(0, 4), 1.0)
	_prompt(canvas, stage, stage.camp_position + Vector2(0, 39), Color("b5d7ba"))
	var sigils: Array = stage.map_data.get("sigils", [])
	for index in range(sigils.size()):
		var values: Array = sigils[index]
		var point: Vector2 = Vector2(float(values[0]), float(values[1]))
		var active: bool = stage.activated_sigils.has(index)
		_object(canvas, "rune_active" if active else "rune_dormant", point + Vector2(0, 7), 1.0)
		if not active:
			_prompt(canvas, stage, point + Vector2(0, -57), Color("cfbfdd"))
	for chest in stage.map_data.get("chests", []):
		var point: Vector2 = Vector2(float(chest.pos[0]), float(chest.pos[1]))
		var opened: bool = stage.opened_chests.has(str(chest.id))
		_object(canvas, "chest_open" if opened else "chest_closed", point + Vector2(0, 5), 1.0)
		if not opened:
			_prompt(canvas, stage, point + Vector2(0, -49), GOLD)
