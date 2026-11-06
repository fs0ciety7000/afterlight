class_name ItemFactory
extends RefCounted
## Equipment and rune drops (docs/GAME_BALANCE.md §14, §17): rarity by
## source, item level, implicit, affixes without duplicate id or group,
## legendary effects. Pure: every draw goes through the SeededRng it is given.
##
## An item instance is a plain Dictionary (saved as is, see StateSchema):
## {uid, item_id, rarity, item_level, affixes: [{id, value}], legendary,
##  enhance, enhance_attempts, pity}. `value` is the rolled affix value at +0;
## enhancement scales implicit and flat affixes when modifiers are computed.

static var _catalog_source: Dictionary = {}
static var _catalog: Dictionary = {}


## Content lists used by the rolls, sorted by id so the draws never depend on
## dictionary order. Cached per content index.
static func catalog(content: Dictionary) -> Dictionary:
	if is_same(content, _catalog_source) and not _catalog.is_empty():
		return _catalog
	var bases := {}
	var affixes := {}
	var legendaries := {}
	var runes := []
	var ids := content.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = content[id]
		match e.get("_type", ""):
			"item":
				_push(bases, e["slot"], id)
			"affix":
				for slot in e["slots"]:
					_push(affixes, slot, id)
			"legendary":
				_push(legendaries, e["slot"], id)
			"rune":
				runes.append(id)
	_catalog = {"bases": bases, "affixes": affixes, "legendaries": legendaries, "runes": runes}
	_catalog_source = content
	return _catalog


static func _push(map: Dictionary, key: String, id: String) -> void:
	if not map.has(key):
		map[key] = []
	map[key].append(id)


## Rarity drawn from the source's weights (§14.1).
static func roll_rarity(rng: SeededRng, profile: String) -> String:
	var weights: Dictionary = BalanceItems.RARITY_WEIGHTS.get(
		profile, BalanceItems.RARITY_WEIGHTS["normal"]
	)
	var picked: Variant = rng.pick_weighted(weights)
	return str(picked) if picked != null else "common"


## A new item (without uid) for a loot profile at item level `ilvl`.
## Returns {} if the content has no item base.
static func roll_item(
	rng: SeededRng, content: Dictionary, profile: String, ilvl: int
) -> Dictionary:
	var cat := catalog(content)
	var rarity := roll_rarity(rng, profile)
	var slots := _eligible_slots(cat, content, ilvl, rarity == "legendary")
	if slots.is_empty():
		return {}
	var slot: String = slots[rng.range_int(0, slots.size() - 1)]
	var bases := _eligible_bases(cat, content, slot, ilvl)
	var base_id: String = bases[rng.range_int(0, bases.size() - 1)]
	return make_item(rng, content, base_id, rarity, ilvl)


## Rolls affixes (and the legendary effect) of a given base and rarity.
static func make_item(
	rng: SeededRng, content: Dictionary, base_id: String, rarity: String, ilvl: int
) -> Dictionary:
	var base: Dictionary = content[base_id]
	var cat := catalog(content)
	var pool: Array = base.get("affix_pools", [])
	if pool.is_empty():
		pool = cat["affixes"].get(base["slot"], [])
	var affixes := []
	var used_groups := {}
	var used_ids := {}
	var u_min := BalanceItems.LEGENDARY_ROLL_MIN if rarity == "legendary" else 0.0
	for i in int(BalanceItems.AFFIX_COUNT[rarity]):
		var weights := {}
		for id in pool:
			var a: Dictionary = content[id]
			if not used_ids.has(id) and not used_groups.has(a["group"]):
				weights[id] = float(a["weight"])
		var picked: Variant = rng.pick_weighted(weights)
		if picked == null:
			break
		var affix: Dictionary = content[picked]
		used_ids[picked] = true
		used_groups[affix["group"]] = true
		var u := rng.range_float(u_min, 1.0)
		var span := affix_range(affix, ilvl)
		affixes.append({"id": picked, "value": lerpf(span[0], span[1], u)})
	var legendary := ""
	if rarity == "legendary":
		var weights := {}
		for id in cat["legendaries"].get(base["slot"], []):
			weights[id] = float(content[id]["weight"])
		var picked: Variant = rng.pick_weighted(weights)
		legendary = str(picked) if picked != null else ""
	return {
		"uid": "",
		"item_id": base_id,
		"rarity": rarity,
		"item_level": ilvl,
		"affixes": affixes,
		"legendary": legendary,
		"enhance": 0,
		"enhance_attempts": 0,
		"pity": 0,
	}


## Scaled [min, max] of an affix at `ilvl` (the range shown to the player).
static func affix_range(affix: Dictionary, ilvl: int) -> Array:
	var scale := BalanceItems.affix_scale(affix["scaling"], ilvl)
	return [float(affix["min"]) * scale, float(affix["max"]) * scale]


## Slots that can drop at `ilvl`. A legendary only rolls on a slot that has a
## legendary effect (GAME_BALANCE §14.3, provisional rule of jalon 4).
static func _eligible_slots(
	cat: Dictionary, content: Dictionary, ilvl: int, legendary: bool
) -> Array:
	var out := []
	for slot in ContentSchemas.SLOTS:
		if _eligible_bases(cat, content, slot, ilvl).is_empty():
			continue
		if legendary and cat["legendaries"].get(slot, []).is_empty():
			continue
		out.append(slot)
	if out.is_empty() and legendary:
		return _eligible_slots(cat, content, ilvl, false)
	return out


static func _eligible_bases(cat: Dictionary, content: Dictionary, slot: String, ilvl: int) -> Array:
	var out := []
	for id in cat["bases"].get(slot, []):
		if int(content[id]["min_ilvl"]) <= ilvl:
			out.append(id)
	return out


## A rune drop {id, tier}: tier by profile (§17), type by rune weight.
static func roll_rune(rng: SeededRng, content: Dictionary, profile: String) -> Dictionary:
	var cat := catalog(content)
	var tiers: Dictionary = BalanceGrimoire.RUNE_TIER_WEIGHTS.get(
		profile, BalanceGrimoire.RUNE_TIER_WEIGHTS["normal"]
	)
	var tier: Variant = rng.pick_weighted(tiers)
	var weights := {}
	for id in cat["runes"]:
		weights[id] = float(content[id]["weight"])
	var rune: Variant = rng.pick_weighted(weights)
	if rune == null or tier == null:
		return {}
	return {"id": str(rune), "tier": int(tier)}


## Stat modifiers of an item: [{stat, layer ("flat" | "percent"), value, from}]
## where `from` is "implicit" or the affix id.
static func modifiers(item: Dictionary, content: Dictionary) -> Array:
	var base: Dictionary = content.get(item["item_id"], {})
	if base.is_empty():
		return []
	var ilvl := int(item["item_level"])
	var enhance := int(item["enhance"])
	var out := []
	for line in base["implicit"]:
		var value := BalanceItems.implicit_value(
			line["stat"], float(line["base"]), ilvl, item["rarity"], enhance
		)
		out.append({"stat": line["stat"], "layer": "flat", "value": value, "from": "implicit"})
	for a in item["affixes"]:
		var affix: Dictionary = content.get(a["id"], {})
		if affix.is_empty():
			continue
		var value := float(a["value"])
		if affix["scaling"] == "flat":
			value *= BalanceItems.enhance_mult(enhance)
		out.append(
			{"stat": affix["stat"], "layer": affix["layer"], "value": value, "from": a["id"]}
		)
	return out


## Sums modifiers by layer: {flat: {stat: value}, percent: {stat: value}}.
static func sum_modifiers(mods: Array) -> Dictionary:
	var flat := {}
	var percent := {}
	for m in mods:
		var target: Dictionary = flat if m["layer"] == "flat" else percent
		target[m["stat"]] = float(target.get(m["stat"], 0.0)) + float(m["value"])
	return {"flat": flat, "percent": percent}


## Mana dust given by salvaging this item (§13).
static func salvage_value(item: Dictionary) -> int:
	return BalanceItems.salvage_dust(item["rarity"], int(item["item_level"]))
