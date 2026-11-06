class_name InputActions
extends RefCounted
## Registers the game's input actions. Movement uses physical key positions,
## so W/A/S/D on QWERTY is Z/Q/S/D on AZERTY with no extra setup; shortcuts
## (E, M, I, C, K, +, -) use the printed letter, whatever the layout.

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
