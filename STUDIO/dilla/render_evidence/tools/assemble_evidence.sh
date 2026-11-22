#!/bin/sh
# Assemble measured canon evidence from per-stem analyses + source provenance.
set -eu
DA="${DILLA_ANALYSIS_DIR:-/home/z/my-project/dilla-analysis}"
PICKS="${SC_PICKS:-/home/z/my-project/scripts/sc_picks.json}"
OUT=$DA/canon_evidence.json
AN=$DA/analysis

echo "{" > "$OUT"
echo " \"assembled\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"," >> "$OUT"
echo " \"analyzer\": \"demucs htdemucs (CLI) -> pure-node spectral/onset analysis (scripts/dilla_stem_analyze.js)\"," >> "$OUT"
echo " \"method\": \"per stem: band energy shares (kick<130Hz, snare 150-1200Hz bp@400, hats>5kHz), onset flux peak-picking, tempo via onset-envelope autocorrelation 55-200bpm folded to 60-180, 16-slot grid via best-phase quantization (+-45ms), swing from off-8th residuals; mix: chroma (FFT 8192 @22050, 55-2200Hz) + Krumhansl key correlation\"," >> "$OUT"
echo " \"limits\": \"SoundCloud transcodes decode above 0 dBFS on some rows (peak_dbfs > 0) - levels are relative evidence only; official_preview rows carry 30s windows; key estimates are single-method (Krumhansl) and cross-checks are pending; swing assumes off-8th placement\"," >> "$OUT"
echo " \"curated_list_source\": \"pub index.html a3185f4 YOUTUBE_TRACKS (operator canon, 22 rows)\"," >> "$OUT"
echo " \"tracks\": [" >> "$OUT"

n=$(jq '.picks | length' "$PICKS")
i=0
first=1
while [ "$i" -lt "$n" ]; do
  ytid=$(jq -r ".picks[$i].ytid" "$PICKS")
  slug=$(jq -r ".picks[$i].slug" "$PICKS")
  artist=$(jq -r ".picks[$i].artist" "$PICKS")
  title=$(jq -r ".picks[$i].title" "$PICKS")
  cls=$(jq -r ".picks[$i].match_class" "$PICKS")
  up=$(jq -r ".picks[$i].uploader // \"\"" "$PICKS")
  note=$(jq -r ".picks[$i].pick_note" "$PICKS")
  i=$((i+1))
  if [ "$cls" = "no_match" ]; then
    [ $first -eq 0 ] && echo "," >> "$OUT"
    first=0
    printf '{"ytid":"%s","slug":"%s","artist":"%s","title":"%s","match_class":"no_match","pick_note":"%s","measured":null}' \
      "$ytid" "$slug" "$artist" "$title" "$note" >> "$OUT"
    continue
  fi
  dfile="$AN/$slug.drums.json"
  mfile="$AN/$slug.mix.json"
  [ $first -eq 0 ] && echo "," >> "$OUT"
  first=0
  if [ -s "$dfile" ] && [ -s "$mfile" ]; then
    drums=$(jq -c '{tempo, grid16: {kick: .grid16.grid.kick, snare: .grid16.grid.snare, hat: .grid16.grid.hat}, swing_position_pct: .grid16.swing_position_pct, off8_residual_ms: .grid16.off8_residual_ms, on_grid_share: .grid16.on_grid_share, bars_spanned: .grid16.bars_spanned, band_energy_share, onsets}' "$dfile")
    mix=$(jq -c '{key_estimate, chroma, centroid_hz, levels}' "$mfile")
    printf '{"ytid":"%s","slug":"%s","artist":"%s","title":"%s","match_class":"%s","uploader":"%s","pick_note":"%s","measured":{"drums":%s,"mix":%s}}' \
      "$ytid" "$slug" "$artist" "$title" "$cls" "$up" "$note" "$drums" "$mix" >> "$OUT"
  else
    printf '{"ytid":"%s","slug":"%s","artist":"%s","title":"%s","match_class":"%s","uploader":"%s","pick_note":"%s","measured":"analysis_missing"}' \
      "$ytid" "$slug" "$artist" "$title" "$cls" "$up" "$note" >> "$OUT"
  fi
done
echo "" >> "$OUT"
echo "]}" >> "$OUT"
jq . "$OUT" > /dev/null && echo "canon_evidence.json valid"
