#!/usr/bin/env bash
# Aubelin NPCs, lot 1 (2026-11-06, cap 5 USD, ledger art/source/LOT_2026-11-06_npcs.md). FAL_KEY from the
# environment (never printed). fal steps cost money: one at a time, write the ledger row first, look at the result.
#   tools/fal/npcs.sh <step>   (steps in the usage line at the bottom)
# Only image inputs: our portraits (assets/textures/portraits/npc_{bastien,maelle,aubelin_merchant}.webp).
set -euo pipefail
cd "$(dirname "$0")/../.."
FAL=/root/.claude/plugins/cache/video-to-game/video-to-game/1.0.0/skills/video-to-game/scripts/fal_asset.py
OUT=art/source/npcs
B="blender -b --factory-startup"
NPCS="odile bastien maelle rosalie tobias ysaline"
declare -A HEIGHT=([odile]=1.58 [bastien]=1.82 [maelle]=1.68 [rosalie]=1.62 [tobias]=1.76 [ysaline]=1.65)
declare -A SEED=([odile]=101 [bastien]=102 [maelle]=103 [rosalie]=104 [tobias]=105 [ysaline]=106)

case "${1:-}" in
drafts)  # flux/schnell text-only drafts of the three new NPCs (~0.003 USD each)
	style=$(grep '^STYLE:' "$OUT/prompts/drafts.txt" | cut -d' ' -f2-)
	for n in odile tobias ysaline; do
		seed=$((81 + $(echo "odile tobias ysaline" | tr ' ' '\n' | grep -n "^$n$" | cut -d: -f1) - 1))
		python3 "$FAL" fal-ai/flux/schnell -o "$OUT/drafts" --name "npc_${n}_draft" --arg image_size=portrait_4_3 \
			--arg num_inference_steps=4 --arg seed=$seed --arg num_images=1 \
			--arg prompt="$style $(grep "^$n:" "$OUT/prompts/drafts.txt" | cut -d' ' -f2-)"
	done ;;
sheet)   # the six villagers in one row, our three portraits as identity/style refs (~0.15 USD)
	for p in bastien maelle aubelin_merchant; do
		python3 -c "from PIL import Image; Image.open('assets/textures/portraits/npc_$p.webp').convert('RGB').save('$OUT/raw/ref_$p.png')"
	done
	python3 "$FAL" fal-ai/nano-banana-pro/edit -o "$OUT" --name npc_sheet --file image_urls="$OUT/raw/ref_bastien.png" \
		--file image_urls="$OUT/raw/ref_maelle.png" --file image_urls="$OUT/raw/ref_aubelin_merchant.png" \
		--arg aspect_ratio=21:9 --arg resolution=2K --arg output_format=png --arg seed=91 \
		--arg prompt="$(cat "$OUT/prompts/npc_sheet.txt")" ;;
cut)     # local cut-outs, one per column (no fal call)
	python3 tools/fal/cutout_grid.py "$OUT/npc_sheet.png" "$OUT/cut" --grid 6x1 $NPCS ;;
tripo)   # Tripo H3.1 image-to-3d on one cut-out (~0.4 USD): npcs.sh tripo <npc>
	n=$2
	python3 "$FAL" tripo3d/h3.1/image-to-3d -o "$OUT/raw/$n" --name "${n}_tripo" --file image_url="$OUT/cut/${n}_cut.png" \
		--arg pbr=false --arg texture=true --arg texture_quality=detailed --arg geometry_quality=standard \
		--arg face_limit=15000 --arg model_seed=${SEED[$n]} --arg texture_seed=${SEED[$n]} ;;
albedo)  # flat 512 px albedos from the Tripo textures (no fal call)
	tmp=$(mktemp -d)
	py=$'import json,struct,sys\nb=open(sys.argv[1],"rb").read();n=struct.unpack_from("<I",b,12)[0];j=json.loads(b[20:20+n]);bv=j["bufferViews"][j["images"][0]["bufferView"]];o=28+n+bv.get("byteOffset",0);open(sys.argv[2],"wb").write(b[o:o+bv["byteLength"]])'
	mkdir -p "$OUT/tex"
	for n in $NPCS; do
		python3 -c "$py" "$OUT/raw/$n/${n}_tripo_0.glb" "$tmp/$n.img"
		python3 tools/blender/flatten_albedo.py "$tmp/$n.img" "$OUT/tex/${n}_albedo.png" --k 12 --size 512 \
			--dark-target '' --skin-shift 1,1,1 --keep 0.2 >/dev/null
	done ;;
build)   # static GLBs -> assets/models/npcs/<npc>.glb, and the notice board (hand-built, no fal)
	for n in $NPCS; do
		$B -P tools/blender/build_npcs.py -- "$n" --mesh "$OUT/raw/$n/${n}_tripo_0.glb" \
			--albedo "$OUT/tex/${n}_albedo.png" --height "${HEIGHT[$n]}" | grep @@REPORT
	done
	$B -P tools/blender/build_notice_board.py -- assets/models/props/notice_board.glb | grep @@REPORT ;;
qa)      # blender-asset-qa check + review sheet per model -> art/source/npcs/qa_<id>.jpg
	tmp=$(mktemp -d)
	for n in $NPCS notice_board; do
		g=assets/models/npcs/$n.glb; front=-Y
		[ "$n" = notice_board ] && g=assets/models/props/notice_board.glb
		$B -P tools/blender/qa_glb.py -- "$g" | grep @@QA | cut -c7- | python3 -c \
			"import json,sys; r=json.load(sys.stdin); print('$n', 'pass' if r['pass'] else 'FAIL', r['errors'], r['warnings'])"
		$B -P tools/blender/render_turnaround.py -- "$g" "$tmp/$n" --res 500 --front=$front >/dev/null
		$B -P tools/blender/inspect_glb.py -- "$g" "$tmp/${n}_wire.png" wire front three_quarter >/dev/null
		python3 tools/blender/compose_sheet.py "$tmp/$n.png" "$tmp/$n"/qa_front.png "$tmp/$n"/qa_side.png \
			"$tmp/$n"/qa_back.png "$tmp/$n"/qa_three_quarter_top.png >/dev/null
		python3 -c "from PIL import Image
a = Image.open('$tmp/$n.png').convert('RGB'); w = Image.open('$tmp/${n}_wire.png').convert('RGB')
w = w.resize((round(w.width * a.height / w.height), a.height)); c = Image.new('RGB', (a.width + w.width, a.height))
c.paste(a, (0, 0)); c.paste(w, (a.width, 0)); c.save('$OUT/qa_$n.jpg', quality=85)"
	done ;;
lineup)  # all NPCs next to Fern under the 11 m game camera (Blender, Workbench) -> art/source/npcs/lineup_11m.jpg (+ _6m)
	$B -P tools/blender/render_npc_lineup.py -- "$OUT/lineup_11m.png" assets/models/characters/fern/fern.glb \
		$(for n in $NPCS; do echo assets/models/npcs/$n.glb; done) assets/models/props/notice_board.glb
	for f in lineup_11m lineup_11m_6m; do
		python3 -c "from PIL import Image; Image.open('$OUT/$f.png').convert('RGB').save('$OUT/$f.jpg', quality=88)"
		rm "$OUT/$f.png"
	done ;;
*) echo "usage: $0 drafts|sheet|cut|tripo <npc>|albedo|build|qa|lineup"; exit 1 ;;
esac
