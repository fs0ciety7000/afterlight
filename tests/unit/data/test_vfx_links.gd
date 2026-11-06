extends TestCase
## Every `vfx` value in spells and abilities names an existing recipe
## (assets/vfx/recipes), and every recipe is valid.


func test_spell_and_ability_vfx_point_to_recipes() -> void:
	var r := ContentLoader.load_roots(["res://game/data/canon", "res://game/data/original"])
	for type_name in ["spell", "ability"]:
		for e in r["by_type"].get(type_name, []):
			var id: String = e.get("vfx", "")
			if id != "":
				assert_true(VfxRecipes.has(id), "%s: unknown recipe %s" % [e["id"], id])


func test_all_recipes_validate() -> void:
	for id in VfxRecipes.list_ids():
		var errors := VfxRecipes.validate(id, Vfx.BLOCKS.keys())
		assert_eq(errors.size(), 0, "%s: %s" % [id, ", ".join(errors)])
