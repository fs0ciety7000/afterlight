class_name VfxRecipes
extends RefCounted
## Effect recipes: data files `assets/vfx/recipes/<name>.json`, id `vfx.<name>`.
## A recipe is a small timeline of blocks placed on four beats (anticipation, release,
## impact, afterglow) plus defaults. `extends` derives a recipe from another one (defaults and
## beats are merged, `blocks` replaced if given, `patch` merges params into the parent blocks).
## Format and procedure: docs/VFX.md "Recettes".

const DIR := "res://assets/vfx/recipes/"
const BEATS := ["anticipation", "release", "impact", "afterglow"]
const ANCHORS := [
	"caster",
	"caster_chest",
	"tip",
	"target",
	"target_ground",
	"center",
	"sky",
	"sky_above",
]

static var _cache: Dictionary = {}


static func path_of(recipe_id: String) -> String:
	return DIR + recipe_id.trim_prefix("vfx.") + ".json"


static func has(recipe_id: String) -> bool:
	return recipe_id.begins_with("vfx.") and FileAccess.file_exists(path_of(recipe_id))


## The resolved recipe (inheritance applied), or {} with an error pushed.
static func get_recipe(recipe_id: String) -> Dictionary:
	if _cache.has(recipe_id):
		return _cache[recipe_id]
	var raw := _load(recipe_id)
	if raw.is_empty():
		return {}
	var out := raw
	var parent_id := String(raw.get("extends", ""))
	if parent_id != "":
		out = _derive(get_recipe(parent_id), raw)
	_cache[recipe_id] = out
	return out


static func clear_cache() -> void:
	_cache.clear()


static func list_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	var dir := DirAccess.open(DIR)
	if dir == null:
		return ids
	for f in dir.get_files():
		if f.ends_with(".json"):
			ids.append("vfx." + f.get_basename())
	ids.sort()
	return ids


## Problems found in a recipe (unknown block, beat or anchor), empty when valid.
static func validate(recipe_id: String, block_ids: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	var r := get_recipe(recipe_id)
	if r.is_empty():
		errors.append("%s: cannot load" % recipe_id)
		return errors
	if String(r.get("id", "")) != recipe_id:
		errors.append("%s: id field is %s" % [recipe_id, r.get("id", "")])
	for key in r.get("beats", {}) as Dictionary:
		if not key in BEATS:
			errors.append("%s: unknown beat %s" % [recipe_id, key])
	var blocks: Array = r.get("blocks", [])
	if blocks.is_empty():
		errors.append("%s: no blocks" % recipe_id)
	for e: Dictionary in blocks:
		var b := String(e.get("block", ""))
		if not b in block_ids:
			errors.append("%s: unknown block %s" % [recipe_id, b])
		if not String(e.get("beat", "release")) in BEATS:
			errors.append("%s: unknown beat %s" % [recipe_id, e.get("beat")])
		for k in ["at", "from", "to"]:
			if e.has(k) and not String(e[k]) in ANCHORS:
				errors.append("%s: %s has unknown anchor %s" % [recipe_id, b, e[k]])
	return errors


static func _load(recipe_id: String) -> Dictionary:
	var path := path_of(recipe_id)
	if not FileAccess.file_exists(path):
		push_error("VFX recipe not found: %s (%s)" % [recipe_id, path])
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error(
			"VFX recipe %s: line %d %s" % [path, json.get_error_line(), json.get_error_message()]
		)
		return {}
	if not json.data is Dictionary:
		push_error("VFX recipe %s: not an object" % path)
		return {}
	return json.data


static func _derive(parent: Dictionary, child: Dictionary) -> Dictionary:
	var out := parent.duplicate(true)
	for key in child:
		if key in ["defaults", "beats"]:
			var merged: Dictionary = (out.get(key, {}) as Dictionary).duplicate()
			merged.merge(child[key], true)
			out[key] = merged
		elif key != "patch":
			out[key] = child[key]
	for patch: Dictionary in child.get("patch", []):
		for e: Dictionary in out.get("blocks", []):
			if String(e.get("block")) != String(patch.get("block")):
				continue
			if patch.has("beat") and String(e.get("beat")) != String(patch["beat"]):
				continue
			var params: Dictionary = (e.get("params", {}) as Dictionary).duplicate()
			params.merge(patch.get("params", {}), true)
			e["params"] = params
	return out
