extends Node
## Autoload "UiProbe": names important controls and, on the web, publishes
## their on-screen rectangles and a state summary to `window.__afterlight`.
## Playwright reads it to click like a player and check the outcome.

## Free-form facts from the 3D views (player position, timings, map view).
var world := {}
## Test-only commands from the page (`window.__afterlightTest(name)`),
## enabled by `?test=1` in the address. Handlers are registered by screens.
var test_handlers := {}
## Test channel: a new game skips the intro cards unless the page has
## `intro=1` (older E2E runs expect the world right away).
var test_skip_intro := false
var _controls := {}
var _test_callback: JavaScriptObject
var _elapsed := 0.0
var _messages: Array[String] = []


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	var flag: Variant = JavaScriptBridge.eval(
		"new URLSearchParams(window.location.search).get('test') || ''", true
	)
	if str(flag) == "1":
		GameState.test_channel = true
		var offset: Variant = JavaScriptBridge.eval(
			"new URLSearchParams(window.location.search).get('clock_offset_s') || '0'", true
		)
		GameState.debug_clock_offset_s = int(str(offset))
		var intro: Variant = JavaScriptBridge.eval(
			"new URLSearchParams(window.location.search).get('intro') || ''", true
		)
		test_skip_intro = str(intro) != "1"
		JavaScriptBridge.eval(
			"window.__afterlightSetTest = (cb) => { window.__afterlightTest = (n) => cb(n); };",
			true
		)
		_test_callback = JavaScriptBridge.create_callback(_on_test_command)
		JavaScriptBridge.get_interface("window").__afterlightSetTest(_test_callback)
		test_handlers["reveal"] = _reveal


## Test channel: scrolls the nearest ScrollContainer so the control shows, as
## a player would before tapping it.
func _reveal(id: String) -> void:
	var ref: Variant = _controls.get(id)
	if not is_instance_valid(ref):
		return
	var c: Control = ref
	var node := c.get_parent()
	while node != null:
		if node is ScrollContainer:
			(node as ScrollContainer).ensure_control_visible(c)
		node = node.get_parent()


## True when the control's centre lies outside a clipping ancestor (e.g. a
## ScrollContainer): drawn "visible" but not on screen where it says.
static func is_clipped(c: Control) -> bool:
	var centre := c.get_global_rect().get_center()
	var node := c.get_parent()
	while node != null:
		if node is Control and (node as Control).clip_contents:
			if not (node as Control).get_global_rect().grow(1.0).has_point(centre):
				return true
		node = node.get_parent()
	return false


## True when the control sits in a scroll list: it may be scrolled out of
## view (and clipped) on purpose.
static func in_scroll_list(c: Control) -> bool:
	var node := c.get_parent()
	while node != null:
		if node is ScrollContainer:
			return true
		node = node.get_parent()
	return false


## True when a label or button shows only part of its text: one line clipped
## or ellipsized short of its width, or wrapped lines that do not all fit.
static func is_truncated(c: Control) -> bool:
	if not (c is Label or c is Button):
		return false
	var text := str(c.get("text"))
	if text == "" or c.size.x <= 0.0:
		return false
	if c.get("autowrap_mode") != TextServer.AUTOWRAP_OFF:
		if c is Label:
			var l := c as Label
			return l.get_visible_line_count() < l.get_line_count()
		return false
	var cut: bool = (
		c.get("clip_text") or c.get("text_overrun_behavior") != TextServer.OVERRUN_NO_TRIMMING
	)
	if not cut:
		return false
	var room := c.size.x
	var box := c.get_theme_stylebox("normal")
	if box:
		room -= box.get_minimum_size().x
	if c is Button and (c as Button).icon != null:
		room -= ((c as Button).icon.get_width() + float(c.get_theme_constant("h_separation")))
	var font := c.get_theme_font("font")
	var width := (
		font
		. get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, c.get_theme_font_size("font_size")
		)
		. x
	)
	return width > room + 1.0


## `name` or `name:arg`: a handler registered under `name` gets `arg` (a
## String) when the command carries one.
func _on_test_command(args: Array) -> void:
	var name := str(args[0]) if args.size() > 0 else ""
	if test_handlers.has(name):
		(test_handlers[name] as Callable).call()
		note("test:" + name)
		return
	var cut := name.find(":")
	if cut > 0 and test_handlers.has(name.left(cut)):
		(test_handlers[name.left(cut)] as Callable).call(name.substr(cut + 1))
		note("test:" + name)


func register(id: String, control: Control) -> void:
	_controls[id] = control


func note(message: String) -> void:
	_messages.append(message)
	if _messages.size() > 20:
		_messages.pop_front()


func _process(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	_elapsed += delta
	if _elapsed < 0.15:
		return
	_elapsed = 0.0
	JavaScriptBridge.eval("window.__afterlight = %s;" % JSON.stringify(snapshot()), true)


func snapshot() -> Dictionary:
	var controls := {}
	for id in _controls.keys():
		var ref: Variant = _controls[id]
		if not is_instance_valid(ref) or not (ref as Control).is_inside_tree():
			_controls.erase(id)
			continue
		var c: Control = ref
		var rect := c.get_viewport().get_screen_transform() * c.get_global_rect()
		var entry := {
			"x": rect.position.x,
			"y": rect.position.y,
			"w": rect.size.x,
			"h": rect.size.y,
			"visible": c.is_visible_in_tree(),
			"clipped": is_clipped(c),
			"scrolled": in_scroll_list(c),
			"truncated": is_truncated(c),
		}
		if c is BaseButton:
			entry["disabled"] = (c as BaseButton).disabled
		if "text" in c:
			entry["text"] = str(c.get("text"))
		controls[id] = entry
	return {
		"ready": true,
		"screen": Router.current_id,
		"controls": controls,
		"state": GameState.summary(),
		"save": {"last_saved_at": SaveService.last_saved_at, "error": SaveService.last_error},
		"messages": _messages,
		"world": world,
		"settings":
		{
			"text_scale": Settings.text_scale(),
			"reduce_motion": Settings.reduce_motion,
			"bindings": Settings.bindings,
		},
	}
