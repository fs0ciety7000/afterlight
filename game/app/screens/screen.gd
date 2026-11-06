class_name Screen
extends Control
## Base class for full-screen UI screens.

const KEYART := "res://assets/textures/ui/title_day.jpg"
const NARROW_WIDTH := 1000.0


func setup(_params: Dictionary) -> void:
	pass


func is_narrow() -> bool:
	return get_viewport_rect().size.x < NARROW_WIDTH


## Full-bleed key art with a soft scrim; `strength` 0..1.
func add_backdrop(strength: float = 0.0) -> void:
	var art := TextureRect.new()
	art.texture = load(KEYART)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	var ink: Color = UiTokens.DAY["ink"]
	gradient.set_color(0, Color(ink, 0.55 + 0.35 * strength))
	gradient.set_color(1, Color(ink, 0.05 + 0.5 * strength))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0, 0.5)
	tex.fill_to = Vector2(1, 0.5)
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)


## Shows a transient status line in `target`.
func flash(target: Label, message: String, is_error: bool = false) -> void:
	target.text = message
	target.theme_type_variation = "ErrorLabel" if is_error else "MutedLabel"
	UiProbe.note(message)
