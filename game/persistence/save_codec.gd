class_name SaveCodec
extends RefCounted
## Turns a game state into a save file and back. No file I/O here: the
## service handles disks, this handles format, integrity and migrations.

const FORMAT := "afterlight-save"
const CURRENT_VERSION := 6

## Error codes returned by decode(); the UI maps them to French messages.
const ERR_NOT_JSON := "not_json"
const ERR_NOT_A_SAVE := "not_a_save"
const ERR_FUTURE_VERSION := "future_version"
const ERR_CHECKSUM := "checksum"
const ERR_MIGRATION := "migration"
const ERR_INVALID_STATE := "invalid_state"


## Canonical JSON: sorted keys, full precision. Values go through a JSON
## round trip first so ints and floats hash the same way after loading.
static func canonical(value: Variant) -> String:
	var round_trip: Variant = JSON.parse_string(JSON.stringify(value, "", true, true))
	return JSON.stringify(round_trip, "", true, true)


static func checksum(state: Dictionary) -> String:
	return canonical(state).sha256_text()


static func encode(state: Dictionary, now_unix: int, version: int = CURRENT_VERSION) -> String:
	var envelope := {
		"format": FORMAT,
		"version": version,
		"saved_at": now_unix,
		"checksum": checksum(state),
		"state": state,
	}
	return JSON.stringify(envelope, "\t", true, true)


## Returns {ok, state, version, saved_at, migrated_from, error, detail}.
## `migrations` maps a version n to a Callable(state) -> state at n + 1.
static func decode(
	text: String, migrations: Dictionary = {}, current_version: int = CURRENT_VERSION
) -> Dictionary:
	var result := {
		"ok": false,
		"state": {},
		"version": 0,
		"saved_at": 0,
		"migrated_from": 0,
		"error": "",
		"detail": "",
	}
	var json := JSON.new()
	if json.parse(text) != OK:
		return _error(result, ERR_NOT_JSON, json.get_error_message())
	var envelope: Variant = json.data
	if typeof(envelope) != TYPE_DICTIONARY or envelope.get("format") != FORMAT:
		return _error(result, ERR_NOT_A_SAVE, "missing format marker")
	for key in ["version", "saved_at", "checksum", "state"]:
		if not envelope.has(key):
			return _error(result, ERR_NOT_A_SAVE, "missing '%s'" % key)
	if typeof(envelope["state"]) != TYPE_DICTIONARY:
		return _error(result, ERR_NOT_A_SAVE, "state is not an object")
	var version := int(envelope["version"])
	result["version"] = version
	result["saved_at"] = int(envelope["saved_at"])
	if version > current_version:
		return _error(result, ERR_FUTURE_VERSION, "version %d > %d" % [version, current_version])
	if checksum(envelope["state"]) != str(envelope["checksum"]):
		return _error(result, ERR_CHECKSUM, "checksum mismatch")
	var state: Dictionary = envelope["state"]
	var from := version
	while version < current_version:
		if not migrations.has(version):
			return _error(result, ERR_MIGRATION, "no migration from v%d" % version)
		var migrated: Variant = (migrations[version] as Callable).call(state.duplicate(true))
		if typeof(migrated) != TYPE_DICTIONARY:
			return _error(result, ERR_MIGRATION, "migration from v%d failed" % version)
		state = migrated
		version += 1
	var checked := StateSchema.validate(state)
	if not checked["errors"].is_empty():
		return _error(result, ERR_INVALID_STATE, "\n".join(checked["errors"]))
	result["ok"] = true
	result["state"] = checked["value"]
	result["version"] = version
	result["migrated_from"] = from if from != version else 0
	return result


static func _error(result: Dictionary, code: String, detail: String) -> Dictionary:
	result["error"] = code
	result["detail"] = detail
	return result
