class_name InputActions
extends RefCounted
## Registers the game's input actions. Movement uses physical key positions,
## so W/A/S/D on QWERTY is Z/Q/S/D on AZERTY with no extra setup; shortcuts
## (E, M, +, -) use the printed letter, whatever the layout.

const PHYSICAL := ["move_forward", "move_back", "move_left", "move_right"]
const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E],
	"open_map": [KEY_M],
	"map_zoom_in": [KEY_EQUAL, KEY_KP_ADD],
	"map_zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
}


static func install() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			if action in PHYSICAL:
				ev.physical_keycode = key
			else:
				ev.keycode = key
			InputMap.action_add_event(action, ev)
