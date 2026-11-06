class_name StoryCards
extends Control
## Story cards (docs/content/dialogues.md §2, §9.3): one sentence per card on
## a dark veil, « Suivant » and « Passer » always visible (GDD §16.1).

signal finished(skipped: bool)

## "intro" or "epilogue": its cards are story.<set>.card_01..03.
var card_set := "intro"
var _keys: Array[String] = []
var _index := -1
var _text: Label
var _next: Button
var _done := false


static func open(host: Control, set_name: String) -> StoryCards:
	var c := StoryCards.new()
	c.card_set = set_name
	host.add_child(c)
	return c


static func keys_of(set_name: String) -> Array[String]:
	var out: Array[String] = []
	for i in range(1, 10):
		var key := "story.%s.card_%02d" % [set_name, i]
		if TranslationServer.translate(key) == key:
			break
		out.append(key)
	return out


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_keys = keys_of(card_set)
	var veil := ColorRect.new()
	veil.color = UiTokens.NIGHT["surface_alt"]
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := Kit.vbox(UiTokens.SPACE["xxl"])
	center.add_child(col)
	_text = Kit.label("", "TitleLabel", true)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.add_theme_color_override("font_color", UiTokens.NIGHT["ink"])
	_text.custom_minimum_size = Vector2(minf(720.0, get_viewport_rect().size.x - 48.0), 0)
	UiProbe.register("story.card", _text)
	col.add_child(_text)
	var row := Kit.hbox()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var skip := Kit.button(tr("ui.dialogue.skip"), false, "story.skip")
	skip.add_theme_color_override("font_color", UiTokens.NIGHT["ink"])
	skip.custom_minimum_size.y = UiTokens.at_least_css(UiTokens.TOUCH_TARGET)
	skip.pressed.connect(_finish.bind(true))
	row.add_child(skip)
	_next = Kit.button(tr("ui.dialogue.next"), true, "story.next")
	_next.custom_minimum_size.y = UiTokens.at_least_css(UiTokens.TOUCH_TARGET)
	_next.pressed.connect(_advance)
	row.add_child(_next)
	col.add_child(row)
	UiProbe.world["story_cards"] = card_set
	_advance()
	_next.call_deferred("grab_focus")


func _exit_tree() -> void:
	UiProbe.world["story_cards"] = ""


func _advance() -> void:
	_index += 1
	if _index >= _keys.size():
		_finish(false)
		return
	_text.text = tr(_keys[_index])
	UiProbe.note(_text.text)
	if _index == _keys.size() - 1:
		_next.text = tr("ui.dialogue.close")


func _finish(skipped: bool) -> void:
	if _done:
		return
	_done = true
	finished.emit(skipped)
	queue_free()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			_advance()


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish(true)
	elif event.is_action_pressed("interact") or event.is_action_pressed("combat_pause"):
		get_viewport().set_input_as_handled()
		_advance()
