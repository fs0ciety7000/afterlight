extends TestCase
## ROADMAP 1.11 and 7.7 (headless part): at 130 % text size, the screens
## reachable without the 3D world fit the E2E viewports. Nothing leaves the
## viewport (lists scroll vertically, never sideways) and no clipped or
## ellipsized label hides part of its text.

## Logical UI sizes of the E2E projects (Main._fit_ui_scale): desktop
## 1280x720, Pixel 7 landscape (863x360 CSS, min 640 logical height) and
## iPad landscape (1080x810 CSS).
const VIEWPORTS := {
	"desktop": [Vector2i(1280, 720), 1.0],
	"mobile": [Vector2i(1534, 640), 0.5625],
	"tablet": [Vector2i(1080, 810), 1.0],
}
const SCREENS := {
	"title": "res://game/app/screens/title_screen.gd",
	"settings": "res://game/app/screens/settings_screen.gd",
	"character": "res://game/app/screens/character_screen.gd",
	"bag": "res://game/app/screens/bag_screen.gd",
	"forge": "res://game/app/screens/forge_screen.gd",
	"runecarver": "res://game/app/screens/runecarver_screen.gd",
	"merchant": "res://game/app/screens/merchant_screen.gd",
	"hunts": "res://game/app/screens/hunts_screen.gd",
	"journal": "res://game/app/screens/journal_screen.gd",
	"world_map": "res://game/app/screens/world_map_screen.gd",
	"offline_summary": "res://game/app/screens/offline_summary_screen.gd",
	"grimoire": "res://game/app/screens/grimoire_screen.gd",
}
const TEXT_SCALE_INDEX := 3
const TOLERANCE := 1.0
## Narrowest acceptable column for a wrapped label.
const MIN_WRAP_WIDTH := 96.0


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_text_scale_130_is_the_largest_setting() -> void:
	assert_near(UiTokens.TEXT_SCALES[TEXT_SCALE_INDEX], 1.3, 0.001, "130 %")


func test_key_screens_fit_at_130_percent() -> void:
	TranslationServer.set_locale("fr")
	GameState.start_new(Content.start())
	GameState.data["wallet"]["gold"] = 1000
	for vp_name: String in VIEWPORTS:
		for id: String in SCREENS:
			_check(vp_name, id, {})
		_check(vp_name, "settings", {"tab": "controls"})
	GameState.clear()


func test_title_without_a_game_fits_at_130_percent() -> void:
	TranslationServer.set_locale("fr")
	for vp_name: String in VIEWPORTS:
		_check(vp_name, "title", {})


func _check(vp_name: String, id: String, params: Dictionary) -> void:
	var size: Vector2i = VIEWPORTS[vp_name][0]
	var saved_css := UiTokens.css_per_logical
	UiTokens.css_per_logical = VIEWPORTS[vp_name][1]
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	_root().add_child(vp)
	var host := Control.new()
	host.theme = ThemeBuilder.build(UiTokens.DAY, UiTokens.TEXT_SCALES[TEXT_SCALE_INDEX])
	host.size = Vector2(size)
	vp.add_child(host)
	var screen: Control = (load(SCREENS[id]) as GDScript).new()
	screen.call("setup", params)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(screen)
	settle(screen)
	var label := "%s %s%s" % [vp_name, id, " " + str(params) if not params.is_empty() else ""]
	for problem in overflow_problems(screen, Rect2(Vector2.ZERO, Vector2(size))):
		failures.append("%s: %s" % [label, problem])
	_root().remove_child(vp)
	vp.free()
	UiTokens.css_per_logical = saved_css


## Lays out `root` now (headless tests have no frame to wait for): wrapped
## labels recompute their height, then containers sort top-down, a few times
## until sizes settle.
static func settle(root: Control) -> void:
	for i in 8:
		for l in root.find_children("*", "Label", true, false):
			(l as Control).update_minimum_size()
		for c in root.find_children("*", "Container", true, false):
			(c as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)


## Visible controls that leave `view` (or, inside a scroll list, leave it
## sideways), and labels whose text is clipped or ellipsized.
static func overflow_problems(root: Control, view: Rect2) -> PackedStringArray:
	var out := PackedStringArray()
	for child in root.get_children():
		if child is Control and (child as Control).visible:
			var need := (child as Control).get_combined_minimum_size()
			if need.x > view.size.x + TOLERANCE:
				out.append("%s needs %s, wider than the viewport" % [_describe(child), need])
	for node in root.find_children("*", "Control", true, false):
		var c := node as Control
		if not c.is_visible_in_tree() or c.size == Vector2.ZERO:
			continue
		var r := c.get_global_rect()
		var scroll := _scroll_parent(c, root)
		var bounds := view if scroll == null else scroll.get_global_rect()
		var name := _describe(c)
		if r.position.x < bounds.position.x - TOLERANCE or r.end.x > bounds.end.x + TOLERANCE:
			out.append("%s leaves the %s sideways (%s)" % [name, _area(scroll), r])
		elif scroll == null and (r.position.y < -TOLERANCE or r.end.y > view.end.y + TOLERANCE):
			out.append("%s leaves the viewport vertically (%s)" % [name, r])
		if _squeezed(c):
			out.append("%s wraps in a column too narrow (%d px)" % [name, roundi(c.size.x)])
		if _truncates(c):
			out.append("%s truncates « %s »" % [name, c.get("text")])
	return out


## A wrapped label left so narrow its longest word barely fits.
static func _squeezed(c: Control) -> bool:
	if not c is Label or (c as Label).autowrap_mode == TextServer.AUTOWRAP_OFF:
		return false
	var l := c as Label
	return l.text.length() > 12 and l.size.x < MIN_WRAP_WIDTH


## A label or button that cuts its single line of text short.
static func _truncates(c: Control) -> bool:
	if not (c is Label or c is Button):
		return false
	var text := str(c.get("text"))
	var cut: bool = (
		c.get("clip_text") or c.get("text_overrun_behavior") != TextServer.OVERRUN_NO_TRIMMING
	)
	if (
		text == ""
		or not cut
		or (c is Label and (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF)
	):
		return false
	var font := c.get_theme_font("font")
	var room := c.size.x
	if c is Button:
		var box := c.get_theme_stylebox("normal")
		room -= box.get_minimum_size().x if box else 0.0
	return (
		(
			font
			. get_string_size(
				text, HORIZONTAL_ALIGNMENT_LEFT, -1, c.get_theme_font_size("font_size")
			)
			. x
		)
		> room + TOLERANCE
	)


static func _scroll_parent(c: Control, root: Control) -> ScrollContainer:
	var p := c.get_parent()
	while p != null and p != root:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


static func _area(scroll: ScrollContainer) -> String:
	return "viewport" if scroll == null else "scroll list"


static func _describe(c: Control) -> String:
	for id: String in UiProbe._controls:
		if is_instance_valid(UiProbe._controls[id]) and UiProbe._controls[id] == c:
			return id
	var text := str(c.get("text")) if "text" in c else ""
	return "%s%s" % [c.get_class(), " « %s »" % text.left(40) if text != "" else ""]
