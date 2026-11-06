class_name OfflineSummaryScreen
extends Screen
## « Pendant votre absence » (GDD §12, §17 screen.offline_summary): what the
## offline hunt earned since the last session, shown once after a load and
## credited by « Récupérer » (GameState.claim_offline, once). A summary that
## credits nothing (unsafe hunt, ineligible hunt, clock moved back) shows why.

var _summary: Dictionary = {}
var _claim: Button
var _status: Label


## Screen to open after a load: this one while a summary waits, else the world.
static func entry_screen() -> String:
	return "offline_summary" if not GameState.pending_offline_summary().is_empty() else "explore"


func _ready() -> void:
	add_backdrop(0.8)
	_summary = GameState.pending_offline_summary()
	var narrow := is_narrow()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := Kit.panel()
	var width := minf(560.0, get_viewport_rect().size.x - 32.0)
	card.custom_minimum_size = Vector2(width, 0)
	center.add_child(card)
	var col := Kit.vbox(UiTokens.SPACE["md"])
	card.add_child(col)

	var title := Kit.label(tr("ui.offline.title"), "HeadingLabel", true)
	UiProbe.register("offline.title", title)
	col.add_child(title)
	if _summary.is_empty():
		_status = Kit.label(tr("error.offline.nothing_to_claim"), "MutedLabel", true)
		col.add_child(_status)
		_add_claim(col, tr("ui.combat.continue"))
		return
	var encounter: String = _summary["encounter"]
	var hunt := Kit.label(
		tr("ui.offline.hunt").format({"encounter": Content.display_name(encounter)}),
		"SubheadingLabel",
		true
	)
	UiProbe.register("offline.hunt", hunt)
	col.add_child(hunt)
	col.add_child(_durations())
	col.add_child(HSeparator.new())

	var body := Kit.vbox(UiTokens.SPACE["sm"])
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _summary["status"] == OfflineCalc.STATUS_OK:
		_gains(body)
	else:
		_refusal(body)
	var limit := get_viewport_rect().size.y * (0.5 if narrow else 0.55)
	if body.get_combined_minimum_size().y > limit:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(0, limit)
		scroll.add_child(body)
		col.add_child(scroll)
	else:
		col.add_child(body)

	col.add_child(HSeparator.new())
	_status = Kit.label("", "MutedLabel", true)
	UiProbe.register("offline.status", _status)
	col.add_child(_status)
	_add_claim(col, tr("ui.offline.claim"))


func _add_claim(col: VBoxContainer, text: String) -> void:
	var row := Kit.hbox()
	row.alignment = BoxContainer.ALIGNMENT_END
	_claim = Kit.button(text, true, "offline.claim")
	_claim.custom_minimum_size.y = UiTokens.at_least_css(UiTokens.TOUCH_TARGET)
	_claim.pressed.connect(_on_claim)
	row.add_child(_claim)
	col.add_child(row)


## Absence, counted time (capped at 8 h) and the offline efficiency.
func _durations() -> Control:
	var box := Kit.vbox(UiTokens.SPACE["xs"])
	var away := Kit.label(
		tr("ui.offline.away").format(
			{"duration": Kit.format_duration(maxi(int(_summary["elapsed_s"]), 0))}
		),
		"MutedLabel",
		true
	)
	UiProbe.register("offline.away", away)
	box.add_child(away)
	if _summary["status"] != OfflineCalc.STATUS_OK:
		return box
	var counted := Kit.label(
		tr("ui.offline.counted").format(
			{"duration": Kit.format_duration(int(_summary["counted_s"]))}
		),
		"LeadLabel",
		true
	)
	UiProbe.register("offline.duration", counted)
	box.add_child(counted)
	var capped := Kit.label(
		tr("ui.offline.capped").format({"hours": BalanceOffline.OFFLINE_CAP_S / 3600}),
		"MutedLabel",
		true
	)
	capped.visible = bool(_summary["capped"])
	UiProbe.register("offline.capped", capped)
	box.add_child(capped)
	var eff := Kit.label(
		tr("ui.offline.efficiency").format(
			{"value": roundi(float(_summary["efficiency"]) * 100.0)}
		),
		"MutedLabel",
		true
	)
	box.add_child(eff)
	return box


func _gains(body: VBoxContainer) -> void:
	_row(body, tr("ui.offline.clears"), str(floori(float(_summary["clears"]))), "offline.clears")
	_row(
		body,
		tr("ui.offline.xp"),
		tr("ui.fmt.plus").format({"value": int(_summary["xp"])}),
		"offline.xp"
	)
	if int(_summary["levels_gained"]) > 0:
		_row(
			body,
			tr("ui.offline.level"),
			tr("ui.offline.level_value").format(
				{"before": _summary["level_before"], "after": _summary["level_after"]}
			),
			"offline.level"
		)
	_row(
		body,
		tr("ui.offline.gold"),
		tr("ui.fmt.plus").format({"value": int(_summary["gold"])}),
		"offline.gold"
	)
	var materials: Dictionary = _summary["materials"]
	_row(
		body,
		tr("ui.offline.materials"),
		ProgressionText.cost(0, materials) if not materials.is_empty() else tr("ui.offline.none"),
		"offline.materials"
	)
	var kept: Array = _summary["items"]
	_row(body, tr("ui.offline.items_kept"), str(kept.size()), "offline.items_kept")
	for i in kept.size():
		var item: Dictionary = kept[i]
		var line := Kit.label(ProgressionText.item_name(item), "", true)
		line.add_theme_color_override(
			"font_color", ProgressionText.rarity_color(str(item.get("rarity", ""))).darkened(0.35)
		)
		UiProbe.register("offline.item.%d" % i, line)
		body.add_child(line)
	if int(_summary["items_salvaged"]) > 0:
		var dust := {BalanceItems.DUST_ID: int(_summary["salvage_dust"])}
		_row(
			body,
			tr("ui.offline.items_salvaged"),
			tr("ui.offline.count_plus").format(
				{"count": _summary["items_salvaged"], "gain": ProgressionText.cost(0, dust)}
			),
			"offline.items_salvaged"
		)
	var runes: Array = _summary["runes"]
	if not runes.is_empty():
		var names := PackedStringArray()
		for r: Dictionary in runes:
			names.append(ProgressionText.rune_name(r["id"], int(r["tier"])))
		_row(
			body,
			tr("ui.offline.runes_kept"),
			tr("ui.common.separator").join(names),
			"offline.runes_kept"
		)
	if int(_summary["runes_salvaged"]) > 0:
		var shards := {BalanceGrimoire.SHARD_ID: int(_summary["rune_shards"])}
		_row(
			body,
			tr("ui.offline.runes_salvaged"),
			tr("ui.offline.count_plus").format(
				{"count": _summary["runes_salvaged"], "gain": ProgressionText.cost(0, shards)}
			),
			"offline.runes_salvaged"
		)
	if int(_summary["xp_wasted"]) > 0:
		var wasted := Kit.label(
			GameState.reason_text(
				{"key": "log.xp_wasted", "params": {"xp": _summary["xp_wasted"]}}
			),
			"MutedLabel",
			true
		)
		UiProbe.register("offline.xp_wasted", wasted)
		body.add_child(wasted)


## Unsafe, ineligible or clock: the reason, and nothing credited.
func _refusal(body: VBoxContainer) -> void:
	body.add_child(Kit.label(tr("ui.offline.warning_title"), "SubheadingLabel", true))
	var lines := PackedStringArray()
	var all: Array = _summary.get("lines", [])
	for i in range(1, all.size()):  # line 0 is the hunt, already shown
		lines.append(GameState.reason_text(all[i]))
	var warning := Kit.label("\n".join(lines), "ErrorLabel", true)
	UiProbe.register("offline.warning", warning)
	body.add_child(warning)


func _row(parent: Control, label_text: String, value: String, probe_id: String) -> void:
	var row := Kit.hbox()
	var n := Kit.label(label_text, "", true)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	var v := Kit.label(value, "NumberLabel", true)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiProbe.register(probe_id, v)
	row.add_child(v)
	parent.add_child(row)


func _on_claim() -> void:
	_claim.disabled = true
	if _summary.is_empty():
		Router.go_to("explore", {}, false)
		return
	var r := GameState.claim_offline()
	if not r["ok"]:
		flash(
			_status,
			tr("ui.offline.claim_failed").format({"reason": GameState.reason_text(r)}),
			true
		)
		_summary = {}
		_claim.text = tr("ui.combat.continue")
		_claim.disabled = false
		return
	var toast := ""
	if int(r["xp"]) > 0 or int(r["gold"]) > 0:
		toast = tr("ui.offline.claimed").format({"xp": r["xp"], "gold": r["gold"]})
		flash(_status, toast)
	Router.go_to("explore", {"toast": toast}, false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# The summary waits for its claim: Échap does not skip it.
		get_viewport().set_input_as_handled()


func grab_initial_focus() -> void:
	if is_instance_valid(_claim):
		_claim.grab_focus()
