class_name ConfirmDialog
extends Control
## Modal confirmation drawn with the game theme (no OS dialog).

signal confirmed
signal cancelled


static func open(
	host: Control, title: String, body: String, probe_prefix: String = "confirm"
) -> ConfirmDialog:
	var d := ConfirmDialog.new()
	host.add_child(d)
	d._build(host, title, body, probe_prefix)
	return d


func _build(host: Control, title: String, body: String, probe_prefix: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := Kit.panel("ScrimPanel")
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := Kit.panel()
	var width := minf(520.0, host.get_viewport_rect().size.x - 32.0)
	card.custom_minimum_size = Vector2(width, 0)
	center.add_child(card)
	var col := Kit.vbox(UiTokens.SPACE["lg"])
	card.add_child(col)
	col.add_child(Kit.label(title, "HeadingLabel", true))
	var text := Kit.label(body, "", true)
	text.custom_minimum_size = Vector2(width - 48.0, 0)
	col.add_child(text)
	var row := Kit.hbox()
	row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(row)
	var cancel := Kit.button(tr("ui.confirm.cancel"), false, probe_prefix + ".cancel")
	var ok := Kit.button(tr("ui.confirm.yes"), true, probe_prefix + ".ok")
	row.add_child(cancel)
	row.add_child(ok)
	cancel.pressed.connect(func() -> void: _close(false))
	ok.pressed.connect(func() -> void: _close(true))
	cancel.call_deferred("grab_focus")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close(false)


func _close(ok: bool) -> void:
	if ok:
		confirmed.emit()
	else:
		cancelled.emit()
	queue_free()
