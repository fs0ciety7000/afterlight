extends TestCase
## GameState.tactics: French texts of the tactics screen, saved deltas that
## survive a save and reload, tips seen once (GDD decisions 23-27).

const F := preload("res://tests/unit/engine/story_fixtures.gd")

var _real_store: SaveStore


func _begin(level: int) -> void:
	_real_store = SaveService.store
	SaveService.store = SaveStore.new("user://test_saves/tactics_%d" % Time.get_ticks_usec())
	GameState.adopt(F.state(level), false)


func _end() -> void:
	SaveService.store = _real_store
	GameState.clear()


func _row(id: String) -> Dictionary:
	for row in GameState.tactics.tactics_view()["rows"]:
		if row["id"] == id:
			return row
	return {}


func test_view_texts_in_french() -> void:
	_begin(2)
	assert_true(GameState.tactics.tactics_unlocked(), "open from the start")
	var barrier := _row("spell.defensive_barrier")
	assert_eq(barrier["name"], "Barrière défensive", "name")
	assert_eq(
		barrier["say"],
		"Fern se protège juste avant un coup annoncé, ou si ses PV passent sous 30 %.",
		"what Fern will do"
	)
	assert_eq(
		barrier["options"][3]["label"],
		"Avant un coup télégraphé, sinon sous X % (par défaut)",
		"default flagged"
	)
	assert_eq(barrier["param"]["label"], "30 %", "slider label")
	assert_eq(
		_row("consumable.healing_draught")["options"][1]["label"], "Auto si PV < 35 %", "infusion"
	)
	assert_true(_row("spell.mana_volley").is_empty(), "Volley hidden before level 3")
	_end()


func test_set_tactic_saves_and_reloads() -> void:
	_begin(5)
	var r := GameState.tactics.set_tactic(
		"", "spell.mana_volley", "auto_min_enemies", {"min_enemies": 2}
	)
	assert_true(r["ok"], "set")
	assert_eq(
		_row("spell.mana_volley")["say"],
		"Fern lance la Salve s'il reste au moins 2 ennemis à portée.",
		"live text"
	)
	var text := SaveCodec.encode(GameState.data, 1)
	var back := SaveCodec.decode(text, SaveMigrations.all())
	assert_true(back["ok"], "reloads")
	TacticsRules.sanitize(back["state"], CombatBench.content())
	assert_eq(
		back["state"]["characters"]["character.fern"]["tactics"], {"min_enemies": 2}, "delta saved"
	)
	assert_eq(GameState.progression.combat_setup()["tactics"], {"min_enemies": 2}, "fights use it")
	var bad := GameState.tactics.set_tactic("", "spell.mana_volley", "auto_full")
	assert_eq(GameState.reason_text(bad), "Valeur refusée pour ce réglage", "refusal text")
	assert_true(GameState.tactics.reset_tactics()["ok"], "reset")
	assert_eq(GameState.data["characters"]["character.fern"]["tactics"], {}, "nothing saved")
	_end()


func test_preset_diff_text_and_tips() -> void:
	_begin(12)
	var d := GameState.tactics.preset_diff("tactics_preset.morvaine")
	assert_eq(d["lines"][0]["text"], "Ciblage : Le plus proche → Lanceurs d'abord", "diff line")
	assert_true(GameState.tactics.apply_preset("tactics_preset.morvaine")["ok"], "applied")
	assert_eq(GameState.tactics.preset_diff("tactics_preset.morvaine")["lines"], [], "nothing left")
	var tip := GameState.tactics.next_tip(
		{"trigger": "first_campfire", "dungeon": "dungeon.silent_dial_cloister"}
	)
	assert_true(tip["text"].begins_with("Plus loin, la gardienne du cadran"), "tip text")
	GameState.tactics.mark_tip_seen(tip["id"])
	assert_true(
		(
			GameState
			. tactics
			. next_tip({"trigger": "first_campfire", "dungeon": "dungeon.silent_dial_cloister"})
			. is_empty()
		),
		"once per save"
	)
	_end()


func test_invalid_saved_tactics_are_ignored_on_load() -> void:
	var s := F.state(5)
	s["characters"]["character.fern"]["tactics"] = {"targeting": "everyone", "min_enemies": 4}
	_real_store = SaveService.store
	SaveService.store = SaveStore.new("user://test_saves/tactics_%d" % Time.get_ticks_usec())
	GameState.adopt(s, false)
	assert_eq(GameState.data["characters"]["character.fern"]["tactics"], {"min_enemies": 4}, "kept")
	_end()
