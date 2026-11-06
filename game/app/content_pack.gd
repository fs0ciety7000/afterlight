extends Node
## Autoload "ContentPack": the second web pack (docs/ARCHITECTURE.md, "Taille de
## l'export et chargement"). The boot pack holds code, UI, data and the title;
## `content.pck` holds places, models and music. On the web it is downloaded
## while the title shows, then mounted with ProjectSettings.load_resource_pack.
## In the editor, tests and single-pack exports the content is already in
## res://, so the state starts at READY and nothing is downloaded.

signal changed

enum State { READY, LOADING, FAILED }

## A file that only the content pack carries: present means mounted.
const SENTINEL := "res://game/world/locations/aubelin.tscn"
## Written next to index.html by tools/web_content.mjs (size, md5, file name).
const MANIFEST := "content.json"
## Emscripten MEMFS: not synced to IndexedDB, unlike user:// (/userfs).
const WEB_PACK_PATH := "/tmp/afterlight_content.pck"
const FALLBACK_PACK_PATH := "user://content.pck"

var state := State.READY
## 0..1 while LOADING (bytes received over the manifest's size).
var progress := 0.0
## French reason, set when FAILED.
var error := ""
var _http: HTTPRequest
var _base_url := ""
var _pack_path := WEB_PACK_PATH
var _expected_bytes := 0
var _pack_url := ""
var _fetching_pack := false


func _ready() -> void:
	if is_mounted():
		_publish()
		return
	_base_url = _resolve_base_url()
	if _base_url == "":
		_fail(tr("ui.content.error.missing"))
		return
	if not OS.has_feature("web"):
		_pack_path = FALLBACK_PACK_PATH
	start()


func is_ready() -> bool:
	return state == State.READY


func is_failed() -> bool:
	return state == State.FAILED


func is_mounted() -> bool:
	return ResourceLoader.exists(SENTINEL)


## Starts (or restarts after a failure) the download: manifest, then pack.
func start() -> void:
	if state == State.LOADING and _http != null:
		return
	if is_mounted():
		_set_state(State.READY)
		return
	error = ""
	progress = 0.0
	_expected_bytes = 0
	_fetching_pack = false
	_set_state(State.LOADING)
	_request(_base_url + MANIFEST, "")


## Facts for the E2E probe (`window.__afterlight.world.content`).
func snapshot() -> Dictionary:
	return {
		"state": (["ready", "loading", "failed"] as Array[String])[state],
		"progress": snappedf(progress, 0.01),
		"error": error,
	}


func _process(_delta: float) -> void:
	if state != State.LOADING or not _fetching_pack or _http == null:
		return
	var total := _expected_bytes if _expected_bytes > 0 else _http.get_body_size()
	if total <= 0:
		return
	var p := clampf(float(_http.get_downloaded_bytes()) / total, 0.0, 0.99)
	if p - progress >= 0.01:
		progress = p
		_publish()


func _request(url: String, download_to: String) -> void:
	_drop_http()
	_http = HTTPRequest.new()
	_http.download_file = download_to
	_http.download_chunk_size = 1 << 20
	_http.timeout = 0.0 if download_to != "" else 20.0
	# On the web the browser already undoes Content-Encoding: gzip; decoding it
	# a second time fails (StreamPeerGZIP) and the pack never mounts.
	_http.accept_gzip = not OS.has_feature("web")
	add_child(_http)
	_http.request_completed.connect(_on_completed)
	var err := _http.request(url, PackedStringArray(["Cache-Control: no-cache"]))
	if err != OK:
		_fail(tr("ui.content.error.network"))


func _on_completed(
	result: int, code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		var cant_write := (
			result == HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN
			or result == HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR
		)
		if _fetching_pack and cant_write and _pack_path != FALLBACK_PACK_PATH:
			_pack_path = FALLBACK_PACK_PATH  # no MEMFS /tmp: keep it in user://
			_fetch_pack()
			return
		push_warning("Content pack: HTTPRequest result %d" % result)
		_fail(tr("ui.content.error.network"))
		return
	if code != 200:
		_fail(tr("ui.content.error.http").format({"code": code}))
		return
	if not _fetching_pack:
		_on_manifest(body)
	else:
		_on_pack(body)


func _on_manifest(body: PackedByteArray) -> void:
	var manifest: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not manifest is Dictionary or not (manifest as Dictionary).has("file"):
		_fail(tr("ui.content.error.manifest"))
		return
	var m: Dictionary = manifest
	_expected_bytes = int(m.get("bytes", 0))
	# The md5 in the query string keeps a browser cache from serving a stale pack.
	_pack_url = "%s%s?v=%s" % [_base_url, str(m["file"]).uri_encode(), str(m.get("md5", ""))]
	_fetch_pack()


func _fetch_pack() -> void:
	_fetching_pack = true
	# Web: HTTPRequest.download_file leaves an empty file in the browser's
	# virtual FS, so the body is kept in memory and written here (user://).
	_request(_pack_url, "" if OS.has_feature("web") else _pack_path)


func _on_pack(body: PackedByteArray = PackedByteArray()) -> void:
	_drop_http()
	if not body.is_empty():
		_pack_path = FALLBACK_PACK_PATH
		var w := FileAccess.open(_pack_path, FileAccess.WRITE)
		if w == null:
			_fail(tr("ui.content.error.incomplete"))
			return
		w.store_buffer(body)
		w.close()
	var size := 0
	var f := FileAccess.open(_pack_path, FileAccess.READ)
	if f != null:
		size = f.get_length()
		f.close()
	if size == 0 or (_expected_bytes > 0 and size != _expected_bytes):
		push_warning("Content pack: %d bytes on disk, %d expected" % [size, _expected_bytes])
		_fail(tr("ui.content.error.incomplete"))
		return
	if not ProjectSettings.load_resource_pack(_pack_path) or not is_mounted():
		_fail(tr("ui.content.error.mount"))
		return
	progress = 1.0
	print("Content pack mounted (%d bytes)" % size)
	_set_state(State.READY)


func _fail(reason: String) -> void:
	_drop_http()
	_fetching_pack = false
	error = reason
	push_warning("Content pack: " + reason)
	_set_state(State.FAILED)


func _set_state(next: State) -> void:
	state = next
	_publish()


func _publish() -> void:
	UiProbe.world["content"] = snapshot()
	changed.emit()


func _drop_http() -> void:
	if _http != null:
		_http.cancel_request()
		_http.queue_free()
		_http = null


## Web: the folder of the page. Elsewhere: `--content-base=<url>` after `--`
## on the command line (to try a split build on desktop), else nothing.
func _resolve_base_url() -> String:
	if OS.has_feature("web"):
		var href: Variant = JavaScriptBridge.eval("new URL('.', window.location.href).href", true)
		return str(href) if href != null else ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--content-base="):
			var url := arg.trim_prefix("--content-base=")
			return url if url.ends_with("/") else url + "/"
	return ""
