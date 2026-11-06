extends Screen
## Chasse hors ligne (GDD §12, ROADMAP 5.5): the known encounters of the
## region, grouped by place, each with its quote (clear time, XP/h, gold/h,
## survival warning) and a « Choisir » button. An encounter that cannot be
## the offline hunt (elite, boss, never won, too slow) shows the reason under
## its disabled button. Opened from the world map (selected place first) or
## from the explore HUD (current place first).

var _location := ""
var _body: VBoxContainer
var _current: Label
var _status: Label
var _close: Button
var _refresh_queued := false
var _refocus_id := ""
var _scroll: ScrollContainer


func setup(params: Dictionary) -> void:
	_location = str(params.get("location", ""))


func _ready() -> void:
	if _location == "" and GameState.has_game():
		_location = GameState.data["world"]["location_id"]
	add_backdrop(0.8)
	var narrow := is_narrow()
	var panel := Kit.panel()
	add_child(Kit.margin(panel, narrow))
	var col := Kit.vbox(UiTokens.SPACE["sm"])
	panel.add_child(col)

	var head := Kit.hbox()
	var title := Kit.label(tr("ui.hunts.title"), "HeadingLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiProbe.register("hunts.title", title)
	head.add_child(title)
	_close = Kit.button(tr("ui.hunts.close"), false, "hunts.close")
	_close.custom_minimum_size.y = UiTokens.at_least_css(UiTokens.TOUCH_TARGET)
	_close.pressed.connect(_on_close)
	head.add_child(_close)
	col.add_child(head)
	var intro := (
		Kit
		. label(
			(
				tr("ui.hunts.intro")
				. format(
					{
						"hours": BalanceOffline.OFFLINE_CAP_S / 3600,
						"efficiency":
						roundi(OfflineCalc.efficiency(GameState.data, Content.index()) * 100.0),
					}
				)
			),
			"MutedLabel",
			true
		)
	)
	col.add_child(intro)
	_current = Kit.label("", "LeadLabel", true)
	UiProbe.register("hunts.current", _current)
	col.add_child(_current)
	col.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The focused choice (the first one enabled on open) is scrolled into view.
	scroll.follow_focus = true
	_body = Kit.vbox(UiTokens.SPACE["md"])
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	col.add_child(scroll)
	_status = Kit.label("", "MutedLabel", true)
	UiProbe.register("hunts.status", _status)
	col.add_child(_status)

	GameState.changed.connect(_queue_refresh)
	_refresh()


## Places of the region the player knows (not under the fog) that hold
## encounters, `first` leading, each with its encounters by level.
static func known_hunts(first: String) -> Array[Dictionary]:
	var content := Content.index()
	var region: String = GameState.data["world"]["region_id"]
	var by_place := {}
	for id: String in content:
		var e: Dictionary = content[id]
		if e.get("_type", "") == "encounter":
			var place := str(e.get("location", ""))
			if not by_place.has(place):
				by_place[place] = []
			by_place[place].append(id)
	var out: Array[Dictionary] = []
	for place: String in Content.get_entity(region).get("locations", []):
		if not by_place.has(place) or GameState.location_status(place) == WorldRules.HIDDEN:
			continue
		var ids: Array = by_place[place]
		ids.sort_custom(
			func(a: String, b: String) -> bool:
				var la := int(content[a].get("level", 0))
				var lb := int(content[b].get("level", 0))
				return la < lb or (la == lb and a < b)
		)
		var entry := {"location": place, "encounters": ids}
		if place == first:
			out.push_front(entry)
		else:
			out.append(entry)
	return out


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh")


func _refresh() -> void:
	_refresh_queued = false
	if not GameState.has_game() or not is_inside_tree():
		return
	var hunt := GameState.offline_hunt()
	_current.text = (
		tr("ui.hunts.current").format({"encounter": Content.display_name(hunt)})
		if hunt != ""
		else tr("ui.hunts.current_none")
	)
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var groups := known_hunts(_location)
	if groups.is_empty():
		_body.add_child(Kit.label(tr("ui.hunts.empty"), "MutedLabel", true))
	for group in groups:
		var place: String = group["location"]
		var heading := Kit.label(Content.display_name(place), "SubheadingLabel", true)
		UiProbe.register("hunts.place." + place.get_slice(".", 1), heading)
		_body.add_child(heading)
		for id: String in group["encounters"]:
			_body.add_child(_card(id, hunt))
	var c: Control = UiProbe._controls.get(_refocus_id) if _refocus_id != "" else null
	if c and c.is_inside_tree() and not (c as Button).disabled:
		_focus_after_layout(c)
	elif _refocus_id != "" or get_viewport().gui_get_focus_owner() == null:
		# The list was rebuilt under the focus: back to the first choice.
		_focus_after_layout(null)
	_refocus_id = ""


## Focus only once the rebuilt list has its layout, so the scroll follows the
## real position of the control (not the one of the freed cards).
func _focus_after_layout(c: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if c == null:
		grab_initial_focus()
		c = get_viewport().gui_get_focus_owner()
	elif is_instance_valid(c) and c.is_inside_tree():
		c.grab_focus()
	if is_instance_valid(c) and c.is_inside_tree() and _scroll.is_ancestor_of(c):
		_scroll.ensure_control_visible(c)


## One encounter: name, kind and level, its quote, and the choose button
## (disabled with its reason when the quote refuses).
func _card(id: String, hunt: String) -> Control:
	var short := id.get_slice(".", 1)
	var e := Content.get_entity(id)
	var quote := GameState.offline_hunt_quote(id)
	var card := Kit.panel("CardPanel")
	var row := Kit.hbox()
	card.add_child(row)
	var text := Kit.vbox(UiTokens.SPACE["xs"])
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Kit.label(Content.display_name(id), "LeadLabel", true)
	UiProbe.register("hunts.name." + short, name_label)
	text.add_child(name_label)
	var kind := str(e.get("kind", "normal"))
	var tags := PackedStringArray(
		[tr("ui.hunts.kind." + kind), tr("ui.hunts.level").format({"level": e.get("level", 1)})]
	)
	text.add_child(Kit.label(tr("ui.common.separator").join(tags), "MutedLabel"))
	if quote["ok"]:
		var stats := (
			Kit
			. label(
				(
					tr("ui.hunts.stats")
					. format(
						{
							"seconds": ceili(float(quote["clear_time_s"])),
							"xp": quote["xp_per_hour"],
							"gold": quote["gold_per_hour"],
						}
					)
				),
				"NumberLabel",
				true
			)
		)
		UiProbe.register("hunts.stats." + short, stats)
		text.add_child(stats)
		var warning := Kit.label("", "ErrorLabel", true)
		if str(quote.get("warning", "")) != "":
			warning.text = GameState.reason_text(
				{"key": quote["warning"], "params": quote.get("warning_params", {})}
			)
		warning.visible = warning.text != ""
		UiProbe.register("hunts.warning." + short, warning)
		text.add_child(warning)
	row.add_child(text)

	var box := Kit.vbox(UiTokens.SPACE["xs"])
	var is_current := id == hunt
	var b := Kit.button(
		tr("ui.hunts.chosen") if is_current else tr("ui.hunts.choose"),
		not is_current,
		"hunts.choose." + short
	)
	b.custom_minimum_size.y = UiTokens.at_least_css(UiTokens.TOUCH_TARGET)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.disabled = is_current or not quote["ok"]
	var reason := Kit.label("" if quote["ok"] else GameState.reason_text(quote), "MutedLabel", true)
	reason.visible = not quote["ok"]
	reason.custom_minimum_size = Vector2(minf(260.0, get_viewport_rect().size.x * 0.4), 0)
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.tooltip_text = reason.text
	UiProbe.register("hunts.choose." + short + "_reason", reason)
	b.pressed.connect(_choose.bind(id))
	box.add_child(b)
	box.add_child(reason)
	row.add_child(box)
	return card


func _choose(id: String) -> void:
	_refocus_id = "hunts.choose." + id.get_slice(".", 1)
	var r := GameState.set_offline_hunt(id)
	if r["ok"]:
		flash(_status, tr("ui.hunts.set").format({"encounter": Content.display_name(id)}))
	else:
		flash(_status, GameState.reason_text(r), true)


func _on_close() -> void:
	Router.back("explore")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_close()


func grab_initial_focus() -> void:
	for group in known_hunts(_location):
		for id: String in group["encounters"]:
			var c: Variant = UiProbe._controls.get("hunts.choose." + id.get_slice(".", 1))
			if is_instance_valid(c) and not (c as Button).disabled:
				(c as Button).grab_focus()
				return
	_close.grab_focus()
