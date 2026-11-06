class_name ProgressionViews
extends RefCounted
## Read-only views of the game state for the progression screens, reached as
## `GameState.progression.views`. Nothing here changes the state.

var _owner: Node


func _init(owner: Node) -> void:
	_owner = owner


func _data() -> Dictionary:
	return _owner.data


func leader() -> String:
	return _owner.data["party"][0] if _owner.has_game() else ""


## {gold, materials: {id: qty}} of the party.
func wallet() -> Dictionary:
	return _data()["wallet"] if _owner.has_game() else {"gold": 0, "materials": {}}


## {level, xp, to_next (0 at the cap), cap} of the leader.
func xp_progress() -> Dictionary:
	var hero: Dictionary = _data()["characters"][leader()]
	var level := int(hero["level"])
	return {
		"level": level,
		"xp": int(hero["xp"]),
		"to_next": BalanceProgression.xp_to_next(level),
		"cap": BalanceProgression.LEVEL_CAP,
	}


## {slot: uid or ""} worn by the leader, in StateSchema order.
func worn_items() -> Dictionary:
	var out := {}
	var equipment: Dictionary = _data()["characters"][leader()]["equipment"]
	for slot in StateSchema.EQUIPMENT_SLOTS:
		out[slot] = str(equipment.get(slot, ""))
	return out


func equipment_slots() -> Array:
	return StateSchema.EQUIPMENT_SLOTS.duplicate()


func bag_capacity() -> int:
	return BalanceItems.INVENTORY_SLOTS


## Equipment slot of an item instance ("weapon"...).
func item_slot(item_instance: Dictionary) -> String:
	return Equipment.slot_of(item_instance, Content.index())


## Highest enhancement of a rarity.
func enhance_max(rarity: String) -> int:
	return BalanceItems.enhance_max(rarity)


## Spells that take ranks and runes: [{id, rank, max_rank, slots,
## runes: [{id, tier}], unlock_level, learned}].
func spells() -> Array:
	var out := []
	var level := int(_data()["characters"][leader()]["level"])
	for id in Grimoire.ranked_spells(leader(), Content.index()):
		var rank := Grimoire.rank_of(_data(), leader(), id)
		var need := Grimoire.unlock_level(leader(), id, Content.index())
		(
			out
			. append(
				{
					"id": id,
					"rank": rank,
					"max_rank": BalanceGrimoire.SPELL_RANK_MAX,
					"slots": BalanceGrimoire.rune_slots(rank),
					"runes": Grimoire.socketed(_data(), leader(), id).duplicate(true),
					"unlock_level": need,
					"learned": level >= need,
				}
			)
		)
	return out


## Runes in stock: [{id, tier, count}] with count > 0, by id then tier.
func rune_stock() -> Array:
	var out := []
	var ids: Array = _data()["runes"].keys()
	ids.sort()
	for id in ids:
		for tier in range(1, StateSchema.RUNE_TIERS + 1):
			var n := Inventory.rune_count(_data(), id, tier)
			if n > 0:
				out.append({"id": id, "tier": tier, "count": n})
	return out


## {id: qty} of carried consumables.
func consumables() -> Dictionary:
	return _data()["consumables"]


## Owned artifacts {id: level}.
func owned_artifacts() -> Dictionary:
	return _data()["artifacts"]


## Artifact slots of the leader: [{index, id, level_required, unlocked,
## lock (refusal shown while locked)}].
func artifact_slots() -> Array:
	var out := []
	var hero: Dictionary = _data()["characters"][leader()]
	var worn: Array = hero.get("artifacts", [])
	for i in BalanceEconomy.ARTIFACT_SLOT_LEVELS.size():
		var need := ArtifactRules.slot_level(i)
		var lock := ArtifactRules.slot_lock(_data(), leader(), i)
		var unlocked := lock.is_empty()
		(
			out
			. append(
				{
					"index": i,
					"id": str(worn[i]) if i < worn.size() else "",
					"level_required": need,
					"unlocked": unlocked,
					"lock": lock,
				}
			)
		)
	return out
