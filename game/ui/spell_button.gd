class_name SpellButton
extends BaseButton
## Round spell button (DESIGN.md "HUD combat"): radial cooldown sweep with
## the seconds left, key hint, dimmed when the spell cannot be cast. Shows the painted
## icon (GameIcons) when the spell has one, else its initials.
## Feedback within 120 ms of every press (GDD §14, ROADMAP 7.5): a flash and a short squash on
## press, a red ring and a shake when the sim refuses, a pulsing ring while the cast is queued.
## Reduced motion keeps the colours and drops the squash, the shake and the pulse.

const PRESS_S := 0.12
const REJECT_S := 0.3
const SHAKE_PX := 4.0

## Presses answered since boot (all buttons), for the E2E probe.
static var presses := 0

var spell_id := ""
var key_hint := ""
var big := false
var cooldown_s := 0.0
var cooldown_total := 0.0
var charge_ratio := 1.0
var usable := true
## The sim holds this spell in its input buffer (it starts when the current action ends).
var queued := false:
	set(value):
		if value != queued:
			queued = value
			_wake()
var reduce_motion := false
var _press_left := 0.0
var _reject_left := 0.0
var _label_name := ""
var _icon: Texture2D


func setup(id: String, hint: String, is_ultimate: bool = false) -> void:
	spell_id = id
	key_hint = hint
	big = is_ultimate
	var side := 84.0 if big else 68.0
	custom_minimum_size = Vector2(side, side)
	focus_mode = Control.FOCUS_NONE
	_label_name = Content.display_name(id)
	_icon = GameIcons.for_id(id)
	tooltip_text = _label_name
	set_process(false)


## The player asked for this spell (click, tap or key): answer right away, before the sim does.
func press_feedback() -> void:
	presses += 1
	_press_left = PRESS_S
	_wake()


## The sim refused the cast (no mana, cooldown...): red ring and a small shake.
func reject_feedback() -> void:
	_reject_left = REJECT_S
	_wake()


func _wake() -> void:
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_press_left = maxf(_press_left - delta, 0.0)
	_reject_left = maxf(_reject_left - delta, 0.0)
	queue_redraw()
	if _press_left <= 0.0 and _reject_left <= 0.0 and (not queued or reduce_motion):
		set_process(false)


func _draw() -> void:
	var p: Dictionary = UiTokens.NIGHT
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 2.0
	var press := _press_left / PRESS_S
	var reject := _reject_left / REJECT_S
	if not reduce_motion:
		r *= 1.0 - 0.08 * press
		if reject > 0.0:
			draw_set_transform(Vector2(sin(reject * 30.0) * SHAKE_PX * reject, 0.0))
	var fill: Color = p["surface"]
	if is_hovered():
		fill = fill.lightened(0.1)
	fill = fill.lightened(0.3 * press)
	draw_circle(c, r, Color(fill, 0.92))
	var ring: Color = p["accent"] if big else p["line"]
	var ring_w := (2.0 if big else 1.5) + 1.5 * press
	ring = ring.lerp(p["accent"].lightened(0.3), press).lerp(p["danger"], reject)
	if reject > 0.0:
		ring_w = maxf(ring_w, 3.0)
	draw_arc(c, r, 0.0, TAU, 48, ring, ring_w, true)
	if queued:
		var pulse := 1.0 if reduce_motion else 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
		draw_arc(c, r - 4.0, 0.0, TAU, 48, Color(p["accent"].lightened(0.35), pulse), 2.5, true)
	var font := get_theme_default_font()
	if _icon:
		var side := r * 1.5
		draw_texture_rect(_icon, Rect2(c - Vector2(side, side) / 2.0, Vector2(side, side)), false)
	else:
		# Spell initials as a compact glyph when the spell has no painted icon.
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
