class_name LevelTag
extends HBoxContainer
## Level of an encounter or a place against the leader's (GDD decision 30):
## « Niveau 2 », or, when it is above Fern's, a `danger` pictogram and
## « Niveau 3 (au-dessus du vôtre) » in the `danger` colour (never the
## colour alone). Fed by GameState.content_api.encounter_level().

var above := false
var label: Label


## `info`: {level, above, key, params} from ContentApi.encounter_level.
## `variation`: the label's look when the level is not above; `palette`:
## UiTokens.DAY or NIGHT (the combat HUD).
static func make(
	info: Dictionary, variation: String = "MutedLabel", palette: Dictionary = UiTokens.DAY
) -> LevelTag:
	var tag := LevelTag.new()
	tag.add_theme_constant_override("separation", UiTokens.SPACE["xs"])
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.above = bool(info.get("above", false))
	if tag.above:
		var mark := _Mark.new()
		mark.color = palette["danger"]
		tag.add_child(mark)
	tag.label = Kit.label(
		TranslationServer.translate(str(info.get("key", "ui.map.level"))).format(
			info.get("params", {})
		),
		"LeadLabel" if tag.above else variation
	)
	if tag.above:
		tag.label.add_theme_color_override("font_color", palette["danger"])
	tag.add_child(tag.label)
	return tag


## Warning triangle with an exclamation mark, in the `danger` colour.
class _Mark:
	extends Control

	var color := Color.RED

	func _init() -> void:
		custom_minimum_size = Vector2(18, 18)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := size
		var c := color
		draw_colored_polygon(
			PackedVector2Array(
				[Vector2(s.x / 2.0, 1.0), Vector2(s.x - 1.0, s.y - 1.0), Vector2(1.0, s.y - 1.0)]
			),
			c
		)
		var ink := Color.WHITE
		draw_line(Vector2(s.x / 2.0, s.y * 0.35), Vector2(s.x / 2.0, s.y * 0.68), ink, 2.0)
		draw_circle(Vector2(s.x / 2.0, s.y * 0.82), 1.2, ink)
