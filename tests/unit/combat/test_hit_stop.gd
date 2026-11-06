extends TestCase
## ROADMAP 7.4 / GDD §14: a hit-stop freezes the combat clock without
## consuming a tick (the event log is the one of a run without hit-stops,
## determinism 3.1 stays green), and it is off at ×4.

const TICK := BalanceCombat.TICK_SECONDS
const FRAME := 1.0 / 60.0


func test_hit_stop_steps_no_tick_and_banks_no_time() -> void:
	var c := CombatClock.new()
	assert_eq(c.advance(0.1, 1, false), 2, "two ticks in 100 ms")
	var banked := c.acc
	assert_true(c.request_hit_stop(0.06, 1), "accepted at x1")
	assert_eq(c.advance(0.05, 1, false), 0, "frozen")
	assert_eq(c.advance(0.05, 1, false), 0, "still frozen (10 ms left)")
	assert_near(c.acc, banked, 0.000001, "no time banked during the freeze")
	assert_true(not c.frozen(), "over")
	assert_eq(c.advance(0.05, 1, false), 1, "ticks again")


func test_overlapping_hit_stops_keep_the_longest() -> void:
	var c := CombatClock.new()
	c.request_hit_stop(0.06, 2)
	c.request_hit_stop(0.03, 2)
	assert_near(c.hit_stop_left, 0.06, 0.000001, "longest kept")


func test_hit_stop_is_off_at_x4() -> void:
	var c := CombatClock.new()
	assert_true(not c.request_hit_stop(0.06, 4), "refused at x4")
	assert_true(not c.frozen(), "not frozen")
	assert_eq(c.advance(0.05, 4, false), 4, "x4 keeps stepping")
	assert_true(c.request_hit_stop(0.06, 2), "accepted at x2")


func test_combat_view_ignores_hit_stops_at_x4() -> void:
	var v := CombatView.new()
	v._handle({"type": "encounter_started", "speed_cap": 4, "units": []})
	var before := CombatView.hit_stops_applied
	v.speed_index = CombatView.SPEEDS.find(4)
	v._on_hit_stop(0.06)
	assert_eq(CombatView.hit_stops_applied, before, "x4: not applied")
	v.speed_index = 0
	v._on_hit_stop(0.06)
	assert_eq(CombatView.hit_stops_applied, before + 1, "x1: applied")
	v.free()


## A fight driven frame by frame through the clock, with a hit-stop on every
## hit (longer on crits and boss hits, as CombatFx asks), gives the event log
## of the plain run for the same command stream.
func test_hit_stops_leave_the_event_log_unchanged() -> void:
	for c in [["encounter.whispering_wood_02", 1, 3], ["encounter.cloister_boss", 11, 5]]:
		var plain := _run(c[0], c[1], c[2], false)
		var stopped := _run(c[0], c[1], c[2], true)
		assert_eq(stopped["hash"], plain["hash"], "%s: same log" % c[0])
		assert_true(int(stopped["stops"]) > 0, "%s: hit-stops happened" % c[0])
		assert_true(float(stopped["time"]) > float(plain["time"]), "%s: frozen time" % c[0])


func _run(encounter: String, level: int, seed_value: int, hit_stops: bool) -> Dictionary:
	var sim := CombatSim.create(
		{"encounter": encounter, "seed": seed_value, "party": [CombatBench.fern(level)]},
		CombatBench.content()
	)
	var clock := CombatClock.new()
	var stops := 0
	var time := 0.0
	while not sim.finished and sim.tick < 8000:
		time += FRAME
		for i in clock.advance(FRAME, 1, false):
			if sim.finished:
				break
			match sim.tick:
				20:
					sim.command({"type": "cast", "spell": "spell.zoltraak"})
				60:
					sim.command({"type": "move_to", "x": 3.0, "z": 7.0})
			for e in sim.step():
				if not hit_stops or e["type"] != "damage_dealt":
					continue
				var boss: bool = sim.unit(str(e.get("source", ""))).get("is_boss", false)
				var seconds := 0.06 if boss else (0.045 if e.get("crit", false) else 0.03)
				if clock.request_hit_stop(seconds, 1):
					stops += 1
	return {"hash": CombatSim.hash_events(sim.event_log), "stops": stops, "time": time}
