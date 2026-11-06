extends Screen
## Journal (GDD §17, docs/content/*.md): quests (tracked one first, objectives
## with their progress, rewards), the day's contracts (refreshed on open,
## « Récupérer » with the reason when disabled), the bestiary (tiers 1 / 5 /
## 25, locked entries say what unlocks them) and the discoveries by place.
## Opened from the HUD (Journal, J, the quest tracker) or the notice board
## (Contracts tab).

const TABS := ["quests", "contracts", "bestiary", "discoveries"]

var tab := "quests"
var _body: VBoxContainer
var _status: Label
var _scroll: ScrollContainer
var _refresh_queued := false
## Lines from the contracts refresh (new day, yesterday's auto-claim).
var _contract_news := []


func setup(params: Dictionary) -> void:
	var t := str(params.get("tab", "quests"))
	tab = t if TABS.has(t) else "quests"


func _ready() -> void:
	add_backdrop(0.8)
	var narrow := is_narrow()
	var panel := Kit.panel()
	add_child(Kit.margin(panel, narrow))
	var col := Kit.vbox(UiTokens.SPACE["sm"])
	panel.add_child(col)

	var head := Kit.hbox()
	var title := Kit.label(tr("ui.journal.title"), "HeadingLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiProbe.register("journal.title", title)
	head.add_child(title)
	var close := _button(tr("ui.prog.close"), false, "journal.close")
	close.pressed.connect(_close)
	head.add_child(close)
	col.add_child(head)

	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", UiTokens.SPACE["sm"])
	tabs.add_theme_constant_override("v_separation", UiTokens.SPACE["sm"])
	for id: String in TABS:
		var b := _button(tr("ui.journal.tab_" + id), id == tab, "journal.tab." + id)
		b.pressed.connect(_switch.bind(id))
		tabs.add_child(b)
	col.add_child(tabs)
	col.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	_body = Kit.vbox(UiTokens.SPACE["md"])
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	col.add_child(_scroll)
	_status = Kit.label("", "MutedLabel", true)
	UiProbe.register("journal.status", _status)
	col.add_child(_status)

	if tab == "contracts":
		_refresh_contracts()
	GameState.changed.connect(_queue_refresh)
	_refresh()


func grab_initial_focus() -> void:
	var c: Control = UiProbe._controls.get("journal.tab." + tab)
	if c and c.is_inside_tree():
		c.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("open_journal"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	Router.back("explore")


func _switch(id: String) -> void:
	if id == tab:
		return
	tab = id
	for t: String in TABS:
		var b := UiProbe._controls.get("journal.tab." + t) as Button
		if b:
			b.theme_type_variation = "PrimaryButton" if t == tab else "SecondaryButton"
	if tab == "contracts":
		_refresh_contracts()
	_status.text = ""
	_refresh()


func _button(text: String, primary: bool, probe_id: String) -> Button:
	var b := Kit.button(text, primary, probe_id)
	b.custom_minimum_size.y = UiTokens.at_least_css(UiTokens.TOUCH_TARGET)
	return b


## Rolls the day's contracts when the day moved on (never during a fight:
## the journal is a screen of its own).
func _refresh_contracts() -> void:
	_contract_news = []
	var r := GameState.content_api.refresh_contracts()
	if not r["auto_claimed"].is_empty():
		_contract_news.append(
			tr("ui.contracts.auto_claimed").format({"gold": r["auto_claimed"].get("gold", 0)})
		)
	if r["new_day"]:
		_contract_news.append(tr("ui.contracts.new_day"))
		SaveService.save_now()


func _queue_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		call_deferred("_refresh")


func _refresh() -> void:
	_refresh_queued = false
	if not GameState.has_game() or not is_inside_tree():
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	match tab:
		"quests":
			build_quests(_body)
		"contracts":
			build_contracts(_body, _contract_news)
		"bestiary":
			build_bestiary(_body)
		"discoveries":
			build_discoveries(_body)


static func _wide(text: String, variation: String = "") -> Label:
	var l := Kit.label(text, variation, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(240, 0)
	return l


static func _t(key: String) -> String:
	return StoryText.tr_key(key)


# --- Quests -------------------------------------------------------------------------


static func build_quests(into: VBoxContainer) -> void:
	var api := GameState.content_api
	var log := api.quest_log()
	if log.is_empty():
		into.add_child(_wide(_t("ui.journal.quests_empty"), "MutedLabel"))
		return
	var tracked := api.tracked_quest()
	var ordered := log.filter(func(e: Dictionary) -> bool: return e["id"] == tracked)
	ordered.append_array(log.filter(func(e: Dictionary) -> bool: return e["id"] != tracked))
	for entry: Dictionary in ordered:
		into.add_child(_quest_card(entry, entry["id"] == tracked))


static func _quest_card(entry: Dictionary, tracked: bool) -> Control:
	var id: String = entry["id"]
	var short := id.get_slice(".", 1)
	var card := Kit.panel("CardPanel")
	var col := Kit.vbox(UiTokens.SPACE["xs"])
	card.add_child(col)
	var name_label := _wide(StoryText.quest_name(id), "SubheadingLabel")
	UiProbe.register("journal.quest." + short, name_label)
	col.add_child(name_label)
	var meta := StoryText.quest_meta(entry)
	if tracked:
		meta = _t("ui.common.separator").join([_t("ui.journal.tracked"), meta])
	var meta_label := _wide(meta, "MutedLabel")
	UiProbe.register("journal.quest.%s.state" % short, meta_label)
	col.add_child(meta_label)
	var desc_key := str(Content.get_entity(id).get("desc_key", ""))
	if desc_key != "":
		col.add_child(_wide(_t(desc_key)))
	for o: Dictionary in entry["objectives"]:
		if not o["visible"]:
			continue
		var line := _wide(QuestTracker.objective_line(o), "MutedLabel" if o["done"] else "")
		UiProbe.register("journal.quest.%s.objective.%s" % [short, o["id"]], line)
		col.add_child(line)
	if entry["state"] == "completed":
		col.add_child(
			_wide(
				_t("ui.journal.return_to").format(
					{"npc": StoryText.speaker_name(str(entry["giver"]))}
				),
				"LeadLabel"
			)
		)
	if entry["state"] != "turned_in":
		var rewards := StoryText.rewards_text(GameState.content_api.quest_rewards(id))
		if rewards != "":
			var r := _wide(_t("ui.dialogue.rewards").format({"rewards": rewards}), "MutedLabel")
			UiProbe.register("journal.quest.%s.rewards" % short, r)
			col.add_child(r)
	return card


# --- Contracts ----------------------------------------------------------------------


func build_contracts(into: VBoxContainer, news: Array = []) -> void:
	into.add_child(_wide(_t("ui.contracts.title"), "SubheadingLabel"))
	into.add_child(_wide(_t("ui.contracts.renews"), "MutedLabel"))
	for line: String in news:
		var l := _wide(line, "LeadLabel")
		UiProbe.register("journal.contracts.news", l)
		into.add_child(l)
	var cards := GameState.content_api.contracts()
	if cards.is_empty():
		into.add_child(_wide(_t("ui.contracts.empty"), "MutedLabel"))
	for c: Dictionary in cards:
		into.add_child(_contract_card(c))
	into.add_child(_wide(_t("ui.contracts.offline_note"), "MutedLabel"))


func _contract_card(c: Dictionary) -> Control:
	var id: String = c["id"]
	var short := id.get_slice(".", 1)
	var card := Kit.panel("CardPanel")
	var row := Kit.hbox()
	card.add_child(row)
	var col := Kit.vbox(UiTokens.SPACE["xs"])
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(_wide(Content.display_name(id), "LeadLabel"))
	var progress := _wide(_t(str(c["key"])).format({"n": int(c["count"])}), "")
	UiProbe.register("journal.contract.%s.progress" % short, progress)
	col.add_child(progress)
	col.add_child(_wide(_t("ui.contracts.reward").format(c["reward"]), "MutedLabel"))
	var box := Kit.vbox(UiTokens.SPACE["xs"])
	var claimed: bool = c["state"] == "claimed"
	var b := _button(
		_t("ui.contracts.claimed") if claimed else _t("ui.contracts.claim"),
		true,
		"journal.contract.%s.claim" % short
	)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	var reason_text := contract_reason(c)
	b.disabled = reason_text != ""
	b.tooltip_text = reason_text
	var reason := Kit.label(reason_text, "MutedLabel", true)
	reason.visible = reason_text != "" and not claimed
	reason.custom_minimum_size = Vector2(180, 0)
	UiProbe.register("journal.contract.%s.claim_reason" % short, reason)
	b.pressed.connect(_claim.bind(id))
	box.add_child(b)
	box.add_child(reason)
	row.add_child(box)
	return card


## Why « Récupérer » is disabled ("" when it is not).
static func contract_reason(c: Dictionary) -> String:
	match str(c["state"]):
		"completed":
			return ""
		"claimed":
			return StoryText.tr_key("ui.contracts.claimed")
	return GameState.reason_text({"error": "error.contract.not_completed"})


func _claim(id: String) -> void:
	var r := GameState.content_api.claim_contract(id)
	if r["ok"]:
		SaveService.save_now()
		flash(_status, tr("ui.contracts.reward").format(r["reward"]))
	else:
		flash(_status, GameState.reason_text(r), true)


# --- Bestiary -----------------------------------------------------------------------


static func build_bestiary(into: VBoxContainer) -> void:
	var entries := GameState.content_api.bestiary()
	if entries.is_empty():
		into.add_child(_wide(_t("ui.journal.bestiary_empty"), "MutedLabel"))
		return
	for e: Dictionary in entries:
		into.add_child(_bestiary_card(e))


static func _bestiary_card(e: Dictionary) -> Control:
	var id: String = e["enemy_id"]
	var short := id.get_slice(".", 1)
	var enemy := Content.get_entity(id)
	var tier := int(e["tier"])
	var card := Kit.panel("CardPanel")
	var col := Kit.vbox(UiTokens.SPACE["xs"])
	card.add_child(col)
	var title := _wide(
		Content.display_name(id) if tier >= 1 else _t("ui.bestiary.unknown"), "SubheadingLabel"
	)
	UiProbe.register("journal.bestiary.%s.name" % short, title)
	col.add_child(title)
	var tier_text := (
		_t("ui.journal.bestiary_tier").format(
			{"tier": tier, "label": _t("ui.bestiary.tier_%d" % tier)}
		)
		if tier >= 1
		else _t("ui.journal.bestiary_locked")
	)
	var tier_label := _wide(
		_t("ui.common.separator").join(
			[tier_text, _t("ui.bestiary.victories").format({"count": int(e["victories"])})]
		),
		"MutedLabel"
	)
	UiProbe.register("journal.bestiary.%s.tier" % short, tier_label)
	col.add_child(tier_label)
	var next := _wide(StoryText.next_tier_text(e), "MutedLabel")
	UiProbe.register("journal.bestiary.%s.next" % short, next)
	col.add_child(next)
	if tier >= 1:
		col.add_child(_wide(_t(str(enemy.get("desc_key", "")))))
		var lore := id + ".lore"
		if TranslationServer.translate(lore) != lore:
			col.add_child(_wide(_t(lore), "MutedLabel"))
	if tier >= 2:
		var lines := []
		for element: String in StoryText.ELEMENTS:
			lines.append(StoryText.affinity_line(enemy, element))
		var aff := _wide(_t("ui.common.separator").join(lines))
		UiProbe.register("journal.bestiary.%s.affinities" % short, aff)
		col.add_child(aff)
		var abilities := []
		for ability in enemy.get("abilities", []):
			abilities.append(Content.display_name(str(ability)))
		if not abilities.is_empty():
			col.add_child(
				_wide(
					_t("ui.journal.abilities").format({"list": ", ".join(abilities)}), "MutedLabel"
				)
			)
		var tip := id + ".tip"
		if TranslationServer.translate(tip) != tip:
			col.add_child(_wide(_t(tip), "LeadLabel"))
	if tier >= 3:
		var s: Dictionary = enemy.get("stats_l1", {})
		var stats := _wide(
			(
				_t("ui.journal.stats")
				. format(
					{
						"hp": int(s.get("hp", 0)),
						"power": int(s.get("power", 0)),
						"defense": roundi(float(s.get("def_ratio", 0.0)) * 100.0),
						"barrier": roundi(float(s.get("barrier_ratio", 0.0)) * 100.0),
						"aggro": ProgressionText.number(float(s.get("aggro_m", 0.0))),
					}
				)
			),
			"MutedLabel"
		)
		UiProbe.register("journal.bestiary.%s.stats" % short, stats)
		col.add_child(stats)
	return card


# --- Discoveries --------------------------------------------------------------------


static func build_discoveries(into: VBoxContainer) -> void:
	var api := GameState.content_api
	var region: String = GameState.data["world"]["region_id"]
	var any := false
	for place: String in Content.get_entity(region).get("locations", []):
		var counts := api.discovery_counts(place)
		if int(counts.get("total", 0)) == 0:
			continue
		if GameState.location_status(place) == WorldRules.HIDDEN:
			continue
		any = true
		var short := place.get_slice(".", 1)
		var head := Kit.hbox()
		var name_label := _wide(Content.display_name(place), "SubheadingLabel")
		head.add_child(name_label)
		var count := Kit.label(_t("ui.discovery.count").format(counts), "NumberLabel")
		UiProbe.register("journal.discoveries.%s.count" % short, count)
		head.add_child(count)
		into.add_child(head)
		for id in Content.get_entity(place).get("discoveries", []):
			var d := Content.get_entity(str(id))
			if not d.get("counts_for_location", false):
				continue
			into.add_child(_discovery_line(str(id)))
	if not any:
		into.add_child(_wide(_t("ui.journal.discoveries_empty"), "MutedLabel"))


static func _discovery_line(id: String) -> Control:
	var found: bool = GameState.data["progress"]["discoveries"].has(id)
	var card := Kit.panel("CardPanel")
	var col := Kit.vbox(UiTokens.SPACE["xs"])
	card.add_child(col)
	var title := _wide(
		Content.display_name(id) if found else _t("ui.bestiary.unknown"), "LeadLabel"
	)
	UiProbe.register("journal.discovery." + id.get_slice(".", 1), title)
	col.add_child(title)
	var lore := id + ".lore"
	if found and TranslationServer.translate(lore) != lore:
		col.add_child(_wide(_t(lore), "MutedLabel"))
	elif not found:
		col.add_child(_wide(_t("ui.journal.discovery_hidden"), "MutedLabel"))
	return card
