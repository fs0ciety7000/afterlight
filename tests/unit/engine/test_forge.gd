extends TestCase
## Criterion 4.5 (GAME_BALANCE §15): enhancement costs equal the table,
## success is guaranteed up to +5, pity adds up then resets, and the same item
## at the same attempt count gives the same result after a reload.

const P := preload("res://tests/unit/engine/progression_fixtures.gd")
const RICH := 1_000_000


func _state_with(item: Dictionary, gold: int = RICH, dust: int = RICH) -> Dictionary:
	var s := P.state(gold, {"material.mana_dust": dust})
	s["inventory"] = [item]
	return s


func test_costs_equal_the_balance_table() -> void:
	# §15 example, ilvl 10: +1 141 / 4, +6 632 / 24, +8 1 152 / 32, +10 2 100 / 40.
	var expected := {0: [141, 4], 5: [632, 24], 7: [1152, 32], 9: [2100, 40]}
	for n in expected:
		var item := P.item("x", "item.birch_staff", "legendary", 10, [], n)
		var q := Forge.quote(_state_with(item), "x")
		assert_true(q["ok"], "quote +%d" % (n + 1))
		assert_eq([q["gold"], q["dust"]], expected[n], "cost +%d" % (n + 1))
	var gold := 0
	var dust := 0
	for n in 10:
		gold += BalanceItems.enhance_gold(10, n)
		dust += BalanceItems.enhance_dust(n)
	assert_true(absi(gold - 7700) < 50, "total ≈ 7 700 (%d)" % gold)
	assert_eq(dust, 220, "total dust")


func test_success_is_guaranteed_up_to_plus_five() -> void:
	for k in 30:
		var s := _state_with(P.item("u%d" % k, "item.birch_staff", "legendary", 10))
		s["meta"]["seed"] = 1000 + k
		for n in 5:
			var r := Forge.enhance(s, "u%d" % k)
			assert_true(r["ok"] and r["success"], "seed %d +%d" % [k, n + 1])
			s = r["state"]
		assert_eq(s["inventory"][0]["enhance"], 5, "+5 reached")


## A uid whose first attempt at +5 → +6 fails (roll >= 0.9).
func _failing_uid(seed_value: int, attempt: int, threshold: float) -> String:
	for k in 1000:
		var uid := "f%d" % k
		if Forge.roll(seed_value, uid, attempt) >= threshold:
			return uid
	return ""


func test_pity_adds_up_then_resets_and_a_failure_refunds_half_the_gold() -> void:
	var seed_value: int = P.state()["meta"]["seed"]
	var uid := _failing_uid(seed_value, 5, 0.9)
	assert_true(uid != "", "found a failing roll")
	var item := P.item(uid, "item.birch_staff", "legendary", 10, [], 5)
	item["enhance_attempts"] = 5
	var s := _state_with(item, 10_000, 100)
	var r := Forge.enhance(s, uid)
	assert_true(r["ok"] and not r["success"], "fails at 0.9")
	var after: Dictionary = r["state"]["inventory"][0]
	assert_eq([after["enhance"], after["pity"], after["enhance_attempts"]], [5, 1, 6], "pity +1")
	assert_eq(r["refund"], 316, "half of 632 back")
	assert_eq(r["state"]["wallet"]["gold"], 10_000 - 632 + 316, "gold")
	assert_eq(r["state"]["wallet"]["materials"]["material.mana_dust"], 100 - 24, "dust lost")
	var q := Forge.quote(r["state"], uid)
	assert_near(q["chance"], 1.0, 1e-9, "0.9 + 0.1 pity")
	var ok := Forge.enhance(r["state"], uid)
	assert_true(ok["success"], "pity makes it")
	assert_eq(ok["state"]["inventory"][0]["pity"], 0, "pity reset")
	assert_eq(ok["state"]["inventory"][0]["enhance"], 6, "+6")
	# Pity keeps adding up at +10 (0.5, 0.6, 0.7...).
	assert_near(BalanceItems.enhance_chance(9, 0), 0.5, 1e-9, "base +10")
	assert_near(BalanceItems.enhance_chance(9, 3), 0.8, 1e-9, "after 3 fails")


func test_reloading_cannot_reroll_an_attempt() -> void:
	var s := _state_with(P.item("x", "item.birch_staff", "epic", 8, [], 7))
	s["inventory"][0]["enhance_attempts"] = 9
	var first := Forge.enhance(s, "x")
	var decoded := SaveCodec.decode(SaveCodec.encode(s, 1), SaveMigrations.all())
	assert_true(decoded["ok"], "reload")
	var again := Forge.enhance(decoded["state"], "x")
	assert_eq(again["success"], first["success"], "same outcome after reload")
	assert_eq(
		SaveCodec.canonical(again["state"]), SaveCodec.canonical(first["state"]), "same state"
	)
	for k in 20:
		var a := Forge.roll(77, "i%d" % k, k)
		assert_eq(Forge.roll(77, "i%d" % k, k), a, "pure roll")


func test_refusals_give_a_reason_and_the_amount() -> void:
	var item := P.item("x", "item.birch_staff", "rare", 10)
	var poor := Forge.enhance(_state_with(item, 100), "x")
	assert_eq(poor["error"], "error.not_enough_gold", "gold")
	assert_eq(poor["params"]["required"], 141, "141 required")
	var dustless := Forge.quote(_state_with(item, RICH, 3), "x")
	assert_eq(dustless["error"], "error.not_enough_material", "dust")
	assert_eq(
		dustless["params"],
		{"material": "material.mana_dust.name", "required": 4, "owned": 3},
		"dust params"
	)
	var capped := P.item("y", "item.birch_staff", "common", 3, [], 4)
	assert_eq(Forge.quote(_state_with(capped), "y")["error"], "error.enhance_max", "common max +4")
	assert_eq(Forge.quote(_state_with(item), "zz")["error"], "error.item_not_found", "unknown")
