class_name MapMarker
extends BaseButton
## A place on the world map: available, locked (with a padlock) or current.

const RADIUS := 13.0

var location_id := ""
var status := WorldRules.AVAILABLE
var is_current := false
var is_selected := false
var _label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(44, 44)
	size = custom_minimum_size
	focus_mode = Control.FOCUS_ALL
	_label = Kit.label(Content.display_name(location_id), "MutedLabel")
	_label.add_theme_color_override("font_color", UiTokens.DAY["ink"])
	_label.position = Vector2(-60, 44)
	_label.custom_minimum_size = Vector2(164, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(UiTokens.DAY["surface"], 0.85)
	plate.set_corner_radius_all(UiTokens.RADIUS)
	plate.content_margin_left = 6
	plate.content_margin_right = 6
	_label.add_theme_stylebox_override("normal", plate)
	add_child(_label)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var p: Dictionary = UiTokens.DAY
	var c := size / 2.0
	var locked := status == WorldRules.LOCKED
	var fill: Color = p["ink_muted"] if locked else p["accent"]
	if is_selected or has_focus() or is_hovered():
		draw_circle(c, RADIUS + 7.0, Color(p["focus"], 0.35))
	draw_circle(c, RADIUS, fill)
	draw_arc(c, RADIUS, 0.0, TAU, 32, p["accent_ink"], 2.0, true)
	if locked:
		# Padlock: body and shackle.
		draw_rect(Rect2(c + Vector2(-5, -1), Vector2(10, 8)), p["accent_ink"])
		draw_arc(c + Vector2(0, -2), 4.0, PI, TAU, 12, p["accent_ink"], 2.0, true)
	if is_current:
		draw_arc(c, RADIUS + 4.0, 0.0, TAU, 32, p["focus"], 2.0, true)
