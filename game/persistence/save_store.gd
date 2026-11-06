class_name SaveStore
extends RefCounted
## Disk side of saving: one slot, atomic writes, a backup copy and a
## quarantine folder for damaged files. A damaged save is never overwritten
## before it has been copied to quarantine.

const MAIN := "slot_0.json"
const BACKUP := "slot_0.bak.json"
const TEMP := "slot_0.json.tmp"
const CORRUPT_DIR := "corrupt"

var dir_path: String
var migrations: Dictionary


func _init(
	path: String = "user://saves", migration_table: Dictionary = SaveMigrations.all()
) -> void:
	dir_path = path
	migrations = migration_table


func main_path() -> String:
	return dir_path.path_join(MAIN)


func backup_path() -> String:
	return dir_path.path_join(BACKUP)


func has_main() -> bool:
	return FileAccess.file_exists(main_path())


func read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


## Reads the main slot. Returns {status: "empty"|"ok"|"corrupt", decoded,
## backup: decode result of the backup or {} }.
func read() -> Dictionary:
	if not has_main():
		return {"status": "empty", "decoded": {}, "backup": _decode_backup()}
	var decoded := SaveCodec.decode(read_text(main_path()), migrations)
	if decoded["ok"]:
		return {"status": "ok", "decoded": decoded, "backup": {}}
	return {"status": "corrupt", "decoded": decoded, "backup": _decode_backup()}


## Writes a state atomically. Returns {ok, error}.
func write(state: Dictionary, now_unix: int) -> Dictionary:
	if DirAccess.make_dir_recursive_absolute(dir_path) != OK:
		return {"ok": false, "error": "cannot create %s" % dir_path}
	var text := SaveCodec.encode(state, now_unix)
	var temp := dir_path.path_join(TEMP)
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot open %s (%d)" % [temp, FileAccess.get_open_error()]}
	file.store_string(text)
	file.close()
	if not SaveCodec.decode(read_text(temp), migrations)["ok"]:
		DirAccess.remove_absolute(temp)
		return {"ok": false, "error": "written file failed verification"}
	if has_main():
		if SaveCodec.decode(read_text(main_path()), migrations)["ok"]:
			_replace(main_path(), backup_path())
		else:
			quarantine(now_unix)
	var err := _replace(temp, main_path())
	if err != OK:
		return {"ok": false, "error": "cannot move save into place (%d)" % err}
	_flush()
	return {"ok": true, "error": ""}


## Copies the current main file into the quarantine folder. Returns the copy's path.
func quarantine(now_unix: int) -> String:
	if not has_main():
		return ""
	var folder := dir_path.path_join(CORRUPT_DIR)
	DirAccess.make_dir_recursive_absolute(folder)
	var target := folder.path_join("slot_0-%d.json" % now_unix)
	var n := 1
	while FileAccess.file_exists(target):
		target = folder.path_join("slot_0-%d-%d.json" % [now_unix, n])
		n += 1
	DirAccess.copy_absolute(main_path(), target)
	return target


func quarantined_files() -> PackedStringArray:
	var folder := dir_path.path_join(CORRUPT_DIR)
	var dir := DirAccess.open(folder)
	var out := PackedStringArray()
	if dir:
		for f in dir.get_files():
			out.append(folder.path_join(f))
	return out


## Makes the backup the main save again (after quarantining the damaged main).
func restore_backup(now_unix: int) -> Dictionary:
	var backup := _decode_backup()
	if backup.is_empty() or not backup["ok"]:
		return {"ok": false, "error": "no valid backup"}
	if has_main():
		quarantine(now_unix)
	DirAccess.copy_absolute(backup_path(), main_path())
	_flush()
	return {"ok": true, "error": "", "decoded": backup}


func _decode_backup() -> Dictionary:
	if not FileAccess.file_exists(backup_path()):
		return {}
	return SaveCodec.decode(read_text(backup_path()), migrations)


## On the web, Godot copies user:// into IndexedDB when a file is closed, not
## when one is renamed. Writing a tiny marker after the rename makes the new
## save durable right away (it was lost on reload otherwise).
func _flush() -> void:
	var marker := FileAccess.open(dir_path.path_join(".flush"), FileAccess.WRITE)
	if marker:
		marker.store_string(str(Time.get_ticks_msec()))
		marker.close()


static func _replace(from: String, to: String) -> int:
	if FileAccess.file_exists(to):
		DirAccess.remove_absolute(to)
	return DirAccess.rename_absolute(from, to)
