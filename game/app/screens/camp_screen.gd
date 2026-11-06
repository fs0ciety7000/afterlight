extends Screen
## Camp: the hub of Milestone 1. Shows the real party, wallet and place from
## GameState, and owns manual save, export and import.

var _save_status: Label
var _status: Label
var _play_time: Label


func _ready() -> void:
	add_backdrop(0.6)
	var narrow := is_narrow()
	var root := Kit.vbox(UiTokens.SPACE["xl"])
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(root)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(Kit.margin(scroll, narrow))

	var s := GameState.summary()
	var header := Kit.panel()
	var head_col := Kit.vbox(UiTokens.SPACE["xs"])
	header.add_child(head_col)
	head_col.add_child(Kit.label(tr("ui.camp.title"), "TitleLabel"))
	var place := (
		"%s · %s" % [Content.display_name(s["location_id"]), Content.display_name(s["region_id"])]
	)
	head_col.add_child(Kit.label(place, "LeadLabel"))
	root.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 1 if narrow else 3
	grid.add_theme_constant_override("h_separation", UiTokens.SPACE["xl"])
	grid.add_theme_constant_override("v_separation", UiTokens.SPACE["xl"])
	root.add_child(grid)
	grid.add_child(_party_card())
	grid.add_child(_wallet_card())
	grid.add_child(_save_card())

	var nav := Kit.hbox()
	var settings := Kit.button(tr("ui.menu.settings"), false, "camp.settings")
	settings.pressed.connect(func() -> void: Router.go_to("settings"))
	var menu := Kit.button(tr("ui.menu.main_menu"), false, "camp.main_menu")
	menu.pressed.connect(func() -> void: Router.go_to("title"))
	nav.add_child(settings)
	nav.add_child(menu)
	root.add_child(nav)

	SaveService.saved.connect(_on_saved)
	SaveService.save_failed.connect(_on_save_failed)
	SaveService.import_ready.connect(_on_import_ready)
	SaveService.import_failed.connect(_on_import_failed)
	_refresh_save_status()


func _process(_delta: float) -> void:
	if GameState.has_game() and _play_time:
		_play_time.text = Kit.format_duration(int(GameState.data["meta"]["play_time"]))


func _card(title: String) -> Array:
	var card := Kit.panel("CardPanel")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := Kit.vbox()
	card.add_child(col)
	col.add_child(Kit.label(title, "SubheadingLabel"))
	return [card, col]


func _party_card() -> Control:
	var parts := _card(tr("ui.camp.party"))
	var col: VBoxContainer = parts[1]
	var party: Array = GameState.data["party"]
	for i in party.size():
		var id: String = party[i]
		if id == "":
			col.add_child(Kit.label(tr("ui.camp.empty_slot"), "MutedLabel"))
			continue
		var hero: Dictionary = GameState.data["characters"][id]
		var row := Kit.hbox()
		var name := Kit.label(Content.display_name(id), "LeadLabel")
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var level := Kit.label(tr("ui.camp.level").format({"level": hero["level"]}), "NumberLabel")
		UiProbe.register("camp.party.%d.level" % i, level)
		row.add_child(level)
		col.add_child(row)
		col.add_child(Kit.label(tr("ui.camp.xp").format({"xp": hero["xp"]}), "MutedLabel"))
	return parts[0]


func _wallet_card() -> Control:
	var parts := _card(tr("ui.camp.wallet"))
	var col: VBoxContainer = parts[1]
	var row := Kit.hbox()
	var gold_name := Kit.label(tr("ui.camp.gold"))
	gold_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gold_name)
	var gold := Kit.label(str(GameState.data["wallet"]["gold"]), "NumberLabel")
	UiProbe.register("camp.gold", gold)
	row.add_child(gold)
	col.add_child(row)
	var materials: Dictionary = GameState.data["wallet"]["materials"]
	for id in materials:
		var m := Kit.hbox()
		var n := Kit.label(Content.display_name(id))
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.add_child(n)
		m.add_child(Kit.label(str(materials[id]), "NumberLabel"))
		col.add_child(m)
	var time_row := Kit.hbox()
	var t := Kit.label(tr("ui.camp.play_time"))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_row.add_child(t)
	_play_time = Kit.label("", "NumberLabel")
	time_row.add_child(_play_time)
	col.add_child(time_row)
	return parts[0]


func _save_card() -> Control:
	var parts := _card(tr("ui.camp.save"))
	var col: VBoxContainer = parts[1]
	_save_status = Kit.label("", "MutedLabel", true)
	UiProbe.register("camp.save_status", _save_status)
	col.add_child(_save_status)
	var save := Kit.button(tr("ui.camp.save"), true, "camp.save")
	save.pressed.connect(func() -> void: SaveService.save_now())
	col.add_child(save)
	var export := Kit.button(tr("ui.camp.export"), false, "camp.export")
	export.pressed.connect(func() -> void: flash(_status, SaveService.export_current()))
	col.add_child(export)
	var import := Kit.button(tr("ui.camp.import"), false, "camp.import")
	import.pressed.connect(func() -> void: SaveService.request_import(self))
	col.add_child(import)
	col.add_child(Kit.label(tr("ui.save.autosave_hint"), "MutedLabel", true))
	_status = Kit.label("", "MutedLabel", true)
	col.add_child(_status)
	return parts[0]


func grab_initial_focus() -> void:
	var b: Control = UiProbe._controls.get("camp.save")
	if b:
		b.grab_focus()


func _refresh_save_status() -> void:
	if SaveService.last_error != "":
		_save_status.text = tr("ui.save.status_failed").format({"reason": SaveService.last_error})
		_save_status.theme_type_variation = "ErrorLabel"
	elif SaveService.last_saved_at > 0:
		_save_status.text = tr("ui.save.status_at").format(
			{"time": Kit.format_time(SaveService.last_saved_at)}
		)
		_save_status.theme_type_variation = "MutedLabel"
	else:
		_save_status.text = tr("ui.save.status_never")


func _on_saved(_at: int) -> void:
	_refresh_save_status()


func _on_save_failed(_reason: String) -> void:
	_refresh_save_status()


func _on_import_ready(decoded: Dictionary) -> void:
	var state: Dictionary = decoded["state"]
	var leader: String = state["party"][0]
	var body := (
		tr("ui.import.confirm_body")
		. format(
			{
				"name": Content.display_name(leader),
				"level": state["characters"][leader]["level"],
				"date": Kit.format_date(decoded["saved_at"]),
			}
		)
	)
	var d := ConfirmDialog.open(self, tr("ui.import.confirm_title"), body, "import_confirm")
	d.confirmed.connect(
		func() -> void:
			SaveService.apply_import(decoded)
			Router.go_to("camp", {}, false)
	)
	d.cancelled.connect(func() -> void: flash(_status, tr("ui.import.cancelled")))


func _on_import_failed(code: String) -> void:
	if code == "cancelled":
		flash(_status, tr("ui.import.cancelled"))
	else:
		flash(_status, tr("ui.import.failed").format({"reason": tr("error.save." + code)}), true)
