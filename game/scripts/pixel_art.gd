extends RefCounted
class_name PixelArt
## Runtime adapter for the project's original, committed pixel atlases.
## Asset loading and prop placement happen once, never once per draw frame.

static var _textures: Dictionary = {}
static var _missing: Dictionary = {}
const VerticalEnvironment = preload("res://scripts/visual_environment.gd")
const VerticalAnimation = preload("res://scripts/visual_animation.gd")
const THEMES: Array[String] = ["classroom", "sanctuary", "forest", "tower", "ember", "archive", "coast", "frost", "void"]


static func _texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	if _missing.has(path):
		return null
	if ResourceLoader.exists(path):
		var loaded: Texture2D = load(path) as Texture2D
		if loaded != null:
			_textures[path] = loaded
			return loaded
	_missing[path] = true
	push_warning("Pixel atlas unavailable: " + path)
	return null


static func portrait_texture(definition: Dictionary) -> Texture2D:
	var id: String = str(definition.get("id", "n01"))
	var texture: Texture2D = _texture("res://art/portraits/" + id + ".png")
	return texture if texture != null else _texture("res://art/portraits/n01.png")


static func draw_character(canvas: CanvasItem, pos: Vector2, definition: Dictionary, frame: float, facing: Vector2, active: bool = false, scale_factor: float = 1.0) -> void:
	if VerticalAnimation.draw_definition(canvas, pos, definition, frame, facing, scale_factor, active):
		return
	var texture: Texture2D = _texture("res://art/sprites/" + str(definition.get("id", "n01")) + ".png")
	if texture == null:
		texture = _texture("res://art/sprites/n01.png")
	var scale: float = maxf(0.1, scale_factor) * 0.8
	_shadow(canvas, pos, Vector2(13, 5) * scale_factor, Color(0.025, 0.045, 0.07, 0.48))
	if active:
		canvas.draw_arc(pos + Vector2(0, -2), 15 * scale_factor, 0, TAU, 24, Color("bde9dd"), 1.0)
		canvas.draw_colored_polygon(PackedVector2Array([
			pos + Vector2(0, -45) * scale_factor,
			pos + Vector2(3, -49) * scale_factor,
			pos + Vector2(-3, -49) * scale_factor,
		]), Color("f5dda2"))
	if texture == null:
		return
	var frame_index: int = posmod(int(floor(frame * 5.0)), 4)
	var direction: float = -1.0 if facing.x < -0.1 else 1.0
	canvas.draw_set_transform(pos.round(), 0.0, Vector2(direction, 1.0))
	canvas.draw_texture_rect_region(texture, Rect2(Vector2(-20, -44) * scale, Vector2(40, 48) * scale), Rect2(frame_index * 40, 0, 40, 48))
	canvas.draw_set_transform(Vector2.ZERO)


static func draw_enemy(canvas: CanvasItem, pos: Vector2, kind: String, frame: float, flash: bool = false, boss: bool = false) -> void:
	var texture: Texture2D = _texture("res://art/enemies/" + kind + ".png")
	if texture == null:
		texture = _texture("res://art/enemies/stalker.png")
	if texture == null:
		return
	var scale: float = 0.64 if boss else 0.8
	var size: Vector2 = texture.get_size() * scale
	_shadow(canvas, pos, Vector2(34, 11) if boss else Vector2(14, 5), Color(0.015, 0.035, 0.06, 0.48))
	var bob: float = roundf(sin(frame * (2.4 if boss else 4.0)) * (2.0 if boss else 1.0))
	var feet: float = 10.0 * scale
	var tint: Color = Color(1.8, 1.35, 1.3, 1.0) if flash else Color.WHITE
	canvas.draw_texture_rect(texture, Rect2(pos.round() + Vector2(-size.x * 0.5, -size.y + feet + bob), size), false, tint)
	if boss:
		var glow: Color = Color("b9dfee")
		glow.a = 0.18 + sin(frame * 2.0) * 0.05
		canvas.draw_arc(pos + Vector2(0, -3), 32.0, frame * 0.2, frame * 0.2 + TAU, 32, glow, 1.0)


static func _theme(map_data: Dictionary) -> String:
	var value: String = str(map_data.get("theme", "forest"))
	return value if THEMES.has(value) else "forest"


static func _prop_texture(prop: Dictionary, theme: String, index: int) -> Texture2D:
	var kind: String = str(prop.get("kind", "rock"))
	var name: String = "tree_%s_%d" % [theme, index % 3] if kind == "tree" else kind
	return _texture("res://art/props/" + name + ".png")


static func _prop_offset(texture: Texture2D, kind: String) -> Vector2:
	var margin: float = 14.0 if kind in ["tree", "house"] else 8.0
	if kind == "water":
		return -texture.get_size() * 0.5
	return Vector2(-texture.get_width() * 0.5, -texture.get_height() + margin)


static func create_environment_props(world: Node2D, map_data: Dictionary) -> Array[Node2D]:
	if VerticalEnvironment.supports(map_data):
		return VerticalEnvironment.create_props(world, map_data)
	var group: Node2D = Node2D.new()
	group.name = "AstralEnvironmentProps"
	world.add_child(group)
	var nodes: Array[Node2D] = []
	var theme: String = _theme(map_data)
	var index: int = 0
	for value in map_data.get("props", []):
		var prop: Dictionary = value
		var texture: Texture2D = _prop_texture(prop, theme, index)
		index += 1
		if texture == null:
			continue
		var point: Array = prop.get("pos", [0, 0])
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(float(point[0]), float(point[1])).round()
		sprite.offset = _prop_offset(texture, str(prop.get("kind", "rock")))
		# Water is terrain; every other prop shares the actors' foot-depth ordering.
		sprite.z_index = 0 if str(prop.get("kind", "")) == "water" else int(sprite.position.y)
		group.add_child(sprite)
		nodes.append(sprite)
	return nodes


static func draw_environment(canvas: CanvasItem, map_data: Dictionary, time: float) -> void:
	if VerticalEnvironment.supports(map_data):
		VerticalEnvironment.draw_ground(canvas, map_data, time)
		return
	var theme: String = _theme(map_data)
	var ground: Texture2D = _texture("res://art/grounds/" + theme + ".png")
	if ground != null:
		canvas.draw_texture(ground, Vector2.ZERO)
	else:
		canvas.draw_rect(Rect2(0, 0, 1600, 1000), Color("182a38"))
	# Existing worlds can use the renderer without creating the optional depth layers.
	if not canvas.has_node("AstralEnvironmentProps"):
		var index: int = 0
		for prop in map_data.get("props", []):
			var texture: Texture2D = _prop_texture(prop, theme, index)
			index += 1
			if texture == null:
				continue
			var point: Array = prop.get("pos", [0, 0])
			var pos: Vector2 = Vector2(float(point[0]), float(point[1]))
			canvas.draw_texture(texture, pos.round() + _prop_offset(texture, str(prop.get("kind", "rock"))))
	# Small pixel motes add life without putting bright textures under combat telegraphs.
	var mote: Color = Color("ebc888") if theme == "ember" else Color("aedbd5")
	mote.a = 0.22
	if theme in ["forest", "sanctuary", "ember", "void", "frost"]:
		for index in range(20):
			var x: float = fposmod(float(index * 163 + 73) + sin(time * 0.25 + index) * 18, 1536) + 32
			var y: float = fposmod(float(index * 107 + 29) - time * (6.0 if theme == "frost" else 2.0), 920) + 40
			canvas.draw_rect(Rect2(Vector2(x, y).round(), Vector2(2, 2)), mote)


static func draw_effect(canvas: CanvasItem, pos: Vector2, kind: String, radius: float, color: Color, progress: float) -> void:
	var t: float = clampf(progress, 0.0, 1.0)
	var visible: Color = color
	visible.a *= 1.0 - t
	var core: Color = Color("fff4d4")
	core.a = visible.a
	var r: float = maxf(1.0, radius)
	match kind:
		"slash":
			var sweep: float = t * PI * 0.85
			canvas.draw_arc(pos + Vector2(0, -12), r * (0.6 + t * 0.25), -PI * 0.8 + sweep, -PI * 0.18 + sweep, 12, visible, 4.0)
			canvas.draw_arc(pos + Vector2(0, -12), r * (0.52 + t * 0.25), -PI * 0.74 + sweep, -PI * 0.25 + sweep, 12, core, 2.0)
		"lightning":
			var points: PackedVector2Array = PackedVector2Array()
			for index in range(8):
				var offset: float = sin(index * 2.7 + floorf(t * 10)) * r * 0.16 if index > 0 and index < 7 else 0.0
				points.append((pos + Vector2(offset, -r + float(index) / 7.0 * r * 1.3)).round())
			canvas.draw_polyline(points, visible, 5.0)
			canvas.draw_polyline(points, core, 2.0)
		"heal":
			canvas.draw_arc(pos, r * (0.4 + t * 0.45), 0, TAU, 20, visible, 2.0)
			for index in range(5):
				var point: Vector2 = pos + Vector2(sin(index * 2.4) * r * 0.45, -12 - t * 35 - float(index % 3) * 8)
				canvas.draw_rect(Rect2(point.round() - Vector2(1, 5), Vector2(2, 10)), visible)
				canvas.draw_rect(Rect2(point.round() - Vector2(5, 1), Vector2(10, 2)), visible)
		"dodge":
			for index in range(5):
				var point: Vector2 = pos + Vector2(-float(index) * 5 - t * 12, -6 - float(index % 2) * 8)
				canvas.draw_rect(Rect2(point.round(), Vector2(8, 2)), visible)
		"burst":
			canvas.draw_arc(pos, r * (0.15 + t * 0.9), 0, TAU, 16, visible, 2.0)
			for index in range(12):
				var direction: Vector2 = Vector2.from_angle(index * TAU / 12.0)
				var point: Vector2 = pos + direction * r * (0.2 + t * 0.85)
				canvas.draw_line(point.round(), (point + direction * 6).round(), visible, 2.0)
				canvas.draw_rect(Rect2(point.round() - Vector2(1, 1), Vector2(3, 3)), core)
		_:
			canvas.draw_arc(pos, r * (0.25 + t * 0.75), 0, TAU, 24, visible, 2.0)
			canvas.draw_arc(pos, r * (0.15 + t * 0.5), t * PI, t * PI + TAU, 6, visible, 1.0)


static func _shadow(canvas: CanvasItem, pos: Vector2, size: Vector2, color: Color) -> void:
	canvas.draw_set_transform(pos.round(), 0, Vector2(1, size.y / maxf(1, size.x)))
	canvas.draw_circle(Vector2.ZERO, size.x, color)
	canvas.draw_set_transform(Vector2.ZERO)
