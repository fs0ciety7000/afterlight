class_name SeededRng
extends RefCounted
## Deterministic random stream (PCG32 via RandomNumberGenerator).
## Seed and state are plain ints so a stream can be saved and resumed.

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value


## Derives an independent seed for a named stream, so drawing loot never
## shifts the combat sequence (and vice versa).
static func derive_seed(base_seed: int, stream: String, counter: int = 0) -> int:
	return ("%d:%s:%d" % [base_seed, stream, counter]).hash()


func get_state() -> int:
	return _rng.state


func set_state(value: int) -> void:
	_rng.state = value


## Uniform float in [0, 1).
func next_float() -> float:
	return _rng.randf()


## Uniform int in [from, to] (inclusive).
func range_int(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func range_float(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


## True with probability `p` (clamped to [0, 1]).
func chance(p: float) -> bool:
	return _rng.randf() < clampf(p, 0.0, 1.0)


## Picks a key from {key: weight}. Keys are visited in sorted order so the
## result does not depend on dictionary insertion order. Returns null if all
## weights are zero.
func pick_weighted(weights: Dictionary) -> Variant:
	var keys := weights.keys()
	keys.sort()
	var total := 0.0
	for key in keys:
		total += maxf(float(weights[key]), 0.0)
	if total <= 0.0:
		return null
	var roll := _rng.randf() * total
	for key in keys:
		roll -= maxf(float(weights[key]), 0.0)
		if roll < 0.0:
			return key
	return keys[keys.size() - 1]
