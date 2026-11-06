class_name TacticsRules
extends RefCounted
## Saved tactics and tips (GDD decisions 23-27, owner answers 2 and 4).
## `characters.<id>.tactics` holds only the deviations from the defaults, in
## the shape of CombatTactics.build overrides: {targeting?, mana_reserve?,
## barrier_hp_pct?, min_enemies?, spells?: {id: mode}, consumables?: {id: mode}}.
## A newly learned spell therefore takes its default. The offline model never
## reads them (GAME_BALANCE §20.1). `progress.tips_seen` lists the tips shown
## once; tips with `repeat` (defeat advice) are never stored.

## Settings that are not a spell or a consumable, with their slider.
const SCALARS := ["targeting", "mana_reserve", "barrier_hp_pct", "min_enemies"]
## Mode -> the setting its slider edits (shown only for these modes).
const MODE_PARAM := {
	"auto_hp_below": "barrier_hp_pct",
	"auto_telegraph_or_hp": "barrier_hp_pct",
	"auto_min_enemies": "min_enemies",
}


## Spells the character has learned (actives, then the ultimate) and every
## consumable, by id: the tactic definitions of the view.
static func defs(state: Dictionary, character: String, content: Dictionary) -> Dictionary:
	var level := int(state["characters"][character]["level"])
	var out := {}
	for id in Grimoire.ranked_spells(character, content):
		if content.has(id) and Grimoire.unlock_level(character, id, content) <= level:
			out[id] = content[id]
	for id in _consumables(content):
		out[id] = content[id]
	return out


## Every spell of the kit, learned or not (saved values are checked against it).
static func kit_defs(character: String, content: Dictionary) -> Dictionary:
	var out := {}
	for id in Grimoire.ranked_spells(character, content):
		if content.has(id):
			out[id] = content[id]
	for id in _consumables(content):
		out[id] = content[id]
	return out


static func saved(state: Dictionary, character: String) -> Dictionary:
	return state["characters"][character].get("tactics", {})


## Full tactics the character fights with (defaults + saved deltas).
static func effective(state: Dictionary, character: String, content: Dictionary) -> Dictionary:
	return CombatTactics.build(defs(state, character, content), saved(state, character))


## The deltas of `full` from the defaults of `spell_defs` (saved shape).
static func delta(full: Dictionary, spell_defs: Dictionary) -> Dictionary:
	var base := CombatTactics.build(spell_defs)
	var out := {}
	for key in SCALARS:
		if not _same(full[key], base[key]):
			out[key] = full[key]
	for group in ["spells", "consumables"]:
		var diff := {}
		for id in full[group]:
			if full[group][id] != base[group].get(id, ""):
				diff[id] = full[group][id]
		if not diff.is_empty():
			out[group] = diff
	return out


## Sets `key` (setting, spell or consumable id) to `value`, plus the slider
## values in `params` ({barrier_hp_pct, min_enemies, mana_reserve...}).
## ActionResult: {ok, error, params, state, tactics (full)}.
static func set_tactic(
	state: Dictionary,
	character: String,
	key: String,
	value: Variant,
	params: Dictionary,
	content: Dictionary
) -> Dictionary:
	if not state["characters"].has(character):
		return ActionResult.refuse("error.tactics.unknown_setting")
	var learned := defs(state, character, content)
	if not SCALARS.has(key) and not learned.has(key):
		if kit_defs(character, content).has(key):
			return ActionResult.refuse(
				"error.spell_locked", {"level": Grimoire.unlock_level(character, key, content)}
			)
		return ActionResult.refuse("error.tactics.unknown_setting")
	var full := CombatTactics.build(learned, saved(state, character))
	var changes := {key: value}
	changes.merge(params)
	for k in changes:
		var why := CombatTactics.set_value(full, learned, str(k), changes[k])
		if why == "unknown_key":
			return ActionResult.refuse("error.tactics.unknown_setting")
		if why != "":
			return ActionResult.refuse("error.tactics.invalid_value")
	return _store(state, character, full, learned)


## Back to the defaults (nothing saved).
static func reset(state: Dictionary, character: String) -> Dictionary:
	var next := state.duplicate(true)
	next["characters"][character]["tactics"] = {}
	return ActionResult.success(next)


## What applying a preset would change, in row order: {ok, error, params,
## lines: [{id, name_key, from, to, from_key, to_key, from_params, to_params}]}.
static func preset_diff(
	state: Dictionary, character: String, preset_id: String, content: Dictionary
) -> Dictionary:
	var preset: Dictionary = content.get(preset_id, {})
	if preset.get("_type", "") != "tactics_preset":
		return ActionResult.refuse("error.tactics.unknown_preset")
	var learned := defs(state, character, content)
	var now := CombatTactics.build(learned, saved(state, character))
	var after := _with_preset(now, learned, preset)
	var lines := []
	for row in _row_ids(learned):
		var from: Variant = _value_of(now, row)
		var to: Variant = _value_of(after, row)
		if _same(from, to):
			continue
		(
			lines
			. append(
				{
					"id": row,
					"name_key": _name_key(row, content),
					"from": from,
					"to": to,
					"from_key": _label_key(row, learned, from),
					"to_key": _label_key(row, learned, to),
					"from_params": _label_params(row, from),
					"to_params": _label_params(row, to),
				}
			)
		)
	var out := ActionResult.success({}, {"lines": lines})
	out.erase("state")
	return out


## Applies a preset on top of the current tactics (values for spells not yet
## learned are skipped). ActionResult with `tactics` (full).
static func apply_preset(
	state: Dictionary, character: String, preset_id: String, content: Dictionary
) -> Dictionary:
	var preset: Dictionary = content.get(preset_id, {})
	if preset.get("_type", "") != "tactics_preset":
		return ActionResult.refuse("error.tactics.unknown_preset")
	var learned := defs(state, character, content)
	var now := CombatTactics.build(learned, saved(state, character))
	return _store(state, character, _with_preset(now, learned, preset), learned)


## Drops saved values CombatTactics refuses (GDD decision 25), in place.
## Returns ["<character>: <key> = <value>"] for the log.
static func sanitize(state: Dictionary, content: Dictionary) -> Array:
	var dropped := []
	for character in state.get("characters", {}):
		var kit := kit_defs(character, content)
		var raw: Variant = state["characters"][character].get("tactics", {})
		if typeof(raw) != TYPE_DICTIONARY:
			raw = {}
		var probe := CombatTactics.build(kit)
		var kept := {}
		for key in raw:
			if key in ["spells", "consumables"] and typeof(raw[key]) == TYPE_DICTIONARY:
				var group := {}
				for id in raw[key]:
					if CombatTactics.set_value(probe, kit, str(id), raw[key][id]) == "":
						group[id] = raw[key][id]
					else:
						dropped.append("%s: %s = %s" % [character, id, raw[key][id]])
				if not group.is_empty():
					kept[key] = group
			elif SCALARS.has(key) and CombatTactics.set_value(probe, kit, key, raw[key]) == "":
				kept[key] = probe[key]  # normalized (min_enemies back to int)
			else:
				dropped.append("%s: %s = %s" % [character, key, raw[key]])
		state["characters"][character]["tactics"] = kept
	return dropped


# --- View -----------------------------------------------------------------------


## The tactics screen (GDD decision 24): {character, rows: [row]}, rows in
## order (targeting, learned spells, consumables, mana reserve). A row:
## {id, kind: targeting|spell|consumable|reserve, name_key, current, default,
## is_default, options: [{id, label_key, label_params, is_default}],
## param: {} or {key, value, default, min, max, step, label_key, label_params},
## say_key, say_params}.
static func view(state: Dictionary, character: String, content: Dictionary) -> Dictionary:
	var learned := defs(state, character, content)
	var now := CombatTactics.build(learned, saved(state, character))
	var base := CombatTactics.build(learned)
	var rows := []
	for id in _row_ids(learned):
		rows.append(_row(id, learned, now, base, content))
	return {"character": character, "rows": rows}


static func _row(
	id: String, learned: Dictionary, now: Dictionary, base: Dictionary, content: Dictionary
) -> Dictionary:
	var current: Variant = _value_of(now, id)
	var default: Variant = _value_of(base, id)
	var row := {
		"id": id,
		"kind": _kind(id, learned),
		"name_key": _name_key(id, content),
		"current": current,
		"default": default,
		"is_default": _same(current, default),
		"options": [],
		"param": {},
		"say_key": _say_key(id, learned, current),
		"say_params": _say_params(id, now, current),
	}
	if id == "mana_reserve":
		row["param"] = _slider(
			"mana_reserve", now, base, 0.0, BalanceCombat.TACTIC_MANA_RESERVE_MAX, 0.1
		)
		return row
	var modes: Array = (
		CombatTactics.TARGETING if id == "targeting" else CombatTactics.modes_for(learned[id])
	)
	for mode in modes:
		(
			row["options"]
			. append(
				{
					"id": mode,
					"label_key": _label_key(id, learned, mode),
					"label_params": _label_params(id, mode),
					"is_default": mode == default,
				}
			)
		)
	match MODE_PARAM.get(current, ""):
		"barrier_hp_pct":
			row["param"] = _slider(
				"barrier_hp_pct",
				now,
				base,
				BalanceCombat.TACTIC_BARRIER_HP_MIN,
				BalanceCombat.TACTIC_BARRIER_HP_MAX,
				0.1
			)
		"min_enemies":
			row["param"] = _slider(
				"min_enemies",
				now,
				base,
				BalanceCombat.TACTIC_MIN_ENEMIES_SHOWN_MIN,
				BalanceCombat.TACTIC_MIN_ENEMIES_SHOWN_MAX,
				1
			)
	return row


static func _slider(
	key: String, now: Dictionary, base: Dictionary, low: float, high: float, step: float
) -> Dictionary:
	var is_count := key == "min_enemies"
	return {
		"key": key,
		"value": now[key],
		"default": base[key],
		"min": low,
		"max": high,
		"step": step,
		"label_key": "ui.tactics.value_enemies" if is_count else "ui.tactics.value_pct",
		"label_params": {"n": now[key]} if is_count else {"x": _pct(now[key])},
	}


static func _row_ids(learned: Dictionary) -> Array:
	var out := ["targeting"]
	for id in learned:
		if not CombatTactics.is_consumable(learned[id]):
			out.append(id)
	for id in learned:
		if CombatTactics.is_consumable(learned[id]):
			out.append(id)
	out.append("mana_reserve")
	return out


static func _kind(id: String, learned: Dictionary) -> String:
	if id == "targeting":
		return "targeting"
	if id == "mana_reserve":
		return "reserve"
	return "consumable" if CombatTactics.is_consumable(learned[id]) else "spell"


static func _value_of(t: Dictionary, id: String) -> Variant:
	if id in ["targeting", "mana_reserve"]:
		return t[id]
	if t["spells"].has(id):
		return t["spells"][id]
	return t["consumables"].get(id, "manual")


static func _name_key(id: String, content: Dictionary) -> String:
	if id in ["targeting", "mana_reserve"]:
		return "ui.tactics.setting." + id
	return str(content.get(id, {}).get("name_key", id + ".name"))


static func _label_key(id: String, _learned: Dictionary, value: Variant) -> String:
	match id:
		"targeting":
			return "ui.tactics.targeting.%s" % value
		"mana_reserve":
			return "ui.tactics.value_pct"
	return "ui.tactics.mode.%s" % value


static func _label_params(id: String, value: Variant) -> Dictionary:
	if id == "mana_reserve":
		return {"x": _pct(value)}
	match str(value):
		"auto_low_hp":
			return {"x": _pct(BalanceCombat.TACTIC_HEAL_HP_PCT)}
		"auto_low_mana":
			return {"x": _pct(BalanceCombat.TACTIC_ELIXIR_MANA_PCT)}
	return {}


## "ui.tactics.say.<setting or id suffix>.<mode>" (one line in plain French).
static func _say_key(id: String, _learned: Dictionary, value: Variant) -> String:
	match id:
		"targeting":
			return "ui.tactics.say.targeting.%s" % value
		"mana_reserve":
			return "ui.tactics.say.mana_reserve"
	return "ui.tactics.say.%s.%s" % [id.get_slice(".", 1), value]


static func _say_params(id: String, now: Dictionary, value: Variant) -> Dictionary:
	if id == "mana_reserve":
		return {"x": _pct(now["mana_reserve"])}
	match str(value):
		"auto_hp_below", "auto_telegraph_or_hp":
			return {"x": _pct(now["barrier_hp_pct"])}
		"auto_min_enemies":
			return {"n": int(now["min_enemies"])}
	return _label_params(id, value)


static func _pct(value: Variant) -> int:
	return roundi(float(value) * 100.0)


# --- Tips -------------------------------------------------------------------------


## The tip to show for `context` ({} if none): context = {trigger:
## "level_reached", level} | {trigger: "first_campfire", dungeon} | {trigger:
## "boss_cast", encounter, ability} | {trigger: "defeat", encounter, ability
## (the last hit, encounter_completed.last_hit.spell)}. Result: {id,
## title_key, text_key, display, duration_s, actions, preset, repeat}.
static func next_tip(state: Dictionary, context: Dictionary, content: Dictionary) -> Dictionary:
	var seen: Array = state["progress"].get("tips_seen", [])
	var ids := []
	for id in content:
		if content[id].get("_type", "") == "tip":
			ids.append(id)
	ids.sort()
	for id in ids:
		var tip: Dictionary = content[id]
		if tip["trigger"] != str(context.get("trigger", "")):
			continue
		if not tip["repeat"] and seen.has(id):
			continue
		if _tip_matches(tip, context):
			return {
				"id": id,
				"title_key": tip["name_key"],
				"text_key": id,
				"display": tip["display"],
				"duration_s": float(tip["duration_s"]),
				"actions": tip["actions"].duplicate(),
				"preset": tip["preset"],
				"repeat": tip["repeat"],
			}
	return {}


static func _tip_matches(tip: Dictionary, context: Dictionary) -> bool:
	match tip["trigger"]:
		"level_reached":
			return int(context.get("level", 0)) >= int(tip["level"])
		"first_campfire":
			return tip["dungeon"] == "" or tip["dungeon"] == str(context.get("dungeon", ""))
	if tip["encounter"] != "" and tip["encounter"] != str(context.get("encounter", "")):
		return false
	return tip["abilities"].has(str(context.get("ability", "")))


## Marks a tip as shown. Repeating tips (defeat advice) are not stored.
static func mark_tip_seen(state: Dictionary, tip_id: String, content: Dictionary) -> Dictionary:
	var tip: Dictionary = content.get(tip_id, {})
	if tip.get("_type", "") != "tip":
		return ActionResult.refuse("error.tip.unknown")
	var next := state.duplicate(true)
	var seen: Array = next["progress"]["tips_seen"]
	if not tip["repeat"] and not seen.has(tip_id):
		seen.append(tip_id)
	return ActionResult.success(next)


# --- Helpers ----------------------------------------------------------------------


static func _with_preset(now: Dictionary, learned: Dictionary, preset: Dictionary) -> Dictionary:
	var after := now.duplicate(true)
	var t: Dictionary = preset["tactics"]
	for key in t:
		if key in ["spells", "consumables"]:
			for id in t[key]:
				CombatTactics.set_value(after, learned, str(id), t[key][id])
		else:
			CombatTactics.set_value(after, learned, str(key), t[key])
	return after


static func _store(
	state: Dictionary, character: String, full: Dictionary, learned: Dictionary
) -> Dictionary:
	var next := state.duplicate(true)
	var kept := delta(full, learned)
	# Values saved for spells not learned yet stay (a lower level save).
	var old: Dictionary = saved(state, character)
	for group in ["spells", "consumables"]:
		for id in old.get(group, {}):
			if not learned.has(id):
				if not kept.has(group):
					kept[group] = {}
				kept[group][id] = old[group][id]
	next["characters"][character]["tactics"] = kept
	return ActionResult.success(next, {"tactics": full})


static func _consumables(content: Dictionary) -> Array:
	var out := []
	for id in content:
		if content[id].get("_type", "") == "consumable":
			out.append(id)
	out.sort()
	return out


static func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return absf(float(a) - float(b)) < 0.000001
	return a == b
