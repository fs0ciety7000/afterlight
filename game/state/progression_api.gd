class_name ProgressionApi
extends RefCounted
## Progression actions for the UI (Milestone 4): thin wrappers around the pure
## engine (game/engine/progression), reached as `GameState.progression`.
## Each action returns the engine's result without the state:
## {ok, error, params, ...}; on success GameState adopts the new state, marks
## it dirty and saves it. A refusal's `error` is a translation key filled by
## `params`: GameState.reason_text(result) gives the French text.

## Read-only views for the progression screens (wallet, slots, spells...).
var views: ProgressionViews
var _owner: Node


func _init(owner: Node) -> void:
	_owner = owner
	views = ProgressionViews.new(owner)


func _data() -> Dictionary:
	return _owner.data


func leader() -> String:
	return _owner.data["party"][0] if _owner.has_game() else ""


## Adopts a successful ActionResult and strips the state from it.
func _commit(r: Dictionary) -> Dictionary:
	var out := r.duplicate()
	out.erase("state")
	if r["ok"]:
		_owner.commit_action(r["state"])
	return out


## Quotes never change the state.
func _peek(r: Dictionary) -> Dictionary:
	var out := r.duplicate()
	out.erase("state")
	return out


## Final stats of the leader (equipment, artifacts, level).
func hero_stats() -> Dictionary:
	return Equipment.stats(_data(), leader(), Content.index())


## Modifiers by source [{source, stat, layer, value, from}].
func hero_modifiers() -> Array:
	return Equipment.modifiers(_data(), leader(), Content.index())


## Bag items (not worn), each an item instance (see ItemFactory).
func bag_items() -> Array:
	return Inventory.bag(_data())


func item(uid: String) -> Dictionary:
	return Inventory.find(_data(), uid)


## Item modifiers [{stat, layer, value, from}] for an item card.
func item_modifiers(uid: String) -> Array:
	return ItemFactory.modifiers(Inventory.find(_data(), uid), Content.index())


## Scaled [min, max] of an affix on an item (the "[5-9]" range).
func affix_range(affix_id: String, item_level: int) -> Array:
	return ItemFactory.affix_range(Content.get_entity(affix_id), item_level)


## Per-stat comparison with the worn item of the same slot:
## [{stat, layer, candidate, current, delta, sign: better|worse|equal}].
func compare_item(uid: String) -> Array:
	return Equipment.compare_with_worn(_data(), leader(), uid, Content.index())


func equip_item(uid: String) -> Dictionary:
	return _commit(Equipment.equip(_data(), leader(), uid, Content.index()))


func unequip_slot(slot: String) -> Dictionary:
	return _commit(Equipment.unequip(_data(), leader(), slot))


func salvage_items(uids: Array) -> Dictionary:
	return _commit(Inventory.salvage(_data(), uids))


## {uids, count, dust} for the bulk salvage confirmation.
func salvage_quote(rarities: Array) -> Dictionary:
	return Inventory.salvage_quote(_data(), rarities)


func salvage_rarities(rarities: Array) -> Dictionary:
	return _commit(Inventory.salvage_by_rarity(_data(), rarities))


func enhance_quote(uid: String) -> Dictionary:
	return _peek(Forge.quote(_data(), uid))


func enhance_item(uid: String) -> Dictionary:
	return _commit(Forge.enhance(_data(), uid))


func rank_quote(spell_id: String) -> Dictionary:
	return _peek(Grimoire.rank_quote(_data(), leader(), spell_id, Content.index()))


func rank_up_spell(spell_id: String) -> Dictionary:
	return _commit(Grimoire.rank_up(_data(), leader(), spell_id, Content.index()))


func socket_rune(spell_id: String, rune_id: String, tier: int) -> Dictionary:
	return _commit(Grimoire.socket(_data(), leader(), spell_id, rune_id, tier, Content.index()))


func unsocket_rune(spell_id: String, index: int) -> Dictionary:
	return _commit(Grimoire.unsocket(_data(), leader(), spell_id, index))


func fusion_quote(rune_id: String, tier: int) -> Dictionary:
	return _peek(RuneRules.fusion_quote(_data(), rune_id, tier, Content.index()))


func fuse_runes(rune_id: String, tier: int) -> Dictionary:
	return _commit(RuneRules.fuse(_data(), rune_id, tier, Content.index()))


func salvage_rune(rune_id: String, tier: int, qty: int = 1) -> Dictionary:
	return _commit(RuneRules.salvage(_data(), rune_id, tier, qty))


func equip_artifact(index: int, artifact_id: String) -> Dictionary:
	return _commit(ArtifactRules.equip(_data(), leader(), index, artifact_id))


func unequip_artifact(index: int) -> Dictionary:
	return _commit(ArtifactRules.unequip(_data(), leader(), index))


func artifact_quote(artifact_id: String) -> Dictionary:
	return _peek(ArtifactRules.level_quote(_data(), artifact_id))


func level_artifact(artifact_id: String) -> Dictionary:
	return _commit(ArtifactRules.level_up(_data(), artifact_id))


## [{id, price, carried, carry_max}] of a shop.
func shop_stock(shop_id: String) -> Array:
	return Merchant.stock(_data(), shop_id, Content.index())


func buy_quote(shop_id: String, consumable_id: String, qty: int = 1) -> Dictionary:
	return _peek(Merchant.buy_quote(_data(), shop_id, consumable_id, qty, Content.index()))


func buy(shop_id: String, consumable_id: String, qty: int = 1) -> Dictionary:
	return _commit(Merchant.buy(_data(), shop_id, consumable_id, qty, Content.index()))


func unequip_quote(slot: String) -> Dictionary:
	return _peek(Equipment.unequip(_data(), leader(), slot))


func salvage_items_quote(uids: Array) -> Dictionary:
	return _peek(Inventory.salvage(_data(), uids))


func socket_quote(spell_id: String, rune_id: String, tier: int) -> Dictionary:
	return _peek(Grimoire.socket(_data(), leader(), spell_id, rune_id, tier, Content.index()))


func salvage_rune_quote(rune_id: String, tier: int) -> Dictionary:
	return _peek(RuneRules.salvage(_data(), rune_id, tier, 1))


func artifact_equip_quote(index: int, artifact_id: String) -> Dictionary:
	return _peek(ArtifactRules.equip(_data(), leader(), index, artifact_id))


func artifact_unequip_quote(index: int) -> Dictionary:
	return _peek(ArtifactRules.unequip(_data(), leader(), index))


## CombatSim setup fields for the saved party: {party: [entry], consumables}.
func combat_setup() -> Dictionary:
	return PartyBuild.setup(_data(), Content.index())
