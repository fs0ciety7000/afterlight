class_name MinimapButton
extends BaseButton
## Round mini-map (DESIGN.md): the painted region map around the current
## location, with a marker. Pressing it opens the world map.

var diameter := 148.0
var _texture: Texture2D


func _ready() -> void:
	custom_minimum_size = Vector2(diameter, diameter)
	focus_mode = Control.FOCUS_NONE
	var region: String = GameState.data["world"]["region_id"]
	var path: String = Content.get_entity(region).get("map_texture", "")
	if ResourceLoader.exists(path):
		_texture = load(path)
	GameState.changed.connect(queue_redraw)


func _draw() -> void:
	var palette: Dictionary = UiTokens.DAY
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0
	draw_circle(c, r, palette["surface_alt"])
	var location: Dictionary = Content.get_entity(GameState.data["world"]["location_id"])
	var pos: Array = location.get("map_pos", [0.5, 0.5])
	if _texture:
		# Show a window of the map centred on the location, clipped to the circle
		# by drawing a polygon with UVs.
		var tex_size := _texture.get_size()
		var window := tex_size.y * 0.35
		var centre := Vector2(pos[0] * tex_size.x, pos[1] * tex_size.y)
		var points := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in 48:
			var a := TAU * i / 48.0
			var d := Vector2(cos(a), sin(a))
			points.append(c + d * (r - 2.0))
			uvs.append((centre + d * window / 2.0) / tex_size)
		draw_colored_polygon(points, Color.WHITE, uvs, _texture)
	draw_circle(c, 5.0, palette["accent"])
	draw_arc(c, 8.0, 0.0, TAU, 24, palette["accent_ink"], 2.0, true)
	draw_arc(c, r - 1.0, 0.0, TAU, 64, palette["line"], 2.0, true)
