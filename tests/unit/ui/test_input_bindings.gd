extends TestCase
## ROADMAP 7.6 and GDD §15: every action has keyboard and gamepad defaults,
## rebinding swaps on conflict, refuses the menu keys, survives a save
## round trip and resets to the defaults.


func _press(key: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = key
	e.physical_keycode = key
	e.pressed = true
	return e


func _pad(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	e.device = 0
	return e


func _fresh() -> void:
	InputActions.install()
	InputActions.reset_all()


func test_every_action_has_keyboard_and_gamepad_defaults() -> void:
	_fresh()
	for action: String in InputActions.ACTIONS:
		assert_true(InputMap.has_action(action), action)
		assert_true(not InputActions.events_of(action, "key").is_empty(), action + " key")
		assert_true(not InputActions.events_of(action, "pad").is_empty(), action + " pad")


func test_remappable_defaults_do_not_conflict() -> void:
	_fresh()
	for slot in ["key", "pad"]:
		var seen := {}
		for action: String in InputActions.REMAPPABLE:
			for e in InputActions.events_of(action, slot):
				var id := JSON.stringify(InputActions.to_data(e))
				assert_true(not seen.has(id), "%s %s also used by %s" % [action, id, seen.get(id)])
				seen[id] = action


func test_gamepad_back_and_menu_buttons_stay_on_ui_cancel() -> void:
	_fresh()
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_B), "ui_cancel"), "B goes back")
	assert_true(
		InputMap.event_is_action(_pad(JOY_BUTTON_START), "ui_cancel"), "Start opens the menu"
	)
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_A), "ui_accept"), "A confirms")
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_A), "interact"), "A interacts")
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_X), "combat_spell_1"), "X casts spell 1")


func test_rebind_spell_1_moves_the_key() -> void:
	_fresh()
	var r := InputActions.rebind("combat_spell_1", _press(KEY_G))
	assert_true(r["ok"], "rebind ok")
	assert_eq(r["swapped_with"], "", "no conflict")
	assert_true(InputMap.event_is_action(_press(KEY_G), "combat_spell_1"), "G casts spell 1")
	assert_true(not InputMap.event_is_action(_press(KEY_1), "combat_spell_1"), "1 no longer does")
	assert_eq(InputActions.key_hint("combat_spell_1"), "G", "hint")
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_X), "combat_spell_1"), "pad kept")
	assert_eq(InputActions.overrides().keys(), ["combat_spell_1"], "one override")
	InputActions.reset_all()


func test_conflict_swaps_the_two_actions() -> void:
	_fresh()
	var r := InputActions.rebind("combat_spell_1", _press(KEY_2))
	assert_true(r["ok"], "ok")
	assert_eq(r["swapped_with"], "combat_spell_2", "swapped")
	assert_true(InputMap.event_is_action(_press(KEY_2), "combat_spell_1"), "2 -> spell 1")
	assert_true(not InputMap.event_is_action(_press(KEY_2), "combat_spell_2"), "2 left spell 2")
	assert_true(InputMap.event_is_action(_press(KEY_1), "combat_spell_2"), "1 -> spell 2")
	var p := InputActions.rebind("combat_spell_1", _pad(JOY_BUTTON_A))
	assert_eq(p["swapped_with"], "interact", "pad swap")
	assert_true(InputMap.event_is_action(_pad(JOY_BUTTON_X), "interact"), "X -> interact")
	InputActions.reset_all()


func test_menu_keys_are_refused() -> void:
	_fresh()
	var r := InputActions.rebind("interact", _press(KEY_ESCAPE))
	assert_true(not r["ok"], "escape refused")
	assert_eq(r["error"], "ui.controls.error_reserved", "reason")
	assert_true(not InputActions.rebind("interact", _pad(JOY_BUTTON_START))["ok"], "start refused")
	assert_true(InputMap.event_is_action(_press(KEY_E), "interact"), "E kept")
	assert_true(InputActions.overrides().is_empty(), "nothing changed")


func test_overrides_round_trip_and_reset() -> void:
	_fresh()
	InputActions.rebind("combat_spell_1", _press(KEY_G))
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_RIGHT_X
	stick.axis_value = 0.9
	InputActions.rebind("combat_ultimate", stick)
	var saved := InputActions.overrides()
	# What Settings writes is plain data: it survives a ConfigFile round trip.
	var cfg := ConfigFile.new()
	cfg.set_value("input", "bindings", saved)
	var back := ConfigFile.new()
	assert_eq(back.parse(cfg.encode_to_text()), OK, "parse")
	InputActions.reset_all()
	assert_true(InputMap.event_is_action(_press(KEY_1), "combat_spell_1"), "reset")
	InputActions.apply_overrides(back.get_value("input", "bindings"))
	assert_true(InputMap.event_is_action(_press(KEY_G), "combat_spell_1"), "G restored")
	assert_true(InputMap.event_is_action(stick, "combat_ultimate"), "stick restored")
	assert_eq(InputActions.overrides(), saved, "same overrides")
	InputActions.reset_all()
	assert_true(InputActions.overrides().is_empty(), "defaults")


func test_malformed_overrides_are_ignored() -> void:
	_fresh()
	(
		InputActions
		. apply_overrides(
			{
				"combat_spell_1": {"key": [{"p": -4}, "x", {"k": KEY_ESCAPE}]},
				"combat_spell_2": {"key": [{"b": 2}]},
				"not_an_action": {"key": [{"p": KEY_G}]},
				"interact": "E",
				7: {},
			}
		)
	)
	assert_true(InputActions.overrides().is_empty(), "nothing applied")
	assert_true(InputMap.event_is_action(_press(KEY_1), "combat_spell_1"), "1 kept")


func test_every_label_is_translated() -> void:
	_fresh()
	var keys := ContentLoader.translation_keys("res://game/i18n/strings.csv")
	for action: String in InputActions.REMAPPABLE:
		assert_true(keys.has("ui.controls.action." + action), action)
		for slot in ["key", "pad"]:
			assert_true(InputActions.label(action, slot) != "", "%s %s label" % [action, slot])
	for table: Dictionary in [InputActions.KEY_NAMES, InputActions.DPAD_NAMES]:
		for code: int in table:
			assert_true(keys.has(table[code]), table[code])
	for axis: int in InputActions.AXIS_NAMES:
		for key: String in InputActions.AXIS_NAMES[axis]:
			assert_true(key.length() <= 2 or keys.has(key), key)
