extends TestCase


func test_round_trip_restores_identical_state() -> void:
	var state := Fixtures.new_state()
	var r := SaveCodec.decode(SaveCodec.encode(state, 1_800_000_100))
	assert_true(r["ok"], "ok (%s %s)" % [r["error"], r["detail"]])
	assert_eq(SaveCodec.canonical(r["state"]), SaveCodec.canonical(state), "same state")
	assert_eq(typeof(r["state"]["wallet"]["gold"]), TYPE_INT, "ints restored")
	assert_eq(r["saved_at"], 1_800_000_100, "saved_at")


func test_garbage_is_rejected_as_not_json() -> void:
	assert_eq(SaveCodec.decode("{not json")["error"], SaveCodec.ERR_NOT_JSON, "not json")


func test_other_json_is_rejected_as_not_a_save() -> void:
	assert_eq(SaveCodec.decode('{"hello": 1}')["error"], SaveCodec.ERR_NOT_A_SAVE, "not a save")


func test_tampered_state_fails_checksum() -> void:
	var text := SaveCodec.encode(Fixtures.new_state(), 1)
	text = text.replace('"gold": 100', '"gold": 999999')
	assert_eq(SaveCodec.decode(text)["error"], SaveCodec.ERR_CHECKSUM, "checksum")


func test_future_version_is_rejected() -> void:
	var text := SaveCodec.encode(Fixtures.new_state(), 1, SaveCodec.CURRENT_VERSION + 1)
	assert_eq(SaveCodec.decode(text)["error"], SaveCodec.ERR_FUTURE_VERSION, "future")


func test_structurally_invalid_state_is_rejected() -> void:
	var state := Fixtures.new_state()
	state["wallet"]["gold"] = -5
	var r := SaveCodec.decode(SaveCodec.encode(state, 1))
	assert_eq(r["error"], SaveCodec.ERR_INVALID_STATE, "invalid")
	assert_true(r["detail"].contains("$.wallet.gold"), "detail names the field")
