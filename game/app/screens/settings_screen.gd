extends Screen
## Settings: text size and reduced motion, stored per device.

var _status: Label


func _ready() -> void:
	add_backdrop(0.7)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := Kit.panel()
	card.custom_minimum_size = Vector2(minf(560, get_viewport_rect().size.x - 32), 0)
	center.add_child(card)
	var col := Kit.vbox(UiTokens.SPACE["lg"])
	card.add_child(col)
	col.add_child(Kit.label(tr("ui.settings.title"), "TitleLabel"))

	var size_row := Kit.hbox()
	var size_label := Kit.label(tr("ui.settings.text_size"))
	size_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(size_label)
	var size_pick := OptionButton.new()
	size_pick.custom_minimum_size = Vector2(160, UiTokens.TOUCH_TARGET)
	for i in UiTokens.TEXT_SCALES.size():
		size_pick.add_item("%d %%" % roundi(UiTokens.TEXT_SCALES[i] * 100), i)
	size_pick.select(Settings.text_scale_index)
	size_pick.item_selected.connect(
		func(index: int) -> void:
			Settings.set_text_scale_index(index)
			flash(_status, tr("ui.settings.saved"))
	)
	UiProbe.register("settings.text_size", size_pick)
	size_row.add_child(size_pick)
	col.add_child(size_row)

	var motion := CheckButton.new()
	motion.text = tr("ui.settings.reduce_motion")
	motion.button_pressed = Settings.reduce_motion
	motion.custom_minimum_size = Vector2(0, UiTokens.TOUCH_TARGET)
	motion.toggled.connect(
		func(on: bool) -> void:
			Settings.set_reduce_motion(on)
			flash(_status, tr("ui.settings.saved"))
	)
	UiProbe.register("settings.reduce_motion", motion)
	col.add_child(motion)
	col.add_child(Kit.label(tr("ui.settings.reduce_motion_hint"), "MutedLabel", true))

	_status = Kit.label("", "MutedLabel")
	col.add_child(_status)
	var back := Kit.button(tr("ui.menu.back"), true, "settings.back")
	back.pressed.connect(func() -> void: Router.back())
	col.add_child(back)


func grab_initial_focus() -> void:
	var b: Control = UiProbe._controls.get("settings.back")
	if b:
		b.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Router.back()
