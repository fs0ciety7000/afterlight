extends Screen
## Settings, stored per device. Three tabs: display (text size, graphics
## quality, reduced motion), sound (one volume per audio bus) and controls
## (keyboard and gamepad rebinding with conflict swap and reset, ROADMAP 7.6).

const TABS := ["general", "sound", "controls"]

var _tab := "general"
var _status: Label
var _card: PanelContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _tab_buttons := {}
var _bind_buttons := {}
var _capture_action := ""
var _capture_slot := ""


func setup(params: Dictionary) -> void:
	var tab := str(params.get("tab", "general"))
	_tab = tab if tab in TABS else "general"


func _ready() -> void:
	add_backdrop(0.7)
	_card = Kit.panel()
	_card.custom_minimum_size = Vector2(minf(720, get_viewport_rect().size.x - 32), 0)
	_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(Kit.margin(_card, is_narrow()))
	var col := Kit.vbox(UiTokens.SPACE["lg"])
	_card.add_child(col)
	col.add_child(Kit.label(tr("ui.settings.title"), "TitleLabel"))

	var tabs := Kit.hbox(UiTokens.SPACE["sm"])
	for tab: String in TABS:
		var b := Kit.button(tr("ui.settings.tab." + tab), false, "settings.tab." + tab)
		b.toggle_mode = true
		b.pressed.connect(func() -> void: _show_tab(tab))
		_tab_buttons[tab] = b
		tabs.add_child(b)
	col.add_child(tabs)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body = Kit.vbox(UiTokens.SPACE["lg"])
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	col.add_child(_scroll)

	_status = Kit.label("", "MutedLabel", true)
	UiProbe.register("settings.status", _status)
	col.add_child(_status)
	var back := Kit.button(tr("ui.menu.back"), true, "settings.back")
	back.pressed.connect(func() -> void: Router.back())
	col.add_child(back)
	_show_tab(_tab)


func grab_initial_focus() -> void:
	(_tab_buttons[_tab] as Control).grab_focus()


func _show_tab(tab: String) -> void:
	_cancel_capture()
	_tab = tab
	for t: String in _tab_buttons:
		var b: Button = _tab_buttons[t]
		b.set_pressed_no_signal(t == tab)
		b.theme_type_variation = "PrimaryButton" if t == tab else "SecondaryButton"
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_bind_buttons.clear()
	# The display tab is short: the card fits its content. The controls and
	# sound lists scroll inside a card as tall as the screen.
	var long := tab in ["controls", "sound"]
	_scroll.vertical_scroll_mode = (
		ScrollContainer.SCROLL_MODE_AUTO if long else ScrollContainer.SCROLL_MODE_DISABLED
	)
	_card.size_flags_vertical = Control.SIZE_FILL if long else Control.SIZE_SHRINK_CENTER
	if tab == "controls":
		_build_controls()
	elif tab == "sound":
		_build_sound()
	else:
		_build_general()


func _build_general() -> void:
	var size_pick := _option_row("ui.settings.text_size", "settings.text_size")
	for i in UiTokens.TEXT_SCALES.size():
		size_pick.add_item("%d %%" % roundi(UiTokens.TEXT_SCALES[i] * 100), i)
	size_pick.select(Settings.text_scale_index)
	size_pick.item_selected.connect(
		func(index: int) -> void:
			Settings.set_text_scale_index(index)
			flash(_status, tr("ui.settings.saved"))
	)

	var quality_pick := _option_row("ui.settings.graphics_quality", "settings.graphics_quality")
	for key in [
		"ui.settings.quality_low", "ui.settings.quality_medium", "ui.settings.quality_high"
	]:
		quality_pick.add_item(tr(key))
	quality_pick.select(Settings.graphics_quality)
	quality_pick.item_selected.connect(
		func(index: int) -> void:
			Settings.set_graphics_quality(index)
			flash(_status, tr("ui.settings.saved"))
	)

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
	_body.add_child(motion)
	_body.add_child(Kit.label(tr("ui.settings.reduce_motion_hint"), "MutedLabel", true))


## One slider per bus (0-100 %), applied live and saved by Settings.
func _build_sound() -> void:
	for bus: String in Settings.VOLUME_BUSES:
		var row := Kit.hbox()
		var label := Kit.label(tr("ui.settings.volume." + bus.to_lower()), "", true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size = Vector2(120, 0)
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 5
		slider.value = roundi(Settings.volume(bus) * 100.0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size = Vector2(160, UiTokens.TOUCH_TARGET)
		slider.focus_mode = Control.FOCUS_ALL
		row.add_child(slider)
		var pct := Kit.label(_pct(slider.value), "MutedLabel")
		pct.custom_minimum_size = Vector2(56, 0)
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pct)
		slider.value_changed.connect(
			func(v: float) -> void:
				pct.text = _pct(v)
				Settings.set_volume(bus, v / 100.0)
		)
		UiProbe.register("settings.volume." + bus.to_lower(), slider)
		_body.add_child(row)
	_body.add_child(Kit.label(tr("ui.settings.sound_hint"), "MutedLabel", true))


func _pct(value: float) -> String:
	return tr("ui.settings.volume_pct").format({"pct": roundi(value)})


## A labelled row with a picker; returns the picker.
func _option_row(label_key: String, probe_id: String) -> OptionButton:
	var row := Kit.hbox()
	var label := Kit.label(tr(label_key), "", true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(160, UiTokens.TOUCH_TARGET)
	UiProbe.register(probe_id, pick)
	row.add_child(pick)
	_body.add_child(row)
	return pick


func _build_controls() -> void:
	_body.add_child(Kit.label(tr("ui.controls.hint"), "MutedLabel", true))
	var head := Kit.hbox()
	for key in ["ui.controls.action", "ui.controls.keyboard", "ui.controls.gamepad"]:
		var h := Kit.label(tr(key), "MutedLabel", true)
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(h)
	_body.add_child(head)
	for action: String in InputActions.REMAPPABLE:
		var row := Kit.hbox()
		var name_label := Kit.label(tr("ui.controls.action." + action), "", true)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.custom_minimum_size = Vector2(120, 0)
		row.add_child(name_label)
		for slot in ["key", "pad"]:
			var b := Kit.button("", false, "controls.%s.%s" % [slot, action])
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size = Vector2(120, UiTokens.TOUCH_TARGET)
			b.pressed.connect(_start_capture.bind(action, slot))
			_bind_buttons["%s/%s" % [slot, action]] = b
			row.add_child(b)
		_body.add_child(row)
	var reset := Kit.button(tr("ui.controls.reset"), false, "controls.reset")
	reset.pressed.connect(_on_reset)
	_body.add_child(reset)
	_refresh_bindings()


func _refresh_bindings() -> void:
	for id: String in _bind_buttons:
		var slot := id.get_slice("/", 0)
		var action := id.get_slice("/", 1)
		var b: Button = _bind_buttons[id]
		if action == _capture_action and slot == _capture_slot:
			b.text = tr("ui.controls.press_key" if slot == "key" else "ui.controls.press_button")
		else:
			var text := InputActions.label(action, slot)
			b.text = text if text != "" else tr("ui.controls.unbound")


func _start_capture(action: String, slot: String) -> void:
	_capture_action = action
	_capture_slot = slot
	_refresh_bindings()


func _cancel_capture() -> void:
	_capture_action = ""
	_capture_slot = ""


## Takes the next key or gamepad input while a binding waits for one. Runs
## before the GUI so Space, Enter or A are captured, not pressed.
func _input(event: InputEvent) -> void:
	if _capture_action == "" or not InputActions.is_bindable(event):
		return
	get_viewport().set_input_as_handled()
	if InputActions.is_reserved(event):
		_cancel_capture()
		_refresh_bindings()
		flash(_status, tr("ui.controls.cancelled"))
		return
	if InputActions.slot_of(event) != _capture_slot:
		return
	var action := _capture_action
	_cancel_capture()
	var result := InputActions.rebind(action, event)
	_refresh_bindings()
	if not result["ok"]:
		flash(_status, tr(str(result["error"])), true)
		return
	Settings.set_bindings(InputActions.overrides())
	var input := InputActions.label(action, InputActions.slot_of(event))
	var other := str(result["swapped_with"])
	if other != "":
		flash(
			_status,
			(
				tr("ui.controls.swapped")
				. format(
					{
						"input": input,
						"action": tr("ui.controls.action." + action),
						"other": tr("ui.controls.action." + other),
					}
				)
			)
		)
	else:
		flash(
			_status,
			tr("ui.controls.saved").format(
				{"input": input, "action": tr("ui.controls.action." + action)}
			)
		)


func _on_reset() -> void:
	_cancel_capture()
	InputActions.reset_all()
	Settings.set_bindings({})
	_refresh_bindings()
	flash(_status, tr("ui.controls.reset_done"))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Router.back()
