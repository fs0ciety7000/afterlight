extends TestCase
## Saved tactics and tips (GDD decisions 23-27 and owner answers): partial
## deltas per character, the tactics view, presets, tips seen once.

const P := preload("res://tests/unit/engine/progression_fixtures.gd")
const FERN := "character.fern"
const BARRIER := "spell.defensive_barrier"
const VOLLEY := "spell.mana_volley"
const DRAUGHT := "consumable.healing_draught"
const PRESET := "tactics_preset.morvaine"


func _rows(s: Dictionary) -> Dictionary:
	var out := {}
	for row in TacticsRules.view(s, FERN, P.content())["rows"]:
		out[row["id"]] = row
	return out


func test_new_game_has_no_saved_tactics_and_no_tip_seen() -> void:
	var s := P.state()
	assert_eq(s["characters"][FERN]["tactics"], {}, "no delta")
	assert_eq(s["progress"]["tips_seen"], [], "no tip")


func test_view_lists_learned_spells_in_order_with_defaults() -> void:
	var ids := []
	for row in TacticsRules.view(P.state(0, {}, 1), FERN, P.content())["rows"]:
		ids.append(row["id"])
	assert_eq(
		ids,
		[
			"targeting",
			"spell.zoltraak",
			"consumable.healing_draught",
			"consumable.mana_elixir",
			"mana_reserve"
		],
		"level 1: Barrier, Volley, ultimate hidden"
	)
	var rows := _rows(P.state(0, {}, 5))
	assert_eq(rows.size(), 8, "every row at level 5")
	var barrier: Dictionary = rows[BARRIER]
	assert_eq(
		[barrier["current"], barrier["default"]],
		["auto_telegraph_or_hp"] + ["auto_telegraph_or_hp"],
		"default"
	)
	assert_true(barrier["is_default"], "flagged default")
	assert_eq(barrier["say_key"], "ui.tactics.say.defensive_barrier.auto_telegraph_or_hp", "say")
	assert_eq(barrier["say_params"], {"x": 30}, "30 %")
	assert_eq(barrier["param"]["key"], "barrier_hp_pct", "slider")
	var modes := []
	for o in barrier["options"]:
		modes.append(o["id"])
	assert_eq(
		modes,
		["manual", "auto_hp_below", "auto_before_telegraph", "auto_telegraph_or_hp"],
		"options"
	)
	assert_true(rows["spell.zoltraak"]["param"].is_empty(), "no slider for Zoltraak")
	assert_eq(rows["mana_reserve"]["say_params"], {"x": 20}, "reserve 20 %")
	assert_eq(rows[DRAUGHT]["current"], "auto_low_hp", "infusion Auto (GDD decision 32)")
	assert_eq(rows[DRAUGHT]["say_params"], {"x": 30}, "under 30 %")


func test_set_tactic_saves_only_the_delta_and_refuses_bad_values() -> void:
	var s := P.state(0, {}, 5)
	var r := TacticsRules.set_tactic(
		s, FERN, VOLLEY, "auto_min_enemies", {"min_enemies": 4}, P.content()
	)
	assert_true(r["ok"], "set (%s)" % r)
	assert_eq(
		r["state"]["characters"][FERN]["tactics"], {"min_enemies": 4}, "only the slider differs"
	)
	r = TacticsRules.set_tactic(r["state"], FERN, BARRIER, "auto_before_telegraph", {}, P.content())
	assert_eq(
		r["state"]["characters"][FERN]["tactics"],
		{"min_enemies": 4, "spells": {BARRIER: "auto_before_telegraph"}},
		"delta"
	)
	assert_eq(s["characters"][FERN]["tactics"], {}, "input untouched")
	var back := TacticsRules.set_tactic(
		r["state"], FERN, BARRIER, "auto_telegraph_or_hp", {}, P.content()
	)
	assert_eq(back["state"]["characters"][FERN]["tactics"], {"min_enemies": 4}, "back to default")
	var bad := TacticsRules.set_tactic(s, FERN, BARRIER, "auto_full", {}, P.content())
	assert_eq(bad["error"], "error.tactics.invalid_value", "invalid mode")
	bad = TacticsRules.set_tactic(s, FERN, "fly", "yes", {}, P.content())
	assert_eq(bad["error"], "error.tactics.unknown_setting", "unknown key")
	bad = TacticsRules.set_tactic(P.state(0, {}, 1), FERN, VOLLEY, "auto", {}, P.content())
	assert_eq(bad["error"], "error.spell_locked", "not learned yet")
	var reserve := TacticsRules.set_tactic(s, FERN, "mana_reserve", 0.3, {}, P.content())
	assert_eq(reserve["state"]["characters"][FERN]["tactics"], {"mana_reserve": 0.3}, "reserve")
	var reset := TacticsRules.reset(r["state"], FERN)
	assert_eq(reset["state"]["characters"][FERN]["tactics"], {}, "reset")


func test_saved_tactics_reach_the_combat_setup() -> void:
	var s := P.state(0, {}, 5)
	s = TacticsRules.set_tactic(s, FERN, "targeting", "casters_first", {}, P.content())["state"]
	var setup := PartyBuild.setup(s, P.content())
	assert_eq(setup["tactics"], {"targeting": "casters_first"}, "partial tactics in the setup")
	setup["encounter"] = "encounter.whispering_wood_02"
	setup["seed"] = 1
	var sim := CombatSim.create(setup, P.content())
	assert_eq(sim.tactics["targeting"], "casters_first", "the sim plays them")


func test_invalid_saved_values_are_dropped_on_load() -> void:
	var s := P.state(0, {}, 5)
	s["characters"][FERN]["tactics"] = {
		"targeting": "everyone",
		"mana_reserve": 0.3,
		"spells": {BARRIER: "auto_full", VOLLEY: "auto"}
	}
	var dropped := TacticsRules.sanitize(s, P.content())
	assert_eq(
		s["characters"][FERN]["tactics"], {"mana_reserve": 0.3, "spells": {VOLLEY: "auto"}}, "kept"
	)
	assert_eq(dropped.size(), 2, "two values dropped (%s)" % [dropped])


func test_preset_diff_then_apply() -> void:
	var s := P.state(0, {}, 12)
	var d := TacticsRules.preset_diff(s, FERN, PRESET, P.content())
	assert_true(d["ok"], "diff")
	var keys := []
	for line in d["lines"]:
		keys.append(line["id"])
	# The infusion is already on Auto by default (GDD decision 32): no change.
	assert_eq(keys, ["targeting", BARRIER], "two changes, in row order")
	assert_eq(d["lines"][0]["from_key"], "ui.tactics.targeting.nearest", "from")
	assert_eq(d["lines"][0]["to_key"], "ui.tactics.targeting.casters_first", "to")
	var r := TacticsRules.apply_preset(s, FERN, PRESET, P.content())
	assert_eq(
		r["state"]["characters"][FERN]["tactics"],
		{"targeting": "casters_first", "spells": {BARRIER: "auto_before_telegraph"}},
		"applied as a delta"
	)
	assert_eq(
		TacticsRules.preset_diff(r["state"], FERN, PRESET, P.content())["lines"], [], "no diff left"
	)
	assert_eq(
		TacticsRules.apply_preset(s, FERN, "tactics_preset.none", P.content())["error"],
		"error.tactics.unknown_preset",
		"unknown"
	)


func test_tips_once_except_defeat_tips() -> void:
	var c := P.content()
	var s := P.state(0, {}, 1)
	assert_true(
		TacticsRules.next_tip(s, {"trigger": "level_reached", "level": 1}, c).is_empty(),
		"nothing at level 1"
	)
	var tip := TacticsRules.next_tip(s, {"trigger": "level_reached", "level": 2}, c)
	assert_eq(tip["id"], "tip.barrier_unlocked", "barrier tip at level 2")
	assert_eq(tip["text_key"], "tip.barrier_unlocked", "text key")
	s = TacticsRules.mark_tip_seen(s, "tip.barrier_unlocked", c)["state"]
	assert_eq(s["progress"]["tips_seen"], ["tip.barrier_unlocked"], "seen")
	assert_true(
		TacticsRules.next_tip(s, {"trigger": "level_reached", "level": 3}, c).is_empty(), "once"
	)
	var camp := TacticsRules.next_tip(
		s, {"trigger": "first_campfire", "dungeon": "dungeon.silent_dial_cloister"}, c
	)
	assert_eq(
		[camp["id"], camp["preset"], camp["display"]],
		["tip.campfire_tactics", PRESET, "panel"],
		"campfire"
	)
	assert_eq(camp["actions"], ["apply_preset", "open_tactics", "later"], "buttons")
	var seal := {
		"trigger": "boss_cast",
		"encounter": "encounter.cloister_boss",
		"ability": "ability.morvaine_ash_seal"
	}
	assert_eq(TacticsRules.next_tip(s, seal, c)["duration_s"], 3.0, "3 s banner")
	var defeat := {
		"trigger": "defeat",
		"encounter": "encounter.cloister_boss",
		"ability": "ability.morvaine_ash_seal_hollow"
	}
	assert_eq(TacticsRules.next_tip(s, defeat, c)["id"], "tip.defeat_ash_seal", "seal defeat")
	var again := TacticsRules.mark_tip_seen(s, "tip.defeat_ash_seal", c)
	assert_true(again["ok"], "ok")
	assert_eq(
		again["state"]["progress"]["tips_seen"],
		["tip.barrier_unlocked"],
		"defeat tips are not stored"
	)
	assert_eq(
		TacticsRules.next_tip(again["state"], defeat, c)["id"], "tip.defeat_ash_seal", "repeats"
	)
	defeat["ability"] = "ability.morvaine_enrage"
	assert_eq(TacticsRules.next_tip(s, defeat, c)["id"], "tip.defeat_enrage", "enrage defeat")
	defeat["ability"] = "ability.lantern_bolt"
	assert_true(TacticsRules.next_tip(s, defeat, c).is_empty(), "no tip for other causes")
	assert_eq(
		TacticsRules.mark_tip_seen(s, "tip.nope", c)["error"], "error.tip.unknown", "unknown tip"
	)
