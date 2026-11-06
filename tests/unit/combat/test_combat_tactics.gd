extends TestCase
## Tactics of the simulation (GDD §7.4, decisions 22-31): the Barrier modes,
## consumable tactics.


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


## GDD decision 22: the default Barrier waits for the telegraphed Seal...
func test_default_barrier_shields_the_ash_seal() -> void:
	var tactics := _manual_tactics()
	tactics["spells"].erase("spell.defensive_barrier")
	var sim := (
		CombatSim
		. create(
			{
				"encounter": "encounter.cloister_boss",
				"seed": 2,
				"party": [CombatBench.fern(11)],
				"tactics": tactics,
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
	_until(sim, "telegraph_started", {"spell": "ability.morvaine_ash_seal"}, 400)
	var shield := _until(sim, "spell_cast", {"spell": "spell.defensive_barrier"}, 80)
	assert_true(not shield.is_empty(), "barrier before the seal")
	var hit := _until(sim, "damage_dealt", {"spell": "ability.morvaine_ash_seal"}, 40)
	assert_true(hit.get("absorbed", 0.0) > 0.0, "the shield takes the seal (%s)" % hit)


## ...and otherwise fires under 30 % HP.
func test_default_barrier_falls_back_on_the_hp_threshold() -> void:
	var tactics := _manual_tactics()
	tactics["spells"].erase("spell.defensive_barrier")
	var sim := _sim(
		_content([{"enemy": "enemy.mist_wolf", "count": 1}], 5), 5, {"tactics": tactics}
	)
	sim.step()
	var fern: Dictionary = sim.units[0]
	fern["hp"] = int(fern["max_hp"] * 0.35)
	assert_eq(
		_of(_steps(sim, 2), "spell_cast", {"spell": "spell.defensive_barrier"}).size(), 0, "35 %"
	)
	fern["hp"] = int(fern["max_hp"] * 0.29)
	var cast := _of(_steps(sim, 2), "spell_cast", {"spell": "spell.defensive_barrier"})
	assert_eq(cast.size(), 1, "under 30 %")


func test_shield_modes_include_telegraph_or_hp() -> void:
	var barrier: Dictionary = CombatBench.content()["spell.defensive_barrier"]
	assert_true(CombatTactics.MODES.has("auto_telegraph_or_hp"), "known mode")
	assert_eq(
		CombatTactics.modes_for(barrier),
		["manual", "auto_hp_below", "auto_before_telegraph", "auto_telegraph_or_hp"],
		"shield modes"
	)
	assert_eq(CombatTactics.default_mode(barrier), "auto_telegraph_or_hp", "shield default")


## Owner answer 2 (GDD, decisions 22-31) and GDD decision 32: consumable
## tactics; the healing infusion is "auto_low_hp" (under 30 % HP) by default,
## the mana elixir Manual.
func test_consumable_tactics_defaults_and_auto_low_hp() -> void:
	var content := _content([{"enemy": "enemy.mist_wolf", "count": 1}], 5)
	var stock := {"consumable.healing_draught": 2, "consumable.mana_elixir": 1}
	var sim := _sim(content, 5, {"tactics": _manual_tactics(), "consumables": stock})
	assert_eq(
		sim.tactics["consumables"],
		{"consumable.healing_draught": "auto_low_hp", "consumable.mana_elixir": "manual"},
		"infusion Auto, elixir Manual by default"
	)
	var manual := _manual_tactics()
	manual["consumables"] = {"consumable.healing_draught": "manual"}
	sim = _sim(content, 5, {"tactics": manual, "consumables": stock})
	sim.step()
	sim.units[0]["hp"] = int(sim.units[0]["max_hp"] * 0.2)
	sim.units[0]["mana"] = 5.0
	assert_eq(_of(_steps(sim, 3), "consumable_used").size(), 0, "manual: never drunk")
	var tactics := _manual_tactics()
	tactics["consumables"] = {
		"consumable.healing_draught": "auto_low_hp", "consumable.mana_elixir": "auto_low_mana"
	}
	sim = _sim(content, 5, {"tactics": tactics, "consumables": stock})
	sim.step()
	var fern: Dictionary = sim.units[0]
	fern["hp"] = int(fern["max_hp"] * 0.32)
	assert_eq(_of(_steps(sim, 3), "consumable_used").size(), 0, "32 %: not yet")
	fern["hp"] = int(fern["max_hp"] * 0.25)
	fern["mana"] = 5.0
	var used := _of(_steps(sim, 3), "consumable_used")
	assert_eq(used.size(), 1, "one potion (shared cooldown)")
	assert_eq(used[0]["consumable"], "consumable.healing_draught", "healing first")
	fern["consumable_cd"] = 0
	used = _of(_steps(sim, 3), "consumable_used")
	assert_eq(used.size(), 1, "then the elixir")
	assert_eq(used[0]["consumable"], "consumable.mana_elixir", "mana under 20 %")
	sim.command({"type": "set_tactic", "key": "consumable.mana_elixir", "value": "auto_low_hp"})
	assert_eq(_of(sim.step(), "command_rejected", {"reason": "invalid_value"}).size(), 1, "role")
