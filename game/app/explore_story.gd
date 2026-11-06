class_name ExploreStory
extends Node
## Milestone 6 content in the explore screen: NPCs with their quest markers
## and dialogues, discoveries, chests and herbs, story cards and Fern's short
## lines. Reads and acts only through GameState.content_api; the world layer
## (WorldInteractables) only draws. Owned by the explore screen (`host`).

signal prompt_changed(text: String)

const TALK_RADIUS_M := 3.5
const USE_RADIUS_M := 2.5
const ZONE_RADIUS_M := 3.0
const HOLD_S := 1.5
## Screens opened after a service NPC's dialogue (dialogues.md §1).
const PANELS := {
	"smith": "forge",
	"runecarver": "runecarver",
	"merchant": "merchant",
	"board": "journal",
}
## Fern's line on the first visit of a place (dialogues.md §9.1).
const FIRST_VISIT_LINES := {
	"location.lantern_mire": "dialogue.fern_enter_mire",
	"location.watch_ruins": "dialogue.fern_enter_ruins",
}

## The explore screen: overlays go on it; it shows toasts and reloads places.
var host: Control
var view: ExploreView
var dungeon: ExploreDungeon
## A dialogue, a card or a hold is running: the world waits.
var busy := false
var _check_elapsed := 0.0
var _prompt_id := ""
## Clicked from afar: walk there, then use it.
var _pending := ""
var _hold_id := ""
var _hold_left := 0.0


func _ready() -> void:
	GameState.changed.connect(_refresh_markers)


# --- Building the place ----------------------------------------------------------


## Fills the place with its NPCs, discoveries and dungeon things.
func populate() -> void:
	if view == null or view.interactables == null:
		return
	var entries := []
	var place := place_id()
	for npc: Dictionary in GameState.content_api.npcs_here():
		var anchor := view.anchor(str(npc["anchor"]))
		if anchor == null:
			continue
		var nm := tr(str(npc["name_key"]))
		var is_board: bool = npc["role"] == "board"
		(
			entries
			. append(
				{
					"id": npc["id"],
					"kind": "board" if is_board else "npc",
					"anchor": anchor,
					"name": nm,
					"prompt":
					(
						tr("ui.story.read_board")
						if is_board
						else tr("ui.story.talk").format({"name": nm})
					),
					"radius": TALK_RADIUS_M,
					"trigger": "interact",
					"marker": npc["marker"],
					"model": str(Content.get_entity(npc["id"]).get("model", "")),
				}
			)
		)
	# A taken chest stays in place, open; other found things are gone.
	var opened := []
	for d: Dictionary in GameState.content_api.discoveries_in(place):
		if d["found"] and d["kind"] != "chest":
			continue
		var anchor := view.anchor(str(d["anchor"]))
		if anchor == null:
			continue
		var e := discovery_entry(d, anchor)
		if d["found"]:
			e["opened"] = true
			opened.append(d["id"])
		entries.append(e)
	if dungeon and dungeon.inside():
		entries.append_array(dungeon.interactables())
	else:
		entries.append_array(_gates())
	view.interactables.build(entries)
	# Drawn open, then dropped from the usable things (no prompt, no plate).
	for id: String in opened:
		view.interactables.remove(id)
	_pending = ""
	_prompt_id = "-"
	_set_prompt("")
	_publish()


## Interactable of a discovery, chest or herb.
static func discovery_entry(d: Dictionary, anchor: Node3D) -> Dictionary:
	var id: String = d["id"]
	var kind := "discovery"
	var prompt := StoryText.tr_key("ui.story.examine")
	if d["kind"] == "chest":
		kind = "chest"
		prompt = StoryText.tr_key("ui.story.open_chest")
	elif id.contains("mist_herb"):
		kind = "herb"
		prompt = StoryText.tr_key("ui.story.pick")
	var action := id + ".action"
	if TranslationServer.translate(action) != action:
		prompt = StoryText.tr_key(action)
	var zone: bool = d["trigger"] == "zone"
	return {
		"id": id,
		"kind": kind,
		"anchor": anchor,
		"name": Content.display_name(id),
		"prompt": prompt,
		"radius": ZONE_RADIUS_M if zone else USE_RADIUS_M,
		"trigger": d["trigger"],
		"marker": "",
		"model": "",
	}


## Postern of a dungeon (exits marked « interact »).
func _gates() -> Array:
	var out := []
	for area: Area3D in view.interact_exits():
		var to := str(area.get_meta("to", ""))
		var anchor := view.anchor(str(area.get_meta("anchor", "")))
		(
			out
			. append(
				{
					"id": "gate:" + to,
					"kind": "gate",
					"anchor": anchor if anchor else area,
					"name": Content.display_name(to),
					"prompt": tr("ui.story.enter").format({"place": Content.display_name(to)}),
					"radius": 4.0,
					"trigger": "interact",
					"marker": "",
					"model": "",
					"target": to,
				}
			)
		)
	return out


func place_id() -> String:
	if dungeon and dungeon.inside():
		return str(GameState.summary()["dungeon"])
	return str(GameState.data["world"]["location_id"])


func _refresh_markers() -> void:
	if view == null or view.interactables == null or not GameState.has_game():
		return
	for npc: Dictionary in GameState.content_api.npcs_here():
		if view.interactables.has(npc["id"]):
			if view.interactables.marker_of(npc["id"]) != npc["marker"]:
				view.interactables.set_marker(npc["id"], npc["marker"])


# --- Every frame ---------------------------------------------------------------------


func _process(delta: float) -> void:
	if view == null or view.player == null or view.interactables == null:
		return
	if _hold_id != "":
		_hold_tick(delta)
	_check_elapsed += delta
	if _check_elapsed < 0.1:
		return
	_check_elapsed = 0.0
	if busy or view.player.combat_driven:
		_set_prompt("")
		return
	var pos := view.player.global_position
	for id: String in view.interactables.zones_at(pos):
		use(id)
		return
	var near := view.interactables.nearest(pos)
	_set_prompt(str(near.get("id", "")))
	if _pending != "" and near.get("id", "") == _pending:
		var id := _pending
		_pending = ""
		view.player.stop()
		use(id)
	_publish()


func _set_prompt(id: String) -> void:
	if id == _prompt_id:
		return
	_prompt_id = id
	var e := view.interactables.entry(id) if id != "" else {}
	UiProbe.world["interact_target"] = id
	prompt_changed.emit(str(e.get("prompt", "")))


## For the E2E runs: what is near and where it is on screen.
func _publish() -> void:
	if view.rig == null:
		return
	var to_screen := view.get_viewport().get_screen_transform()
	var out := {}
	var pts := view.interactables.screen_points(view.rig.camera)
	for id: String in pts:
		var s: Vector2 = to_screen * pts[id]
		out[id] = {
			"x": s.x,
			"y": s.y,
			"kind": view.interactables.entry(id)["kind"],
			"marker": view.interactables.marker_of(id),
			"dist": view.interactables.position_of(id).distance_to(view.player.global_position),
		}
	UiProbe.world["interactables"] = out


# --- Using things ----------------------------------------------------------------------


## E or the prompt button: uses what is in reach.
func interact() -> bool:
	if busy or _prompt_id == "":
		return false
	use(_prompt_id)
	return true


## Click or tap: on a thing in reach, use it; further away, walk there first.
func click(screen_pos: Vector2) -> bool:
	if busy or view.interactables == null:
		return false
	var id := view.interactables.at_screen(view.rig.camera, screen_pos)
	if id == "":
		return false
	if id == _prompt_id:
		use(id)
		return true
	_pending = id
	var path := view.path_to(view.interactables.position_of(id))
	if path.size() > 1:
		view.player.follow_path(path)
	else:
		view.player.move_to(view.interactables.position_of(id))
	return true


func use(id: String) -> void:
	var e := view.interactables.entry(id)
	if e.is_empty():
		return
	match str(e["kind"]):
		"npc", "board":
			talk(id)
		"discovery", "chest", "herb":
			_take(id, e)
		"gate":
			if dungeon:
				dungeon.enter(str(e["target"]))
		"fountain", "campfire":
			if dungeon:
				dungeon.use(str(e["kind"]))


# --- Dialogues -------------------------------------------------------------------------


## Talks to an NPC: lines, then finish_talk (quest offered or handed in),
## the hand-in card, the next dialogue, the service panel.
func talk(npc_id: String) -> void:
	var t := GameState.content_api.talk(npc_id)
	if not t["ok"]:
		host.call("show_toast", GameState.reason_text(t), true)
		return
	var offer := str(t.get("offers", ""))
	if offer != "" and GameState.content_api.quest_state(offer) != "available":
		offer = ""
	UiProbe.world["dialogue"] = t["dialogue"]
	set_busy(true)
	view.interactables.set_talking(npc_id, true)
	var d := DialogueOverlay.open(host, t["lines"], offer)
	d.finished.connect(func(_skipped: bool) -> void: _after_talk(npc_id, t))


func _after_talk(npc_id: String, t: Dictionary) -> void:
	var r := GameState.content_api.finish_talk(npc_id, str(t["dialogue"]))
	UiProbe.world["dialogue"] = ""
	view.interactables.set_talking(npc_id, false)
	if not r["ok"]:
		set_busy(false)
		host.call("show_toast", GameState.reason_text(r), true)
		return
	SaveService.save_now()
	var then := func() -> void: _after_hand_in(npc_id, t, r)
	if str(r.get("turned_in", "")) != "":
		var card := DialogueOverlay.card(
			host,
			tr("ui.quest.turned_in").format({"quest": StoryText.quest_name(r["turned_in"])}),
			StoryText.rewards_text(r.get("rewards", {}))
		)
		card.finished.connect(func(_s: bool) -> void: then.call())
	else:
		then.call()


func _after_hand_in(npc_id: String, t: Dictionary, r: Dictionary) -> void:
	if str(r.get("turned_in", "")) == "quest.main_04":
		play_cards("epilogue", func() -> void: _after_hand_in(npc_id, t, {}))
		return
	if str(r.get("next_dialogue", "")) != "":
		var next := GameState.content_api.talk(npc_id)
		if next["ok"] and next["dialogue"] == r["next_dialogue"]:
			set_busy(false)
			talk(npc_id)
			return
	set_busy(false)
	if t.get("opens_panel", false) and PANELS.has(str(t["role"])):
		var screen: String = PANELS[str(t["role"])]
		var params := {"tab": "contracts"} if screen == "journal" else {}
		Router.go_to(screen, params)


## Lines that are not an NPC's (Fern, Morvaine, the bell). `subtitle`: no
## input, they fade on their own and the world goes on.
func play_lines(lines: Array, subtitle: bool, done: Callable = Callable()) -> void:
	if lines.is_empty():
		if done.is_valid():
			done.call()
		return
	if not subtitle:
		set_busy(true)
	var d := DialogueOverlay.open(host, lines, "", subtitle)
	d.finished.connect(
		func(_s: bool) -> void:
			if not subtitle:
				set_busy(false)
			if done.is_valid():
				done.call()
	)


func play_dialogue(dialogue_id: String, subtitle: bool, done: Callable = Callable()) -> void:
	play_lines(StoryText.dialogue_lines(dialogue_id), subtitle, done)


## Intro or epilogue cards over the world.
func play_cards(set_name: String, done: Callable = Callable()) -> void:
	set_busy(true)
	var c := StoryCards.open(host, set_name)
	c.finished.connect(
		func(_s: bool) -> void:
			set_busy(false)
			if done.is_valid():
				done.call()
	)


## Fern's line when a place is entered for the first time.
func first_visit(place: String) -> void:
	if FIRST_VISIT_LINES.has(place):
		play_dialogue(FIRST_VISIT_LINES[place], true)


func set_busy(value: bool) -> void:
	busy = value
	if view and view.player:
		view.player.stop()
		view.player.set_physics_process(not value)
		view.set_physics_process(not value)


# --- Discoveries, chests, herbs ----------------------------------------------------


func _take(id: String, e: Dictionary) -> void:
	var check := GameState.content_api.discovery_check(id)
	if not check["ok"]:
		host.call("show_toast", GameState.reason_text(check), true)
		return
	if e["trigger"] == "interact_hold":
		_hold_id = id
		_hold_left = HOLD_S
		set_busy(true)
		host.call("show_toast", tr("ui.story.holding").format({"action": e["prompt"]}))
		return
	_do_take(id)


func _hold_tick(delta: float) -> void:
	_hold_left -= delta
	if _hold_left > 0.0:
		return
	var id := _hold_id
	_hold_id = ""
	set_busy(false)
	_do_take(id)


func _do_take(id: String) -> void:
	var r := GameState.content_api.take_discovery(id)
	if not r["ok"]:
		host.call("show_toast", GameState.reason_text(r), true)
		return
	view.interactables.remove(id)
	_prompt_id = ""
	prompt_changed.emit("")
	var e: Dictionary = r["event"]
	var found: Array = UiProbe.world.get("discoveries_found", [])
	found.append(id)
	UiProbe.world["discoveries_found"] = found
	if Content.get_entity(id).get("kind", "") == "chest":
		var text := tr("ui.discovery.chest_opened")
		var loot := StoryText.rewards_text(e)
		host.call("show_toast", text if loot == "" else text + tr("ui.common.separator") + loot)
	var notes := []
	for line: Dictionary in e.get("lines", []):
		notes.append(GameState.reason_text(line))
	if not notes.is_empty():
		host.call("show_toast", tr("ui.common.separator").join(notes))
	# The lore of the place as a subtitle, then Fern's line if she has one.
	var lines := []
	var lore := id + ".lore"
	if TranslationServer.translate(lore) != lore:
		lines.append({"speaker": "", "key": lore})
	var fern := "dialogue.fern_" + id.get_slice(".", 1)
	if Content.has_entity(fern):
		lines.append_array(StoryText.dialogue_lines(fern))
	play_lines(lines, true)
	SaveService.save_now()


# --- Test channel ----------------------------------------------------------------------


## Test channel: puts Fern on the first discovery of the place not found yet
## (zone ones first: they are taken on arrival).
func test_go_to_discovery() -> void:
	var best := ""
	for id: String in view.interactables.ids():
		var e := view.interactables.entry(id)
		if e["kind"] != "discovery":
			continue
		if (
			best == ""
			or (e["trigger"] == "zone" and view.interactables.entry(best)["trigger"] != "zone")
		):
			best = id
	if best != "":
		view.teleport(view.interactables.position_of(best) + Vector3(0.5, 0.2, 0.5))
