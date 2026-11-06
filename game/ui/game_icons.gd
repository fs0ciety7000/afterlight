class_name GameIcons
extends RefCounted
## Painted icons generated as sheets (art/source/icons, tools/fal/icons.sh) and exported to
## assets/textures/icons/<id>.webp. Returns null when an id has no icon: callers keep their
## procedural glyph.

const DIR := "res://assets/textures/icons/"

static var _cache: Dictionary = {}


static func path_for(id: String) -> String:
	var icon: String = str(Content.get_entity(id).get("icon", ""))
	return icon if icon != "" else DIR + id + ".webp"


static func for_id(id: String) -> Texture2D:
	if id == "":
		return null
	if _cache.has(id):
		return _cache[id]
	var path := path_for(id)
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_cache[id] = tex
	return tex
