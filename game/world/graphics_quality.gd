class_name GraphicsQuality
extends RefCounted
## Rendering quality levels for weaker devices (low-end phones, no GPU).
## Applied to the root viewport and to a location scene's lighting and grass.

const LOW := 0
const MEDIUM := 1
const HIGH := 2
const NAMES := ["low", "medium", "high"]

## Per level: 3D resolution scale, MSAA, sun shadows, share of grass drawn.
const LEVELS := [
	{"scale": 0.5, "msaa": Viewport.MSAA_DISABLED, "shadows": false, "grass": 0.25},
	{"scale": 0.75, "msaa": Viewport.MSAA_DISABLED, "shadows": true, "grass": 0.6},
	{"scale": 1.0, "msaa": Viewport.MSAA_2X, "shadows": true, "grass": 1.0},
]


static func apply(level: int, viewport: Viewport, scene: Node) -> void:
	var cfg: Dictionary = LEVELS[clampi(level, LOW, HIGH)]
	viewport.scaling_3d_scale = cfg["scale"]
	viewport.msaa_3d = cfg["msaa"]
	if scene == null:
		return
	for node in scene.find_children("*", "DirectionalLight3D", true, false):
		(node as DirectionalLight3D).shadow_enabled = cfg["shadows"]
	var grass := scene.get_node_or_null("Visuals/Grass")
	if grass:
		for node in grass.find_children("*", "MultiMeshInstance3D", true, false):
			var mm := (node as MultiMeshInstance3D).multimesh
			if mm:
				mm.visible_instance_count = (
					-1 if cfg["grass"] >= 1.0 else int(mm.instance_count * cfg["grass"])
				)
