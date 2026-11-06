extends TestCase
## Day -> night fade on entering the dungeon and the « lumière d'après » when
## Morvaine falls (docs/content/dungeon.md 2.6, ROADMAP 7.3): they play as
## tweens, cut with reduced motion, and never edit the shared scene resources.

const DAY := {
	"ambient_color": Color(0.7, 0.7, 0.8),
	"ambient_energy": 0.3,
	"fog_color": Color(0.9, 0.85, 0.75),
	"fog_density": 0.004,
	"brightness": 0.96,
	"background_energy": 1.0,
	"sun_color": Color(1.0, 0.85, 0.63),
	"sun_energy": 0.65,
}


## A tiny night place: environment, moon, one lamp, the dial's after-light and threads.
func _night() -> Node3D:
	var root := Node3D.new()
	var env_node := Node3D.new()
	env_node.name = "Environment"
	root.add_child(env_node)
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.ambient_light_color = Color(0.24, 0.27, 0.32)
	env.ambient_light_energy = 0.9
	env.fog_light_color = Color(0.12, 0.16, 0.25)
	env.fog_density = 0.008
	env.adjustment_enabled = true
	we.environment = env
	env_node.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(0.74, 0.82, 1.0)
	sun.light_energy = 0.4
	env_node.add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.light_energy = 0.7
	env_node.add_child(lamp)
	var dial := Node3D.new()
	dial.name = "dial"
	var rooms := Node3D.new()
	rooms.name = "Rooms"
	env_node.add_child(rooms)
	rooms.add_child(dial)
	var after := OmniLight3D.new()
	after.name = "AfterLight"
	after.visible = false
	after.light_energy = 3.0
	after.position = Vector3(0, 14, 0)
	dial.add_child(after)
	var glow := Node3D.new()
	glow.name = "Glow"
	var visuals := Node3D.new()
	visuals.name = "Visuals"
	root.add_child(visuals)
	visuals.add_child(glow)
	var threads := MeshInstance3D.new()
	threads.name = "EmberThreads"
	var mesh := QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/env_ember.gdshader")
	mesh.material = mat
	threads.mesh = mesh
	glow.add_child(threads)
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	return root


func test_blend_runs_from_the_place_left_to_the_new_one() -> void:
	var night := {"ambient_energy": 0.9, "fog_color": Color(0, 0, 0), "extra": 2.0}
	var a := EnvFade.blend(DAY, night, 0.0)
	var b := EnvFade.blend(DAY, night, 1.0)
	assert_near(a["ambient_energy"], 0.3, 0.0001, "start: day")
	assert_near(b["ambient_energy"], 0.9, 0.0001, "end: night")
	assert_eq(b["fog_color"], Color(0, 0, 0), "colour end")
	assert_near(EnvFade.blend(DAY, night, 0.5)["ambient_energy"], 0.6, 0.0001, "half way")
	assert_near(a["extra"], 2.0, 0.0001, "missing in `from`: the night value")


func test_fade_blends_a_copy_and_kindles_the_lamps() -> void:
	var root := _night()
	var we := root.get_node("Environment/WorldEnvironment") as WorldEnvironment
	var shared := we.environment
	var before := EnvFade.fades_played
	var tw := EnvFade.play(root, DAY, false)
	assert_true(tw != null, "a tween")
	assert_eq(EnvFade.fades_played, before + 1, "counted")
	assert_true(we.environment != shared, "the shared Environment is not edited")
	assert_near(shared.ambient_light_energy, 0.9, 0.0001, "shared resource untouched")
	assert_near(we.environment.ambient_light_energy, 0.3, 0.0001, "starts at the day value")
	var sun := root.get_node("Environment/Sun") as DirectionalLight3D
	assert_near(sun.light_energy, 0.65, 0.0001, "sun starts at the day value")
	var lamp := root.get_node("Environment/Lamp") as OmniLight3D
	assert_near(lamp.light_energy, 0.0, 0.0001, "lamps unlit at first")
	tw.custom_step(EnvFade.SECONDS + 0.1)
	assert_near(we.environment.ambient_light_energy, 0.9, 0.0001, "ends at night")
	assert_near(we.environment.fog_density, 0.008, 0.00001, "night fog")
	assert_near(sun.light_energy, 0.4, 0.0001, "moon")
	assert_near(lamp.light_energy, 0.7, 0.0001, "lamp lit")
	assert_true(EnvFade.SECONDS >= 1.5 and EnvFade.SECONDS <= 2.0, "1.5-2 s")
	root.free()


func test_reduced_motion_cuts() -> void:
	var root := _night()
	var we := root.get_node("Environment/WorldEnvironment") as WorldEnvironment
	var shared := we.environment
	var before := EnvFade.fades_played
	assert_true(EnvFade.play(root, DAY, true) == null, "no tween")
	assert_true(EnvFade.play(root, {}, false) == null, "nothing to fade from")
	assert_eq(EnvFade.fades_played, before, "not counted")
	assert_true(we.environment == shared, "night at once")
	root.free()


func test_after_light_swells_in_three_seconds_and_cuts_the_threads() -> void:
	var root := _night()
	var light := root.get_node(EnvFade.AFTER_LIGHT) as OmniLight3D
	var threads := root.get_node(EnvFade.THREADS) as MeshInstance3D
	var before := EnvFade.after_lights_played
	var tw := EnvFade.after_light(root, false)
	assert_true(tw != null, "a tween")
	assert_eq(EnvFade.after_lights_played, before + 1, "counted")
	assert_true(light.visible, "on")
	assert_near(light.light_energy, 0.0, 0.0001, "starts dark")
	assert_true(light.position.y > 14.0 + 5.0, "starts up the shaft")
	tw.custom_step(EnvFade.AFTER_LIGHT_S * 0.6)
	assert_true(light.light_energy > 3.0, "swells past its resting energy")
	tw.custom_step(EnvFade.AFTER_LIGHT_S)
	assert_near(light.light_energy, 3.0, 0.0001, "settles")
	assert_near(light.position.y, 14.0, 0.0001, "came down")
	var mat := threads.material_override as ShaderMaterial
	assert_true(mat != null, "threads use their own material copy")
	assert_near(float(mat.get_shader_parameter("strength")), 0.0, 0.0001, "threads out")
	assert_true(not threads.visible, "threads hidden")
	assert_true(EnvFade.after_light(root, false) == null, "plays once")
	root.free()


func test_after_light_is_instant_when_reduced() -> void:
	var root := _night()
	var before := EnvFade.after_lights_played
	assert_true(EnvFade.after_light(root, true) == null, "no tween")
	var light := root.get_node(EnvFade.AFTER_LIGHT) as OmniLight3D
	assert_true(light.visible, "on at once")
	assert_near(light.light_energy, 3.0, 0.0001, "full energy")
	assert_true(not (root.get_node(EnvFade.THREADS) as Node3D).visible, "threads hidden")
	assert_eq(EnvFade.after_lights_played, before, "not counted")
	root.free()


func test_after_light_curve() -> void:
	assert_near(EnvFade.after_light_curve(0.0), 0.0, 0.0001, "dark")
	assert_near(EnvFade.after_light_curve(1.0), 1.0, 0.0001, "rest")
	var peak := 0.0
	for i in 101:
		peak = maxf(peak, EnvFade.after_light_curve(i / 100.0))
	assert_true(peak > 1.2 and peak < 1.4, "overshoot about a third")
