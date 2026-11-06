extends TestCase
## Engine side of criterion 4.8 and determinism: victory → item in the bag →
## equip → the stat changes → enhance → save → reload → identical state; the
## same seed replays the whole chain to the same state.

const P := preload("res://tests/unit/engine/progression_fixtures.gd")
const FERN := "character.fern"


func _completed(seed_value: int) -> Dictionary:
	var sim := CombatSim.create(
		{
			"encounter": "encounter.cloister_alpha",
			"seed": seed_value,
			"party": [CombatBench.fern(11)]
		},
		P.content()
	)
	for u in sim.units:
		if u["side"] == "enemy":
			sim.kills.append(u["uid"])
	return {
		"type": "encounter_completed",
		"encounter": "encounter.cloister_alpha",
		"result": "victory",
		"rewards": CombatRewards.compute(sim),
		"consumables_used": {},
	}


func _play(seed_value: int) -> Dictionary:
	var s := P.state(5000, {"material.mana_dust": 50}, 11)
	var out := CombatOutcome.apply(s, _completed(seed_value), P.content())
	s = out["state"]
	var uid: String = out["summary"]["items"][0]
	var before := Equipment.stats(s, FERN, P.content())
	s = Equipment.equip(s, FERN, uid, P.content())["state"]
	var worn := Equipment.stats(s, FERN, P.content())
	var enhanced := Forge.enhance(s, uid)
	s = enhanced["state"]
	return {
		"state": s,
		"uid": uid,
		"before": before,
		"worn": worn,
		"after": Equipment.stats(s, FERN, P.content()),
		"enhanced": enhanced,
	}


func test_victory_equip_enhance_save_reload() -> void:
	var run := _play(21)
	assert_true(run["before"] != run["worn"], "equipping changes a stat")
	assert_true(run["enhanced"]["ok"] and run["enhanced"]["success"], "+1 is guaranteed")
	assert_true(run["after"] != run["worn"], "enhancing changes a stat")
	var text := SaveCodec.encode(run["state"], 1)
	var loaded := SaveCodec.decode(text, SaveMigrations.all())
	assert_true(loaded["ok"], "reload (%s %s)" % [loaded["error"], loaded["detail"]])
	assert_eq(
		SaveCodec.canonical(loaded["state"]), SaveCodec.canonical(run["state"]), "identical state"
	)
	assert_eq(Equipment.stats(loaded["state"], FERN, P.content()), run["after"], "identical stats")


func test_same_seed_replays_to_the_same_state() -> void:
	var a := _play(33)
	var b := _play(33)
	assert_eq(SaveCodec.canonical(a["state"]), SaveCodec.canonical(b["state"]), "same state")
	var c := _play(34)
	assert_true(
		SaveCodec.canonical(c["state"]) != SaveCodec.canonical(a["state"]), "another seed differs"
	)
