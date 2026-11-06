extends Node
## Autoload "UiProbe": names important controls and, on the web, publishes
## their on-screen rectangles and a state summary to `window.__afterlight`.
## Playwright reads it to click like a player and check the outcome.

var _controls := {}
var _elapsed := 0.0
var _messages: Array[String] = []


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
		var c: Control = _controls[id]
		if not is_instance_valid(c) or not c.is_inside_tree():
			_controls.erase(id)
			continue
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
		"settings": {"text_scale": Settings.text_scale(), "reduce_motion": Settings.reduce_motion},
	}
