#!/usr/bin/env bash
# Aubelin NPCs, lot 2 (2026-11-06, cap 2.20 USD, ledger art/source/LOT_2026-11-06_npcs_rig.md): Meshy rig and
# clips on the static Tripo NPCs of lot 1. FAL_KEY from the environment (never printed). The rig step costs
# 0.20 + 0.12 per clip: one call at a time, write the ledger row first, look at the deformation sheet.
#   tools/fal/npcs_rig.sh <step>   (steps in the usage line at the bottom)
# Meshy library ids: 243 Idle_3 (calm idle, as Fern and Morvaine), 313 Talk_with_Hands_Open (Odile, Maëlle).
# Outputs: _0 rig (rest), then one GLB per clip at _8, _10, ... in the order of animation_action_ids.
set -euo pipefail
cd "$(dirname "$0")/../.."
FAL=/root/.claude/plugins/cache/video-to-game/video-to-game/1.0.0/skills/video-to-game/scripts/fal_asset.py
OUT=art/source/npcs/rig
B="blender -b --factory-startup"
NPCS="odile bastien maelle rosalie tobias ysaline"
TALKERS="odile maelle"
declare -A HEIGHT=([odile]=1.58 [bastien]=1.82 [maelle]=1.68 [rosalie]=1.62 [tobias]=1.76 [ysaline]=1.65)
# arms modelled bent around a prop stay in their modelled pose (Meshy's clips assume a hanging arm)
declare -A FREEZE=([odile]=LeftShoulder,LeftArm,LeftForeArm,LeftHand [ysaline]=LeftShoulder,LeftArm,LeftForeArm,LeftHand)

case "${1:-}" in
input)  # static GLB of lot 1 -> rig input with a JPEG texture (no fal call). Run on the STATIC models
	#       (commit 092ebf7): `build` overwrites assets/models/npcs/<npc>.glb with the rigged ones
	for n in $NPCS; do
		$B -P tools/blender/glb_reexport.py -- "assets/models/npcs/$n.glb" "$OUT/${n}_rig_in.glb" | grep @@REPORT
	done ;;
rig)    # Meshy rigging/multi-animation on one NPC (0.32 USD, 0.44 with talk): npcs_rig.sh rig <npc>
	n=$2
	ids='[243]'
	[[ " $TALKERS " == *" $n "* ]] && ids='[243,313]'
	python3 "$FAL" fal-ai/meshy/rigging/multi-animation -o "$OUT/$n" --name "${n}_rig" \
		--file model_url="$OUT/${n}_rig_in.glb" --arg animation_action_ids="$ids" --arg height_meters="${HEIGHT[$n]}" ;;
build)  # rigged GLBs -> assets/models/npcs/<npc>.glb (clips idle, talk), same paths as lot 1
	for n in $NPCS; do
		talk=()
		[[ " $TALKERS " == *" $n "* ]] && talk=(--clip "talk=$OUT/$n/${n}_rig_10.glb")
		$B -P tools/blender/build_npc_rigged.py -- "$n" --rig "$OUT/$n/${n}_rig_0.glb" \
			--clip "idle=$OUT/$n/${n}_rig_8.glb" "${talk[@]}" --albedo "art/source/npcs/tex/${n}_albedo.png" \
			--freeze "${FREEZE[$n]:-}" | grep @@REPORT
	done ;;
qa)     # deformation sheets: 6 frames of each clip, front and side -> art/source/npcs/qa_<npc>_anim.jpg
	for n in $NPCS; do
		tmp=$(mktemp -d)
		clips=idle
		[[ " $TALKERS " == *" $n "* ]] && clips=idle,talk
		for v in front side; do
			man=$($B -P tools/blender/render_pose_strip.py -- "assets/models/npcs/$n.glb" "$tmp/$v/x.png" \
				--clips $clips --frames 6 --view $v --front=-Y --res 320 2>/dev/null | grep @@MANIFEST | cut -c13-)
			python3 tools/blender/compose_strip.py "$man" "$tmp/$v.png" >/dev/null
		done
		python3 -c "from PIL import Image
a = Image.open('$tmp/front.png'); b = Image.open('$tmp/side.png')
c = Image.new('RGB', (max(a.width, b.width), a.height + b.height)); c.paste(a, (0, 0)); c.paste(b, (0, a.height))
c.save('art/source/npcs/qa_${n}_anim.jpg', quality=85)"
		rm -rf "$tmp"
	done ;;
*) echo "usage: $0 input|rig <npc>|build|qa"; exit 1 ;;
esac
