#!/usr/bin/env bash
# Renders every VFX preview clip under xvfb, then builds MP4 clips and contact sheets.
#   tools/vfx_record.sh            all clips
#   tools/vfx_record.sh zoltraak   only clips whose name contains "zoltraak"
# Frames: art/source/vfx/frames/<clip>/ (git-ignored), clips: art/source/vfx/clips/<clip>.mp4,
# contact sheets: art/source/vfx/clips/<clip>_sheet.jpg, costs: art/source/vfx/perf.json.
set -euo pipefail
cd "$(dirname "$0")/.."
ONLY="${1:-}"
FRAMES=art/source/vfx/frames
CLIPS=art/source/vfx/clips
mkdir -p "$FRAMES" "$CLIPS"
if [ -n "$ONLY" ]; then
	rm -rf "$FRAMES"/*"$ONLY"*
else
	rm -rf "${FRAMES:?}"/*
fi
ARGS=(--record)
[ -n "$ONLY" ] && ARGS+=("--only=$ONLY")
# --fixed-fps 30: every frame advances the game clock by exactly 1/30 s, however slow the
# software renderer is, so the clips play at true speed.
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
	--resolution 1280x720 --fixed-fps 30 \
	res://game/world/prototype/vfx_preview.tscn -- "${ARGS[@]}"
for dir in "$FRAMES"/*/; do
	clip=$(basename "$dir")
	n=$(ls "$dir" | wc -l)
	[ "$n" -gt 0 ] || continue
	ffmpeg -loglevel error -y -framerate 30 -i "$dir/%04d.png" \
		-c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow "$CLIPS/$clip.mp4"
	# Contact sheet: 8 frames evenly spread over the clip, 4 x 2, half resolution.
	step=$(( n / 8 > 0 ? n / 8 : 1 ))
	ffmpeg -loglevel error -y -i "$dir/%04d.png" \
		-vf "select='not(mod(n\,$step))',scale=640:-1,tile=4x2:padding=4:color=0x0d1220" \
		-frames:v 1 -q:v 3 "$CLIPS/${clip}_sheet.jpg"
	echo "$CLIPS/$clip.mp4 ($n frames)"
done
