class_name ContentRules
extends RefCounted
## Cross-entity validation rules (docs/CONTENT_PIPELINE.md §8). Structural
## rules (V1-V4, V6-V8, V19) are applied by ContentLoader while reading.
## Not yet enforced: V15 (quest graph) and V20 (save compatibility); they
## land with the milestones that introduce quests (see docs/ROADMAP.md).

const CONDITION_KEYS := {
	"start": "",
	"quest_completed": "quest",
	"location_cleared": "location",
	"level_at_least": "",
	"item_owned": "item",
	"all": "",
}
const LOOT_KIND_TYPES := {
	"material": ["material", "currency"],
	"item": ["item"],
	"rune": ["rune"],
	"artifact": ["artifact"],
	"consumable": ["consumable"],
}
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
				_check_condition(e["unlock"], by_id, f)
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
			"encounter":
				if e["kind"] in ["boss", "elite"] and e["offline_eligible"]:
					f.call("V10", "%s encounters cannot be offline_eligible" % e["kind"])
				if e["kind"] == "boss" and e["speed_cap"] == 4:
					f.call("V10", "boss encounters cannot run at x4")
			"loot_table":
				_check_loot(e, by_id, f)
			"quest":
				for c in e["prerequisites"]:
					_check_condition(c, by_id, f)
	_check_world_reachability(ctx)
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
	for i in range(1, values.size()):
		if float(values[i]) <= float(values[i - 1]):
			f.call("V17", "values_by_tier must be strictly increasing")
			break
	if e["group"] == "conversion" and e["element"] == "":
		f.call("V7", "conversion runes need an element")
	if e["group"] == "modifier" and e["stat"] == "":
		f.call("V7", "modifier runes need a stat")


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
		_:
			var want: String = CONDITION_KEYS[key]
			if not by_id.has(str(value)):
				f.call("V6", "%s: unknown %s '%s'" % [key, want, value])
			elif by_id[str(value)]["_type"] != want:
				f.call("V6", "%s: '%s' is not a %s" % [key, value, want])


## V16: every location must be reachable from the start, following fog
## reveals (a location must be revealed by the start or by a reachable
## location) and unlock conditions that can be satisfied.
static func _check_world_reachability(ctx: Dictionary) -> void:
	var by_id: Dictionary = ctx["by_id"]
	var starts: Array = ctx["by_type"].get("start", [])
	if starts.size() != 1:
		return
	var start: Dictionary = starts[0]
	var revealed := {start["location"]: true}
	var reachable := {}
	var changed := true
	while changed:
		changed = false
		for loc in ctx["by_type"].get("location", []):
			var id: String = loc["id"]
			if reachable.has(id) or not revealed.has(id):
				continue
			if _satisfiable(loc["unlock"], by_id, reachable, {}):
				reachable[id] = true
				for other in loc["fog_reveal"]:
					revealed[other] = true
				changed = true
	for loc in ctx["by_type"].get("location", []):
		if not reachable.has(loc["id"]):
			var why := (
				"never revealed by fog_reveal"
				if not revealed.has(loc["id"])
				else "unlock condition can never be met"
			)
			ContentLoader.fail(
				ctx, "V16", ctx["files"][loc["id"]], loc["id"], "unreachable from the start: " + why
			)


static func _satisfiable(
	c: Dictionary, by_id: Dictionary, reachable: Dictionary, seen: Dictionary
) -> bool:
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
			return reachable.has(str(value))
		"item_owned":
			return by_id.has(str(value))
		"quest_completed":
			var quest_id := str(value)
			if seen.has(quest_id) or not by_id.has(quest_id):
				return false
			seen[quest_id] = true
			for pre in by_id[quest_id].get("prerequisites", []):
				if not _satisfiable(pre, by_id, reachable, seen):
					return false
			return true
		"all":
			for sub in value:
				if not _satisfiable(sub, by_id, reachable, seen):
					return false
			return true
	return false
