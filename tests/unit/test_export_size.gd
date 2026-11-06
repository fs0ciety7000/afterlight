extends TestCase
## Guards the web export budget from docs/ARCHITECTURE.md "Taille de l'export":
## source files stay out of the pack, textures are imported lossy, and the last build
## (build/web/index.pck, if present) fits the budget. Breakdown: python3 tools/pck_report.py.

const PCK_PATH := "res://build/web/index.pck"
const PCK_BUDGET_BYTES := 30_000_000
const REQUIRED_EXCLUDES := [
	"art/*",
	"tools/*",
	"tests/*",
	"build/*",
	"assets/environment/*.glb",
]
## Small UI pictograms may stay lossless (crisp edges, a few KB each).
const LOSSLESS_ALLOWED := ["res://assets/textures/icons/"]
const COMPRESS_LOSSLESS := 0
const COMPRESS_VRAM_UNCOMPRESSED := 3


func test_last_web_build_fits_the_budget() -> void:
	if not FileAccess.file_exists(PCK_PATH):
		return  # no build yet: `pnpm build:web` then `pnpm test` checks it
	var size := FileAccess.open(PCK_PATH, FileAccess.READ).get_length()
	assert_true(
		size <= PCK_BUDGET_BYTES,
		(
			"index.pck is %.1f MB, budget %.1f MB (python3 tools/pck_report.py)"
			% [size / 1e6, PCK_BUDGET_BYTES / 1e6]
		)
	)


func test_web_preset_excludes_sources() -> void:
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK, "export_presets.cfg readable")
	var excludes: String = presets.get_value("preset.0", "exclude_filter", "")
	for pattern: String in REQUIRED_EXCLUDES:
		assert_true(pattern in excludes, "Web preset must exclude %s" % pattern)


func test_runtime_resources_do_not_use_excluded_files() -> void:
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	var excludes := (presets.get_value("preset.0", "exclude_filter", "") as String).split(",")
	var ref := RegEx.create_from_string('path="res://([^"]+)"')
	var files := _files("res://assets/environment/materials", ".tres")
	files.append_array(_files("res://game/world", ".tscn"))
	for file in files:
		for hit in ref.search_all(FileAccess.get_file_as_string(file)):
			var used := hit.get_string(1)
			for pattern: String in excludes:
				assert_true(
					not used.matchn(pattern.strip_edges()),
					"%s uses %s, left out of the export by %s" % [file, used, pattern.strip_edges()]
				)


func test_textures_are_not_imported_lossless() -> void:
	for path in _files("res://assets", ".import"):
		var cfg := ConfigFile.new()
		if cfg.load(path) != OK or cfg.get_value("remap", "importer", "") != "texture":
			continue
		if LOSSLESS_ALLOWED.any(func(prefix: String) -> bool: return path.begins_with(prefix)):
			continue
		var mode: int = cfg.get_value("params", "compress/mode", COMPRESS_LOSSLESS)
		assert_true(
			mode != COMPRESS_LOSSLESS and mode != COMPRESS_VRAM_UNCOMPRESSED,
			"%s: use compress/mode=1 (lossy WebP), see ARCHITECTURE" % path.trim_suffix(".import")
		)


func _files(dir_path: String, suffix: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_files(dir_path.path_join(sub), suffix))
	for file in dir.get_files():
		if file.ends_with(suffix):
			out.append(dir_path.path_join(file))
	return out
