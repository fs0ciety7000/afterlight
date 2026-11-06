extends TestCase
## Exercises the migration chain with a synthetic future format, so the
## mechanism is proven before the first real migration is needed.


func _v0_state() -> Dictionary:
	# Hypothetical older format: gold stored at top level, no wallet.
	var state := Fixtures.new_state()
	var gold: int = state["wallet"]["gold"]
	state.erase("wallet")
	state["gold"] = gold
	return state


static func _v0_to_v1(s: Dictionary) -> Dictionary:
	s["wallet"] = {"gold": s["gold"], "materials": {}}
	s.erase("gold")
	return s


func _migrations() -> Dictionary:
	return {0: _v0_to_v1}


func test_old_save_is_migrated_to_current_version() -> void:
	var text := SaveCodec.encode(_v0_state(), 1, 0)
	var r := SaveCodec.decode(text, _migrations(), 1)
	assert_true(r["ok"], "ok (%s %s)" % [r["error"], r["detail"]])
	assert_eq(r["migrated_from"], 0, "migrated from v0")
	assert_eq(r["version"], 1, "now v1")
	assert_eq(r["state"]["wallet"]["gold"], 100, "gold moved into wallet")


func test_missing_migration_step_is_an_error_not_a_crash() -> void:
	var text := SaveCodec.encode(_v0_state(), 1, 0)
	assert_eq(SaveCodec.decode(text, {}, 1)["error"], SaveCodec.ERR_MIGRATION, "no step")


func test_released_table_covers_every_version_below_current() -> void:
	var table := SaveMigrations.all()
	for v in range(1, SaveCodec.CURRENT_VERSION):
		assert_true(table.has(v), "migration from v%d exists" % v)
