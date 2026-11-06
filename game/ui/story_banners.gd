class_name StoryBanners
extends VBoxContainer
## Banners for GameState.story_events (quest updated or completed, discovery
## found, bestiary tier, contract done...). Stacked at the top centre, each
## one leaves after a few seconds. The last texts are published to
## UiProbe.world["banners"] for the E2E runs.

const SHOW_S := 4.0
const MAX_SHOWN := 3
const PROBE_KEEP := 12


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", UiTokens.SPACE["sm"])
	GameState.story_events.connect(_on_events)


func _on_events(events: Array) -> void:
	var seen := {}
	for e: Dictionary in events:
		if not StoryText.BANNER_TYPES.has(str(e.get("type", ""))):
			continue
		var text := StoryText.banner_text(e)
		if text == "" or seen.has(text):
			continue
		seen[text] = true
		show_text(text, str(e["type"]))


func show_text(text: String, kind: String = "") -> void:
	var probe: Array = UiProbe.world.get("banners", [])
	probe.append(text)
	while probe.size() > PROBE_KEEP:
		probe.pop_front()
	UiProbe.world["banners"] = probe
	UiProbe.note(text)
	var card := Kit.panel("CardPanel")
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var label := Kit.label(text, "LeadLabel", true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(minf(520.0, get_viewport_rect().size.x - 48.0), 0)
	if kind in ["quest_completed", "quest_turned_in", "bestiary_tier_unlocked"]:
		label.add_theme_color_override("font_color", UiTokens.DAY["accent"])
	card.add_child(label)
	add_child(card)
	UiProbe.register("banner.last", label)
	while get_child_count() > MAX_SHOWN:
		var old := get_child(0)
		remove_child(old)
		old.queue_free()
	get_tree().create_timer(SHOW_S).timeout.connect(
		func() -> void:
			if is_instance_valid(card):
				card.queue_free()
	)
