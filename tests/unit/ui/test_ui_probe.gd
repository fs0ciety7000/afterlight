extends TestCase
## UiProbe flags read by the screens E2E (ROADMAP 7.7): `truncated` for a
## label or button that hides part of its text, `scrolled` for a control
## inside a scroll list.

const LONG := "Restaurer la copie de secours de la sauvegarde"


func _host() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.disable_3d = true
	(Engine.get_main_loop() as SceneTree).root.add_child(vp)
	return vp


func _free(vp: SubViewport) -> void:
	vp.get_parent().remove_child(vp)
	vp.free()


func test_a_clipped_or_ellipsized_line_is_truncated_only_when_too_narrow() -> void:
	var vp := _host()
	for mode in ["clip", "ellipsis"]:
		var l := Label.new()
		l.text = LONG
		if mode == "clip":
			l.clip_text = true
		else:
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		vp.add_child(l)
		l.size = Vector2(40, 30)
		assert_true(UiProbe.is_truncated(l), "%s label 40 px" % mode)
		l.size = Vector2(2000, 30)
		assert_true(not UiProbe.is_truncated(l), "%s label 2000 px" % mode)
	_free(vp)


func test_a_label_that_grows_with_its_text_is_not_truncated() -> void:
	var vp := _host()
	var l := Label.new()
	l.text = LONG
	vp.add_child(l)
	l.size = Vector2(10, 10)  # clamped to its minimum size: the whole line
	assert_true(not UiProbe.is_truncated(l), "plain label")
	var empty := Label.new()
	empty.clip_text = true
	vp.add_child(empty)
	assert_true(not UiProbe.is_truncated(empty), "empty label")
	_free(vp)


func test_wrapped_lines_that_do_not_all_show_are_truncated() -> void:
	var vp := _host()
	var l := Label.new()
	l.text = LONG
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vp.add_child(l)
	l.size = Vector2(120, 400)
	assert_true(l.get_line_count() > 1, "wraps")
	assert_true(not UiProbe.is_truncated(l), "all lines shown")
	l.max_lines_visible = 1
	assert_true(UiProbe.is_truncated(l), "one line of several")
	_free(vp)


func test_a_clipped_button_is_truncated_when_too_narrow() -> void:
	var vp := _host()
	var b := Button.new()
	b.text = LONG
	b.clip_text = true
	vp.add_child(b)
	b.size = Vector2(60, 40)
	assert_true(UiProbe.is_truncated(b), "60 px")
	b.size = Vector2(2000, 40)
	assert_true(not UiProbe.is_truncated(b), "2000 px")
	var plain := Button.new()
	plain.text = LONG
	vp.add_child(plain)
	assert_true(not UiProbe.is_truncated(plain), "button sized by its text")
	_free(vp)


func test_in_scroll_list() -> void:
	var vp := _host()
	var scroll := ScrollContainer.new()
	var col := VBoxContainer.new()
	var inside := Button.new()
	col.add_child(inside)
	scroll.add_child(col)
	vp.add_child(scroll)
	var outside := Button.new()
	vp.add_child(outside)
	assert_true(UiProbe.in_scroll_list(inside), "inside")
	assert_true(not UiProbe.in_scroll_list(outside), "outside")
	_free(vp)
