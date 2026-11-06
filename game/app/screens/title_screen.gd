extends Screen
## Title: continue, new game, import, settings.

var _status: Label
var _continue: Button
var _boot: Dictionary = {}


func setup(params: Dictionary) -> void:
	_boot = params.get("boot", {})


func _ready() -> void:
	add_backdrop(0.0)
	var card := Kit.panel()
	card.custom_minimum_size = Vector2(440 if not is_narrow() else 360, 0)
	var col := Kit.vbox(UiTokens.SPACE["lg"])
	card.add_child(col)

	col.add_child(Kit.label(tr("ui.game.title"), "DisplayLabel"))
	col.add_child(Kit.label(tr("ui.game.tagline"), "LeadLabel", true))
	col.add_child(HSeparator.new())

	var has_save: bool = SaveService.store.has_main() and _boot.get("status", "") != "corrupt"
	_continue = Kit.button(tr("ui.menu.continue"), true, "title.continue")
	_continue.visible = has_save
	_continue.pressed.connect(_on_continue)
	col.add_child(_continue)
	if has_save and GameState.has_game():
		var s := GameState.summary()
		var line := (
			tr("ui.title.continue_summary")
			. format(
				{
					"name": Content.display_name(s["leader"]),
					"level": s["level"],
					"place": Content.display_name(s["location_id"]),
				}
			)
		)
		col.add_child(Kit.label(line, "MutedLabel", true))

	var new_game := Kit.button(tr("ui.menu.new_game"), not has_save, "title.new_game")
	new_game.pressed.connect(_on_new_game)
	col.add_child(new_game)
	var import := Kit.button(tr("ui.menu.import"), false, "title.import")
	import.pressed.connect(func() -> void: SaveService.request_import(self))
	col.add_child(import)
	var settings := Kit.button(tr("ui.menu.settings"), false, "title.settings")
	settings.pressed.connect(func() -> void: Router.go_to("settings"))
	col.add_child(settings)

	_status = Kit.label("", "MutedLabel", true)
	col.add_child(_status)
	col.add_child(Kit.label(tr("ui.game.disclaimer"), "MutedLabel", true))

	var holder := MarginContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var side: int = UiTokens.SPACE["huge"] if not is_narrow() else UiTokens.SPACE["lg"]
	holder.add_theme_constant_override("margin_left", side)
	holder.add_theme_constant_override("margin_top", UiTokens.SPACE["xl"])
	holder.add_theme_constant_override("margin_bottom", UiTokens.SPACE["xl"])
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(card)
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(center)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(scroll)
	add_child(holder)

	SaveFlows.wire_import(
		self, _status, func() -> void: Router.go_to(OfflineSummaryScreen.entry_screen())
	)


func grab_initial_focus() -> void:
	if _continue.visible:
		_continue.grab_focus()
	else:
		(UiProbe._controls["title.new_game"] as Control).grab_focus()


func _on_continue() -> void:
	if not GameState.has_game():
		var r := SaveService.boot_read()
		if r["status"] != "ok":
			Router.go_to("save_recovery", {"boot": r})
			return
		GameState.adopt(r["decoded"]["state"])
	# A summary of the absence waits for its claim before the world.
	Router.go_to(OfflineSummaryScreen.entry_screen())


func _on_new_game() -> void:
	if SaveService.store.has_main():
		var d := ConfirmDialog.open(
			self,
			tr("ui.new_game.confirm_title"),
			tr("ui.new_game.confirm_body"),
			"new_game_confirm"
		)
		d.confirmed.connect(_start_new_game)
	else:
		_start_new_game()


func _start_new_game() -> void:
	GameState.start_new(Content.start())
	SaveService.save_now()
	# The intro cards play over Aubelin (docs/content/dialogues.md §2).
	Router.go_to("explore", {"intro": true})
