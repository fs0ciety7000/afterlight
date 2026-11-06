extends TestCase
## ROADMAP 7.5 (unit part): a spell button answers its press at once, within
## 120 ms, whatever the sim decides next; a refusal and a queued cast show too.


func _button() -> SpellButton:
	var b := SpellButton.new()
	b.setup("spell.zoltraak", "1")
	return b


func test_press_answers_within_120_ms() -> void:
	var b := _button()
	assert_true(SpellButton.PRESS_S <= 0.12, "press feedback lasts at most 120 ms")
	assert_true(not b.is_processing(), "idle at rest")
	var before := SpellButton.presses
	b.press_feedback()
	assert_eq(SpellButton.presses, before + 1, "press counted")
	assert_true(b.is_processing(), "animating from the same frame")
	assert_near(b.get("_press_left"), SpellButton.PRESS_S, 0.0001, "flash starts at once")
	b._process(SpellButton.PRESS_S)
	assert_true(not b.is_processing(), "back to rest after 120 ms")
	b.free()


func test_refusal_and_queue_are_shown() -> void:
	var b := _button()
	b.reject_feedback()
	assert_true(b.is_processing(), "shake / red ring")
	b._process(SpellButton.REJECT_S)
	assert_true(not b.is_processing(), "refusal over")
	b.queued = true
	assert_true(b.is_processing(), "queued ring pulses")
	b.queued = false
	b._process(0.016)
	assert_true(not b.is_processing(), "stops once the cast starts")
	b.free()


func test_reduced_motion_keeps_a_steady_queued_ring() -> void:
	var b := _button()
	b.reduce_motion = true
	b.queued = true
	b._process(0.016)
	assert_true(not b.is_processing(), "no pulse to animate")
	b.free()
