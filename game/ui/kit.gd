class_name Kit
extends RefCounted
## Small builders for consistent UI. Styling comes from the theme.


static func label(text: String, variation: String = "", wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, primary: bool = false, probe_id: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "PrimaryButton" if primary else "SecondaryButton"
	b.custom_minimum_size = Vector2(0, UiTokens.TOUCH_TARGET)
	b.focus_mode = Control.FOCUS_ALL
	if probe_id != "":
		UiProbe.register(probe_id, b)
	Audio.hook_button(b, primary, probe_id)
	return b


static func vbox(separation: int = UiTokens.SPACE["md"]) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation: int = UiTokens.SPACE["md"]) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func panel(variation: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	if variation != "":
		p.theme_type_variation = variation
	return p


## Screen margins from DESIGN.md: 24 px desktop, 16 px on narrow screens.
static func margin(child: Control, narrow: bool) -> MarginContainer:
	var m := MarginContainer.new()
	var px: int = UiTokens.SPACE["lg"] if narrow else UiTokens.SPACE["xl"]
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, px)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_child(child)
	return m


static func format_duration(seconds: int) -> String:
	var h := seconds / 3600
	var m := (seconds % 3600) / 60
	return "%d h %02d" % [h, m] if h > 0 else "%d min" % m


static func format_time(unix: int) -> String:
	var t := Time.get_datetime_dict_from_unix_time(unix + _utc_offset_seconds())
	return "%02d:%02d" % [t["hour"], t["minute"]]


static func format_date(unix: int) -> String:
	var t := Time.get_datetime_dict_from_unix_time(unix + _utc_offset_seconds())
	return "%02d/%02d/%d %02d:%02d" % [t["day"], t["month"], t["year"], t["hour"], t["minute"]]


static func _utc_offset_seconds() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
