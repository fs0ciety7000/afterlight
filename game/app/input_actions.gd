class_name InputActions
extends RefCounted
## Registers the game's input actions. Movement uses physical key positions,
## so W/A/S/D on QWERTY is Z/Q/S/D on AZERTY with no extra setup; shortcuts
## (E, M, I, C, K, J, +, -) use the printed letter, whatever the layout.
## Every action also has a gamepad binding (Xbox layout names). Players can
## rebind the actions of REMAPPABLE (Settings > Commandes); the overrides are
## stored by Settings and applied by install() at boot.

const PHYSICAL := [
	"move_forward",
	"move_back",
	"move_left",
	"move_right",
	"combat_spell_1",
	"combat_spell_2",
	"combat_spell_3",
	"consumable_1",
	"consumable_2",
]
const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E],
	"open_map": [KEY_M],
	"open_bag": [KEY_I],
	"open_character": [KEY_C],
	"open_grimoire": [KEY_K],
	"open_journal": [KEY_J],
	"map_zoom_in": [KEY_EQUAL, KEY_KP_ADD],
	"map_zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
	"combat_spell_1": [KEY_1, KEY_KP_1],
	"combat_spell_2": [KEY_2, KEY_KP_2],
	"combat_spell_3": [KEY_3, KEY_KP_3],
	"combat_ultimate": [KEY_R],
	"combat_pause": [KEY_SPACE],
	"combat_speed": [KEY_F],
	"consumable_1": [KEY_4, KEY_KP_4],
	"consumable_2": [KEY_5, KEY_KP_5],
}
## Gamepad defaults: {"b": JoyButton} or {"a": JoyAxis, "d": -1 | 1}.
## B and Start stay on ui_cancel (back / game menu), A also confirms in menus.
const PAD := {
	"move_forward": [{"a": JOY_AXIS_LEFT_Y, "d": -1}],
	"move_back": [{"a": JOY_AXIS_LEFT_Y, "d": 1}],
	"move_left": [{"a": JOY_AXIS_LEFT_X, "d": -1}],
	"move_right": [{"a": JOY_AXIS_LEFT_X, "d": 1}],
	"interact": [{"b": JOY_BUTTON_A}],
	"open_map": [{"b": JOY_BUTTON_BACK}],
	"open_bag": [{"b": JOY_BUTTON_DPAD_DOWN}],
	"open_character": [{"b": JOY_BUTTON_DPAD_LEFT}],
	"open_grimoire": [{"b": JOY_BUTTON_DPAD_RIGHT}],
	"open_journal": [{"b": JOY_BUTTON_DPAD_UP}],
	"map_zoom_in": [{"a": JOY_AXIS_RIGHT_Y, "d": -1}],
	"map_zoom_out": [{"a": JOY_AXIS_RIGHT_Y, "d": 1}],
	"combat_spell_1": [{"b": JOY_BUTTON_X}],
	"combat_spell_2": [{"b": JOY_BUTTON_Y}],
	"combat_spell_3": [{"b": JOY_BUTTON_RIGHT_SHOULDER}],
	"combat_ultimate": [{"a": JOY_AXIS_TRIGGER_RIGHT, "d": 1}],
	"combat_pause": [{"b": JOY_BUTTON_RIGHT_STICK}],
	"combat_speed": [{"b": JOY_BUTTON_LEFT_STICK}],
	"consumable_1": [{"b": JOY_BUTTON_LEFT_SHOULDER}],
	"consumable_2": [{"a": JOY_AXIS_TRIGGER_LEFT, "d": 1}],
}
## Actions listed in Settings > Commandes, in display order.
const REMAPPABLE := [
	"move_forward",
	"move_back",
	"move_left",
	"move_right",
	"interact",
	"open_map",
	"open_journal",
	"open_bag",
	"open_character",
	"open_grimoire",
	"combat_spell_1",
	"combat_spell_2",
	"combat_spell_3",
	"combat_ultimate",
	"combat_pause",
	"combat_speed",
	"consumable_1",
	"consumable_2",
]
## Keys and buttons that always open the menu or go back (ui_cancel).
const RESERVED_KEYS := [KEY_ESCAPE]
const RESERVED_BUTTONS := [JOY_BUTTON_B, JOY_BUTTON_START]
## Display servers that map a physical key to the layout's letter.
const LAYOUT_AWARE := ["Windows", "macOS", "X11", "Wayland"]
const KEY_NAMES := {
	KEY_SPACE: "ui.key.space",
	KEY_UP: "ui.key.up",
	KEY_DOWN: "ui.key.down",
	KEY_LEFT: "ui.key.left",
	KEY_RIGHT: "ui.key.right",
	KEY_ENTER: "ui.key.enter",
	KEY_TAB: "ui.key.tab",
	KEY_SHIFT: "ui.key.shift",
	KEY_CTRL: "ui.key.ctrl",
	KEY_BACKSPACE: "ui.key.backspace",
}
const BUTTON_NAMES := {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_BACK: "Select",
}
const DPAD_NAMES := {
	JOY_BUTTON_DPAD_UP: "ui.pad.dpad_up",
	JOY_BUTTON_DPAD_DOWN: "ui.pad.dpad_down",
	JOY_BUTTON_DPAD_LEFT: "ui.pad.dpad_left",
	JOY_BUTTON_DPAD_RIGHT: "ui.pad.dpad_right",
}
const AXIS_NAMES := {
	JOY_AXIS_LEFT_X: ["ui.pad.left_stick_left", "ui.pad.left_stick_right"],
	JOY_AXIS_LEFT_Y: ["ui.pad.left_stick_up", "ui.pad.left_stick_down"],
	JOY_AXIS_RIGHT_X: ["ui.pad.right_stick_left", "ui.pad.right_stick_right"],
	JOY_AXIS_RIGHT_Y: ["ui.pad.right_stick_up", "ui.pad.right_stick_down"],
	JOY_AXIS_TRIGGER_LEFT: ["LT", "LT"],
	JOY_AXIS_TRIGGER_RIGHT: ["RT", "RT"],
}


## Adds the actions with their default bindings, the gamepad Start button to
## ui_cancel, then the player's saved overrides.
static func install(overrides: Dictionary = {}) -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		_add_defaults(action, "key")
		_add_defaults(action, "pad")
	# Godot's ui_accept and ui_cancel have no gamepad button by default.
	for pair: Array in [
		["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B], ["ui_cancel", JOY_BUTTON_START]
	]:
		var b := _button(pair[1])
		if not InputMap.action_has_event(pair[0], b):
			InputMap.action_add_event(pair[0], b)
	apply_overrides(overrides)


## Applies saved overrides: {action: {"key": [...], "pad": [...]}} (see
## to_data). Unknown actions and malformed entries are ignored.
static func apply_overrides(overrides: Dictionary) -> void:
	for action: Variant in overrides:
		if not (action is String and action in REMAPPABLE and overrides[action] is Dictionary):
			continue
		var entry: Dictionary = overrides[action]
		for slot in ["key", "pad"]:
			if not entry.has(slot) or not (entry[slot] is Array):
				continue
			var events: Array[InputEvent] = []
			for d: Variant in entry[slot]:
				var ev := from_data(d)
				if ev != null and slot_of(ev) == slot:
					events.append(ev)
			if not events.is_empty():
				_set_slot(action, slot, events)


## The player's bindings that differ from the defaults, ready to save.
static func overrides() -> Dictionary:
	var out := {}
	for action: String in REMAPPABLE:
		var entry := {}
		for slot in ["key", "pad"]:
			var now := _slot_data(events_of(action, slot))
			if now != _slot_data(_defaults(action, slot)):
				entry[slot] = now
		if not entry.is_empty():
			out[action] = entry
	return out


## Restores every remappable action to its default bindings.
static func reset_all() -> void:
	for action: String in REMAPPABLE:
		for slot in ["key", "pad"]:
			_set_slot(action, slot, _defaults(action, slot))


## Binds `captured` (a real key press or pad input) to `action` in its slot
## ("key" or "pad"). Returns {"ok": bool, "error": translation key or "",
## "swapped_with": action or ""}. When another remappable action already uses
## that input, the two actions swap their bindings for that slot.
static func rebind(action: String, captured: InputEvent) -> Dictionary:
	var result := {"ok": false, "error": "", "swapped_with": ""}
	var binding := to_binding(captured, action)
	if binding == null or not action in REMAPPABLE:
		result["error"] = "ui.controls.error_unsupported"
		return result
	if is_reserved(captured):
		result["error"] = "ui.controls.error_reserved"
		return result
	var slot := slot_of(binding)
	var previous := events_of(action, slot)
	for other: String in REMAPPABLE:
		if other != action and InputMap.event_is_action(captured, other):
			_set_slot(other, slot, previous)
			result["swapped_with"] = other
			break
	_set_slot(action, slot, [binding])
	result["ok"] = true
	return result


## True for inputs kept for the menu and back (Escape, B, Start).
static func is_reserved(event: InputEvent) -> bool:
	if event is InputEventKey:
		var k := event as InputEventKey
		return k.keycode in RESERVED_KEYS or k.physical_keycode in RESERVED_KEYS
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).button_index in RESERVED_BUTTONS
	return false


## True for an input the rebind capture should take (a press, not a release,
## key repeat or stick noise).
static func is_bindable(event: InputEvent) -> bool:
	if event is InputEventKey:
		var k := event as InputEventKey
		return k.pressed and not k.echo
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	if event is InputEventJoypadMotion:
		return absf((event as InputEventJoypadMotion).axis_value) > 0.6
	return false


## The stored form of a captured input: the physical key position for
## movement and spells, the printed letter for shortcuts (as the defaults),
## all gamepads, the stick direction only.
static func to_binding(e: InputEvent, action: String = "") -> InputEvent:
	if e is InputEventKey:
		var src := e as InputEventKey
		var k := InputEventKey.new()
		var physical := src.physical_keycode if src.physical_keycode != KEY_NONE else src.keycode
		var printed := src.keycode if src.keycode != KEY_NONE else src.physical_keycode
		if action == "" or action in PHYSICAL:
			k.physical_keycode = physical
		else:
			k.keycode = printed
		return k
	if e is InputEventJoypadButton:
		return _button((e as InputEventJoypadButton).button_index)
	if e is InputEventJoypadMotion:
		var m := InputEventJoypadMotion.new()
		m.axis = (e as InputEventJoypadMotion).axis
		m.axis_value = signf((e as InputEventJoypadMotion).axis_value)
		m.device = -1
		return m
	return null


static func slot_of(e: InputEvent) -> String:
	if e is InputEventKey:
		return "key"
	if e is InputEventJoypadButton or e is InputEventJoypadMotion:
		return "pad"
	return ""


static func events_of(action: String, slot: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not InputMap.has_action(action):
		return out
	for e in InputMap.action_get_events(action):
		if slot_of(e) == slot:
			out.append(e)
	return out


## "W / Haut", "X", "LT"... The keyboard label follows the player's layout.
static func label(action: String, slot: String) -> String:
	var parts := PackedStringArray()
	for e in events_of(action, slot):
		parts.append(event_label(e))
	return " / ".join(parts)


## The first keyboard key of `action`, for short hints (spell buttons).
static func key_hint(action: String) -> String:
	var keys := events_of(action, "key")
	return event_label(keys[0]) if not keys.is_empty() else ""


static func event_label(e: InputEvent) -> String:
	if e is InputEventKey:
		var k := e as InputEventKey
		var code := k.keycode
		if code == KEY_NONE:
			# The printed letter at that position on the player's layout
			# (Z for the W position on AZERTY), where the platform can tell.
			if DisplayServer.get_name() in LAYOUT_AWARE:
				code = DisplayServer.keyboard_get_label_from_physical(k.physical_keycode)
			if code == KEY_NONE:
				code = k.physical_keycode
		if KEY_NAMES.has(code):
			return TranslationServer.translate(KEY_NAMES[code])
		return OS.get_keycode_string(code)
	if e is InputEventJoypadButton:
		var b := (e as InputEventJoypadButton).button_index
		if DPAD_NAMES.has(b):
			return TranslationServer.translate(DPAD_NAMES[b])
		return BUTTON_NAMES.get(b, "#%d" % b)
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		var names: Array = AXIS_NAMES.get(m.axis, ["", ""])
		return TranslationServer.translate(names[1 if m.axis_value > 0.0 else 0])
	return ""


static func to_data(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		var k := e as InputEventKey
		return {"k": int(k.keycode)} if k.keycode != KEY_NONE else {"p": int(k.physical_keycode)}
	if e is InputEventJoypadButton:
		return {"b": int((e as InputEventJoypadButton).button_index)}
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		return {"a": int(m.axis), "d": 1 if m.axis_value > 0.0 else -1}
	return {}


## Rebuilds an input from its stored form; null when malformed.
static func from_data(d: Variant) -> InputEvent:
	if not d is Dictionary:
		return null
	var data: Dictionary = d
	if data.has("p") or data.has("k"):
		var code := int(data.get("p", data.get("k", 0)))
		if code <= 0 or code in RESERVED_KEYS:
			return null
		var k := InputEventKey.new()
		if data.has("p"):
			k.physical_keycode = code as Key
		else:
			k.keycode = code as Key
		return k
	if data.has("b"):
		var index := int(data["b"])
		if index < 0 or index >= JOY_BUTTON_SDL_MAX or index in RESERVED_BUTTONS:
			return null
		return _button(index as JoyButton)
	if data.has("a"):
		var axis := int(data["a"])
		if axis < 0 or axis >= JOY_AXIS_SDL_MAX:
			return null
		var m := InputEventJoypadMotion.new()
		m.axis = axis as JoyAxis
		m.axis_value = 1.0 if int(data.get("d", 1)) > 0 else -1.0
		m.device = -1
		return m
	return null


## A button of any gamepad.
static func _button(index: JoyButton) -> InputEventJoypadButton:
	var b := InputEventJoypadButton.new()
	b.button_index = index
	b.device = -1
	return b


static func _defaults(action: String, slot: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if slot == "key":
		for key: Key in ACTIONS.get(action, []):
			var ev := InputEventKey.new()
			if action in PHYSICAL:
				ev.physical_keycode = key
			else:
				ev.keycode = key
			out.append(ev)
	else:
		for d: Dictionary in PAD.get(action, []):
			out.append(from_data(d))
	return out


static func _add_defaults(action: String, slot: String) -> void:
	for ev in _defaults(action, slot):
		InputMap.action_add_event(action, ev)


static func _set_slot(action: String, slot: String, events: Array[InputEvent]) -> void:
	for e in events_of(action, slot):
		InputMap.action_erase_event(action, e)
	for e in events:
		InputMap.action_add_event(action, e)


static func _slot_data(events: Array[InputEvent]) -> Array:
	var out := []
	for e in events:
		out.append(to_data(e))
	return out
