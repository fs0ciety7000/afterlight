class_name CombatBench
extends RefCounted
## Balance bench helpers (docs/GAME_BALANCE.md §22.1): gear profiles of §21.1
## and player profiles, run headless on many seeds. Used by the unit tests
## (reduced seed counts) and by tools/combat_bench.gd (full run).

const ROOTS := ["res://game/data/canon", "res://game/data/original"]

## Gear profiles (§21.1, §22.1). Every slot at ilvl = L:
## rarity implicit multiplier, enhancement level, % power affix, crit chance.
const GEAR := {
	"bare": {"rarity": 0.0, "enhance": 0, "power_pct": 0.0, "crit": 0.0},
	"unlucky": {"rarity": 1.0, "enhance": 0, "power_pct": 0.0, "crit": 0.02},
	"typical": {"rarity": 1.1, "enhance": 3, "power_pct": 0.06, "crit": 0.03},
	"good": {"rarity": 1.35, "enhance": 8, "power_pct": 0.15, "crit": 0.05},
}
## SLOT_IMPLICIT summed over the six slots (GAME_BALANCE §14.2).
const IMPLICIT := {"power": 8.0, "max_hp": 85.0, "defense": 9.0}
const ILVL_GROWTH := 0.15
const ENH_STAT_PER_LEVEL := 0.06

const POTIONS := {"consumable.healing_draught": 3, "consumable.mana_elixir": 2}
const PRESET := "tactics_preset.morvaine"
const SEALS := ["ability.morvaine_ash_seal", "ability.morvaine_ash_seal_hollow"]

static var _content: Dictionary = {}


static func content() -> Dictionary:
	if _content.is_empty():
		_content = ContentLoader.load_roots(ROOTS)["by_id"]
	return _content


## Flat and percent modifiers of a gear profile at `level`.
static func gear(profile: String, level: int) -> Dictionary:
	var g: Dictionary = GEAR[profile]
	var mult: float = (
		(1.0 + ILVL_GROWTH * (level - 1)) * g["rarity"] * (1.0 + ENH_STAT_PER_LEVEL * g["enhance"])
	)
	var flat := {}
	for stat in IMPLICIT:
		flat[stat] = IMPLICIT[stat] * mult
	flat["crit_chance"] = g["crit"]
	return {"flat": flat, "percent": {"power": g["power_pct"]}}


## "starter" (GAME_BALANCE §22.6): only the guaranteed staff, uncommon ilvl
## 1, +0, every affix at the middle of its range (affixes picked on a fixed
## seed). Flat and percent modifiers, like gear().
static func starter_gear() -> Dictionary:
	var c := content()
	var item := ItemFactory.make_item(SeededRng.new(1), c, "item.birch_staff", "uncommon", 1)
	for a in item["affixes"]:
		var r := ItemFactory.affix_range(c[a["id"]], 1)
		a["value"] = (float(r[0]) + float(r[1])) * 0.5
	var sums := ItemFactory.sum_modifiers(ItemFactory.modifiers(item, c))
	return {"flat": sums["flat"], "percent": sums["percent"]}


static func fern(level: int, profile: String = "typical") -> Dictionary:
	var g := starter_gear() if profile == "starter" else gear(profile, level)
	return {
		"character": "character.fern",
		"level": level,
		"slot": 3,
		"flat": g["flat"],
		"percent": g["percent"],
	}


## Player profiles: "idle" (default tactics, no input), "idle_tuned" (defaults
## + tactics_preset.morvaine, « Appliquer le conseil »; no input),
## "script_optimal" (interrupts, shields the big hits, focuses casters, ult
## when full, potions), "confused" (fire conversion on everything, Barrier
## left on manual). Every profile carries the same potions (3 infusions, 2
## elixirs); only automatic tactics or the script drink them.
static func setup(
	encounter: String, level: int, seed_value: int, gear_profile: String, player: String
) -> Dictionary:
	var s := {
		"encounter": encounter,
		"seed": seed_value,
		"party": [fern(level, gear_profile)],
		"keep_log": false,
		"consumables": POTIONS.duplicate(),
	}
	match player:
		"idle_tuned":
			s["tactics"] = content()[PRESET]["tactics"].duplicate(true)
		"script_optimal":
			s["tactics"] = {
				"targeting": "casters_first",
				"spells":
				{
					"spell.zoltraak": "auto",
					"spell.mana_volley": "auto",
					"spell.defensive_barrier": "auto_before_telegraph",
					"spell.afterlight": "auto_full",
				},
			}
		"confused":
			s["tactics"] = {"spells": {"spell.defensive_barrier": "manual"}}
			var mods := {}
			for id in ["spell.zoltraak", "spell.mana_volley", "spell.afterlight"]:
				mods[id] = {"element": "fire", "status_chance": 0.2}
			s["party"][0]["spell_mods"] = mods
	return s


## Runs one fight. The optimal script also drinks potions and shields under
## 40 % HP. Returns {result, duration_s, hp_pct, interrupts, no_mana_s,
## cause (last hit of a defeat: "seal", "enrage" or "other", "" on a
## victory), seals (Ash Seals that hit Fern), seals_shielded (of them, the
## ones a shield absorbed)}.
static func run_one(setup_data: Dictionary, player: String) -> Dictionary:
	var sim := CombatSim.create(setup_data, content())
	var interrupts := 0
	var low_mana_ticks := 0
	var seals := 0
	var shielded := 0
	var cause := ""
	while not sim.finished:
		if player == "script_optimal":
			_script(sim)
		for e in sim.step():
			if e["type"] == "cast_interrupted" and e["reason"] == "interrupt":
				interrupts += 1
			elif e["type"] == "damage_dealt" and SEALS.has(e["spell"]):
				seals += 1
				shielded += 1 if float(e.get("absorbed", 0.0)) > 0.0 else 0
			elif e["type"] == "encounter_completed" and e["result"] != "victory":
				cause = defeat_cause(str(e["last_hit"].get("spell", "")))
		var fern: Dictionary = sim.units[0]
		if fern["mana"] < 25.0:
			low_mana_ticks += 1
	var f: Dictionary = sim.units[0]
	return {
		"result": sim.result,
		"duration_s": sim.time_s(),
		"hp_pct": float(f["hp"]) / float(f["max_hp"]),
		"interrupts": interrupts,
		"no_mana_s": low_mana_ticks * BalanceCombat.TICK_SECONDS,
		"cause": cause,
		"seals": seals,
		"seals_shielded": shielded,
	}


## Defeat cause of GAME_BALANCE §22.6: the Seal, Cendre totale, or other.
static func defeat_cause(last_hit_spell: String) -> String:
	if SEALS.has(last_hit_spell):
		return "seal"
	return "enrage" if last_hit_spell == "ability.morvaine_enrage" else "other"


static func _script(sim: CombatSim) -> void:
	var f: Dictionary = sim.units[0]
	if not f["alive"]:
		return
	_hold_interrupt(sim, f)
	var hp_pct := float(f["hp"]) / float(f["max_hp"])
	if hp_pct < 0.4 and f["consumable_cd"] <= 0:
		if f["consumables"].get("consumable.healing_draught", 0) > 0:
			sim.command({"type": "use_consumable", "consumable": "consumable.healing_draught"})
	elif f["mana"] < 20.0 and f["consumable_cd"] <= 0:
		if f["consumables"].get("consumable.mana_elixir", 0) > 0:
			sim.command({"type": "use_consumable", "consumable": "consumable.mana_elixir"})
	# Barrier on cooldown while hurt, unless a big telegraphed hit (seal)
	# comes back before the Barrier does.
	var barrier := "spell.defensive_barrier"
	if not f["spells"].has(barrier) or not f["queued"].is_empty():
		return
	if f["cooldowns"].get(barrier, 0) > 0 or f["shield"] > 0.0 or hp_pct >= 0.85:
		return
	var barrier_cd := BalanceCombat.ticks(float(sim.def(barrier)["cooldown_s"]))
	for e in sim.hostiles(f):
		for id in CombatRules.abilities_of(e):
			if sim.def(id).get("tags", []).has("unavoidable") and id != "ability.morvaine_enrage":
				if int(e["cooldowns"].get(id, 0)) < barrier_cd:
					return
	sim.command({"type": "cast", "spell": barrier})


## Runs `seeds` fights. Returns {win_rate, p50, p90, hp_p50, interrupts,
## no_mana_pct, causes: {seal, enrage, other} (defeats), seals,
## seals_shielded} (durations over every fight, victories and defeats alike).
static func bench(
	encounter: String, level: int, gear_profile: String, player: String, seeds: int
) -> Dictionary:
	var wins := 0
	var durations := []
	var hp := []
	var interrupts := 0
	var no_mana := 0.0
	var total := 0.0
	var causes := {"seal": 0, "enrage": 0, "other": 0}
	var seals := 0
	var shielded := 0
	for i in seeds:
		var r := run_one(setup(encounter, level, 1000 + i, gear_profile, player), player)
		if r["result"] == "victory":
			wins += 1
		durations.append(r["duration_s"])
		hp.append(r["hp_pct"])
		interrupts += r["interrupts"]
		no_mana += r["no_mana_s"]
		total += r["duration_s"]
		seals += r["seals"]
		shielded += r["seals_shielded"]
		if r["cause"] != "":
			causes[r["cause"]] += 1
	durations.sort()
	hp.sort()
	return {
		"win_rate": float(wins) / float(seeds),
		"p50": durations[int(seeds * 0.5)],
		"p90": durations[mini(seeds - 1, int(seeds * 0.9))],
		"hp_p50": hp[int(seeds * 0.5)],
		"interrupts": float(interrupts) / float(seeds),
		"no_mana_pct": no_mana / maxf(total, 0.001),
		"causes": causes,
		"seals": seals,
		"seals_shielded": shielded,
	}


## Keeps Zoltraak for an interrupt when an interruptible ability is due
## before Zoltraak would come back (cooldown or HP trigger close).
static func _hold_interrupt(sim: CombatSim, f: Dictionary) -> void:
	var zoltraak := "spell.zoltraak"
	if not f["spells"].has(zoltraak):
		return
	var window := BalanceCombat.ticks(float(sim.def(zoltraak)["cooldown_s"]))
	var hold := false
	for e in sim.hostiles(f):
		for id in CombatRules.abilities_of(e):
			var ab := sim.def(id)
			if not ab.get("interruptible", false):
				continue
			var trigger: Dictionary = ab.get("trigger", {})
			if trigger.has("hp_below"):
				var fired := int(e["triggers"].get(id, 0))
				var list: Array = trigger["hp_below"]
				if fired < list.size():
					var gap := float(e["hp"]) / float(e["max_hp"]) - float(list[fired])
					hold = hold or gap < 0.15
			elif int(e["cooldowns"].get(id, 0)) <= window:
				hold = true
	var mode := "auto_interrupt" if hold else "auto"
	if sim.tactics["spells"].get(zoltraak, "") != mode:
		sim.command({"type": "set_tactic", "key": zoltraak, "value": mode})
