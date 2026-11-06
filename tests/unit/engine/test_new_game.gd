extends TestCase


func test_new_game_state_is_valid() -> void:
	var state := Fixtures.new_state()
	var r := StateSchema.validate(state)
	assert_eq(r["errors"].size(), 0, "errors: %s" % "\n".join(r["errors"]))


func test_new_game_uses_start_definition() -> void:
	var state := Fixtures.new_state(77, 1_800_000_500)
	assert_eq(state["party"], ["character.fern", "", "", ""], "party")
	assert_eq(state["characters"]["character.fern"]["level"], 1, "level 1")
	assert_eq(state["wallet"]["gold"], 100, "gold")
	assert_eq(state["world"]["unlocked_regions"], ["region.test_vale"], "region unlocked")
	assert_eq(state["meta"]["seed"], 77, "seed")
	assert_eq(state["meta"]["created_at"], 1_800_000_500, "created_at")


func test_new_game_is_deterministic() -> void:
	assert_eq(Fixtures.new_state(5, 10), Fixtures.new_state(5, 10), "same inputs, same state")


func test_party_member_must_exist() -> void:
	var state := Fixtures.new_state()
	state["party"][1] = "character.ghost"
	var errors: PackedStringArray = StateSchema.validate(state)["errors"]
	assert_true("\n".join(errors).contains("character.ghost"), "dangling party member")
