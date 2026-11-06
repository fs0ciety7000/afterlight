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

	# Bottom-right: spells (an arc for the thumb on touch screens, a row otherwise).
	var snap := view.snapshot()
	var hero := _hero(snap)
	var keys := ["1", "2", "3"]
	var spells: Array = hero.get("spells", [])
	var buttons: Array[SpellButton] = []
	for i in spells.size():
		buttons.append(_spell_button(spells[i], keys[i] if i < keys.size() else "", false))
	var ult: SpellButton = null
	if str(hero.get("ultimate", "")) != "":
		ult = _spell_button(hero["ultimate"], "R", true)
	if DisplayServer.is_touchscreen_available():
		_layout_arc(buttons, ult, margin)
	else:
		var row := Kit.hbox(UiTokens.SPACE["md"])
		row.alignment = BoxContainer.ALIGNMENT_END
		for b in buttons:
			row.add_child(b)
		if ult:
			row.add_child(ult)
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
	var group := ButtonGroup.new()
	for mode in ["all", "party", "enemies"]:
		var b := Button.new()
		b.text = tr("ui.combat.log_" + mode)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = mode == "all"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, UiTokens.TOUCH_TARGET)
		b.pressed.connect(
			func() -> void:
				_log_filter = mode
				_render_log()
		)
		UiProbe.register("combat.log_filter." + mode, b)
		head.add_child(b)
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


## Thumb arc (DESIGN.md mobile): the ultimate in the corner, spells around it.
func _layout_arc(buttons: Array[SpellButton], ult: SpellButton, margin: float) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	var corner := get_viewport_rect().size - Vector2(margin, margin)
	# Thumb targets stay >= 48 CSS px even where the UI is scaled down (phones).
	var side := 0.0
	for b in buttons:
		b.custom_minimum_size = Vector2.ONE * UiTokens.at_least_css(b.custom_minimum_size.x)
		side = maxf(side, b.custom_minimum_size.x)
	var half_ult := 0.0
	if ult:
		ult.custom_minimum_size = (
			Vector2.ONE * UiTokens.at_least_css(ult.custom_minimum_size.x, 56.0)
		)
		half_ult = ult.custom_minimum_size.x / 2.0
	var centre := corner - Vector2.ONE * maxf(half_ult, 52.0)
	if ult:
		holder.add_child(ult)
		ult.position = centre - ult.custom_minimum_size / 2.0
	# Radius so neighbours on the quarter circle do not overlap (chord >= side + gap).
	var n := maxf(buttons.size(), 1)
	var chord := side + UiTokens.SPACE["sm"]
	var radius := maxf(
		120.0, maxf(chord / (2.0 * sin(deg_to_rad(45.0 / n))), half_ult + chord / 2.0)
	)
	for i in buttons.size():
		var b := buttons[i]
		holder.add_child(b)
		var a := deg_to_rad(180.0 + 90.0 * (i + 0.5) / maxf(buttons.size(), 1))
		b.position = centre + Vector2(cos(a), sin(a)) * radius - b.custom_minimum_size / 2.0


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
		"focus": hero.get("focus", ""),
		"targets": _enemy_screen_points(snap),
		"enemies":
		(
			snap["units"]
			. filter(func(u: Dictionary) -> bool: return u["side"] == "enemy" and u["alive"])
			. size()
		),
	}


## Screen points (window pixels) of living enemies, for tests and tooling.
func _enemy_screen_points(snap: Dictionary) -> Dictionary:
	var out := {}
	if camera == null:
		return out
	var to_screen := get_viewport().get_screen_transform()
	for u in snap["units"]:
		var node := view.actor(u["uid"])
		if (
			u["side"] == "enemy"
			and u["alive"]
			and node
			and not camera.is_position_behind(node.global_position)
		):
			var p := to_screen * camera.unproject_position(node.global_position + Vector3.UP * 0.6)
			out[u["uid"]] = {"x": p.x, "y": p.y}
	return out


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
	# Applied on defeat too: consumables used in the fight are spent.
	var summary := GameState.apply_combat_result(e)
	_result = Kit.panel()
	_result.custom_minimum_size = Vector2(minf(440.0, get_viewport_rect().size.x - 32.0), 0)
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
		var body := Kit.label(tr("ui.combat.defeat_body"), "", true)
		body.custom_minimum_size = Vector2(_result.custom_minimum_size.x - 48.0, 0)
		col.add_child(body)
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
