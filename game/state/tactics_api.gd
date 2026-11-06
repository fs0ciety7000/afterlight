class_name TacticsApi
extends RefCounted
## Tactics screen, tactics presets and tips for the UI (GDD decisions 23-27,
## owner answers 2-4), reached as `GameState.tactics`. Thin wrapper around
## TacticsRules (game/engine/progression).
##
## Actions return {ok, error, params, ...} without the state, like
## ProgressionApi; on success GameState adopts the new state, marks it dirty
## and asks for a save. A refusal's `error` is a strings.csv key filled by
## `params` (GameState.reason_text). `character` "" means the leader.

var _owner: Node


func _init(owner: Node) -> void:
	_owner = owner


func _data() -> Dictionary:
	return _owner.data


func _c() -> Dictionary:
	return Content.index()


func _who(character: String) -> String:
	return character if character != "" else str(_owner.data["party"][0])


func _commit(r: Dictionary) -> Dictionary:
	var out := r.duplicate()
	out.erase("state")
	if r["ok"]:
		_owner.commit_action(r["state"])
	return out


## Owner answer 4: the tactics screen is open from level 1 (true in a game).
func tactics_unlocked() -> bool:
	return _owner.has_game()


## The tactics screen: {character, rows}. Each row (TacticsRules.view) also
## carries its texts: `name`, `say` (the one-line « what Fern will do »),
## each option's `label` (« Le plus proche (par défaut) » for the default),
## and the slider's `label` when the current mode uses one.
func tactics_view(character: String = "") -> Dictionary:
	if not _owner.has_game():
		return {}
	var v := TacticsRules.view(_data(), _who(character), _c())
	for row in v["rows"]:
		row["name"] = _owner.tr(row["name_key"])
		row["say"] = _owner.tr(row["say_key"]).format(row["say_params"])
		for o in row["options"]:
			o["label"] = _owner.tr(o["label_key"]).format(o["label_params"])
			if o["is_default"]:
				o["label"] += " " + _owner.tr("ui.tactics.default_suffix")
		if not row["param"].is_empty():
			var p: Dictionary = row["param"]
			p["label"] = _owner.tr(p["label_key"]).format(p["label_params"])
	return v


## Sets one setting (`key`: "targeting", "mana_reserve", a spell or a
## consumable id) to `value`, with slider values in `params`
## ({barrier_hp_pct, min_enemies}). Saves the delta. {ok, error, params,
## tactics (full CombatTactics dictionary, e.g. for a running fight's
## set_tactic commands)}.
func set_tactic(
	character: String, key: String, value: Variant, params: Dictionary = {}
) -> Dictionary:
	if not _owner.has_game():
		return ActionResult.refuse("error.tactics.unknown_setting")
	return _commit(TacticsRules.set_tactic(_data(), _who(character), key, value, params, _c()))


## « Rétablir les réglages par défaut ». {ok, error, params}.
func reset_tactics(character: String = "") -> Dictionary:
	if not _owner.has_game():
		return ActionResult.refuse("error.tactics.unknown_setting")
	return _commit(TacticsRules.reset(_data(), _who(character)))


## What « Appliquer le conseil » would change: {ok, error, params, lines:
## [{id, name_key, from, to, from_key, to_key, from_params, to_params, text}]}
## with text « Ciblage : Le plus proche → Lanceurs d'abord »; empty lines =
## already applied (ui.tactics.diff_none).
func preset_diff(preset_id: String, character: String = "") -> Dictionary:
	if not _owner.has_game():
		return ActionResult.refuse("error.tactics.unknown_preset")
	var r := TacticsRules.preset_diff(_data(), _who(character), preset_id, _c())
	for line in r.get("lines", []):
		line["text"] = (
			_owner
			. tr("ui.tactics.diff_line")
			. format(
				{
					"setting": _owner.tr(line["name_key"]),
					"from": _owner.tr(line["from_key"]).format(line["from_params"]),
					"to": _owner.tr(line["to_key"]).format(line["to_params"]),
				}
			)
		)
	return r


## Applies a preset and saves. {ok, error, params, tactics}.
func apply_preset(preset_id: String, character: String = "") -> Dictionary:
	if not _owner.has_game():
		return ActionResult.refuse("error.tactics.unknown_preset")
	return _commit(TacticsRules.apply_preset(_data(), _who(character), preset_id, _c()))


## The tip to show now, or {}. `context`: {trigger: "level_reached", level}
## | {trigger: "first_campfire", dungeon} | {trigger: "boss_cast", encounter,
## ability} | {trigger: "defeat", encounter, ability (last_hit.spell of
## encounter_completed)}. Result: {id, title_key, text_key, title, text,
## display (toast | panel | banner | defeat), duration_s, actions
## (apply_preset | open_tactics | later | close), preset, repeat}.
## Call mark_tip_seen(id) once it is shown.
func next_tip(context: Dictionary) -> Dictionary:
	if not _owner.has_game():
		return {}
	var tip := TacticsRules.next_tip(_data(), context, _c())
	if not tip.is_empty():
		tip["title"] = _owner.tr(tip["title_key"])
		tip["text"] = _owner.tr(tip["text_key"])
	return tip


## Records a shown tip (not the repeating defeat tips) and saves.
func mark_tip_seen(tip_id: String) -> Dictionary:
	if not _owner.has_game():
		return ActionResult.refuse("error.tip.unknown")
	return _commit(TacticsRules.mark_tip_seen(_data(), tip_id, _c()))
