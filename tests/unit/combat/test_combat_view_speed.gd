extends TestCase
## ROADMAP 3.8: speed cycles x1 -> x2 -> x4, but never beyond the encounter's
## cap (bosses are capped at x2).


func _view(cap: int) -> CombatView:
	var v := CombatView.new()
	v._handle({"type": "encounter_started", "speed_cap": cap, "units": []})
	return v


func test_normal_encounter_cycles_through_x4() -> void:
	var v := _view(4)
	var seen := [v.speed()]
	for i in 3:
		v.cycle_speed()
		seen.append(v.speed())
	assert_eq(seen, [1, 2, 4, 1], "x1 x2 x4 x1")
	v.free()


func test_boss_cap_refuses_x4() -> void:
	var v := _view(2)
	var seen := [v.speed()]
	for i in 3:
		v.cycle_speed()
		seen.append(v.speed())
	assert_eq(seen, [1, 2, 1, 2], "never x4")
	v.free()
