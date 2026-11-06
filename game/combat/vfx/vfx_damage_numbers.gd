class_name VfxDamageNumbers
extends Node3D
## Floating combat numbers anchored in 3D (GDD §14, DESIGN.md): white (normal), gold and bigger
## (crit), green with "+" (heal), grey in parentheses (absorbed by a shield). Rise 1.2 m and fade
## over 0.8 s with a 1.3 -> 1 pop in 120 ms; reduce motion: no pop, shorter rise. Hits on the
## same target within 100 ms are merged into one number.

const FONT: Font = preload("res://assets/fonts/AlegreyaSans-Bold.ttf")
const LIFE_S := 0.8
const RISE_M := 1.2
const POP_S := 0.12
const MERGE_S := 0.1
const OUTLINE := Color("#0d1220")
const STYLES := {
	"normal": {"color": Color("#ffffff"), "size": 28},
	"crit": {"color": Color("#f2c14e"), "size": 36},
	"heal": {"color": Color("#9ee08a"), "size": 28},
	"absorbed": {"color": Color("#a7adb8"), "size": 24},
}

## Height above the target origin where numbers start (m).
@export var head_height := 1.9
## World size of one font pixel at the 3/4 combat camera (~11 m): 28 px reads at 1080p.
@export var pixel_size := 0.0075

var _live: Array[Dictionary] = []
var _lane := 0
var _clock := 0.0


func show_number(target: Variant, amount: int, kind: String = "normal", reduced := false) -> void:
	var now := _now()
	for n in _live:
		if n["target"] == target and n["kind"] == kind and now - float(n["born"]) < MERGE_S:
			n["amount"] = int(n["amount"]) + amount
			(n["label"] as Label3D).text = _text(int(n["amount"]), kind)
			return
	var style: Dictionary = STYLES.get(kind, STYLES["normal"])
	var label := Label3D.new()
	label.font = FONT
	label.font_size = int(style["size"])
	label.outline_size = 10
	label.outline_modulate = OUTLINE
	label.modulate = style["color"]
	label.pixel_size = pixel_size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 10
	label.outline_render_priority = 9
	label.double_sided = true
	label.text = _text(amount, kind)
	add_child(label)
	_lane = (_lane + 1) % 3
	var start := VfxBlock.where(target) + Vector3.UP * head_height
	start += Vector3.RIGHT * (float(_lane) - 1.0) * 0.25
	label.global_position = start
	(
		_live
		. append(
			{
				"label": label,
				"target": target,
				"kind": kind,
				"amount": amount,
				"born": now,
				"age": 0.0,
				"start": start,
				"reduced": reduced,
			}
		)
	)


func _process(delta: float) -> void:
	_clock += delta
	var done: Array[Dictionary] = []
	for n in _live:
		n["age"] = float(n["age"]) + delta
		var t := float(n["age"])
		var label := n["label"] as Label3D
		var k := clampf(t / LIFE_S, 0.0, 1.0)
		var rise := (RISE_M * 0.35 if n["reduced"] else RISE_M) * (1.0 - pow(1.0 - k, 2.0))
		label.global_position = (n["start"] as Vector3) + Vector3.UP * rise
		var pop := 1.0
		if not n["reduced"] and t < POP_S:
			pop = lerpf(1.3, 1.0, t / POP_S)
		label.scale = Vector3.ONE * pop
		var a := 1.0 - clampf((k - 0.6) / 0.4, 0.0, 1.0)
		label.modulate.a = a
		label.outline_modulate.a = a
		if k >= 1.0:
			done.append(n)
	for n in done:
		_live.erase(n)
		(n["label"] as Label3D).queue_free()


func live_count() -> int:
	return _live.size()


func _now() -> float:
	return _clock


static func _text(amount: int, kind: String) -> String:
	match kind:
		"heal":
			return "+%d" % amount
		"absorbed":
			return "(%d)" % amount
	return str(amount)
