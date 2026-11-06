class_name Schema
extends RefCounted
## Small declarative validator for JSON-like data (content files, save states).
##
## A spec is a Dictionary:
##   type      "int" | "float" | "number" | "string" | "bool" | "array" | "dict" | "any"
##   optional  bool (default false); `default` is used when the key is missing
##   enum      Array of allowed values
##   min, max  numeric bounds (or length bounds for strings and arrays)
##   prefix    required string prefix, e.g. "spell."
##   pattern   RegEx the string must fully match
##   ref       entity type the string must reference (collected, checked by the caller)
##   items     spec of each array item
##   fields    {key: spec} for a dict with known keys (unknown keys are errors)
##   values    spec of each value for a dict used as a map
##   keys      spec of each key for a map (strings)
##
## validate() returns {"value": normalized copy, "errors": PackedStringArray,
## "refs": Array of [path, ref_type, id]}. JSON numbers come back as floats in
## Godot, so "int" fields accept integral floats and are converted.

const ID_PATTERN := "^[a-z][a-z0-9_]*\\.[a-z0-9_.]+$"


static func validate(value: Variant, spec: Dictionary, path: String = "$") -> Dictionary:
	var ctx := {"errors": PackedStringArray(), "refs": []}
	var out: Variant = _check(value, spec, path, ctx)
	return {"value": out, "errors": ctx["errors"], "refs": ctx["refs"]}


static func _fail(ctx: Dictionary, path: String, message: String) -> void:
	var errors: PackedStringArray = ctx["errors"]
	errors.append("%s: %s" % [path, message])
	ctx["errors"] = errors


static func _check(value: Variant, spec: Dictionary, path: String, ctx: Dictionary) -> Variant:
	var kind: String = spec.get("type", "any")
	match kind:
		"any":
			return value
		"int":
			return _check_int(value, spec, path, ctx)
		"float", "number":
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				_fail(ctx, path, "expected a number")
				return value
			_check_bounds(float(value), spec, path, ctx)
			return float(value)
		"string":
			return _check_string(value, spec, path, ctx)
		"bool":
			if typeof(value) != TYPE_BOOL:
				_fail(ctx, path, "expected a boolean")
			return value
		"array":
			return _check_array(value, spec, path, ctx)
		"dict":
			return _check_dict(value, spec, path, ctx)
	_fail(ctx, path, "unknown spec type '%s'" % kind)
	return value


static func _check_int(value: Variant, spec: Dictionary, path: String, ctx: Dictionary) -> Variant:
	var as_int := 0
	if typeof(value) == TYPE_INT:
		as_int = value
	elif typeof(value) == TYPE_FLOAT and is_finite(value) and floorf(value) == value:
		as_int = int(value)
	else:
		_fail(ctx, path, "expected an integer")
		return value
	_check_bounds(float(as_int), spec, path, ctx)
	if spec.has("enum") and not (spec["enum"] as Array).has(as_int):
		_fail(ctx, path, "value %d not in %s" % [as_int, spec["enum"]])
	return as_int


static func _check_bounds(number: float, spec: Dictionary, path: String, ctx: Dictionary) -> void:
	if spec.has("min") and number < float(spec["min"]):
		_fail(ctx, path, "must be >= %s" % spec["min"])
	if spec.has("max") and number > float(spec["max"]):
		_fail(ctx, path, "must be <= %s" % spec["max"])


static func _check_string(
	value: Variant, spec: Dictionary, path: String, ctx: Dictionary
) -> Variant:
	if typeof(value) != TYPE_STRING:
		_fail(ctx, path, "expected a string")
		return value
	var text: String = value
	if spec.has("min") and text.length() < int(spec["min"]):
		_fail(ctx, path, "must have at least %s characters" % spec["min"])
	if spec.has("max") and text.length() > int(spec["max"]):
		_fail(ctx, path, "must have at most %s characters" % spec["max"])
	if spec.has("enum") and not (spec["enum"] as Array).has(text):
		_fail(ctx, path, "'%s' not in %s" % [text, spec["enum"]])
	if spec.has("prefix") and not text.begins_with(spec["prefix"]):
		_fail(ctx, path, "'%s' must start with '%s'" % [text, spec["prefix"]])
	if spec.has("pattern"):
		var re := RegEx.create_from_string(spec["pattern"])
		var m := re.search(text)
		if m == null or m.get_string() != text:
			_fail(ctx, path, "'%s' does not match %s" % [text, spec["pattern"]])
	if spec.has("ref") and text != "":
		(ctx["refs"] as Array).append([path, spec["ref"], text])
	return text


static func _check_array(
	value: Variant, spec: Dictionary, path: String, ctx: Dictionary
) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		_fail(ctx, path, "expected an array")
		return value
	var items: Array = value
	if spec.has("min") and items.size() < int(spec["min"]):
		_fail(ctx, path, "must have at least %s items" % spec["min"])
	if spec.has("max") and items.size() > int(spec["max"]):
		_fail(ctx, path, "must have at most %s items" % spec["max"])
	var out := []
	for i in items.size():
		if spec.has("items"):
			out.append(_check(items[i], spec["items"], "%s[%d]" % [path, i], ctx))
		else:
			out.append(items[i])
	return out


static func _check_dict(value: Variant, spec: Dictionary, path: String, ctx: Dictionary) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		_fail(ctx, path, "expected an object")
		return value
	var source: Dictionary = value
	var out := {}
	if spec.has("fields"):
		var fields: Dictionary = spec["fields"]
		for key in fields:
			var field_spec: Dictionary = fields[key]
			if source.has(key):
				out[key] = _check(source[key], field_spec, "%s.%s" % [path, key], ctx)
			elif field_spec.get("optional", false):
				if field_spec.has("default"):
					out[key] = _deep_copy(field_spec["default"])
			else:
				_fail(ctx, path, "missing field '%s'" % key)
		for key in source:
			if not fields.has(key):
				_fail(ctx, "%s.%s" % [path, key], "unknown field")
	else:
		var keys := source.keys()
		keys.sort()
		for key in keys:
			if typeof(key) != TYPE_STRING:
				_fail(ctx, path, "map keys must be strings")
				continue
			if spec.has("keys"):
				_check(key, spec["keys"], "%s{%s}" % [path, key], ctx)
			if spec.has("values"):
				out[key] = _check(source[key], spec["values"], "%s.%s" % [path, key], ctx)
			else:
				out[key] = source[key]
	return out


static func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
