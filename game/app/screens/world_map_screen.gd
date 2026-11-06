extends Screen
## World map (GDD §5.1): painted region map, fog of war, places with their
## status, zoom (2 steps), pan, and travel to available places.

const ZOOMS := [1.0, 1.5, 2.25]
const FOG_SHADER := preload("res://assets/shaders/map_fog.gdshader")
const PAN_STEP := 80.0

var _frame: Control
var _canvas: Control
var _markers: Control
var _fog: ColorRect
var _zoom_index := 0
var _pan := Vector2.ZERO
var _base_size := Vector2.ZERO
var _selected := ""
var _detail_title: Label
var _detail_body: Label
var _detail_status: Label
var _travel: Button
var _dragging := false
var _drag_last := Vector2.ZERO


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UiTokens.DAY["ink"]
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var narrow := is_narrow()
	var layout: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
	layout.add_theme_constant_override("separation", UiTokens.SPACE["lg"])
	add_child(Kit.margin(layout, narrow))

	_frame = Control.new()
	_frame.clip_contents = true
	_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_frame.gui_input.connect(_on_frame_input)
	_frame.resized.connect(_layout_map)
	layout.add_child(_frame)
	UiProbe.register("map.frame", _frame)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_canvas)
	var art := TextureRect.new()
	var region: String = GameState.data["world"]["region_id"]
	var path: String = Content.get_entity(region).get("map_texture", "")
	if ResourceLoader.exists(path):
		art.texture = load(path)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if art.texture == null:
		var parchment := ColorRect.new()
		parchment.color = UiTokens.DAY["surface_alt"]
		parchment.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		parchment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.add_child(parchment)
	_canvas.add_child(art)
	_fog = ColorRect.new()
	_fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fog_mat := ShaderMaterial.new()
	fog_mat.shader = FOG_SHADER
	_fog.material = fog_mat
	_canvas.add_child(_fog)
	_markers = Control.new()
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.add_child(_markers)

	layout.add_child(_side_panel(narrow))
	_build_markers()
	_select(GameState.data["world"]["location_id"])
	_update_fog()
	call_deferred("_layout_map")


func _side_panel(narrow: bool) -> Control:
	var panel := Kit.panel()
	panel.custom_minimum_size = Vector2(0 if narrow else 360, 0)
	var col := Kit.vbox()
	panel.add_child(col)
	var head := Kit.hbox()
	var title := Kit.label(tr("ui.map.title"), "HeadingLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Kit.button(tr("ui.map.close"), false, "map.close")
	close.pressed.connect(_close)
	head.add_child(close)
	col.add_child(head)
	var zoom_row := Kit.hbox()
	var zin := Kit.button(tr("ui.map.zoom_in"), false, "map.zoom_in")
	zin.pressed.connect(func() -> void: _zoom(1))
	var zout := Kit.button(tr("ui.map.zoom_out"), false, "map.zoom_out")
	zout.pressed.connect(func() -> void: _zoom(-1))
	zoom_row.add_child(zin)
	zoom_row.add_child(zout)
	col.add_child(zoom_row)
	if not narrow:
		col.add_child(Kit.label(tr("ui.map.hint"), "MutedLabel", true))
	col.add_child(HSeparator.new())
	_detail_title = Kit.label("", "SubheadingLabel", true)
	UiProbe.register("map.detail_title", _detail_title)
	col.add_child(_detail_title)
	_detail_status = Kit.label("", "MutedLabel", true)
	UiProbe.register("map.detail_status", _detail_status)
	col.add_child(_detail_status)
	_detail_body = Kit.label("", "", true)
	if not narrow:
		col.add_child(_detail_body)
	_travel = Kit.button(tr("ui.map.travel"), true, "map.travel")
	_travel.pressed.connect(_on_travel)
	col.add_child(_travel)
	# Offline hunt choice, the selected place first (GDD §12, ROADMAP 5.5).
	var hunts := Kit.button(tr("ui.map.hunts"), false, "map.hunts")
	hunts.pressed.connect(func() -> void: Router.go_to("hunts", {"location": _selected}))
	col.add_child(hunts)
	return panel


func _build_markers() -> void:
	var region: String = GameState.data["world"]["region_id"]
	for id in Content.get_entity(region).get("locations", []):
		var status := GameState.location_status(id)
		if status == WorldRules.HIDDEN:
			continue
		var m := MapMarker.new()
		m.location_id = id
		m.status = status
		m.is_current = id == GameState.data["world"]["location_id"]
		m.pressed.connect(_select.bind(id))
		_markers.add_child(m)
		UiProbe.register("map.marker." + id.get_slice(".", 1), m)


func _select(id: String) -> void:
	_selected = id
	for m: MapMarker in _markers.get_children():
		m.is_selected = m.location_id == id
		m.queue_redraw()
	var e := Content.get_entity(id)
	_detail_title.text = Content.display_name(id)
	var status := GameState.location_status(id)
	var lines := []
	if e.get("kind", "") == "hub":
		lines.append(tr("ui.map.hub"))
	elif e.has("level"):
		lines.append(tr("ui.map.level").format({"level": e["level"]}))
	if id == GameState.data["world"]["location_id"]:
		lines.append(tr("ui.map.here"))
	elif status == WorldRules.LOCKED:
		lines.append(GameState.lock_reason(id))
	_detail_status.text = tr("ui.common.separator").join(lines)
	_detail_body.text = tr(e.get("desc_key", "")) if e.get("desc_key", "") != "" else ""
	_travel.disabled = (
		status != WorldRules.AVAILABLE or id == GameState.data["world"]["location_id"]
	)
	UiProbe.world["map_selected"] = id


func _on_travel() -> void:
	UiProbe.world["travel_clicked_ms"] = Time.get_ticks_msec()
	if GameState.travel(_selected, "default") == "":
		SaveService.save_now()
		Router.go_to("explore", {}, false)


func _close() -> void:
	Router.back("explore")


# --- Zoom, pan, fog --------------------------------------------------------


func _layout_map() -> void:
	var tex_aspect := 16.0 / 9.0
	var frame := _frame.size
	if frame.x <= 0.0 or frame.y <= 0.0:
		return
	# Fit the whole map in the frame at zoom 1.
	_base_size = Vector2(frame.x, frame.x / tex_aspect)
	if _base_size.y > frame.y:
		_base_size = Vector2(frame.y * tex_aspect, frame.y)
	_apply_view()


func _zoom(step: int) -> void:
	var old := float(ZOOMS[_zoom_index])
	_zoom_index = clampi(_zoom_index + step, 0, ZOOMS.size() - 1)
	var ratio := float(ZOOMS[_zoom_index]) / old
	# Keep the centre of the frame fixed.
	var centre := _frame.size / 2.0
	_pan = centre - (centre - _pan) * ratio
	_apply_view()


func _apply_view() -> void:
	var scaled := _base_size * float(ZOOMS[_zoom_index])
	var frame := _frame.size
	var min_pan := frame - scaled
	if scaled.x <= frame.x:
		_pan.x = (frame.x - scaled.x) / 2.0
	else:
		_pan.x = clampf(_pan.x, min_pan.x, 0.0)
	if scaled.y <= frame.y:
		_pan.y = (frame.y - scaled.y) / 2.0
	else:
		_pan.y = clampf(_pan.y, min_pan.y, 0.0)
	_canvas.position = _pan
	_canvas.size = scaled
	for m: MapMarker in _markers.get_children():
		var pos: Array = Content.get_entity(m.location_id)["map_pos"]
		m.position = _pan + Vector2(pos[0], pos[1]) * scaled - m.size / 2.0
	UiProbe.world["map"] = {"zoom": ZOOMS[_zoom_index], "pan_x": _pan.x, "pan_y": _pan.y}


func _update_fog() -> void:
	var points := PackedVector2Array()
	for id in GameState.data["world"]["revealed_locations"]:
		var pos: Array = Content.get_entity(id).get("map_pos", [0.5, 0.5])
		points.append(Vector2(pos[0], pos[1]))
	while points.size() < 16:
		points.append(Vector2(-1, -1))
	var mat := _fog.material as ShaderMaterial
	mat.set_shader_parameter("points", points)
	mat.set_shader_parameter("count", GameState.data["world"]["revealed_locations"].size())


func _on_frame_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(-1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_drag_last = mb.position
	elif event is InputEventMouseMotion and _dragging:
		# Use positions, not `relative`: some browsers report zero movement.
		var pos := (event as InputEventMouseMotion).position
		_pan += pos - _drag_last
		_drag_last = pos
		_apply_view()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("open_map"):
		get_viewport().set_input_as_handled()
		_close()
	elif event.is_action_pressed("map_zoom_in"):
		_zoom(1)
	elif event.is_action_pressed("map_zoom_out"):
		_zoom(-1)
	elif event.is_action_pressed("move_left"):
		_pan.x += PAN_STEP
		_apply_view()
	elif event.is_action_pressed("move_right"):
		_pan.x -= PAN_STEP
		_apply_view()
	elif event.is_action_pressed("move_forward"):
		_pan.y += PAN_STEP
		_apply_view()
	elif event.is_action_pressed("move_back"):
		_pan.y -= PAN_STEP
		_apply_view()


func grab_initial_focus() -> void:
	for m: MapMarker in _markers.get_children():
		if m.location_id == _selected:
			m.grab_focus()
