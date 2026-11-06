extends TestCase
## ROADMAP 7.3 (unit part): "Réduire les animations" cuts camera shake and
## hit-stop, replaces fades with cuts and halves the particles; the render
## flags published for the E2E follow the setting.


func _with_reduced(on: bool, body: Callable) -> void:
	var saved := Settings.reduce_motion
	Settings.reduce_motion = on
	body.call()
	Settings.reduce_motion = saved


func test_flags_follow_the_setting() -> void:
	_with_reduced(
		true,
		func() -> void:
			var f := MotionFlags.snapshot()
			assert_eq(f["reduce_motion"], true, "reduced")
			assert_eq(f["camera_shake"], false, "no shake")
			assert_eq(f["screen_fades"], false, "cuts")
			assert_eq(f["hit_stop"], false, "no hit-stop")
			assert_near(f["particle_scale"], 0.5, 0.001, "half the particles")
	)
	_with_reduced(
		false,
		func() -> void:
			var f := MotionFlags.snapshot()
			assert_eq(f["camera_shake"], true, "shake")
			assert_eq(f["screen_fades"], true, "fades")
			assert_eq(f["hit_stop"], true, "hit-stop")
			assert_near(f["particle_scale"], 1.0, 0.001, "all particles")
	)


func test_camera_ignores_shake_when_reduced() -> void:
	var rig := CameraRig.new()
	_with_reduced(
		true,
		func() -> void:
			var before := CameraRig.shakes_applied
			rig.add_shake(0.8)
			assert_eq(CameraRig.shakes_applied, before, "no shake applied")
			assert_near(rig.get("_trauma"), 0.0, 0.0001, "no trauma")
	)
	_with_reduced(
		false,
		func() -> void:
			var before := CameraRig.shakes_applied
			rig.add_shake(0.5)
			assert_eq(CameraRig.shakes_applied, before + 1, "shake applied")
	)
	rig.free()


func test_vfx_requests_no_hit_stop_or_shake_and_halves_particles() -> void:
	var vfx := Vfx.new()
	var got := {"stop": 0, "shake": 0}
	vfx.hit_stop_requested.connect(func(_s: float) -> void: got["stop"] += 1)
	vfx.shake_requested.connect(func(_t: float) -> void: got["shake"] += 1)
	vfx.reduce_motion = true
	vfx.request_hit_stop(0.05)
	vfx.request_shake(0.4)
	assert_eq(got, {"stop": 0, "shake": 0}, "reduced: nothing requested")
	assert_near(vfx.particle_scale(), 0.5, 0.001, "half the particles")
	var block := VfxBlock.new()
	block.host = vfx
	assert_eq(block.budget(24), 12, "budget halved")
	vfx.reduce_motion = false
	vfx.request_hit_stop(0.05)
	vfx.request_shake(0.4)
	assert_eq(got, {"stop": 1, "shake": 1}, "normal: both requested")
	assert_eq(block.budget(24), 24, "full budget")
	block.free()
	vfx.free()


func test_router_cuts_instead_of_fading() -> void:
	_with_reduced(true, func() -> void: assert_true(not Router.fades_enabled(), "cut"))
	_with_reduced(false, func() -> void: assert_true(Router.fades_enabled(), "fade"))
