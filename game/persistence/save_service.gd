extends Node
## Autoload "SaveService": saves GameState to disk (IndexedDB on the web),
## autosaves, exports and imports. All format rules live in SaveCodec and
## SaveStore; this node adds timing and platform glue.

signal saved(at_unix: int)
signal save_failed(reason: String)
signal import_ready(decoded: Dictionary)
signal import_failed(code: String)

const AUTOSAVE_SECONDS := 30.0
const EXPORT_NAME := "afterlight-sauvegarde.json"

var store := SaveStore.new()
var last_saved_at := 0
var last_error := ""
var _timer: Timer
var _js_callbacks: Array = []
var _pick_callback: JavaScriptObject


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = AUTOSAVE_SECONDS
	_timer.autostart = true
	_timer.timeout.connect(_on_autosave_tick)
	add_child(_timer)
	GameState.save_requested.connect(save_if_dirty)
	if OS.has_feature("web"):
		_install_web_hooks()


## Reads the slot at boot. See SaveStore.read().
func boot_read() -> Dictionary:
	return store.read()


func save_now() -> bool:
	if not GameState.has_game():
		return false
	var now := GameState.now_unix()
	GameState.mark_active(now)
	var r := store.write(GameState.data, now)
	if r["ok"]:
		last_saved_at = now
		last_error = ""
		GameState.dirty = false
		saved.emit(now)
		return true
	last_error = r["error"]
	save_failed.emit(r["error"])
	return false


func save_if_dirty() -> void:
	if GameState.has_game() and GameState.dirty:
		save_now()


func _on_autosave_tick() -> void:
	if GameState.has_game():
		GameState.dirty = true  # play time moved on
		save_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_if_dirty()


# --- Export / import -------------------------------------------------------


## Exports the current game. Returns a French status message.
func export_current() -> String:
	if not GameState.has_game():
		return ""
	return _export_text(SaveCodec.encode(GameState.data, GameState.now_unix()))


## Exports the raw bytes of the damaged main file (recovery screen).
func export_damaged() -> String:
	return _export_text(store.read_text(store.main_path()), "afterlight-sauvegarde-endommagee.json")


func _export_text(text: String, file_name: String = EXPORT_NAME) -> String:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), file_name, "application/json")
		return tr("ui.export.done_web")
	DirAccess.make_dir_recursive_absolute("user://exports")
	var path := "user://exports".path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return tr("ui.export.done_path").format({"path": ProjectSettings.globalize_path(path)})


## Opens a file picker; emits import_ready(decoded) or import_failed(code).
func request_import(host: Node) -> void:
	if OS.has_feature("web"):
		_pick_callback = JavaScriptBridge.create_callback(_on_web_file)
		JavaScriptBridge.get_interface("window").__afterlightPickFile(_pick_callback)
		return
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; Sauvegarde Afterlight"])
	dialog.use_native_dialog = true
	dialog.file_selected.connect(
		func(path: String) -> void: import_text(FileAccess.get_file_as_string(path))
	)
	dialog.canceled.connect(func() -> void: import_failed.emit("cancelled"))
	host.add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func import_text(text: String) -> void:
	if text == "":
		import_failed.emit("cancelled")
		return
	var decoded := SaveCodec.decode(text, store.migrations)
	if decoded["ok"]:
		import_ready.emit(decoded)
	else:
		import_failed.emit(decoded["error"])


## Applies a decoded import after the player confirmed it.
func apply_import(decoded: Dictionary) -> bool:
	GameState.adopt(decoded["state"], false)
	GameState.dirty = true
	return save_now()


func _on_web_file(args: Array) -> void:
	import_text(str(args[0]) if args.size() > 0 and args[0] != null else "")


func _install_web_hooks() -> void:
	(
		JavaScriptBridge
		. eval(
			"""
		window.__afterlightPickFile = function (cb) {
			const input = document.createElement('input');
			input.type = 'file';
			input.accept = '.json,application/json';
			input.addEventListener('change', () => {
				const file = input.files && input.files[0];
				if (!file) { cb(''); return; }
				file.text().then((t) => cb(t), () => cb(''));
			});
			input.addEventListener('cancel', () => cb(''));
			input.click();
		};
		""",
			true
		)
	)
	var on_hidden := JavaScriptBridge.create_callback(func(_args: Array) -> void: save_if_dirty())
	_js_callbacks.append(on_hidden)
	var doc := JavaScriptBridge.get_interface("document")
	doc.addEventListener("visibilitychange", on_hidden)
