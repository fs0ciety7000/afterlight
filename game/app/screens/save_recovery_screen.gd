extends Screen
## Shown when the save cannot be loaded. Nothing is erased without consent:
## the damaged file is already copied to quarantine before this screen opens.

var _boot: Dictionary = {}
var _status: Label


func setup(params: Dictionary) -> void:
	_boot = params.get("boot", {})


func _ready() -> void:
	add_backdrop(0.8)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := Kit.panel()
	card.custom_minimum_size = Vector2(minf(640, get_viewport_rect().size.x - 32), 0)
	center.add_child(card)
	var col := Kit.vbox(UiTokens.SPACE["lg"])
	card.add_child(col)
	var title := Kit.label(tr("ui.recovery.title"), "TitleLabel")
	UiProbe.register("recovery.title", title)
	col.add_child(title)
	var code: String = _boot.get("decoded", {}).get("error", "not_json")
	col.add_child(
		Kit.label(tr("ui.recovery.body").format({"reason": tr("error.save." + code)}), "", true)
	)

	var backup: Dictionary = _boot.get("backup", {})
	if not backup.is_empty() and backup["ok"]:
		var state: Dictionary = backup["state"]
		var leader: String = state["party"][0]
		var restore := Kit.button(tr("ui.recovery.restore"), true, "recovery.restore")
		restore.pressed.connect(_on_restore)
		col.add_child(restore)
		(
			col
			. add_child(
				(
					Kit
					. label(
						(
							tr("ui.recovery.restore_detail")
							. format(
								{
									"date": Kit.format_date(backup["saved_at"]),
									"name": Content.display_name(leader),
									"level": state["characters"][leader]["level"],
								}
							)
						),
						"MutedLabel",
						true
					)
				)
			)
		)
	else:
		col.add_child(Kit.label(tr("ui.recovery.no_backup"), "MutedLabel", true))

	var export := Kit.button(tr("ui.recovery.export"), false, "recovery.export")
	export.pressed.connect(func() -> void: flash(_status, SaveService.export_damaged()))
	col.add_child(export)
	var new_game := Kit.button(tr("ui.recovery.new_game"), false, "recovery.new_game")
	new_game.pressed.connect(_on_new_game)
	col.add_child(new_game)
	_status = Kit.label("", "MutedLabel", true)
	col.add_child(_status)


func _on_restore() -> void:
	var r := SaveService.store.restore_backup(GameState.now_unix())
	if r["ok"]:
		GameState.adopt(r["decoded"]["state"])
		Router.go_to("camp", {}, false)
	else:
		flash(_status, r["error"], true)


func _on_new_game() -> void:
	var d := ConfirmDialog.open(
		self,
		tr("ui.new_game.confirm_title"),
		tr("ui.recovery.new_confirm_body"),
		"new_game_confirm"
	)
	d.confirmed.connect(
		func() -> void:
			GameState.start_new(Content.start())
			SaveService.save_now()
			Router.go_to("camp", {}, false)
	)
