class_name ExploreDungeon
extends Node
## The dungeon expedition in the explore screen (docs/content/dungeon.md
## §2.3): entering by the postern, rooms followed as Fern walks (closed
## grilles push her back), fountain and campfire, the bell-ringer's
## shortcut, leaving with its confirmation, the boss's lines and the bell.
## Every rule is in DungeonRun, reached through GameState.content_api.

const ROOM_REACH_M := 26.0
const FOUNTAIN_LINE_M := 9.0
## Anchor names that are not a room's centre (chest, Morvaine's alcoves).
const NOT_CENTRES := ["chest", "lantern"]

var host: Control
var view: ExploreView
var story: ExploreStory
## room id -> centre (world position), read from the scene's anchors.
var _centres := {}
var _last_good := Vector3.INF
var _elapsed := 0.0
var _boss_tried := false
var _fountain_line := false
## The scene has Rooms/<id> areas: they drive the rooms, not the centres.
var _has_areas := false


func inside() -> bool:
	return GameState.has_game() and str(GameState.summary().get("dungeon", "")) != ""


func dungeon_id() -> String:
	return str(GameState.summary().get("dungeon", "")) if GameState.has_game() else ""


## How to load the dungeon: {place, spawn, encounters} ({} outside). Fern
## stands at her room's spawn (the campfire once it is the checkpoint); the
## packs are the rooms not won yet.
func load_args() -> Dictionary:
	var v := GameState.content_api.dungeon_view()
	if v.is_empty():
		return {}
	var encounters := []
	for room: Dictionary in v["rooms"]:
		if room["encounter"] != "" and not room["cleared"]:
			encounters.append(room["encounter"])
	var spawn := "default"
	if v["room"] == v["checkpoint"] and v["checkpoint"] != DungeonRun.ENTRANCE:
		spawn = "checkpoint_" + str(v["checkpoint"])
	return {"place": v["dungeon_id"], "spawn": spawn, "encounters": encounters}


## Called once the dungeon scene is loaded.
func on_loaded() -> void:
	_centres.clear()
	_last_good = Vector3.INF
	_fountain_line = false
	for a: Node in view.anchors():
		var room := str(a.get_meta("room", ""))
		if room == "" or _centres.has(room) or not a is Node3D:
			continue
		if NOT_CENTRES.any(func(word: String) -> bool: return str(a.name).contains(word)):
			continue
		_centres[room] = (a as Node3D).global_position
	# Room areas of the scene (Rooms/<room id>): walking in moves the run.
	var rooms := view.scene_node("Rooms")
	_has_areas = rooms != null and rooms.get_child_count() > 0
	if rooms:
		for area: Node in rooms.get_children():
			if area is Area3D:
				var room := str(area.get_meta("room", area.name))
				_centres[room] = (area as Area3D).global_position
				(area as Area3D).body_entered.connect(_on_room_body.bind(room))
	apply_gates()
	_publish()


## Grilles (Gates/<name>, collision layer 5 by default): a room's grille is
## closed (blocking, visible) until its fight is won in this run; the
## shortcut grilles until Morvaine's first defeat.
func apply_gates() -> void:
	var gates := view.scene_node("Gates") if view else null
	var v := GameState.content_api.dungeon_view()
	if gates == null or v.is_empty():
		return
	var cleared := {}
	for r: Dictionary in v["rooms"]:
		cleared[r["id"]] = r["cleared"] or r["encounter"] == ""
	var states := {}
	for gate: Node in gates.get_children():
		if not gate is CollisionObject3D:
			continue
		var open: bool = (
			v["shortcut_open"]
			if str(gate.name).begins_with("shortcut")
			else cleared.get(str(gate.get_meta("room", "")), true)
		)
		var body := gate as CollisionObject3D
		body.set_collision_layer_value(1, not open)
		var grille := gate.get_node_or_null("Grille") as Node3D
		if grille:
			grille.visible = not open
		states[str(gate.name)] = open
	UiProbe.world["dungeon_gates"] = states


func _on_room_body(body: Node3D, room: String) -> void:
	if body != view.player or not inside() or view.player.combat_driven:
		return
	_enter_room(room, body.global_position)


## Fern walks into `room`: the run follows, or a closed door pushes her back.
func _enter_room(room: String, pos: Vector3) -> void:
	var v := GameState.content_api.dungeon_view()
	if v.is_empty() or room == v["room"]:
		_last_good = pos
		return
	var open := false
	for r: Dictionary in v["rooms"]:
		if r["id"] == room:
			open = r["accessible"]
	if open:
		if GameState.content_api.dungeon_move(room)["ok"]:
			_last_good = pos
			_publish()
	elif _last_good != Vector3.INF:
		view.teleport(_last_good, view.player.global_basis)
		host.call("show_toast", tr("ui.dungeon.door_locked"), true)


## Fountain and campfire of the scene.
func interactables() -> Array:
	var out := []
	if not inside():
		return out
	for a: Node in view.anchors():
		var kind := str(a.get_meta("interact", ""))
		if kind not in ["fountain", "campfire"]:
			continue
		(
			out
			. append(
				{
					"id": kind,
					"kind": kind,
					"anchor": a,
					"name": tr("ui.story.%s_name" % kind),
					"prompt": tr("ui.dungeon." + kind),
					"radius": 3.5,
					"trigger": "interact",
					"marker": "",
					"model": "",
				}
			)
		)
	return out


# --- Entering, leaving ------------------------------------------------------------------


func enter(target: String) -> void:
	var r := GameState.content_api.enter_dungeon(target)
	if not r["ok"]:
		host.call("show_toast", GameState.reason_text(r), true)
		return
	_boss_tried = false
	GameState.runtime_position = null
	host.call("reload_place")
	SaveService.save_now()
	if r.get("first", false):
		story.play_dialogue("dialogue.fern_dungeon_enter", true)


## An exit of the dungeon scene was reached: the door out, the exit after
## the boss, or the bell-ringer's stair.
func on_exit(to: String, spawn: String, area: Area3D) -> void:
	var needs := str(area.get_meta("requires_cleared", "")) if area else ""
	if needs != "" and int(GameState.data["progress"]["cleared_encounters"].get(needs, 0)) == 0:
		host.call("show_toast", tr("ui.dungeon.door_locked"), true)
		return
	if to == dungeon_id():
		_shortcut(spawn)
		return
	var q := GameState.content_api.leave_dungeon_quote()
	if not q["ok"]:
		return
	var boss_won := needs != ""
	if q.get("confirm", false) and not boss_won:
		story.set_busy(true)
		var d := ConfirmDialog.open(
			host, tr("ui.story.leave_title"), tr("ui.dungeon.leave_confirm"), "dungeon.leave"
		)
		d.confirmed.connect(
			func() -> void:
				story.set_busy(false)
				leave()
		)
		d.cancelled.connect(
			func() -> void:
				story.set_busy(false)
				view.place_at("default")
		)
		return
	leave()


func leave() -> void:
	var r := GameState.content_api.leave_dungeon()
	if not r["ok"]:
		return
	GameState.runtime_position = null
	host.call("reload_place")
	SaveService.save_now()


func _shortcut(spawn: String) -> void:
	var room := "campfire" if spawn.ends_with("campfire") else "vestibule"
	var r := GameState.content_api.dungeon_move(room)
	if not r["ok"]:
		host.call("show_toast", GameState.reason_text(r), true)
		return
	view.place_at(spawn)
	_last_good = view.player.global_position
	host.call("show_toast", tr("ui.dungeon.shortcut"))


# --- Fountain, campfire ----------------------------------------------------------------


func use(kind: String) -> void:
	var api := GameState.content_api
	var r := api.use_fountain() if kind == "fountain" else api.rest_at_campfire()
	if not r["ok"]:
		var text := (
			tr("ui.dungeon.fountain_used")
			if r["error"] == "error.dungeon.fountain_used"
			else GameState.reason_text(r)
		)
		host.call("show_toast", text, true)
		return
	SaveService.save_now()
	if kind == "fountain":
		host.call(
			"show_toast",
			tr("ui.story.fountain_healed").format({"pct": roundi(float(r["heal_pct"]) * 100.0)})
		)
	else:
		host.call("show_toast", tr("ui.story.rested"))
	_publish()


# --- Rooms --------------------------------------------------------------------------------


func _process(delta: float) -> void:
	if not inside() or view == null or view.player == null or _centres.is_empty():
		return
	if view.player.combat_driven or story.busy:
		return
	_elapsed += delta
	if _elapsed < 0.2:
		return
	_elapsed = 0.0
	var pos := view.player.global_position
	var room := room_at(pos)
	if room == "" or _has_areas:
		if room == str(GameState.content_api.dungeon_view().get("room", "")):
			_last_good = pos
	else:
		_enter_room(room, pos)
	if not _fountain_line and _centres.has("fountain"):
		if pos.distance_to(_centres["fountain"]) <= FOUNTAIN_LINE_M:
			_fountain_line = true
			story.play_dialogue("dialogue.fern_fountain", true)


## Room whose centre is the nearest within reach ("" in the corridors far
## from every room).
func room_at(pos: Vector3) -> String:
	var best := ""
	var best_d := ROOM_REACH_M
	for room: String in _centres:
		var c: Vector3 = _centres[room]
		var d := Vector2(pos.x, pos.z).distance_to(Vector2(c.x, c.z)) + absf(pos.y - c.y)
		if d < best_d:
			best = room
			best_d = d
	return best


func _publish() -> void:
	var v := GameState.content_api.dungeon_view()
	if v.is_empty():
		UiProbe.world["dungeon"] = {}
		return
	var cleared := []
	for r: Dictionary in v["rooms"]:
		if r["cleared"]:
			cleared.append(r["id"])
	UiProbe.world["dungeon"] = {
		"room": v["room"],
		"checkpoint": v["checkpoint"],
		"cleared": cleared,
		"shortcut_open": v["shortcut_open"],
		"fountain_used": v["fountain_used"],
		"hp_pct": v["vitals"]["hp_pct"],
	}


# --- Combat ---------------------------------------------------------------------------------


## Room of an encounter of the running dungeon ({} if none).
func room_of(encounter_id: String) -> Dictionary:
	var v := GameState.content_api.dungeon_view()
	for r: Dictionary in v.get("rooms", []):
		if r["encounter"] == encounter_id:
			return r
	return {}


## Before a room fight: Morvaine speaks first (intro, then a single line on
## the next tries). Calls `start` when the fight may begin.
func before_combat(encounter_id: String, start: Callable) -> void:
	var room := room_of(encounter_id)
	if room.is_empty() or room["kind"] != "boss":
		start.call()
		return
	var line := "dialogue.morvaine_retry" if _boss_tried else "dialogue.morvaine_intro"
	_boss_tried = true
	story.play_dialogue(line, false, start)


## HP, mana and ultimate charge carried from the last room (they do not come
## back between rooms) merged into the party entry of a room fight.
func combat_setup(encounter_id: String, setup: Dictionary) -> Dictionary:
	if room_of(encounter_id).is_empty():
		return setup
	var out := setup.duplicate(true)
	var party: Array = out.get("party", [])
	if not party.is_empty():
		(party[0] as Dictionary).merge(GameState.content_api.dungeon_vitals(), true)
	return out


## After a room fight: Morvaine's last words, Fern's, and the bell.
func after_combat(encounter_id: String, victory: bool) -> void:
	apply_gates()
	_publish()
	var room := room_of(encounter_id)
	if not victory or room.is_empty() or room["kind"] != "boss":
		return
	var lines := StoryText.dialogue_lines("dialogue.morvaine_defeat")
	lines.append_array(StoryText.dialogue_lines("dialogue.fern_after_boss"))
	lines.append({"speaker": "", "key": "story.bell.subtitle"})
	UiProbe.world["bell_rung"] = true
	story.play_lines(lines, true)
