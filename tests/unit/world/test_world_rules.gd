extends TestCase

const CONTENT := {
	"location.village":
	{
		"_type": "location",
		"region": "region.vale",
		"name_key": "location.village.name",
		"unlock": {"start": true},
		"fog_reveal": ["location.wood", "location.marsh"],
		"encounters": [],
	},
	"location.wood":
	{
		"_type": "location",
		"region": "region.vale",
		"name_key": "location.wood.name",
		"unlock": {"start": true},
		"fog_reveal": ["location.ruins"],
		"encounters": [],
	},
	"location.marsh":
	{
		"_type": "location",
		"region": "region.vale",
		"name_key": "location.marsh.name",
		"unlock": {"level_at_least": 4},
		"fog_reveal": [],
		"encounters": [],
	},
	"location.ruins":
	{
		"_type": "location",
		"region": "region.vale",
		"name_key": "location.ruins.name",
		"unlock": {"all": [{"level_at_least": 2}, {"quest_completed": "quest.q1"}]},
		"fog_reveal": [],
		"encounters": [],
	},
	"quest.q1": {"_type": "quest", "name_key": "quest.q1.name"},
}

const START := {
	"party": ["character.fern"],
	"region": "region.vale",
	"location": "location.village",
	"gold": 0,
}


func _state() -> Dictionary:
	return NewGame.create(START, 1, 1, CONTENT)


func test_new_game_reveals_the_neighbours_of_the_start() -> void:
	var s := _state()
	assert_eq(WorldRules.status("location.village", s, CONTENT), WorldRules.AVAILABLE, "village")
	assert_eq(WorldRules.status("location.wood", s, CONTENT), WorldRules.AVAILABLE, "wood")
	assert_eq(WorldRules.status("location.marsh", s, CONTENT), WorldRules.LOCKED, "marsh locked")
	assert_eq(WorldRules.status("location.ruins", s, CONTENT), WorldRules.HIDDEN, "ruins hidden")


func test_locked_location_explains_why() -> void:
	var r := WorldRules.reason(CONTENT["location.marsh"]["unlock"], _state(), CONTENT)
	assert_eq(r, {"key": "ui.lock.level", "params": {"level": 4}}, "level reason")
	var s := _state()
	s["characters"]["character.fern"]["level"] = 3
	var q := WorldRules.reason(CONTENT["location.ruins"]["unlock"], s, CONTENT)
	assert_eq(q["key"], "ui.lock.quest", "first unmet sub-condition")
	assert_eq(q["params"]["quest"], "quest.q1.name", "quest name key")


func test_travel_moves_and_lifts_fog() -> void:
	var r := WorldRules.travel("location.wood", "from_village", _state(), CONTENT)
	assert_true(r["ok"], "travel ok")
	var s: Dictionary = r["state"]
	assert_eq(s["world"]["location_id"], "location.wood", "moved")
	assert_eq(s["world"]["spawn"], "from_village", "spawn")
	assert_true(s["world"]["discovered_locations"].has("location.wood"), "discovered")
	assert_eq(WorldRules.status("location.ruins", s, CONTENT), WorldRules.LOCKED, "ruins revealed")


func test_travel_is_refused_when_locked_hidden_or_unknown() -> void:
	var s := _state()
	assert_eq(
		WorldRules.travel("location.marsh", "default", s, CONTENT)["error"],
		"not_available",
		"locked"
	)
	assert_eq(
		WorldRules.travel("location.ruins", "default", s, CONTENT)["error"],
		"not_available",
		"hidden"
	)
	assert_eq(
		WorldRules.travel("location.nope", "default", s, CONTENT)["error"],
		"unknown_location",
		"unknown"
	)


func test_travel_does_not_mutate_the_input_state() -> void:
	var s := _state()
	var before := SaveCodec.canonical(s)
	WorldRules.travel("location.wood", "default", s, CONTENT)
	assert_eq(SaveCodec.canonical(s), before, "input untouched")


func test_conditions_unlock_as_the_player_progresses() -> void:
	var s := _state()
	s["characters"]["character.fern"]["level"] = 4
	assert_eq(
		WorldRules.status("location.marsh", s, CONTENT), WorldRules.AVAILABLE, "level 4 opens marsh"
	)
	s = WorldRules.travel("location.wood", "default", s, CONTENT)["state"]
	s["progress"]["quests"]["quest.q1"] = {"state": "turned_in", "step": 1, "counts": {}}
	assert_eq(
		WorldRules.status("location.ruins", s, CONTENT), WorldRules.AVAILABLE, "quest + level"
	)
