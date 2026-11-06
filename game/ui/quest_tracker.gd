class_name QuestTracker
extends PanelContainer
## Compact quest tracker of the explore HUD (DESIGN.md « suivi de quête »):
## the tracked quest and the objectives of its current step with their
## progress. Pressing it opens the journal. Rebuilt when GameState changes.

signal open_requested

var _title: Label
var _lines: VBoxContainer
var _queued := false


func _ready() -> void:
	theme_type_variation = "CardPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := Kit.vbox(UiTokens.SPACE["xs"])
	add_child(col)
	_title = Kit.label("", "SubheadingLabel", true)
	UiProbe.register("hud.quest", _title)
	col.add_child(_title)
	_lines = Kit.vbox(UiTokens.SPACE["xs"])
	col.add_child(_lines)
	GameState.changed.connect(_queue)
	refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			open_requested.emit()


func _queue() -> void:
	if not _queued:
		_queued = true
		call_deferred("refresh")


func refresh() -> void:
	_queued = false
	if not is_inside_tree():
		return
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	var entry := tracked_entry()
	visible = not entry.is_empty()
	if entry.is_empty():
		_title.text = ""
		return
	_title.text = StoryText.quest_name(entry["id"])
	var width := 260.0
	_title.custom_minimum_size = Vector2(width, 0)
	if entry["state"] == "completed":
		var giver := StoryText.speaker_name(str(entry["giver"]))
		var back := Kit.label(tr("ui.journal.return_to").format({"npc": giver}), "MutedLabel", true)
		back.custom_minimum_size = Vector2(width, 0)
		UiProbe.register("hud.quest.return", back)
		_lines.add_child(back)
		return
	for o: Dictionary in entry["objectives"]:
		if not o["visible"] or int(o["step"]) != int(entry["step"]):
			continue
		var line := Kit.label(objective_line(o), "MutedLabel", true)
		line.custom_minimum_size = Vector2(width, 0)
		if o["done"]:
			line.add_theme_color_override("font_color", UiTokens.DAY["success"].darkened(0.25))
		UiProbe.register("hud.quest.objective." + str(o["id"]), line)
		_lines.add_child(line)


## « ✓ »-free objective line: text, then « fait » when done.
static func objective_line(o: Dictionary) -> String:
	var text := StoryText.objective_text(o)
	return (
		StoryText.tr_key("ui.journal.objective_done").format({"objective": text})
		if o["done"]
		else text
	)


## The log entry of the tracked quest ({} if none).
static func tracked_entry() -> Dictionary:
	if not GameState.has_game():
		return {}
	var id := GameState.content_api.tracked_quest()
	if id == "":
		return {}
	for entry: Dictionary in GameState.content_api.quest_log():
		if entry["id"] == id:
			return entry
	return {}
