#!/usr/bin/env bash
# Milestone 3 enemies (see art/source/enemies/AB_TEST.md). FAL_KEY from the environment (never printed).
# fal steps cost money: run them one at a time and look at each result before the next.
#   tools/fal/enemies.sh concept|views|cutout|ab-birch|ab-wolf-meshy|ab-wolf-tripo|build|qa|shots
# concept/views/cutout/ab-birch ran on 2026-11-06 (art/source/enemies/fal_log.json).
# ab-wolf-* could NOT run: the fal account balance was exhausted (HTTP 403 "User is locked") right
# after ab-birch. Until they run, build makes the four enemies procedurally in Blender (no fal).
set -euo pipefail
cd "$(dirname "$0")/../.."
FAL=/root/.claude/plugins/cache/video-to-game/video-to-game/1.0.0/skills/video-to-game/scripts/fal_asset.py
OUT=art/source/enemies
B="blender -b --factory-startup"

case "${1:-}" in
concept)  # side view of the mist wolf, flat colours, our direction frames as style refs (~0.15 USD)
	python3 "$FAL" fal-ai/nano-banana-pro/edit -o "$OUT" --name mist_wolf_concept \
		--file image_urls=art/concepts/directions/A_world.jpg --file image_urls=art/concepts/directions/B_combat.jpg \
		--arg aspect_ratio=4:3 --arg resolution=2K --arg output_format=png \
		--arg prompt="$(cat "$OUT/prompts/mist_wolf_concept.txt")" ;;
views)    # front + back from our side concept only (~0.15 USD)
	python3 "$FAL" fal-ai/nano-banana-pro/edit -o "$OUT" --name mist_wolf_views \
		--file image_urls="$OUT/mist_wolf_concept.png" --arg aspect_ratio=16:9 --arg resolution=2K \
		--arg output_format=png --arg prompt="$(cat "$OUT/prompts/mist_wolf_views.txt")" ;;
cutout)   # local cut-outs (no fal call) + mirrored right view
	python3 tools/fal/cutout_views.py "$OUT/mist_wolf_concept.png" "$OUT/mist_wolf_views.png" "$OUT" \
		mist_wolf side,front,back
	python3 -c "from PIL import Image, ImageOps; ImageOps.mirror(Image.open('$OUT/mist_wolf_side_cut.png')).save('$OUT/mist_wolf_right_cut.png')" ;;
ab-birch) # Tripo side of the vegetation A/B (Meshy side: art/source/env/raw/birch_a, same image) (~0.4 USD)
	python3 "$FAL" tripo3d/h3.1/image-to-3d -o "$OUT/raw/ab_birch_a" --name birch_a_tripo \
		--file image_url=art/source/env/cut/birch_a.png --arg pbr=false --arg texture=true \
		--arg texture_quality=detailed --arg geometry_quality=standard --arg face_limit=8000 ;;
ab-wolf-meshy)  # creature A/B, Meshy side (~1.2 USD). Views order: front, left, back, right
	python3 "$FAL" meshy/v7.1/multi-image-to-3d -o "$OUT/raw/mist_wolf_meshy" --name mist_wolf_meshy \
		--file image_urls="$OUT/mist_wolf_front_cut.png" --file image_urls="$OUT/mist_wolf_side_cut.png" \
		--file image_urls="$OUT/mist_wolf_back_cut.png" --file image_urls="$OUT/mist_wolf_right_cut.png" \
		--arg enable_pbr=false --arg should_texture=true --arg target_polycount=15000 --arg topology=triangle \
		--arg symmetry_mode=auto \
		--arg texture_prompt="stylized anime game creature, pure flat unshaded base colors, no baked shadows, no ambient occlusion, no highlights, no gradients; blue-grey wolf fur, pale grey-blue belly chest and legs, darker slate spine stripe, pale ice-blue eyes, dark nose and claws" ;;
ab-wolf-tripo)  # creature A/B, Tripo side (~0.4 USD), same four views
	python3 "$FAL" tripo3d/h3.1/multiview-to-3d -o "$OUT/raw/mist_wolf_tripo" --name mist_wolf_tripo \
		--file image_urls="$OUT/mist_wolf_front_cut.png" --file image_urls="$OUT/mist_wolf_side_cut.png" \
		--file image_urls="$OUT/mist_wolf_back_cut.png" --file image_urls="$OUT/mist_wolf_right_cut.png" \
		--arg pbr=false --arg texture=true --arg texture_quality=detailed --arg geometry_quality=standard \
		--arg face_limit=15000 ;;
build)    # procedural enemies (no fal): GLB + .blend + palette
	$B -P tools/blender/build_enemies.py -- mist_wolf wandering_lantern stone_sentinel morvaine | grep @@REPORT ;;
qa)       # Blender turnaround + pose strips -> art/source/enemies/qa_<id>_{turnaround,poses}.jpg
	tmp=$(mktemp -d)
	for e in mist_wolf wandering_lantern stone_sentinel morvaine; do
		g=assets/models/enemies/$e/$e.glb
		$B -P tools/blender/render_turnaround.py -- "$g" "$tmp/$e" --res 500 >/dev/null
		python3 tools/blender/compose_sheet.py "$tmp/$e.png" "$tmp/$e"/qa_front.png "$tmp/$e"/qa_side.png \
			"$tmp/$e"/qa_back.png "$tmp/$e"/qa_three_quarter_top.png
		clips=idle,run,attack,cast,hit,death; [ "$e" = morvaine ] && clips=$clips,phase
		man=$($B -P tools/blender/render_pose_strip.py -- "$g" "$tmp/strip_$e/x.png" --clips $clips --frames 6 \
			--view side --res 240 | grep @@MANIFEST | cut -c13-)
		python3 tools/blender/compose_strip.py "$man" "$tmp/poses_$e.png"
		python3 -c "from PIL import Image; Image.open('$tmp/$e.png').convert('RGB').save('$OUT/qa_${e}_turnaround.jpg', quality=85); Image.open('$tmp/poses_$e.png').convert('RGB').save('$OUT/qa_${e}_poses.jpg', quality=85)"
	done ;;
shots)    # gameplay-camera captures in the Whispering Wood (needs a GL driver)
	xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 \
		res://game/world/prototype/enemy_preview.tscn -- --shots ;;
*) echo "usage: $0 concept|views|cutout|ab-birch|ab-wolf-meshy|ab-wolf-tripo|build|qa|shots"; exit 1 ;;
esac
