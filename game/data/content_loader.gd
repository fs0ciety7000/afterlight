class_name ContentLoader
extends RefCounted
## Reads and validates content files (docs/CONTENT_PIPELINE.md §2 and §8).
## Separate from the autoload so tests can load fixture folders.
##
## File: {"schema_version": 1, "type": "<type>", "entries": [ {...} ]}
## named after its type (enemies.json holds type "enemy"). Each entry's type
## comes from its id prefix and must be allowed in that file.

const STRINGS_CSV := "res://game/i18n/strings.csv"
const RUNTIME_LOOKUP := "__runtime_lookup__"


static func load_roots(roots: Array, strings_csv: String = STRINGS_CSV) -> Dictionary:
	var ctx := {"errors": PackedStringArray(), "by_id": {}, "by_type": {}, "refs": [], "files": {}}
	for root in roots:
		for path in _json_files(root):
			_load_file(path, root, ctx)
	_check_refs(ctx)
	ContentRules.check(ctx, translation_keys(strings_csv))
	return {"errors": ctx["errors"], "by_id": ctx["by_id"], "by_type": ctx["by_type"]}


static func translation_keys(csv_path: String) -> Dictionary:
	var keys := {}
	var f := FileAccess.open(csv_path, FileAccess.READ)
	if f == null:
		# Exported builds only ship the compiled (optimized) translation, which
		# cannot list its keys: ContentRules then asks TranslationServer per key.
		keys[RUNTIME_LOOKUP] = true
		return keys
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() > 0 and row[0] != "":
			keys[row[0]] = true
	return keys


static func fail(ctx: Dictionary, rule: String, file: String, id: String, message: String) -> void:
	var errors: PackedStringArray = ctx["errors"]
	errors.append("%s %s %s %s" % [rule, file, id, message])
	ctx["errors"] = errors


static func _load_file(path: String, root: String, ctx: Dictionary) -> void:
	var file := path.get_file()
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		fail(
			ctx,
			"V1",
			file,
			"-",
			"invalid JSON line %d: %s" % [json.get_error_line(), json.get_error_message()]
		)
		return
	var doc: Variant = json.data
	if typeof(doc) != TYPE_DICTIONARY:
		fail(ctx, "V1", file, "-", "expected an object")
		return
	if int(doc.get("schema_version", -1)) != ContentSchemas.SCHEMA_VERSION:
		fail(ctx, "V1", file, "-", "schema_version missing or unknown")
		return
	var stem := file.get_basename()
	if not ContentSchemas.FILES.has(stem):
		fail(ctx, "V1", file, "-", "unknown content file name")
		return
	var declared: String = ContentSchemas.FILES[stem][0]
	var allowed: Array = ContentSchemas.FILES[stem][1]
	if doc.get("type", "") != declared:
		fail(ctx, "V1", file, "-", "type must be '%s' in %s" % [declared, file])
		return
	if typeof(doc.get("entries")) != TYPE_ARRAY:
		fail(ctx, "V1", file, "-", "entries must be an array")
		return
	var folder_origin := "canon" if root.trim_suffix("/").ends_with("canon") else "original"
	for raw in doc["entries"]:
		_load_entry(raw, file, folder_origin, allowed, ctx)


static func _load_entry(
	raw: Variant, file: String, folder_origin: String, allowed: Array, ctx: Dictionary
) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		fail(ctx, "V7", file, "-", "entry must be an object")
		return
	var id := str(raw.get("id", ""))
	for literal in ["name", "text", "label"]:
		if raw.has(literal):
			fail(
				ctx, "V19", file, id, "literal '%s' is not allowed, use a translation key" % literal
			)
	var re := RegEx.create_from_string(ContentSchemas.ID_PATTERN)
	if re.search(id) == null or id.length() > 48:
		fail(ctx, "V2", file, id, "id must match %s (48 chars max)" % ContentSchemas.ID_PATTERN)
		return
	var type_name := ContentSchemas.type_of_id(id)
	if not allowed.has(type_name):
		fail(ctx, "V2", file, id, "prefix '%s' is not allowed in %s" % [id.get_slice(".", 0), file])
		return
	if raw.get("origin", "") != folder_origin:
		fail(ctx, "V4", file, id, "origin must be '%s' in this folder" % folder_origin)
		return
	var r := Schema.validate(raw, ContentSchemas.entity_spec(type_name), id)
	for e in r["errors"]:
		var rule := "V8" if (e.contains("must be >=") or e.contains("must be <=")) else "V7"
		fail(ctx, rule, file, id, e.trim_prefix(id + "."))
	if not r["errors"].is_empty():
		return
	if ctx["by_id"].has(id):
		fail(ctx, "V3", file, id, "duplicate id (also in %s)" % ctx["files"][id])
		return
	var entity: Dictionary = r["value"]
	entity["_type"] = type_name
	ctx["by_id"][id] = entity
	ctx["files"][id] = file
	if not ctx["by_type"].has(type_name):
		ctx["by_type"][type_name] = []
	ctx["by_type"][type_name].append(entity)
	for ref in r["refs"]:
		ctx["refs"].append([file, id, ref[0], ref[1], ref[2]])


static func _check_refs(ctx: Dictionary) -> void:
	for ref in ctx["refs"]:
		var file: String = ref[0]
		var owner: String = ref[1]
		var where: String = str(ref[2]).trim_prefix(owner + ".")
		var types: Array = ref[3] if ref[3] is Array else [ref[3]]
		var target: String = ref[4]
		if not ctx["by_id"].has(target):
			fail(ctx, "V6", file, owner, "%s: unknown %s '%s'" % [where, "/".join(types), target])
		elif not types.has(ctx["by_id"][target]["_type"]):
			fail(
				ctx,
				"V6",
				file,
				owner,
				(
					"%s: '%s' is a %s, expected %s"
					% [where, target, ctx["by_id"][target]["_type"], "/".join(types)]
				)
			)


static func _json_files(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_json_files(root.path_join(sub)))
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(root.path_join(f))
	out.sort()
	return out
