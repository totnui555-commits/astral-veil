extends RefCounted
class_name PortraitLibrary
## Shared illustrated atlas; face and dialogue crops do not duplicate textures.

static var _atlas: Texture2D
static var _town_atlas: Texture2D
static var _views: Dictionary = {}
const HEROES = ["c01","c04","c07","n01","n02","c02","c03","c05","c06","c08","c09","c10","c11","c12","c13","c14","c15","c16","c17","c18","c19","c20","c21","c22","c23","c24","c25","c26","c27","c28","c29","c30","n03","n04","n05","n06","n07","n08"]
const COURT = ["king","archmage","chancellor","royal_guard","lady","lord"]
static var _full_views: Dictionary = {}
const FACE_REGIONS = {
	"c01": Rect2(90,49,240,293),
	"c04": Rect2(488,60,255,315),
	"c07": Rect2(837,75,248,296)
}

static func is_illustrated(definition: Dictionary) -> bool:
	return str(definition.get("id","")) in HEROES or str(definition.get("id","")) in COURT

static func texture(definition: Dictionary) -> Texture2D:
	return _view(definition,false)

static func full_texture(definition: Dictionary) -> Texture2D:
	return _view(definition,true)

static func _view(definition: Dictionary, full: bool) -> Texture2D:
	var id = str(definition.get("id",""))
	if not id in HEROES and not id in COURT: return PixelArt.portrait_texture(definition)
	# Individual small face crops keep the 38-person roster inexpensive. Only
	# the two most recent dialogue portraits remain cached at full resolution.
	if not id in ["c01","c04","c07","n01","n02","c02","c03","c05"]:
		if full:
			if not _full_views.has(id):
				if _full_views.size() >= 2: _full_views.erase(_full_views.keys()[0])
				_full_views[id] = load("res://art/vertical/portraits/cast/"+id+".png")
			return _full_views[id]
		if not _views.has(id): _views[id] = load("res://art/vertical/portraits/faces/"+id+".png")
		return _views[id]
	var outfit_id: String = VisualAnimation.costume_id(id)
	var key = outfit_id + ("_full" if full else "_face")
	if _views.has(key): return _views[key]
	if _atlas == null: _atlas = load("res://art/vertical/portraits/trio.png") as Texture2D
	var view = AtlasTexture.new()
	view.atlas = _atlas
	view.region = Rect2(HEROES.find(id)*384,0,384,768) if full else FACE_REGIONS.get(id, Rect2(0,0,1,1))
	if id in ["n01","n02"]:
		if _town_atlas == null: _town_atlas = load("res://art/vertical/portraits/town_pair.png") as Texture2D
		view.atlas = _town_atlas
		var column: int = 0 if id == "n01" else 1
		view.region = Rect2(column*384,0,384,768) if full else Rect2(column*384+120,8,205,210)
	if id in ["c02","c03","c05"]:
		var portrait_path: String = "festival_portraits_living" if outfit_id.ends_with("_festival") else "portraits_living"
		view.atlas = load("res://art/vertical/portraits/"+portrait_path+".png")
		var col: int = ["c02","c03","c05"].find(id)
		view.region = Rect2(col*384,0,384,576) if full else Rect2(col*384+84,8,225,240)
	view.filter_clip = true
	_views[key] = view
	return view
