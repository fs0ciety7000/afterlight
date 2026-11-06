#!/usr/bin/env bash
# Fern v1 character pipeline (see art/source/fern_v1/PIPELINE_NOTES.md). Re-runs every step from the
# logged fal calls (art/source/fern_v1/fal_log.json). Needs FAL_KEY in the environment (never printed).
# fal steps cost money: run them one at a time and look at each result before the next.
#   tools/fal/fern_v1.sh concept|views|cutout|mesh|rig|rigidle|flatten|build|qa|shots|compare|all-local
# all-local = flatten + build + qa + shots + compare (no fal call).
set -euo pipefail
cd "$(dirname "$0")/../.."
FAL=/root/.claude/plugins/cache/video-to-game/video-to-game/1.0.0/skills/video-to-game/scripts/fal_asset.py
OUT=art/source/fern_v1
GLB=assets/models/characters/fern/fern.glb
B="blender -b --factory-startup"

step() {
case "$1" in
concept)  # front A-pose, flat colours, short bangs; our own direction frames as style refs (~0.15 USD)
	python3 "$FAL" fal-ai/nano-banana-pro/edit -o "$OUT" --name fern_v1_concept_front \
		--file image_urls=art/concepts/directions/A_world.jpg --file image_urls=art/concepts/directions/B_combat.jpg \
		--arg aspect_ratio=2:3 --arg resolution=2K --arg output_format=png \
		--arg prompt="$(cat "$OUT/prompt_concept_front.txt")" ;;
views)    # side + back from our front concept only (~0.15 USD)
	python3 "$FAL" fal-ai/nano-banana-pro/edit -o "$OUT" --name fern_v1_concept_views \
		--file image_urls="$OUT/fern_v1_concept_front.png" \
		--arg aspect_ratio=4:3 --arg resolution=2K --arg output_format=png \
		--arg prompt="$(cat "$OUT/prompt_concept_views.txt")" ;;
cutout)   # local flood-fill cutout of the flat grey backgrounds (no fal call)
	python3 tools/fal/cutout_views.py "$OUT/fern_v1_concept_front.png" "$OUT/fern_v1_concept_views.png" "$OUT" ;;
mesh)     # meshy v7.1 multi-image (front, side, back), textured, no PBR
	python3 "$FAL" meshy/v7.1/multi-image-to-3d -o "$OUT" --name fern_v1_meshy \
		--file image_urls="$OUT/fern_v1_front_cut.png" --file image_urls="$OUT/fern_v1_side_cut.png" \
		--file image_urls="$OUT/fern_v1_back_cut.png" \
		--arg pose_mode=a-pose --arg enable_pbr=false --arg should_texture=true --arg target_polycount=30000 \
		--arg topology=triangle --arg symmetry_mode=auto \
		--arg texture_prompt="stylized anime game character, pure flat unshaded base colors, no baked shadows, no ambient occlusion, no highlights, no gradients; violet hair, black coat, white dress, black boots, pale peach skin" ;;
rig)      # Idle(0) Walking_Woman(1) Run_02(14) Charged_Spell_Cast(125) mage_soell_cast(129,130,131)
	#        Hit_Reaction(178) dying_backwards(189) Victory_Cheer(59) -> outputs _8,_10,..,_26 in that order
	python3 "$FAL" fal-ai/meshy/rigging/multi-animation -o "$OUT" --name fern_v1_rig \
		--file model_url="$OUT/fern_v1_meshy_0.glb" \
		--arg animation_action_ids='[0,1,14,125,129,130,131,178,189,59]' --arg height_meters=1.6 ;;
rigidle)  # calmer idles: Idle_02(11) Idle_03(12) Idle_3(243) Idle_4(244) Idle_5(245) Idle_6(246) -> _8.._18
	python3 "$FAL" fal-ai/meshy/rigging/multi-animation -o "$OUT" --name fern_v1_rig_idle \
		--file model_url="$OUT/fern_v1_meshy_0.glb" \
		--arg animation_action_ids='[11,12,243,244,245,246]' --arg height_meters=1.6 ;;
flatten)  # base colour -> flat colour regions (k-means), eyes kept, coat lifted to #37323b
	python3 tools/blender/flatten_albedo.py "$OUT/fern_v1_meshy_7.png" "$OUT/fern_albedo.png" ;;
build)    # chosen clips: idle=Idle_3 (trimmed to 5 s), cast=mage_soell_cast, hit, death, victory (4 s)
	$B -P tools/blender/build_character_v1.py -- --rig "$OUT/fern_v1_rig_0.glb" \
		--clip idle="$OUT/fern_v1_rig_idle_12.glb:1:120" --clip walk="$OUT/fern_v1_rig_10.glb" \
		--clip run="$OUT/fern_v1_rig_12.glb" --clip cast="$OUT/fern_v1_rig_16.glb" \
		--clip hit="$OUT/fern_v1_rig_22.glb" --clip death="$OUT/fern_v1_rig_24.glb" \
		--clip victory="$OUT/fern_v1_rig_26.glb:1:100" \
		--albedo "$OUT/fern_albedo.png" --out "$GLB" --blend "$OUT/fern_v1.blend" | grep "@@REPORT@@" ;;
qa)       # Blender turnaround (rest) + pose strips (no springs: Blender shows the baked motion only)
	tmp=$(mktemp -d)
	$B -P tools/blender/render_turnaround.py -- "$GLB" "$tmp" >/dev/null
	python3 tools/blender/compose_sheet.py "$OUT/qa_turnaround.png" "$tmp"/qa_front.png "$tmp"/qa_side.png \
		"$tmp"/qa_back.png "$tmp"/qa_three_quarter_top.png
	man=$($B -P tools/blender/render_pose_strip.py -- "$GLB" "$tmp/strip/x.png" --clips walk,run,cast,hit,death,victory \
		--frames 6 --view side --res 300 | grep @@MANIFEST | cut -c13-)
	python3 tools/blender/compose_strip.py "$man" "$OUT/qa_poses.png"
	for f in qa_turnaround qa_poses; do python3 -c "from PIL import Image; Image.open('$OUT/$f.png').convert('RGB').save('$OUT/$f.jpg', quality=88)"; rm "$OUT/$f.png"; done ;;
shots)    # real Godot frames (Compatibility renderer, software GL under xvfb)
	godot --headless --path . --import >/dev/null 2>&1 || true
	xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
		res://game/world/prototype/fern_preview.tscn -- --shots --shots-dir=res://$OUT/ ;;
compare)  # v0 (art/source/fern) vs v1 at the same gameplay camera
	python3 tools/fal/compare_shots.py art/source/fern "$OUT" "$OUT/compare_v0_v1.jpg" ;;
all-local) for s in flatten build qa shots compare; do step "$s"; done ;;
*) echo "usage: $0 concept|views|cutout|mesh|rig|rigidle|flatten|build|qa|shots|compare|all-local"; exit 1 ;;
esac
}
step "${1:-}"
