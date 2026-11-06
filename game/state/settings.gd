extends Node
## Autoload "Settings": per-device preferences, stored apart from saves.

signal changed

const PATH := "user://settings.cfg"

var text_scale_index := 1
var reduce_motion := false


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		text_scale_index = clampi(
			int(cfg.get_value("ui", "text_scale_index", 1)), 0, UiTokens.TEXT_SCALES.size() - 1
		)
		reduce_motion = bool(cfg.get_value("ui", "reduce_motion", false))
	elif OS.has_feature("web"):
		var prefers: Variant = JavaScriptBridge.eval(
			"window.matchMedia('(prefers-reduced-motion: reduce)').matches", true
		)
		reduce_motion = prefers == true


func text_scale() -> float:
	return UiTokens.TEXT_SCALES[text_scale_index]


func set_text_scale_index(index: int) -> void:
	text_scale_index = clampi(index, 0, UiTokens.TEXT_SCALES.size() - 1)
	_save()


func set_reduce_motion(value: bool) -> void:
	reduce_motion = value
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "text_scale_index", text_scale_index)
	cfg.set_value("ui", "reduce_motion", reduce_motion)
	cfg.save(PATH)
	changed.emit()
