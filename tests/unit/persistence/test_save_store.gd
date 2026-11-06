extends TestCase
## Uses a throwaway folder under user:// for each test.

var _dirs: Array[String] = []


func _store() -> SaveStore:
	var path := "user://test_saves/%d_%d" % [Time.get_ticks_usec(), _dirs.size()]
	_dirs.append(path)
	return SaveStore.new(path)


func _write_raw(store: SaveStore, name: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(store.dir_path)
	var f := FileAccess.open(store.dir_path.path_join(name), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_empty_slot_reports_empty() -> void:
	assert_eq(_store().read()["status"], "empty", "empty")


func test_write_then_read_round_trips() -> void:
	var store := _store()
	var state := Fixtures.new_state()
	assert_true(store.write(state, 100)["ok"], "write ok")
	var r := store.read()
	assert_eq(r["status"], "ok", "status")
	assert_eq(SaveCodec.canonical(r["decoded"]["state"]), SaveCodec.canonical(state), "same state")
	assert_true(
		not FileAccess.file_exists(store.dir_path.path_join(SaveStore.TEMP)), "no temp left"
	)


func test_second_write_keeps_previous_as_backup() -> void:
	var store := _store()
	var first := Fixtures.new_state()
	store.write(first, 100)
	var second := first.duplicate(true)
	second["wallet"]["gold"] = 250
	store.write(second, 200)
	assert_eq(store.read()["decoded"]["state"]["wallet"]["gold"], 250, "main is newest")
	var backup := SaveCodec.decode(store.read_text(store.backup_path()))
	assert_eq(backup["state"]["wallet"]["gold"], 100, "backup is previous")


func test_corrupt_main_is_reported_with_valid_backup() -> void:
	var store := _store()
	store.write(Fixtures.new_state(), 100)
	store.write(Fixtures.new_state(), 200)
	_write_raw(store, SaveStore.MAIN, "{ broken")
	var r := store.read()
	assert_eq(r["status"], "corrupt", "corrupt")
	assert_eq(r["decoded"]["error"], SaveCodec.ERR_NOT_JSON, "error code")
	assert_true(r["backup"]["ok"], "backup usable")


func test_writing_over_a_corrupt_save_quarantines_it_first() -> void:
	var store := _store()
	_write_raw(store, SaveStore.MAIN, "{ broken")
	assert_true(store.write(Fixtures.new_state(), 300)["ok"], "write ok")
	var files := store.quarantined_files()
	assert_eq(files.size(), 1, "one quarantined file")
	assert_eq(store.read_text(files[0]), "{ broken", "original bytes kept")
	assert_true(not FileAccess.file_exists(store.backup_path()), "corrupt file not used as backup")


func test_restore_backup_replaces_damaged_main() -> void:
	var store := _store()
	var good := Fixtures.new_state()
	store.write(good, 100)
	store.write(good, 200)
	_write_raw(store, SaveStore.MAIN, "garbage")
	assert_true(store.restore_backup(400)["ok"], "restored")
	assert_eq(store.read()["status"], "ok", "main readable again")
	assert_eq(store.quarantined_files().size(), 1, "damaged main kept in quarantine")


func test_restore_without_backup_fails_cleanly() -> void:
	var store := _store()
	_write_raw(store, SaveStore.MAIN, "garbage")
	assert_true(not store.restore_backup(1)["ok"], "no backup")
	assert_eq(store.read_text(store.main_path()), "garbage", "damaged main untouched")
