#!/bin/sh
# Measure the RENDERED dilla.wav with the exact same pipeline used on the
# reference canon: demucs htdemucs -> pure-node per-stem/mix analysis.
# Resumable: skips demucs if 4 stems exist, skips existing analysis JSONs.
# Laws: TRUTHFUL_STATUS, EXTERNAL_RESEARCH_IS_EVIDENCE_NOT_AUTHORITY.
set -u
DA="${DILLA_ANALYSIS_DIR:-/home/z/my-project/dilla-analysis}"
RA=$DA/render_analysis
WAV="${DILLA_RENDER_WAV:-/home/z/my-project/download/dilla-renders/dilla.wav}"
NODE=/usr/local/bin/node
[ -x "$NODE" ] || NODE=$(command -v node)
mkdir -p "$RA"

ST=$RA/htdemucs/dilla
if [ ! -f "$ST/drums.wav" ] || [ ! -f "$ST/bass.wav" ] || [ ! -f "$ST/other.wav" ] || [ ! -f "$ST/vocals.wav" ]; then
  echo "demucs: separating render (CPU, one pass)"
  demucs -n htdemucs -o "$RA" "$WAV" && echo "demucs done" || { echo "DEMUCS FAILED"; exit 1; }
else
  echo "demucs stems already present"
fi

for s in drums bass other vocals; do
  f="$ST/$s.wav"
  [ -f "$f" ] || { echo "missing stem $s"; continue; }
  out="$RA/dilla.$s.json"
  if [ ! -s "$out" ]; then
    ffmpeg -y -i "$f" -ac 1 -ar 22050 -f f32le -v error - 2>/dev/null \
      | "$NODE" "$(dirname "$0")/dilla_stem_analyze.js" > "$out" \
      && echo "analyzed render.$s" || echo "FAILED render.$s"
  fi
done

out="$RA/dilla.mix.json"
if [ ! -s "$out" ]; then
  ffmpeg -y -i "$WAV" -ac 1 -ar 22050 -f f32le -v error - 2>/dev/null \
    | "$NODE" "$(dirname "$0")/dilla_stem_analyze.js" > "$out" \
    && echo "analyzed render.mix" || echo "FAILED render.mix"
fi
echo "render analysis done"
