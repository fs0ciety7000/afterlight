extends TestCase
## Criterion 4.7: a full bag salvages item loot into mana dust with a summary
## line, nothing is lost silently; bulk salvage by rarity; stacks and caps.

const P := preload("res://tests/unit/engine/progression_fixtures.gd")
const FERN := "character.fern"


func _drops(count: int, rarity: String = "rare", ilvl: int = 10) -> Array:
	var out := []
	for i in count:
		var item := P.item("", "item.birch_staff", rarity, ilvl)
		out.append(item)
	return out


func test_loot_gets_stable_uids_in_the_bag() -> void:
	var s := P.state()
	var r := Inventory.receive(s, {"items": _drops(2)}, P.content())
	assert_eq(r["items"], ["i1", "i2"], "uids")
	assert_eq(s["rng"]["item"], 2, "counter saved")
	assert_eq(Inventory.bag_count(s), 2, "in the bag")
	assert_eq(r["lines"], [], "no salvage line")


func test_full_bag_salvages_loot_with_a_summary_line() -> void:
	var s := P.state(0, {"material.mana_dust": 3})
	P.fill_bag(s, BalanceItems.INVENTORY_SLOTS - 1)
	var r := Inventory.receive(s, {"items": _drops(3)}, P.content())
	assert_eq(r["items"].size(), 1, "one fits")
	assert_eq(r["auto_salvaged"].size(), 2, "two salvaged")
	assert_eq(r["items"].size() + r["auto_salvaged"].size(), 3, "nothing lost")
	var each := BalanceItems.salvage_dust("rare", 10)
	assert_eq(each, 22, "floor(12 × 1.9)")
	assert_eq(r["salvage_dust"], 2 * each, "dust total")
	assert_eq(s["wallet"]["materials"]["material.mana_dust"], 3 + 2 * each, "dust added")
	assert_eq(
		r["lines"],
		[{"key": "log.loot.auto_salvaged_other", "params": {"count": 2, "dust": 2 * each}}],
		"summary line"
	)
	assert_eq(Inventory.bag_count(s), BalanceItems.INVENTORY_SLOTS, "bag full, not over")


func test_worn_items_do_not_take_bag_slots() -> void:
	var s := P.state()
	P.fill_bag(s, BalanceItems.INVENTORY_SLOTS)
	s["characters"][FERN]["equipment"]["weapon"] = "b1"
	assert_eq(Inventory.bag_count(s), BalanceItems.INVENTORY_SLOTS - 1, "59 in the bag")
	var r := Inventory.receive(s, {"items": _drops(2, "common", 1)}, P.content())
	assert_eq(r["items"].size(), 1, "one more fits")
	assert_eq(
		r["lines"][0],
		{"key": "log.loot.auto_salvaged_one", "params": {"count": 1, "dust": 2}},
		"one"
	)


func test_bulk_salvage_by_rarity_keeps_worn_and_other_rarities() -> void:
	var s := P.state()
	s["inventory"] = [
		P.item("c1", "item.birch_staff", "common", 1),
		P.item("c2", "item.wool_robe", "common", 5),
		P.item("u1", "item.wool_robe", "uncommon", 3),
		P.item("c3", "item.cloth_gloves", "common", 2),
	]
	s["characters"][FERN]["equipment"]["hands"] = "c3"
	var quote := Inventory.salvage_quote(s, ["common"])
	assert_eq(quote["uids"], ["c1", "c2"], "worn c3 kept")
	assert_eq(quote["dust"], 2 + floori(2 * 1.4), "dust 2 + 2")
	var r := Inventory.salvage_by_rarity(s, ["common"])
	assert_true(r["ok"], "ok")
	assert_eq(r["count"], 2, "count")
	var left := []
	for item in r["state"]["inventory"]:
		left.append(item["uid"])
	assert_eq(left, ["u1", "c3"], "left")
	assert_eq(r["state"]["wallet"]["materials"]["material.mana_dust"], quote["dust"], "dust")
	assert_eq(Inventory.salvage(s, ["c3"])["error"], "error.item_not_found", "worn refused")
	assert_eq(Inventory.salvage_by_rarity(s, ["epic"])["error"], "error.nothing_to_salvage", "none")


func test_runes_artifacts_and_consumables_stack_with_caps() -> void:
	var s := P.state()
	s["consumables"]["consumable.healing_draught"] = 4
	var r := (
		Inventory
		. receive(
			s,
			{
				"runes": [{"id": "rune.ember", "tier": 2}, {"id": "rune.ember", "tier": 2}],
				"artifacts": ["artifact.ashen_bell"],
				"consumables": {"consumable.healing_draught": 3},
			},
			P.content()
		)
	)
	assert_eq(s["runes"]["rune.ember"], [0, 2, 0, 0, 0], "rune stack by tier")
	assert_eq(s["artifacts"], {"artifact.ashen_bell": 1}, "artifact owned at level 1")
	assert_eq(s["consumables"]["consumable.healing_draught"], 5, "capped at 5")
	assert_eq(
		r["lines"],
		[
			{
				"key": "log.loot.consumable_overflow",
				"params": {"max": 5, "item": "consumable.healing_draught.name", "count": 2},
			}
		],
		"overflow reported"
	)
	var again := Inventory.receive(s, {"artifacts": ["artifact.ashen_bell"]}, P.content())
	assert_eq(again["lines"][0]["key"], "log.loot.artifact_known", "duplicate reported")
	assert_eq(StateSchema.validate(s)["errors"].size(), 0, "state stays valid")
