extends TestCase


func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(c: Color) -> float:
	var ch := func(v: float) -> float:
		return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * ch.call(c.r) + 0.7152 * ch.call(c.g) + 0.0722 * ch.call(c.b)


func test_text_contrast_meets_4_5_in_both_themes() -> void:
	for palette in [UiTokens.DAY, UiTokens.NIGHT]:
		for bg in ["surface", "surface_alt"]:
			var ratio := _contrast(palette["ink"], palette[bg])
			assert_true(ratio >= 4.5, "%s ink on %s: %.2f" % [palette["name"], bg, ratio])
		var accent := _contrast(palette["accent_ink"], palette["accent"])
		assert_true(accent >= 4.5, "%s primary button text: %.2f" % [palette["name"], accent])


func test_muted_text_stays_readable() -> void:
	for palette in [UiTokens.DAY, UiTokens.NIGHT]:
		var ratio := _contrast(palette["ink_muted"], palette["surface"])
		assert_true(ratio >= 4.5, "%s muted: %.2f" % [palette["name"], ratio])


func test_both_palettes_define_the_same_roles() -> void:
	assert_eq(UiTokens.DAY.keys().size(), UiTokens.NIGHT.keys().size(), "same count")
	for key in UiTokens.DAY:
		assert_true(UiTokens.NIGHT.has(key), "night has %s" % key)


func test_text_scale_changes_font_sizes() -> void:
	var normal := ThemeBuilder.build(UiTokens.DAY, 1.0)
	var large := ThemeBuilder.build(UiTokens.DAY, 1.3)
	assert_eq(normal.default_font_size, 16, "body 16")
	assert_eq(large.default_font_size, 21, "body 21 at 130%")
	assert_eq(large.get_font_size("font_size", "TitleLabel"), 52, "title scales")
