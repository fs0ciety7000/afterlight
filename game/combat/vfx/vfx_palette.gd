class_name VfxPalette
extends RefCounted
## Element palettes and day / night intensity for every VFX block (docs/VFX.md "Palette").
## Each palette: `core` (white-hot centre), `fringe` (coloured halo), `spark` (particles),
## `dark` (smoke, scorch embers). Colours are sRGB; the shaders declare them `source_color`.

const PEARL := Color("#f1f4ff")
const GLOW := Color("#a9c4ff")
const AMETHYST := Color("#a58ad6")

const ELEMENTS := {
	"arcane":
	{
		"core": PEARL,
		"fringe": Color("#9d8fe0"),
		"spark": GLOW,
		"dark": Color("#3a2f5c"),
	},
	"fire":
	{
		"core": Color("#fff3dc"),
		"fringe": Color("#ff8a3d"),
		"spark": Color("#ffc067"),
		"dark": Color("#5a2a1a"),
	},
	"frost":
	{
		"core": Color("#f4fbff"),
		"fringe": Color("#7cc8ef"),
		"spark": Color("#c9ecff"),
		"dark": Color("#24445c"),
	},
	"lightning":
	{
		"core": Color("#fffbe8"),
		"fringe": Color("#e9c95a"),
		"spark": Color("#fff1a8"),
		"dark": Color("#4a3f1a"),
	},
	# Not elements, but the same four roles for non-damage feedback.
	"heal":
	{
		"core": Color("#f4ffe8"),
		"fringe": Color("#9ee08a"),
		"spark": Color("#cdf5b8"),
		"dark": Color("#2d4a2a"),
	},
	"gold":
	{
		"core": Color("#fff6dc"),
		"fringe": Color("#f2c14e"),
		"spark": Color("#ffe39a"),
		"dark": Color("#4a3a12"),
	},
	"danger":
	{
		"core": Color("#ffd9c4"),
		"fringe": Color("#c4553f"),
		"spark": Color("#ff9a6a"),
		"dark": Color("#3a1410"),
	},
	"ash":
	{
		"core": Color("#ffcf9a"),
		"fringe": Color("#ff7a3a"),
		"spark": Color("#ff9a55"),
		"dark": Color("#2a2426"),
	},
	"mist":
	{
		"core": Color("#eef3ff"),
		"fringe": Color("#b8c6dd"),
		"spark": Color("#dfe7f5"),
		"dark": Color("#8a96ad"),
	},
}

## Day: effects cover part of the bright background (premultiplied `cover`) and push intensity
## a little; night: purely additive glow on the dark scene. Glow (bloom) does the rest.
const DAY := {"cover": 0.5, "intensity": 0.95}
const NIGHT := {"cover": 0.0, "intensity": 1.0}


static func colors(element: String) -> Dictionary:
	return ELEMENTS.get(element, ELEMENTS["arcane"])


static func color(element: String, role: String) -> Color:
	return colors(element).get(role, PEARL)


static func lighting(night: bool) -> Dictionary:
	return NIGHT if night else DAY


static func has_element(element: String) -> bool:
	return ELEMENTS.has(element)
