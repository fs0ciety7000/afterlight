extends ProgressionScreen
## Graveuse de runes (GDD §10.4, §17 panel.runecarver): 3 identical runes of
## tier n become one of tier n+1 for gold and rune shards, always
## successfully. A spare rune can also be salvaged into shards.

var _rune := ""
var _tier := 1


func _init() -> void:
	screen_id = "runecarver"


func _entries() -> Array:
	var api: ProgressionApi = GameState.progression
	var out: Array = api.views.rune_stock()
	var owned := out.map(func(r: Dictionary) -> String: return r["id"])
	var defs: Array = Content.all_of("rune").map(func(e: Dictionary) -> String: return e["id"])
	defs.sort()
	for id: String in defs:
		if not owned.has(id):
			out.append({"id": id, "tier": 1, "count": 0})
	return out


func _build(into: VBoxContainer) -> void:
	var api: ProgressionApi = GameState.progression
	var entries := _entries()
	var found := false
	for e: Dictionary in entries:
		found = found or (e["id"] == _rune and int(e["tier"]) == _tier)
	if not found and not entries.is_empty():
		_rune = entries[0]["id"]
		_tier = int(entries[0]["tier"])
	var panes := two_panes(into)
	var left := panes[0]
	var right := panes[1]
	heading(left, tr("ui.runes.stock"))
	if api.views.rune_stock().is_empty():
		empty_hint(left, tr("ui.bag.no_runes"))
	for e: Dictionary in entries:
		var key := "%s_%d" % [str(e["id"]).get_slice(".", 1), int(e["tier"])]
		var row := Kit.hbox()
		var tile := ItemTile.make(TILE)
		tile.show_rune(e["id"], int(e["tier"]))
		tile.selected = e["id"] == _rune and int(e["tier"]) == _tier
		tile.pressed.connect(
			func() -> void:
				_rune = e["id"]
				_tier = int(e["tier"])
				_refocus_id = "runes.rune." + key
				_queue_refresh()
		)
		UiProbe.register("runes.rune." + key, tile)
		row.add_child(tile)
		var label := Kit.label(
			tr("ui.grimoire.stock_line").format(
				{"name": ProgressionText.rune_name(e["id"], int(e["tier"])), "count": e["count"]}
			),
			"",
			true
		)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		left.add_child(row)
	if _rune != "":
		_detail(right)


func _detail(parent: VBoxContainer) -> void:
	var api: ProgressionApi = GameState.progression
	var title := Kit.label(ProgressionText.rune_name(_rune, _tier), "SubheadingLabel", true)
	UiProbe.register("runes.name", title)
	parent.add_child(title)
	var desc: String = Content.get_entity(_rune).get("desc_key", "")
	if desc != "":
		parent.add_child(Kit.label(tr(desc), "MutedLabel", true))
	var q: Dictionary = api.fusion_quote(_rune, _tier)
	heading(parent, tr("ui.runes.fusion"))
	if q.has("gold"):
		var target := ProgressionText.rune_name(_rune, int(q["to"]))
		value_row(
			parent,
			tr("ui.runes.recipe").format(
				{"required": q["required"], "name": ProgressionText.rune_name(_rune, _tier)}
			),
			target,
			"runes.recipe"
		)
		value_row(
			parent,
			tr("ui.forge.cost"),
			ProgressionText.cost(int(q["gold"]), {"material.rune_shard": q["shards"]}),
			"runes.cost"
		)
		value_row(parent, tr("ui.runes.owned"), str(q["owned"]), "runes.owned")
		parent.add_child(Kit.label(tr("ui.runes.rules"), "MutedLabel", true))
	action(
		parent,
		tr("ui.runes.fuse"),
		"runes.fuse",
		q,
		func() -> void:
			var r: Dictionary = api.fuse_runes(_rune, _tier)
			if r.get("ok", false):
				_tier = int(r["to"])
			report(
				r, tr("ui.runes.fused").format({"name": ProgressionText.rune_name(_rune, _tier)})
			)
	)
	action(
		parent,
		tr("ui.runes.salvage"),
		"runes.salvage",
		api.salvage_rune_quote(_rune, _tier),
		func() -> void:
			var r: Dictionary = api.salvage_rune(_rune, _tier)
			report(r, tr("ui.runes.salvaged").format({"shards": r.get("shards", 0)})),
		false
	)
