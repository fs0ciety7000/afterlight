class_name UiTokens
extends RefCounted
## Design tokens from DESIGN.md. Screens never hardcode colors or sizes.

const SPACE := {"xs": 4, "sm": 8, "md": 12, "lg": 16, "xl": 24, "xxl": 32, "huge": 48}
const RADIUS := 3
const FONT_SIZES := {
	"display": 56, "h1": 40, "h2": 28, "h3": 22, "lead": 18, "body": 16, "small": 13
}
const TOUCH_TARGET := 48

const DAY := {
	"name": "day",
	"surface": Color("#f3ead6"),
	"surface_alt": Color("#e6d9bb"),
	"ink": Color("#2b2620"),
	"ink_muted": Color("#6b6152"),
	"line": Color("#b39253"),
	"accent": Color("#6b4f8f"),
	"accent_ink": Color("#fbf7ee"),
	"mana": Color("#3f7f9a"),
	"focus": Color("#c79a3c"),
	"scrim": Color("#2b262073"),
	"danger": Color("#c4553f"),
	"success": Color("#6f9f5e"),
	"warning": Color("#d0a33a"),
}

const NIGHT := {
	"name": "night",
	"surface": Color("#1c2431"),
	"surface_alt": Color("#141b26"),
	"ink": Color("#e7ebf2"),
	"ink_muted": Color("#93a0b7"),
	"line": Color("#c9d6f099"),
	"accent": Color("#a58ad6"),
	"accent_ink": Color("#141b26"),
	"mana": Color("#a9c4ff"),
	"focus": Color("#a9c4ff"),
	"scrim": Color("#05080d99"),
	"danger": Color("#e07a63"),
	"success": Color("#8cc47a"),
	"warning": Color("#e2b85a"),
}

const RARITY := {
	"common": Color("#9a968c"),
	"uncommon": Color("#6f9f5e"),
	"rare": Color("#4f84b8"),
	"epic": Color("#8a66bf"),
	"legendary": Color("#c79a3c"),
}

const TEXT_SCALES := [0.9, 1.0, 1.15, 1.3]

## CSS pixels per logical UI pixel, set by the root when the window resizes.
## Below 1 on phones, where the UI is shrunk to fit a minimum logical height.
static var css_per_logical := 1.0


## Logical size that shows as at least `css` CSS pixels on screen.
static func at_least_css(logical: float, css: float = TOUCH_TARGET) -> float:
	return maxf(logical, ceilf(css / maxf(css_per_logical, 0.01)))
