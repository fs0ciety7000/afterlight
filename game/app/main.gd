extends Control
## Root of the game: owns the UI layer, the theme and the boot sequence.
## The 3D world layer is added in Milestone 2.

const MIN_LOGICAL_HEIGHT := 640.0
const MAX_LOGICAL_HEIGHT := 1080.0

var _host: Control
var _veil: ColorRect


func _ready() -> void:
	TranslationServer.set_locale("fr")
	InputActions.install(Settings.bindings)
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
	_register_test_handlers()
	_boot()
	print("Afterlight booted")


## Test channel (`?test=1`): setup shortcuts for the progression E2E runs.
## Registered here, on the root, so they work from every screen.
func _register_test_handlers() -> void:
	UiProbe.test_handlers["force_item_drop"] = func() -> void: GameState.test_force_item_drop = true
	UiProbe.test_handlers["grant_forge_funds"] = func() -> void:
		GameState.test_grant(1000, {"material.mana_dust": 40})
	UiProbe.test_handlers["grant_level"] = _test_grant_level
	# Full-run E2E (ROADMAP 6.3): accelerated XP and the gear a run would give.
	UiProbe.test_handlers["grant_levels"] = func(n: String) -> void:
		for i in maxi(int(n), 0):
			_test_grant_level()
	UiProbe.test_handlers["grant_gear"] = func(arg: String) -> void:
		GameState.test_grant_gear(arg.get_slice("/", 0), int(arg.get_slice("/", 1)))
	UiProbe.test_handlers["grant_gold"] = func(n: String) -> void:
		GameState.test_grant(maxi(int(n), 0), {})
	UiProbe.test_handlers["reveal_watch_ruins"] = _test_reveal_watch_ruins
	# Accessibility E2E (ROADMAP 1.11, 7.3, 7.7): set the options without the pickers.
	UiProbe.test_handlers["text_scale"] = func(i: String) -> void:
		Settings.set_text_scale_index(int(i))
	UiProbe.test_handlers["reduce_motion"] = func(on: String) -> void:
		Settings.set_reduce_motion(on == "1")


## Test channel only (idle E2E 5.5): shows the Watch Ruins on the map, where
## the elite and the boss live, without playing the quests that reveal them.
func _test_reveal_watch_ruins() -> void:
	if not GameState.has_game():
		return
	var next := GameState.data.duplicate(true)
	var revealed: Array = next["world"]["revealed_locations"]
	if not revealed.has("location.watch_ruins"):
		revealed.append("location.watch_ruins")
	GameState.commit_action(next)


## Test channel only (idle E2E): the leader gains one level, then the game
## saves, so a won pack can become a hunt the party survives offline.
func _test_grant_level() -> void:
	if not GameState.has_game():
		return
	var next := GameState.data.duplicate(true)
	var hero: Dictionary = next["characters"][next["party"][0]]
	hero["level"] = mini(int(hero["level"]) + 1, BalanceProgression.LEVEL_CAP)
	hero["xp"] = 0
	GameState.commit_action(next)


## Reduced-motion render flags for the E2E probe (UiProbe publishes on the web only).
func _process(_delta: float) -> void:
	if OS.has_feature("web"):
		UiProbe.world["motion_flags"] = MotionFlags.snapshot()


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
	UiTokens.css_per_logical = (window.y / dpr) / logical_h
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = Vector2i(roundi(window.x * logical_h / window.y), roundi(logical_h))
