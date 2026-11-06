extends Node
## Autoload "Settings": per-device preferences, stored apart from saves.

signal changed
## Input bindings saved (no theme rebuild needed).
signal bindings_changed
## A bus volume changed (0..1); the Audio autoload applies it.
signal volume_changed(bus: String, linear: float)

const PATH := "user://settings.cfg"
## Audio buses the settings screen offers, in display order.
const VOLUME_BUSES := ["Master", "Music", "SFX", "UI", "Ambience"]

var text_scale_index := 1
var reduce_motion := false
## GraphicsQuality level (0 low, 1 medium, 2 high).
var graphics_quality := 2
## Player input overrides {action: {"key": [...], "pad": [...]}}, see
## InputActions.overrides(). Validated when applied.
var bindings := {}
## Bus -> volume 0..1 (1 = as mixed).
var volumes := {}


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		text_scale_index = clampi(
			int(cfg.get_value("ui", "text_scale_index", 1)), 0, UiTokens.TEXT_SCALES.size() - 1
		)
		reduce_motion = bool(cfg.get_value("ui", "reduce_motion", false))
		graphics_quality = clampi(int(cfg.get_value("video", "quality", _default_quality())), 0, 2)
		var saved: Variant = cfg.get_value("input", "bindings", {})
		bindings = saved if saved is Dictionary else {}
		for bus: String in VOLUME_BUSES:
			volumes[bus] = clampf(float(cfg.get_value("audio", bus, 1.0)), 0.0, 1.0)
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


func volume(bus: String) -> float:
	return float(volumes.get(bus, 1.0))


## Saved without `changed` (no theme rebuild while a slider moves).
func set_volume(bus: String, linear: float) -> void:
	if not bus in VOLUME_BUSES:
		return
	volumes[bus] = clampf(linear, 0.0, 1.0)
	_save(false)
	volume_changed.emit(bus, volumes[bus])


func set_bindings(value: Dictionary) -> void:
	bindings = value.duplicate(true)
	_save(false)
	bindings_changed.emit()


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


func _save(notify: bool = true) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "text_scale_index", text_scale_index)
	cfg.set_value("ui", "reduce_motion", reduce_motion)
	cfg.set_value("video", "quality", graphics_quality)
	cfg.set_value("input", "bindings", bindings)
	for bus: String in volumes:
		cfg.set_value("audio", bus, volumes[bus])
	cfg.save(PATH)
	if notify:
		changed.emit()
