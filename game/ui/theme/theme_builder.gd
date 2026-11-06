class_name ThemeBuilder
extends RefCounted
## Builds a Godot Theme from a token palette (UiTokens.DAY / NIGHT).
## Type variations used by screens: TitleLabel, HeadingLabel, SubheadingLabel,
## MutedLabel, NumberLabel, PrimaryButton, SecondaryButton, CardPanel, ErrorLabel.

const SERIF := "res://assets/fonts/CormorantGaramond-SemiBold.ttf"
const SANS := "res://assets/fonts/AlegreyaSans-Regular.ttf"
const SANS_MEDIUM := "res://assets/fonts/AlegreyaSans-Medium.ttf"
const SANS_BOLD := "res://assets/fonts/AlegreyaSans-Bold.ttf"


static func build(palette: Dictionary, text_scale: float = 1.0) -> Theme:
	var t := Theme.new()
	var size := func(key: String) -> int: return roundi(UiTokens.FONT_SIZES[key] * text_scale)
	var serif: Font = load(SERIF)
	var sans: Font = load(SANS)
	var sans_medium: Font = load(SANS_MEDIUM)
	var numbers := FontVariation.new()
	numbers.base_font = load(SANS_BOLD)
	numbers.opentype_features = {"tnum": 1, "lnum": 1}

	t.default_font = sans
	t.default_font_size = size.call("body")
	var ink: Color = palette["ink"]
	var muted: Color = palette["ink_muted"]

	t.set_color("font_color", "Label", ink)
	_label_variant(t, "TitleLabel", serif, size.call("h1"), ink)
	_label_variant(t, "DisplayLabel", serif, size.call("display"), ink)
	_label_variant(t, "HeadingLabel", serif, size.call("h2"), ink)
	_label_variant(t, "SubheadingLabel", serif, size.call("h3"), ink)
	_label_variant(t, "MutedLabel", sans, size.call("small"), muted)
	_label_variant(t, "LeadLabel", sans, size.call("lead"), ink)
	_label_variant(t, "NumberLabel", numbers, size.call("lead"), ink)
	_label_variant(t, "ErrorLabel", sans_medium, size.call("body"), palette["danger"])

	# Panels
	t.set_stylebox("panel", "PanelContainer", _box(palette["surface"], palette["line"], 1, true))
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", _box(palette["surface_alt"], palette["line"], 1, false))
	t.set_type_variation("ScrimPanel", "PanelContainer")
	t.set_stylebox("panel", "ScrimPanel", _box(palette["scrim"], Color.TRANSPARENT, 0, false, 0))

	# Buttons: secondary is the default look, primary is the accent variation.
	_button(
		t,
		"Button",
		palette,
		palette["surface"].lerp(palette["surface_alt"], 0.5),
		ink,
		palette["line"]
	)
	t.set_font("font", "Button", sans_medium)
	t.set_font_size("font_size", "Button", size.call("lead"))
	t.set_type_variation("SecondaryButton", "Button")
	t.set_type_variation("PrimaryButton", "Button")
	_button(
		t, "PrimaryButton", palette, palette["accent"], palette["accent_ink"], palette["accent"]
	)

	# Check buttons / option buttons inherit Button colors.
	for type_name in ["CheckButton", "CheckBox", "OptionButton"]:
		t.set_font("font", type_name, sans_medium)
		t.set_font_size("font_size", type_name, size.call("body"))
		t.set_color("font_color", type_name, ink)
		t.set_color("font_hover_color", type_name, ink)
		t.set_color("font_pressed_color", type_name, ink)
		t.set_color("font_focus_color", type_name, ink)
	_button(t, "OptionButton", palette, palette["surface"], ink, palette["line"])

	t.set_stylebox("panel", "PopupMenu", _box(palette["surface"], palette["line"], 1, true))
	t.set_color("font_color", "PopupMenu", ink)
	t.set_color("font_hover_color", "PopupMenu", ink)
	t.set_stylebox("hover", "PopupMenu", _box(palette["surface_alt"], Color.TRANSPARENT, 0, false))

	t.set_stylebox(
		"background", "ProgressBar", _box(palette["surface_alt"], palette["line"], 1, false, 2)
	)
	t.set_stylebox("fill", "ProgressBar", _box(palette["mana"], Color.TRANSPARENT, 0, false, 2))
	t.set_color("font_color", "ProgressBar", ink)

	t.set_constant("separation", "VBoxContainer", UiTokens.SPACE["md"])
	t.set_constant("separation", "HBoxContainer", UiTokens.SPACE["md"])
	t.set_color("font_color", "RichTextLabel", ink)
	t.set_color("default_color", "RichTextLabel", ink)
	t.set_font("normal_font", "RichTextLabel", sans)
	t.set_font_size("normal_font_size", "RichTextLabel", size.call("body"))
	t.set_meta("palette", palette)
	return t


static func _label_variant(
	t: Theme, name: String, font: Font, font_size: int, color: Color
) -> void:
	t.set_type_variation(name, "Label")
	t.set_font("font", name, font)
	t.set_font_size("font_size", name, font_size)
	t.set_color("font_color", name, color)


static func _button(
	t: Theme, type_name: String, palette: Dictionary, bg: Color, fg: Color, border: Color
) -> void:
	var pad := Vector2(UiTokens.SPACE["xl"], UiTokens.SPACE["md"])
	t.set_stylebox("normal", type_name, _box(bg, border, 1, false, UiTokens.RADIUS, pad))
	t.set_stylebox(
		"hover",
		type_name,
		_box(bg.lightened(0.08), palette["focus"], 1, false, UiTokens.RADIUS, pad)
	)
	t.set_stylebox(
		"pressed",
		type_name,
		_box(bg.darkened(0.08), palette["focus"], 1, false, UiTokens.RADIUS, pad)
	)
	t.set_stylebox(
		"disabled",
		type_name,
		_box(Color(bg, bg.a * 0.5), Color(border, 0.4), 1, false, UiTokens.RADIUS, pad)
	)
	var focus := _box(Color.TRANSPARENT, palette["focus"], 2, false, UiTokens.RADIUS + 2)
	focus.expand_margin_left = 3
	focus.expand_margin_right = 3
	focus.expand_margin_top = 3
	focus.expand_margin_bottom = 3
	t.set_stylebox("focus", type_name, focus)
	t.set_color("font_color", type_name, fg)
	t.set_color("font_hover_color", type_name, fg)
	t.set_color("font_pressed_color", type_name, fg)
	t.set_color("font_focus_color", type_name, fg)
	t.set_color("font_hover_pressed_color", type_name, fg)
	t.set_color("font_disabled_color", type_name, Color(fg, 0.5))


static func _box(
	bg: Color,
	border: Color,
	border_width: int,
	shadow: bool,
	radius: int = UiTokens.RADIUS,
	padding: Vector2 = Vector2(UiTokens.SPACE["xl"], UiTokens.SPACE["xl"])
) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = padding.x
	s.content_margin_right = padding.x
	s.content_margin_top = padding.y
	s.content_margin_bottom = padding.y
	s.anti_aliasing = true
	if shadow:
		s.shadow_color = Color(0, 0, 0, 0.25)
		s.shadow_size = 12
		s.shadow_offset = Vector2(0, 8)
	return s
