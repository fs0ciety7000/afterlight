extends Screen
## Exploration: the 3D location with the HUD on top (DESIGN.md "HUD
## exploration"). Travel through exits goes through GameState.travel().

const PORTRAIT_SIZE := 72.0
## Screen radius of the environment cut-out around Fern (see env_toon).
const EXPLORE_CUT_RADIUS := 0.22
const COMBAT_CUT_RADIUS := 0.36

var view: ExploreView
var _menu: GameMenu
var _toast: Label
var _toast_timer: SceneTreeTimer
var _level: Label
var _gold: Label
var _place: Label
var _joystick: TouchStick
var _travel_started_ms := 0
var _probe_elapsed := 0.0
var _explore_nodes: Array[Node] = []
var _combat: CombatView
var _combat_hud: CombatHud
var _combat_move_cd := 0.0
var _combat_moving := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	view = ExploreView.new()
	view.name = "ExploreView"
	Router.world_root.add_child(view)
	view.exit_reached.connect(_on_exit_reached)
	view.location_ready.connect(_on_location_ready)
	view.location_failed.connect(_on_location_failed)
	view.encounter_engaged.connect(_start_combat)
	_build_hud()
	for child in get_children():
		if child != _toast:
			_explore_nodes.append(child)
	GameState.changed.connect(_refresh_hud)
	_load_current()


func _exit_tree() -> void:
	if is_instance_valid(view):
		if view.player:
			GameState.runtime_position = view.player.global_position
		view.queue_free()


func _load_current() -> void:
	var world: Dictionary = GameState.data["world"]
	var leader: String = GameState.data["party"][0]
	_travel_started_ms = Time.get_ticks_msec()
	view.load_location(
		world["location_id"], world["spawn"], Content.index(), Content.move_speed(leader)
	)
	if GameState.runtime_position != null and view.player:
		view.player.global_position = GameState.runtime_position
		view.rig.snap()
	_refresh_hud()


func _on_location_ready(location_id: String) -> void:
	var ms := Time.get_ticks_msec() - _travel_started_ms
	UiProbe.world["location_ready_ms"] = ms
	UiProbe.world["location_ready_at_ms"] = Time.get_ticks_msec()
	UiProbe.world["location_id"] = location_id
	_show_toast(tr("ui.explore.arrived").format({"place": Content.display_name(location_id)}))


func _on_location_failed(_location_id: String, _reason: String) -> void:
	_show_toast(tr("ui.explore.scene_missing"), true)


func _on_exit_reached(to: String, spawn: String) -> void:
	var status := GameState.location_status(to)
	if status != WorldRules.AVAILABLE:
		_show_toast(
			tr("ui.explore.exit_locked").format({"reason": GameState.lock_reason(to)}), true
		)
		return
	var error := GameState.travel(to, spawn)
	if error == "":
		_load_current()
		SaveService.save_now()


# --- Input -----------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if _menu != null:
		return
	if _combat != null:
		_combat_input(event)
		return
	if event.is_action_pressed("open_map"):
		get_viewport().set_input_as_handled()
		Router.go_to("world_map")
	elif event.is_action_pressed("open_bag"):
		get_viewport().set_input_as_handled()
		Router.go_to("bag")
	elif event.is_action_pressed("open_character"):
		get_viewport().set_input_as_handled()
		Router.go_to("character")
	elif event.is_action_pressed("open_grimoire"):
		get_viewport().set_input_as_handled()
		Router.go_to("grimoire")
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_open_menu()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				view.click_to_move(mb.position)
			MOUSE_BUTTON_WHEEL_UP:
				view.rig.zoom(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				view.rig.zoom(-1)


func _process(delta: float) -> void:
	_combat_steering(delta)
	_probe_elapsed += delta
	if _probe_elapsed < 0.1 or view == null or view.player == null:
		return
	_probe_elapsed = 0.0
	var p := view.player.global_position
	UiProbe.world["player"] = {"x": p.x, "y": p.y, "z": p.z}
	UiProbe.world["fps"] = Engine.get_frames_per_second()
	UiProbe.world["joystick"] = {"x": view.player.joystick.x, "y": view.player.joystick.y}
	var exits := {}
	var to_screen := get_viewport().get_screen_transform()
	for to in view.exit_screen_points():
		var s: Vector2 = to_screen * view.exit_screen_points()[to]
		exits[to] = {"x": s.x, "y": s.y}
	UiProbe.world["exits"] = exits
	var ps := to_screen * view.rig.camera.unproject_position(p)
	UiProbe.world["player_screen"] = {"x": ps.x, "y": ps.y}
	var packs := {}
	for id in view.pack_positions():
		var w: Vector3 = view.pack_positions()[id]
		if not view.rig.camera.is_position_behind(w):
			var sp := to_screen * view.rig.camera.unproject_position(w)
			packs[id] = {"x": sp.x, "y": sp.y, "dist": w.distance_to(p)}
	UiProbe.world["packs"] = packs


func _open_menu() -> void:
	_menu = GameMenu.new()
	_menu.in_combat = _combat != null
	add_child(_menu)
	if _combat:
		_combat.paused = true
	_menu.closed.connect(func() -> void: _menu = null)


# --- HUD -------------------------------------------------------------------


func _build_hud() -> void:
	var narrow := is_narrow()
	var margin: int = UiTokens.SPACE["lg"] if narrow else UiTokens.SPACE["xl"]

	# Top-left: portrait, name, level, gold.
	var card := Kit.panel("CardPanel")
	card.position = Vector2(margin, margin)
	var row := Kit.hbox()
	card.add_child(row)
	var portrait := TextureRect.new()
	var leader: String = GameState.data["party"][0]
	var portrait_path: String = Content.get_entity(leader).get("portrait", "")
	if ResourceLoader.exists(portrait_path):
		portrait.texture = load(portrait_path)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var side := PORTRAIT_SIZE * (0.75 if narrow else 1.0)
	portrait.custom_minimum_size = Vector2(side, side)
	row.add_child(portrait)
	var col := Kit.vbox(UiTokens.SPACE["xs"])
	row.add_child(col)
	col.add_child(Kit.label(Content.display_name(leader), "SubheadingLabel"))
	_level = Kit.label("", "NumberLabel")
	UiProbe.register("hud.level", _level)
	col.add_child(_level)
	_gold = Kit.label("", "MutedLabel")
	UiProbe.register("hud.gold", _gold)
	col.add_child(_gold)
	add_child(card)

	# Top-right: place name and minimap button (opens the world map).
	var right := Kit.vbox(UiTokens.SPACE["xs"])
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.position = Vector2(-margin, margin)
	right.alignment = BoxContainer.ALIGNMENT_END
	var minimap := MinimapButton.new()
	minimap.diameter = 104.0 if narrow else 148.0
	minimap.pressed.connect(func() -> void: Router.go_to("world_map"))
	UiProbe.register("hud.minimap", minimap)
	minimap.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(minimap)
	var place_panel := Kit.panel("CardPanel")
	place_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_place = Kit.label("", "LeadLabel")
	UiProbe.register("hud.place", _place)
	place_panel.add_child(_place)
	right.add_child(place_panel)
	add_child(right)
	right.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, margin
	)

	# Bottom: character, bag, grimoire, map, menu (DESIGN.md "HUD exploration").
	var bar := Kit.hbox()
	var touch := DisplayServer.is_touchscreen_available()
	var suffix := "_touch" if touch else ""
	for entry: Array in [
		["character", "ui.explore.character_button"],
		["bag", "ui.explore.bag_button"],
		["grimoire", "ui.explore.grimoire_button"],
	]:
		var screen: String = entry[0]
		var b := Kit.button(tr(entry[1] + suffix), false, "hud." + screen)
		b.pressed.connect(func() -> void: Router.go_to(screen))
		bar.add_child(b)
	var map_button := Kit.button(tr("ui.explore.map_button" + suffix), false, "hud.map")
	map_button.pressed.connect(func() -> void: Router.go_to("world_map"))
	bar.add_child(map_button)
	var menu_button := Kit.button(tr("ui.explore.menu_button" + suffix), false, "hud.menu")
	menu_button.pressed.connect(_open_menu)
	bar.add_child(menu_button)
	for b: Button in bar.get_children():
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = UiTokens.at_least_css(UiTokens.TOUCH_TARGET)
	add_child(bar)
	bar.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, margin
	)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH

	# Bottom-left: touch joystick.
	if DisplayServer.is_touchscreen_available() or narrow:
		_joystick = TouchStick.new()
		add_child(_joystick)
		_joystick.place_bottom_left(margin)
		_joystick.changed.connect(
			func(v: Vector2) -> void:
				if view and view.player:
					view.player.joystick = v
		)
		UiProbe.register("hud.joystick", _joystick)

	# Toast for arrivals and blocked paths.
	_toast = Kit.label("", "LeadLabel")
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 96
	)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var toast_box := StyleBoxFlat.new()
	toast_box.bg_color = Color(UiTokens.DAY["surface"], 0.9)
	toast_box.set_corner_radius_all(UiTokens.RADIUS)
	toast_box.set_content_margin_all(UiTokens.SPACE["md"])
	_toast.add_theme_stylebox_override("normal", toast_box)
	_toast.visible = false
	UiProbe.register("hud.toast", _toast)
	add_child(_toast)


func _refresh_hud() -> void:
	if not GameState.has_game() or _level == null:
		return
	var s := GameState.summary()
	_level.text = tr("ui.explore.level").format({"level": s["level"]})
	_gold.text = tr("ui.explore.gold").format({"gold": s["gold"]})
	_place.text = Content.display_name(s["location_id"])


func _show_toast(message: String, is_error: bool = false) -> void:
	_toast.text = message
	_toast.add_theme_color_override(
		"font_color", UiTokens.DAY["danger"] if is_error else UiTokens.DAY["ink"]
	)
	_toast.visible = true
	UiProbe.note(message)
	_toast_timer = get_tree().create_timer(3.0)
	var timer := _toast_timer
	timer.timeout.connect(
		func() -> void:
			if timer == _toast_timer and is_instance_valid(_toast):
				_toast.visible = false
	)


# --- Combat ----------------------------------------------------------------


func _start_combat(encounter_id: String, anchor: Node3D) -> void:
	var counter := int(GameState.data["rng"].get("combat", 0))
	GameState.data["rng"]["combat"] = counter + 1
	var seed_value: int = absi(
		SeededRng.derive_seed(int(GameState.data["meta"]["seed"]), "combat", counter)
	)
	var cleared: Dictionary = GameState.data["progress"]["cleared_encounters"]
	var setup: Dictionary = GameState.progression.combat_setup()
	setup["seed"] = seed_value
	setup["first_clear"] = int(cleared.get(encounter_id, 0)) == 0
	_combat = CombatView.new()
	_combat.name = "Combat"
	view.add_child(_combat)
	var error := _combat.start(encounter_id, anchor, view.player, setup, view.rig)
	if error != "":
		push_error("Combat %s: %s" % [encounter_id, error])
		_combat.queue_free()
		_combat = null
		view.engaged = ""
		return
	view.hide_pack(encounter_id)
	view.rig.cut_radius = COMBAT_CUT_RADIUS
	for n in _explore_nodes:
		if n is CanvasItem:
			(n as CanvasItem).visible = n == _joystick
	_combat_hud = CombatHud.new()
	add_child(_combat_hud)
	_combat_hud.bind(_combat, view.rig.camera)
	_combat_hud.leave_requested.connect(_end_combat)
	UiProbe.world["combat"] = encounter_id
	UiProbe.world["combat_result"] = ""
	UiProbe.test_handlers["defeat_party"] = func() -> void:
		if _combat and _combat.sim:
			_combat.sim.test_defeat_party()
	_combat.finished.connect(
		func(e: Dictionary) -> void: UiProbe.world["combat_result"] = e.get("result", "")
	)


func _end_combat(victory: bool) -> void:
	var id := _combat.encounter_id
	_combat.queue_free()
	_combat = null
	_combat_hud.queue_free()
	_combat_hud = null
	view.player.combat_driven = false
	view.rig.cut_radius = EXPLORE_CUT_RADIUS
	for n in _explore_nodes:
		if n is CanvasItem:
			(n as CanvasItem).visible = true
	UiProbe.world["combat"] = ""
	if victory:
		view.clear_pack(id)
		view.engaged = ""
		SaveService.save_now()
	else:
		# Defeat: back to the entrance of the place, full health, nothing lost.
		GameState.runtime_position = null
		GameState.data["world"]["spawn"] = "default"
		_load_current()
	_refresh_hud()


func _combat_input(event: InputEvent) -> void:
	var handled := true
	if event.is_action_pressed("combat_spell_1"):
		_combat_hud.cast_index(0)
	elif event.is_action_pressed("combat_spell_2"):
		_combat_hud.cast_index(1)
	elif event.is_action_pressed("combat_spell_3"):
		_combat_hud.cast_index(2)
	elif event.is_action_pressed("combat_ultimate"):
		_combat_hud.cast_ultimate()
	elif event.is_action_pressed("combat_pause"):
		_combat_hud.toggle_pause()
	elif event.is_action_pressed("combat_speed"):
		_combat.cycle_speed()
		_combat_hud._refresh_controls()
	elif event.is_action_pressed("ui_cancel"):
		_open_menu()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var uid := _combat.pick_unit(view.rig.camera, mb.position)
			if uid != "":
				_combat.command({"type": "set_focus", "target": uid})
			else:
				var point: Variant = view.ground_point(mb.position)
				if point != null:
					var p := _combat.to_sim(point)
					_combat.command({"type": "move_to", "x": p.x, "z": p.y})
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			view.rig.zoom(1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			view.rig.zoom(-1)
		else:
			handled = false
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


## Keyboard or stick movement during combat becomes short move orders.
func _combat_steering(delta: float) -> void:
	if _combat == null or _combat.paused:
		return
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if v == Vector2.ZERO and view.player:
		v = view.player.joystick
	_combat_move_cd -= delta
	if v != Vector2.ZERO:
		if _combat_move_cd <= 0.0:
			var target := view.player.global_position + Vector3(v.x, 0.0, v.y).normalized() * 2.5
			var p := _combat.to_sim(target)
			_combat.command({"type": "move_to", "x": p.x, "z": p.y})
			_combat_move_cd = 0.25
			_combat_moving = true
	elif _combat_moving:
		_combat.command({"type": "stop"})
		_combat_moving = false
