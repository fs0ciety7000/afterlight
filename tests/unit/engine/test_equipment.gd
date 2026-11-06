extends TestCase
## Criterion 4.4: equipping then unequipping gives back exactly the original
## stats; modifiers are tagged by source. Plus the equip / unequip refusals.

const P := preload("res://tests/unit/engine/progression_fixtures.gd")
const FERN := "character.fern"


func _gear_state() -> Dictionary:
	var s := P.state()
	var rng := SeededRng.new(11)
	var n := 0
	for slot in StateSchema.EQUIPMENT_SLOTS:
		for base in ItemFactory.catalog(P.content())["bases"][slot]:
			n += 1
			var item := ItemFactory.make_item(rng, P.content(), base, "epic", 12)
			item["uid"] = "g%d" % n
			item["enhance"] = n % 5
			s["inventory"].append(item)
	return s


func test_equip_then_unequip_restores_the_exact_stats() -> void:
	var s := _gear_state()
	var before := Equipment.stats(s, FERN, P.content())
	var worn := s
	for item in s["inventory"]:
		var r := Equipment.equip(worn, FERN, item["uid"], P.content())
		assert_true(r["ok"], "equip %s" % item["uid"])
		worn = r["state"]
	var geared := Equipment.stats(worn, FERN, P.content())
	assert_true(geared["power"] > before["power"], "power grows")
	assert_true(geared["max_hp"] > before["max_hp"], "hp grows")
	var bare := worn
	for slot in StateSchema.EQUIPMENT_SLOTS:
		var r := Equipment.unequip(bare, FERN, slot)
		assert_true(r["ok"], "unequip %s" % slot)
		bare = r["state"]
	assert_eq(Equipment.stats(bare, FERN, P.content()), before, "exact original stats")
	assert_eq(Inventory.bag_count(bare), s["inventory"].size(), "everything back in the bag")


func test_modifiers_are_tagged_and_removed_by_source() -> void:
	var s := _gear_state()
	var a: String = s["inventory"][0]["uid"]
	var b: String = s["inventory"][2]["uid"]
	s = Equipment.equip(s, FERN, a, P.content())["state"]
	var only_a := Equipment.modifiers(s, FERN, P.content())
	s = Equipment.equip(s, FERN, b, P.content())["state"]
	for m in Equipment.modifiers(s, FERN, P.content()):
		assert_true(m["source"] in ["item:" + a, "item:" + b], "tagged %s" % m["source"])
	var slot := Equipment.slot_of(Inventory.find(s, b), P.content())
	s = Equipment.unequip(s, FERN, slot)["state"]
	assert_eq(Equipment.modifiers(s, FERN, P.content()), only_a, "only b's modifiers left")


func test_equipping_over_an_item_swaps_it_back_to_the_bag() -> void:
	var s := P.state()
	s["inventory"] = [
		P.item("x1", "item.birch_staff", "common", 3), P.item("x2", "item.birch_staff", "rare", 5)
	]
	var before := Equipment.stats(s, FERN, P.content())
	s = Equipment.equip(s, FERN, "x1", P.content())["state"]
	var r := Equipment.equip(s, FERN, "x2", P.content())
	assert_eq(r["replaced"], "x1", "x1 replaced")
	assert_eq(r["state"]["characters"][FERN]["equipment"]["weapon"], "x2", "x2 worn")
	assert_eq(Inventory.bag_count(r["state"]), 1, "x1 back in the bag")
	var off: Dictionary = Equipment.unequip(r["state"], FERN, "weapon")["state"]
	assert_eq(Equipment.stats(off, FERN, P.content()), before, "back to the original")


func test_refusals_carry_a_reason() -> void:
	var s := P.state()
	assert_eq(Equipment.equip(s, FERN, "nope", P.content())["error"], "error.item_not_found", "uid")
	assert_eq(Equipment.unequip(s, FERN, "weapon")["error"], "error.slot_empty", "empty slot")
	P.fill_bag(s, BalanceItems.INVENTORY_SLOTS)
	s["inventory"].append(P.item("w", "item.birch_staff"))
	s["characters"][FERN]["equipment"]["weapon"] = "w"
	var r := Equipment.unequip(s, FERN, "weapon")
	assert_eq(r["error"], "error.inventory_full", "full bag")
	assert_eq(r["params"], {"max": 60}, "reason params")


func test_stats_feed_the_combat_setup() -> void:
	var s := P.state()
	s["inventory"] = [P.item("x1", "item.birch_staff", "rare", 10, [], 4)]
	s = Equipment.equip(s, FERN, "x1", P.content())["state"]
	var flat: Dictionary = Equipment.bonuses(s, FERN, P.content())["flat"]
	assert_near(flat["power"], 20.98, 0.01, "§2.2 staff implicit at +4")
	var sim := (
		CombatSim
		. create(
			{
				"encounter": "encounter.whispering_wood_01",
				"seed": 1,
				"party":
				[
					{
						"character": FERN,
						"level": 1,
						"flat": Equipment.bonuses(s, FERN, P.content())["flat"],
					}
				],
			},
			P.content()
		)
	)
	assert_near(sim.units[0]["stats"]["power"], 30.0 + 20.98, 0.01, "combat power")
