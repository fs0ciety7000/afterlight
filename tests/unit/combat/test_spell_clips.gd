extends TestCase
## Spell clips: every `anim` field names a clip of its caster's model, and the combat view picks
## the spell clip with the generic one as fallback.

const ENEMY_CLIPS := ["idle", "run", "attack", "cast", "hit", "death"]


func _clips(path: String) -> PackedStringArray:
	var scene := (load(path) as PackedScene).instantiate()
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	var names := PackedStringArray()
	if not players.is_empty():
		names = (players[0] as AnimationPlayer).get_animation_list()
	scene.free()
	return names


func test_player_spell_clips_exist_in_fern() -> void:
	var clips := _clips(ExplorePlayer.MODEL)
	for base in ["idle", "walk", "run", "cast", "hit", "death", "victory"]:
		assert_true(clips.has(base), "fern.glb lost clip %s" % base)
	var r := ContentLoader.load_roots(["res://game/data/canon", "res://game/data/original"])
	var seen := 0
	for e in r["by_type"].get("spell", []):
		var anim: String = e.get("anim", "")
		if anim != "":
			seen += 1
			assert_true(clips.has(anim), "%s: fern.glb has no clip %s" % [e["id"], anim])
	assert_true(seen >= 4, "Zoltraak, volley, barrier and ultimate each name a clip")


func test_enemy_models_keep_combat_clips() -> void:
	for e in Content.all_of("enemy"):
		var model: String = e.get("model", "")
		if model == "":
			continue
		var clips := _clips(model)
		for c in ENEMY_CLIPS:
			assert_true(clips.has(c), "%s: missing clip %s" % [model, c])


func test_cast_clip_uses_anim_then_generic() -> void:
	assert_eq(CombatView.cast_clip("spell.zoltraak", "cast"), "cast_beam")
	assert_eq(CombatView.cast_clip("spell.afterlight", "cast"), "cast_ultimate")
	assert_eq(CombatView.cast_clip("spell.mana_bolt", "cast"), "cast")
	assert_eq(CombatView.cast_clip("ability.morvaine_ash_bolt", "attack"), "attack")
	assert_eq(CombatView.cast_clip("", "attack"), "attack")
