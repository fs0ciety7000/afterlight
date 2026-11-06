class_name CameraRig
extends Node3D
## 3/4 top-down follow camera (DESIGN.md): ~50° pitch, damped follow and
## two zoom steps.

const PITCH_DEG := 50.0
const DISTANCES := [11.0, 8.5, 6.5]
const FOLLOW_SHARPNESS := 6.0
const FOV := 40.0

## Shakes accepted since boot (all rigs), read by MotionFlags for the E2E probe.
static var shakes_applied := 0

var target: Node3D
## Screen radius of the cut-out around the hero (wider in combat).
var cut_radius := 0.22
var zoom_index := 0
var camera: Camera3D
var _trauma := 0.0
var _distance := 11.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = FOV
	camera.current = true
	add_child(camera)
	_distance = DISTANCES[zoom_index]
	_place_camera()


func snap() -> void:
	if target:
		global_position = target.global_position
	_place_camera()


## Camera shake request (crits, boss hits); decays quickly. Ignored when
## "Réduire les animations" is on (DESIGN.md "Mouvement").
func add_shake(trauma: float) -> void:
	if trauma <= 0.0 or not shake_allowed():
		return
	shakes_applied += 1
	_trauma = clampf(_trauma + trauma, 0.0, 1.0)


static func shake_allowed() -> bool:
	return not Settings.reduce_motion


func zoom(step: int) -> void:
	zoom_index = clampi(zoom_index + step, 0, DISTANCES.size() - 1)


func _process(delta: float) -> void:
	if target:
		var t := 1.0 - exp(-FOLLOW_SHARPNESS * delta)
		global_position = global_position.lerp(target.global_position, t)
	_distance = lerpf(_distance, DISTANCES[zoom_index], 1.0 - exp(-8.0 * delta))
	_place_camera()
	if target:
		# Environment shaders cut out what stands in front of the hero.
		RenderingServer.global_shader_parameter_set(
			"hero_depth", camera.global_position.distance_to(target.global_position + Vector3.UP)
		)
		RenderingServer.global_shader_parameter_set("hero_cut_radius", cut_radius)


func _place_camera() -> void:
	var pitch := deg_to_rad(PITCH_DEG)
	camera.position = Vector3(0.0, sin(pitch) * _distance + 0.8, cos(pitch) * _distance)
	camera.rotation = Vector3(-pitch, 0.0, 0.0)
	if _trauma > 0.0:
		var amp := _trauma * _trauma * 0.25
		camera.position += Vector3(randf_range(-amp, amp), randf_range(-amp, amp), 0.0)
		_trauma = maxf(_trauma - get_process_delta_time() * 2.5, 0.0)
