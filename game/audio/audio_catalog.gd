class_name AudioCatalog
extends RefCounted
## Audio data: the map `assets/audio/audio_map.json` (place -> music, combat
## event -> sfx rules, story sounds, captions) and the files it names
## (`assets/audio/music/<id>.ogg`, `assets/audio/sfx/<id>.ogg`, variants
## `<id>_1..N.ogg`). No playback here: the Audio autoload plays what this picks.

const MAP_PATH := "res://assets/audio/audio_map.json"
const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"
const BUSES := ["Master", "Music", "SFX", "UI", "Ambience"]
const MAX_VARIANTS := 8

static var _map: Dictionary = {}


static func map() -> Dictionary:
	if _map.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
		_map = parsed if parsed is Dictionary else {}
	return _map


static func music_path(id: String) -> String:
	return MUSIC_DIR + id + ".ogg"


static func has_music(id: String) -> bool:
	return id != "" and ResourceLoader.exists(music_path(id))


## Files of an sfx id: `<id>.ogg`, or its variants `<id>_1.ogg`, `<id>_2.ogg`...
static func sfx_paths(id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if id == "":
		return out
	var single := SFX_DIR + id + ".ogg"
	if ResourceLoader.exists(single):
		out.append(single)
		return out
	for i in range(1, MAX_VARIANTS + 1):
		var p := SFX_DIR + "%s_%d.ogg" % [id, i]
		if not ResourceLoader.exists(p):
			break
		out.append(p)
	return out


static func has_sfx(id: String) -> bool:
	return not sfx_paths(id).is_empty()


## Music of a place (location or dungeon id, or "title", "combat", "boss"), "" if none.
static func music_for(key: String) -> String:
	return str((map().get("music", {}) as Dictionary).get(key, ""))


static func steps_for(place: String) -> String:
	var steps: Dictionary = map().get("steps", {})
	return str(steps.get(place, steps.get("default", "")))


static func room_ambience(room_kind: String) -> String:
	return str((map().get("rooms", {}) as Dictionary).get(room_kind, ""))


static func ui_sfx(kind: String) -> String:
	return str((map().get("ui", {}) as Dictionary).get(kind, ""))


static func story_sfx(kind: String) -> String:
	return str((map().get("story", {}) as Dictionary).get(kind, ""))


static func caption_for(kind: String) -> String:
	return str((map().get("captions", {}) as Dictionary).get(kind, ""))


## First combat rule matching the event: {sfx, caption?} or {}.
## `facts` holds what the event alone does not say: target_family (the target's
## enemy family) and rarity (best rarity of a loot drop).
static func combat_rule(e: Dictionary, facts: Dictionary = {}) -> Dictionary:
	for rule: Dictionary in map().get("combat", []):
		if rule.get("event", "") != e.get("type", ""):
			continue
		if rule.has("spell") and rule["spell"] != str(e.get("spell", "")):
			continue
		if rule.has("target_family") and rule["target_family"] != facts.get("target_family", ""):
			continue
		if rule.has("min_rarity"):
			var rank := BalanceItems.RARITIES.find(str(facts.get("rarity", "")))
			if rank < BalanceItems.RARITIES.find(str(rule["min_rarity"])):
				continue
		return rule
	return {}


## Best rarity in a loot_dropped event ("" when it drops no item, rune or artifact).
static func best_rarity(e: Dictionary) -> String:
	var best := -1
	for key in ["items", "runes"]:
		for it: Variant in e.get(key, []):
			if it is Dictionary:
				best = maxi(best, BalanceItems.RARITIES.find(str(it.get("rarity", ""))))
	if not (e.get("artifacts", []) as Array).is_empty():
		best = maxi(best, BalanceItems.RARITIES.find("epic"))
	return BalanceItems.RARITIES[best] if best >= 0 else ""


## Every sfx id the map names (combat, ui, story, steps, rooms).
static func referenced_sfx() -> PackedStringArray:
	var m := map()
	var out := PackedStringArray()
	for rule: Dictionary in m.get("combat", []):
		out.append(str(rule.get("sfx", "")))
	for section in ["ui", "story", "steps", "rooms"]:
		for v: Variant in (m.get(section, {}) as Dictionary).values():
			out.append(str(v))
	return out


static func referenced_music() -> PackedStringArray:
	var out := PackedStringArray()
	for v: Variant in (map().get("music", {}) as Dictionary).values():
		out.append(str(v))
	return out
