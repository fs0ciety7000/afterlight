class_name ItemTile
extends Button
## Square tile for an item, a rune, a consumable or a material, drawn in code
## (no image): a glyph of the slot or kind, the rarity frame pattern
## (DESIGN.md: simple, double, ornate; never colour alone) and the
## enhancement level. Empty tiles show a faint frame.

const KIND_ITEM := "item"
const KIND_RUNE := "rune"
const KIND_CONSUMABLE := "consumable"
const KIND_MATERIAL := "material"
const KIND_EMPTY := "empty"

var kind := KIND_EMPTY
## Equipment slot ("weapon"...) for items, element group for runes.
var glyph := ""
var rarity := ""
var enhance := 0
var tier := 0
var selected := false


static func make(side: float) -> ItemTile:
	var t := ItemTile.new()
	t.theme_type_variation = "SecondaryButton"
	var s := UiTokens.at_least_css(side)
	t.custom_minimum_size = Vector2(s, s)
	t.focus_mode = Control.FOCUS_ALL
	return t


func show_item(item: Dictionary, slot: String) -> void:
	kind = KIND_ITEM
	glyph = slot
	rarity = str(item.get("rarity", "common"))
	enhance = int(item.get("enhance", 0))
	tooltip_text = (
		ProgressionText.item_name(item)
		+ ProgressionText.tr_key("ui.common.separator")
		+ ProgressionText.rarity_name(rarity)
	)
	queue_redraw()


func show_rune(rune_id: String, rune_tier: int) -> void:
	kind = KIND_RUNE
	glyph = rune_id
	tier = rune_tier
	rarity = ""
	tooltip_text = ProgressionText.rune_name(rune_id, rune_tier)
	queue_redraw()


func show_kind(what: String, id: String = "") -> void:
	kind = what
	glyph = id
	rarity = ""
	tooltip_text = Content.display_name(id) if id != "" else ""
	queue_redraw()


func _draw() -> void:
	var palette: Dictionary = UiTokens.DAY
	var r := Rect2(Vector2.ZERO, size)
	var pad := float(UiTokens.SPACE["xs"])
	var inner := r.grow(-pad)
	var line: Color = palette["line"]
	if kind == KIND_EMPTY:
		draw_rect(inner, Color(line, 0.35), false, 1.0)
		return
	var frame: Color = ProgressionText.rarity_color(rarity) if rarity != "" else line
	_draw_frame(inner, frame)
	_draw_glyph(inner.grow(-pad * 2.0), palette["ink"])
	var font := get_theme_default_font()
	var font_size: int = UiTokens.FONT_SIZES["small"]
	var badge := ""
	if kind == KIND_ITEM and enhance > 0:
		badge = ProgressionText.tr_key("ui.fmt.plus").format({"value": enhance})
	elif kind == KIND_RUNE and tier > 0:
		badge = ProgressionText.ROMAN[clampi(tier, 1, 5) - 1]
	if badge != "":
		var at := Vector2(inner.end.x - pad, inner.end.y - pad)
		var w := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(
			font,
			at - Vector2(w, 0),
			badge,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			palette["ink"]
		)
	if selected:
		draw_rect(r.grow(-1.0), palette["focus"], false, 3.0)


## Common and uncommon: simple frame (thicker for uncommon); rare: double;
## epic: double with corner diamonds; legendary: ornate (diamonds on corners
## and edges).
func _draw_frame(rect: Rect2, color: Color) -> void:
	match rarity:
		"uncommon":
			draw_rect(rect, color, false, 2.5)
		"rare", "epic", "legendary":
			draw_rect(rect, color, false, 1.5)
			draw_rect(rect.grow(-4.0), color, false, 1.5)
			if rarity != "rare":
				for p in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end]:
					_diamond(p, 4.5, color)
				_diamond(Vector2(rect.position.x, rect.end.y), 4.5, color)
			if rarity == "legendary":
				var c := rect.get_center()
				for p in [
					Vector2(c.x, rect.position.y),
					Vector2(c.x, rect.end.y),
					Vector2(rect.position.x, c.y),
					Vector2(rect.end.x, c.y)
				]:
					_diamond(p, 3.5, color)
		_:
			draw_rect(rect, color, false, 1.0)


func _diamond(at: Vector2, half: float, color: Color) -> void:
	draw_colored_polygon(
		PackedVector2Array(
			[
				at + Vector2(0, -half),
				at + Vector2(half, 0),
				at + Vector2(0, half),
				at - Vector2(half, 0)
			]
		),
		color
	)


## Line glyphs (1.5 px family, DESIGN.md "Icônes").
func _draw_glyph(box: Rect2, ink: Color) -> void:
	var c := box.get_center()
	var s := minf(box.size.x, box.size.y) / 2.0
	var w := 1.5
	match kind:
		KIND_RUNE:
			var d := PackedVector2Array(
				[
					c + Vector2(0, -s),
					c + Vector2(s * 0.7, 0),
					c + Vector2(0, s),
					c + Vector2(-s * 0.7, 0)
				]
			)
			d.append(d[0])
			draw_polyline(d, ink, w, true)
			draw_line(c + Vector2(0, -s * 0.5), c + Vector2(0, s * 0.5), ink, w, true)
			draw_line(c + Vector2(-s * 0.3, -s * 0.1), c + Vector2(s * 0.3, s * 0.1), ink, w, true)
		KIND_CONSUMABLE:
			draw_arc(c + Vector2(0, s * 0.3), s * 0.55, 0.0, TAU, 24, ink, w, true)
			draw_rect(
				Rect2(c + Vector2(-s * 0.18, -s * 0.85), Vector2(s * 0.36, s * 0.6)), ink, false, w
			)
		KIND_MATERIAL:
			var g := PackedVector2Array(
				[
					c + Vector2(-s * 0.6, -s * 0.2),
					c + Vector2(-s * 0.3, -s * 0.6),
					c + Vector2(s * 0.3, -s * 0.6),
					c + Vector2(s * 0.6, -s * 0.2),
					c + Vector2(0, s * 0.7),
				]
			)
			g.append(g[0])
			draw_polyline(g, ink, w, true)
		_:
			_draw_slot_glyph(c, s, ink, w)


func _draw_slot_glyph(c: Vector2, s: float, ink: Color, w: float) -> void:
	match glyph:
		"weapon":
			draw_line(c + Vector2(-s * 0.6, s * 0.9), c + Vector2(s * 0.4, -s * 0.5), ink, w, true)
			draw_arc(c + Vector2(s * 0.5, -s * 0.6), s * 0.3, 0.0, TAU, 20, ink, w, true)
		"head":
			draw_arc(c + Vector2(0, s * 0.3), s * 0.7, PI, TAU, 20, ink, w, true)
			draw_line(c + Vector2(-s * 0.7, s * 0.3), c + Vector2(s * 0.7, s * 0.3), ink, w, true)
			draw_line(c + Vector2(0, -s * 0.4), c + Vector2(s * 0.3, -s * 0.8), ink, w, true)
		"chest":
			var robe := PackedVector2Array(
				[
					c + Vector2(-s * 0.3, -s * 0.8),
					c + Vector2(s * 0.3, -s * 0.8),
					c + Vector2(s * 0.7, s * 0.8),
					c + Vector2(-s * 0.7, s * 0.8),
				]
			)
			robe.append(robe[0])
			draw_polyline(robe, ink, w, true)
		"hands":
			draw_rect(
				Rect2(c + Vector2(-s * 0.45, -s * 0.1), Vector2(s * 0.9, s * 0.8)), ink, false, w
			)
			for i in 4:
				var x := -s * 0.45 + s * 0.3 * i
				draw_line(c + Vector2(x, -s * 0.1), c + Vector2(x, -s * 0.7), ink, w, true)
		"feet":
			var boot := PackedVector2Array(
				[
					c + Vector2(-s * 0.3, -s * 0.8),
					c + Vector2(s * 0.1, -s * 0.8),
					c + Vector2(s * 0.1, s * 0.3),
					c + Vector2(s * 0.7, s * 0.5),
					c + Vector2(s * 0.7, s * 0.8),
					c + Vector2(-s * 0.3, s * 0.8),
				]
			)
			boot.append(boot[0])
			draw_polyline(boot, ink, w, true)
		"amulet":
			draw_line(c + Vector2(-s * 0.6, -s * 0.8), c + Vector2(0, s * 0.1), ink, w, true)
			draw_line(c + Vector2(s * 0.6, -s * 0.8), c + Vector2(0, s * 0.1), ink, w, true)
			draw_arc(c + Vector2(0, s * 0.45), s * 0.35, 0.0, TAU, 20, ink, w, true)
		_:
			draw_arc(c, s * 0.5, 0.0, TAU, 20, ink, w, true)
