extends TestCase

const ITEM := {
	"type": "dict",
	"fields":
	{
		"id": {"type": "string", "prefix": "item.", "pattern": Schema.ID_PATTERN},
		"level": {"type": "int", "min": 1, "max": 60},
		"rarity": {"type": "string", "enum": ["common", "rare"]},
		"tags": {"type": "array", "items": {"type": "string"}, "optional": true, "default": []},
		"spell": {"type": "string", "ref": "spell", "optional": true},
		"stats": {"type": "dict", "values": {"type": "number"}},
	},
}


func _valid() -> Dictionary:
	return {"id": "item.ash_staff", "level": 3.0, "rarity": "rare", "stats": {"power": 12}}


func test_valid_value_normalizes_ints_and_defaults() -> void:
	var r := Schema.validate(_valid(), ITEM)
	assert_eq(r["errors"].size(), 0, "no errors")
	assert_eq(typeof(r["value"]["level"]), TYPE_INT, "level is int")
	assert_eq(r["value"]["tags"], [], "default tags")


func test_reports_each_problem_with_its_path() -> void:
	var bad := {
		"id": "staff", "level": 2.5, "rarity": "mythic", "stats": {"power": "x"}, "extra": 1
	}
	var errors: PackedStringArray = Schema.validate(bad, ITEM)["errors"]
	var text := "\n".join(errors)
	assert_true(text.contains("$.id"), "id prefix")
	assert_true(text.contains("$.level: expected an integer"), "level")
	assert_true(text.contains("$.rarity"), "rarity enum")
	assert_true(text.contains("$.stats.power: expected a number"), "map value")
	assert_true(text.contains("$.extra: unknown field"), "unknown field")


func test_missing_required_field_fails() -> void:
	var value := _valid()
	value.erase("rarity")
	var errors: PackedStringArray = Schema.validate(value, ITEM)["errors"]
	assert_true("\n".join(errors).contains("missing field 'rarity'"), "missing")


func test_bounds_are_enforced() -> void:
	var value := _valid()
	value["level"] = 99
	assert_eq(Schema.validate(value, ITEM)["errors"].size(), 1, "max")


func test_refs_are_collected() -> void:
	var value := _valid()
	value["spell"] = "spell.zoltraak"
	var refs: Array = Schema.validate(value, ITEM)["refs"]
	assert_eq(refs, [["$.spell", "spell", "spell.zoltraak"]], "refs")
