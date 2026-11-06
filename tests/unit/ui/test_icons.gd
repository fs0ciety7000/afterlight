extends TestCase
## Painted icons: every `icon` path of the iconed families exists, and spells, item bases,
## runes, materials, consumables and artifacts all resolve to a texture. (Status icons are
## not painted yet: their `icon` paths are placeholders.)

const ICONED := ["item", "rune", "material", "consumable", "artifact"]


func test_data_icon_paths_exist() -> void:
	var r := ContentLoader.load_roots(["res://game/data/canon", "res://game/data/original"])
	for type_name in ICONED:
		for e in r["by_type"].get(type_name, []):
			var path: String = e.get("icon", "")
			if path.begins_with("res://assets/textures/icons/"):
				assert_true(ResourceLoader.exists(path), "%s: missing icon %s" % [e["id"], path])


func test_every_icon_family_resolves() -> void:
	var ids := [
		"spell.zoltraak", "spell.mana_volley", "spell.defensive_barrier", "spell.afterlight"
	]
	ids.append("passive.veiled_mana")
	for type_name in ICONED:
		for e in Content.all_of(type_name):
			ids.append(e["id"])
	assert_true(ids.size() >= 35, "35 icons expected, got %d ids" % ids.size())
	for id in ids:
		assert_true(GameIcons.for_id(id) != null, "%s has no icon" % id)


func test_unknown_id_falls_back_to_glyph() -> void:
	assert_true(GameIcons.for_id("item.does_not_exist") == null)
	assert_true(GameIcons.for_id("") == null)
	var tile := ItemTile.make(64)
	tile.show_item({"item_id": "item.birch_staff", "rarity": "rare"}, "weapon")
	assert_true(tile.painted_icon != null, "item tile uses the item base icon")
	tile.show_kind(ItemTile.KIND_EMPTY)
	assert_true(tile.painted_icon == null, "empty tile has no icon")
	tile.free()
