extends TestCase
## Guards the web export budget from docs/ARCHITECTURE.md "Taille de l'export":
## two packs (boot `index.pck`, `content.pck` fetched while the title shows),
## source files out of both, every content file in exactly one pack, textures
## imported lossy, and the last build (build/web/, if present) within budget.
## Breakdown: python3 tools/pck_report.py build/web/<pack>.

const WEB_DIR := "res://build/web/"
## Boot pack: code, UI, fonts, data, title art, sounds, title music.
const BOOT_BUDGET_BYTES := 6_000_000
## Places, models, environment, music other than the title's.
const CONTENT_BUDGET_BYTES := 28_000_000
## Downloaded before the title (gzip, as served): index.wasm + index.pck.
## 2.5 MB/s at 20 Mb/s: 17.5 MB is 7 s, leaving 3 s of start-up for 7.2.
const BEFORE_TITLE_BUDGET_BYTES := 17_500_000
const REQUIRED_EXCLUDES := [
	"art/*",
	"tools/*",
	"tests/*",
	"build/*",
	"assets/environment/*.glb",
]
## Folders that ship in content.pck only (music: all but the title's).
const CONTENT_ROOTS := [
	"assets/environment",
	"assets/models",
	"game/world/locations",
	"game/world/dungeons",
	"assets/audio/music",
]
const BOOT_ONLY := ["assets/audio/music/music_title.ogg", "assets/textures/ui/title_day.jpg"]
const CONTENT_SENTINEL := "game/world/locations/aubelin.tscn"
## Small UI pictograms may stay lossless (crisp edges, a few KB each).
const LOSSLESS_ALLOWED := ["res://assets/textures/icons/"]
const COMPRESS_LOSSLESS := 0
const COMPRESS_VRAM_UNCOMPRESSED := 3

var _boot_excludes := PackedStringArray()
var _content_includes := PackedStringArray()
var _content_excludes := PackedStringArray()


func _init() -> void:
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	_boot_excludes = _patterns(presets.get_value("preset.0", "exclude_filter", ""))
	_content_includes = _patterns(presets.get_value("preset.1", "include_filter", ""))
	_content_excludes = _patterns(presets.get_value("preset.1", "exclude_filter", ""))


func test_last_web_build_fits_the_budget() -> void:
	var boot := _size(WEB_DIR + "index.pck")
	if boot < 0:
		return  # no build yet: `pnpm build:web` then `pnpm test` checks it
	assert_true(
		boot <= BOOT_BUDGET_BYTES,
		"index.pck is %.1f MB, budget %.1f MB" % [boot / 1e6, BOOT_BUDGET_BYTES / 1e6]
	)
	var content := _size(WEB_DIR + "content.pck")
	assert_true(content > 0, "build/web/content.pck missing: pnpm build:web exports both packs")
	assert_true(
		content <= CONTENT_BUDGET_BYTES,
		"content.pck is %.1f MB, budget %.1f MB" % [content / 1e6, CONTENT_BUDGET_BYTES / 1e6]
	)
	var manifest: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(WEB_DIR + "content.json")
	)
	assert_true(manifest is Dictionary, "build/web/content.json written by tools/web_content.mjs")
	if manifest is Dictionary:
		assert_eq(int((manifest as Dictionary).get("bytes", 0)), content, "content.json size")


func test_download_before_the_title_fits_the_budget() -> void:
	if _size(WEB_DIR + "index.pck") < 0 or _size(WEB_DIR + "index.wasm") < 0:
		return
	var total := 0
	for file in ["index.wasm", "index.pck"]:
		total += (
			FileAccess
			. get_file_as_bytes(WEB_DIR + file)
			. compress(FileAccess.COMPRESSION_GZIP)
			. size()
		)
	assert_true(
		total <= BEFORE_TITLE_BUDGET_BYTES,
		(
			"wasm + index.pck gzip is %.1f MB, budget %.1f MB (7.2: title < 10 s at 20 Mb/s)"
			% [total / 1e6, BEFORE_TITLE_BUDGET_BYTES / 1e6]
		)
	)


func test_web_preset_excludes_sources() -> void:
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK, "export_presets.cfg readable")
	assert_eq(presets.get_value("preset.1", "name", ""), "Web content", "content pack preset")
	for pattern: String in REQUIRED_EXCLUDES:
		var sample := pattern.replace("*", "x")
		assert_true(not _in_boot(sample), "Web preset must exclude %s" % pattern)
		assert_true(not _in_content(sample), "Web content preset must exclude %s" % pattern)


func test_content_files_ship_in_exactly_one_pack() -> void:
	var count := 0
	for root: String in CONTENT_ROOTS:
		for path in _files("res://" + root, ""):
			var rel := path.trim_prefix("res://")
			if rel.get_extension() in ["import", "uid", "gd", "json", "gitkeep", "md"]:
				continue
			if rel.get_extension() == "glb" and rel.begins_with("assets/environment/"):
				continue  # sources of meshes/*.res, in neither pack
			if rel.ends_with("_village_props_atlas.webp"):
				continue  # per-GLB copies of the shared atlas, in neither pack
			var boot := _in_boot(rel)
			var content := _in_content(rel)
			assert_true(boot != content, "%s: boot %s, content %s" % [rel, boot, content])
			count += 1
	assert_true(count > 100, "content files found (%d)" % count)
	assert_true(_in_content(CONTENT_SENTINEL) and not _in_boot(CONTENT_SENTINEL), "sentinel")
	for rel: String in BOOT_ONLY:
		assert_true(_in_boot(rel) and not _in_content(rel), "%s ships in the boot pack" % rel)


## A preload() is resolved when its script loads, before the content pack is
## mounted: scripts must load content by path at use (ResourceLoader.exists).
func test_scripts_do_not_preload_content() -> void:
	var ref := RegEx.create_from_string('preload\\("res://([^"]+)"\\)')
	for file in _files("res://game", ".gd"):
		for hit in ref.search_all(FileAccess.get_file_as_string(file)):
			var used := hit.get_string(1)
			assert_true(not _in_content(used), "%s preloads %s (content pack)" % [file, used])


func test_runtime_resources_do_not_use_excluded_files() -> void:
	var ref := RegEx.create_from_string('path="res://([^"]+)"')
	var files := _files("res://assets/environment/materials", ".tres")
	files.append_array(_files("res://game/world", ".tscn"))
	for file in files:
		for hit in ref.search_all(FileAccess.get_file_as_string(file)):
			var used := hit.get_string(1)
			assert_true(
				_in_boot(used) or _in_content(used),
				"%s uses %s, left out of both web packs" % [file, used]
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


## Same matching as the exporter: `matchn` on the path without res://.
func _in_boot(rel: String) -> bool:
	return not _matches(rel, _boot_excludes)


func _in_content(rel: String) -> bool:
	return _matches(rel, _content_includes) and not _matches(rel, _content_excludes)


func _matches(rel: String, patterns: PackedStringArray) -> bool:
	for pattern in patterns:
		if rel.matchn(pattern):
			return true
	return false


func _patterns(filter: String) -> PackedStringArray:
	var out := PackedStringArray()
	for p in filter.split(",", false):
		out.append(p.strip_edges())
	return out


func _size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	return FileAccess.open(path, FileAccess.READ).get_length()


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
