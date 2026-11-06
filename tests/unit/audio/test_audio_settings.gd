extends TestCase
## Sound settings: one volume per bus, saved in Settings (user://settings.cfg),
## applied to the Audio buses at once, and the "Son" tab fits the E2E
## viewports at 130 % text size.

const Layout := preload("res://tests/unit/ui/test_text_scale_layout.gd")


func test_volume_is_saved_and_applied() -> void:
	var before := Settings.volumes.duplicate()
	Settings.set_volume("Music", 0.35)
	assert_near(Audio.get_bus_volume("Music"), 0.35, 0.001, "applied to the bus")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(Settings.PATH), OK, "settings file written")
	assert_near(float(cfg.get_value("audio", "Music", -1.0)), 0.35, 0.001, "saved")
	Settings.set_volume("Ambience", 0.0)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Ambience")), "0 mutes")
	Settings.set_volume("Nope", 0.5)
	assert_true(not Settings.volumes.has("Nope"), "unknown bus ignored")
	Settings.set_volume("SFX", 3.0)
	assert_near(Settings.volume("SFX"), 1.0, 0.001, "clamped")
	for bus: String in Settings.VOLUME_BUSES:
		Settings.set_volume(bus, float(before.get(bus, 1.0)))


func test_every_settings_bus_is_an_audio_bus() -> void:
	for bus: String in Settings.VOLUME_BUSES:
		assert_true(bus in AudioCatalog.BUSES, "%s is a bus" % bus)


func test_sound_tab_has_a_slider_per_bus_and_fits() -> void:
	TranslationServer.set_locale("fr")
	for vp_name: String in Layout.VIEWPORTS:
		var size: Vector2i = Layout.VIEWPORTS[vp_name][0]
		var saved_css := UiTokens.css_per_logical
		UiTokens.css_per_logical = Layout.VIEWPORTS[vp_name][1]
		var vp := SubViewport.new()
		vp.size = size
		vp.disable_3d = true
		(Engine.get_main_loop() as SceneTree).root.add_child(vp)
		var host := Control.new()
		host.theme = ThemeBuilder.build(UiTokens.DAY, UiTokens.TEXT_SCALES[Layout.TEXT_SCALE_INDEX])
		host.size = Vector2(size)
		vp.add_child(host)
		var screen: Control = (load("res://game/app/screens/settings_screen.gd") as GDScript).new()
		screen.call("setup", {"tab": "sound"})
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.add_child(screen)
		Layout.settle(screen)
		assert_eq(screen.find_children("*", "HSlider", true, false).size(), 5, "5 sliders")
		for problem in Layout.overflow_problems(screen, Rect2(Vector2.ZERO, Vector2(size))):
			failures.append("%s sound tab: %s" % [vp_name, problem])
		vp.get_parent().remove_child(vp)
		vp.free()
		UiTokens.css_per_logical = saved_css
