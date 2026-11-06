class_name OfflineCalc
extends RefCounted
## Offline progression (docs/GAME_BALANCE.md §20, GDD §12): hunt eligibility,
## the analytical summary of an absence and its claim. Pure and batch: the
## clock (`now_unix`) is a parameter, no combat tick runs, every draw comes
## from the "offline" stream seeded by (game seed, last_active_at, now).
##
## A summary is a plain Dictionary saved in state.offline.pending until it is
## claimed (StateSchema.offline_summary_spec()):
## {status ("ok" | "clock" | "unsafe" | "ineligible"), reason (error key or
##  ""), encounter, from, to, elapsed_s, counted_s, capped, efficiency,
##  clear_time_s, cycle_s, survival_s, required_s, clears, xp, gold,
##  materials {id: n} (drops, salvage not included), items [item without uid]
##  (kept), items_dropped, items_salvaged, salvage_dust, runes [{id, tier}]
##  (kept), runes_dropped, runes_salvaged, rune_shards, level_before,
##  level_after, levels_gained, xp_wasted}.
## Only "ok" credits anything; lines(summary) gives the text lines.

const STATUS_OK := "ok"
const STATUS_CLOCK := "clock"
const STATUS_UNSAFE := "unsafe"
const STATUS_INELIGIBLE := "ineligible"


## Can `encounter_id` be the offline hunt? Kind, flag and first victory only
## (no stats involved). Returns an ActionResult without state.
static func hunt_check(state: Dictionary, encounter_id: String, content: Dictionary) -> Dictionary:
	var e: Dictionary = content.get(encounter_id, {})
	if e.get("_type", "") != "encounter":
		return ActionResult.refuse("error.offline.unknown_encounter")
	if str(e.get("kind", "")) != "normal":
		return ActionResult.refuse("error.offline.not_normal", {"encounter": e["name_key"]})
	if not e.get("offline_eligible", false):
		return ActionResult.refuse("error.offline.not_eligible", {"encounter": e["name_key"]})
	if int(state["progress"]["cleared_encounters"].get(encounter_id, 0)) <= 0:
		return ActionResult.refuse("error.offline.not_cleared", {"encounter": e["name_key"]})
	return ActionResult.success({})


## Quote for the "chasse hors ligne" button: eligibility plus the estimate.
## Refuses when the fight would last over CLEAR_TIME_MAX_S. A hunt the party
## would not survive is allowed but carries `warning` (the summary will then
## credit nothing). Extra on success: {encounter, clear_time_s, cycle_s,
## efficiency, clears_per_hour, xp_per_hour, gold_per_hour, survives,
## survival_s, required_s, warning, warning_params}.
static func quote(state: Dictionary, encounter_id: String, content: Dictionary) -> Dictionary:
	var check := hunt_check(state, encounter_id, content)
	if not check["ok"]:
		return check
	var est := estimate(state, encounter_id, content)
	if est["error"] != "":
		return ActionResult.refuse("error.offline.unknown_encounter")
	if float(est["clear_time_s"]) > BalanceOffline.CLEAR_TIME_MAX_S:
		return ActionResult.refuse("error.offline.too_slow", _too_slow_params(est))
	var eff := efficiency(state, content)
	var per_hour := BalanceOffline.clears(3600, eff, est["cycle_s"])
	var expect := expectation(state, encounter_id, content)
	var out := {
		"encounter": encounter_id,
		"clear_time_s": est["clear_time_s"],
		"cycle_s": est["cycle_s"],
		"efficiency": eff,
		"clears_per_hour": per_hour,
		"xp_per_hour": floori(per_hour * float(expect["xp"])),
		"gold_per_hour": floori(per_hour * float(expect["gold"])),
		"survives": est["survives"],
		"survival_s": est["survival_s"],
		"required_s": est["required_s"],
		"warning": "",
		"warning_params": {},
	}
	if not est["survives"]:
		out["warning"] = "error.offline.unsafe"
		out["warning_params"] = _unsafe_params(est)
	return ActionResult.success({}, out)


## Sets the offline hunt (state.farming) after the quote accepted it.
static func set_hunt(state: Dictionary, encounter_id: String, content: Dictionary) -> Dictionary:
	var q := quote(state, encounter_id, content)
	if not q["ok"]:
		return q
	var next := state.duplicate(true)
	next["farming"] = encounter_id
	q["state"] = next
	return q


## OFFLINE_EFFICIENCY plus the worn Cracked Hourglass (§18).
static func efficiency(state: Dictionary, content: Dictionary) -> float:
	var leader: String = state["party"][0]
	return BalanceOffline.efficiency(ArtifactRules.offline_efficiency_bonus(state, leader, content))


## OfflineModel.estimate for the saved party leader (stats frozen now), or
## for `entry` when given (a CombatSim party entry, used by the tests).
static func estimate(
	state: Dictionary, encounter_id: String, content: Dictionary, entry: Dictionary = {}
) -> Dictionary:
	if entry.is_empty():
		entry = PartyBuild.entry(state, state["party"][0], content)
	return OfflineModel.estimate(entry, encounter_id, content)


## Expected rewards of one repeat clear (never a first clear) for the leader:
## {xp, gold, materials {id: qty}, items: [{ref, count}], runes: [{ref, count}],
##  profile, ilvl}. XP has the level penalty, gold the leader's gold_find.
static func expectation(state: Dictionary, encounter_id: String, content: Dictionary) -> Dictionary:
	var leader: String = state["party"][0]
	var level := int(state["characters"][leader]["level"])
	var gold_find := float(Equipment.stats(state, leader, content)["gold_find"])
	return expectation_for(content.get(encounter_id, {}), level, gold_find, content)


static func expectation_for(
	encounter: Dictionary, level: int, gold_find: float, content: Dictionary
) -> Dictionary:
	var enemies := OfflineModel.pack(encounter, content)
	var table: Dictionary = content.get(encounter.get("loot_table", ""), {})
	var xp := 0.0
	for e in enemies:
		xp += (
			BalanceEnemies.enemy_xp(e["level"], float(e["def"].get("xp_mult", 1.0)))
			* BalanceEnemies.xp_penalty(level, e["level"])
		)
	var gold := 0.0
	var materials := {}
	var items := []
	var runes := []
	for entry in table.get("entries", []):
		if not CombatRewards.applies(entry, false) or enemies.is_empty():
			continue
		var rolls := enemies.size() if entry["per"] == "enemy" else 1
		var chance := float(entry["chance"])
		var qty := (float(entry["qty"][0]) + float(entry["qty"][1])) * 0.5
		match str(entry["kind"]):
			"gold":
				var picked: Array = enemies if entry["per"] == "enemy" else [enemies[0]]
				for e in picked:
					gold += (
						chance
						* BalanceEnemies.enemy_gold(
							e["level"], float(e["def"].get("gold_mult", 1.0)), 1.0, gold_find
						)
					)
			"material":
				var ref: String = entry["ref"]
				materials[ref] = float(materials.get(ref, 0.0)) + chance * qty * rolls
			"item":
				items.append({"ref": str(entry.get("ref", "")), "count": chance * qty * rolls})
			"rune":
				runes.append({"ref": str(entry.get("ref", "")), "count": chance * qty * rolls})
	return {
		"xp": xp,
		"gold": gold,
		"materials": materials,
		"items": items,
		"runes": runes,
		"profile": CombatRewards.loot_profile(table, false),
		"ilvl":
		BalanceItems.item_level(int(encounter.get("level", 1)), str(encounter.get("kind", ""))),
	}


## Settles an absence. Returns {summary ({} when there is nothing to show),
## last_active_at (the stamp to keep: max(stored, now), so a clock moved back
## never rewinds it)}.
## `entry` overrides the party build (tests); by default the saved leader.
static func compute(
	state: Dictionary, now_unix: int, content: Dictionary, entry: Dictionary = {}
) -> Dictionary:
	var from := int(state["meta"]["last_active_at"])
	var elapsed := now_unix - from
	var out := {"summary": {}, "last_active_at": maxi(from, now_unix)}
	var hunt := str(state.get("farming", ""))
	if hunt == "" or (elapsed >= 0 and elapsed < BalanceOffline.OFFLINE_MIN_S):
		return out
	var summary := _empty_summary(state, hunt, from, now_unix, content)
	out["summary"] = summary
	if elapsed < 0:
		summary["status"] = STATUS_CLOCK
		return out
	var check := hunt_check(state, hunt, content)
	if not check["ok"]:
		return _refuse(out, STATUS_INELIGIBLE, check["error"])
	var est := estimate(state, hunt, content, entry)
	if est["error"] != "":
		return _refuse(out, STATUS_INELIGIBLE, "error.offline.unknown_encounter")
	summary["clear_time_s"] = est["clear_time_s"]
	summary["cycle_s"] = est["cycle_s"]
	summary["survival_s"] = minf(est["survival_s"], 1.0e9)
	summary["required_s"] = est["required_s"]
	if float(est["clear_time_s"]) > BalanceOffline.CLEAR_TIME_MAX_S:
		return _refuse(out, STATUS_INELIGIBLE, "error.offline.too_slow")
	if not est["survives"]:
		return _refuse(out, STATUS_UNSAFE, "error.offline.unsafe")
	var leader: String = state["party"][0]
	var hero: Dictionary = state["characters"][leader]
	var expect := expectation_for(content[hunt], int(hero["level"]), est["gold_find"], content)
	var n := BalanceOffline.clears(summary["counted_s"], summary["efficiency"], est["cycle_s"])
	summary["clears"] = n
	summary["xp"] = floori(n * float(expect["xp"]))
	summary["gold"] = floori(n * float(expect["gold"]))
	var rng := SeededRng.new(
		offline_seed(int(state["meta"]["seed"]), from, from + int(summary["counted_s"]))
	)
	var ids: Array = expect["materials"].keys()
	ids.sort()
	for id in ids:
		var qty := _draw_count(rng, n * float(expect["materials"][id]))
		if qty > 0:
			summary["materials"][id] = qty
	_draw_items(summary, state, expect, n, rng, content)
	_draw_runes(summary, expect, n, rng, content)
	var leveled := BalanceProgression.grant_xp(hero["level"], hero["xp"], summary["xp"])
	summary["level_after"] = leveled["level"]
	summary["levels_gained"] = leveled["levels_gained"]
	summary["xp_wasted"] = leveled["wasted"]
	return out


## Seed of the "offline" stream (§20.3): game seed, last_active_at and the end
## of the counted window, min(now, last_active_at + OFFLINE_CAP_S), so 8 h and
## 8 h + 1 s draw the same gains.
static func offline_seed(game_seed: int, from_unix: int, until_unix: int) -> int:
	return SeededRng.derive_seed(game_seed, "offline:%d" % from_unix, until_unix)


static func _empty_summary(
	state: Dictionary, hunt: String, from: int, now: int, content: Dictionary
) -> Dictionary:
	var level := int(state["characters"][state["party"][0]]["level"])
	var elapsed := now - from
	return {
		"status": STATUS_OK,
		"reason": "",
		"encounter": hunt,
		"from": from,
		"to": now,
		"elapsed_s": elapsed,
		"counted_s": BalanceOffline.counted_seconds(elapsed),
		"capped": elapsed > BalanceOffline.OFFLINE_CAP_S,
		"efficiency": efficiency(state, content),
		"clear_time_s": 0.0,
		"cycle_s": 0.0,
		"survival_s": 0.0,
		"required_s": 0.0,
		"clears": 0.0,
		"xp": 0,
		"gold": 0,
		"materials": {},
		"items": [],
		"items_dropped": 0,
		"items_salvaged": 0,
		"salvage_dust": 0,
		"runes": [],
		"runes_dropped": 0,
		"runes_salvaged": 0,
		"rune_shards": 0,
		"level_before": level,
		"level_after": level,
		"levels_gained": 0,
		"xp_wasted": 0,
	}


static func _refuse(out: Dictionary, status: String, reason: String) -> Dictionary:
	out["summary"]["status"] = status
	out["summary"]["reason"] = reason
	return out


static func _too_slow_params(est: Dictionary) -> Dictionary:
	return {
		"seconds": ceili(float(est["clear_time_s"])),
		"max": int(BalanceOffline.CLEAR_TIME_MAX_S),
	}


static func _unsafe_params(est: Dictionary) -> Dictionary:
	return {
		"survival": floori(minf(float(est["survival_s"]), 1.0e9)),
		"required": ceili(float(est["required_s"])),
	}


## floori(x) + (rng < fractional part ? 1 : 0) (§20.3).
static func _draw_count(rng: SeededRng, expected: float) -> int:
	var whole := floori(expected)
	return whole + (1 if rng.next_float() < expected - float(whole) else 0)


## Item drops: count by the §20.3 rule, each one rolled individually up to
## OFFLINE_ITEM_SAMPLE_MAX (beyond, salvaged at the expected dust). The best
## (rarity, then item level) are kept up to OFFLINE_ITEM_KEEP_MAX and the free
## bag slots; the rest is salvaged into mana dust.
static func _draw_items(
	summary: Dictionary,
	state: Dictionary,
	expect: Dictionary,
	n: float,
	rng: SeededRng,
	content: Dictionary
) -> void:
	var drawn := []
	var dust := 0.0
	var budget := BalanceOffline.OFFLINE_ITEM_SAMPLE_MAX
	var ilvl := int(expect["ilvl"])
	var profile: String = expect["profile"]
	for source in expect["items"]:
		var count := _draw_count(rng, n * float(source["count"]))
		summary["items_dropped"] += count
		var sampled := mini(count, budget)
		budget -= sampled
		for i in sampled:
			var item := (
				ItemFactory.make_item(
					rng, content, source["ref"], ItemFactory.roll_rarity(rng, profile), ilvl
				)
				if source["ref"] != ""
				else ItemFactory.roll_item(rng, content, profile, ilvl)
			)
			if not item.is_empty():
				drawn.append(item)
		dust += float(count - sampled) * expected_item_dust(profile, ilvl)
	var order := []
	for i in drawn.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return _item_better(drawn[a], drawn[b], a, b))
	var free := BalanceItems.INVENTORY_SLOTS - Inventory.bag_count(state)
	var keep := clampi(mini(BalanceOffline.OFFLINE_ITEM_KEEP_MAX, free), 0, drawn.size())
	var salvage := 0
	for rank in order.size():
		var item: Dictionary = drawn[order[rank]]
		if rank < keep:
			summary["items"].append(item)
		else:
			salvage += ItemFactory.salvage_value(item)
	summary["items_salvaged"] = summary["items_dropped"] - summary["items"].size()
	summary["salvage_dust"] = salvage + floori(dust)


static func _item_better(a: Dictionary, b: Dictionary, ia: int, ib: int) -> bool:
	var ra := BalanceItems.RARITIES.find(a["rarity"])
	var rb := BalanceItems.RARITIES.find(b["rarity"])
	if ra != rb:
		return ra > rb
	if int(a["item_level"]) != int(b["item_level"]):
		return int(a["item_level"]) > int(b["item_level"])
	return ia < ib


## Mean salvage dust of one item of `profile` at `ilvl`.
static func expected_item_dust(profile: String, ilvl: int) -> float:
	var weights: Dictionary = BalanceItems.RARITY_WEIGHTS.get(
		profile, BalanceItems.RARITY_WEIGHTS["normal"]
	)
	var total := 0.0
	var dust := 0.0
	for rarity in weights:
		total += float(weights[rarity])
		dust += float(weights[rarity]) * BalanceItems.salvage_dust(rarity, ilvl)
	return dust / total if total > 0.0 else 0.0


## Rune drops: same rule; the highest tiers are kept up to
## OFFLINE_RUNE_KEEP_MAX, the rest is salvaged into rune shards.
static func _draw_runes(
	summary: Dictionary, expect: Dictionary, n: float, rng: SeededRng, content: Dictionary
) -> void:
	var drawn := []
	var shards := 0.0
	var budget := BalanceOffline.OFFLINE_RUNE_SAMPLE_MAX
	var profile: String = expect["profile"]
	var tiers: Dictionary = BalanceGrimoire.RUNE_TIER_WEIGHTS.get(
		profile, BalanceGrimoire.RUNE_TIER_WEIGHTS["normal"]
	)
	for source in expect["runes"]:
		var count := _draw_count(rng, n * float(source["count"]))
		summary["runes_dropped"] += count
		var sampled := mini(count, budget)
		budget -= sampled
		for i in sampled:
			var rune := (
				{"id": source["ref"], "tier": int(rng.pick_weighted(tiers))}
				if source["ref"] != ""
				else ItemFactory.roll_rune(rng, content, profile)
			)
			if not rune.is_empty():
				drawn.append(rune)
		shards += float(count - sampled) * expected_rune_shards(profile)
	var order := []
	for i in drawn.size():
		order.append(i)
	order.sort_custom(
		func(a: int, b: int) -> bool:
			if int(drawn[a]["tier"]) != int(drawn[b]["tier"]):
				return int(drawn[a]["tier"]) > int(drawn[b]["tier"])
			return a < b
	)
	var salvage := 0
	for rank in order.size():
		var rune: Dictionary = drawn[order[rank]]
		if rank < BalanceOffline.OFFLINE_RUNE_KEEP_MAX:
			summary["runes"].append(rune)
		else:
			salvage += BalanceGrimoire.rune_salvage_shards(int(rune["tier"]))
	summary["runes_salvaged"] = summary["runes_dropped"] - summary["runes"].size()
	summary["rune_shards"] = salvage + floori(shards)


## Mean salvage shards of one dropped rune of `profile`.
static func expected_rune_shards(profile: String) -> float:
	var tiers: Dictionary = BalanceGrimoire.RUNE_TIER_WEIGHTS.get(
		profile, BalanceGrimoire.RUNE_TIER_WEIGHTS["normal"]
	)
	var total := 0.0
	var shards := 0.0
	for tier in tiers:
		total += float(tiers[tier])
		shards += float(tiers[tier]) * BalanceGrimoire.rune_salvage_shards(int(tier))
	return shards / total if total > 0.0 else 0.0


## The pending summary of state.offline, or {}.
static func pending(state: Dictionary) -> Dictionary:
	var list: Array = state.get("offline", {}).get("pending", [])
	return list[0] if not list.is_empty() else {}


## Stores a summary as the pending one (state mutated: pass a copy).
static func store(state: Dictionary, summary: Dictionary) -> void:
	state["offline"]["pending"] = [] if summary.is_empty() else [summary]


## Credits the pending summary once and clears it. A summary that is not "ok"
## credits nothing but is cleared too (the player has read it). Result extra:
## {summary, xp, gold, materials {id: n} (drops + salvage), levels_gained,
## level, items: [uid], auto_salvaged, salvage_dust, runes, lines}.
static func claim(state: Dictionary, content: Dictionary) -> Dictionary:
	var summary := pending(state)
	if summary.is_empty():
		return ActionResult.refuse("error.offline.nothing_to_claim")
	var next := state.duplicate(true)
	store(next, {})
	var extra := {
		"summary": summary,
		"xp": 0,
		"gold": 0,
		"materials": {},
		"levels_gained": 0,
		"level": int(next["characters"][next["party"][0]]["level"]),
		"items": [],
		"auto_salvaged": [],
		"salvage_dust": 0,
		"runes": [],
		"lines": [],
	}
	if summary["status"] != STATUS_OK:
		return ActionResult.success(next, extra)
	var hero: Dictionary = next["characters"][next["party"][0]]
	var leveled := BalanceProgression.grant_xp(hero["level"], hero["xp"], int(summary["xp"]))
	hero["level"] = leveled["level"]
	hero["xp"] = leveled["xp"]
	next["wallet"]["gold"] = int(next["wallet"]["gold"]) + int(summary["gold"])
	var materials: Dictionary = {}
	for id in summary["materials"]:
		materials[id] = int(summary["materials"][id])
	if int(summary["salvage_dust"]) > 0:
		var dust := BalanceItems.DUST_ID
		materials[dust] = int(materials.get(dust, 0)) + int(summary["salvage_dust"])
	if int(summary["rune_shards"]) > 0:
		var shard := BalanceGrimoire.SHARD_ID
		materials[shard] = int(materials.get(shard, 0)) + int(summary["rune_shards"])
	for id in materials:
		Inventory.add_material(next, id, materials[id])
	var loot := Inventory.receive(
		next, {"items": summary["items"], "runes": summary["runes"]}, content
	)
	extra["xp"] = int(summary["xp"])
	extra["gold"] = int(summary["gold"])
	extra["materials"] = materials
	extra["levels_gained"] = leveled["levels_gained"]
	extra["level"] = leveled["level"]
	for key in ["items", "auto_salvaged", "salvage_dust", "runes"]:
		extra[key] = loot[key]
	extra["lines"] = loot["lines"]
	if int(leveled["wasted"]) > 0:
		extra["lines"].append(Inventory.line("log.xp_wasted", {"xp": leveled["wasted"]}))
	return ActionResult.success(next, extra)


## Text lines of a summary for the "Pendant votre absence" screen:
## [{key, params}] (GameState.reason_text translates them).
static func lines(summary: Dictionary) -> Array:
	var out := []
	if summary.is_empty():
		return out
	var encounter: String = summary["encounter"]
	out.append(Inventory.line("log.offline.hunt", {"encounter": encounter + ".name"}))
	match str(summary["status"]):
		STATUS_CLOCK:
			out.append(Inventory.line("log.offline.clock", {}))
			return out
		STATUS_UNSAFE:
			var params := {
				"survival": floori(float(summary["survival_s"])),
				"required": ceili(float(summary["required_s"])),
			}
			out.append(Inventory.line(summary["reason"], params))
			return out
		STATUS_INELIGIBLE:
			var params := {
				"encounter": encounter + ".name",
				"seconds": ceili(float(summary["clear_time_s"])),
				"max": int(BalanceOffline.CLEAR_TIME_MAX_S),
			}
			out.append(Inventory.line(summary["reason"], params))
			return out
	var counted := int(summary["counted_s"])
	var duration := {"hours": counted / 3600, "minutes": (counted % 3600) / 60}
	out.append(Inventory.line("log.offline.duration", duration))
	if summary["capped"]:
		out.append(Inventory.line("log.offline.capped", {"hours": counted / 3600}))
	out.append(Inventory.line("log.offline.clears", {"count": floori(float(summary["clears"]))}))
	out.append(Inventory.line("log.offline.xp", {"xp": int(summary["xp"])}))
	if int(summary["levels_gained"]) > 0:
		var params := {
			"level": int(summary["level_after"]), "levels": int(summary["levels_gained"])
		}
		out.append(Inventory.line("log.offline.level_up", params))
	out.append(Inventory.line("log.offline.gold", {"gold": int(summary["gold"])}))
	var ids: Array = summary["materials"].keys()
	ids.sort()
	for id in ids:
		var params := {"qty": int(summary["materials"][id]), "material": id + ".name"}
		out.append(Inventory.line("log.offline.material", params))
	var kept: int = summary["items"].size()
	if kept > 0:
		out.append(Inventory.line("log.offline.items_kept", {"count": kept}))
	if int(summary["items_salvaged"]) > 0:
		var params := {
			"count": int(summary["items_salvaged"]), "dust": int(summary["salvage_dust"])
		}
		out.append(Inventory.line("log.offline.items_salvaged", params))
	if not summary["runes"].is_empty():
		out.append(Inventory.line("log.offline.runes_kept", {"count": summary["runes"].size()}))
	if int(summary["runes_salvaged"]) > 0:
		var params := {
			"count": int(summary["runes_salvaged"]), "shards": int(summary["rune_shards"])
		}
		out.append(Inventory.line("log.offline.runes_salvaged", params))
	if int(summary["xp_wasted"]) > 0:
		out.append(Inventory.line("log.xp_wasted", {"xp": int(summary["xp_wasted"])}))
	return out
