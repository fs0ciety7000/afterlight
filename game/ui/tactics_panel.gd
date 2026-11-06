class_name TacticsPanel
extends Control
## `panel.tactics` (GDD §7.4, §17, decisions 23-27, owner answers 2-4): one
## row per setting (targeting, spells, consumables, mana reserve) with its
## options, a slider when the mode uses one, and the plain French sentence of
## what Fern will do, updated live. « Appliquer le conseil » shows the diff of
## the preset first, then applies it; « Rétablir les réglages par défaut ».
## No « Valider »: each change is saved at once (GameState.tactics).
##
## A modal over any screen (grimoire, explore, combat HUD). The actions sit in
## the header so they stay visible on short phone screens; the rows scroll.
## UiProbe: tactics.panel, tactics.title, tactics.close, tactics.reset (+
## _reason), tactics.apply_preset (+ _reason), tactics.hint, tactics.status,
## tactics.diff, tactics.diff_confirm, tactics.diff_cancel, and per row
## (`short` = targeting, mana_reserve or the id's suffix): tactics.row.<short>,
## tactics.name.<short>, tactics.say.<short>, tactics.opt.<short>.<mode>,
## tactics.slider.<short>, tactics.value.<short>.

## A setting changed (mid-combat, the HUD forwards it to the running fight).
signal changed
signal closed

const MAX_WIDTH := 1040.0
## Same breakpoint as the screens (Screen.NARROW_WIDTH).
const NARROW_WIDTH := 1000.0

## Options: {focus: row id to scroll to, preset: preset id (default: the
## leader's), show_diff: open on the preset's diff, live: a fight is running}.
var options: Dictionary = {}
var _api: TacticsApi
var _narrow := false
var _preset := ""
var _scroll: ScrollContainer
var _rows_box: VBoxContainer
var _rows := {}
var _row_ids: Array = []
var _status: Label
var _reset: Button
var _reset_reason: Label
var _apply: Button
var _apply_reason: Label
var _diff_box: PanelContainer
var _diff_text: Label
var _diff_confirm: Button
var _close: Button
## True while _sync writes the sliders (their range clamps emit value_changed).
var _syncing := false


## Opens the panel over `host` (full rect) and returns it.
static func open(host: Control, opts: Dictionary = {}) -> TacticsPanel:
	var p := TacticsPanel.new()
	p.options = opts
	host.add_child(p)
	return p


## The tactics preset offered to the leader ("" if none).
static func preset_for_leader() -> String:
	if not GameState.has_game():
		return ""
	var leader := str(GameState.data["party"][0])
	var ids := []
	var index: Dictionary = Content.index()
	for id: String in index:
		var e: Dictionary = index[id]
		if e.get("_type", "") == "tactics_preset" and str(e.get("character", leader)) == leader:
			ids.append(id)
	ids.sort()
	return ids[0] if not ids.is_empty() else ""


## Short probe suffix of a row id (« spell.defensive_barrier » → defensive_barrier).
static func short_id(row_id: String) -> String:
	return row_id.get_slice(".", 1) if row_id.contains(".") else row_id


## Label of a row's current option, without « (par défaut) » (grimoire badge).
static func current_label(row: Dictionary) -> String:
	for o: Dictionary in row.get("options", []):
		if o["id"] == row["current"]:
			return TranslationServer.translate(o["label_key"]).format(o["label_params"])
	if not row.get("param", {}).is_empty():
		return str(row["param"]["label"])
	return ""


func _ready() -> void:
	_api = GameState.tactics
	_narrow = get_viewport_rect().size.x < NARROW_WIDTH
	_preset = str(options.get("preset", ""))
	if _preset == "":
		_preset = preset_for_leader()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := Kit.panel("ScrimPanel")
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	_build()
	_sync()
	if bool(options.get("show_diff", false)):
		_show_diff()
	call_deferred("_initial_focus")


func _build() -> void:
	var vw := get_viewport_rect().size.x
	var edge: float = UiTokens.SPACE["lg"] if _narrow else UiTokens.SPACE["xl"]
	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var side := maxf(edge, (vw - MAX_WIDTH) / 2.0)
	frame.add_theme_constant_override("margin_left", int(side))
	frame.add_theme_constant_override("margin_right", int(side))
	frame.add_theme_constant_override("margin_top", int(edge))
	frame.add_theme_constant_override("margin_bottom", int(edge))
	add_child(frame)
	var card := Kit.panel()
	UiProbe.register("tactics.panel", card)
	frame.add_child(card)
	var col := Kit.vbox(UiTokens.SPACE["sm"])
	card.add_child(col)

	# Header: title and every action, first thing on screen (phones).
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", UiTokens.SPACE["md"])
	head.add_theme_constant_override("v_separation", UiTokens.SPACE["sm"])
	var title := Kit.label(tr("ui.tactics.title"), "HeadingLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiProbe.register("tactics.title", title)
	head.add_child(title)
	_apply = _button(tr("ui.tactics.apply_preset"), true, "tactics.apply_preset")
	_apply.pressed.connect(_show_diff)
	_apply.visible = _preset != ""
	head.add_child(_apply)
	_reset = _button(tr("ui.tactics.reset"), false, "tactics.reset")
	_reset.pressed.connect(_on_reset)
	head.add_child(_reset)
	_close = _button(tr("ui.tactics.close"), false, "tactics.close")
	_close.pressed.connect(close)
	head.add_child(_close)
	col.add_child(head)
	# Reasons of the disabled actions (DESIGN.md: disabled = reason shown).
	_apply_reason = Kit.label("", "MutedLabel", true)
	UiProbe.register("tactics.apply_preset_reason", _apply_reason)
	col.add_child(_apply_reason)
	_reset_reason = Kit.label("", "MutedLabel", true)
	UiProbe.register("tactics.reset_reason", _reset_reason)
	col.add_child(_reset_reason)

	# The preset's diff, shown before applying it.
	_diff_box = Kit.panel("CardPanel")
	_diff_box.visible = false
	var diff_col := Kit.vbox(UiTokens.SPACE["sm"])
	_diff_box.add_child(diff_col)
	diff_col.add_child(Kit.label(tr("ui.tactics.diff_title"), "SubheadingLabel", true))
	_diff_text = Kit.label("", "", true)
	UiProbe.register("tactics.diff", _diff_text)
	diff_col.add_child(_diff_text)
	var diff_row := HFlowContainer.new()
	diff_row.add_theme_constant_override("h_separation", UiTokens.SPACE["sm"])
	diff_row.add_theme_constant_override("v_separation", UiTokens.SPACE["sm"])
	_diff_confirm = _button(tr("ui.tactics.confirm_preset"), true, "tactics.diff_confirm")
	_diff_confirm.pressed.connect(_on_apply_preset)
	diff_row.add_child(_diff_confirm)
	var cancel := _button(tr("ui.tactics.cancel"), false, "tactics.diff_cancel")
	cancel.pressed.connect(_hide_diff)
	diff_row.add_child(cancel)
	diff_col.add_child(diff_row)
	col.add_child(_diff_box)

	var hint := Kit.label(
		tr("ui.tactics.live_hint" if bool(options.get("live", false)) else "ui.tactics.hint"),
		"MutedLabel",
		true
	)
	UiProbe.register("tactics.hint", hint)
	col.add_child(hint)
	_status = Kit.label("", "MutedLabel", true)
	UiProbe.register("tactics.status", _status)
	col.add_child(_status)
	col.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows_box = Kit.vbox(UiTokens.SPACE["lg"])
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows_box)
	col.add_child(_scroll)
	_build_rows()


func _button(text: String, primary: bool, probe_id: String) -> Button:
	var b := Kit.button(text, primary, probe_id)
	b.custom_minimum_size.y = UiTokens.at_least_css(UiTokens.TOUCH_TARGET)
	return b


func _build_rows() -> void:
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_rows.clear()
	_row_ids.clear()
	var view := _api.tactics_view()
	for row: Dictionary in view.get("rows", []):
		_row_ids.append(row["id"])
		_rows_box.add_child(_make_row(row))
		_rows_box.add_child(HSeparator.new())


## One setting: icon and name, the sentence, the options (a segmented row on
## wide screens, a list on narrow ones) and the slider when the mode uses one.
func _make_row(row: Dictionary) -> Control:
	var id: String = row["id"]
	var short := short_id(id)
	var parts := {"options": {}}
	var box: BoxContainer = (
		Kit.vbox(UiTokens.SPACE["sm"]) if _narrow else Kit.hbox(UiTokens.SPACE["xl"])
	)
	UiProbe.register("tactics.row." + short, box)
	var text := Kit.vbox(UiTokens.SPACE["xs"])
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := Kit.hbox(UiTokens.SPACE["sm"])
	var icon := GameIcons.for_id(id) if id.contains(".") else null
	if icon:
		var tex := TextureRect.new()
		tex.texture = icon
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(32, 32)
		head.add_child(tex)
	var name_label := Kit.label(str(row["name"]), "SubheadingLabel", true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiProbe.register("tactics.name." + short, name_label)
	head.add_child(name_label)
	text.add_child(head)
	var say := Kit.label("", "LeadLabel", true)
	UiProbe.register("tactics.say." + short, say)
	text.add_child(say)
	parts["say"] = say
	box.add_child(text)

	var controls := Kit.vbox(UiTokens.SPACE["sm"])
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.size_flags_stretch_ratio = 1.4
	if not (row["options"] as Array).is_empty():
		var opts: Container
		if _narrow:
			opts = Kit.vbox(UiTokens.SPACE["xs"])
		else:
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", UiTokens.SPACE["xs"])
			flow.add_theme_constant_override("v_separation", UiTokens.SPACE["xs"])
			opts = flow
		for o: Dictionary in row["options"]:
			var mode := str(o["id"])
			var b := _button(str(o["label"]), false, "tactics.opt.%s.%s" % [short, mode])
			b.pressed.connect(_on_option.bind(id, mode))
			opts.add_child(b)
			parts["options"][mode] = b
		controls.add_child(opts)
		parts["choices"] = opts
	# The slider (Barrier HP, Salve enemies, mana reserve), hidden when unused.
	var slider_row := Kit.hbox(UiTokens.SPACE["md"])
	var value := Kit.label("", "NumberLabel")
	value.custom_minimum_size.x = 96
	UiProbe.register("tactics.value." + short, value)
	slider_row.add_child(value)
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = UiTokens.at_least_css(UiTokens.TOUCH_TARGET)
	slider.focus_mode = Control.FOCUS_ALL
	UiProbe.register("tactics.slider." + short, slider)
	slider.value_changed.connect(_on_slider.bind(id))
	slider_row.add_child(slider)
	controls.add_child(slider_row)
	parts["slider_row"] = slider_row
	parts["slider"] = slider
	parts["value"] = value
	box.add_child(controls)
	parts["box"] = box
	_rows[id] = parts
	return box


## Puts the current view into the rows (in place: a slider being dragged is
## kept) and refreshes the action buttons and their reasons.
func _sync() -> void:
	var view := _api.tactics_view()
	var rows: Array = view.get("rows", [])
	var ids := rows.map(func(r: Dictionary) -> String: return r["id"])
	if ids != _row_ids:
		_build_rows()
	_syncing = true
	var all_default := true
	for row: Dictionary in rows:
		var parts: Dictionary = _rows.get(row["id"], {})
		if parts.is_empty():
			continue
		all_default = all_default and bool(row["is_default"]) and _param_default(row)
		(parts["say"] as Label).text = str(row["say"])
		for mode: String in parts["options"]:
			var b: Button = parts["options"][mode]
			var on := str(row["current"]) == mode
			b.theme_type_variation = "PrimaryButton" if on else "SecondaryButton"
			b.tooltip_text = str(row["say"]) if on else ""
		var p: Dictionary = row["param"]
		(parts["slider_row"] as Control).visible = not p.is_empty()
		if not p.is_empty():
			var s: HSlider = parts["slider"]
			s.min_value = float(p["min"])
			s.max_value = float(p["max"])
			s.step = float(p["step"])
			s.set_value_no_signal(float(p["value"]))
			(parts["value"] as Label).text = str(p["label"])
	_syncing = false
	_reset.disabled = all_default
	_reset_reason.text = tr("ui.tactics.reset_none") if all_default else ""
	_reset_reason.visible = all_default
	_reset.tooltip_text = _reset_reason.text
	if _preset != "":
		var diff := _api.preset_diff(_preset)
		var none: bool = diff.get("ok", false) and (diff.get("lines", []) as Array).is_empty()
		var refused: bool = not diff.get("ok", false)
		_apply.disabled = none or refused
		_apply_reason.text = (
			tr("ui.tactics.diff_none") if none else (GameState.reason_text(diff) if refused else "")
		)
		_apply_reason.visible = _apply.disabled
		_apply.tooltip_text = _apply_reason.text
	else:
		_apply_reason.visible = false


func _param_default(row: Dictionary) -> bool:
	var p: Dictionary = row["param"]
	return p.is_empty() or absf(float(p["value"]) - float(p["default"])) < 0.000001


func _on_option(row_id: String, mode: String) -> void:
	_report(_api.set_tactic("", row_id, mode), tr("ui.tactics.saved"))


func _on_slider(value: float, row_id: String) -> void:
	if _syncing:
		return
	var view := _api.tactics_view()
	for row: Dictionary in view.get("rows", []):
		if row["id"] != row_id or (row["param"] as Dictionary).is_empty():
			continue
		var key := str(row["param"]["key"])
		var v: Variant = int(round(value)) if key == "min_enemies" else snappedf(value, 0.01)
		var r: Dictionary = (
			_api.set_tactic("", "mana_reserve", v)
			if row_id == "mana_reserve"
			else _api.set_tactic("", row_id, row["current"], {key: v})
		)
		_report(r, tr("ui.tactics.saved"))
		return


func _on_reset() -> void:
	_hide_diff()
	_report(_api.reset_tactics(), tr("ui.tactics.reset_done"))


## « Appliquer le conseil »: what it would change first.
func _show_diff() -> void:
	if _preset == "":
		return
	var diff := _api.preset_diff(_preset)
	if not diff.get("ok", false):
		_flash(GameState.reason_text(diff), true)
		return
	var lines := PackedStringArray()
	for line: Dictionary in diff.get("lines", []):
		lines.append(str(line["text"]))
	var joined := "\n".join(lines)
	_diff_text.text = joined if not lines.is_empty() else tr("ui.tactics.diff_none")
	_diff_confirm.visible = not lines.is_empty()
	_diff_box.visible = true
	UiProbe.world["tactics_diff"] = Array(lines)
	call_deferred("_focus", _diff_confirm if _diff_confirm.visible else _close)


func _focus(c: Control) -> void:
	if is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree():
		c.grab_focus()


func _hide_diff() -> void:
	_diff_box.visible = false
	UiProbe.world["tactics_diff"] = []


func _on_apply_preset() -> void:
	var r := _api.apply_preset(_preset)
	_hide_diff()
	_report(r, tr("ui.tactics.applied"))


func _report(r: Dictionary, success_text: String) -> void:
	if r.get("ok", false):
		_flash(success_text, false)
		changed.emit()
	else:
		_flash(GameState.reason_text(r), true)
	_sync()


func _flash(message: String, is_error: bool) -> void:
	_status.text = message
	_status.theme_type_variation = "ErrorLabel" if is_error else "MutedLabel"
	UiProbe.note(message)


func _initial_focus() -> void:
	if not is_inside_tree() or _diff_box.visible:
		return
	var focus_id := str(options.get("focus", ""))
	var target: Control = _close
	var row_id := (
		focus_id if _rows.has(focus_id) else (str(_row_ids[0]) if not _row_ids.is_empty() else "")
	)
	if row_id != "":
		var parts: Dictionary = _rows[row_id]
		for mode: String in parts["options"]:
			var b: Button = parts["options"][mode]
			if b.theme_type_variation == "PrimaryButton":
				target = b
		if target == _close and (parts["slider_row"] as Control).visible:
			target = parts["slider"]
	if is_instance_valid(target) and target.is_inside_tree():
		target.grab_focus()
	if focus_id != "" and _rows.has(focus_id):
		UiProbe.world["tactics_focus"] = focus_id
		# Once the rows are laid out, the asked row comes into view.
		await get_tree().process_frame
		# Its choices, not the whole row: a tall row would show its bottom.
		var parts: Dictionary = _rows.get(focus_id, {})
		var shown: Control = parts.get("choices", parts.get("box"))
		if is_inside_tree() and is_instance_valid(shown):
			_scroll.ensure_control_visible(shown)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _diff_box.visible:
			_hide_diff()
		else:
			close()


func close() -> void:
	UiProbe.world["tactics_open"] = false
	closed.emit()
	if get_parent():
		get_parent().remove_child(self)
	queue_free()


func _enter_tree() -> void:
	UiProbe.world["tactics_open"] = true
