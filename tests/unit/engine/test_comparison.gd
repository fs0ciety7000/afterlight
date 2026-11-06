extends TestCase
## Criterion 4.9: the green / red comparison is right on 20 witness pairs.
## Each pair lists the expected sign of the stats that differ ("stat|layer");
## every other compared stat must be "equal".

const P := preload("res://tests/unit/engine/progression_fixtures.gd")


func _pairs() -> Array:
	var staff := "item.birch_staff"
	var robe := "item.wool_robe"
	var amulet := "item.copper_amulet"
	var gloves := "item.cloth_gloves"
	var boots := "item.walking_boots"
	return [
		# 1-3: item level.
		[
			P.item("a", staff, "common", 5),
			P.item("b", staff, "common", 3),
			{"power|flat": "better"}
		],
		[P.item("a", staff, "common", 3), P.item("b", staff, "common", 5), {"power|flat": "worse"}],
		[P.item("a", staff, "rare", 4), P.item("b", staff, "rare", 4), {}],
		# 4-5: enhancement against rarity (8.736 / 8.268 against 8.58).
		[
			P.item("a", staff, "common", 3, [], 2),
			P.item("b", staff, "uncommon", 3),
			{"power|flat": "better"}
		],
		[
			P.item("a", staff, "common", 3, [], 1),
			P.item("b", staff, "uncommon", 3),
			{"power|flat": "worse"}
		],
		# 6-7: affixes on one side only.
		[
			P.item("a", staff, "common", 2, [["affix.power_pct", 0.05]]),
			P.item("b", staff, "common", 2),
			{"power|percent": "better"}
		],
		[
			P.item("a", staff, "common", 2, [["affix.crit_chance", 0.03]]),
			P.item("b", staff, "common", 2, [["affix.crit_damage", 0.1]]),
			{"crit_chance|flat": "better", "crit_damage|flat": "worse"}
		],
		# 8: empty slot.
		[P.item("a", staff, "common", 1), {}, {"power|flat": "better"}],
		# 9-10: chest, two implicit stats; flat against percent HP.
		[
			P.item("a", robe, "common", 5),
			P.item("b", robe, "rare", 5),
			{"max_hp|flat": "worse", "defense|flat": "worse"}
		],
		[
			P.item("a", robe, "rare", 5, [["affix.max_hp_pct", 0.04]]),
			P.item("b", robe, "rare", 5, [["affix.max_hp_flat", 20]]),
			{"max_hp|percent": "better", "max_hp|flat": "worse"}
		],
		# 11-12: amulet crit follows the tier (ilvl 1 → 0.02, 6 and 10 → 0.025).
		[
			P.item("a", amulet, "common", 1),
			P.item("b", amulet, "common", 6),
			{"crit_chance|flat": "worse"}
		],
		[P.item("a", amulet, "common", 6), P.item("b", amulet, "common", 10), {}],
		# 13: enhancement scales implicit and flat affixes.
		[
			P.item("a", gloves, "common", 4, [["affix.power_flat", 3]]),
			P.item("b", gloves, "common", 4, [["affix.power_flat", 3]], 2),
			{"power|flat": "worse", "defense|flat": "worse"}
		],
		# 14: different affix families.
		[
			P.item("a", boots, "uncommon", 2, [["affix.move_speed", 0.04]]),
			P.item("b", boots, "uncommon", 2, [["affix.gold_find", 0.06]]),
			{"move_speed|percent": "better", "gold_find|flat": "worse"}
		],
		# 15: another base of the same slot, higher ilvl.
		[
			P.item("a", "item.traveler_hood", "common", 7),
			P.item("b", "item.sage_circlet", "common", 8),
			{"max_hp|flat": "worse", "defense|flat": "worse"}
		],
		# 16: same affix, smaller roll.
		[
			P.item("a", "item.sage_circlet", "rare", 8, [["affix.mana_regen", 0.5]]),
			P.item("b", "item.sage_circlet", "rare", 8, [["affix.mana_regen", 0.6]]),
			{"mana_regen|flat": "worse"}
		],
		# 17: epic ilvl 10 (19.035) against legendary ilvl 9 (19.8).
		[
			P.item("a", staff, "epic", 10),
			P.item("b", "item.ashwood_staff", "legendary", 9),
			{"power|flat": "worse"}
		],
		# 18: two elements.
		[
			P.item("a", staff, "rare", 6, [["affix.element_bonus_fire", 0.1]]),
			P.item("b", staff, "rare", 6, [["affix.element_bonus_frost", 0.1]]),
			{"element_bonus_fire|flat": "better", "element_bonus_frost|flat": "worse"}
		],
		# 19: enhanced flat affix beats a bigger raw roll (10.62 against 9.5).
		[
			P.item("a", staff, "common", 1, [["affix.power_flat", 3]], 3),
			P.item("b", staff, "common", 1, [["affix.power_flat", 3.5]]),
			{"power|flat": "better"}
		],
		# 20: percent affixes are not enhanced.
		[
			P.item("a", staff, "common", 1, [["affix.power_pct", 0.05]], 4),
			P.item("b", staff, "common", 1, [["affix.power_pct", 0.06]]),
			{"power|percent": "worse", "power|flat": "better"}
		],
	]


func test_twenty_witness_pairs() -> void:
	var pairs := _pairs()
	assert_eq(pairs.size(), 20, "20 pairs")
	for i in pairs.size():
		var expected: Dictionary = pairs[i][2]
		var seen := {}
		for line in Equipment.compare(pairs[i][0], pairs[i][1], P.content()):
			var key: String = "%s|%s" % [line["stat"], line["layer"]]
			seen[key] = true
			assert_eq(line["sign"], expected.get(key, "equal"), "pair %d %s" % [i + 1, key])
			assert_near(
				line["delta"], line["candidate"] - line["current"], 1e-9, "pair %d delta" % [i + 1]
			)
		for key in expected:
			assert_true(seen.has(key), "pair %d compares %s" % [i + 1, key])


func test_compare_with_worn_uses_the_same_slot() -> void:
	var s := P.state()
	s["inventory"] = [
		P.item("w", "item.birch_staff", "common", 1), P.item("c", "item.birch_staff", "common", 5)
	]
	s["characters"][P.FERN]["equipment"]["weapon"] = "w"
	var lines := Equipment.compare_with_worn(s, P.FERN, "c", P.content())
	assert_eq(lines.size(), 1, "one stat")
	assert_eq(lines[0]["sign"], "better", "higher ilvl is better")
	assert_near(lines[0]["delta"], 6.0 * 1.6 - 6.0, 0.0001, "delta")
