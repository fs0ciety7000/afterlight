class_name EnvFade
extends RefCounted
## World light transitions of the dungeon (docs/content/dungeon.md 2.6, DESIGN.md "Passage jour →
## nuit"). Rendering only: callers pass the loaded place and the reduced-motion setting.
## - Day -> night: the new place's WorldEnvironment and sun start from the place Fern left and
##   blend to their own values in SECONDS; its lamps kindle in the second half. A cut when reduced.
## - « Lumière d'après »: when Morvaine falls, the dial's AfterLight comes down the shaft and
##   swells in AFTER_LIGHT_S while the ember threads die out. Its end state at once when reduced.

const SECONDS := 1.6
const AFTER_LIGHT_S := 3.0
## How far above its resting place the after-light starts (m, up the shaft).
const AFTER_LIGHT_DROP_M := 10.0
const WORLD_ENV := "Environment/WorldEnvironment"
const SUN := "Environment/Sun"
const AFTER_LIGHT := "Environment/Rooms/dial/AfterLight"
const THREADS := "Visuals/Glow/EmberThreads"

## Day -> night fades and after-light swells played since boot (none when reduced), for the E2E.
static var fades_played := 0
static var after_lights_played := 0


## The light of a loaded place, to fade from: {} when it has no WorldEnvironment.
static func snapshot(scene: Node) -> Dictionary:
	var we := scene.get_node_or_null(WORLD_ENV) as WorldEnvironment if scene else null
	if we == null or we.environment == null:
		return {}
	var e := we.environment
	var out := {
		"ambient_color": e.ambient_light_color,
		"ambient_energy": e.ambient_light_energy,
		"fog_color": e.fog_light_color,
		"fog_density": e.fog_density,
		"brightness": e.adjustment_brightness if e.adjustment_enabled else 1.0,
		"background_energy": e.background_energy_multiplier,
	}
	var sun := scene.get_node_or_null(SUN) as DirectionalLight3D
	if sun:
		out["sun_color"] = sun.light_color
		out["sun_energy"] = sun.light_energy
	return out


## The light of `scene` as `from` -> its own at `t` (0..1). Pure, for the tween and the tests.
static func blend(from: Dictionary, to: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key: String in to:
		if not from.has(key):
			out[key] = to[key]
		elif to[key] is Color:
			out[key] = (from[key] as Color).lerp(to[key], t)
		else:
			out[key] = lerpf(float(from[key]), float(to[key]), t)
	return out


## Fades `scene` (just loaded) from the light of the place left (`from`, see snapshot). Returns
## the tween, or null when there is nothing to fade or `reduced` asks for a cut.
static func play(scene: Node, from: Dictionary, reduced: bool, seconds: float = SECONDS) -> Tween:
	var we := scene.get_node_or_null(WORLD_ENV) as WorldEnvironment if scene else null
	if reduced or from.is_empty() or we == null or we.environment == null:
		return null
	# A copy: the Environment is shared with the cached PackedScene.
	var env := we.environment.duplicate() as Environment
	we.environment = env
	var to := snapshot(scene)
	var sun := scene.get_node_or_null(SUN) as DirectionalLight3D
	var lamps: Array[Light3D] = []
	var energies: Array[float] = []
	for node in scene.find_children("*", "Light3D", true, false):
		var l := node as Light3D
		if l is DirectionalLight3D or not l.visible:
			continue
		lamps.append(l)
		energies.append(l.light_energy)
	var step := func(t: float) -> void:
		_apply(env, sun, blend(from, to, t))
		var kindle := smoothstep(0.35, 1.0, t)
		for i in lamps.size():
			if is_instance_valid(lamps[i]):
				lamps[i].light_energy = energies[i] * kindle
	step.call(0.0)
	fades_played += 1
	var tw := scene.create_tween()
	tw.tween_method(step, 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tw


static func _apply(env: Environment, sun: DirectionalLight3D, v: Dictionary) -> void:
	env.ambient_light_color = v["ambient_color"]
	env.ambient_light_energy = v["ambient_energy"]
	env.fog_light_color = v["fog_color"]
	env.fog_density = v["fog_density"]
	env.background_energy_multiplier = v["background_energy"]
	if env.adjustment_enabled:
		env.adjustment_brightness = v["brightness"]
	if sun and v.has("sun_color"):
		sun.light_color = v["sun_color"]
		sun.light_energy = v["sun_energy"]


## Energy of the after-light at `t` (0..1) of its swell, as a fraction of its resting energy:
## rises, overshoots by a third, settles at 1.
static func after_light_curve(t: float) -> float:
	var rise := smoothstep(0.0, 0.7, t)
	var swell := sin(PI * clampf((t - 0.35) / 0.65, 0.0, 1.0))
	return rise * (1.0 + 0.35 * swell)


## Morvaine has fallen: the warm light comes down the shaft and the threads die out. `instant`
## (reduced motion, or a place reloaded after the fight) sets the end state at once. Returns the
## tween, or null.
static func after_light(scene: Node, instant: bool) -> Tween:
	var light := scene.get_node_or_null(AFTER_LIGHT) as OmniLight3D if scene else null
	if light == null or light.visible:
		return null
	var energy := light.light_energy
	var rest := light.position
	light.visible = true
	var threads := scene.get_node_or_null(THREADS) as MeshInstance3D
	var mat: ShaderMaterial = null
	if threads and threads.mesh:
		var own := threads.mesh.surface_get_material(0) as ShaderMaterial
		if own:
			mat = own.duplicate() as ShaderMaterial
			threads.material_override = mat
	if instant:
		if threads:
			threads.visible = false
		return null
	after_lights_played += 1
	var step := func(t: float) -> void:
		light.light_energy = energy * after_light_curve(t)
		var drop := 1.0 - t
		light.position = rest + Vector3.UP * AFTER_LIGHT_DROP_M * drop * drop
		if mat:
			mat.set_shader_parameter("strength", 1.0 - smoothstep(0.0, 0.8, t))
	step.call(0.0)
	var tw := scene.create_tween()
	tw.tween_method(step, 0.0, 1.0, AFTER_LIGHT_S)
	if threads:
		tw.tween_callback(func() -> void: threads.visible = false)
	return tw
