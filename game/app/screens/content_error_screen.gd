extends Screen
## Blocks the game when content files are invalid, and lists the errors.


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UiTokens.DAY["surface"]
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := Kit.vbox()
	col.add_child(Kit.label(tr("error.content.title"), "TitleLabel"))
	col.add_child(Kit.label(tr("error.content.body"), "", true))
	var list := Kit.label("\n".join(Content.errors), "MutedLabel", true)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiProbe.register("content_error.list", list)
	col.add_child(list)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(col)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(Kit.margin(scroll, is_narrow()))
	for e in Content.errors:
		push_error(e)
