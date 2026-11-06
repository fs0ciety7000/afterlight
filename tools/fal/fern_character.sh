#!/usr/bin/env bash
# Character pipeline trial (Fern): concept -> cutout -> image-to-3D -> rig + clips -> Blender -> Godot.
# Reproduces the exact calls logged in art/source/fern/fal_log.json. Needs FAL_KEY in the environment
# (never printed). Each step costs money: run the steps one at a time and look at each result.
#   tools/fal/fern_character.sh concept|cutout|mesh|rig|build|qa|shots
set -euo pipefail
cd "$(dirname "$0")/../.."
FAL=/root/.claude/plugins/cache/video-to-game/video-to-game/1.0.0/skills/video-to-game/scripts/fal_asset.py
OUT=art/source/fern
GLB=assets/models/characters/fern/fern.glb

case "${1:-}" in
concept)  # fal-ai/nano-banana-pro/edit, our own direction frames as style refs (~0.15 USD)
	python3 "$FAL" fal-ai/nano-banana-pro/edit -o "$OUT" --name fern_concept_v1 \
		--file image_urls=art/concepts/directions/A_world.jpg --file image_urls=art/concepts/directions/B_combat.jpg \
		--arg aspect_ratio=2:3 --arg resolution=2K --arg output_format=png \
		--arg prompt="$(cat "$OUT/prompt_concept.txt")" ;;
cutout)   # fal-ai/birefnet/v2 (~0.01 USD)
	python3 "$FAL" fal-ai/birefnet/v2 -o "$OUT" --name fern_cutout --file image_url="$OUT/fern_concept_v1.png" \
		--arg model="General Use (Heavy)" --arg operating_resolution=2048x2048 ;;
mesh)     # meshy/v7.1/image-to-3d, textured, no PBR (1.20 USD)
	python3 "$FAL" meshy/v7.1/image-to-3d -o "$OUT" --name fern_meshy --file image_url="$OUT/fern_cutout.png" \
		--arg pose_mode=a-pose --arg enable_pbr=false --arg should_texture=true \
		--arg target_polycount=30000 --arg topology=triangle --arg symmetry_mode=auto ;;
rig)      # fal-ai/meshy/rigging/multi-animation: Idle(0) Walking_Woman(1) Run_02(14) Charged_Spell_Cast(125)
	python3 "$FAL" fal-ai/meshy/rigging/multi-animation -o "$OUT" --name fern_rig \
		--file model_url="$OUT/fern_meshy_0.glb" --arg animation_action_ids='[0,1,14,125]' --arg height_meters=1.6 ;;
build)    # output index -> clip: _0 rig, _8 idle, _10 walk, _12 run, _14 cast (see PIPELINE_NOTES.md)
	blender -b --factory-startup -P tools/blender/build_character.py -- --rig "$OUT/fern_rig_0.glb" \
		--clip idle="$OUT/fern_rig_8.glb" --clip walk="$OUT/fern_rig_10.glb" \
		--clip run="$OUT/fern_rig_12.glb" --clip cast="$OUT/fern_rig_14.glb" \
		--out "$GLB" --blend "$OUT/fern.blend" --target-tris 22000 ;;
qa)
	tmp=$(mktemp -d)
	blender -b --factory-startup -P tools/blender/render_turnaround.py -- "$GLB" "$tmp"
	python3 tools/blender/compose_sheet.py "$OUT/qa_turnaround.png" "$tmp"/qa_front.png "$tmp"/qa_side.png \
		"$tmp"/qa_back.png "$tmp"/qa_three_quarter_top.png ;;
shots)    # needs xvfb (apt-get install -y xvfb) and libEGL/mesa for software GL
	godot --headless --path . --import >/dev/null 2>&1 || true
	xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
		res://game/world/prototype/fern_preview.tscn -- --shots ;;
*) echo "usage: $0 concept|cutout|mesh|rig|build|qa|shots"; exit 1 ;;
esac
