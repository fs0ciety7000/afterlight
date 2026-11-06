class_name ContentRules
extends RefCounted
## Cross-entity validation rules (docs/CONTENT_PIPELINE.md §8). Structural
## rules (V1-V4, V6-V8, V19) are applied by ContentLoader while reading.
## V20 (save compatibility) needs a save: check_save_ids(), run by the tests
## on the reference save.

const CONDITION_KEYS := {
	"start": "",
	"quest_completed": "quest",
	"location_cleared": "location",
	"level_at_least": "",
	"item_owned": "item",
	"all": "",
	"quest_state": "",
	"objective": "",
	"discovery_found": "discovery",
}
## Reward unlock tokens that are not entity ids (quest rewards.unlocks).
const UNLOCK_TOKENS := ["artifact_slot_1"]
const LOOT_KIND_TYPES := {
	"material": ["material", "currency"],
	"item": ["item"],
	"rune": ["rune"],
	"artifact": ["artifact"],
	"consumable": ["consumable"],
}
## Loot kinds whose ref may be empty: the engine then picks a base (item) or a
## rune at random (GAME_BALANCE §14, §17).
const LOOT_RANDOM_KINDS := ["item", "rune"]
const MIN_TELEGRAPH_S := 0.6
const TELEGRAPH_COEFF := 1.5


static func check(ctx: Dictionary, translations: Dictionary) -> void:
	var by_id: Dictionary = ctx["by_id"]
	for id in by_id:
		var e: Dictionary = by_id[id]
		var file: String = ctx["files"][id]
		var f := func(rule: String, message: String) -> void:
			ContentLoader.fail(ctx, rule, file, id, message)
		_check_common(e, by_id, translations, f)
		match e["_type"]:
			"character":
				_check_character(e, by_id, f)
			"spell", "ability":
				_check_spell(e, f)
			"status":
				if e["kind"] == "dot" and not e.has("tick_s"):
					f.call("V7", "tick_s is required for a dot")
			"enemy":
				_check_enemy(e, f)
			"affix":
				if float(e["min"]) > float(e["max"]):
					f.call("V8", "min > max")
			"rune":
				_check_rune(e, f)
			"artifact":
				if e["values_by_level"].size() != e["max_level"]:
					f.call("V7", "values_by_level must have max_level values")
				if not _increasing(e["values_by_level"]):
					f.call("V8", "values_by_level must be strictly increasing")
				_check_condition(e["unlock"], by_id, f)
			"item":
				if e["implicit"].is_empty():
					f.call("V7", "an item base needs an implicit")
				if _affix_pool(e, ctx).is_empty():
					f.call("V7", "no affix can roll on slot %s" % e["slot"])
			"region":
				if not e["locations"].has(e["hub"]):
					f.call("V7", "hub must be one of locations")
				_check_condition(e["unlock"], by_id, f)
			"location":
				if e["kind"] != "hub" and not e.has("level"):
					f.call("V7", "level is required unless kind is hub")
				_check_condition(e["unlock"], by_id, f)
			"dungeon":
				_check_dungeon(e, f)
				_check_condition(e["unlock"], by_id, f)
			"discovery":
				_check_discovery(e, by_id, f)
			"npc":
				for entry in e["dialogues"]:
					if not entry["condition"].is_empty():
						_check_condition(entry["condition"], by_id, f)
			"dialogue":
				for line in e["lines"]:
					if line.has("condition"):
						_check_condition(line["condition"], by_id, f)
			"encounter":
				_check_materials(e["first_clear_rewards"].get("materials", {}), by_id, f)
				_check_first_clear_items(e, by_id, f)
				if e["kind"] in ["boss", "elite"] and e["offline_eligible"]:
					f.call("V10", "%s encounters cannot be offline_eligible" % e["kind"])
				if e["kind"] == "boss" and e["speed_cap"] == 4:
					f.call("V10", "boss encounters cannot run at x4")
			"loot_table":
				_check_loot(e, by_id, f)
			"quest":
				_check_quest(e, by_id, f)
			"tactics_preset":
				_check_tactics_preset(e, by_id, f)
			"tip":
				_check_tip(e, f)
				if not _translated(translations, id):
					f.call("V9", "tip text '%s' missing from strings.csv" % id)
	_check_quest_cycles(ctx)
	_check_progression(ctx)
	var starts: Array = ctx["by_type"].get("start", [])
	if starts.size() != 1:
		ContentLoader.fail(
			ctx,
			"V7",
			"start.json",
			"-",
			"exactly one start entry is required (found %d)" % starts.size()
		)


static func _check_common(
	e: Dictionary, by_id: Dictionary, translations: Dictionary, f: Callable
) -> void:
	var id: String = e["id"]
	if e["origin"] == "canon" and str(e["canon_note"]).strip_edges() == "":
		f.call("V5", "canon entries need a canon_note")
	for r in e["canon_refs"]:
		if not by_id.has(r) or by_id[r]["origin"] != "canon":
			f.call("V5", "canon_refs '%s' is not a canon entry" % r)
	if e["name_key"] != id + ".name":
		f.call("V9", "name_key must be '%s.name'" % id)
	elif not _translated(translations, e["name_key"]):
		f.call("V9", "name_key '%s' missing from strings.csv" % e["name_key"])
	var needs_desc: bool = ContentSchemas.NEEDS_DESC.has(e["_type"])
	if e["desc_key"] == "":
		if needs_desc:
			f.call("V9", "desc_key is required for a %s" % e["_type"])
	elif e["desc_key"] != id + ".desc":
		f.call("V9", "desc_key must be '%s.desc'" % id)
	elif not _translated(translations, e["desc_key"]):
		f.call("V9", "desc_key '%s' missing from strings.csv" % e["desc_key"])


static func _translated(translations: Dictionary, key: String) -> bool:
	if translations.has(key):
		return true
	if translations.has(ContentLoader.RUNTIME_LOOKUP):
		return str(TranslationServer.translate(key)) != key
	return false


static func _check_character(e: Dictionary, by_id: Dictionary, f: Callable) -> void:
	if not e["playable"]:
		return
	for key in ["role", "auto_attack", "ultimate", "model", "portrait"]:
		if str(e[key]) == "":
			f.call("V18", "playable characters need %s" % key)
	if e["spells"].is_empty():
		f.call("V18", "playable characters need spells")
	if e["base_stats"].is_empty() or e["growth"].is_empty():
		f.call("V18", "playable characters need base_stats and growth")
	var expect := {"auto_attack": "auto", "ultimate": "ultimate"}
	for key in expect:
		var ref: String = e[key]
		if by_id.has(ref) and by_id[ref].get("kind") != expect[key]:
			f.call("V18", "%s '%s' must have kind %s" % [key, ref, expect[key]])
	for ref in e["spells"]:
		if by_id.has(ref) and by_id[ref].get("kind") != "active":
			f.call("V18", "spells '%s' must have kind active" % ref)


static func _check_spell(e: Dictionary, f: Callable) -> void:
	var kind: String = e["kind"]
	if kind != "passive" and e["element"] == "":
		f.call("V7", "element is required")
	if kind != "passive" and e["targeting"] == "":
		f.call("V7", "targeting is required")
	if kind == "active" and not e.has("mana_cost"):
		f.call("V7", "mana_cost is required for an active spell")
	if kind in ["auto", "attack"]:
		if not e.has("interval_s"):
			f.call("V7", "interval_s is required for %s" % kind)
	elif kind != "passive" and not e.has("cooldown_s"):
		f.call("V7", "cooldown_s is required")
	if kind == "ultimate" and not e.has("ult_charge_cost"):
		f.call("V7", "ult_charge_cost is required for an ultimate")
	if kind in ["active", "ultimate"] and not e.has("ranks"):
		f.call("V7", "ranks (5) are required for %s" % kind)
	if e["targeting"] != "self" and kind != "passive" and not e.has("range_m"):
		f.call("V7", "range_m is required unless targeting self")
	if e.has("telegraph") and float(e["telegraph"]["duration_s"]) < MIN_TELEGRAPH_S:
		f.call("V13", "telegraph shorter than %.1f s" % MIN_TELEGRAPH_S)
	if e["_type"] == "ability" and not e.has("telegraph"):
		for effect in e["effects"]:
			if float(effect.get("coeff", 0.0)) >= TELEGRAPH_COEFF:
				f.call("V13", "coeff >= %.1f needs a telegraph" % TELEGRAPH_COEFF)
				break


static func _check_enemy(e: Dictionary, f: Callable) -> void:
	if e["archetype"] != "boss":
		return
	if e["phases"].is_empty() or not e.has("enrage_s"):
		f.call("V11", "bosses need phases and enrage_s")
	var last := 2.0
	for phase in e["phases"]:
		var t := float(phase["hp_threshold"])
		if t >= last:
			f.call("V11", "phase thresholds must be strictly decreasing")
		last = t


static func _check_rune(e: Dictionary, f: Callable) -> void:
	var values: Array = e["values_by_tier"]
	if values.size() != 5:
		f.call("V17", "values_by_tier needs exactly 5 values")
	if not _increasing(values):
		f.call("V17", "values_by_tier must be strictly increasing")
	if e["group"] == "conversion" and e["element"] == "":
		f.call("V7", "conversion runes need an element")
	if e["group"] == "modifier" and e["stat"] == "":
		f.call("V7", "modifier runes need a stat")


static func _increasing(values: Array) -> bool:
	for i in range(1, values.size()):
		if float(values[i]) <= float(values[i - 1]):
			return false
	return true


## Affixes that can roll on an item base: its affix_pools, or every affix
## whose slots include the base's slot.
static func _affix_pool(item: Dictionary, ctx: Dictionary) -> Array:
	if not item["affix_pools"].is_empty():
		return item["affix_pools"]
	var out := []
	for a in ctx["by_type"].get("affix", []):
		if (a["slots"] as Array).has(item["slot"]):
			out.append(a["id"])
	return out


static func _check_dungeon(e: Dictionary, f: Callable) -> void:
	var rooms: Array = e["rooms"]
	var has_boss := false
	for room in rooms:
		has_boss = has_boss or room["kind"] == "boss"
		if room["kind"] in ["encounter", "elite", "boss"] and room["encounter"] == "":
			f.call("V7", "room '%s' needs an encounter" % room["id"])
	if not has_boss or rooms[rooms.size() - 1]["kind"] != "boss":
		f.call("V12", "the last room must be the boss")


static func _check_loot(e: Dictionary, by_id: Dictionary, f: Callable) -> void:
	var total := 0.0
	for entry in e["entries"]:
		total += float(entry["chance"])
		if entry["qty"][0] > entry["qty"][1]:
			f.call("V8", "qty min > max")
		if entry["kind"] == "gold":
			continue
		var ref: String = entry["ref"]
		if ref == "" and LOOT_RANDOM_KINDS.has(entry["kind"]):
			continue
		if ref == "":
			f.call("V7", "%s entries need a ref" % entry["kind"])
		elif (
			by_id.has(ref)
			and not (LOOT_KIND_TYPES[entry["kind"]] as Array).has(by_id[ref]["_type"])
		):
			f.call("V6", "'%s' does not match kind %s" % [ref, entry["kind"]])
	if total <= 0.0:
		f.call("V14", "the sum of chances is zero")


static func _check_condition(c: Variant, by_id: Dictionary, f: Callable) -> void:
	if typeof(c) != TYPE_DICTIONARY or c.size() != 1:
		f.call("V7", "a condition has exactly one key among %s" % ", ".join(CONDITION_KEYS.keys()))
		return
	var key: String = c.keys()[0]
	if not CONDITION_KEYS.has(key):
		f.call("V7", "unknown condition '%s'" % key)
		return
	var value: Variant = c[key]
	match key:
		"start":
			if value != true:
				f.call("V7", "start condition must be true")
		"level_at_least":
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or float(value) < 1:
				f.call("V8", "level_at_least must be >= 1")
		"all":
			if typeof(value) != TYPE_ARRAY or value.is_empty():
				f.call("V7", "all needs a non-empty list")
			else:
				for sub in value:
					_check_condition(sub, by_id, f)
		"quest_state":
			if typeof(value) != TYPE_DICTIONARY or not value.has("id") or not value.has("state"):
				f.call("V7", "quest_state needs {id, state}")
			elif not ContentSchemas.QUEST_STATES.has(str(value["state"])):
				f.call("V7", "quest_state: unknown state '%s'" % value["state"])
			else:
				_check_typed_ref("quest_state", str(value["id"]), "quest", by_id, f)
		"objective":
			if (
				typeof(value) != TYPE_DICTIONARY
				or not value.has("quest")
				or not value.has("id")
				or typeof(value.get("done")) != TYPE_BOOL
			):
				f.call("V7", "objective needs {quest, id, done}")
			elif _check_typed_ref("objective", str(value["quest"]), "quest", by_id, f):
				var ids: Array = by_id[str(value["quest"])]["objectives"].map(
					func(o: Dictionary) -> String: return o["id"]
				)
				if not ids.has(str(value["id"])):
					f.call(
						"V6",
						"objective: '%s' has no objective '%s'" % [value["quest"], value["id"]]
					)
		_:
			_check_typed_ref(key, str(value), CONDITION_KEYS[key], by_id, f)


static func _check_typed_ref(
	key: String, id: String, want: String, by_id: Dictionary, f: Callable
) -> bool:
	if not by_id.has(id):
		f.call("V6", "%s: unknown %s '%s'" % [key, want, id])
		return false
	if by_id[id]["_type"] != want:
		f.call("V6", "%s: '%s' is not a %s" % [key, id, want])
		return false
	return true


## {material id: qty} maps hold ids as keys, which the schema cannot follow.
static func _check_materials(materials: Dictionary, by_id: Dictionary, f: Callable) -> void:
	for id in materials:
		if not by_id.has(id) or not by_id[id]["_type"] in ["material", "currency"]:
			f.call("V6", "'%s' is not a material" % id)


static func _check_discovery(e: Dictionary, by_id: Dictionary, f: Callable) -> void:
	_check_materials(e["reward"]["materials"], by_id, f)
	if not e["available_if"].is_empty():
		_check_condition(e["available_if"], by_id, f)
	if float(e["fog_radius"]) > 0.0 and e["map_pos"].is_empty():
		f.call("V7", "fog_radius needs map_pos")
	if e["counts_for_location"] and e["map_pos"].is_empty():
		f.call("V7", "a counted discovery needs map_pos (fog of the map)")


## V15 (structure): objective events and targets, steps, rewards, daily fields.
static func _check_quest(e: Dictionary, by_id: Dictionary, f: Callable) -> void:
	for c in e["prerequisites"]:
		_check_condition(c, by_id, f)
	var daily: bool = e["kind"] == "daily"
	if not daily and not e.has("level"):
		f.call("V7", "level is required for a %s quest" % e["kind"])
	if daily and (e["tier"] == "" or not e.has("weight")):
		f.call("V7", "daily quests need tier and weight")
	var ids := {}
	var steps := {}
	for o in e["objectives"]:
		if ids.has(o["id"]):
			f.call("V15", "objective id '%s' is used twice" % o["id"])
		ids[o["id"]] = true
		steps[int(o["step"])] = true
		var allowed: Array = ContentSchemas.OBJECTIVE_TARGETS[o["event"]]
		var target: String = o["target"]
		if by_id.has(target) and not allowed.has(by_id[target]["_type"]):
			f.call(
				"V15",
				(
					"objective '%s': %s cannot target a %s"
					% [o["id"], o["event"], by_id[target]["_type"]]
				)
			)
		if o["source"] != "" and not o["event"] in ["CastInterrupted", "StatusApplied"]:
			f.call("V15", "objective '%s': source only applies to casts and statuses" % o["id"])
	for s in range(1, steps.size() + 1):
		if not steps.has(s):
			f.call("V15", "objective steps must run 1..n without gaps")
			break
	var rewards: Dictionary = e["rewards"]
	_check_materials(rewards["materials"], by_id, f)
	for token in rewards["unlocks"]:
		var t := ContentSchemas.type_of_id(str(token))
		if not UNLOCK_TOKENS.has(token) and not (by_id.has(token) and t in ["location", "dungeon"]):
			f.call("V6", "unlocks '%s' is neither a location, a dungeon nor a known token" % token)


## V15: quest prerequisites (quest_completed, through `all`) may not loop.
static func _check_quest_cycles(ctx: Dictionary) -> void:
	var edges := {}
	for q in ctx["by_type"].get("quest", []):
		var out := []
		for c in q["prerequisites"]:
			_quest_refs(c, out)
		edges[q["id"]] = out
	var ids := edges.keys()
	ids.sort()
	var done := {}
	for id in ids:
		var path: Array = []
		if _has_cycle(id, edges, {}, done, path):
			ContentLoader.fail(
				ctx, "V15", ctx["files"][id], id, "prerequisites form a cycle: " + " > ".join(path)
			)


static func _quest_refs(c: Variant, out: Array) -> void:
	if typeof(c) != TYPE_DICTIONARY or c.size() != 1:
		return
	var key: String = c.keys()[0]
	if key == "quest_completed":
		out.append(str(c[key]))
	elif key == "all" and typeof(c[key]) == TYPE_ARRAY:
		for sub in c[key]:
			_quest_refs(sub, out)


static func _has_cycle(
	id: String, edges: Dictionary, stack: Dictionary, done: Dictionary, path: Array
) -> bool:
	if stack.has(id):
		path.append(id)
		return true
	if done.has(id) or not edges.has(id):
		return false
	stack[id] = true
	path.append(id)
	for next in edges[id]:
		if _has_cycle(next, edges, stack, done, path):
			return true
	stack.erase(id)
	path.pop_back()
	done[id] = true
	return false


## V15 and V16: walks the critical path from the start. A location is
## reachable once revealed (start, fog_reveal of a reachable location, a
## discovery found in one, or a completed quest's unlocks) and unlocked; a
## dungeon once its location is reachable and it is unlocked; a quest is
## completable once its prerequisites hold and every objective's target can
## be reached or obtained. Every location must end reachable (V16) and every
## main quest completable (V15).
static func _check_progression(ctx: Dictionary) -> void:
	var by_id: Dictionary = ctx["by_id"]
	var starts: Array = ctx["by_type"].get("start", [])
	if starts.size() != 1:
		return
	var start: Dictionary = starts[0]
	var reach := {
		"revealed": {start["location"]: true},
		"places": {},
		"quests": {},
		"materials": {},
	}
	for id in start.get("materials", {}):
		reach["materials"][id] = true
	var changed := true
	while changed:
		changed = false
		for loc in ctx["by_type"].get("location", []):
			var id: String = loc["id"]
			if reach["places"].has(id) or not reach["revealed"].has(id):
				continue
			if _satisfiable(loc["unlock"], by_id, reach):
				_reach_place(id, loc["fog_reveal"], ctx, reach)
				changed = true
		for d in ctx["by_type"].get("dungeon", []):
			if reach["places"].has(d["id"]) or not reach["places"].has(d["location"]):
				continue
			if _satisfiable(d["unlock"], by_id, reach):
				_reach_place(d["id"], [], ctx, reach)
				changed = true
		for q in ctx["by_type"].get("quest", []):
			if reach["quests"].has(q["id"]) or not _quest_open(q, by_id, reach):
				continue
			reach["quests"][q["id"]] = true
			for id in q["rewards"]["materials"]:
				reach["materials"][id] = true
			for id in q["rewards"]["artifacts"]:
				reach["materials"][id] = true
			for token in q["rewards"]["unlocks"]:
				reach["revealed"][token] = true
			changed = true
	for loc in ctx["by_type"].get("location", []):
		if not reach["places"].has(loc["id"]):
			var why := (
				"never revealed (fog_reveal, discovery or quest unlocks)"
				if not reach["revealed"].has(loc["id"])
				else "unlock condition can never be met"
			)
			ContentLoader.fail(
				ctx, "V16", ctx["files"][loc["id"]], loc["id"], "unreachable from the start: " + why
			)
	for q in ctx["by_type"].get("quest", []):
		if q["kind"] == "main" and not reach["quests"].has(q["id"]):
			ContentLoader.fail(
				ctx,
				"V15",
				ctx["files"][q["id"]],
				q["id"],
				"main quest cannot be completed from the start: " + _blocker(q, by_id, reach)
			)


## Marks a place reachable: what it reveals, and what its encounters and
## discoveries can give.
static func _reach_place(id: String, fog: Array, ctx: Dictionary, reach: Dictionary) -> void:
	reach["places"][id] = true
	reach["revealed"][id] = true
	for other in fog:
		reach["revealed"][other] = true
	var by_id: Dictionary = ctx["by_id"]
	for enc in _place_encounters(id, ctx):
		var table: Dictionary = by_id.get(enc.get("loot_table", ""), {})
		for entry in table.get("entries", []):
			if str(entry.get("ref", "")) != "":
				reach["materials"][entry["ref"]] = true
		for m in enc["first_clear_rewards"].get("materials", {}):
			reach["materials"][m] = true
		for it in enc["first_clear_rewards"].get("items", []):
			reach["materials"][it["base"]] = true
	for disc in ctx["by_type"].get("discovery", []):
		if disc["location"] != id:
			continue
		for other in disc["reveals"]:
			reach["revealed"][other] = true
		for m in disc["reward"]["materials"]:
			reach["materials"][m] = true
		for a in disc["reward"]["artifacts"]:
			reach["materials"][a] = true


## Encounters fought in a place: a location's own list, or a dungeon's rooms.
static func _place_encounters(id: String, ctx: Dictionary) -> Array:
	var by_id: Dictionary = ctx["by_id"]
	var place: Dictionary = by_id.get(id, {})
	var out := []
	var ids: Array = place.get("encounters", []).duplicate()
	for room in place.get("rooms", []):
		if str(room.get("encounter", "")) != "":
			ids.append(room["encounter"])
	for enc_id in ids:
		if by_id.has(enc_id):
			out.append(by_id[enc_id])
	return out


static func _quest_open(q: Dictionary, by_id: Dictionary, reach: Dictionary) -> bool:
	for c in q["prerequisites"]:
		if not _satisfiable(c, by_id, reach):
			return false
	for o in q["objectives"]:
		if not _target_reachable(o, by_id, reach):
			return false
	return true


## Why a quest stays closed (first failing prerequisite or objective).
static func _blocker(q: Dictionary, by_id: Dictionary, reach: Dictionary) -> String:
	for c in q["prerequisites"]:
		if not _satisfiable(c, by_id, reach):
			return "prerequisite %s never holds" % JSON.stringify(c)
	for o in q["objectives"]:
		if not _target_reachable(o, by_id, reach):
			return "objective '%s' (%s) cannot be reached" % [o["id"], o["target"]]
	return "unknown"


static func _target_reachable(o: Dictionary, by_id: Dictionary, reach: Dictionary) -> bool:
	var target: String = o["target"]
	var e: Dictionary = by_id.get(target, {})
	match e.get("_type", ""):
		"location", "dungeon":
			return reach["places"].has(target)
		"npc", "discovery":
			return reach["places"].has(str(e["location"]))
		"encounter":
			if reach["places"].has(str(e["location"])) and _listed(target, e["location"], by_id):
				return true
			for place in reach["places"]:
				for room in by_id.get(place, {}).get("rooms", []):
					if room.get("encounter", "") == target:
						return true
			return false
		"enemy":
			for place in reach["places"]:
				var pe: Dictionary = by_id.get(place, {})
				var ids: Array = pe.get("encounters", []).duplicate()
				for room in pe.get("rooms", []):
					ids.append(str(room.get("encounter", "")))
				for enc_id in ids:
					for group in by_id.get(enc_id, {}).get("enemies", []):
						if group["enemy"] == target:
							return true
			return false
		"material", "currency", "artifact":
			return reach["materials"].has(target)
	return true


static func _listed(encounter_id: String, location_id: String, by_id: Dictionary) -> bool:
	return (by_id.get(location_id, {}).get("encounters", []) as Array).has(encounter_id)


static func _satisfiable(c: Dictionary, by_id: Dictionary, reach: Dictionary) -> bool:
	if c.is_empty():
		return true
	var key: String = c.keys()[0]
	var value: Variant = c[key]
	match key:
		"start":
			return true
		"level_at_least":
			return int(value) <= BalanceProgression.LEVEL_CAP
		"location_cleared":
			return reach["places"].has(str(value))
		"item_owned":
			return by_id.has(str(value))
		"quest_completed":
			return reach["quests"].has(str(value))
		"quest_state":
			if str(value.get("state", "")) in ["completed", "turned_in"]:
				return reach["quests"].has(str(value.get("id", "")))
			return true
		"objective":
			return true
		"discovery_found":
			return reach["places"].has(str(by_id.get(str(value), {}).get("location", "")))
		"all":
			for sub in value:
				if not _satisfiable(sub, by_id, reach):
					return false
			return true
	return false


## V20: every id a reference save holds must still exist in the content, or
## be listed in `retired` (ids removed with a save migration). Returns the
## error lines ("V20 save <path> <id> ...").
static func check_save_ids(
	state: Dictionary, by_id: Dictionary, retired: Dictionary = {}
) -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	_collect_ids(state, "$", seen)
	var paths := seen.keys()
	paths.sort()
	for path in paths:
		var id: String = seen[path]
		if not by_id.has(id) and not retired.has(id):
			errors.append(
				(
					"V20 save %s %s removed from the data without deprecated or a migration"
					% [path, id]
				)
			)
	return errors


## Every string (or dictionary key) shaped like a content id, by path.
static func _collect_ids(value: Variant, path: String, out: Dictionary) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for k in value:
				if _is_content_id(str(k)):
					out["%s{%s}" % [path, k]] = str(k)
				_collect_ids(value[k], "%s.%s" % [path, k], out)
		TYPE_ARRAY:
			for i in value.size():
				_collect_ids(value[i], "%s[%d]" % [path, i], out)
		TYPE_STRING:
			if _is_content_id(value):
				out[path] = value


static func _is_content_id(text: String) -> bool:
	var prefix := text.get_slice(".", 0)
	return (
		text.contains(".")
		and ContentSchemas.PREFIX_TO_TYPE.has(prefix)
		and RegEx.create_from_string(ContentSchemas.ID_PATTERN).search(text) != null
	)


## GDD decision 29: a first clear item base must drop at the encounter's level.
static func _check_first_clear_items(e: Dictionary, by_id: Dictionary, f: Callable) -> void:
	for it in e["first_clear_rewards"].get("items", []):
		var base: Dictionary = by_id.get(it["base"], {})
		if not base.is_empty() and int(base.get("min_ilvl", 1)) > int(e["level"]):
			f.call(
				"V8",
				(
					"first_clear_rewards.items: %s min_ilvl %d > encounter level %d"
					% [it["base"], int(base["min_ilvl"]), int(e["level"])]
				)
			)


## A preset holds values CombatTactics accepts for its character's spells
## and the consumables.
static func _check_tactics_preset(e: Dictionary, by_id: Dictionary, f: Callable) -> void:
	var hero: Dictionary = by_id.get(e["character"], {})
	var spells := {}
	for id in hero.get("spells", []) + [hero.get("ultimate", "")]:
		if by_id.has(id):
			spells[id] = by_id[id]
	for id in by_id:
		if by_id[id]["_type"] == "consumable":
			spells[id] = by_id[id]
	var t := CombatTactics.build(spells)
	var overrides: Dictionary = e["tactics"]
	for key in overrides:
		if key in ["spells", "consumables"]:
			if typeof(overrides[key]) != TYPE_DICTIONARY:
				f.call("V7", "tactics.%s must be a dictionary" % key)
				continue
			for id in overrides[key]:
				var why := CombatTactics.set_value(t, spells, str(id), overrides[key][id])
				if why != "":
					f.call("V7", "tactics.%s.%s: %s" % [key, id, why])
		else:
			var why := CombatTactics.set_value(t, spells, str(key), overrides[key])
			if why != "":
				f.call("V7", "tactics.%s: %s" % [key, why])


## Each trigger needs its own field (GDD decision 27).
static func _check_tip(e: Dictionary, f: Callable) -> void:
	match e["trigger"]:
		"level_reached":
			if int(e["level"]) < 1:
				f.call("V7", "a level_reached tip needs level")
		"boss_cast", "defeat":
			if e["abilities"].is_empty():
				f.call("V7", "a %s tip needs abilities" % e["trigger"])
	if e["actions"].has("apply_preset") and e["preset"] == "":
		f.call("V7", "apply_preset needs a preset")
