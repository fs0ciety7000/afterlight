class_name ProgressionScreen
extends Screen
## Shared frame of the progression screens (GDD §17: Personnage, Sac,
## Grimoire, Forge, Graveuse, Marchande): title, purse, tabs to switch
## between them, close, and a body rebuilt from GameState whenever it
## changes. Screens only read GameState.progression and call its actions;
## every action button carries the reason of its quote when disabled
## (ROADMAP 4.10).

const TABS := ["character", "bag", "grimoire", "forge", "runecarver", "merchant"]
## Tile side in logical pixels (DESIGN.md: 48 px target + frame).
const TILE := UiTokens.TOUCH_TARGET + UiTokens.SPACE["lg"]
## Shopkeepers shown at the top of their screen: portrait, name and role
## (assets/textures/portraits/npc_<name>.webp, keys <npc>.name and <npc>.role).
const NPCS := {
	"forge": "npc.bastien",
	"runecarver": "npc.maelle",
	"merchant": "npc.aubelin_merchant",
}
const PORTRAITS_DIR := "res://assets/textures/portraits/"

var screen_id := ""
var _body: VBoxContainer
var _status: Label
var _purse: Label
var _refresh_queued := false
var _refocus_id := ""


func _ready() -> void:
	add_backdrop(0.8)
	var narrow := is_narrow()
	var panel := Kit.panel()
	var frame := Kit.margin(panel, narrow)
	add_child(frame)
	var col := Kit.vbox(UiTokens.SPACE["sm"])
	panel.add_child(col)

	var head := Kit.hbox()
	var title := Kit.label(tr("ui.prog.tab." + screen_id), "HeadingLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiProbe.register(screen_id + ".title", title)
	head.add_child(title)
	_purse = Kit.label("", "NumberLabel")
	_purse.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiProbe.register(screen_id + ".purse", _purse)
	head.add_child(_purse)
	var close := button(tr("ui.prog.close"), false, "prog.close")
	close.pressed.connect(close_screen)
	head.add_child(close)
	col.add_child(head)

	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", UiTokens.SPACE["sm"])
	tabs.add_theme_constant_override("v_separation", UiTokens.SPACE["sm"])
	for id: String in TABS:
		var b := button(tr("ui.prog.tab." + id), id == screen_id, "prog.tab." + id)
		b.pressed.connect(func() -> void: open(id))
		tabs.add_child(b)
	col.add_child(tabs)
	col.add_child(HSeparator.new())
	if NPCS.has(screen_id):
		col.add_child(_npc_header(NPCS[screen_id], narrow))

	_body = Kit.vbox()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	_status = Kit.label("", "MutedLabel", true)
	UiProbe.register(screen_id + ".status", _status)
	col.add_child(_status)

	GameState.changed.connect(_queue_refresh)
	_refresh()


## Portrait, name and role of the screen's shopkeeper.
func _npc_header(npc_id: String, narrow: bool) -> Control:
	var row := Kit.hbox()
	var portrait := TextureRect.new()
	var path := PORTRAITS_DIR + "npc_" + npc_id.get_slice(".", 1) + ".webp"
	if ResourceLoader.exists(path):
		portrait.texture = load(path)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var side := 48.0 if narrow else 72.0
	portrait.custom_minimum_size = Vector2(side, side)
	UiProbe.register(screen_id + ".npc_portrait", portrait)
	row.add_child(portrait)
	var text := Kit.vbox(UiTokens.SPACE["xs"])
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	var npc_name := Kit.label(tr(npc_id + ".name"), "SubheadingLabel")
	UiProbe.register(screen_id + ".npc_name", npc_name)
	text.add_child(npc_name)
	text.add_child(Kit.label(tr(npc_id + ".role"), "MutedLabel"))
	row.add_child(text)
	return row


## Switches to another progression screen; Back still returns to the world.
static func open(id: String, params: Dictionary = {}) -> void:
	Router.go_to(id, params, Router.current_id == "explore")


func close_screen() -> void:
	Router.back("explore")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_screen()


func grab_initial_focus() -> void:
	var c: Control = UiProbe._controls.get("prog.tab." + screen_id)
	if c and c.is_inside_tree():
		c.grab_focus()


## Subclasses fill the body from the current state.
func _build(_into: VBoxContainer) -> void:
	pass


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh")


func _refresh() -> void:
	_refresh_queued = false
	if not GameState.has_game() or not is_inside_tree():
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused and _body.is_ancestor_of(focused):
		_refocus_id = _probe_id_of(focused)
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_purse.text = _purse_text()
	_build(_body)
	if _refocus_id != "":
		var c: Control = UiProbe._controls.get(_refocus_id)
		if c and c.is_inside_tree() and c.focus_mode != Control.FOCUS_NONE:
			c.call_deferred("grab_focus")
		_refocus_id = ""


func _probe_id_of(c: Control) -> String:
	for id in UiProbe._controls:
		if UiProbe._controls[id] == c:
			return id
	return ""


func _purse_text() -> String:
	var w: Dictionary = GameState.progression.views.wallet()
	return tr("ui.fmt.gold").format({"gold": w["gold"]})


# --- Builders ----------------------------------------------------------------


## A button that stays at least 48 CSS px tall on phones.
func button(text: String, primary: bool = false, probe_id: String = "") -> Button:
	var b := Kit.button(text, primary, probe_id)
	b.custom_minimum_size.y = UiTokens.at_least_css(UiTokens.TOUCH_TARGET)
	return b


## An action button with the reason of its quote shown under it when it is
## disabled ("Or insuffisant : 141 requis"). The reason label is registered
## as `<probe_id>_reason`.
func action(
	parent: Control,
	text: String,
	probe_id: String,
	quote: Dictionary,
	on_press: Callable,
	primary: bool = true
) -> Button:
	var box := Kit.vbox(UiTokens.SPACE["xs"])
	var b := button(text, primary, probe_id)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var ok: bool = quote.get("ok", false)
	b.disabled = not ok
	var reason := Kit.label("" if ok else GameState.reason_text(quote), "MutedLabel", true)
	reason.visible = not ok
	b.tooltip_text = reason.text
	UiProbe.register(probe_id + "_reason", reason)
	b.pressed.connect(
		func() -> void:
			_refocus_id = probe_id
			on_press.call()
	)
	box.add_child(b)
	box.add_child(reason)
	parent.add_child(box)
	return b


## Shows the outcome of an action: its result text, or its refusal.
func report(r: Dictionary, success_text: String) -> void:
	if r.get("ok", false):
		flash(_status, success_text)
	else:
		flash(_status, GameState.reason_text(r), true)


## Two panes, side by side on wide screens (each scrolls on its own), or
## stacked in one scroll on narrow ones. Returns [left, right].
func two_panes(into: Control, left_ratio: float = 1.0) -> Array[VBoxContainer]:
	var left := Kit.vbox()
	var right := Kit.vbox()
	if is_narrow():
		var scroll := _scroll()
		var stack := Kit.vbox(UiTokens.SPACE["lg"])
		stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.add_child(left)
		stack.add_child(right)
		scroll.add_child(stack)
		into.add_child(scroll)
	else:
		var row := Kit.hbox(UiTokens.SPACE["xl"])
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		for pair in [[left, left_ratio], [right, 1.0]]:
			var scroll := _scroll()
			scroll.size_flags_stretch_ratio = pair[1]
			(pair[0] as VBoxContainer).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.add_child(pair[0])
			row.add_child(scroll)
		into.add_child(row)
	return [left, right]


## One scrolling column filling the body.
func one_pane(into: Control) -> VBoxContainer:
	var scroll := _scroll()
	var col := Kit.vbox()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	into.add_child(scroll)
	return col


func _scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


func heading(parent: Control, text: String) -> Label:
	var l := Kit.label(text, "SubheadingLabel", true)
	parent.add_child(l)
	return l


## "Name ........ value" row; the value label is returned (and registered).
func value_row(parent: Control, label_text: String, value: String, probe_id: String = "") -> Label:
	var row := Kit.hbox()
	var n := Kit.label(label_text, "", true)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	var v := Kit.label(value, "NumberLabel")
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	if probe_id != "":
		UiProbe.register(probe_id, v)
	parent.add_child(row)
	return v


## Rarity shown three ways (DESIGN.md): colour swatch, frame of the tile,
## and the word.
func rarity_label(rarity: String) -> Label:
	var l := Kit.label(ProgressionText.rarity_name(rarity), "MutedLabel")
	var box := StyleBoxFlat.new()
	box.bg_color = Color.TRANSPARENT
	box.border_color = ProgressionText.rarity_color(rarity)
	box.border_width_left = UiTokens.SPACE["xs"]
	box.content_margin_left = UiTokens.SPACE["sm"]
	l.add_theme_stylebox_override("normal", box)
	return l


func empty_hint(parent: Control, text: String) -> Label:
	var l := Kit.label(text, "MutedLabel", true)
	parent.add_child(l)
	return l
