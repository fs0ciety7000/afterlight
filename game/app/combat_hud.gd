class_name CombatHud
extends Control
## Combat HUD (DESIGN.md "HUD combat"): Fern's bars, spells with cooldowns,
## speed and pause, enemy and boss bars, log and the end panel. It reads the
## sim snapshot and sends commands through the CombatView; no rules here.

signal leave_requested(victory: bool)

const LOG_LINES := 60
const LOG_TYPES := ["damage_dealt", "spell_cast", "status_applied"]
const NEWLINE := "\n"

var view: CombatView
var camera: Camera3D
var _hp: ProgressBar
var _mana: ProgressBar
var _ult: ProgressBar
var _hp_text: Label
var _spells := {}
var _speed: Button
var _pause: Button
var _boss_box: VBoxContainer
var _boss_bar: ProgressBar
var _boss_name: Label
var _enemy_bars := {}
var _log: RichTextLabel
var _log_lines: Array[Dictionary] = []
var _log_filter := "all"
var _toast: Label
var _toast_until := 0
var _consumables: HBoxContainer
var _result: PanelContainer


func bind(combat: CombatView, cam: Camera3D) -> void:
	view = combat
	camera = cam
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.sim_event.connect(_on_event)
	view.finished.connect(_on_finished)
	_build()


func _build() -> void:
	var margin := 24.0
	# Bottom-left: Fern's bars.
	var bars := Kit.panel("CardPanel")
	var col := Kit.vbox(UiTokens.SPACE["xs"])
	bars.add_child(col)
	_hp_text = Kit.label("", "NumberLabel")
	col.add_child(_hp_text)
	_hp = _bar(Color("#7fae6e"), 220)
	_mana = _bar(UiTokens.NIGHT["mana"], 220)
	_ult = _bar(UiTokens.NIGHT["accent"], 220)
	col.add_child(_hp)
	col.add_child(_mana)
	col.add_child(_ult)
	UiProbe.register("combat.hp", _hp_text)
	add_child(bars)
	bars.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, margin
	)

	# Bottom-right: spells (an arc on touch screens, a row otherwise).
	var row := Kit.hbox(UiTokens.SPACE["md"])
	row.alignment = BoxContainer.ALIGNMENT_END
	var snap := view.snapshot()
	var hero := _hero(snap)
	var keys := ["1", "2", "3"]
	var spells: Array = hero.get("spells", [])
	for i in spells.size():
		row.add_child(_spell_button(spells[i], keys[i] if i < keys.size() else "", false))
	if str(hero.get("ultimate", "")) != "":
		row.add_child(_spell_button(hero["ultimate"], "R", true))
	add_child(row)
	row.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, margin
	)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_consumables = Kit.hbox()
	for id in hero.get("consumables", {}):
		var b := Kit.button(
			Content.display_name(id), false, "combat.consumable." + str(id).get_slice(".", 1)
		)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(
			func() -> void: view.command({"type": "use_consumable", "consumable": id})
		)
		_consumables.add_child(b)
	add_child(_consumables)
	_consumables.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, margin
	)
	_consumables.grow_horizontal = Control.GROW_DIRECTION_BOTH

	# Top-right: speed and pause.
	var ctl := Kit.hbox()
	_speed = Kit.button("", false, "combat.speed")
	_speed.focus_mode = Control.FOCUS_NONE
	_speed.pressed.connect(
		func() -> void:
			view.cycle_speed()
			_refresh_controls()
	)
	_pause = Kit.button("", false, "combat.pause")
	_pause.focus_mode = Control.FOCUS_NONE
	_pause.pressed.connect(toggle_pause)
	ctl.add_child(_speed)
	ctl.add_child(_pause)
	add_child(ctl)
	ctl.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, margin
	)
	ctl.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# Top-centre: boss bar with phase marks.
	_boss_box = Kit.vbox(UiTokens.SPACE["xs"])
	_boss_name = Kit.label("", "SubheadingLabel")
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.add_theme_color_override("font_color", UiTokens.NIGHT["ink"])
	_boss_bar = _bar(Color("#c4553f"), 520)
	_boss_box.add_child(_boss_name)
	_boss_box.add_child(_boss_bar)
	_boss_box.visible = false
	UiProbe.register("combat.boss_bar", _boss_name)
	add_child(_boss_box)
	_boss_box.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, margin
	)
	_boss_box.grow_horizontal = Control.GROW_DIRECTION_BOTH

	# Left: combat log with a source filter.
	var log_panel := Kit.panel("CardPanel")
	log_panel.custom_minimum_size = Vector2(320, 200)
	var log_col := Kit.vbox(UiTokens.SPACE["xs"])
	log_panel.add_child(log_col)
	var head := Kit.hbox()
	head.add_child(Kit.label(tr("ui.combat.log"), "SubheadingLabel"))
	var filter := OptionButton.new()
	for key in ["ui.combat.log_all", "ui.combat.log_party", "ui.combat.log_enemies"]:
		filter.add_item(tr(key))
	filter.item_selected.connect(
		func(i: int) -> void:
			_log_filter = ["all", "party", "enemies"][i]
			_render_log()
	)
	filter.focus_mode = Control.FOCUS_NONE
	UiProbe.register("combat.log_filter", filter)
	head.add_child(filter)
	log_col.add_child(head)
	_log = RichTextLabel.new()
	_log.fit_content = false
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(300, 150)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiProbe.register("combat.log", _log)
	log_col.add_child(_log)
	add_child(log_panel)
	log_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, margin
	)
	log_panel.visible = get_viewport_rect().size.x >= 1100.0

	_toast = Kit.label("", "LeadLabel")
	_toast.add_theme_color_override("font_color", UiTokens.NIGHT["danger"])
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.position.y += 140
	_toast.visible = false
	UiProbe.register("combat.toast", _toast)
	add_child(_toast)
	_refresh_controls()


func _bar(color: Color, width: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(width, 10)
	b.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	b.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.07, 0.1, 0.85)
	bg.set_corner_radius_all(2)
	b.add_theme_stylebox_override("background", bg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _spell_button(id: String, key: String, ultimate: bool) -> SpellButton:
	var b := SpellButton.new()
	b.setup(id, key, ultimate)
	b.pressed.connect(func() -> void: cast(id))
	UiProbe.register("combat.spell." + id.get_slice(".", 1), b)
	_spells[id] = b
	return b


func cast(spell_id: String) -> void:
	view.command({"type": "cast", "spell": spell_id})


func cast_index(i: int) -> void:
	var hero := _hero(view.snapshot())
	var spells: Array = hero.get("spells", [])
	if i < spells.size():
		cast(spells[i])


func cast_ultimate() -> void:
	var hero := _hero(view.snapshot())
	if str(hero.get("ultimate", "")) != "":
		cast(hero["ultimate"])


func toggle_pause() -> void:
	view.paused = not view.paused
	_refresh_controls()


func _refresh_controls() -> void:
	_speed.text = tr("ui.combat.speed").format({"x": view.speed()})
	_pause.text = tr("ui.combat.resume") if view.paused else tr("ui.combat.pause")
	UiProbe.world["combat_speed"] = view.speed()
	UiProbe.world["combat_paused"] = view.paused


func _process(_delta: float) -> void:
	if view == null:
		return
	var snap := view.snapshot()
	if snap.is_empty():
		return
	var hero := _hero(snap)
	if not hero.is_empty():
		_hp.max_value = hero["max_hp"]
		_hp.value = hero["hp"]
		_mana.max_value = maxf(hero["max_mana"], 1.0)
		_mana.value = hero["mana"]
		_ult.max_value = maxf(hero.get("ult_charge_max", 100.0), 1.0)
		_ult.value = hero.get("ult_charge", 0.0)
		_hp_text.text = tr("ui.combat.hp").format(
			{"hp": int(hero["hp"]), "max": int(hero["max_hp"])}
		)
		for id in _spells:
			var b: SpellButton = _spells[id]
			b.cooldown_s = float(hero["cooldowns"].get(id, 0.0))
			b.cooldown_total = maxf(b.cooldown_total, b.cooldown_s)
			if b.cooldown_s <= 0.0:
				b.cooldown_total = 0.0
			if id == hero.get("ultimate", ""):
				b.charge_ratio = (
					float(hero["ult_charge"]) / maxf(float(hero["ult_charge_max"]), 1.0)
				)
			b.queue_redraw()
	_update_enemy_bars(snap)
	if _toast.visible and Time.get_ticks_msec() > _toast_until:
		_toast.visible = false
	UiProbe.world["combat_ticks"] = view.ticks
	UiProbe.world["combat_snapshot"] = {
		"hero_hp": hero.get("hp", 0),
		"hero_mana": hero.get("mana", 0),
		"cooldowns": hero.get("cooldowns", {}),
		"queued": hero.get("queued", ""),
		"enemies":
		(
			snap["units"]
			. filter(func(u: Dictionary) -> bool: return u["side"] == "enemy" and u["alive"])
			. size()
		),
	}


func _update_enemy_bars(snap: Dictionary) -> void:
	for u in snap["units"]:
		if u["side"] != "enemy":
			continue
		var uid: String = u["uid"]
		if u.get("is_boss", false):
			_boss_box.visible = u["alive"]
			_boss_name.text = Content.display_name(u["def_id"])
			_boss_bar.max_value = u["max_hp"]
			_boss_bar.value = u["hp"]
			continue
		if not _enemy_bars.has(uid):
			var b := _bar(Color("#c4553f"), 72)
			b.custom_minimum_size = Vector2(72, 7)
			add_child(b)
			_enemy_bars[uid] = b
			UiProbe.register("combat.enemy." + uid, b)
		var bar: ProgressBar = _enemy_bars[uid]
		bar.visible = u["alive"]
		bar.max_value = u["max_hp"]
		bar.value = u["hp"]
		var node := view.actor(uid)
		if node and camera and not camera.is_position_behind(node.global_position):
			var head := node.global_position + Vector3.UP * 2.2
			var sp := (
				get_viewport().get_canvas_transform().affine_inverse()
				* camera.unproject_position(head)
			)
			bar.position = sp - Vector2(36, 0)


func _on_event(e: Dictionary) -> void:
	match e["type"]:
		"command_rejected":
			_show_toast(tr("ui.combat.reject." + str(e["reason"])))
		"boss_phase_changed":
			_show_toast(tr("ui.combat.boss_phase").format({"phase": e["phase"]}))
	if e["type"] in LOG_TYPES:
		_log_lines.append(e)
		if _log_lines.size() > LOG_LINES:
			_log_lines.pop_front()
		_render_log()


func _render_log() -> void:
	var lines := PackedStringArray()
	for e in _log_lines:
		var source: String = e.get("source", e.get("unit", ""))
		var is_party := source.begins_with("p")
		if _log_filter == "party" and not is_party:
			continue
		if _log_filter == "enemies" and is_party:
			continue
		lines.append(_log_text(e))
	_log.text = NEWLINE.join(lines)


func _log_text(e: Dictionary) -> String:
	var who := func(uid: String) -> String:
		var u: Dictionary = {}
		for x in view.snapshot().get("units", []):
			if x["uid"] == uid:
				u = x
		return Content.display_name(u.get("def_id", uid)) if not u.is_empty() else uid
	match e["type"]:
		"damage_dealt":
			var key := "ui.combat.log_crit" if e.get("crit", false) else "ui.combat.log_damage"
			return tr(key).format(
				{
					"source": who.call(e["source"]),
					"target": who.call(e["target"]),
					"amount": e["amount"]
				}
			)
		"spell_cast":
			return tr("ui.combat.log_cast").format(
				{"source": who.call(e["unit"]), "spell": Content.display_name(e["spell"])}
			)
		"status_applied":
			return tr("ui.combat.log_status").format(
				{"target": who.call(e["target"]), "status": Content.display_name(e["status"])}
			)
	return ""


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_until = Time.get_ticks_msec() + 1600
	UiProbe.note(text)


func _on_finished(e: Dictionary) -> void:
	var victory: bool = e.get("result", "") == "victory"
	var summary := GameState.apply_combat_result(e) if victory else {}
	_result = Kit.panel()
	var col := Kit.vbox()
	_result.add_child(col)
	var title := Kit.label(
		tr("ui.combat.victory") if victory else tr("ui.combat.defeat"), "TitleLabel"
	)
	UiProbe.register("combat.result_title", title)
	col.add_child(title)
	if victory:
		col.add_child(
			Kit.label(
				tr("ui.combat.rewards").format({"xp": summary["xp"], "gold": summary["gold"]}),
				"LeadLabel"
			)
		)
		if summary["levels_gained"] > 0:
			if view.vfx:
				view.vfx.play("vfx.level_up", {"caster": view.actor("p3")})
			col.add_child(
				Kit.label(
					tr("ui.combat.level_up").format({"level": summary["level"]}), "SubheadingLabel"
				)
			)
	else:
		col.add_child(Kit.label(tr("ui.combat.defeat_body"), "", true))
	var ok := Kit.button(tr("ui.combat.continue"), true, "combat.continue")
	ok.pressed.connect(func() -> void: leave_requested.emit(victory))
	col.add_child(ok)
	add_child(_result)
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_result.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result.grow_vertical = Control.GROW_DIRECTION_BOTH
	ok.call_deferred("grab_focus")


static func _hero(snap: Dictionary) -> Dictionary:
	for u in snap.get("units", []):
		if u["side"] == "party":
			return u
	return {}
