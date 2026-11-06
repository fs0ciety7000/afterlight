extends ProgressionScreen
## Forge (GDD §10.2, §17 panel.forge): pick an item, see the next attempt
## (cost, chance, pity) and enhance it. A failure keeps the level, gives back
## part of the gold and raises the next chance.

var _selected := ""
var _result_text := ""
var _result_ok := true


func _init() -> void:
	screen_id = "forge"


func setup(params: Dictionary) -> void:
	_selected = str(params.get("uid", ""))


func _build(into: VBoxContainer) -> void:
	var api: ProgressionApi = GameState.progression
	var uids: Array = []
	var worn: Dictionary = api.views.worn_items()
	for slot: String in api.views.equipment_slots():
		if str(worn[slot]) != "":
			uids.append(worn[slot])
	for item: Dictionary in api.bag_items():
		uids.append(item["uid"])
	if not uids.has(_selected):
		_selected = uids[0] if not uids.is_empty() else ""
	var panes := two_panes(into)
	var left := panes[0]
	var right := panes[1]
	heading(left, tr("ui.forge.pick"))
	if uids.is_empty():
		empty_hint(left, tr("ui.forge.no_items"))
	for uid: String in uids:
		_item_row(left, uid, worn.values().has(uid))
	if _selected != "":
		_detail(right, _selected)
	else:
		empty_hint(right, tr("ui.forge.hint"))


func _item_row(parent: VBoxContainer, uid: String, is_worn: bool) -> void:
	var api: ProgressionApi = GameState.progression
	var item: Dictionary = api.item(uid)
	var row := Kit.hbox()
	var tile := ItemTile.make(TILE)
	tile.show_item(item, api.views.item_slot(item))
	tile.selected = uid == _selected
	tile.pressed.connect(
		func() -> void:
			_selected = uid
			_result_text = ""
			_refocus_id = "forge.item." + uid
			_queue_refresh()
	)
	UiProbe.register("forge.item." + uid, tile)
	row.add_child(tile)
	var col := Kit.vbox(UiTokens.SPACE["xs"])
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(Kit.label(ProgressionText.item_name(item), "", true))
	var meta := ProgressionText.rarity_name(item["rarity"])
	if is_worn:
		meta = tr("ui.forge.worn").format({"rarity": meta})
	col.add_child(Kit.label(meta, "MutedLabel"))
	row.add_child(col)
	parent.add_child(row)


func _detail(parent: VBoxContainer, uid: String) -> void:
	var api: ProgressionApi = GameState.progression
	var item: Dictionary = api.item(uid)
	var head := Kit.hbox()
	var tile := ItemTile.make(TILE)
	tile.show_item(item, api.views.item_slot(item))
	tile.focus_mode = Control.FOCUS_NONE
	head.add_child(tile)
	var col := Kit.vbox(UiTokens.SPACE["xs"])
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Kit.label(ProgressionText.item_name(item), "SubheadingLabel", true)
	UiProbe.register("forge.item_name", title)
	col.add_child(title)
	col.add_child(rarity_label(item["rarity"]))
	head.add_child(col)
	parent.add_child(head)
	# The button and its result sit right under the item's name: on phones the
	# header, tabs and portrait leave little room and the rest scrolls.
	var q: Dictionary = api.enhance_quote(uid)
	action(parent, tr("ui.forge.enhance"), "forge.enhance", q, _enhance.bind(uid))
	var result := Kit.label(_result_text, "LeadLabel" if _result_ok else "ErrorLabel", true)
	result.visible = _result_text != ""
	UiProbe.register("forge.result", result)
	parent.add_child(result)
	var lines := PackedStringArray()
	for m: Dictionary in api.item_modifiers(uid):
		lines.append(ProgressionText.modifier_line(m, int(item["item_level"])))
	var mods := Kit.label("\n".join(lines), "", true)
	UiProbe.register("forge.item_mods", mods)

	heading(parent, tr("ui.forge.next"))
	value_row(
		parent,
		tr("ui.forge.level"),
		tr("ui.forge.level_value").format({"level": item["enhance"], "max": q.get("max", 0)}),
		"forge.level"
	)
	if int(q.get("from", 0)) < int(q.get("max", 0)):
		value_row(
			parent,
			tr("ui.forge.target"),
			tr("ui.fmt.plus").format({"value": q.get("to", 0)}),
			"forge.target"
		)
		value_row(
			parent,
			tr("ui.forge.cost"),
			ProgressionText.cost(int(q.get("gold", 0)), {"material.mana_dust": q.get("dust", 0)}),
			"forge.cost"
		)
		value_row(
			parent,
			tr("ui.forge.chance"),
			ProgressionText.chance(q.get("chance", 0.0)),
			"forge.chance"
		)
		if float(q.get("pity_bonus", 0.0)) > 0.0:
			value_row(
				parent,
				tr("ui.forge.pity"),
				tr("ui.fmt.plus").format({"value": ProgressionText.chance(q["pity_bonus"])}),
				"forge.pity"
			)
	# Then the item's stats and the rules.
	parent.add_child(mods)
	if int(q.get("from", 0)) < int(q.get("max", 0)):
		parent.add_child(Kit.label(tr("ui.forge.rules"), "MutedLabel", true))


func _enhance(uid: String) -> void:
	var r: Dictionary = GameState.progression.enhance_item(uid)
	if not r.get("ok", false):
		_result_ok = false
		_result_text = GameState.reason_text(r)
	elif r.get("success", false):
		_result_ok = true
		_result_text = tr("ui.forge.success").format({"level": r["level"]})
	else:
		_result_ok = false
		_result_text = tr("ui.forge.failure").format({"level": r["level"], "refund": r["refund"]})
	flash(_status, _result_text, not _result_ok)
	_queue_refresh()
