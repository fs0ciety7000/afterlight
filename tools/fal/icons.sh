#!/usr/bin/env bash
# Icon sheets (lot 2026-11-06, art/source/LOT_2026-11-06_assets.md). FAL_KEY from the environment (never printed).
# Each sheet is ONE generated image split locally into cells, then exported to assets/textures/icons/<id>.webp.
#   tools/fal/icons.sh drafts|spells|sheets|split|export
set -euo pipefail
cd "$(dirname "$0")/../.."
FAL=/root/.claude/plugins/cache/video-to-game/video-to-game/1.0.0/skills/video-to-game/scripts/fal_asset.py
OUT=art/source/icons
SPELLS="spell.zoltraak spell.mana_volley spell.defensive_barrier spell.afterlight passive.veiled_mana spell.mana_bolt"
EQUIP="item.birch_staff item.ashwood_staff item.traveler_hood item.sage_circlet item.wool_robe item.mage_robe
	item.cloth_gloves item.runed_gloves item.walking_boots item.pathfinder_boots item.copper_amulet item.moonstone_amulet"
RUNES="rune.ember rune.frost rune.storm rune.acuity rune.thrift rune.swiftness rune.echo rune.potency"
MISC="material.mana_dust material.rune_shard material.grimoire_page material.ashen_essence consumable.healing_draught
	consumable.mana_elixir artifact.cracked_hourglass artifact.pressed_flower artifact.traveler_compass artifact.ashen_bell"

case "${1:-}" in
drafts)  # cheap layout drafts (~0.003 USD each)
	n=6; for s in spells equipment runes misc; do
		python3 "$FAL" fal-ai/flux/schnell -o "$OUT/drafts" --name "icons_${s}_draft" --arg image_size=landscape_4_3 \
			--arg seed=$((50 + n)) --arg num_inference_steps=4 --arg prompt="$(cat "$OUT/prompts/$s.txt")"
		n=$((n + 1)); done ;;
spells)  # final spells sheet, text only (~0.15 USD)
	python3 "$FAL" fal-ai/nano-banana-pro -o "$OUT" --name icons_spells --arg aspect_ratio=3:2 --arg resolution=2K \
		--arg output_format=png --arg seed=60 --arg prompt="$(cat "$OUT/prompts/spells.txt")" ;;
sheets)  # the other sheets, our spells sheet as the only (style) reference (~0.15 USD each)
	for sa in equipment:4:3:61 runes:16:9:64 misc:21:9:65; do IFS=: read -r s a b seed <<<"$sa"
		python3 "$FAL" fal-ai/nano-banana-pro/edit -o "$OUT" --name "icons_$s" --file image_urls="$OUT/icons_spells.png" \
			--arg aspect_ratio="$a:$b" --arg resolution=2K --arg output_format=png --arg seed="$seed" \
			--arg prompt="$(cat "$OUT/prompts/$s.txt")"; done ;;
split)   # grid cells -> art/source/icons/cut/<id>.png (no fal call)
	S=tools/fal/split_sheet.py
	# shellcheck disable=SC2086
	{ python3 $S "$OUT/icons_spells.png" "$OUT/cut" --grid 3x2 $SPELLS
	  python3 $S "$OUT/icons_equipment.png" "$OUT/cut" --grid 4x3 $EQUIP
	  python3 $S "$OUT/icons_runes.png" "$OUT/cut" --grid 4x2 $RUNES
	  python3 $S "$OUT/icons_misc.png" "$OUT/cut" --grid 5x2 $MISC; } ;;
export)  # 128 px WebP (lossy q90 with alpha) -> assets/textures/icons/<id>.webp, plus a contact sheet
	python3 tools/fal/export_icons.py "$OUT/cut" assets/textures/icons 128 "$OUT/icons_contact.jpg" ;;
*) echo "usage: $0 drafts|spells|sheets|split|export"; exit 1 ;;
esac
