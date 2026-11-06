class_name SpellButton
extends BaseButton
## Round spell button (DESIGN.md "HUD combat"): radial cooldown sweep with
## the seconds left, key hint, dimmed when the spell cannot be cast.

var spell_id := ""
var key_hint := ""
var big := false
var cooldown_s := 0.0
var cooldown_total := 0.0
var charge_ratio := 1.0
var usable := true
var _label_name := ""


func setup(id: String, hint: String, is_ultimate: bool = false) -> void:
	spell_id = id
	key_hint = hint
	big = is_ultimate
	var side := 84.0 if big else 68.0
	custom_minimum_size = Vector2(side, side)
	focus_mode = Control.FOCUS_NONE
	_label_name = Content.display_name(id)
	tooltip_text = _label_name


func _draw() -> void:
	var p: Dictionary = UiTokens.NIGHT
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 2.0
	var fill: Color = p["surface"]
	if is_hovered():
		fill = fill.lightened(0.1)
	draw_circle(c, r, Color(fill, 0.92))
	var ring: Color = p["accent"] if big else p["line"]
	draw_arc(c, r, 0.0, TAU, 48, ring, 2.0 if big else 1.5, true)
	var font := get_theme_default_font()
	# Spell initials as a compact glyph until the icon set (A4) exists.
	var initials := _initials(_label_name)
	var fs := 22 if big else 18
	var ts := font.get_string_size(initials, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(
		font,
		c + Vector2(-ts.x / 2.0, ts.y / 3.0),
		initials,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		fs,
		p["pearl"] if p.has("pearl") else p["ink"]
	)
	if charge_ratio < 1.0:
		_draw_sector(c, r - 3.0, 1.0 - charge_ratio, Color(0, 0, 0, 0.55))
	if cooldown_s > 0.0 and cooldown_total > 0.0:
		_draw_sector(c, r - 3.0, cooldown_s / cooldown_total, Color(0, 0, 0, 0.6))
		var secs := str(ceili(cooldown_s))
		var ss := font.get_string_size(secs, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
		draw_string(
			font,
			c + Vector2(-ss.x / 2.0, ss.y / 3.0),
			secs,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			20,
			Color.WHITE
		)
	if not usable and cooldown_s <= 0.0:
		draw_circle(c, r - 3.0, Color(0, 0, 0, 0.35))
	if key_hint != "":
		draw_string(
			font,
			Vector2(size.x - 16.0, size.y - 4.0),
			key_hint,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			p["ink_muted"]
		)


func _draw_sector(c: Vector2, r: float, ratio: float, color: Color) -> void:
	var pts := PackedVector2Array([c])
	var steps := 32
	for i in steps + 1:
		var a := -PI / 2.0 + TAU * ratio * i / steps
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	if pts.size() >= 3:
		draw_colored_polygon(pts, color)


static func _initials(text: String) -> String:
	var parts := text.split(" ", false)
	if parts.size() >= 2:
		return (parts[0].left(1) + parts[parts.size() - 1].left(1)).to_upper()
	return text.left(2)
