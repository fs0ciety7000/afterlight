extends TestCase


func _sequence(seed_value: int, count: int) -> Array:
	var rng := SeededRng.new(seed_value)
	var out := []
	for i in count:
		out.append(rng.range_int(0, 1_000_000))
	return out


func test_same_seed_gives_same_sequence() -> void:
	assert_eq(_sequence(42, 50), _sequence(42, 50), "seed 42")


func test_different_seeds_differ() -> void:
	assert_true(_sequence(1, 20) != _sequence(2, 20), "seeds 1 and 2")


func test_state_can_be_saved_and_resumed() -> void:
	var rng := SeededRng.new(7)
	for i in 10:
		rng.next_float()
	var saved := rng.get_state()
	var expected := [rng.next_float(), rng.next_float(), rng.next_float()]
	var resumed := SeededRng.new(0)
	resumed.set_state(saved)
	assert_eq(
		[resumed.next_float(), resumed.next_float(), resumed.next_float()], expected, "resume"
	)


func test_derived_streams_are_stable_and_distinct() -> void:
	assert_eq(SeededRng.derive_seed(99, "loot", 3), SeededRng.derive_seed(99, "loot", 3), "stable")
	assert_true(
		SeededRng.derive_seed(99, "loot", 3) != SeededRng.derive_seed(99, "combat", 3), "distinct"
	)


func test_pick_weighted_ignores_insertion_order_and_zero_weights() -> void:
	var a := SeededRng.new(5)
	var b := SeededRng.new(5)
	var picks_a := []
	var picks_b := []
	for i in 30:
		picks_a.append(a.pick_weighted({"common": 70, "rare": 25, "epic": 5, "never": 0}))
		picks_b.append(b.pick_weighted({"never": 0, "epic": 5, "rare": 25, "common": 70}))
	assert_eq(picks_a, picks_b, "order independent")
	assert_true(not picks_a.has("never"), "zero weight never picked")
	assert_eq(SeededRng.new(1).pick_weighted({"a": 0}), null, "all zero")


func test_pick_weighted_follows_weights() -> void:
	var rng := SeededRng.new(123)
	var counts := {"a": 0, "b": 0}
	for i in 4000:
		counts[rng.pick_weighted({"a": 3, "b": 1})] += 1
	assert_near(float(counts["a"]) / 4000.0, 0.75, 0.03, "share of a")
