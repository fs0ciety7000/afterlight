extends Node
## Autoload "UiProbe": names important controls and, on the web, publishes
## their on-screen rectangles and a state summary to `window.__afterlight`.
## Playwright reads it to click like a player and check the outcome.

## Free-form facts from the 3D views (player position, timings, map view).
var world := {}
## Test-only commands from the page (`window.__afterlightTest(name)`),
## enabled by `?test=1` in the address. Handlers are registered by screens.
var test_handlers := {}
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
		JavaScriptBridge.eval(
			"window.__afterlightSetTest = (cb) => { window.__afterlightTest = (n) => cb(n); };",
			true
		)
		_test_callback = JavaScriptBridge.create_callback(_on_test_command)
		JavaScriptBridge.get_interface("window").__afterlightSetTest(_test_callback)


func _on_test_command(args: Array) -> void:
	var name := str(args[0]) if args.size() > 0 else ""
	if test_handlers.has(name):
		(test_handlers[name] as Callable).call()
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
		"settings": {"text_scale": Settings.text_scale(), "reduce_motion": Settings.reduce_motion},
	}
