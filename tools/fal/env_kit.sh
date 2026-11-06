#!/usr/bin/env bash
# Environment kit for Val d'Aubelin: concept sheets -> local split -> image-to-3D -> Blender -> GLB.
# Reproduces the calls logged in art/source/env/fal_log.json (FAL_KEY from the environment, never printed).
#   tools/fal/env_kit.sh sheets|split|mesh <name>...|build
set -euo pipefail
cd "$(dirname "$0")/../.."
FAL=/root/.claude/plugins/cache/video-to-game/video-to-game/1.0.0/skills/video-to-game/scripts/fal_asset.py
OUT=art/source/env

polycount() { case "$1" in house_*) echo 12000 ;; bridge|stall|well|cart|birch_*) echo 8000 ;; *) echo 5000 ;; esac; }

case "${1:-}" in
sheets)   # fal-ai/nano-banana-pro text-to-image (0.15 USD each). The /edit endpoint with A_world.jpg as
	      # reference pasted the objects INTO the reference scene (sheet_*.png, unusable), so style is in words.
	for s in houses props nature; do
		python3 "$FAL" fal-ai/nano-banana-pro -o "$OUT" --name "sheet2_$s" --arg aspect_ratio=16:9 \
			--arg resolution=2K --arg output_format=png --arg prompt="$(cat "$OUT/prompts/sheet_${s}_t2i.txt")"
	done ;;
split)    # local background removal (flat grey), no fal call
	python3 tools/fal/split_sheet.py "$OUT/sheet2_houses.png" "$OUT/cut" house_a house_b house_c
	python3 tools/fal/split_sheet.py "$OUT/sheet2_props.png" "$OUT/cut" well fence stall cart lantern barrels bridge
	python3 tools/fal/split_sheet.py "$OUT/sheet2_nature.png" "$OUT/cut" birch_a birch_b bush rock_a rock_b ;;
mesh)     # meshy/v7.1/image-to-3d, textured, no PBR (0.80 + 0.40 USD each); one raw dir per object
	shift
	for n in "$@"; do
		python3 "$FAL" meshy/v7.1/image-to-3d -o "$OUT/raw/$n" --name "${n}_meshy" --file image_url="$OUT/cut/$n.png" \
			--arg enable_pbr=false --arg should_texture=true --arg topology=triangle \
			--arg target_polycount="$(polycount "$n")" --arg symmetry_mode=auto
	done ;;
build)
	blender -b --factory-startup -P tools/blender/build_env_kit.py -- "$OUT/raw" assets/environment ;;
*) echo "usage: $0 sheets|split|mesh <name>...|build"; exit 1 ;;
esac
# Other steps (see art/source/env/fal_log.json for exact prompts and arguments):
#   ground textures, grass cards, backdrop: fal-ai/nano-banana-pro, prompts art/source/env/prompts/tex_*.txt,
#     grass_cards.txt, backdrop.txt, outputs in art/source/env/gen/
#   region map: fal-ai/nano-banana-pro/edit + art/concepts/keyart/title_day.jpg, prompts/map.txt
#   birch_b and bush retried with tripo3d/h3.1/image-to-3d (Meshy made them paper-thin), raw_tripo/
#   post-process: python3 tools/fal/process_env_textures.py props|ground|cards|backdrop|map
#   card canopies (birch_*, bush, fruit_tree; no fal): python3 tools/blender/build_foliage.py atlas, then
#     blender -b --factory-startup -P tools/blender/build_foliage.py -- assets/environment
#   doorstep / flower_bed (no fal): python3 tools/blender/build_village_props.py atlas, then
#     blender -b --factory-startup -P tools/blender/build_village_props.py -- assets/environment
#   stall awning stripes: blender -b --factory-startup -P tools/blender/repaint_awning.py -- assets/environment/props/stall.glb
#   (see art/source/env/POLISH_M3.md; set meshes/generate_lods=false in the .import of card meshes)
#   scenes: xvfb-run -a godot --path . --rendering-driver opengl3 -s res://game/world/prototype/build_locations.gd
#     (a GL driver is required: the headless dummy renderer drops MultiMesh buffers)
