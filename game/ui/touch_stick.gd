class_name TouchStick
extends Control
## Touch joystick (bottom-left on touch screens, DESIGN.md). `value` is in
## screen space, length <= 1.

signal changed(value: Vector2)

const RADIUS := 64.0
const KNOB := 26.0

var value := Vector2.ZERO
var _touch := -1
var _knob := Vector2.ZERO


func _init() -> void:
	custom_minimum_size = Vector2(RADIUS * 2.0 + 16.0, RADIUS * 2.0 + 16.0)
	mouse_filter = Control.MOUSE_FILTER_STOP


## Anchors the stick to the bottom-left corner with a margin.
func place_bottom_left(margin: float) -> void:
	var side := custom_minimum_size
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = margin
	offset_right = margin + side.x
	offset_top = -margin - side.y
	offset_bottom = -margin


func _center() -> Vector2:
	return size / 2.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch == -1:
			_touch = t.index
			_update(t.position)
		elif not t.pressed and t.index == _touch:
			_release()
		accept_event()
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _touch:
		_update((event as InputEventScreenDrag).position)
		accept_event()
	elif (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	):
		if event.pressed:
			_update(event.position)
		else:
			_release()
		accept_event()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_update(event.position)
		accept_event()


func _update(local: Vector2) -> void:
	_knob = (local - _center()).limit_length(RADIUS)
	value = _knob / RADIUS
	changed.emit(value)
	queue_redraw()


func _release() -> void:
	_touch = -1
	_knob = Vector2.ZERO
	value = Vector2.ZERO
	changed.emit(value)
	queue_redraw()


func _draw() -> void:
	var palette: Dictionary = UiTokens.DAY
	draw_circle(_center(), RADIUS, Color(palette["surface"], 0.55))
	draw_arc(_center(), RADIUS, 0.0, TAU, 48, palette["line"], 1.5, true)
	draw_circle(_center() + _knob, KNOB, Color(palette["accent"], 0.9))
