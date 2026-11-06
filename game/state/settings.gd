extends Node
## Autoload "Settings": per-device preferences, stored apart from saves.

signal changed

const PATH := "user://settings.cfg"

var text_scale_index := 1
var reduce_motion := false
## GraphicsQuality level (0 low, 1 medium, 2 high).
var graphics_quality := 2


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		text_scale_index = clampi(
			int(cfg.get_value("ui", "text_scale_index", 1)), 0, UiTokens.TEXT_SCALES.size() - 1
		)
		reduce_motion = bool(cfg.get_value("ui", "reduce_motion", false))
		graphics_quality = clampi(int(cfg.get_value("video", "quality", _default_quality())), 0, 2)
	elif OS.has_feature("web"):
		var prefers: Variant = JavaScriptBridge.eval(
			"window.matchMedia('(prefers-reduced-motion: reduce)').matches", true
		)
		reduce_motion = prefers != null and bool(prefers)
		graphics_quality = _default_quality()
	else:
		graphics_quality = _default_quality()
	_apply_url_override()


func text_scale() -> float:
	return UiTokens.TEXT_SCALES[text_scale_index]


func set_text_scale_index(index: int) -> void:
	text_scale_index = clampi(index, 0, UiTokens.TEXT_SCALES.size() - 1)
	_save()


func set_reduce_motion(value: bool) -> void:
	reduce_motion = value
	_save()


func set_graphics_quality(level: int) -> void:
	graphics_quality = clampi(level, 0, 2)
	_save()


## Touch devices start at medium quality, desktops at high.
func _default_quality() -> int:
	return 1 if DisplayServer.is_touchscreen_available() else 2


## `?quality=low|medium|high` in the page address forces a level for this
## session (handy on weak devices and in automated tests). Not saved.
func _apply_url_override() -> void:
	if not OS.has_feature("web"):
		return
	var value: Variant = JavaScriptBridge.eval(
		"new URLSearchParams(window.location.search).get('quality') || ''", true
	)
	var index := ["low", "medium", "high"].find(str(value))
	if index >= 0:
		graphics_quality = index


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "text_scale_index", text_scale_index)
	cfg.set_value("ui", "reduce_motion", reduce_motion)
	cfg.set_value("video", "quality", graphics_quality)
	cfg.save(PATH)
	changed.emit()
