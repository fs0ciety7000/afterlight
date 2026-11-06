class_name MotionFlags
extends RefCounted
## "Réduire les animations" (ROADMAP 7.3) as render flags: what the views
## will do with the current setting, and how many shakes, hit-stops and
## fades (screens, day -> night, after-light) they actually played since boot. Published as
## UiProbe.world["motion_flags"] so the E2E can check it.


static func snapshot() -> Dictionary:
	var reduced := Settings.reduce_motion
	return {
		"reduce_motion": reduced,
		"camera_shake": CameraRig.shake_allowed(),
		"screen_fades": Router.fades_enabled(),
		"hit_stop": not reduced,
		"particle_scale": Vfx.particle_factor(reduced, 2),
		"shakes_applied": CameraRig.shakes_applied,
		"hit_stops_applied": CombatView.hit_stops_applied,
		"fades_played": Router.fades_played,
		"world_fades_played": EnvFade.fades_played,
		"after_lights_played": EnvFade.after_lights_played,
	}
