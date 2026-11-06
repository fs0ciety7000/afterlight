class_name CombatClock
extends RefCounted
## Frame time -> simulation ticks for the combat view (GDD §14, ROADMAP 7.4).
## A hit-stop freezes the clock: no tick is stepped and no time is banked, so
## the sim sees the same ticks in the same order with or without it (the
## event log stays the same, determinism 3.1). Hit-stops are off at ×4.

const MAX_STEPS_PER_FRAME := 40
## From this speed on, hit-stops are ignored (GDD §14 "Désactivé à ×4").
const NO_HIT_STOP_SPEED := 4

## Frame time banked towards the next tick (s of sim time).
var acc := 0.0
## Real time left in the current hit-stop (s).
var hit_stop_left := 0.0


## Asks for a freeze of `seconds`; overlapping requests keep the longest.
## Returns false when refused (nothing asked, or ×4).
func request_hit_stop(seconds: float, speed: int) -> bool:
	if seconds <= 0.0 or speed >= NO_HIT_STOP_SPEED:
		return false
	hit_stop_left = maxf(hit_stop_left, seconds)
	return true


func frozen() -> bool:
	return hit_stop_left > 0.0


## Ticks to step for a frame of `delta` seconds at `speed`.
func advance(delta: float, speed: int, paused: bool) -> int:
	if hit_stop_left > 0.0:
		hit_stop_left = maxf(hit_stop_left - delta, 0.0)
		return 0
	if paused:
		return 0
	acc += delta * speed
	var steps := 0
	while acc >= BalanceCombat.TICK_SECONDS and steps < MAX_STEPS_PER_FRAME:
		acc -= BalanceCombat.TICK_SECONDS
		steps += 1
	if steps >= MAX_STEPS_PER_FRAME:
		acc = 0.0
	return steps


## Progress towards the next tick (0..1), to interpolate positions.
func alpha() -> float:
	return clampf(acc / BalanceCombat.TICK_SECONDS, 0.0, 1.0)
