class_name ProgressionFixtures
extends RefCounted
## Helpers for the Milestone 4 tests: shipped content, a fresh state and
## hand-made item instances.

const FERN := "character.fern"


static func content() -> Dictionary:
	return CombatBench.content()


## New game (Fixtures) with `gold` and materials set.
static func state(gold: int = 0, materials: Dictionary = {}, level: int = 1) -> Dictionary:
	var s := Fixtures.new_state()
	s["wallet"]["gold"] = gold
	s["wallet"]["materials"] = materials.duplicate()
	s["characters"][FERN]["level"] = level
	return s


static func item(
	uid: String,
	base: String,
	rarity: String = "common",
	ilvl: int = 1,
	affixes: Array = [],
	enhance: int = 0
) -> Dictionary:
	var list := []
	for a in affixes:
		list.append({"id": a[0], "value": float(a[1])})
	return {
		"uid": uid,
		"item_id": base,
		"rarity": rarity,
		"item_level": ilvl,
		"affixes": list,
		"legendary": "",
		"enhance": enhance,
		"enhance_attempts": 0,
		"pity": 0,
	}


## Adds `count` common staves to the bag (uids b1, b2...).
static func fill_bag(s: Dictionary, count: int) -> void:
	for i in count:
		s["inventory"].append(item("b%d" % (i + 1), "item.birch_staff"))
