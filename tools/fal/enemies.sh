#!/usr/bin/env bash
# Milestone 3 enemies (see art/source/enemies/AB_TEST.md). FAL_KEY from the environment (never printed).
# fal steps cost money: run them one at a time and look at each result before the next.
#   tools/fal/enemies.sh <step>   (steps listed in the usage line at the bottom)
# concept/views/cutout/ab-birch ran on 2026-11-06; the account then ran dry and the four enemies were
# built procedurally (build-placeholders). Generated lot (same day, cap 5 USD, art/source/enemies/BUDGET.md):
#   gen-wolf, gen-sentinel-concept, gen-sentinel, gen-morvaine-concept, gen-morvaine, gen-morvaine-rig (fal)
#   then cutout-gen, albedo, build-gen (local). wandering_lantern stays procedural (build).
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
gen-wolf) # mist wolf from the four existing views, Tripo multiview (~0.4 USD)
	python3 "$FAL" tripo3d/h3.1/multiview-to-3d -o "$OUT/raw/mist_wolf_tripo" --name mist_wolf_tripo \
		--file image_urls="$OUT/mist_wolf_front_cut.png" --file image_urls="$OUT/mist_wolf_side_cut.png" \
		--file image_urls="$OUT/mist_wolf_back_cut.png" --file image_urls="$OUT/mist_wolf_right_cut.png" \
		--arg pbr=false --arg texture=true --arg texture_quality=detailed --arg geometry_quality=standard \
		--arg face_limit=15000 --arg model_seed=11 --arg texture_seed=11 ;;
gen-sentinel-concept)  # front 3/4 concept, our direction frames as style refs (~0.15 USD)
	python3 "$FAL" fal-ai/nano-banana-pro/edit -o "$OUT" --name stone_sentinel_concept \
		--file image_urls=art/concepts/directions/A_world.jpg --file image_urls=art/concepts/directions/B_combat.jpg \
		--arg aspect_ratio=3:4 --arg resolution=2K --arg output_format=png --arg seed=21 \
		--arg prompt="$(cat "$OUT/prompts/stone_sentinel_concept.txt")" ;;
gen-sentinel)  # Tripo image-to-3d on the cut-out concept (~0.4 USD)
	python3 "$FAL" tripo3d/h3.1/image-to-3d -o "$OUT/raw/stone_sentinel_tripo" --name stone_sentinel_tripo \
		--file image_url="$OUT/stone_sentinel_front34_cut.png" --arg pbr=false --arg texture=true \
		--arg texture_quality=detailed --arg geometry_quality=standard --arg face_limit=15000 \
		--arg model_seed=21 --arg texture_seed=21 ;;
gen-morvaine-concept)  # front / side / back sheet, A-pose (~0.15 USD)
	python3 "$FAL" fal-ai/nano-banana-pro/edit -o "$OUT" --name morvaine_concept \
		--file image_urls=art/concepts/directions/A_world.jpg --file image_urls=art/concepts/directions/B_combat.jpg \
		--arg aspect_ratio=16:9 --arg resolution=2K --arg output_format=png --arg seed=31 \
		--arg prompt="$(cat "$OUT/prompts/morvaine_concept.txt")" ;;
gen-morvaine)  # Meshy multi-image, A-pose (~1.2 USD)
	python3 "$FAL" meshy/v7.1/multi-image-to-3d -o "$OUT/raw/morvaine_meshy" --name morvaine_meshy \
		--file image_urls="$OUT/morvaine_front_cut.png" --file image_urls="$OUT/morvaine_side_cut.png" \
		--file image_urls="$OUT/morvaine_back_cut.png" --arg pose_mode=a-pose --arg enable_pbr=false \
		--arg should_texture=true --arg target_polycount=30000 --arg topology=triangle --arg symmetry_mode=auto \
		--arg texture_prompt="stylized anime game character, pure flat unshaded base colors, no baked shadows, no ambient occlusion, no highlights, no gradients; ash-grey lavender skin, pale gold eyes, charcoal black hair, dark charcoal horns with ember orange tips, dark ash grey gown with thin ember orange seams and hem band, black shoes" ;;
gen-morvaine-rig)  # Meshy humanoid rig + 6 clips (0.2 + 6 x 0.12 USD): Idle_3, Walking_Woman,
	# Charged_Spell_Cast, mage_soell_cast, Hit_Reaction, dying_backwards -> rig_0, _8, _10, _12, _14, _16, _18
	python3 "$FAL" fal-ai/meshy/rigging/multi-animation -o "$OUT/raw/morvaine_rig" --name morvaine_rig \
		--file model_url="$OUT/raw/morvaine_meshy/morvaine_meshy_0.glb" \
		--arg animation_action_ids='[243,1,125,129,178,189]' --arg height_meters=1.9 ;;
gen-morvaine-rig2)  # better attack / cast / death (lot 2026-11-06, art/source/LOT_2026-11-06_assets.md, 0.56 USD):
	# mage_soell_cast_4(133) lunge throw, mage_soell_cast_8(137) raised channel,
	# Strangled_and_Fall_Forward(186) -> morvaine_rig2_0 (rig), _8, _10, _12
	python3 "$FAL" fal-ai/meshy/rigging/multi-animation -o "$OUT/raw/morvaine_rig" --name morvaine_rig2 \
		--file model_url="$OUT/raw/morvaine_meshy/morvaine_meshy_0.glb" \
		--arg animation_action_ids='[133,137,186]' --arg height_meters=1.9 ;;
cutout-gen)  # local cut-outs of the new concepts (no fal call)
	python3 tools/fal/cutout_sheet.py "$OUT/stone_sentinel_concept.png" "$OUT" stone_sentinel front34
	python3 tools/fal/cutout_sheet.py "$OUT/morvaine_concept.png" "$OUT" morvaine front,side,back ;;
albedo)   # flat albedos from the generated textures, then readability tweaks (no fal call)
	tmp=$(mktemp -d)
	py=$'import json,struct,sys\nb=open(sys.argv[1],"rb").read();n=struct.unpack_from("<I",b,12)[0];j=json.loads(b[20:20+n]);bv=j["bufferViews"][j["images"][0]["bufferView"]];o=28+n+bv.get("byteOffset",0);open(sys.argv[2],"wb").write(b[o:o+bv["byteLength"]])'
	python3 -c "$py" "$OUT/raw/mist_wolf_tripo/mist_wolf_tripo_0.glb" "$tmp/wolf.img"
	python3 -c "$py" "$OUT/raw/stone_sentinel_tripo/stone_sentinel_tripo_0.glb" "$tmp/sent.img"
	python3 -c "$py" "$OUT/raw/morvaine_rig/morvaine_rig_0.glb" "$tmp/morv.img"
	F="python3 tools/blender/flatten_albedo.py"
	$F "$tmp/wolf.img" "$OUT/mist_wolf_albedo.png" --k 8 --dark-target '' --skin-shift 1,1,1
	$F "$tmp/sent.img" "$OUT/stone_sentinel_albedo.png" --k 9 --dark-target '' --skin-shift 1,1,1
	$F "$tmp/morv.img" "$OUT/morvaine_albedo.png" --k 10 --dark-target '' --skin-shift 1,1,1
	python3 tools/fal/tune_albedo.py "$OUT/mist_wolf_albedo.png" "$OUT/mist_wolf_albedo.png" --gain 1.12
	python3 tools/fal/tune_albedo.py "$OUT/stone_sentinel_albedo.png" "$OUT/stone_sentinel_albedo.png" --glow '#a9e4ff'
	python3 tools/fal/tune_albedo.py "$OUT/morvaine_albedo.png" "$OUT/morvaine_albedo.png" --darken-grey 0.7 ;;
build-gen)  # generated meshes on the procedural skeletons / Meshy rig -> assets/models/enemies/<id>/<id>.glb
	$B -P tools/blender/build_enemies_gen.py -- mist_wolf --mesh "$OUT/raw/mist_wolf_tripo/mist_wolf_tripo_0.glb" \
		--albedo "$OUT/mist_wolf_albedo.png" | grep @@REPORT
	$B -P tools/blender/build_enemies_gen.py -- stone_sentinel \
		--mesh "$OUT/raw/stone_sentinel_tripo/stone_sentinel_tripo_0.glb" --albedo "$OUT/stone_sentinel_albedo.png" | grep @@REPORT
	R="$OUT/raw/morvaine_rig"
	$B -P tools/blender/build_character_v1.py -- --rig "$R/morvaine_rig_0.glb" \
		--clip idle="$R/morvaine_rig_8.glb:1:120" --clip run="$R/morvaine_rig_10.glb" --clip attack="$R/morvaine_rig2_8.glb" \
		--clip cast="$R/morvaine_rig2_10.glb" --clip hit="$R/morvaine_rig_16.glb" --clip death="$R/morvaine_rig2_12.glb:80:185" \
		--loop idle,run --in-place hit=0.15,attack=0.3,cast=0.3,death=0.5 --albedo "$OUT/morvaine_albedo.png" \
		--out assets/models/enemies/morvaine/morvaine.glb --blend "$OUT/morvaine_gen.blend" --target-tris 28000 \
		--height 1.9 --hand-scale 0.95 --no-staff --name Morvaine --class-mode robe | grep @@REPORT ;;
build)    # procedural wandering lantern (no fal): GLB + .blend + palette
	$B -P tools/blender/build_enemies.py -- wandering_lantern | grep @@REPORT ;;
build-placeholders)  # the procedural wolf / sentinel / Morvaine: OVERWRITES the generated GLBs
	$B -P tools/blender/build_enemies.py -- mist_wolf stone_sentinel morvaine | grep @@REPORT ;;
qa)       # Blender turnaround + pose strips -> art/source/enemies/qa_<id>_{turnaround,poses}.jpg
	tmp=$(mktemp -d)
	for e in mist_wolf wandering_lantern stone_sentinel morvaine; do
		g=assets/models/enemies/$e/$e.glb
		$B -P tools/blender/render_turnaround.py -- "$g" "$tmp/$e" --res 500 >/dev/null
		python3 tools/blender/compose_sheet.py "$tmp/$e.png" "$tmp/$e"/qa_front.png "$tmp/$e"/qa_side.png \
			"$tmp/$e"/qa_back.png "$tmp/$e"/qa_three_quarter_top.png
		clips=idle,run,attack,cast,hit,death
		man=$($B -P tools/blender/render_pose_strip.py -- "$g" "$tmp/strip_$e/x.png" --clips $clips --frames 6 \
			--view side --res 240 | grep @@MANIFEST | cut -c13-)
		python3 tools/blender/compose_strip.py "$man" "$tmp/poses_$e.png"
		python3 -c "from PIL import Image; Image.open('$tmp/$e.png').convert('RGB').save('$OUT/qa_${e}_turnaround.jpg', quality=85); Image.open('$tmp/poses_$e.png').convert('RGB').save('$OUT/qa_${e}_poses.jpg', quality=85)"
	done ;;
shots)    # gameplay-camera captures in the Whispering Wood (needs a GL driver)
	xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 \
		res://game/world/prototype/enemy_preview.tscn -- --shots ;;
compare)  # placeholder (placeholder_shot_*) vs generated (shot_*), same scene and camera
	python3 tools/fal/compare_pairs.py "$OUT/compare_placeholder_vs_generated.jpg" "Placeholder (procedural)" \
		"Generated (fal: Tripo / Meshy)" \
		"$OUT/placeholder_shot_idle_11m.jpg" "$OUT/shot_idle_11m.jpg" "$OUT/placeholder_shot_attack_11m.jpg" \
		"$OUT/shot_attack_11m.jpg" "$OUT/placeholder_shot_idle_6m.jpg" "$OUT/shot_idle_6m.jpg" \
		"$OUT/placeholder_shot_cast_6m.jpg" "$OUT/shot_cast_6m.jpg" ;;
*) echo "usage: $0 concept|views|cutout|ab-birch|ab-wolf-meshy|ab-wolf-tripo|gen-wolf|gen-sentinel-concept|gen-sentinel|gen-morvaine-concept|gen-morvaine|gen-morvaine-rig|gen-morvaine-rig2|cutout-gen|albedo|build-gen|build|build-placeholders|qa|shots|compare"; exit 1 ;;
esac
