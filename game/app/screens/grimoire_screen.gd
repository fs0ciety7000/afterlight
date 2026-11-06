extends ProgressionScreen
## Grimoire (GDD §10.3-§10.4, §17 panel.spellbook): spells with their rank,
## the next rank's cost, rune slots, socketing from the stock and removal.
## « Tactiques » and each spell's tactic badge open panel.tactics (GDD
## decision 23 a), on that spell for a badge.

var _selected := ""


func _init() -> void:
	screen_id = "grimoire"


func setup(params: Dictionary) -> void:
	_selected = str(params.get("spell", ""))


func _build(into: VBoxContainer) -> void:
	var spells: Array = GameState.progression.views.spells()
	var ids := spells.map(func(s: Dictionary) -> String: return s["id"])
	if not ids.has(_selected) and not ids.is_empty():
		_selected = ids[0]
	var panes := two_panes(into, 0.8)
	var left := panes[0]
	var right := panes[1]
	var tactics := button(tr("ui.tactics.tab"), false, "tactics.open.grimoire")
	tactics.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tactics.pressed.connect(open_tactics)
	left.add_child(tactics)
	var modes := {}
	for row: Dictionary in GameState.tactics.tactics_view().get("rows", []):
		modes[row["id"]] = TacticsPanel.current_label(row)
	heading(left, tr("ui.grimoire.spells"))
	for s: Dictionary in spells:
		var short: String = str(s["id"]).get_slice(".", 1)
		var text: String = (
			tr("ui.grimoire.spell_rank").format(
				{"name": Content.display_name(s["id"]), "rank": s["rank"], "max": s["max_rank"]}
			)
			if s["learned"]
			else tr("ui.grimoire.spell_locked").format(
				{"name": Content.display_name(s["id"]), "level": s["unlock_level"]}
			)
		)
		var b := button(text, s["id"] == _selected, "grimoire.spell." + short)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(
			func() -> void:
				_selected = s["id"]
				_refocus_id = "grimoire.spell." + short
				_queue_refresh()
		)
		if not modes.has(s["id"]):
			left.add_child(b)
			continue
		# The spell's tactic as a badge: a click opens the panel on it.
		var row := Kit.hbox(UiTokens.SPACE["sm"])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		var badge := button(
			tr("ui.tactics.badge").format({"mode": modes[s["id"]]}), false, "tactics.badge." + short
		)
		badge.theme_type_variation = "SecondaryButton"
		badge.pressed.connect(open_tactics.bind(str(s["id"])))
		row.add_child(badge)
		left.add_child(row)
	for s: Dictionary in spells:
		if s["id"] == _selected:
			_detail(right, s)


func _detail(parent: VBoxContainer, s: Dictionary) -> void:
	var api: ProgressionApi = GameState.progression
	var id: String = s["id"]
	var title := Kit.label(Content.display_name(id), "SubheadingLabel", true)
	UiProbe.register("grimoire.spell_name", title)
	parent.add_child(title)
	var desc: String = Content.get_entity(id).get("desc_key", "")
	if desc != "":
		parent.add_child(Kit.label(tr(desc), "MutedLabel", true))
	value_row(
		parent,
		tr("ui.grimoire.rank"),
		tr("ui.grimoire.rank_value").format({"rank": s["rank"], "max": s["max_rank"]}),
		"grimoire.rank"
	)

	# Next rank.
	var q: Dictionary = api.rank_quote(id)
	if q.has("gold"):
		value_row(
			parent,
			tr("ui.grimoire.next_cost").format({"rank": q["to"]}),
			ProgressionText.cost(int(q["gold"]), {"material.grimoire_page": q["pages"]}),
			"grimoire.rank_cost"
		)
		value_row(
			parent,
			tr("ui.grimoire.level_required"),
			str(q["level_required"]),
			"grimoire.rank_level"
		)
	action(parent, tr("ui.grimoire.rank_up"), "grimoire.rank_up", q, _rank_up.bind(id))

	# Rune slots.
	heading(parent, tr("ui.grimoire.runes"))
	var runes: Array = s["runes"]
	for i in int(s["slots"]):
		var row := Kit.hbox()
		var tile := ItemTile.make(TILE)
		tile.focus_mode = Control.FOCUS_NONE
		var text := tr("ui.grimoire.slot_free")
		if i < runes.size():
			tile.show_rune(runes[i]["id"], int(runes[i]["tier"]))
			text = ProgressionText.rune_name(runes[i]["id"], int(runes[i]["tier"]))
		else:
			tile.show_kind(ItemTile.KIND_EMPTY)
		row.add_child(tile)
		var label := Kit.label(text, "", true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiProbe.register("grimoire.slot.%d" % i, label)
		row.add_child(label)
		if i < runes.size():
			var b := button(tr("ui.grimoire.unsocket"), false, "grimoire.unsocket.%d" % i)
			b.pressed.connect(
				func() -> void:
					_refocus_id = "grimoire.rank_up"
					report(api.unsocket_rune(id, i), tr("ui.grimoire.unsocketed"))
			)
			row.add_child(b)
		parent.add_child(row)
	if int(s["slots"]) < 3:
		parent.add_child(Kit.label(tr("ui.grimoire.slots_hint"), "MutedLabel", true))

	# Runes in stock.
	heading(parent, tr("ui.grimoire.stock"))
	var stock: Array = api.views.rune_stock()
	if stock.is_empty():
		empty_hint(parent, tr("ui.bag.no_runes"))
	for r: Dictionary in stock:
		var row := Kit.hbox()
		var tile := ItemTile.make(TILE)
		tile.show_rune(r["id"], int(r["tier"]))
		tile.focus_mode = Control.FOCUS_NONE
		row.add_child(tile)
		var label := Kit.label(
			tr("ui.grimoire.stock_line").format(
				{"name": ProgressionText.rune_name(r["id"], int(r["tier"])), "count": r["count"]}
			),
			"",
			true
		)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var key := "%s_%d" % [str(r["id"]).get_slice(".", 1), int(r["tier"])]
		action(
			row,
			tr("ui.grimoire.socket"),
			"grimoire.socket." + key,
			api.socket_quote(id, r["id"], int(r["tier"])),
			func() -> void:
				report(api.socket_rune(id, r["id"], int(r["tier"])), tr("ui.grimoire.socketed")),
			false
		)
		parent.add_child(row)


## panel.tactics over the grimoire, on `focus` (a spell id) when given.
func open_tactics(focus: String = "") -> void:
	var p := TacticsPanel.open(self, {"focus": focus})
	var back := (
		"tactics.badge." + focus.get_slice(".", 1) if focus != "" else "tactics.open.grimoire"
	)
	p.closed.connect(
		func() -> void:
			_refocus_id = back
			_queue_refresh()
	)


func _rank_up(spell_id: String) -> void:
	var r: Dictionary = GameState.progression.rank_up_spell(spell_id)
	report(r, tr("ui.grimoire.ranked").format({"rank": r.get("to", 0)}))
