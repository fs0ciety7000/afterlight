extends TestCase
## Criterion 1.8: every visible text comes from a translation key.
## Statically scans UI code for literal text passed to labels and buttons.

const DIRS := ["res://game/app", "res://game/ui"]
const PATTERNS := [
	'Kit\\.(label|button)\\(\\s*"[^"\\\\]',
	'\\.text\\s*=\\s*"[^"]',
	'ConfirmDialog\\.open\\([^,]+,\\s*"',
]


func test_ui_code_uses_translation_keys() -> void:
	var regexes := []
	for p in PATTERNS:
		regexes.append(RegEx.create_from_string(p))
	for dir_path in DIRS:
		for path in _scripts(dir_path):
			var text := FileAccess.get_file_as_string(path)
			for re: RegEx in regexes:
				var hit := re.search(text)
				assert_true(
					hit == null,
					"%s: literal UI text `%s`" % [path, hit.get_string() if hit else ""]
				)


func test_every_tr_key_in_code_exists() -> void:
	var keys := ContentLoader.translation_keys("res://game/i18n/strings.csv")
	var re := RegEx.create_from_string('tr\\("([a-z_.]+)"\\)')
	for dir_path in DIRS:
		for path in _scripts(dir_path):
			for m in re.search_all(FileAccess.get_file_as_string(path)):
				assert_true(
					keys.has(m.get_string(1)), "%s: unknown key %s" % [path, m.get_string(1)]
				)


func test_save_error_codes_are_all_translated() -> void:
	var keys := ContentLoader.translation_keys("res://game/i18n/strings.csv")
	for code in [
		SaveCodec.ERR_NOT_JSON,
		SaveCodec.ERR_NOT_A_SAVE,
		SaveCodec.ERR_FUTURE_VERSION,
		SaveCodec.ERR_CHECKSUM,
		SaveCodec.ERR_MIGRATION,
		SaveCodec.ERR_INVALID_STATE,
	]:
		assert_true(keys.has("error.save." + code), "error.save.%s" % code)


func _scripts(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_scripts(dir_path.path_join(sub)))
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	return out
