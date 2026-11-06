class_name CombatSim
extends RefCounted
## Deterministic fixed-tick combat simulation (GDD §7, GAME_BALANCE §0-§11).
## Pure: no node, no clock, no global random. Driven by the caller:
##
##   var sim := CombatSim.create(setup, Content.index())
##   sim.command({"type": "cast", "spell": "spell.zoltraak"})   # any time
##   var events := sim.step()        # one tick of TICK_SECONDS
##   var view := sim.snapshot()      # plain data for rendering and UI
##
## Commands are applied at the start of the next tick. Pause and speed belong
## to the caller (step fewer or more ticks per frame); nothing depends on
## frame time. Event and snapshot formats: docs/ARCHITECTURE.md, section
## "Combat : événements et instantané".
##
## setup = {
##   encounter: encounter id, seed: int, first_clear: bool (XP × FIRST_CLEAR_XP_MULT),
##   party: [{character, level, slot, flat, percent, stats, spells, spell_ranks,
##            spell_mods, ult_charge, hp_pct, mana_pct, position}],
##   tactics: partial tactics (CombatTactics), consumables: {consumable id: count},
##   keep_log: bool (default true; the bench turns it off),
## }

## Ticks stepped by every simulation of the process. Instrumentation only:
## the offline tests check it does not move (ROADMAP 5.2).
static var ticks_total := 0

var content: Dictionary = {}
var encounter: Dictionary = {}
var seed_value := 0
var rng: SeededRng
var loot_rng: SeededRng
var tick := 0
var units: Array = []
var telegraphs: Array = []
var zones: Array = []
var projectiles: Array = []
var tactics: Dictionary = {}
var finished := false
var result := ""
var error := ""
var rewards: Dictionary = {}
var kills: Array = []
var last_hit: Dictionary = {}
var roster_changed := false
var first_clear := false
## Consumables the leader carried at the start (to report what was used).
var consumables_start: Dictionary = {}
var keep_log := true
var event_log: Array = []
## What the fight did, for quests, contracts and the bestiary (filled by emit):
## {defeated: {enemy id: n} (summons included), interrupts: {def id: n}
## (casts cut by an interrupt), statuses: {status id: {source def id: n}}
## (applied on enemies)}.
var tally := {"defeated": {}, "interrupts": {}, "statuses": {}}

var _by_uid: Dictionary = {}
var _events: Array = []
var _pending: Array = []
var _commands: Array = []
var _id_counter := 0
var _enemy_counter := 0
var _tactic_spells: Dictionary = {}


## Builds a simulation, or one with `error` set and `finished` true when the
## setup does not match the content.
static func create(setup: Dictionary, content_index: Dictionary) -> CombatSim:
	var sim := CombatSim.new()
	sim.content = content_index
	sim.seed_value = int(setup.get("seed", 0))
	sim.rng = SeededRng.new(SeededRng.derive_seed(sim.seed_value, "combat"))
	sim.loot_rng = SeededRng.new(SeededRng.derive_seed(sim.seed_value, "loot"))
	sim.first_clear = bool(setup.get("first_clear", false))
	sim.keep_log = bool(setup.get("keep_log", true))
	sim._setup(setup)
	return sim


func _setup(setup: Dictionary) -> void:
	encounter = content.get(str(setup.get("encounter", "")), {})
	if encounter.get("_type", "") != "encounter":
		_fail("unknown_encounter")
		return
	for entry in setup.get("party", []):
		var u := CombatFactory.party_unit(entry, content)
		if u.is_empty() or _by_uid.has(u["uid"]):
			_fail("invalid_party")
			return
		_add(u)
	if units.is_empty():
		_fail("empty_party")
		return
	var leader: Dictionary = units[0]
	for id in setup.get("consumables", {}):
		var c: Dictionary = content.get(id, {})
		if c.get("_type", "") == "consumable":
			leader["consumables"][id] = clampi(
				int(setup["consumables"][id]),
				0,
				mini(int(c["carry_max"]), BalanceCombat.CONSUMABLE_CARRY_MAX)
			)
	consumables_start = leader["consumables"].duplicate()
	for u in units:
		for id in u["spells"] + ([u["ultimate"]] if u["ultimate"] != "" else []):
			_tactic_spells[id] = def(id)
	# Consumables take tactics too (Manual by default), carried or not.
	for id in content:
		if content[id].get("_type", "") == "consumable":
			_tactic_spells[id] = content[id]
	tactics = CombatTactics.build(_tactic_spells, setup.get("tactics", {}))
	var list := []
	for group in encounter["enemies"]:
		for i in int(group["count"]):
			list.append(
				[group["enemy"], int(encounter["level"]) + int(group.get("level_offset", 0))]
			)
	for i in list.size():
		var at := CombatFactory.pack_position(i, list.size())
		var e := CombatFactory.enemy_unit(_next_enemy_uid(), list[i][0], list[i][1], content, at)
		if e.is_empty():
			_fail("invalid_enemy")
			return
		_prepare_enemy(e)
		_add(e)
	_queue_event("encounter_started", _start_payload())


func _fail(reason: String) -> void:
	error = reason
	finished = true
	result = "error"


func _add(u: Dictionary) -> void:
	units.append(u)
	_by_uid[u["uid"]] = u


func _next_enemy_uid() -> String:
	_enemy_counter += 1
	return "e%d" % _enemy_counter


func _prepare_enemy(e: Dictionary) -> void:
	for id in CombatRules.abilities_of(e):
		CombatActions.open_cooldown(self, e, id)
	if CombatRules.has_barrier_ability(self, e):
		e["barrier_max"] = BalanceEnemies.barrier(e["barrier_ratio"], e["max_hp"])
		e["barrier"] = e["barrier_max"]


func _start_payload() -> Dictionary:
	var list := []
	for u in units:
		list.append(_unit_brief(u))
	return {
		"encounter": encounter["id"],
		"kind": encounter["kind"],
		"level": int(encounter["level"]),
		"speed_cap": int(encounter["speed_cap"]),
		"seed": seed_value,
		"units": list,
	}


func _unit_brief(u: Dictionary) -> Dictionary:
	return {
		"uid": u["uid"],
		"def_id": u["def_id"],
		"side": u["side"],
		"level": u["level"],
		"position": [snappedf(u["x"], 0.01), snappedf(u["z"], 0.01)],
		"max_hp": u["max_hp"],
		"summoner": u["summoner"],
	}


# --- Public API ---------------------------------------------------------------


## Queues a player command; it is applied at the start of the next tick.
## {type: "cast", spell, target?} | {type: "set_focus", target} |
## {type: "move_to", x, z} | {type: "stop"} | {type: "use_consumable", consumable} |
## {type: "set_tactic", key, value}. Optional "unit" (default: first party member).
func command(cmd: Dictionary) -> void:
	_commands.append(cmd.duplicate(true))


## Advances one tick and returns its events, in order.
## Test helper (E2E defeat path): sets every party member to 1 HP.
func test_defeat_party() -> void:
	for u in units:
		if u["side"] == "party" and u["alive"]:
			u["hp"] = 1.0


func step() -> Array:
	_events = _pending
	_pending = []
	if finished:
		_flush_log()
		return _events
	tick += 1
	ticks_total += 1
	_apply_commands()
	for u in units.duplicate():
		if u["alive"]:
			CombatRules.tick_statuses(self, u)
	for u in units:
		if u["alive"]:
			_tick_timers(u)
	CombatActions.tick_projectiles(self)
	CombatActions.tick_zones(self)
	if roster_changed:
		roster_changed = false
		for u in units:
			if u["side"] == "party":
				u["retarget"] = true
	for u in units.duplicate():
		if u["alive"]:
			CombatActions.progress_cast(self, u)
	for u in units.duplicate():
		if not u["alive"]:
			continue
		if u["side"] == "party":
			CombatAi.think_party(self, u)
		else:
			CombatAi.think_enemy(self, u)
	_separate()
	_check_end()
	_flush_log()
	return _events


## Steps until the end (or `max_ticks`); returns every event.
func run(max_ticks: int = -1) -> Array:
	var out := []
	var n := 0
	while not finished and (max_ticks < 0 or n < max_ticks):
		out.append_array(step())
		n += 1
	return out


func time_s() -> float:
	return float(tick) * BalanceCombat.TICK_SECONDS


## Plain data view of the fight for rendering and UI.
func snapshot() -> Dictionary:
	var list := []
	for u in units:
		list.append(_unit_snapshot(u))
	var tgs := []
	for tg in telegraphs:
		(
			tgs
			. append(
				{
					"id": tg["id"],
					"unit": tg["source"],
					"spell": tg["spell"],
					"shape": tg["shape"],
					"size_m": tg["size_m"],
					"width_m": tg["width_m"],
					"position": [tg["x"], tg["z"]],
					"direction": [tg["dx"], tg["dz"]],
					"remaining_s": tg["remaining"] * BalanceCombat.TICK_SECONDS,
					"duration_s": tg["total"] * BalanceCombat.TICK_SECONDS,
					"attached_to": tg["attached_to"],
				}
			)
		)
	var zs := []
	for z in zones:
		(
			zs
			. append(
				{
					"id": z["id"],
					"unit": z["source"],
					"spell": z["spell"],
					"element": z["element"],
					"size_m": z["radius_m"],
					"position": [z["x"], z["z"]],
					"remaining_s": z["remaining"] * BalanceCombat.TICK_SECONDS,
				}
			)
		)
	var prs := []
	for p in projectiles:
		(
			prs
			. append(
				{
					"id": p["id"],
					"unit": p["source"],
					"target": p["target"],
					"spell": p["spell"],
					"progress": 1.0 - float(p["remaining"]) / float(p["total"]),
				}
			)
		)
	return {
		"tick": tick,
		"time_s": time_s(),
		"encounter": encounter.get("id", ""),
		"speed_cap": int(encounter.get("speed_cap", 4)),
		"finished": finished,
		"result": result,
		"units": list,
		"telegraphs": tgs,
		"zones": zs,
		"projectiles": prs,
		"tactics": tactics.duplicate(true),
	}


func _unit_snapshot(u: Dictionary) -> Dictionary:
	var statuses := []
	for id in u["statuses"]:
		var st: Dictionary = u["statuses"][id]
		(
			statuses
			. append(
				{
					"id": id,
					"stacks": st["stacks"],
					"remaining_s": st["remaining"] * BalanceCombat.TICK_SECONDS,
				}
			)
		)
	var cds := {}
	for id in u["cooldowns"]:
		cds[id] = maxi(0, u["cooldowns"][id]) * BalanceCombat.TICK_SECONDS
	var cast := {}
	var c: Dictionary = u["cast"]
	if not c.is_empty():
		cast = {
			"spell": c["spell"],
			"phase": c["phase"],
			"progress": float(c["elapsed"]) / float(maxi(1, c["total"])),
			"remaining_s": (int(c["total"]) - int(c["elapsed"])) * BalanceCombat.TICK_SECONDS,
			"interruptible": c["interruptible"],
			"target": c["target"],
		}
	var snap := {
		"uid": u["uid"],
		"def_id": u["def_id"],
		"side": u["side"],
		"level": u["level"],
		"archetype": u["archetype"],
		"is_boss": u["is_boss"],
		"alive": u["alive"],
		"position": [u["x"], u["z"]],
		"facing": [u["fx"], u["fz"]],
		"moving": u["moving"],
		"ai_state": u["ai_state"],
		"hp": u["hp"],
		"max_hp": u["max_hp"],
		"mana": u["mana"],
		"max_mana": u["max_mana"],
		"shield": u["shield"],
		"barrier": u["barrier"],
		"barrier_max": u["barrier_max"],
		"damage_reduction": CombatRules.reduction_of(self, u),
		"statuses": statuses,
		"cast": cast,
		"cooldowns": cds,
		"target": u["target"],
		"focus": u["focus"],
		"summoner": u["summoner"],
	}
	if u["side"] == "enemy":
		snap["phase"] = int(u["phase"]) + 1 if not u["phases"].is_empty() else 0
		snap["phase_count"] = u["phases"].size()
	else:
		snap["slot"] = u["slot"]
		snap["row"] = u["row"]
		snap["spells"] = u["spells"].duplicate()
		snap["ultimate"] = u["ultimate"]
		snap["ult_charge"] = u["ult_charge"]
		snap["ult_charge_max"] = BalanceCombat.ULT_CHARGE_MAX
		snap["gcd_s"] = maxi(0, u["gcd"]) * BalanceCombat.TICK_SECONDS
		snap["consumables"] = u["consumables"].duplicate()
		snap["consumable_cd_s"] = maxi(0, u["consumable_cd"]) * BalanceCombat.TICK_SECONDS
		snap["hold_s"] = maxi(0, u["hold"]) * BalanceCombat.TICK_SECONDS
		snap["move_target"] = [u["move"]["x"], u["move"]["z"]] if u["manual"] else []
		snap["queued"] = u["queued"].get("spell", "")
	return snap


## Hash of an event list (determinism checks, GAME_BALANCE §22.1).
static func hash_events(events: Array) -> String:
	return JSON.stringify(events).sha256_text()


# --- Helpers for the rule modules ---------------------------------------------


func emit(type: String, fields: Dictionary) -> void:
	var e := {"type": type, "tick": tick}
	e.merge(fields)
	_events.append(e)
	_count(e)


func _count(e: Dictionary) -> void:
	match e["type"]:
		"enemy_defeated":
			_bump(tally["defeated"], str(e["def_id"]))
		"cast_interrupted":
			if e["reason"] == "interrupt" and unit(str(e["unit"])).get("side", "") == "enemy":
				_bump(tally["interrupts"], str(unit(str(e["by"])).get("def_id", "")))
		"status_applied":
			if unit(str(e["target"])).get("side", "") == "enemy":
				var by_source: Dictionary = tally["statuses"].get(e["status"], {})
				_bump(by_source, str(unit(str(e["source"])).get("def_id", "")))
				tally["statuses"][e["status"]] = by_source


static func _bump(counts: Dictionary, key: String) -> void:
	counts[key] = int(counts.get(key, 0)) + 1


func _queue_event(type: String, fields: Dictionary) -> void:
	var e := {"type": type, "tick": tick}
	e.merge(fields)
	_pending.append(e)


func _flush_log() -> void:
	if keep_log:
		event_log.append_array(_events)


func def(id: String) -> Dictionary:
	return content.get(id, {})


func unit(uid: String) -> Dictionary:
	return _by_uid.get(uid, {})


func next_id(prefix: String) -> String:
	_id_counter += 1
	return "%s%d" % [prefix, _id_counter]


func telegraph(id: String) -> Dictionary:
	for tg in telegraphs:
		if tg["id"] == id:
			return tg
	return {}


func remove_telegraph(id: String, reason: String) -> void:
	var tg := telegraph(id)
	if tg.is_empty():
		return
	telegraphs.erase(tg)
	emit("telegraph_ended", {"id": id, "reason": reason})


func hostiles(u: Dictionary) -> Array:
	var out := []
	for other in units:
		if other["alive"] and other["side"] != u["side"]:
			out.append(other)
	return out


## Alive enemies of `u` within `range_m`, nearest first (ties by creation).
func hostiles_in_range(u: Dictionary, range_m: float) -> Array:
	var pairs := []
	var i := 0
	for other in hostiles(u):
		var d := CombatGeometry.dist(u, other)
		if d <= range_m:
			pairs.append([d, i, other])
		i += 1
	pairs.sort()
	var out := []
	for p in pairs:
		out.append(p[2])
	return out


func nearest_hostile(u: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for other in hostiles(u):
		var d := CombatGeometry.dist(u, other)
		if d < best_d:
			best = other
			best_d = d
	return best


func spawn_enemy(enemy_id: String, level: int, at: Vector2, summoner: String) -> Dictionary:
	var e := CombatFactory.enemy_unit(_next_enemy_uid(), enemy_id, level, content, at)
	if e.is_empty():
		return {}
	e["summoner"] = summoner
	CombatGeometry.set_pos(e, at)
	_prepare_enemy(e)
	_add(e)
	roster_changed = true
	var brief := _unit_brief(e)
	brief["unit"] = e["uid"]
	emit("unit_spawned", brief)
	return e


func reject(u: Dictionary, command_type: String, ref: String, reason: String) -> void:
	emit(
		"command_rejected",
		{"unit": u.get("uid", ""), "command": command_type, "ref": ref, "reason": reason}
	)


# --- Tick internals -----------------------------------------------------------


func _tick_timers(u: Dictionary) -> void:
	for id in u["cooldowns"]:
		if u["cooldowns"][id] > 0:
			u["cooldowns"][id] -= 1
	if u["gcd"] > 0:
		u["gcd"] -= 1
	if u["attack_timer"] > 0:
		u["attack_timer"] -= 1
	if u["side"] == "party":
		u["mana"] = minf(
			u["max_mana"], u["mana"] + float(u["stats"]["mana_regen"]) * BalanceCombat.TICK_SECONDS
		)
		u["idle_ticks"] += 1
		if u["consumable_cd"] > 0:
			u["consumable_cd"] -= 1
		if u["hold"] > 0:
			u["hold"] -= 1
		return
	var barrier_id := CombatRules.barrier_ability(self, u)
	if barrier_id != "" and u["barrier"] < u["barrier_max"] - 0.001:
		u["barrier_timer"] += 1
		if u["barrier_timer"] >= BalanceCombat.ticks(float(def(barrier_id).get("cooldown_s", 0.0))):
			CombatRules.restore_barrier(self, u)


## Pushes overlapping enemies apart (deterministic pairwise pass).
func _separate() -> void:
	var min_d := BalanceCombat.UNIT_RADIUS_M * 2.0
	var alive := []
	for u in units:
		if u["alive"] and u["side"] == "enemy":
			alive.append(u)
	for i in alive.size():
		for j in range(i + 1, alive.size()):
			var a: Dictionary = alive[i]
			var b: Dictionary = alive[j]
			var d := CombatGeometry.pos(b) - CombatGeometry.pos(a)
			var length := d.length()
			if length >= min_d:
				continue
			var push := d.normalized() if length > 0.0001 else Vector2(1.0, 0.0)
			var shift := push * (min_d - length) * 0.5
			CombatGeometry.set_pos(a, CombatGeometry.pos(a) - shift)
			CombatGeometry.set_pos(b, CombatGeometry.pos(b) + shift)


func _check_end() -> void:
	var party_alive := false
	var enemies_alive := false
	for u in units:
		if u["alive"]:
			if u["side"] == "party":
				party_alive = true
			else:
				enemies_alive = true
	if not enemies_alive:
		_finish("victory")
	elif not party_alive or time_s() >= BalanceCombat.COMBAT_TIMEOUT_S:
		_finish("defeat")


func _finish(outcome: String) -> void:
	finished = true
	result = outcome
	rewards = CombatRewards.compute(self) if outcome == "victory" else {}
	if outcome == "victory":
		var at := [0.0, 0.0]
		for u in units:
			if u["uid"] == (kills[kills.size() - 1] if not kills.is_empty() else ""):
				at = [snappedf(u["x"], 0.01), snappedf(u["z"], 0.01)]
		emit(
			"loot_dropped",
			{
				"gold": rewards["gold"],
				"materials": rewards["materials"],
				"items": rewards["items"].duplicate(true),
				"runes": rewards["runes"].duplicate(true),
				"artifacts": rewards["artifacts"].duplicate(),
				"position": at,
			}
		)
	telegraphs.clear()
	zones.clear()
	projectiles.clear()
	emit(
		"encounter_completed",
		{
			"encounter": encounter["id"],
			"result": outcome,
			"duration_s": snappedf(time_s(), 0.01),
			"ticks": tick,
			"rewards": rewards.duplicate(true),
			"consumables_used": consumables_used(),
			"first_clear": first_clear,
			"last_hit": last_hit.duplicate(),
			"location": str(encounter.get("location", "")),
			"tally": tally.duplicate(true),
			"leader": _leader_vitals(),
		}
	)


## HP, mana (fractions) and ultimate charge of the leader at the end (dungeon
## rooms carry them to the next fight).
func _leader_vitals() -> Dictionary:
	if units.is_empty():
		return {"hp_pct": 0.0, "mana_pct": 0.0, "ult_charge": 0.0}
	var u: Dictionary = units[0]
	return {
		"hp_pct": snappedf(float(u["hp"]) / maxf(1.0, float(u["max_hp"])), 0.0001),
		"mana_pct": snappedf(float(u["mana"]) / maxf(1.0, float(u["max_mana"])), 0.0001),
		"ult_charge": snappedf(float(u.get("ult_charge", 0.0)), 0.01),
	}


## {consumable id: count} the leader used during this fight.
func consumables_used() -> Dictionary:
	var out := {}
	var left: Dictionary = units[0]["consumables"] if not units.is_empty() else {}
	for id in consumables_start:
		var used := int(consumables_start[id]) - int(left.get(id, 0))
		if used > 0:
			out[id] = used
	return out


# --- Commands -----------------------------------------------------------------


func _apply_commands() -> void:
	var list := _commands
	_commands = []
	for cmd in list:
		var u := unit(str(cmd.get("unit", "")))
		if u.is_empty():
			u = units[0]
		if not u["alive"] or u["side"] != "party":
			reject(u, str(cmd.get("type", "")), "", "dead")
			continue
		match str(cmd.get("type", "")):
			"cast":
				_cmd_cast(u, str(cmd.get("spell", "")), str(cmd.get("target", "")))
			"set_focus":
				_cmd_focus(u, str(cmd.get("target", "")))
			"move_to":
				_cmd_move(u, float(cmd.get("x", u["x"])), float(cmd.get("z", u["z"])))
			"stop":
				_cmd_stop(u)
			"use_consumable":
				_cmd_consumable(u, str(cmd.get("consumable", "")))
			"set_tactic":
				var why := CombatTactics.set_value(
					tactics, _tactic_spells, str(cmd.get("key", "")), cmd.get("value")
				)
				if why != "":
					reject(u, "set_tactic", str(cmd.get("key", "")), why)
				else:
					u["retarget"] = true
					emit(
						"tactic_changed",
						{"unit": u["uid"], "key": cmd.get("key", ""), "value": cmd.get("value")}
					)
			_:
				reject(u, str(cmd.get("type", "")), "", "unknown_command")


## Instant spells off the global cooldown (Barrier) start at once, without
## touching the buffer. Other casts start this tick or wait in the buffer
## (behind a cast, a move, the global cooldown or a cooldown ending within
## INPUT_BUFFER_S); anything else is refused at once with its reason.
func _cmd_cast(u: Dictionary, spell_id: String, target: String) -> void:
	var r := CombatActions.check_cast(self, u, spell_id, target)
	var reason: String = r["reason"]
	var buffer := BalanceCombat.ticks(BalanceCombat.INPUT_BUFFER_S)
	var spell := def(spell_id)
	if reason == "" and spell.get("ignores_gcd", false) and CombatActions.is_instant(spell):
		CombatActions.start_spell(self, u, spell_id, r["target"])
		return
	if reason == "cooldown" and int(u["cooldowns"].get(spell_id, 0)) <= buffer:
		reason = ""
	if reason in ["", "casting", "moving", "gcd", "out_of_range", "cc"]:
		u["queued"] = {"spell": spell_id, "target": target, "expires": tick + buffer}
		return
	reject(u, "cast", spell_id, reason)


func _cmd_focus(u: Dictionary, target: String) -> void:
	var t := unit(target)
	if target == "":
		u["focus"] = ""
		u["retarget"] = true
	elif t.is_empty() or not t["alive"] or t["side"] == u["side"]:
		reject(u, "set_focus", target, "no_target")
		return
	else:
		u["focus"] = target
		u["target"] = target
	emit("focus_changed", {"unit": u["uid"], "target": u["focus"]})


func _cmd_move(u: Dictionary, x: float, z: float) -> void:
	var p := CombatGeometry.clamp_arena(Vector2(x, z))
	if not u["cast"].is_empty():
		CombatActions.cancel_cast(self, u, "moved", u["uid"])
	u["manual"] = true
	u["hold"] = 0
	u["move"] = {"x": p.x, "z": p.y}
	emit("move_ordered", {"unit": u["uid"], "position": [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]})


func _cmd_stop(u: Dictionary) -> void:
	if u["manual"]:
		u["move"] = {"x": u["x"], "z": u["z"]}


## Whether `u` may drink `id` now (count, shared cooldown, not stunned).
func can_use_consumable(u: Dictionary, id: String) -> bool:
	return (
		int(u["consumables"].get(id, 0)) > 0
		and int(u["consumable_cd"]) <= 0
		and not CombatRules.is_cc(self, u)
	)


## A consumable drunk by the tactics (CombatAi), same rules as the command.
func use_consumable(u: Dictionary, id: String) -> void:
	_cmd_consumable(u, id)


func _cmd_consumable(u: Dictionary, id: String) -> void:
	var c := def(id)
	var reason := ""
	if c.get("_type", "") != "consumable":
		reason = "unknown"
	elif int(u["consumables"].get(id, 0)) <= 0:
		reason = "none_left"
	elif int(u["consumable_cd"]) > 0:
		reason = "cooldown"
	elif CombatRules.is_cc(self, u):
		reason = "cc"
	if reason != "":
		reject(u, "use_consumable", id, reason)
		return
	u["consumables"][id] -= 1
	u["consumable_cd"] = BalanceCombat.ticks(BalanceCombat.CONSUMABLE_SHARED_CD_S)
	emit("consumable_used", {"unit": u["uid"], "consumable": id, "remaining": u["consumables"][id]})
	var effect: Dictionary = c["effect"]
	match effect["type"]:
		"heal":
			CombatRules.heal(self, u, BalanceCombat.HEALING_DRAUGHT_PCT * u["max_hp"], u["uid"], id)
		"restore_mana":
			var before: float = u["mana"]
			u["mana"] = minf(u["max_mana"], before + BalanceCombat.MANA_ELIXIR_AMOUNT)
			emit(
				"mana_restored",
				{"unit": u["uid"], "source": id, "amount": snappedf(u["mana"] - before, 0.1)}
			)
