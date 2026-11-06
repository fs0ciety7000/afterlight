extends Node
## Autoload "Router": shows one screen at a time inside the host given by
## Main, with a short fade (a cut when reduced motion is on).

signal screen_changed(screen_id: String)

const SCREENS := {
	"title": "res://game/app/screens/title_screen.gd",
	"camp": "res://game/app/screens/camp_screen.gd",
	"settings": "res://game/app/screens/settings_screen.gd",
	"save_recovery": "res://game/app/screens/save_recovery_screen.gd",
	"content_error": "res://game/app/screens/content_error_screen.gd",
}
const FADE_SECONDS := 0.16  # x2 (out + in) = 320 ms, DESIGN.md

var current_id := ""
var current: Control
var _host: Control
var _veil: ColorRect
var _history: Array[String] = []


func attach(host: Control, veil: ColorRect) -> void:
	_host = host
	_veil = veil


func go_to(screen_id: String, params: Dictionary = {}, remember: bool = true) -> void:
	assert(SCREENS.has(screen_id), "unknown screen %s" % screen_id)
	SaveService.save_if_dirty()
	if remember and current_id != "":
		_history.append(current_id)
	var fade := not Settings.reduce_motion and current != null
	if fade:
		await _fade_to(1.0)
	if current:
		current.queue_free()
	var screen: Control = (load(SCREENS[screen_id]) as GDScript).new()
	screen.name = screen_id
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if screen.has_method("setup"):
		screen.call("setup", params)
	_host.add_child(screen)
	current = screen
	current_id = screen_id
	screen_changed.emit(screen_id)
	if fade:
		await _fade_to(0.0)
	if screen.has_method("grab_initial_focus"):
		screen.call_deferred("grab_initial_focus")


## Returns to the previous screen (or the given fallback).
func back(fallback: String = "title") -> void:
	var target: String = _history.pop_back() if not _history.is_empty() else fallback
	go_to(target, {}, false)


func _fade_to(alpha: float) -> void:
	_veil.visible = true
	var tween := create_tween()
	tween.tween_property(_veil, "color:a", alpha, FADE_SECONDS).set_trans(Tween.TRANS_CUBIC)
	await tween.finished
	_veil.visible = alpha > 0.0
