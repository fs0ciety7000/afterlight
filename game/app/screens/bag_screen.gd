extends ProgressionScreen
## Sac (GDD §17 panel.inventory): 60-slot grid with rarity frames, worn items,
## the item card with affixes, ranges and the comparison with the worn item
## (green / red + arrow), Équiper / Déséquiper, single and bulk salvage with a
## confirmation; tabs for materials, runes and consumables.

const VIEWS := ["items", "materials", "runes", "consumables"]
const RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]

var _view := "items"
var _selected := ""
var _bulk := ["common"]


func _init() -> void:
	screen_id = "bag"


func setup(params: Dictionary) -> void:
	_selected = str(params.get("uid", ""))
	_view = str(params.get("view", "items"))


func _build(into: VBoxContainer) -> void:
	var views := HFlowContainer.new()
	views.add_theme_constant_override("h_separation", UiTokens.SPACE["sm"])
	for v: String in VIEWS:
		var b := button(tr("ui.bag.view." + v), v == _view, "bag.view." + v)
		b.pressed.connect(
			func() -> void:
				_view = v
				_refocus_id = "bag.view." + v
				_queue_refresh()
		)
		views.add_child(b)
	into.add_child(views)
	match _view:
		"materials":
			_materials(one_pane(into))
		"runes":
			_runes(one_pane(into))
		"consumables":
			_consumables(one_pane(into))
		_:
			_items(into)


# --- Equipment ----------------------------------------------------------------


func _items(into: VBoxContainer) -> void:
	var api: ProgressionApi = GameState.progression
	var bag: Array = api.bag_items()
	var worn: Dictionary = api.views.worn_items()
	if _selected != "" and api.item(_selected).is_empty():
		_selected = ""
	if _selected == "" and not bag.is_empty():
		_selected = bag[0]["uid"]
	var panes := two_panes(into, 1.3)
	var left := panes[0]
	var right := panes[1]

	heading(left, tr("ui.bag.worn"))
	var worn_row := HFlowContainer.new()
	worn_row.add_theme_constant_override("h_separation", UiTokens.SPACE["xs"])
	for slot: String in api.views.equipment_slots():
		var uid: String = worn[slot]
		var tile := ItemTile.make(TILE)
		if uid == "":
			tile.show_kind(ItemTile.KIND_EMPTY)
			tile.tooltip_text = ProgressionText.slot_name(slot)
			tile.disabled = true
		else:
			tile.show_item(api.item(uid), slot)
			tile.selected = uid == _selected
			tile.pressed.connect(_select.bind(uid, "bag.worn." + slot))
		UiProbe.register("bag.worn." + slot, tile)
		worn_row.add_child(tile)
	left.add_child(worn_row)

	var count := Kit.label(
		tr("ui.bag.count").format({"count": bag.size(), "max": api.views.bag_capacity()}),
		"MutedLabel"
	)
	UiProbe.register("bag.count", count)
	left.add_child(count)
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", UiTokens.SPACE["xs"])
	grid.add_theme_constant_override("v_separation", UiTokens.SPACE["xs"])
	for i in api.views.bag_capacity():
		var tile := ItemTile.make(TILE)
		if i < bag.size():
			var item: Dictionary = bag[i]
			tile.show_item(item, api.views.item_slot(item))
			tile.selected = item["uid"] == _selected
			tile.pressed.connect(_select.bind(item["uid"], "bag.slot.%d" % i))
			UiProbe.register("bag.slot.%d" % i, tile)
		else:
			tile.show_kind(ItemTile.KIND_EMPTY)
			tile.focus_mode = Control.FOCUS_NONE
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(tile)
	left.add_child(grid)
	if bag.is_empty():
		empty_hint(left, tr("ui.bag.empty"))
	_bulk_salvage(left)

	if _selected == "":
		empty_hint(right, tr("ui.bag.pick_item"))
	else:
		_card(right, _selected, worn.values().has(_selected))


func _select(uid: String, probe_id: String) -> void:
	_selected = uid
	_refocus_id = probe_id
	_queue_refresh()


func _card(parent: VBoxContainer, uid: String, is_worn: bool) -> void:
	var api: ProgressionApi = GameState.progression
	var item: Dictionary = api.item(uid)
	var slot: String = api.views.item_slot(item)
	var head := Kit.hbox()
	var tile := ItemTile.make(TILE)
	tile.show_item(item, slot)
	tile.focus_mode = Control.FOCUS_NONE
	head.add_child(tile)
	var col := Kit.vbox(UiTokens.SPACE["xs"])
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Kit.label(ProgressionText.item_name(item), "SubheadingLabel", true)
	UiProbe.register("bag.detail_name", title)
	col.add_child(title)
	var rarity := rarity_label(item["rarity"])
	UiProbe.register("bag.detail_rarity", rarity)
	col.add_child(rarity)
	head.add_child(col)
	parent.add_child(head)
	(
		parent
		. add_child(
			(
				Kit
				. label(
					(
						tr("ui.bag.item_meta")
						. format(
							{
								"slot": ProgressionText.slot_name(slot),
								"ilvl": item["item_level"],
								"level": item["enhance"],
								"max": api.views.enhance_max(item["rarity"]),
							}
						)
					),
					"MutedLabel",
					true
				)
			)
		)
	)
	var lines := PackedStringArray()
	for m: Dictionary in api.item_modifiers(uid):
		lines.append(ProgressionText.modifier_line(m, int(item["item_level"])))
	var mods := Kit.label("\n".join(lines), "", true)
	UiProbe.register("bag.detail_mods", mods)
	parent.add_child(mods)
	var legendary := str(item.get("legendary", ""))
	if legendary != "":
		parent.add_child(Kit.label(Content.display_name(legendary), "LeadLabel", true))
		parent.add_child(
			Kit.label(tr(Content.get_entity(legendary).get("desc_key", legendary)), "", true)
		)
	if not is_worn:
		_comparison(parent, uid, slot)

	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", UiTokens.SPACE["sm"])
	if is_worn:
		action(
			actions,
			tr("ui.bag.unequip"),
			"bag.unequip",
			api.unequip_quote(slot),
			func() -> void: report(api.unequip_slot(slot), tr("ui.bag.unequipped"))
		)
	else:
		action(
			actions,
			tr("ui.bag.equip"),
			"bag.equip",
			{"ok": true},
			func() -> void: report(api.equip_item(uid), tr("ui.bag.equipped"))
		)
		action(
			actions,
			tr("ui.bag.salvage_one"),
			"bag.salvage_one",
			api.salvage_items_quote([uid]),
			func() -> void: _confirm_salvage([uid], [], 1),
			false
		)
	var forge := button(tr("ui.bag.to_forge"), false, "bag.to_forge")
	forge.pressed.connect(func() -> void: open("forge", {"uid": uid}))
	actions.add_child(forge)
	parent.add_child(actions)
	# Right under the item's name: on phones the details run below the fold.
	parent.move_child(actions, head.get_index() + 1)


func _comparison(parent: VBoxContainer, uid: String, slot: String) -> void:
	var api: ProgressionApi = GameState.progression
	var worn_uid: String = api.views.worn_items()[slot]
	heading(parent, tr("ui.bag.compare"))
	if worn_uid == "":
		parent.add_child(Kit.label(tr("ui.bag.compare_none"), "MutedLabel", true))
	else:
		parent.add_child(
			Kit.label(
				tr("ui.bag.compare_with").format(
					{"name": ProgressionText.item_name(api.item(worn_uid))}
				),
				"MutedLabel",
				true
			)
		)
	var palette: Dictionary = UiTokens.DAY
	for c: Dictionary in api.compare_item(uid):
		var key := "ui.bag.compare_equal"
		var color: Color = palette["ink_muted"]
		if c["sign"] == "better":
			key = "ui.bag.compare_better"
			color = palette["success"]
		elif c["sign"] == "worse":
			key = "ui.bag.compare_worse"
			color = palette["danger"]
		var text := (
			tr(key)
			. format(
				{
					"stat": ProgressionText.stat_name(c["stat"]),
					"delta": ProgressionText.value(c["stat"], c["layer"], float(c["delta"]), true),
				}
			)
		)
		var l := Kit.label(text, "", true)
		l.add_theme_color_override("font_color", color)
		UiProbe.register("bag.compare.%s_%s" % [c["stat"], c["layer"]], l)
		parent.add_child(l)


func _bulk_salvage(parent: VBoxContainer) -> void:
	var api: ProgressionApi = GameState.progression
	heading(parent, tr("ui.bag.bulk_title"))
	var picks := HFlowContainer.new()
	picks.add_theme_constant_override("h_separation", UiTokens.SPACE["sm"])
	for r: String in RARITIES:
		var box := CheckBox.new()
		box.text = ProgressionText.rarity_name(r)
		box.button_pressed = _bulk.has(r)
		box.custom_minimum_size.y = UiTokens.at_least_css(UiTokens.TOUCH_TARGET)
		box.add_theme_color_override("font_color", ProgressionText.rarity_color(r).darkened(0.3))
		box.toggled.connect(
			func(on: bool) -> void:
				if on and not _bulk.has(r):
					_bulk.append(r)
				elif not on:
					_bulk.erase(r)
				_refocus_id = "bag.bulk_pick." + r
				_queue_refresh()
		)
		UiProbe.register("bag.bulk_pick." + r, box)
		picks.add_child(box)
	parent.add_child(picks)
	var q: Dictionary = api.salvage_quote(_bulk)
	var quote := {"ok": int(q["count"]) > 0, "error": "error.nothing_to_salvage", "params": {}}
	var summary := Kit.label(
		tr("ui.bag.bulk_quote").format({"count": q["count"], "dust": q["dust"]}), "MutedLabel", true
	)
	UiProbe.register("bag.bulk_quote", summary)
	parent.add_child(summary)
	action(
		parent,
		tr("ui.bag.bulk_salvage"),
		"bag.bulk_salvage",
		quote,
		func() -> void: _confirm_salvage([], _bulk.duplicate(), q["count"]),
		false
	)


## Salvage behind a confirmation that shows the quote (count and dust).
func _confirm_salvage(uids: Array, rarities: Array, count: int) -> void:
	var api: ProgressionApi = GameState.progression
	var dust := 0
	if rarities.is_empty():
		for uid: String in uids:
			dust += int(api.salvage_items_quote([uid]).get("dust", 0))
	else:
		dust = int(api.salvage_quote(rarities)["dust"])
	var d := ConfirmDialog.open(
		self,
		tr("ui.bag.salvage_title"),
		tr("ui.bag.salvage_body").format({"count": count, "dust": dust}),
		"bag.salvage_confirm"
	)
	d.confirmed.connect(
		func() -> void:
			var r: Dictionary = (
				api.salvage_items(uids) if rarities.is_empty() else api.salvage_rarities(rarities)
			)
			report(
				r,
				tr("ui.bag.salvaged").format({"count": r.get("count", 0), "dust": r.get("dust", 0)})
			)
	)


# --- Stocks -------------------------------------------------------------------


func _materials(col: VBoxContainer) -> void:
	var w: Dictionary = GameState.progression.views.wallet()
	value_row(col, tr("ui.prog.gold"), str(w["gold"]), "bag.material.gold")
	for e: Dictionary in Content.all_of("material"):
		var id: String = e["id"]
		var row := Kit.hbox()
		var tile := ItemTile.make(TILE)
		tile.show_kind(ItemTile.KIND_MATERIAL, id)
		tile.focus_mode = Control.FOCUS_NONE
		row.add_child(tile)
		var text := Kit.vbox(UiTokens.SPACE["xs"])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_child(Kit.label(Content.display_name(id), "LeadLabel"))
		text.add_child(Kit.label(tr(e.get("desc_key", id)), "MutedLabel", true))
		row.add_child(text)
		var qty := Kit.label(str(int(w["materials"].get(id, 0))), "NumberLabel")
		UiProbe.register("bag.material." + id.get_slice(".", 1), qty)
		row.add_child(qty)
		col.add_child(row)


func _runes(col: VBoxContainer) -> void:
	var stock: Array = GameState.progression.views.rune_stock()
	if stock.is_empty():
		empty_hint(col, tr("ui.bag.no_runes"))
	for s: Dictionary in stock:
		var row := Kit.hbox()
		var tile := ItemTile.make(TILE)
		tile.show_rune(s["id"], s["tier"])
		tile.focus_mode = Control.FOCUS_NONE
		row.add_child(tile)
		var text := Kit.vbox(UiTokens.SPACE["xs"])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_child(Kit.label(ProgressionText.rune_name(s["id"], s["tier"]), "LeadLabel"))
		var desc: String = Content.get_entity(s["id"]).get("desc_key", "")
		text.add_child(Kit.label(tr(desc) if desc != "" else "", "MutedLabel", true))
		row.add_child(text)
		var qty := Kit.label(tr("ui.fmt.count").format({"count": s["count"]}), "NumberLabel")
		UiProbe.register("bag.rune.%s_%d" % [str(s["id"]).get_slice(".", 1), s["tier"]], qty)
		row.add_child(qty)
		col.add_child(row)
	var go := button(tr("ui.bag.to_runecarver"), false, "bag.to_runecarver")
	go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	go.pressed.connect(func() -> void: open("runecarver"))
	col.add_child(go)


func _consumables(col: VBoxContainer) -> void:
	var carried: Dictionary = GameState.progression.views.consumables()
	for e: Dictionary in Content.all_of("consumable"):
		var id: String = e["id"]
		var row := Kit.hbox()
		var tile := ItemTile.make(TILE)
		tile.show_kind(ItemTile.KIND_CONSUMABLE, id)
		tile.focus_mode = Control.FOCUS_NONE
		row.add_child(tile)
		var text := Kit.vbox(UiTokens.SPACE["xs"])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_child(Kit.label(Content.display_name(id), "LeadLabel"))
		text.add_child(Kit.label(tr(e.get("desc_key", id)), "MutedLabel", true))
		row.add_child(text)
		var qty := Kit.label(
			tr("ui.shop.carried").format(
				{"carried": int(carried.get(id, 0)), "max": int(e.get("carry_max", 0))}
			),
			"NumberLabel"
		)
		UiProbe.register("bag.consumable." + id.get_slice(".", 1), qty)
		row.add_child(qty)
		col.add_child(row)
	var go := button(tr("ui.bag.to_merchant"), false, "bag.to_merchant")
	go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	go.pressed.connect(func() -> void: open("merchant"))
	col.add_child(go)
