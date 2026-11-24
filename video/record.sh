#!/usr/bin/env bash
# Record the demo video from scratch, against the live workshop stack.
#
#   EVIDENCE_VIDEO_HOME=<path to the evidence-video toolkit> video/record.sh
#
# It resets the workshop, replays the week act by act, records every take while the real
# product does the thing, adds cards, subtitles and narration, and joins the takes into
# video/out/tyk-ai-studio-workshop-demo.mp4.
#
#   ONLY="07-guardrails-proof" NO_RESET=1 video/record.sh    re-record some takes in place
#
# Needs: the workshop's own prerequisites, ffmpeg, python3 with Pillow, node, and
# `npm i` run once in video/ (Playwright). Narration uses the macOS `say` voice.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
TOOLKIT="${EVIDENCE_VIDEO_HOME:?set EVIDENCE_VIDEO_HOME to the evidence-video toolkit folder}"
[ -f "$TOOLKIT/make_video.py" ] || { echo "no make_video.py in $TOOLKIT"; exit 1; }
set -a; . ./.env; set +a
export SAY_VOICE="${SAY_VOICE:-Daniel}"

if [ -z "${NO_RESET:-}" ]; then
  ./workshop reset >/dev/null 2>&1 || true
  ./workshop up
fi
python3 video/storyboard.py
mkdir -p video/out video/work/logs

for dir in video/work/takes/*/; do
  take="$(basename "$dir")"
  if [ -n "${ONLY:-}" ] && ! printf ' %s ' "$ONLY" | grep -q " $take "; then continue; fi
  echo "=== $take"
  if [ -f "$dir/prep.sh" ]; then bash "$dir/prep.sh" > "video/work/logs/$take.prep.log" 2>&1 || { tail -20 "video/work/logs/$take.prep.log"; exit 1; }; fi
  if [ -f "$dir/scene.json" ]; then
    python3 video/termcast.py "$dir/scene.json" "$dir"
  else
    (cd video && node "$TOOLKIT/record-web.mjs" "$ROOT/$dir/steps.json" "$ROOT/$dir")
  fi
  if [ -f "$dir/after.sh" ]; then bash "$dir/after.sh" > "video/work/logs/$take.after.log" 2>&1 || { tail -20 "video/work/logs/$take.after.log"; exit 1; }; fi
  python3 "$TOOLKIT/make_video.py" build "$dir" > "video/work/logs/$take.build.log" 2>&1 || { tail -20 "video/work/logs/$take.build.log"; exit 1; }
  grep -h "WARN" "$dir/out/fit.log" 2>/dev/null || true
done

: > video/work/concat.txt
for dir in video/work/takes/*/; do
  [ -f "$dir/out/final.mp4" ] && printf "file '%s'\n" "$ROOT/${dir}out/final.mp4" >> video/work/concat.txt
done
ffmpeg -y -loglevel error -f concat -safe 0 -i video/work/concat.txt \
  -c:v libx264 -preset medium -crf 23 -pix_fmt yuv420p -c:a aac -b:a 112k -ar 44100 -movflags +faststart \
  video/out/tyk-ai-studio-workshop-demo.mp4
echo "wrote video/out/tyk-ai-studio-workshop-demo.mp4 ($(du -h video/out/tyk-ai-studio-workshop-demo.mp4 | cut -f1))"
