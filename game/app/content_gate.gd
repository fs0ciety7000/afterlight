class_name ContentGate
extends VBoxContainer
## Shows the web content pack download (ContentPack) where a screen offers to
## enter the world: progress and reason while loading, the error and a retry
## button on failure. The buttons it guards stay disabled until the pack is
## mounted. Hidden when the content is ready (editor, tests, desktop).

var _gated: Array[BaseButton] = []
var _status: Label
var _hint: Label
var _bar: ProgressBar
var _retry: Button


static func create(buttons: Array[BaseButton]) -> ContentGate:
	var gate := ContentGate.new()
	gate._gated = buttons
	return gate


func _ready() -> void:
	add_theme_constant_override("separation", UiTokens.SPACE["sm"])
	_status = Kit.label("", "MutedLabel", true)
	add_child(_status)
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, UiTokens.SPACE["sm"])
	add_child(_bar)
	for slot: String in ["background", "fill"]:
		var box := _bar.get_theme_stylebox(slot).duplicate() as StyleBox
		box.set_content_margin_all(0)  # the theme pads boxes for panels, too tall here
		_bar.add_theme_stylebox_override(slot, box)
	_hint = Kit.label(tr("ui.content.waiting"), "MutedLabel", true)
	add_child(_hint)
	_retry = Kit.button(tr("ui.content.retry"), false, "content.retry")
	_retry.pressed.connect(ContentPack.start)
	add_child(_retry)
	ContentPack.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var ready: bool = ContentPack.is_ready()
	visible = not ready
	for b in _gated:
		if is_instance_valid(b):
			b.disabled = not ready
			b.tooltip_text = "" if ready else tr("ui.content.waiting")
	var failed: bool = ContentPack.is_failed()
	_bar.visible = not failed
	_bar.value = ContentPack.progress
	_retry.visible = failed
	_hint.visible = not ready
	if failed:
		_status.text = tr("ui.content.failed").format({"reason": ContentPack.error})
		_status.theme_type_variation = "ErrorLabel"
	else:
		var percent := roundi(ContentPack.progress * 100.0)
		_status.text = tr("ui.content.loading").format({"percent": percent})
		_status.theme_type_variation = "MutedLabel"
