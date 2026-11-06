extends TestCase
## "Chasser ici" engine helpers (GDD §12, ROADMAP 5.8).

const WOLVES := "encounter.whispering_wood_02"
const ALPHA := "encounter.cloister_alpha"
const P := preload("res://tests/unit/engine/progression_fixtures.gd")


func _state() -> Dictionary:
	var s := P.state(0, {}, 10)
	s["progress"]["cleared_encounters"][WOLVES] = 1
	return s


func test_only_a_won_encounter() -> void:
	var c := P.content()
	var s := _state()
	assert_true(HuntLoop.check(s, WOLVES, c)["ok"], "won")
	assert_eq(HuntLoop.check(s, ALPHA, c)["error"], "error.hunt.not_cleared", "not won")
	assert_eq(HuntLoop.check(s, "encounter.nope", c)["error"], "error.hunt.unknown_encounter")


func test_normal_dungeon_rooms_are_not_hunted() -> void:
	var c := P.content()
	var s := _state()
	s["progress"]["cleared_encounters"]["encounter.cloister_vestibule"] = 1
	assert_eq(
		HuntLoop.check(s, "encounter.cloister_vestibule", c)["error"],
		"error.hunt.dungeon_room",
		"an expedition, not a hunt"
	)


func test_an_elite_is_hunted_here_but_not_offline() -> void:
	var c := P.content()
	var s := _state()
	s["progress"]["cleared_encounters"][ALPHA] = 1
	s["farming"] = WOLVES
	var r := HuntLoop.start(s, ALPHA, c)
	assert_true(r["ok"], "hunt here")
	assert_true(not r["offline_hunt"], "not the offline hunt")
	assert_eq(r["offline_error"], "error.offline.not_normal", "why")
	assert_eq(r["state"]["farming"], WOLVES, "offline hunt unchanged")
	var normal := HuntLoop.start(s, WOLVES, c)
	assert_true(normal["offline_hunt"], "a normal encounter becomes the offline hunt")


func test_each_fight_has_its_own_seed_and_is_reproducible() -> void:
	var c := P.content()
	var first := HuntLoop.next_fight(_state(), WOLVES, c)
	var second := HuntLoop.next_fight(first["state"], WOLVES, c)
	assert_eq(first["state"]["rng"]["combat"], 1, "counter advanced")
	assert_true(first["setup"]["seed"] != second["setup"]["seed"], "new seed")
	assert_eq(HuntLoop.next_fight(_state(), WOLVES, c)["setup"], first["setup"], "same input")
	assert_eq(first["setup"]["first_clear"], false, "repeat loot")
	var sim := CombatSim.create(first["setup"], c)
	while not sim.finished:
		sim.step()
	var done := {}
	for e in sim.event_log:
		if e["type"] == "encounter_completed":
			done = e
	assert_eq(HuntLoop.continues(done), done["result"] == "victory", "stop on defeat only")
	assert_true(not HuntLoop.continues({"result": "defeat"}), "defeat stops")
