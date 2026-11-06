class_name VfxBlock
extends Node3D
## Base of every VFX building block (cast circle, beam, burst...). Rendering only: a block
## never decides anything about the game, it draws what it is told for as long as it is told.
##
## Life cycle: `configure()` merges the caller params over `defaults()`, `_build()` creates the
## layers when the block enters the tree, `_tick(t)` animates them every frame from the block's
## own clock (so x2 / x4 speed and fixed-fps recordings stay exact), and the block frees itself
## when `life` is over. A block with `life < 0` loops (statuses, shields) until `stop()`, which
## plays its outro (`outro_s()`) and then frees it.

signal finished
## Travelling blocks (projectile, beam) emit this when they reach their target.
signal arrived(index: int, position: Vector3)

## Shapes of vfx_glow.gdshader.
enum Shape { ORB, RING, STREAK, GLINT, CRESCENT, SCORCH, MOTE, PUFF }
## Billboard modes of vfx_glow.gdshader.
enum Face { FLAT, CAMERA, AXIAL }

const GLOW_SHADER: Shader = preload("res://assets/vfx/shaders/vfx_glow.gdshader")
const RUNE_SHADER: Shader = preload("res://assets/vfx/shaders/vfx_rune_circle.gdshader")
const BEAM_SHADER: Shader = preload("res://assets/vfx/shaders/vfx_beam.gdshader")
const SHIELD_SHADER: Shader = preload("res://assets/vfx/shaders/vfx_shield.gdshader")
const ARC_SHADER: Shader = preload("res://assets/vfx/shaders/vfx_arc.gdshader")
const ICE_SHADER: Shader = preload("res://assets/vfx/shaders/vfx_ice.gdshader")
const TELEGRAPH_SHADER: Shader = preload("res://assets/vfx/shaders/vfx_telegraph.gdshader")

static var _quad: QuadMesh
static var _ground_quad: QuadMesh

## Merged parameters (defaults() + caller params).
var p: Dictionary = {}
## The Vfx node that spawned this block (flags: night, reduce_motion, particle budget).
var host: Vfx
var age := 0.0
## Total duration in seconds; < 0 loops until stop().
var life := 1.0
## Index of the target this block was spawned for (per-target recipe entries).
var index := 0
var _stop_age := -1.0
var _done := false


func configure(params: Dictionary, vfx: Vfx) -> VfxBlock:
	p = defaults()
	p.merge(params, true)
	host = vfx
	index = int(p.get("index", 0))
	return self


## Default parameters of the block; every key is documented in docs/VFX.md.
func defaults() -> Dictionary:
	return {}


## Seconds the block keeps playing after stop().
func outro_s() -> float:
	return 0.2


## Seconds between the block start and its arrival on the target (travelling blocks).
func travel_time() -> float:
	return 0.0


func stop() -> void:
	if _stop_age < 0.0:
		_stop_age = age


func is_stopping() -> bool:
	return _stop_age >= 0.0


## 0 -> 1 over the outro once stop() was called, else 0.
func stop_t() -> float:
	if _stop_age < 0.0:
		return 0.0
	return clampf((age - _stop_age) / maxf(outro_s(), 0.001), 0.0, 1.0)


func _ready() -> void:
	_build()
	_tick(0.0)


func _process(delta: float) -> void:
	if _done:
		return
	age += delta
	_tick(age)
	var over := life >= 0.0 and age >= life
	if is_stopping() and stop_t() >= 1.0:
		over = true
	if over:
		_done = true
		finished.emit()
		queue_free()


func _build() -> void:
	pass


func _tick(_t: float) -> void:
	pass


# --- parameters ---------------------------------------------------------------------------


func element() -> String:
	return String(p.get("element", "arcane"))


func col(role: String) -> Color:
	return VfxPalette.color(element(), role)


func num(key: String, fallback: float = 0.0) -> float:
	return float(p.get(key, fallback))


func size_scale() -> float:
	return float(p.get("scale", 1.0))


func is_night() -> bool:
	return host != null and host.night


func reduced() -> bool:
	return host != null and host.reduce_motion


## Particle count after the reduce-motion / quality budget (never below 1).
func budget(count: int) -> int:
	var k := 1.0 if host == null else host.particle_scale()
	return maxi(1, int(round(count * k)))


## Resolves a position param: a Node3D (live position), a Vector3, or the fallback.
static func where(value: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if is_instance_valid(value) and value is Node3D:
		return (value as Node3D).global_position
	if value is Vector3:
		return value
	return fallback


## Visual height (m) of a node from its meshes (rest AABB), or `fallback` when it has none.
static func height_of(node: Variant, fallback: float) -> float:
	if not (is_instance_valid(node) and node is Node3D):
		return fallback
	var root := node as Node3D
	var top := -INF
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var box := mi.global_transform * mi.get_aabb()
		top = maxf(top, box.end.y)
	if top == -INF:
		return fallback
	return maxf(top - root.global_position.y, 0.2)


# --- layers -------------------------------------------------------------------------------


static func quad_mesh() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


## A 1 x 1 quad lying on XZ (normal +Y): ground decals and sky circles.
static func ground_mesh() -> QuadMesh:
	if _ground_quad == null:
		_ground_quad = QuadMesh.new()
		_ground_quad.size = Vector2.ONE
		_ground_quad.orientation = PlaneMesh.FACE_Y
	return _ground_quad


## A ShaderMaterial with the palette and the day / night lighting already set.
func material(shader: Shader, roles: Array = ["core", "fringe"]) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	var light := VfxPalette.lighting(is_night())
	var gain := num("intensity", 1.0) * float(light["intensity"])
	m.set_shader_parameter("intensity", gain)
	m.set_shader_parameter("cover", float(light["cover"]))
	m.set_shader_parameter("core_color", col(roles[0]))
	m.set_shader_parameter("fringe_color", col(roles[1]))
	return m


func mesh_layer(mesh: Mesh, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	(parent if parent else self).add_child(mi)
	return mi


## A glow sprite (vfx_glow.gdshader) of `size` metres.
func sprite(
	shape: int, size: float, face: int = Face.CAMERA, roles: Array = ["core", "fringe"]
) -> MeshInstance3D:
	var m := material(GLOW_SHADER, roles)
	m.set_shader_parameter("shape", shape)
	m.set_shader_parameter("billboard", face)
	var mesh: Mesh = ground_mesh() if face == Face.FLAT else quad_mesh()
	var mi := mesh_layer(mesh, m)
	mi.scale = Vector3.ONE * size
	return mi


static func mat_of(mi: MeshInstance3D) -> ShaderMaterial:
	return mi.material_override as ShaderMaterial


static func setp(mi: GeometryInstance3D, key: String, value: Variant) -> void:
	(mi.material_override as ShaderMaterial).set_shader_parameter(key, value)


## CPUParticles3D drawing glow sprites. Works the same in Compatibility (WebGL 2) and the
## other renderers. cfg keys: amount, lifetime, shape, size, face, roles, one_shot,
## explosiveness, velocity (min, max), spread, direction, gravity, radius, damping,
## radial_accel, scale_curve ("shrink" / "grow" / "pop"), local, ramp (Gradient), align.
func particles(cfg: Dictionary) -> CPUParticles3D:
	var cp := CPUParticles3D.new()
	cp.amount = budget(int(cfg.get("amount", 16)))
	cp.lifetime = float(cfg.get("lifetime", 0.6))
	cp.one_shot = bool(cfg.get("one_shot", true))
	cp.explosiveness = float(cfg.get("explosiveness", 1.0 if cp.one_shot else 0.0))
	cp.randomness = float(cfg.get("randomness", 0.3))
	cp.local_coords = bool(cfg.get("local", false))
	cp.fixed_fps = 0
	cp.direction = cfg.get("direction", Vector3.UP)
	cp.spread = float(cfg.get("spread", 180.0))
	var vel: Vector2 = cfg.get("velocity", Vector2(1.0, 3.0))
	cp.initial_velocity_min = vel.x
	cp.initial_velocity_max = vel.y
	cp.gravity = cfg.get("gravity", Vector3.ZERO)
	cp.damping_min = float(cfg.get("damping", 0.0))
	cp.damping_max = float(cfg.get("damping", 0.0)) * 1.3
	cp.radial_accel_min = float(cfg.get("radial_accel", 0.0))
	cp.radial_accel_max = float(cfg.get("radial_accel", 0.0))
	var radius := float(cfg.get("radius", 0.0))
	if radius > 0.0:
		cp.emission_shape = (
			CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
			if cfg.get("surface", false)
			else CPUParticles3D.EMISSION_SHAPE_SPHERE
		)
		cp.emission_sphere_radius = radius
	var ring: Vector2 = cfg.get("ring", Vector2.ZERO)
	if ring != Vector2.ZERO:
		cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		cp.emission_ring_axis = Vector3.UP
		cp.emission_ring_radius = ring.y
		cp.emission_ring_inner_radius = ring.x
		cp.emission_ring_height = 0.05
	var size := float(cfg.get("size", 0.1))
	cp.scale_amount_min = size * 0.7
	cp.scale_amount_max = size * 1.3
	match String(cfg.get("scale_curve", "shrink")):
		"grow":
			cp.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(1, 1)])
		"pop":
			cp.scale_amount_curve = _curve([Vector2(0, 0.2), Vector2(0.15, 1), Vector2(1, 0)])
		"flat":
			pass
		_:
			cp.scale_amount_curve = _curve([Vector2(0, 1), Vector2(1, 0)])
	var face := int(cfg.get("face", Face.CAMERA))
	if face == Face.AXIAL:
		cp.particle_flag_align_y = true
	var m := material(GLOW_SHADER, cfg.get("roles", ["core", "spark"]))
	m.set_shader_parameter("shape", int(cfg.get("shape", Shape.MOTE)))
	m.set_shader_parameter("billboard", face)
	cp.mesh = quad_mesh()
	cp.material_override = m
	cp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ramp: Gradient = cfg.get("ramp", null)
	if ramp == null:
		ramp = Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 1))
		ramp.set_color(1, Color(1, 1, 1, 0))
	cp.color_ramp = ramp
	cp.emitting = bool(cfg.get("emitting", true))
	add_child(cp)
	return cp


static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for pt: Vector2 in points:
		c.add_point(pt)
	return c


# --- easing -------------------------------------------------------------------------------


static func ease_out(x: float) -> float:
	var k := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - k, 3.0)


static func ease_in(x: float) -> float:
	var k := clampf(x, 0.0, 1.0)
	return k * k * k


## 0 -> 1 over [a, b] seconds of `t`.
static func span(t: float, a: float, b: float) -> float:
	return clampf((t - a) / maxf(b - a, 0.0001), 0.0, 1.0)


## Rotates/scales a node so its local +Y goes from `a` to `b` (beams, streaks, arcs).
static func orient_between(node: Node3D, a: Vector3, b: Vector3, width: float) -> void:
	var d := b - a
	var l := maxf(d.length(), 0.001)
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.y) > 0.9 else Vector3.UP).normalized()
	var z := x.cross(y).normalized()
	node.global_transform = Transform3D(Basis(x * width, y * l, z), (a + b) * 0.5)
