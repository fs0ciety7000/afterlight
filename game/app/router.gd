extends Node
## Autoload "Router": shows one screen at a time inside the host given by
## Main, with a short fade (a cut when reduced motion is on).

signal screen_changed(screen_id: String)

const SCREENS := {
	"title": "res://game/app/screens/title_screen.gd",
	"explore": "res://game/app/screens/explore_screen.gd",
	"world_map": "res://game/app/screens/world_map_screen.gd",
	"settings": "res://game/app/screens/settings_screen.gd",
	"character": "res://game/app/screens/character_screen.gd",
	"bag": "res://game/app/screens/bag_screen.gd",
	"grimoire": "res://game/app/screens/grimoire_screen.gd",
	"forge": "res://game/app/screens/forge_screen.gd",
	"runecarver": "res://game/app/screens/runecarver_screen.gd",
	"merchant": "res://game/app/screens/merchant_screen.gd",
	"hunts": "res://game/app/screens/hunts_screen.gd",
	"journal": "res://game/app/screens/journal_screen.gd",
	"offline_summary": "res://game/app/screens/offline_summary_screen.gd",
	"save_recovery": "res://game/app/screens/save_recovery_screen.gd",
	"content_error": "res://game/app/screens/content_error_screen.gd",
}
const FADE_SECONDS := 0.16  # x2 (out + in) = 320 ms, DESIGN.md

var current_id := ""
## Screen fades played since boot (none with reduced motion), for the E2E probe.
var fades_played := 0
## Parent for 3D views (owned by Main, drawn under the UI).
var world_root: Node3D
var current: Control
var _host: Control
var _veil: ColorRect
var _history: Array[String] = []


func attach(host: Control, veil: ColorRect, world: Node3D) -> void:
	_host = host
	_veil = veil
	world_root = world


func go_to(screen_id: String, params: Dictionary = {}, remember: bool = true) -> void:
	assert(SCREENS.has(screen_id), "unknown screen %s" % screen_id)
	SaveService.save_if_dirty()
	if remember and current_id != "":
		_history.append(current_id)
	var fade := fades_enabled() and current != null
	if fade:
		fades_played += 1
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


## Fades between screens, or cuts when "Réduire les animations" is on.
func fades_enabled() -> bool:
	return not Settings.reduce_motion


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
