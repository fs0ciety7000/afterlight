class_name GameMenu
extends Control
## Pause menu over the world: save, export, import, settings, main menu.

signal closed

var _save_status: Label
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := Kit.panel("ScrimPanel")
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := Kit.panel()
	card.custom_minimum_size = Vector2(minf(440.0, get_viewport_rect().size.x - 32.0), 0)
	center.add_child(card)
	var col := Kit.vbox()
	card.add_child(col)
	col.add_child(Kit.label(tr("ui.menu.pause_title"), "TitleLabel"))
	var resume := Kit.button(tr("ui.menu.resume"), true, "menu.resume")
	resume.pressed.connect(close)
	col.add_child(resume)
	var save := Kit.button(tr("ui.camp.save"), false, "menu.save")
	save.pressed.connect(func() -> void: SaveService.save_now())
	col.add_child(save)
	_save_status = Kit.label("", "MutedLabel", true)
	UiProbe.register("menu.save_status", _save_status)
	col.add_child(_save_status)
	var export := Kit.button(tr("ui.camp.export"), false, "menu.export")
	export.pressed.connect(
		func() -> void: SaveFlows._show(_status, SaveService.export_current(), false)
	)
	col.add_child(export)
	var import := Kit.button(tr("ui.camp.import"), false, "menu.import")
	import.pressed.connect(func() -> void: SaveService.request_import(self))
	col.add_child(import)
	var settings := Kit.button(tr("ui.menu.settings"), false, "menu.settings")
	settings.pressed.connect(func() -> void: Router.go_to("settings"))
	col.add_child(settings)
	var title := Kit.button(tr("ui.menu.main_menu"), false, "menu.main_menu")
	title.pressed.connect(func() -> void: Router.go_to("title"))
	col.add_child(title)
	col.add_child(Kit.label(tr("ui.save.autosave_hint"), "MutedLabel", true))
	_status = Kit.label("", "MutedLabel", true)
	col.add_child(_status)
	SaveService.saved.connect(_refresh)
	SaveService.save_failed.connect(func(_r: String) -> void: _refresh())
	SaveFlows.wire_import(self, _status, func() -> void: Router.go_to("explore", {}, false))
	_refresh()
	resume.call_deferred("grab_focus")


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _refresh(_at: int = 0) -> void:
	if SaveService.last_error != "":
		_save_status.text = tr("ui.save.status_failed").format({"reason": SaveService.last_error})
		_save_status.theme_type_variation = "ErrorLabel"
	elif SaveService.last_saved_at > 0:
		var time := Kit.format_time(SaveService.last_saved_at)
		_save_status.text = tr("ui.save.status_at").format({"time": time})
		_save_status.theme_type_variation = "MutedLabel"
	else:
		_save_status.text = tr("ui.save.status_never")
