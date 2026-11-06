extends ProgressionScreen
## Personnage (GDD §17 panel.character): level and XP, the 6 equipment slots,
## final stats and the 2 artifact slots with their lock reason.


func _init() -> void:
	screen_id = "character"


func _build(into: VBoxContainer) -> void:
	var api: ProgressionApi = GameState.progression
	var panes := two_panes(into)
	var left := panes[0]
	var right := panes[1]

	# Level and XP.
	var xp: Dictionary = api.views.xp_progress()
	var head := Kit.hbox()
	var name_label := Kit.label(Content.display_name(api.leader()), "SubheadingLabel")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var level := Kit.label(tr("ui.explore.level").format({"level": xp["level"]}), "NumberLabel")
	UiProbe.register("character.level", level)
	head.add_child(level)
	left.add_child(head)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = UiTokens.SPACE["md"]
	bar.max_value = maxi(int(xp["to_next"]), 1)
	bar.value = int(xp["xp"]) if int(xp["to_next"]) > 0 else bar.max_value
	left.add_child(bar)
	var xp_text := (
		tr("ui.char.xp").format({"xp": xp["xp"], "next": xp["to_next"]})
		if int(xp["to_next"]) > 0
		else tr("ui.char.xp_cap").format({"cap": xp["cap"]})
	)
	var xp_label := Kit.label(xp_text, "MutedLabel")
	UiProbe.register("character.xp", xp_label)
	left.add_child(xp_label)

	# Equipment.
	heading(left, tr("ui.char.equipment"))
	var worn: Dictionary = api.views.worn_items()
	for slot: String in api.views.equipment_slots():
		_slot_row(left, slot, str(worn[slot]))

	# Final stats.
	heading(right, tr("ui.char.stats"))
	var stats: Dictionary = api.hero_stats()
	for stat: String in ProgressionText.SHEET_STATS:
		if not stats.has(stat):
			continue
		value_row(
			right,
			ProgressionText.stat_name(stat),
			ProgressionText.value(stat, "flat", float(stats[stat])),
			"character.stat." + stat
		)

	# Artifacts.
	heading(right, tr("ui.char.artifacts"))
	_artifacts(right)


func _slot_row(parent: VBoxContainer, slot: String, uid: String) -> void:
	var api: ProgressionApi = GameState.progression
	var row := Kit.hbox()
	var tile := ItemTile.make(TILE)
	var item: Dictionary = api.item(uid) if uid != "" else {}
	if item.is_empty():
		tile.show_kind(ItemTile.KIND_EMPTY)
	else:
		tile.show_item(item, slot)
	tile.pressed.connect(func() -> void: open("bag", {"uid": uid, "slot": slot}))
	UiProbe.register("character.tile." + slot, tile)
	row.add_child(tile)
	var col := Kit.vbox(UiTokens.SPACE["xs"])
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(Kit.label(ProgressionText.slot_name(slot), "MutedLabel"))
	var item_name := Kit.label(
		ProgressionText.item_name(item) if not item.is_empty() else tr("ui.char.slot_empty"),
		"",
		true
	)
	UiProbe.register("character.slot." + slot, item_name)
	col.add_child(item_name)
	if not item.is_empty():
		col.add_child(rarity_label(item["rarity"]))
	row.add_child(col)
	if not item.is_empty():
		action(
			row,
			tr("ui.bag.unequip"),
			"character.unequip." + slot,
			api.unequip_quote(slot),
			func() -> void: report(api.unequip_slot(slot), tr("ui.bag.unequipped")),
			false
		)
	parent.add_child(row)


func _artifacts(parent: VBoxContainer) -> void:
	var api: ProgressionApi = GameState.progression
	var slots: Array = api.views.artifact_slots()
	for s: Dictionary in slots:
		var i: int = s["index"]
		var row := Kit.hbox()
		var col := Kit.vbox(UiTokens.SPACE["xs"])
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(Kit.label(tr("ui.char.artifact_slot").format({"n": i + 1}), "MutedLabel"))
		var text := ""
		if not s["unlocked"]:
			text = GameState.reason_text(s["lock"])
		elif str(s["id"]) == "":
			text = tr("ui.char.slot_empty")
		else:
			text = _artifact_text(str(s["id"]))
		var label := Kit.label(text, "", true)
		UiProbe.register("character.artifact_slot.%d" % i, label)
		col.add_child(label)
		row.add_child(col)
		if s["unlocked"] and str(s["id"]) != "":
			action(
				row,
				tr("ui.char.artifact_remove"),
				"character.artifact_remove.%d" % i,
				api.artifact_unequip_quote(i),
				func() -> void: report(api.unequip_artifact(i), tr("ui.char.artifact_removed")),
				false
			)
		parent.add_child(row)

	var owned: Dictionary = api.views.owned_artifacts()
	if owned.is_empty():
		empty_hint(parent, tr("ui.char.no_artifacts"))
		return
	heading(parent, tr("ui.char.owned_artifacts"))
	var ids := owned.keys()
	ids.sort()
	for id: String in ids:
		var card := Kit.panel("CardPanel")
		var col := Kit.vbox(UiTokens.SPACE["xs"])
		card.add_child(col)
		col.add_child(Kit.label(_artifact_text(id), "LeadLabel", true))
		col.add_child(Kit.label(tr(Content.get_entity(id).get("desc_key", id)), "MutedLabel", true))
		var short := id.get_slice(".", 1)
		var buttons := HFlowContainer.new()
		buttons.add_theme_constant_override("h_separation", UiTokens.SPACE["sm"])
		for s: Dictionary in slots:
			var i: int = s["index"]
			action(
				buttons,
				tr("ui.char.artifact_wear").format({"n": i + 1}),
				"character.artifact_wear.%s.%d" % [short, i],
				api.artifact_equip_quote(i, id),
				func() -> void: report(api.equip_artifact(i, id), tr("ui.char.artifact_worn")),
				false
			)
		var q: Dictionary = api.artifact_quote(id)
		if q.has("gold"):
			col.add_child(
				Kit.label(
					tr("ui.char.artifact_cost").format(
						{
							"to": q["to"],
							"cost":
							ProgressionText.cost(
								int(q["gold"]), {"material.ashen_essence": q["essence"]}
							)
						}
					),
					"MutedLabel",
					true
				)
			)
		action(
			buttons,
			tr("ui.char.artifact_level_up"),
			"character.artifact_level." + short,
			q,
			func() -> void: report(api.level_artifact(id), tr("ui.char.artifact_leveled"))
		)
		col.add_child(buttons)
		parent.add_child(card)


func _artifact_text(id: String) -> String:
	var level := int(GameState.progression.views.owned_artifacts().get(id, 0))
	return tr("ui.char.artifact_name").format({"name": Content.display_name(id), "level": level})
