class_name SaveFlows
extends RefCounted
## Import confirmation shared by the title screen and the game menu.


## Connects SaveService import signals for the lifetime of `host`.
## `on_imported` runs after a confirmed import; `status` shows messages.
static func wire_import(host: Control, status: Label, on_imported: Callable) -> void:
	var ready_cb := func(decoded: Dictionary) -> void:
		var state: Dictionary = decoded["state"]
		var leader: String = state["party"][0]
		var body := (
			host
			. tr("ui.import.confirm_body")
			. format(
				{
					"name": Content.display_name(leader),
					"level": state["characters"][leader]["level"],
					"date": Kit.format_date(decoded["saved_at"]),
				}
			)
		)
		var d := ConfirmDialog.open(
			host, host.tr("ui.import.confirm_title"), body, "import_confirm"
		)
		d.confirmed.connect(
			func() -> void:
				SaveService.apply_import(decoded)
				on_imported.call()
		)
		d.cancelled.connect(func() -> void: _show(status, host.tr("ui.import.cancelled"), false))
	var failed_cb := func(code: String) -> void:
		if code == "cancelled":
			_show(status, host.tr("ui.import.cancelled"), false)
		else:
			var reason := host.tr("error.save." + code)
			_show(status, host.tr("ui.import.failed").format({"reason": reason}), true)
	SaveService.import_ready.connect(ready_cb)
	SaveService.import_failed.connect(failed_cb)
	host.tree_exiting.connect(
		func() -> void:
			SaveService.import_ready.disconnect(ready_cb)
			SaveService.import_failed.disconnect(failed_cb)
	)


static func _show(status: Label, message: String, is_error: bool) -> void:
	status.text = message
	status.theme_type_variation = "ErrorLabel" if is_error else "MutedLabel"
	UiProbe.note(message)
