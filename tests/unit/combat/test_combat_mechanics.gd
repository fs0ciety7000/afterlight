extends TestCase
## Combat simulation rules: commands, buffer, cooldowns, interrupts, statuses,
## reactions, shields, telegraphs, dodge, AI archetypes, boss, rewards.

const FERN := "p3"


func _content(enemies: Array, level: int, kind: String = "normal") -> Dictionary:
	var c := CombatBench.content().duplicate()
	c["encounter.test"] = {
		"_type": "encounter",
		"id": "encounter.test",
		"kind": kind,
		"level": level,
		"enemies": enemies,
		"loot_table": "loot.field_normal",
		"speed_cap": 4,
		"offline_eligible": false,
	}
	return c


func _sim(content: Dictionary, level: int, extra: Dictionary = {}) -> CombatSim:
	var setup := {"encounter": "encounter.test", "seed": 3, "party": [CombatBench.fern(level)]}
	setup.merge(extra, true)
	return CombatSim.create(setup, content)


## Steps until an event of `type` (matching `filter` fields) appears.
func _until(
	sim: CombatSim, type: String, filter: Dictionary = {}, max_ticks: int = 4000
) -> Dictionary:
	for i in max_ticks:
		for e in sim.step():
			if e["type"] != type:
				continue
			var ok := true
			for k in filter:
				ok = ok and e.get(k) == filter[k]
			if ok:
				return e
		if sim.finished:
			break
	return {}


func _steps(sim: CombatSim, n: int) -> Array:
	var out := []
	for i in n:
		out.append_array(sim.step())
	return out


func _of(events: Array, type: String, filter: Dictionary = {}) -> Array:
	var out := []
	for e in events:
		if e["type"] == type:
			var ok := true
			for k in filter:
				ok = ok and e.get(k) == filter[k]
			if ok:
				out.append(e)
	return out


func _manual_tactics() -> Dictionary:
	return {
		"spells":
		{
			"spell.zoltraak": "manual",
			"spell.mana_volley": "manual",
			"spell.defensive_barrier": "manual",
		}
	}


func _hit(source: String, element: String, coeff: float = 1.0) -> Dictionary:
	return {
		"source": source,
		"source_side": "party",
		"spell": "test",
		"kind": "active",
		"power": 100.0,
		"level": 1,
		"coeff": coeff,
		"rank": 1,
		"bonus": 0.0,
		"element": element,
		"crit_chance": 0.0,
		"crit_damage": 1.5,
		"crit_bonus": 0.0,
		"can_crit": false,
		"variance": false,
		"reactions": true,
		"interrupt": false,
		"statuses": [],
	}


# --- Setup, events, snapshot --------------------------------------------------


func test_setup_errors_are_reported() -> void:
	var sim := CombatSim.create({"encounter": "encounter.missing"}, CombatBench.content())
	assert_eq(sim.error, "unknown_encounter", "unknown encounter")
	assert_true(sim.finished, "finished at once")
	sim = CombatSim.create(
		{"encounter": "encounter.whispering_wood_01", "party": [{"character": "x"}]},
		CombatBench.content()
	)
	assert_eq(sim.error, "invalid_party", "invalid party")


func test_first_step_starts_the_encounter_and_snapshot_is_plain_data() -> void:
	var sim := _sim(_content([{"enemy": "enemy.mist_wolf", "count": 2}], 1), 1)
	var first := sim.step()
	assert_eq(first[0]["type"], "encounter_started", "first event")
	assert_eq(first[0]["units"].size(), 3, "units listed")
	assert_eq(first[0]["speed_cap"], 4, "speed cap")
	var snap := sim.snapshot()
	var round_trip: Variant = JSON.parse_string(JSON.stringify(snap))
	assert_true(round_trip is Dictionary, "JSON round trip")
	var fern: Dictionary = snap["units"][0]
	for key in ["uid", "position", "facing", "hp", "max_hp", "mana", "statuses", "cooldowns"]:
		assert_true(fern.has(key), "snapshot field " + key)
	assert_true(fern.has("ult_charge") and fern.has("gcd_s"), "party fields")
	assert_eq(fern["uid"], FERN, "Fern sits in slot 3")
	assert_eq(first[0]["units"][0]["position"], [-1.0, 10.0], "back row, 4 m further")


func test_normal_fight_is_won_with_rewards() -> void:
	var sim := (
		CombatSim
		. create(
			{
				"encounter": "encounter.whispering_wood_02",
				"seed": 5,
				"party": [CombatBench.fern(1)],
				"first_clear": true,
			},
			CombatBench.content()
		)
	)
	var events := sim.run(4000)
	assert_eq(sim.result, "victory", "victory")
	var done: Dictionary = events[events.size() - 1]
	assert_eq(done["type"], "encounter_completed", "last event")
	assert_eq(events[events.size() - 2]["type"], "loot_dropped", "loot before completion")
	assert_eq(done["rewards"]["xp"], 72, "3 wolves L1 × 8 XP × first clear")
	assert_true(done["rewards"]["gold"] >= 9 and done["rewards"]["gold"] <= 15, "gold 3 × 4 ± 20 %")
	assert_eq(_of(events, "enemy_defeated").size(), 3, "three kills")
	assert_eq(done["tally"]["defeated"], {"enemy.mist_wolf": 3}, "tally of kills")
	assert_eq(done["location"], "location.whispering_wood", "location of the encounter")
	assert_true(done["leader"]["hp_pct"] > 0.0 and done["leader"]["hp_pct"] <= 1.0, "leader HP")


func test_defeat_has_no_rewards_and_names_the_last_hit() -> void:
	var sim := (
		CombatSim
		. create(
			{
				"encounter": "encounter.cloister_boss",
				"seed": 1,
				"party": [CombatBench.fern(1, "bare")],
				"keep_log": false,
			},
			CombatBench.content()
		)
	)
	var events := sim.run(20000)
	assert_eq(sim.result, "defeat", "defeat")
	var done: Dictionary = events[events.size() - 1]
	assert_eq(done["rewards"], {}, "no rewards")
	assert_eq(done["last_hit"]["target"], FERN, "last hit on Fern")
	assert_eq(_of(events, "character_defeated").size(), 1, "Fern defeated")


# --- Player commands, cooldowns, GCD, buffer ----------------------------------


func test_cast_starts_within_one_tick_then_cools_down() -> void:
	var sim := _sim(
		_content([{"enemy": "enemy.stone_sentinel", "count": 1}], 5),
		5,
		{"tactics": _manual_tactics()}
	)
	sim.step()
	sim.command({"type": "cast", "spell": "spell.zoltraak"})
	var events := sim.step()
	assert_eq(
		_of(events, "spell_cast", {"spell": "spell.zoltraak"}).size(), 1, "spell_cast at once"
	)
	assert_eq(_of(events, "cast_started").size(), 1, "cast bar")
	var done := _until(sim, "cast_completed", {"unit": FERN}, 20)
	assert_eq(done.get("tick", -1), events[0]["tick"] + 6, "0.3 s cast = 6 ticks")
	assert_eq(sim.units[0]["cooldowns"]["spell.zoltraak"], 120, "6 s cooldown")
	sim.command({"type": "cast", "spell": "spell.zoltraak"})
	var refused := _of(sim.step(), "command_rejected")
	assert_eq(refused.size(), 1, "refused")
	assert_eq(refused[0]["reason"], "cooldown", "reason")


func test_buffered_spell_waits_for_the_cast_and_gcd() -> void:
	var sim := _sim(
		_content([{"enemy": "enemy.mist_wolf", "count": 3}], 5), 5, {"tactics": _manual_tactics()}
	)
	_steps(sim, 30)
	sim.command({"type": "cast", "spell": "spell.zoltraak"})
	var t0 := sim.tick + 1
	sim.step()
	sim.command({"type": "cast", "spell": "spell.mana_volley"})
	sim.command({"type": "cast", "spell": "spell.defensive_barrier"})
	var events := _steps(sim, 20)
	var barrier := _of(events, "spell_cast", {"spell": "spell.defensive_barrier"})
	assert_eq(barrier.size(), 1, "barrier cast")
	assert_eq(barrier[0]["tick"], t0 + 1, "barrier ignores the cast and the GCD")
	var volley := _of(events, "spell_cast", {"spell": "spell.mana_volley"})
	assert_eq(volley.size(), 1, "volley cast from the buffer")
	assert_eq(volley[0]["tick"], t0 + 10, "after the 0.5 s GCD")
	assert_eq(_of(events, "command_rejected").size(), 0, "nothing refused")


func test_buffer_expires_and_refusals_have_reasons() -> void:
	var sim := _sim(
		_content([{"enemy": "enemy.mist_wolf", "count": 1}], 5), 5, {"tactics": _manual_tactics()}
	)
	_steps(sim, 30)
	var fern: Dictionary = sim.units[0]
	fern["cooldowns"]["spell.zoltraak"] = 5
	sim.command({"type": "cast", "spell": "spell.zoltraak"})
	var events := _steps(sim, 8)
	assert_eq(_of(events, "spell_cast", {"spell": "spell.zoltraak"}).size(), 1, "within buffer")
	fern["cooldowns"]["spell.mana_volley"] = 40
	sim.command({"type": "cast", "spell": "spell.mana_volley"})
	assert_eq(_of(sim.step(), "command_rejected", {"reason": "cooldown"}).size(), 1, "too far")
	fern["mana"] = 0.0
	sim.command({"type": "cast", "spell": "spell.defensive_barrier"})
	assert_eq(_of(sim.step(), "command_rejected", {"reason": "no_mana"}).size(), 1, "no mana")
	sim.command({"type": "cast", "spell": "spell.afterlight"})
	assert_eq(_of(sim.step(), "command_rejected", {"reason": "no_charge"}).size(), 1, "no charge")
	sim.command({"type": "cast", "spell": "spell.unknown"})
	assert_eq(_of(sim.step(), "command_rejected", {"reason": "locked"}).size(), 1, "locked")


func test_spells_unlock_by_level() -> void:
	var sim := _sim(_content([{"enemy": "enemy.mist_wolf", "count": 1}], 1), 1)
	assert_eq(sim.units[0]["spells"], ["spell.zoltraak"], "level 1 kit")
	assert_eq(sim.units[0]["ultimate"], "", "no ultimate before level 5")
	sim = _sim(_content([{"enemy": "enemy.mist_wolf", "count": 1}], 5), 5)
	assert_eq(sim.units[0]["spells"].size(), 3, "level 5 kit")
	assert_eq(sim.units[0]["ultimate"], "spell.afterlight", "ultimate")


func test_ultimate_channels_twelve_rays() -> void:
	var sim := _sim(
		_content([{"enemy": "enemy.stone_sentinel", "count": 2}], 5),
		5,
		{"tactics": _manual_tactics()}
	)
	_steps(sim, 20)
	sim.units[0]["ult_charge"] = 100.0
	sim.command({"type": "cast", "spell": "spell.afterlight"})
	var events := _steps(sim, 45)
	assert_eq(_of(events, "spell_cast", {"spell": "spell.afterlight"}).size(), 1, "cast")
	assert_eq(_of(events, "damage_dealt", {"spell": "spell.afterlight"}).size(), 12, "12 rays")
	assert_true(sim.units[0]["ult_charge"] < 100.0, "charge spent")


func test_volley_spreads_over_targets_starting_with_focus() -> void:
	var sim := _sim(
		_content([{"enemy": "enemy.stone_sentinel", "count": 3}], 5),
		5,
		{"tactics": _manual_tactics()}
	)
	_steps(sim, 40)
	sim.command({"type": "set_focus", "target": "e3"})
	sim.command({"type": "cast", "spell": "spell.mana_volley"})
	var events := _steps(sim, 30)
	var hits := _of(events, "damage_dealt", {"spell": "spell.mana_volley"})
	assert_eq(hits.size(), 5, "5 projectiles")
	var per := {}
	for h in hits:
		per[h["target"]] = per.get(h["target"], 0) + 1
	assert_eq(per.get("e3", 0), 2, "focus first, round robin")
	assert_eq(per.size(), 3, "all three hit")


func test_focus_drives_auto_attacks() -> void:
	var sim := _sim(_content([{"enemy": "enemy.stone_sentinel", "count": 2}], 5), 5)
	sim.step()
	sim.command({"type": "set_focus", "target": "e2"})
	var events := _steps(sim, 80)
	assert_eq(_of(events, "focus_changed").size(), 1, "focus event")
	for a in _of(events, "attack_started", {"unit": FERN}):
		assert_eq(a["target"], "e2", "auto-attacks on the focus")
	sim.command({"type": "set_focus", "target": "e9"})
	assert_eq(_of(sim.step(), "command_rejected", {"reason": "no_target"}).size(), 1, "bad focus")


func test_consumables_heal_restore_and_share_a_cooldown() -> void:
	var sim := _sim(
		_content([{"enemy": "enemy.mist_wolf", "count": 1}], 5),
		5,
		{"consumables": {"consumable.healing_draught": 1, "consumable.mana_elixir": 2}}
	)
	sim.step()
	var fern: Dictionary = sim.units[0]
	fern["hp"] = 100
	sim.command({"type": "use_consumable", "consumable": "consumable.healing_draught"})
	var healed := _of(sim.step(), "character_healed")
	assert_eq(healed.size(), 1, "healed")
	assert_eq(healed[0]["amount"], roundi(0.35 * fern["max_hp"]), "35 % of max HP")
	sim.command({"type": "use_consumable", "consumable": "consumable.mana_elixir"})
	assert_eq(_of(sim.step(), "command_rejected", {"reason": "cooldown"}).size(), 1, "shared cd")
	fern["consumable_cd"] = 0
	fern["mana"] = 10.0
	sim.command({"type": "use_consumable", "consumable": "consumable.mana_elixir"})
	var restored := _of(sim.step(), "mana_restored")
	assert_eq(restored.size(), 1, "mana restored")
	assert_near(restored[0]["amount"], 50.0, 0.01, "50 mana")
	fern["consumable_cd"] = 0
	sim.command({"type": "use_consumable", "consumable": "consumable.healing_draught"})
	assert_eq(_of(sim.step(), "command_rejected", {"reason": "none_left"}).size(), 1, "none left")


func test_set_tactic_validates_values() -> void:
	var sim := _sim(_content([{"enemy": "enemy.mist_wolf", "count": 1}], 5), 5)
	assert_eq(sim.tactics["spells"]["spell.zoltraak"], "auto", "default Zoltraak")
	assert_eq(sim.tactics["spells"]["spell.mana_volley"], "auto_min_enemies", "default volley")
	assert_eq(
		sim.tactics["spells"]["spell.defensive_barrier"], "auto_telegraph_or_hp", "default barrier"
	)
	assert_near(sim.tactics["barrier_hp_pct"], 0.3, 0.0001, "default threshold (GDD decision 22)")
	assert_eq(sim.tactics["spells"]["spell.afterlight"], "manual", "default ultimate")
	sim.command({"type": "set_tactic", "key": "targeting", "value": "lowest_hp"})
	sim.command({"type": "set_tactic", "key": "mana_reserve", "value": 0.9})
	sim.command({"type": "set_tactic", "key": "spell.afterlight", "value": "auto_interrupt"})
	var events := sim.step()
	assert_eq(sim.tactics["targeting"], "lowest_hp", "targeting set")
	assert_eq(_of(events, "command_rejected", {"reason": "invalid_value"}).size(), 2, "refused")


# --- Repositioning ------------------------------------------------------------


func test_reposition_moves_without_attacking_then_holds() -> void:
	var content := _content([{"enemy": "enemy.stone_sentinel", "count": 1}], 5)
	var sim := _sim(content, 5, {"tactics": _manual_tactics()})
	sim.step()
	var sentinel: Dictionary = sim.units[1]
	sentinel["cooldowns"]["ability.sentinel_slam"] = 100000
	sim.command({"type": "move_to", "x": 6.0, "z": 6.0})
	sim.command({"type": "cast", "spell": "spell.zoltraak"})
	var moving := []
	var arrived := {}
	for i in 200:
		var events := sim.step()
		moving.append_array(events)
		var hold := _of(events, "hold_started")
		if not hold.is_empty():
			arrived = hold[0]
			break
	assert_true(not arrived.is_empty(), "arrived")
	assert_eq(_of(moving, "attack_started", {"unit": FERN}).size(), 0, "no attack while moving")
	assert_eq(_of(moving, "spell_cast", {"unit": FERN}).size(), 0, "no spell while moving")
	var after := _steps(sim, 60)
	assert_eq(_of(after, "spell_cast", {"spell": "spell.zoltraak"}).size(), 1, "queued spell fires")
	assert_near(sim.units[0]["x"], 6.0, 0.01, "holds x")
	assert_near(sim.units[0]["z"], 6.0, 0.01, "holds z")
	assert_true(_of(after, "attack_started", {"unit": FERN}).size() > 0, "attacks from the spot")


func test_hold_ends_when_no_target_is_in_range() -> void:
	var sim := _sim(_content([{"enemy": "enemy.wandering_lantern", "count": 1}], 5), 5)
	sim.step()
	sim.command({"type": "move_to", "x": 0.0, "z": 15.5})
	_until(sim, "hold_started", {}, 200)
	var start := Vector2(sim.units[0]["x"], sim.units[0]["z"])
	_steps(sim, 20)
	var now := Vector2(sim.units[0]["x"], sim.units[0]["z"])
	assert_true(now.distance_to(start) > 0.5, "AI resumes its own placement")


# --- Interrupts, telegraphs, dodge --------------------------------------------


func test_zoltraak_interrupts_lantern_blaze() -> void:
	var sim := _sim(
		_content([{"enemy": "enemy.wandering_lantern", "count": 1}], 5),
		5,
		{"tactics": _manual_tactics()}
	)
	sim.step()
	sim.units[1]["cooldowns"]["ability.lantern_blaze"] = 0
	var started := _until(sim, "cast_started", {"spell": "ability.lantern_blaze"}, 200)
	assert_true(started.get("interruptible", false), "channel is interruptible")
	sim.command({"type": "cast", "spell": "spell.zoltraak", "target": "e1"})
	var events := _steps(sim, 12)
	var cut := _of(events, "cast_interrupted", {"spell": "ability.lantern_blaze"})
	assert_eq(cut.size(), 1, "cast_interrupted")
	assert_eq(cut[0]["reason"], "interrupt", "by an interrupt")
	assert_eq(cut[0]["by"], FERN, "by Fern")
	assert_eq(_of(events, "status_applied", {"status": "status.stun"}).size(), 1, "stunned")
	assert_eq(_of(_steps(sim, 60), "zone_spawned").size(), 0, "no fire zone")
	assert_eq(sim.tally["interrupts"], {"character.fern": 1}, "interrupt tallied for Fern")
	assert_eq(sim.tally["statuses"]["status.stun"], {"character.fern": 1}, "stun tallied")


func test_default_tactics_interrupt_and_blaze_zone_is_left() -> void:
	var sim := _sim(_content([{"enemy": "enemy.wandering_lantern", "count": 1}], 5), 5)
	sim.step()
	sim.units[1]["cooldowns"]["ability.lantern_blaze"] = 0
	var cut := _until(sim, "cast_interrupted", {"spell": "ability.lantern_blaze"}, 200)
	assert_eq(cut.get("reason", ""), "interrupt", "auto interrupt")
	# Same fight without Zoltraak: the zone lands and Fern walks out of it.
	sim = _sim(
		_content([{"enemy": "enemy.wandering_lantern", "count": 1}], 5),
		5,
		{"tactics": _manual_tactics()}
	)
	sim.step()
	sim.units[1]["cooldowns"]["ability.lantern_blaze"] = 0
	var zone := _until(sim, "zone_spawned", {}, 300)
	assert_true(not zone.is_empty(), "zone spawned")
	var events := _steps(sim, 30)
	var center := Vector2(zone["position"][0], zone["position"][1])
	var fern := Vector2(sim.units[0]["x"], sim.units[0]["z"])
	assert_true(fern.distance_to(center) > zone["size_m"], "left the zone")
	var burns := _of(events, "damage_dealt", {"spell": "ability.lantern_blaze"}).size()
	assert_true(burns <= 2, "out after the 0.4 s reaction (%d ticks of 8)" % burns)


func test_telegraphs_last_at_least_the_minimum() -> void:
	var sim := CombatSim.create(
		{"encounter": "encounter.cloister_boss", "seed": 2, "party": [CombatBench.fern(11)]},
		CombatBench.content()
	)
	sim.step()
	var boss: Dictionary = sim.units[1]
	boss["hp"] = int(boss["max_hp"] * 0.29)
	CombatRules.check_phase(sim, boss)
	assert_eq(boss["phase"], 2, "phase 3 (index 2)")
	var events := sim.run(4000)
	var tgs := _of(events, "telegraph_started")
	assert_true(tgs.size() > 0, "telegraphs seen")
	for t in tgs:
		assert_true(t["duration_s"] >= BalanceCombat.TELEGRAPH_MIN_S, "minimum %s" % t)


func test_fern_dodges_the_slam_when_reachable() -> void:
	var sim := _sim(
		_content([{"enemy": "enemy.stone_sentinel", "count": 1}], 5),
		5,
		{"tactics": _manual_tactics()}
	)
	sim.step()
	sim.units[1]["cooldowns"]["ability.sentinel_slam"] = 0
	sim.units[0]["x"] = 0.0
	sim.units[0]["z"] = 2.0
	var tg := _until(sim, "telegraph_started", {"spell": "ability.sentinel_slam"}, 200)
	assert_eq(tg.get("shape", ""), "circle", "circle telegraph")
	assert_near(tg["duration_s"], 1.2, 0.001, "1.2 s")
	var events := _steps(sim, 30)
	assert_eq(_of(events, "telegraph_ended", {"reason": "impact"}).size(), 1, "slam landed")
	assert_eq(_of(events, "damage_dealt", {"spell": "ability.sentinel_slam"}).size(), 0, "dodged")


func test_wolf_lunge_is_telegraphed_then_dashes() -> void:
	var sim := _sim(_content([{"enemy": "enemy.mist_wolf", "count": 1}], 1), 1)
	sim.step()
	sim.units[1]["cooldowns"]["ability.wolf_lunge"] = 0
	var tg := _until(sim, "telegraph_started", {"spell": "ability.wolf_lunge"}, 200)
	assert_eq(tg.get("shape", ""), "line", "line")
	assert_near(tg["duration_s"], 0.6, 0.001, "0.6 s")
	var before := Vector2(sim.units[1]["x"], sim.units[1]["z"])
	_until(sim, "telegraph_ended", {"id": tg["id"]}, 20)
	var after := Vector2(sim.units[1]["x"], sim.units[1]["z"])
	assert_true(after.distance_to(before) > 1.0, "dashed")


# --- Enemy archetypes ---------------------------------------------------------


func test_lantern_keeps_its_distance() -> void:
	var sim := _sim(_content([{"enemy": "enemy.wandering_lantern", "count": 1}], 5), 5)
	sim.step()
	sim.units[1]["cooldowns"]["ability.lantern_blaze"] = 100000
	sim.command({"type": "move_to", "x": 0.0, "z": 1.5})
	var kited := false
	for i in 120:
		sim.step()
		kited = kited or sim.units[1]["ai_state"] == "kite"
	assert_true(kited, "kites when approached")
	assert_true(CombatGeometry.dist(sim.units[0], sim.units[1]) > 4.0, "got away")


func test_sentinel_barrier_takes_double_arcane_and_comes_back() -> void:
	var sim := _sim(_content([{"enemy": "enemy.stone_sentinel", "count": 1}], 5), 5)
	sim.step()
	var s: Dictionary = sim.units[1]
	assert_near(s["barrier"], 0.25 * s["max_hp"], 0.01, "starts with its barrier")
	var before: float = s["barrier"]
	var hit := _hit(FERN, "arcane")
	CombatRules.apply_hit(sim, hit, s)
	var arcane_loss: float = before - s["barrier"]
	before = s["barrier"]
	CombatRules.apply_hit(sim, _hit(FERN, "fire"), s)
	var fire_loss: float = before - s["barrier"]
	assert_near(arcane_loss / fire_loss, 2.0, 0.01, "arcane ×2 on the barrier")
	s["barrier"] = 0.0
	for i in 159:
		sim._tick_timers(s)
	assert_eq(s["barrier"], 0.0, "not before 8 s")
	sim._tick_timers(s)
	assert_near(s["barrier"], s["barrier_max"], 0.01, "full again after 8 s")
	s["barrier"] = 10.0
	s["barrier_timer"] = 150
	CombatRules.apply_hit(sim, hit, s)
	assert_eq(s["barrier_timer"], 0, "arcane damage resets the timer")


func test_alpha_howl_summons_and_frenzies_when_not_interrupted() -> void:
	var sim := (
		CombatSim
		. create(
			{
				"encounter": "encounter.cloister_alpha",
				"seed": 4,
				"party": [CombatBench.fern(10)],
				"tactics": _manual_tactics(),
			},
			CombatBench.content()
		)
	)
	sim.step()
	var alpha: Dictionary = sim.units[1]
	alpha["hp"] = int(alpha["max_hp"] * 0.69)
	var started := _until(sim, "cast_started", {"spell": "ability.alpha_howl"}, 100)
	assert_eq(started.get("duration_s", 0.0), 1.5, "1.5 s channel")
	var events := _steps(sim, 40)
	var spawned := _of(events, "unit_spawned")
	assert_eq(spawned.size(), 2, "two wolves")
	assert_eq(spawned[0]["level"], 10, "level Le - 1")
	assert_true(alpha["statuses"].has("status.haste_buff"), "alpha frenzied")
	assert_true(sim.unit(spawned[0]["uid"])["statuses"].has("status.haste_buff"), "pack frenzied")
	assert_eq(alpha["triggers"]["ability.alpha_howl"], 1, "first threshold used")
	sim.run(20000)
	if sim.result == "victory":
		assert_eq(
			sim.tally["defeated"],
			{"enemy.mist_wolf_alpha": 1, "enemy.mist_wolf": 2},
			"summons count for the bestiary"
		)


# --- Statuses and reactions ---------------------------------------------------


func test_status_stacking_rules() -> void:
	var sim := _sim(_content([{"enemy": "enemy.stone_sentinel", "count": 1}], 5), 5)
	sim.step()
	var s: Dictionary = sim.units[1]
	var src := {"source": FERN, "power": 100.0, "level": 5}
	for i in 4:
		CombatRules.apply_status(sim, s, "status.burn", src)
	assert_eq(s["statuses"]["status.burn"]["stacks"], 3, "burn caps at 3")
	CombatRules.apply_status(sim, s, "status.chill", src)
	CombatRules.apply_status(sim, s, "status.chill", src)
	assert_eq(s["statuses"]["status.chill"]["stacks"], 2, "chill 2")
	CombatRules.apply_status(sim, s, "status.chill", src)
	assert_true(not s["statuses"].has("status.chill"), "chill converted")
	assert_true(s["statuses"].has("status.frozen"), "frozen at 3 stacks")
	CombatRules.remove_status(sim, s, "status.frozen", "expired")
	assert_true(s["immunities"].has("status.frozen"), "freeze immunity")
	assert_eq(s["immunities"]["status.frozen"], 80, "4 s")
	CombatRules.apply_status(sim, s, "status.stun", src)
	var remaining: int = s["statuses"]["status.stun"]["remaining"]
	s["statuses"]["status.stun"]["remaining"] = 5
	CombatRules.apply_status(sim, s, "status.stun", src)
	assert_eq(s["statuses"]["status.stun"]["remaining"], 5, "stun does not stack or refresh")
	assert_eq(remaining, 20, "1 s stun")


func test_bosses_take_half_control_and_never_freeze() -> void:
	var sim := CombatSim.create(
		{"encounter": "encounter.cloister_boss", "seed": 2, "party": [CombatBench.fern(11)]},
		CombatBench.content()
	)
	sim.step()
	var boss: Dictionary = sim.units[1]
	var src := {"source": FERN, "power": 100.0, "level": 11}
	for i in 3:
		CombatRules.apply_status(sim, boss, "status.chill", src)
	assert_eq(boss["statuses"]["status.chill"]["stacks"], 2, "2 chill stacks max")
	assert_true(not boss["statuses"].has("status.frozen"), "never frozen")
	CombatRules.apply_status(sim, boss, "status.stun", src)
	assert_eq(boss["statuses"]["status.stun"]["remaining"], 10, "stun × 0.5")


func test_burn_ticks_every_half_second() -> void:
	var sim := _sim(_content([{"enemy": "enemy.stone_sentinel", "count": 1}], 5), 5)
	sim.step()
	var s: Dictionary = sim.units[1]
	s["barrier"] = 0.0
	CombatRules.apply_status(sim, s, "status.burn", {"source": "e9", "power": 100.0, "level": 5})
	var dots := []
	for i in 80:
		CombatRules.tick_statuses(sim, s)
		dots.append_array(_of(sim._events, "damage_dealt", {"spell": "status.burn"}))
		sim._events = []
	assert_eq(dots.size(), 8, "4 s at one tick per 0.5 s")
	var expected := 0.15 * 100.0 * 0.5 * BalanceCombat.mitigation(5, s["stats"]["defense"])
	assert_eq(dots[0]["amount"], roundi(expected), "0.15 × power per s, mitigated")
	assert_true(not s["statuses"].has("status.burn"), "expired")


func test_reactions() -> void:
	var sim := _sim(_content([{"enemy": "enemy.mist_wolf", "count": 3}], 5), 5)
	sim.step()
	var a: Dictionary = sim.units[1]
	var b: Dictionary = sim.units[2]
	for u in [a, b]:
		u["max_hp"] = 100000
		u["hp"] = 100000
	var base := _damage(sim, _hit(FERN, "arcane"), a)
	CombatRules.apply_status(sim, a, "status.frozen", {"source": FERN})
	var melt := _damage(sim, _hit(FERN, "fire"), a)
	assert_eq(melt["reaction"], "melt", "melt")
	assert_near(float(melt["amount"]) / float(base["amount"]), 1.5 * 1.5, 0.02, "×1.5 on weak fire")
	assert_true(not a["statuses"].has("status.frozen"), "melt removes frozen")
	CombatRules.apply_status(sim, a, "status.burn", {"source": FERN, "power": 10.0})
	CombatRules.apply_status(sim, a, "status.burn", {"source": FERN, "power": 10.0})
	b["x"] = a["x"] + 1.0
	b["z"] = a["z"]
	var hp_b: int = b["hp"]
	var over := _damage(sim, _hit(FERN, "lightning"), a)
	assert_eq(over["reaction"], "overload", "overload")
	assert_eq(a["statuses"]["status.burn"]["stacks"], 1, "one burn stack used")
	assert_true(b["hp"] < hp_b, "explosion hits neighbours")
	var ext := _damage(sim, _hit(FERN, "frost"), a)
	assert_eq(ext["reaction"], "extinguish", "extinguish")
	assert_true(not a["statuses"].has("status.burn"), "burn removed")
	CombatRules.apply_status(sim, a, "status.shock", {"source": FERN})
	var shocked := _damage(sim, _hit(FERN, "arcane"), a)
	assert_true(shocked["shock"], "shock consumed")
	assert_near(float(shocked["amount"]) / float(base["amount"]), 1.15, 0.02, "+15 %")
	assert_true(not a["statuses"].has("status.shock"), "consumed")


func _damage(sim: CombatSim, hit: Dictionary, target: Dictionary) -> Dictionary:
	sim._events = []
	CombatRules.apply_hit(sim, hit, target)
	var hits := _of(sim._events, "damage_dealt", {"target": target["uid"], "spell": hit["spell"]})
	return hits[0] if not hits.is_empty() else {}


func test_shields_keep_the_biggest_and_absorb_first() -> void:
	var sim := _sim(_content([{"enemy": "enemy.mist_wolf", "count": 1}], 5), 5)
	sim.step()
	var fern: Dictionary = sim.units[0]
	CombatRules.apply_shield(sim, fern, 300.0, 4.0, FERN)
	fern["statuses"]["status.shield"]["remaining"] = 10
	CombatRules.apply_shield(sim, fern, 200.0, 4.0, FERN)
	assert_eq(fern["shield"], 300.0, "smaller shield keeps the bigger one")
	assert_eq(fern["statuses"]["status.shield"]["remaining"], 80, "but refreshes the duration")
	CombatRules.apply_shield(sim, fern, 400.0, 4.0, FERN)
	assert_eq(fern["shield"], 400.0, "bigger replaces")
	var hp: int = fern["hp"]
	sim._events = []
	var r := CombatRules.deal_damage(sim, fern, 500.0, "fire", "e1")
	assert_eq(r["absorbed"], 400, "absorbed")
	assert_eq(r["hp_damage"], 100, "rest on HP")
	assert_eq(_of(sim._events, "status_expired", {"reason": "depleted"}).size(), 1, "depleted")
	assert_eq(fern["hp"], hp, "deal_damage does not touch HP itself")


func test_barrier_spell_cleanses_one_harmful_status() -> void:
	var sim := _sim(
		_content([{"enemy": "enemy.mist_wolf", "count": 1}], 5), 5, {"tactics": _manual_tactics()}
	)
	sim.step()
	var fern: Dictionary = sim.units[0]
	CombatRules.apply_status(sim, fern, "status.weaken", {"source": "e1"})
	CombatRules.apply_status(sim, fern, "status.burn", {"source": "e1", "power": 1.0})
	sim.command({"type": "cast", "spell": "spell.defensive_barrier"})
	var events := sim.step()
	assert_eq(_of(events, "shield_applied", {"target": FERN}).size(), 1, "shield")
	assert_eq(_of(events, "status_expired", {"reason": "cleansed"}).size(), 1, "one cleansed")
	assert_true(not fern["statuses"].has("status.burn"), "damage over time first")
	assert_true(fern["statuses"].has("status.weaken"), "weaken stays")


func test_weaken_lowers_power() -> void:
	var sim := _sim(_content([{"enemy": "enemy.mist_wolf", "count": 1}], 5), 5)
	var fern: Dictionary = sim.units[0]
	var power := CombatRules.power_of(sim, fern)
	CombatRules.apply_status(sim, fern, "status.weaken", {"source": "e1"})
	assert_near(CombatRules.power_of(sim, fern), power * 0.7, 0.001, "-30 %")


# --- Boss ---------------------------------------------------------------------


func test_boss_phases_barrier_haste_and_lantern_link() -> void:
	var sim := CombatSim.create(
		{"encounter": "encounter.cloister_boss", "seed": 2, "party": [CombatBench.fern(11)]},
		CombatBench.content()
	)
	sim.step()
	var boss: Dictionary = sim.units[1]
	sim._events = []
	boss["hp"] = int(boss["max_hp"] * 0.66)
	CombatRules.lose_hp(sim, boss, int(boss["max_hp"] * 0.02), FERN, "test")
	var phase := _of(sim._events, "boss_phase_changed")
	assert_eq(phase.size(), 1, "phase 2")
	assert_eq(phase[0]["phase"], 2, "phase number")
	assert_true(phase[0]["hp_pct"] <= 0.65, "at 65 %")
	assert_near(boss["barrier"], 0.15 * boss["max_hp"], 1.0, "veil 15 % of max HP")
	sim._events = []
	CombatRules.lose_hp(sim, boss, int(boss["hp"] - boss["max_hp"] * 0.29), FERN, "test")
	assert_eq(_of(sim._events, "boss_phase_changed")[0]["phase"], 3, "phase 3")
	assert_near(CombatRules.haste_of(boss), 0.30, 0.0001, "+30 % haste")
	assert_eq(boss["barrier"], 0.0, "no more veil")
	var at := Vector2(0, 0)
	for i in 5:
		var lantern := sim.spawn_enemy("enemy.wandering_lantern", 10, at, boss["uid"])
		lantern["link_reduction"] = 0.15
	assert_near(CombatRules.reduction_of(sim, boss), 0.45, 0.0001, "capped at 0.45")


func test_bound_lanterns_summon_two_at_level_minus_two() -> void:
	var sim := CombatSim.create(
		{"encounter": "encounter.cloister_boss", "seed": 2, "party": [CombatBench.fern(11)]},
		CombatBench.content()
	)
	var spawned := _until(sim, "unit_spawned", {}, 2000)
	assert_eq(spawned.get("def_id", ""), "enemy.wandering_lantern", "lantern")
	assert_eq(spawned["level"], 10, "Le - 2")
	assert_near(sim.time_s(), 15.0, 0.06, "first summon at half its cooldown")
	assert_near(CombatRules.reduction_of(sim, sim.units[1]), 0.30, 0.0001, "2 × 0.15")


func test_ash_seal_follows_its_target_and_is_unavoidable() -> void:
	var sim := (
		CombatSim
		. create(
			{
				"encounter": "encounter.cloister_boss",
				"seed": 2,
				"party": [CombatBench.fern(11)],
				"tactics": _manual_tactics(),
			},
			CombatBench.content()
		)
	)
	sim.step()
	var boss: Dictionary = sim.units[1]
	boss["hp"] = int(boss["max_hp"] * 0.6)
	CombatRules.check_phase(sim, boss)
	boss["cooldowns"]["ability.morvaine_ash_seal"] = 0
	boss["cooldowns"]["ability.morvaine_false_word"] = 100000
	var tg := _until(sim, "telegraph_started", {"spell": "ability.morvaine_ash_seal"}, 400)
	assert_eq(tg.get("attached_to", ""), FERN, "attached to Fern")
	assert_near(tg["duration_s"], 3.0, 0.001, "3 s cast")
	var hit := _until(sim, "damage_dealt", {"spell": "ability.morvaine_ash_seal"}, 80)
	assert_eq(hit.get("target", ""), FERN, "hits Fern wherever she is")


func test_enrage_at_300_seconds() -> void:
	var fern := CombatBench.fern(11)
	fern.erase("flat")
	fern.erase("percent")
	fern["stats"] = {"max_hp": 1.0e7, "power": 1.0, "max_mana": 100, "defense": 50}
	var sim := CombatSim.create(
		{"encounter": "encounter.cloister_boss", "seed": 2, "party": [fern], "keep_log": false},
		CombatBench.content()
	)
	var cast := _until(sim, "spell_cast", {"spell": "ability.morvaine_enrage"}, 7000)
	assert_true(not cast.is_empty(), "enrage cast")
	assert_near(cast.get("tick", 0) * BalanceCombat.TICK_SECONDS, 300.0, 0.06, "at 300 s")
	var hit := _until(sim, "damage_dealt", {"spell": "ability.morvaine_enrage"}, 40)
	assert_true(hit.get("amount", 0) > 0, "enrage hit")


# --- Data mirrors the balance constants ---------------------------------------


func test_content_mirrors_balance_constants() -> void:
	var c := CombatBench.content()
	var veiled: Array = c["passive.veiled_mana"]["effects"]
	assert_eq(veiled[0]["after_idle_s"], BalanceCombat.VEILED_MANA_DELAY_S, "veiled delay")
	assert_eq(veiled[0]["bonus"], BalanceCombat.VEILED_MANA_BONUS, "veiled bonus")
	var barrier: Array = c["spell.defensive_barrier"]["effects"]
	assert_eq(barrier[0]["duration_s"], BalanceCombat.SHIELD_DURATION_S, "shield duration")
	assert_eq(c["status.shield"]["duration_s"], BalanceCombat.SHIELD_DURATION_S, "shield status")
	assert_eq(c["status.stun"]["duration_s"], BalanceCombat.INTERRUPT_STUN_S, "stun")
	assert_eq(c["status.stun"]["boss_duration_mult"], BalanceStatuses.BOSS_CC_DURATION_MULT, "boss")
	assert_eq(c["status.frozen"]["immunity_after_s"], BalanceStatuses.FREEZE_IMMUNITY_S, "freeze")
	assert_eq(
		c["consumable.healing_draught"]["effect"]["coeff"],
		BalanceCombat.HEALING_DRAUGHT_PCT,
		"heal"
	)
	assert_eq(
		c["consumable.mana_elixir"]["effect"]["coeff"], BalanceCombat.MANA_ELIXIR_AMOUNT, "elixir"
	)
	var phases: Array = c["enemy.morvaine"]["phases"]
	assert_eq(phases[1]["hp_threshold"], BalanceEnemies.MORVAINE_PHASE_2_HP, "phase 2")
	assert_eq(phases[2]["hp_threshold"], BalanceEnemies.MORVAINE_PHASE_3_HP, "phase 3")
	assert_eq(
		c["ability.morvaine_enrage"]["trigger"]["on_time_s"],
		c["enemy.morvaine"]["enrage_s"],
		"enrage"
	)


func test_encounters_follow_the_ehp_budget() -> void:
	var c := CombatBench.content()
	for id in c:
		var e: Dictionary = c[id]
		if e.get("_type", "") != "encounter" or e["kind"] != "normal":
			continue
		if id == "encounter.whispering_wood_01":
			continue  # first fight, under budget on purpose
		var level := int(e["level"])
		var ehp := 0.0
		for g in e["enemies"]:
			var d: Dictionary = c[g["enemy"]]
			var le := level + int(g.get("level_offset", 0))
			var hp := BalanceEnemies.hp(d["stats_l1"]["hp"], le)
			var m := BalanceCombat.mitigation(
				level, BalanceEnemies.defense(d["stats_l1"]["def_ratio"], le)
			)
			var barrier := BalanceEnemies.barrier(d["stats_l1"]["barrier_ratio"], hp)
			ehp += int(g["count"]) * BalanceEnemies.effective_hp(hp, barrier, m, 1.0, 2.0)
		var budget := BalanceEnemies.encounter_ehp_budget(level)
		var gap := absf(ehp / budget - 1.0)
		assert_true(
			gap <= BalanceEnemies.ENCOUNTER_EHP_TOLERANCE, "%s EHP %.0f / %.0f" % [id, ehp, budget]
		)


func test_whispering_wood_encounters_use_scene_anchors() -> void:
	var c := CombatBench.content()
	var scene := FileAccess.get_file_as_string("res://game/world/locations/whispering_wood.tscn")
	for id in c:
		var e: Dictionary = c[id]
		if e.get("_type", "") == "encounter" and e["location"] == "location.whispering_wood":
			var marker := '[node name="%s" type="Marker3D" parent="Anchors"' % e["anchor"]
			assert_true(scene.contains(marker), "%s anchor %s" % [id, e["anchor"]])
