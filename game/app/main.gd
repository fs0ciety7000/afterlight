extends Control
## Root of the game: owns the UI layer, the theme and the boot sequence.
## The 3D world layer is added in Milestone 2.

const MIN_LOGICAL_HEIGHT := 640.0
const MAX_LOGICAL_HEIGHT := 1080.0

var _host: Control
var _veil: ColorRect


func _ready() -> void:
	TranslationServer.set_locale("fr")
	InputActions.install()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	_host = Control.new()
	_host.name = "ScreenHost"
	_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_host)
	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.color = Color(UiTokens.DAY["ink"], 0.0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.visible = false
	add_child(_veil)
	Router.attach(_host, _veil, world)

	_apply_theme()
	Settings.changed.connect(_apply_theme)
	get_tree().root.size_changed.connect(_fit_ui_scale)
	_fit_ui_scale()
	_boot()
	print("Afterlight booted")


func _boot() -> void:
	if not Content.is_valid():
		Router.go_to("content_error", {}, false)
		return
	var r := SaveService.boot_read()
	match r["status"]:
		"ok":
			GameState.adopt(r["decoded"]["state"])
			Router.go_to("title", {"boot": r}, false)
		"corrupt":
			SaveService.store.quarantine(GameState.now_unix())
			Router.go_to("save_recovery", {"boot": r}, false)
		_:
			Router.go_to("title", {"boot": r}, false)


func _apply_theme() -> void:
	theme = ThemeBuilder.build(UiTokens.DAY, Settings.text_scale())
	if Router.current_id != "" and Router.current_id != "content_error":
		Router.go_to(Router.current_id, {}, false)


## Keeps one logical UI pixel close to one CSS pixel, so text stays readable
## on phones and does not balloon on large monitors.
func _fit_ui_scale() -> void:
	var root := get_tree().root
	var window := Vector2(DisplayServer.window_get_size())
	if window.y <= 0:
		return
	var dpr := 1.0
	if OS.has_feature("web"):
		var v: Variant = JavaScriptBridge.eval("window.devicePixelRatio || 1", true)
		dpr = maxf(float(v), 1.0)
	else:
		dpr = maxf(DisplayServer.screen_get_scale(), 1.0)
	var logical_h := clampf(window.y / dpr, MIN_LOGICAL_HEIGHT, MAX_LOGICAL_HEIGHT)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = Vector2i(roundi(window.x * logical_h / window.y), roundi(logical_h))
