class_name TipCard
extends PanelContainer
## A dismissable hint card (GDD decision 27): title, text and the tip's
## buttons (« Appliquer le conseil », « Ouvrir les tactiques », « Plus tard »,
## « Fermer »). It never pauses nor blocks the world: only its own rect takes
## clicks. The host acts on `action` (the card closes itself on later/close).
## UiProbe: tip.card, tip.title, tip.text, tip.apply, tip.open, tip.later,
## tip.close.

## "apply_preset" | "open_tactics" | "later" | "close".
signal action(id: String)

const BUTTONS := {
	"apply_preset": ["ui.tactics.apply_preset", "tip.apply", true],
	"open_tactics": ["ui.tactics.open", "tip.open", false],
	"later": ["ui.tactics.later", "tip.later", false],
	"close": ["ui.tactics.close", "tip.close", false],
}

## The tip as given by GameState.tactics.next_tip ({id, title, text,
## actions, preset, duration_s}).
var tip: Dictionary = {}
var _until_ms := 0


## `width`: the card's width (wrapped text needs one).
static func make(tip_data: Dictionary, width: float) -> TipCard:
	var card := TipCard.new()
	card.tip = tip_data
	card._build(width)
	return card


func _build(width: float) -> void:
	theme_type_variation = "CardPanel"
	custom_minimum_size = Vector2(width, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiProbe.register("tip.card", self)
	var col := Kit.vbox(UiTokens.SPACE["sm"])
	add_child(col)
	var title := Kit.label(str(tip.get("title", "")), "SubheadingLabel", true)
	title.custom_minimum_size.x = width - UiTokens.SPACE["xl"]
	UiProbe.register("tip.title", title)
	col.add_child(title)
	var text := Kit.label(str(tip.get("text", "")), "", true)
	text.custom_minimum_size.x = width - UiTokens.SPACE["xl"]
	UiProbe.register("tip.text", text)
	col.add_child(text)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", UiTokens.SPACE["sm"])
	row.add_theme_constant_override("v_separation", UiTokens.SPACE["sm"])
	col.add_child(row)
	var actions: Array = tip.get("actions", [])
	if actions.is_empty():
		actions = ["close"]
	var first: Button = null
	for id: String in actions:
		if not BUTTONS.has(id):
			continue
		var spec: Array = BUTTONS[id]
		var b := Kit.button(tr(spec[0]), spec[2], spec[1])
		b.custom_minimum_size.y = UiTokens.at_least_css(UiTokens.TOUCH_TARGET)
		b.pressed.connect(_on_button.bind(id))
		row.add_child(b)
		if first == null:
			first = b
	var seconds := float(tip.get("duration_s", 0.0))
	if seconds > 0.0:
		_until_ms = Time.get_ticks_msec() + int(seconds * 1000.0)
	UiProbe.world["tip"] = str(tip.get("id", ""))
	UiProbe.note(str(tip.get("text", "")))


func _process(_delta: float) -> void:
	if _until_ms > 0 and Time.get_ticks_msec() > _until_ms:
		dismiss()


func _on_button(id: String) -> void:
	action.emit(id)
	dismiss()


## Closes the card.
func dismiss() -> void:
	if UiProbe.world.get("tip", "") == str(tip.get("id", "")):
		UiProbe.world["tip"] = ""
	if get_parent():
		get_parent().remove_child(self)
	queue_free()
