extends RefCounted
class_name VeilUI

# Nocturne slate, restrained brass edges, mint selection.
# Shared Thai/English typography and illustrated action emblems.
const INK = Color("081318")
const PANEL = Color("10262aef")
const GOLD = Color("d9c396")
const WHITE = Color("f0eadb")
const MUTED = Color("9eafaa")
const TEAL = Color("78d3ba")
const RED = Color("ed947e")
const UI_PATH = "res://art/vertical/ui/"
static var textures: Dictionary = {}
static var body_font: Font
static var title_font: Font

static func texture(name: String) -> Texture2D:
	if not textures.has(name):
		var path = UI_PATH + name + ".png"
		if ResourceLoader.exists(path): textures[name] = load(path)
	return textures.get(name)

static var action_icons: Dictionary = {}
static func action_icon(action: String) -> Texture2D:
	var cells = {"attack":Vector2i(0,0),"heavy":Vector2i(1,0),"skill":Vector2i(2,0),"ultimate":Vector2i(3,0),"dodge":Vector2i(0,1),"potion":Vector2i(1,1),"interact":Vector2i(2,1),"tactics":Vector2i(3,1)}
	if not cells.has(action): return null
	if not action_icons.has(action):
		var atlas = texture("combat_icons")
		if atlas == null: return null
		var icon = AtlasTexture.new()
		icon.atlas = atlas
		var cell = Vector2(atlas.get_width()/4.0,atlas.get_height()/2.0)
		icon.region = Rect2(Vector2(cells[action])*cell,cell)
		icon.filter_clip = true
		action_icons[action] = icon
	return action_icons[action]

static func _material(name: String, padding: int = 18, corner: int = 25) -> StyleBox:
	var image = texture(name)
	if image == null:
		var fallback = StyleBoxFlat.new()
		fallback.bg_color = PANEL
		fallback.border_color = GOLD
		fallback.set_border_width_all(1)
		fallback.set_content_margin_all(padding)
		return fallback
	var s = StyleBoxTexture.new()
	s.texture = image
	s.texture_margin_left = corner
	s.texture_margin_right = corner
	s.texture_margin_top = mini(corner, image.get_height() / 2 - 1)
	s.texture_margin_bottom = s.texture_margin_top
	s.set_content_margin_all(padding)
	return s

# Shared hierarchy: quiet surfaces, a single brass edge, mint selection.
static func surface(fill: Color = PANEL, edge: Color = Color("405252"), padding: int = 14, radius: int = 3) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	style.shadow_color = Color("00000070")
	style.shadow_size = 3
	style.shadow_offset = Vector2(0,3)
	return style

static func panel_style() -> StyleBox:
	var style = surface(Color("0b1924fc"), Color("716954"), 24, 3)
	style.border_width_top = 2
	return style

static func card_style() -> StyleBox:
	return surface(Color("142633fa"), Color("34434a"), 14, 2)

static func button_style(state: String = "normal") -> StyleBox:
	var fill = Color("192831")
	var edge = Color("536068")
	match state:
		"hover":
			fill = Color("293a40")
			edge = GOLD
		"pressed", "selected":
			fill = Color("29423f")
			edge = TEAL
		"disabled":
			fill = Color("14212b")
			edge = Color("2b3b44")
	var style = surface(fill,edge,14,3)
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	style.shadow_size = 0
	return style

static func box(color: Color = PANEL, border: Color = Color("354958"), width: int = 1, radius: int = 4) -> StyleBox:
	# Unbordered fills serve bars and overlays, whose exact gameplay color matters.
	if width == 0 or color.a < .01:
		var flat = StyleBoxFlat.new()
		flat.bg_color = color
		flat.border_color = border
		flat.set_border_width_all(width)
		flat.set_corner_radius_all(radius)
		flat.set_content_margin_all(0)
		return flat
	return surface(color, border, 14, radius)

static func _fonts() -> void:
	if body_font != null: return
	var body = FontVariation.new()
	body.base_font = load("res://art/fonts/NotoSans-Regular.ttf")
	body.fallbacks = [load("res://art/fonts/NotoSansThai-Regular.ttf"), load("res://art/fonts/DejaVuSans.ttf")]
	body_font = body
	var title = FontVariation.new()
	title.base_font = load("res://art/fonts/NotoSerif-Regular.ttf")
	title.fallbacks = [load("res://art/fonts/NotoSansThai-Regular.ttf"), body]
	title_font = title

static func theme() -> Theme:
	_fonts()
	var t = Theme.new()
	t.default_font = body_font
	t.default_font_size = 16
	t.set_color("font_color", "Label", WHITE)
	t.set_color("font_shadow_color", "Label", Color("02090bbb"))
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_color("font_color", "Button", WHITE)
	t.set_color("font_hover_color", "Button", Color("fff6de"))
	t.set_color("font_pressed_color", "Button", TEAL)
	t.set_color("font_disabled_color", "Button", Color("728580"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(state, "Button", button_style(state))
	t.set_stylebox("focus", "Button", box(Color.TRANSPARENT, GOLD, 2, 2))
	t.set_stylebox("panel", "PanelContainer", card_style())
	t.set_stylebox("background", "ProgressBar", box(Color("071317"), Color("6e785f"), 0, 2))
	t.set_stylebox("fill", "ProgressBar", box(TEAL, Color.TRANSPARENT, 0, 2))
	t.set_color("font_color", "RichTextLabel", WHITE)
	t.set_stylebox("normal", "TextEdit", _material("card", 14, 27))
	t.set_stylebox("focus", "TextEdit", _material("panel", 14, 27))
	t.set_color("font_color", "TextEdit", WHITE)
	t.set_color("caret_color", "TextEdit", GOLD)
	t.set_color("selection_color", "TextEdit", Color("376f69"))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 12)
	t.set_constant("h_separation", "GridContainer", 10)
	t.set_constant("v_separation", "GridContainer", 10)
	var line = StyleBoxLine.new()
	line.color = Color("71684a")
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 8)
	for slider_type in ["HSlider", "HScrollBar", "VScrollBar"]:
		t.set_stylebox("scroll", slider_type, box(Color("071317"), Color.TRANSPARENT, 0, 2))
		t.set_stylebox("grabber", slider_type, box(Color("697f70"), Color.TRANSPARENT, 0, 2))
		t.set_stylebox("grabber_highlight", slider_type, box(TEAL, Color.TRANSPARENT, 0, 2))
	for scrollbar_type in ["HScrollBar","VScrollBar"]:
		for state in ["scroll","grabber","grabber_highlight"]:
			var style=t.get_stylebox(state,scrollbar_type)
			if scrollbar_type=="VScrollBar":
				style.content_margin_left=6
				style.content_margin_right=6
			else:
				style.content_margin_top=6
				style.content_margin_bottom=6
	t.set_stylebox("slider", "HSlider", box(Color("162c2f"), Color.TRANSPARENT, 0, 2))
	t.set_stylebox("grabber_area", "HSlider", box(Color("698873"), Color.TRANSPARENT, 0, 2))
	for knob_state in ["grabber", "grabber_highlight", "grabber_disabled"]:
		t.set_icon(knob_state, "HSlider", texture("slider_knob"))
	return t

static func label(text: String, size: int = 18, color: Color = WHITE) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func heading(text: String, size: int = 25, color: Color = GOLD) -> Label:
	_fonts()
	var l = label(text, size, color)
	l.add_theme_font_override("font", title_font)
	return l

static func prose(text: String, size: int = 17, color: Color = WHITE) -> Label:
	var l = label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

static func button(text: String, fn: Callable, width: float = 0) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 56)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.mouse_force_pass_scroll_events = true
	b.pressed.connect(func():
		if Engine.get_main_loop() is SceneTree:
			var sound = Engine.get_main_loop().root.get_node_or_null("Sound")
			if sound: sound.sfx("ui")
		fn.call())
	return b

static func selected(button_control: Button, active: bool = true) -> void:
	if active: button_control.add_theme_stylebox_override("normal", button_style("selected"))

static func margin(child: Control, amount: int = 18) -> MarginContainer:
	var m = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, amount)
	m.add_child(child)
	return m

static func portrait(definition: Dictionary, dim: int = 80) -> TextureRect:
	var p = TextureRect.new()
	p.texture = PortraitLibrary.texture(definition)
	p.custom_minimum_size = Vector2(dim, dim)
	p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if PortraitLibrary.is_illustrated(definition) else CanvasItem.TEXTURE_FILTER_NEAREST
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func framed_portrait(definition: Dictionary, dim: int = 80) -> PanelContainer:
	var frame = PanelContainer.new()
	frame.add_theme_stylebox_override("panel", surface(Color("08131c"), Color("7d785f"), 3, 7))
	frame.add_child(portrait(definition, dim))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return frame

static func emblem(kind: String, dim: int = 56) -> TextureRect:
	var image = TextureRect.new()
	image.texture = texture("icon_" + kind)
	image.custom_minimum_size = Vector2(dim, dim)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image

static func bar(value: float, maximum: float, color: Color, width: float = 120, height: float = 7) -> ProgressBar:
	var p = ProgressBar.new()
	p.custom_minimum_size = Vector2(width, height)
	p.max_value = maxf(1, maximum)
	p.value = value
	p.show_percentage = false
	p.add_theme_stylebox_override("fill", box(color, Color.TRANSPARENT, 0, 1))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func fill(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
