class_name DialogueOverlay
extends Control
## Dialogue panel over the world (docs/content/dialogues.md §1): speaker and
## line at the bottom of the screen, advanced by click, tap, E, Enter or
## Space; « Passer » ends it (its effects still apply, the caller runs
## finish_talk on `finished`). Also shows the quest offer and hand-in cards,
## and short subtitles (Fern, Morvaine) that need no input.

signal finished(skipped: bool)

const SUBTITLE_S := 3.0
const MAX_WIDTH := 760.0

var _lines: Array = []
var _index := -1
var _subtitle := false
var _offer := ""
var _panel: PanelContainer
var _speaker: Label
var _text: Label
var _next: Button
var _skip: Button
var _done := false
var _timer: SceneTreeTimer


## Plays NPC or story lines [{speaker, key}]. `offer`: quest offered at the
## end (its card follows the lines). `subtitle`: no panel buttons, no input,
## each line stays SUBTITLE_S seconds.
static func open(
	host: Control, lines: Array, offer: String = "", subtitle: bool = false
) -> DialogueOverlay:
	var d := DialogueOverlay.new()
	d._lines = lines
	d._offer = offer
	d._subtitle = subtitle
	host.add_child(d)
	return d


## A card with a title, a body and one button (quest handed in, rewards).
static func card(host: Control, title: String, body: String) -> DialogueOverlay:
	var d := DialogueOverlay.new()
	host.add_child(d)
	d._show_card(title, body, d.tr("ui.dialogue.continue"))
	return d


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE if _subtitle else Control.MOUSE_FILTER_STOP
	_build()
	if not _lines.is_empty():
		_advance()
	UiProbe.world["dialogue_open"] = true


func _exit_tree() -> void:
	UiProbe.world["dialogue_open"] = false


func _build() -> void:
	_panel = Kit.panel()
	var width := minf(MAX_WIDTH, get_viewport_rect().size.x - 32.0)
	_panel.custom_minimum_size = Vector2(width, 0)
	var col := Kit.vbox(UiTokens.SPACE["sm"])
	_panel.add_child(col)
	_speaker = Kit.label("", "SubheadingLabel")
	_speaker.add_theme_color_override("font_color", UiTokens.DAY["accent"])
	UiProbe.register("dialogue.speaker", _speaker)
	col.add_child(_speaker)
	_text = Kit.label("", "LeadLabel", true)
	_text.custom_minimum_size = Vector2(width - 48.0, 0)
	UiProbe.register("dialogue.text", _text)
	col.add_child(_text)
	if not _subtitle:
		var row := Kit.hbox()
		row.alignment = BoxContainer.ALIGNMENT_END
		_skip = Kit.button(tr("ui.dialogue.skip"), false, "dialogue.skip")
		_skip.custom_minimum_size.y = UiTokens.at_least_css(UiTokens.TOUCH_TARGET)
		_skip.pressed.connect(_finish.bind(true))
		row.add_child(_skip)
		_next = Kit.button(tr("ui.dialogue.next"), true, "dialogue.next")
		_next.custom_minimum_size.y = UiTokens.at_least_css(UiTokens.TOUCH_TARGET)
		_next.pressed.connect(_advance)
		row.add_child(_next)
		col.add_child(row)
	add_child(_panel)
	var bottom := 120.0 if not _subtitle else 160.0
	_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, int(bottom)
	)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if _next:
		_next.call_deferred("grab_focus")


func _advance() -> void:
	if _done:
		return
	_index += 1
	if _index < _lines.size():
		var line: Dictionary = _lines[_index]
		_speaker.text = StoryText.speaker_name(str(line["speaker"]))
		_text.text = tr(str(line["key"]))
		UiProbe.world["dialogue_line"] = str(line["key"])
		UiProbe.note(_text.text)
		if _next:
			var last := _index == _lines.size() - 1 and _offer == ""
			_next.text = tr("ui.dialogue.close") if last else tr("ui.dialogue.next")
		if _subtitle:
			_timer = get_tree().create_timer(SUBTITLE_S)
			var t := _timer
			t.timeout.connect(
				func() -> void:
					if t == _timer and is_inside_tree():
						_advance()
			)
		return
	if _offer != "":
		var quest := _offer
		_offer = ""
		var body := tr(str(Content.get_entity(quest).get("desc_key", "")))
		var rewards := StoryText.rewards_text(GameState.content_api.quest_rewards(quest))
		if rewards != "":
			body += "\n" + tr("ui.dialogue.rewards").format({"rewards": rewards})
		_show_card(
			tr("ui.dialogue.offer").format({"quest": StoryText.quest_name(quest)}),
			body,
			tr("ui.dialogue.accept")
		)
		return
	_finish(false)


## Replaces the line by a card (offer, hand-in) with one button.
func _show_card(title: String, body: String, button_text: String) -> void:
	if _panel == null:
		_build()
	_lines = []
	_index = 0
	_speaker.text = title
	_text.text = body
	UiProbe.register("dialogue.card_title", _speaker)
	UiProbe.note(title)
	if _skip:
		_skip.visible = false
	if _next:
		_next.text = button_text
		UiProbe.register("dialogue.accept", _next)
		if _next.pressed.is_connected(_advance):
			_next.pressed.disconnect(_advance)
		_next.pressed.connect(_finish.bind(false))
		_next.call_deferred("grab_focus")


func _finish(skipped: bool) -> void:
	if _done:
		return
	_done = true
	finished.emit(skipped)
	queue_free()


func _gui_input(event: InputEvent) -> void:
	if _subtitle:
		return
	if event is InputEventMouseButton and event.pressed:
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if _next and _next.pressed.is_connected(_advance):
				_advance()


func _unhandled_input(event: InputEvent) -> void:
	if _subtitle or _done:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _skip and _skip.visible:
			_finish(true)
	elif event.is_action_pressed("interact") or event.is_action_pressed("combat_pause"):
		get_viewport().set_input_as_handled()
		_next.pressed.emit()
