class_name VfxSequence
extends Node3D
## Plays one recipe (VfxRecipes) for one cast: schedules its blocks on the four beats, resolves
## anchors (caster, staff tip, targets, sky) and forwards arrivals so the combat scene can sync
## damage numbers. Returned by Vfx.play("vfx.<recipe>", ctx).
##
## Beats: anticipation lasts ctx.cast_s (or the recipe default), release ctx.channel_s (or the
## default). Impact entries start when the travelling release blocks arrive (per target when
## `per_target`), or at the end of the release beat when nothing travels. Afterglow starts
## `impact` seconds after the last arrival.

signal beat(beat_name: String)
## A projectile / beam reached target `index` (also emitted on its own when nothing travels).
signal arrived(index: int, position: Vector3)
signal finished

var recipe: Dictionary = {}
var ctx: Dictionary = {}
var host: Vfx
var _clock := 0.0
var _queue: Array[Dictionary] = []
var _live: Array[VfxBlock] = []
var _beats: Dictionary = {}
var _expected := 0
var _arrivals := 0
var _impact_started := false
var _last_arrival := -1.0
var _afterglow_started := false
var _cancelled := false


func setup(recipe_data: Dictionary, context: Dictionary, vfx: Vfx) -> VfxSequence:
	recipe = recipe_data
	ctx = (recipe.get("defaults", {}) as Dictionary).duplicate()
	ctx.merge(context, true)
	host = vfx
	return self


func _ready() -> void:
	var b: Dictionary = recipe.get("beats", {})
	_beats = {
		"anticipation": float(ctx.get("cast_s", b.get("anticipation", 0.0))),
		"release": float(ctx.get("channel_s", b.get("release", 0.0))),
		"impact": float(b.get("impact", 0.3)),
		"afterglow": float(b.get("afterglow", 0.0)),
	}
	var t_rel: float = _beats["anticipation"]
	_push_beat("anticipation", 0.0)
	_push_beat("release", t_rel)
	for e: Dictionary in recipe.get("blocks", []):
		var beat_name := String(e.get("beat", "release"))
		if beat_name == "anticipation":
			_schedule(e, 0.0)
		elif beat_name == "release":
			_schedule(e, t_rel)
			if _travels(e):
				_expected += _count(e)
	if _expected == 0:
		# Nothing travels: impact at the end of the release beat.
		_queue.append({"time": t_rel + float(_beats["release"]), "impact_all": true})


## Interrupted cast (cast_interrupted): drops what is not spawned yet, fades what is live.
func cancel() -> void:
	_cancelled = true
	_queue.clear()
	for b in _live:
		if is_instance_valid(b):
			b.stop()


func _process(delta: float) -> void:
	_clock += delta
	var due: Array[Dictionary] = []
	for item in _queue:
		if float(item["time"]) <= _clock:
			due.append(item)
	for item in due:
		_queue.erase(item)
		_run(item)
	if (
		not _cancelled
		and not _afterglow_started
		and _impact_started
		and _arrivals >= _expected
		and _clock >= _last_arrival + float(_beats["impact"])
	):
		_afterglow_started = true
		_start_afterglow()
	for i in range(_live.size() - 1, -1, -1):
		if not is_instance_valid(_live[i]):
			_live.remove_at(i)
	var waiting := not _afterglow_started and not _cancelled
	if _queue.is_empty() and _live.is_empty() and not waiting:
		finished.emit()
		queue_free()


func _push_beat(beat_name: String, time: float) -> void:
	_queue.append({"time": time, "beat": beat_name})


func _run(item: Dictionary) -> void:
	if item.has("beat"):
		beat.emit(String(item["beat"]))
	elif item.has("impact_all"):
		_impact_started = true
		_last_arrival = _clock
		beat.emit("impact")
		var n := maxi(_targets().size(), 1)
		for i in n:
			arrived.emit(i, _anchor("target", i, {}))
			_spawn_impacts(i, i == n - 1)
	else:
		_spawn(item["entry"], int(item["index"]), bool(item.get("last", false)))


func _schedule(e: Dictionary, start: float) -> void:
	var n := _count(e) if e.get("per_target", false) else 1
	var stagger := float(e.get("stagger", 0.0))
	if e.get("spread", false) and n > 1:
		stagger = float(_beats["release"]) / n
	for i in n:
		var time := start + float(e.get("delay", 0.0)) + stagger * i
		_queue.append({"time": time, "entry": e, "index": i, "last": i == n - 1})


func _travels(e: Dictionary) -> bool:
	return String(e.get("block")) in ["projectile", "beam"] and e.has("to")


func _count(e: Dictionary) -> int:
	if e.has("count"):
		return int(e["count"])
	if e.get("per_target", false):
		return maxi(_targets().size(), 1)
	return 1


func _spawn(e: Dictionary, i: int, last: bool) -> VfxBlock:
	if _cancelled:
		return null
	var params: Dictionary = {
		"element": ctx.get("element", "arcane"),
		"intensity": float(ctx.get("intensity", 1.0)),
		"scale": float(ctx.get("scale", 1.0)),
		"crit": bool(ctx.get("crit", false)),
		"index": i,
		"seed": float(ctx.get("seed", 0)) + i,
	}
	params.merge(e.get("params", {}), true)
	# Caller overrides per block id (e.g. {"telegraph": {"radius": 3.0}} from the spell data).
	var overrides: Dictionary = ctx.get("overrides", {})
	params.merge(overrides.get(String(e["block"]), {}), true)
	params["count"] = _count(e) if e.get("per_target", false) else 1
	if e.has("toward"):
		params["toward"] = _anchor(String(e["toward"]), i, e)
	if e.has("attach"):
		params["target"] = _anchor_node(String(e["attach"]), i)
	if e.has("at"):
		params["position"] = _anchor(String(e["at"]), i, e)
		if e.get("follow", false):
			params["follow"] = _anchor_node(String(e["at"]), i)
	if e.has("from"):
		params["from"] = _anchor(String(e["from"]), i, e)
	if e.has("to"):
		var node := _anchor_node(String(e["to"]), i)
		if node and e.get("homing", true):
			params["to"] = node
			params["to_offset"] = _anchor(String(e["to"]), i, e) - node.global_position
		else:
			params["to"] = _anchor(String(e["to"]), i, e)
	if String(e.get("until", "")) != "":
		params["duration"] = _until(String(e["until"]), String(e.get("beat", "release")))
	if String(e.get("block")) == "shield" and ctx.has("duration"):
		params["duration"] = float(ctx["duration"])
	var block := host.spawn_block(String(e["block"]), params)
	if block == null:
		return null
	_live.append(block)
	if _travels(e) and String(e.get("beat", "release")) == "release":
		block.arrived.connect(_on_arrived)
	var feel_ok: bool = last or not e.get("per_target", false)
	if feel_ok and (e.has("hitstop_ms") or e.has("shake")):
		host.request_hit_stop(float(e.get("hitstop_ms", 0.0)) / 1000.0)
		host.request_shake(float(e.get("shake", 0.0)))
	return block


## First live block spawned from `block_id` (e.g. "shield" to call hit() / break_shield()).
func find_block(block_id: String) -> VfxBlock:
	for b in _live:
		if is_instance_valid(b) and String(b.name).begins_with(block_id):
			return b
	return null


func _on_arrived(i: int, pos: Vector3) -> void:
	if _cancelled:
		return
	_arrivals += 1
	_last_arrival = _clock
	if not _impact_started:
		_impact_started = true
		beat.emit("impact")
	arrived.emit(i, pos)
	_spawn_impacts(i, _arrivals >= _expected)


func _spawn_impacts(i: int, last: bool) -> void:
	for e: Dictionary in recipe.get("blocks", []):
		if String(e.get("beat", "")) != "impact":
			continue
		if e.get("per_target", false):
			_queue.append(
				{"time": _clock + float(e.get("delay", 0.0)), "entry": e, "index": i, "last": last}
			)
		elif i == 0:
			_queue.append(
				{"time": _clock + float(e.get("delay", 0.0)), "entry": e, "index": 0, "last": true}
			)


func _start_afterglow() -> void:
	beat.emit("afterglow")
	for e: Dictionary in recipe.get("blocks", []):
		if String(e.get("beat", "")) == "afterglow":
			_schedule(e, _clock)


## Seconds from this entry's beat start to the start of beat `until` ("end" = afterglow end).
func _until(until: String, from_beat: String) -> float:
	var starts := {
		"anticipation": 0.0,
		"release": float(_beats["anticipation"]),
		"impact": float(_beats["anticipation"]) + float(_beats["release"]),
	}
	starts["afterglow"] = float(starts["impact"]) + float(_beats["impact"])
	starts["end"] = float(starts["afterglow"]) + float(_beats["afterglow"])
	return maxf(float(starts.get(until, 0.0)) - float(starts.get(from_beat, 0.0)), 0.0)


# --- anchors ------------------------------------------------------------------------------


func _targets() -> Array:
	if ctx.has("targets"):
		return ctx["targets"]
	if ctx.has("target"):
		return [ctx["target"]]
	return []


func _target_value(i: int) -> Variant:
	var ts := _targets()
	if ts.is_empty():
		return null
	return ts[i % ts.size()]


func _caster_pos() -> Vector3:
	return VfxBlock.where(ctx.get("caster"), VfxBlock.where(ctx.get("from")))


func _anchor_node(anchor_name: String, i: int) -> Node3D:
	var v: Variant = null
	match anchor_name:
		"caster", "caster_chest":
			v = ctx.get("caster")
		"tip":
			v = ctx.get("tip")
		"target", "target_ground":
			v = _target_value(i)
	return v as Node3D if is_instance_valid(v) and v is Node3D else null


func _anchor(anchor_name: String, i: int, e: Dictionary) -> Vector3:
	var up := Vector3.UP
	var out := _caster_pos()
	match anchor_name:
		"caster_chest":
			out += up * float(ctx.get("caster_height", 1.0))
		"tip":
			var fwd := Vector3.FORWARD
			if is_instance_valid(ctx.get("caster")) and ctx.get("caster") is Node3D:
				fwd = -(ctx["caster"] as Node3D).global_basis.z
			out = VfxBlock.where(ctx.get("tip"), out + up * 1.3 + fwd * 0.35)
		"target":
			var th := float(ctx.get("target_height", -1.0))
			if th < 0.0:
				th = VfxBlock.height_of(_target_value(i), 1.6) * 0.55
			out = _target_pos(i) + up * th
		"target_ground":
			out = _target_pos(i) + _jitter(i, e)
		"center":
			out = _center()
		"sky":
			out = _center() + _sky(float(e.get("height", 6.0)), float(e.get("toward_view", 1.0)))
		"sky_above":
			var h := float(e.get("height", 6.0))
			out = _target_pos(i) + _sky(h, float(e.get("toward_view", 0.0))) + _jitter(i + 31, e)
	return out


## A point `h` metres above, pushed toward the camera (ctx.view_back, horizontal, default +Z)
## by `k` (1 = exactly over the anchor on screen from the 50 degree combat camera, 0 = straight
## up, so falling beams keep a readable length on screen).
func _sky(h: float, k: float) -> Vector3:
	var back: Vector3 = ctx.get("view_back", Vector3.BACK)
	var pitch := deg_to_rad(float(ctx.get("view_pitch_deg", 50.0)))
	return Vector3.UP * h + back.normalized() * h / tan(pitch) * k


func _target_pos(i: int) -> Vector3:
	var v: Variant = _target_value(i)
	if v == null:
		return _caster_pos() + Vector3.FORWARD * 6.0
	return VfxBlock.where(v)


func _center() -> Vector3:
	var ts := _targets()
	if ts.is_empty():
		return _target_pos(0)
	var c := Vector3.ZERO
	for v: Variant in ts:
		c += VfxBlock.where(v)
	return c / ts.size()


## Deterministic scatter (seeded by ctx.seed and the index) for rain-like recipes.
func _jitter(i: int, e: Dictionary) -> Vector3:
	var j := float(e.get("jitter", 0.0))
	if j <= 0.0:
		return Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = int(ctx.get("seed", 0)) * 977 + i * 131 + 7
	var a := rng.randf_range(0.0, TAU)
	return Vector3(cos(a), 0.0, sin(a)) * j * sqrt(rng.randf())
