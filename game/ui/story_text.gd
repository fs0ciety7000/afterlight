class_name StoryText
extends RefCounted
## Display helpers for the Milestone 6 story UI: dialogue lines, quest
## objectives and rewards, banners for GameState.story_events, bestiary and
## contract lines. Every word comes from strings.csv.

const ELEMENTS := ["arcane", "fire", "frost", "lightning"]
const COMPASS := "artifact.traveler_compass"
## Events that become a banner (others only refresh the HUD).
const BANNER_TYPES := [
	"quest_activated",
	"quest_progress",
	"quest_completed",
	"quest_turned_in",
	"discovery_found",
	"bestiary_tier_unlocked",
	"contract_completed",
	"contracts_auto_claimed",
	"dungeon_checkpoint",
	"dungeon_shortcut_opened",
]


static func tr_key(key: String) -> String:
	return TranslationServer.translate(key)


## Name of a speaker (npc.*, character.fern, enemy.morvaine).
static func speaker_name(id: String) -> String:
	if id == "":
		return ""
	var e := Content.get_entity(id)
	return tr_key(str(e.get("name_key", id + ".name")))


## Lines of a dialogue that is not an NPC's (Fern, Morvaine):
## [{speaker, key}], the same shape as ContentApi.talk().
static func dialogue_lines(dialogue_id: String) -> Array:
	var out := []
	for line in Content.get_entity(dialogue_id).get("lines", []):
		out.append({"speaker": line["speaker"], "key": "%s.%s" % [dialogue_id, line["key_suffix"]]})
	return out


## « Cueillir des herbes de brume (2/6) ».
static func objective_text(o: Dictionary) -> String:
	return tr_key(str(o["key"])).format({"n": int(o["count"])})


## « +120 XP, +100 or, 1 × Page de grimoire » from a reward preview or a
## quest_turned_in / discovery_found event.
static func rewards_text(r: Dictionary) -> String:
	var parts := []
	if int(r.get("xp", 0)) > 0 or int(r.get("gold", 0)) > 0:
		parts.append(
			tr_key("ui.quest.rewards").format({"xp": int(r.get("xp", 0)), "gold": r.get("gold", 0)})
		)
	var materials: Dictionary = r.get("materials", {})
	var ids := materials.keys()
	ids.sort()
	for id in ids:
		parts.append(
			tr_key("ui.fmt.material").format(
				{"qty": int(materials[id]), "name": Content.display_name(id)}
			)
		)
	for id in r.get("artifacts", []):
		parts.append(Content.display_name(str(id)))
	if not r.get("items", []).is_empty():
		parts.append(tr_key("ui.story.items").format({"count": r["items"].size()}))
	return tr_key("ui.common.separator").join(parts)


## Banner text of a story event ("" when it shows none).
static func banner_text(e: Dictionary) -> String:
	match str(e.get("type", "")):
		"quest_activated":
			return tr_key("ui.quest.activated").format({"quest": quest_name(e["quest"])})
		"quest_progress":
			var q := Content.get_entity(str(e["quest"]))
			if q.get("kind", "") == "daily":
				return ""
			var o := {"key": "%s.objective_%s" % [e["quest"], e["objective"]], "count": e["count"]}
			return tr_key("ui.story.progress").format(
				{"quest": quest_name(e["quest"]), "objective": objective_text(o)}
			)
		"quest_completed":
			var giver := str(Content.get_entity(str(e["quest"])).get("giver", ""))
			return tr_key("ui.quest.completed").format(
				{"quest": quest_name(e["quest"]), "npc": speaker_name(giver)}
			)
		"quest_turned_in":
			return tr_key("ui.quest.turned_in").format({"quest": quest_name(e["quest"])})
		"discovery_found":
			var text := tr_key("ui.discovery.found").format(
				{"name": Content.display_name(str(e["discovery_id"]))}
			)
			var reward := rewards_text(e)
			return text if reward == "" else text + tr_key("ui.common.separator") + reward
		"bestiary_tier_unlocked":
			return (
				tr_key("ui.bestiary.unlocked")
				. format(
					{
						"name": Content.display_name(str(e["enemy_id"])),
						"tier": tr_key("ui.bestiary.tier_%d" % int(e["tier"])),
					}
				)
			)
		"contract_completed":
			return tr_key("ui.story.contract_done").format(
				{"contract": Content.display_name(str(e["id"]))}
			)
		"contracts_auto_claimed":
			return tr_key("ui.contracts.auto_claimed").format({"gold": e.get("gold", 0)})
		"dungeon_checkpoint":
			return tr_key("ui.dungeon.checkpoint").format({"room": room_name(str(e["room"]))})
		"dungeon_shortcut_opened":
			return tr_key("ui.story.shortcut_opened")
	return ""


static func quest_name(quest_id: Variant) -> String:
	return Content.display_name(str(quest_id))


## Name of a room of the running dungeon (« Vestibule »).
static func room_name(room_id: String, dungeon_id: String = "") -> String:
	var d := dungeon_id
	if d == "" and GameState.has_game():
		d = str(GameState.summary().get("dungeon", ""))
	return tr_key("%s.room_%s" % [d, room_id]) if d != "" else room_id


## « Quête principale · niveau 3 · En cours ».
static func quest_meta(entry: Dictionary) -> String:
	return (
		tr_key("ui.common.separator")
		. join(
			[
				tr_key("ui.journal.kind_" + str(entry["kind"])),
				tr_key("ui.journal.level").format({"level": entry["level"]}),
				tr_key("ui.journal.state_" + str(entry["state"])),
			]
		)
	)


## « Faible » / « Résiste » / « Neutre » for one element of an enemy.
static func affinity_line(enemy: Dictionary, element: String) -> String:
	var a := str(enemy.get("affinities", {}).get(element, "neutral"))
	return tr_key("ui.story.affinity").format(
		{"element": tr_key("ui.element." + element), "affinity": tr_key("ui.affinity." + a)}
	)


## What unlocks the next bestiary tier: « Prochain palier : 5 victoires ».
static func next_tier_text(entry: Dictionary) -> String:
	if int(entry.get("next", 0)) <= 0:
		return tr_key("ui.journal.bestiary_complete")
	return tr_key("ui.journal.bestiary_next").format({"count": int(entry["next"])})


## « 12/20 » of a contract or a counted objective.
static func progress_text(count: int, needed: int) -> String:
	return "%d/%d" % [mini(count, needed), needed]


## True when the leader wears the traveler's compass (« ? » hints).
static func compass_worn() -> bool:
	if not GameState.has_game():
		return false
	var hero: Dictionary = GameState.data["characters"].get(GameState.data["party"][0], {})
	return hero.get("artifacts", []).has(COMPASS)
