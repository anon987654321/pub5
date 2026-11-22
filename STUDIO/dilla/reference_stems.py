#!/usr/bin/env python3
"""Per-stem reference analyzer (analyzer_version: stems-1).

Measures what the operator asked to hear about the curated tracks: keys,
chroma and spectral bands per demucs stem, drum grids, swing, tempo and
energy shares. Output is a single JSON document per track:

    python3 reference_stems.py --mix <mix.wav> --stems-dir <demucs_out> \
        --out data/reference_measurements/<slug>.json [--slug S]

The mix and the four htdemucs stems (vocals.wav, drums.wav, bass.wav,
other.wav) must already exist; the orchestrating reference_pipeline.py
creates them. Numbers are rounded to measurement precision; nothing here
is a transcription of notes, only aggregate acoustic evidence.
"""

from __future__ import annotations

import argparse
import json
import os

import librosa
import numpy as np

ANALYZER_VERSION = "stems-1"
SR = 22050

PC_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

# Krumhansl-Kessler key profiles.
KK_MAJ = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
KK_MIN = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])

BANDS = [
    ("sub_below_60_hz", 20.0, 60.0),
    ("low_60_200_hz", 60.0, 200.0),
    ("mid_200_2000_hz", 200.0, 2000.0),
    ("high_2000_9000_hz", 2000.0, 9000.0),
    ("ultra_above_9000_hz", 9000.0, 11025.0),
]

STEM_FILES = {"vocals": "vocals.wav", "drums": "drums.wav", "bass": "bass.wav", "other": "other.wav"}


def r(x, n=3):
    if x is None:
        return None
    return round(float(x), n)


def load(path):
    y, _ = librosa.load(path, sr=SR, mono=True)
    return y


def rms_db(y):
    rms = float(np.sqrt(np.mean(np.square(y)))) if y.size else 0.0
    if rms <= 1e-9:
        return -120.0
    return 20.0 * np.log10(rms)


def spectral_bands(y):
    S = np.abs(librosa.stft(y, n_fft=2048)) ** 2
    freqs = librosa.fft_frequencies(sr=SR, n_fft=2048)
    total = float(S.sum()) or 1e-12
    out = {}
    for name, lo, hi in BANDS:
        mask = (freqs >= lo) & (freqs < hi)
        out[name] = r(float(S[mask].sum()) / total, 4)
    return out


def chroma_and_key(y):
    if y.size < SR // 4:
        return [0.0] * 12, "-", 0.0
    ch = librosa.feature.chroma_cqt(y=y, sr=SR)
    ch = np.nan_to_num(ch, nan=0.0, posinf=0.0, neginf=0.0)
    chroma = ch.mean(axis=1)
    if chroma.sum() <= 1e-9:
        return [0.0] * 12, "-", 0.0
    chroma = chroma / chroma.sum()
    best, best_corr = "-", -2.0
    for mode, prof in (("maj", KK_MAJ), ("min", KK_MIN)):
        for i in range(12):
            c = np.corrcoef(chroma, np.roll(prof, i))[0, 1]
            if c > best_corr:
                best_corr, best = c, f"{PC_NAMES[i]} {mode}"
    return [r(v, 3) for v in chroma], best, r(max(best_corr, 0.0), 3)


def dominant_low_pitch_classes(chroma12):
    total = sum(chroma12) or 1.0
    ranked = sorted(range(12), key=lambda i: -chroma12[i])[:3]
    return [{"pc": PC_NAMES[i], "share": r(chroma12[i] / total, 3)} for i in ranked]


# Chord templates: major, minor(m7), dominant 7.
CHORD_TEMPLATES = {
    "maj": [0, 4, 7],
    "m7": [0, 3, 7, 10],
    "7": [0, 4, 7, 10],
}


def chord_timeline(y, win_s=0.5, hop_s=0.25):
    if y.size < SR:
        return {"chord_changes": 0, "chords": []}
    ch = librosa.feature.chroma_cqt(y=y, sr=SR, hop_length=512)
    ch = np.nan_to_num(ch, nan=0.0, posinf=0.0, neginf=0.0)
    frames_per_win = max(1, int(win_s * SR / 512))
    frames_per_hop = max(1, int(hop_s * SR / 512))
    frame_rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=512)[0]
    if frame_rms.size:
        floor = max(float(np.percentile(frame_rms, 20)), 1e-5)
    else:
        floor = 0.0
    n_win = max(1, (ch.shape[1] - frames_per_win) // frames_per_hop + 1)
    labels, times = [], []
    for w in range(n_win):
        lo = w * frames_per_hop
        if lo + frames_per_win > ch.shape[1]:
            break
        seg = ch[:, lo: lo + frames_per_win].mean(axis=1)
        win_rms = float(frame_rms[lo: lo + frames_per_win].mean()) if frame_rms.size else 1.0
        if seg.sum() <= 1e-9 or win_rms < floor * 0.5:
            continue
        seg = seg / seg.sum()
        best, best_score = None, -2.0
        for root in range(12):
            for qual, steps in CHORD_TEMPLATES.items():
                tpl = np.zeros(12)
                tpl[[(s + root) % 12 for s in steps]] = 1.0
                tpl = tpl / tpl.sum()
                score = float(np.dot(seg, tpl))
                if score > best_score:
                    best_score, best = score, f"{PC_NAMES[root]}{qual}"
        labels.append(best); times.append(r(w * hop_s, 2))
    chords, changes = [], 0
    last = None
    for lab, t in zip(labels, times):
        if lab != last:
            chords.append({"label": lab, "t": t})
            changes += 1
            last = lab
    return {"chord_changes": changes, "chords": chords}


def beat_grid(y):
    tempo, beats = librosa.beat.beat_track(y=y, sr=SR, units="time")
    tempo = float(np.atleast_1d(tempo)[0])
    if len(beats) >= 4:
        ibi = np.diff(beats)
        spread = float(np.std(ibi)) / max(float(np.median(ibi)), 1e-6)
        conf = r(max(0.0, min(1.0, 1.0 - spread * 2.0)), 3)
    else:
        conf = 0.0
    return tempo, list(beats), conf


def _beat_position(t, beats, beat_len):
    """Return (beat_index, frac_in_beat) allowing one virtual beat before
    the first and after the last measured beat, or (None, None) when far
    outside the grid."""
    if len(beats) < 2:
        return None, None
    i = int(np.searchsorted(beats, t, side="right") - 1)
    if i < 0:
        i = -1
        frac = 1.0 + (t - beats[0]) / beat_len
    elif i >= len(beats):
        i = len(beats)
        frac = (t - beats[-1]) / beat_len
    else:
        frac = (t - beats[i]) / beat_len
    if frac < -0.25 or frac >= 1.25:
        return None, None
    return i, min(max(frac, 0.0), 0.999)


def drum_metrics(drums, bpm, beats):
    onsets = librosa.onset.onset_detect(y=drums, sr=SR, units="time", backtrack=True)
    out = {
        "swing_ratio": None,
        "offbeat_onset_share": None,
        "onset_density_per_bar": None,
        "timing_spread_ms": None,
        "drum_grid": {},
    }
    if bpm <= 0 or not len(onsets):
        return out
    beat_len = 60.0 / bpm
    bar_len = beat_len * 4.0
    # Continuous 16th-note position of any time, relative to the measured
    # beat grid. Rounding q to the nearest 16th self-corrects the grid's
    # phase drift: an event at frac 0.96 of beat k belongs to beat k+1.
    def pos16(t):
        i, frac = _beat_position(t, beats, beat_len)
        if i is None:
            return None
        return (i + frac) * 4.0

    qs = [round(pos16(t)) for t in onsets if pos16(t) is not None]
    if not qs:
        return out
    # Swing: the long-gap share of the first 8th-pair inside each beat.
    # Straight 8ths sit at 0.5; the engine's Dilla swing 54 sits at 0.54;
    # triplet swing at 0.667.
    by_beat = {}
    for q in qs:
        by_beat.setdefault(q // 4, []).append(q % 4)
    gaps = []
    for k, slots in by_beat.items():
        slots = sorted(slots)
        if len(slots) >= 2:
            g1 = (slots[1] - slots[0]) / 4.0
            g2 = 1.0 - g1
            if g1 + g2 > 1e-6:
                gaps.append(max(g1, g2) / (g1 + g2))
    out["swing_ratio"] = r(float(np.median(gaps)), 4) if gaps else 0.5
    # Off-grid share: onsets whose nearest 16th slot is an odd 16th.
    out["offbeat_onset_share"] = r(sum(1 for q in qs if q % 2 == 1) / len(qs), 4)
    out["onset_density_per_bar"] = r(len(onsets) / max(len(beats) / 4.0, 0.5), 4)
    sixteenth_ms = beat_len * 250.0
    devs = [abs(pos16(t) - round(pos16(t))) * sixteenth_ms for t in onsets if pos16(t) is not None]
    out["timing_spread_ms"] = r(float(np.median(devs)), 2)

    # 16-step drum grids per voice, folded across bars, normalized 0..1.
    bands = {"kick": (20.0, 130.0), "snare": (170.0, 2600.0), "hat": (5000.0, 10000.0)}
    # A 46 ms window (n_fft=1024) keeps short transients inside one slot;
    # remaining straddlers are split by sub-sampling the window span.
    S = np.abs(librosa.stft(drums, n_fft=1024, hop_length=512))
    freqs = librosa.fft_frequencies(sr=SR, n_fft=1024)
    times_frames = librosa.frames_to_time(np.arange(S.shape[1]), sr=SR, n_fft=1024, hop_length=512)
    win = 1024 / SR
    half = win / 2.0
    n_sub = 8
    bands_energy = {}
    for name, (lo, hi) in bands.items():
        mask = (freqs >= lo) & (freqs < hi)
        energy = S[mask].sum(axis=0)
        if energy.size == 0 or float(energy.max()) <= 0:
            out["drum_grid"][name] = [0.0] * 16
            continue
        bands_energy[name] = energy

    def fold(grid, energy, phase):
        for f, t in enumerate(times_frames):
            share = energy[f] / n_sub
            for s in range(n_sub):
                q = pos16(t - half + win * (s + 0.5) / n_sub)
                if q is None:
                    continue
                grid[(round(q) + phase * 4) % 16] += share

    # Bar-phase selection from the kick band: try the four beat-phase
    # offsets and keep the one that puts the most kick energy on the
    # canonical downbeat slots (0 and 8 = beats 1 and 3).
    if len(bands_energy.get("kick", [])) and len(beats) >= 2:
        best_p, best_score = 0, -1.0
        for p in range(4):
            g = np.zeros(16)
            fold(g, bands_energy["kick"], p)
            score = float(g[0] + g[8])
            if score > best_score:
                best_p, best_score = p, score
    else:
        best_p = 0
    for name, energy in bands_energy.items():
        grid = np.zeros(16)
        fold(grid, energy, best_p)
        if grid.max() > 0:
            grid = grid / grid.max()
        out["drum_grid"][name] = [r(float(v), 3) for v in grid]
    return out

def melody_stats(vocals, other, bpm):
    merged = vocals + other if vocals.size == other.size else other
    if merged.size < SR // 2:
        return {"median_hz": None, "note_density_per_bar": None, "range_semitones": None}
    f0 = librosa.yin(merged, fmin=80.0, fmax=1000.0, sr=SR, frame_length=2048)
    frame_rms = librosa.feature.rms(y=merged, frame_length=2048, hop_length=256)[0][: f0.shape[0]]
    voiced = f0[(frame_rms > max(1e-4, float(np.median(frame_rms)) * 0.3))]
    density = None
    if bpm > 0:
        onsets = librosa.onset.onset_detect(y=merged, sr=SR, units="time")
        density = r(len(onsets) / max((len(merged) / SR) / (60.0 / bpm * 4.0), 0.5), 3)
    if voiced.size == 0:
        return {"median_hz": None, "note_density_per_bar": density, "range_semitones": None}
    lo, hi = np.percentile(voiced, [5, 95])
    return {
        "median_hz": r(float(np.median(voiced)), 1),
        "note_density_per_bar": density,
        "range_semitones": r(12.0 * np.log2(max(hi, 1.0) / max(lo, 1.0)), 1) if lo > 0 else None,
    }


def sections(mix, seg_s=4.2):
    hop = int(seg_s * SR)
    n = len(mix) // hop
    if n < 2:
        return [{"level": "high", "start": 0.0}]
    levels_rms = np.array([rms_db(mix[i * hop:(i + 1) * hop]) for i in range(n)])
    q33, q66 = np.percentile(levels_rms, [33, 66])
    out, last = [], None
    for i, v in enumerate(levels_rms):
        level = "low" if v <= q33 else ("mid" if v <= q66 else "high")
        if level != last:
            out.append({"level": level, "start": r(i * seg_s, 1)})
            last = level
    return out


def analyze(mix_path, stems_dir):
    mix = load(mix_path)
    doc = {
        "analyzer_version": ANALYZER_VERSION,
        "duration_s": r(len(mix) / SR, 2),
        "brightness_hz": None,
        "bpm": None,
        "bpm_confidence": None,
        "swing_ratio": None,
        "offbeat_onset_share": None,
        "onset_density_per_bar": None,
        "timing_spread_ms": None,
        "drum_grid": {},
        "harmony": {},
        "melody": {},
        "sections": [],
        "stem_harmony": {},
        "vocal_energy_share": None,
        "drums_energy_share": None,
        "bass_energy_share": None,
        "other_energy_share": None,
    }
    centroid = librosa.feature.spectral_centroid(y=mix, sr=SR)[0]
    doc["brightness_hz"] = r(float(np.mean(centroid)), 1)

    bpm, beats, conf = beat_grid(mix)
    doc["bpm"] = r(bpm, 2)
    doc["bpm_confidence"] = conf

    stems = {}
    for stem, fname in STEM_FILES.items():
        path = os.path.join(stems_dir, fname)
        stems[stem] = load(path) if os.path.isfile(path) else np.zeros(1)

    drum = drum_metrics(stems["drums"], bpm, beats)
    for k in ("swing_ratio", "offbeat_onset_share", "onset_density_per_bar",
              "timing_spread_ms", "drum_grid"):
        doc[k] = drum[k]

    mix_chroma, mix_key, mix_conf = chroma_and_key(mix)
    doc["harmony"] = {"key": mix_key, "key_confidence": mix_conf,
                      **chord_timeline(stems["other"] if stems["other"].size > SR else mix)}
    doc["melody"] = melody_stats(stems["vocals"], stems["other"], bpm)
    doc["sections"] = sections(mix)

    powers = {}
    for stem in ("vocals", "drums", "bass", "other"):
        y = stems[stem]
        present = bool(y.size > SR // 10 and rms_db(y) > -60.0)
        entry = {"present": present, "rms_db": r(rms_db(y), 1)}
        if present:
            entry["spectral_bands"] = spectral_bands(y)
            if stem in ("vocals", "bass", "other"):
                ch12, key, kc = chroma_and_key(y)
                entry["chroma"] = ch12
                entry["key"] = key
                entry["key_confidence"] = kc
                if stem == "bass":
                    entry["dominant_low_pitch_classes"] = dominant_low_pitch_classes(
                        [c if isinstance(c, float) else 0.0 for c in ch12])
                if stem == "other":
                    entry["chords"] = chord_timeline(y)
        powers[stem] = float(np.mean(np.square(y))) if y.size else 0.0
        doc["stem_harmony"][stem] = entry
    total = sum(powers.values()) or 1e-12
    doc["vocal_energy_share"] = r(powers["vocals"] / total, 3)
    doc["drums_energy_share"] = r(powers["drums"] / total, 3)
    doc["bass_energy_share"] = r(powers["bass"] / total, 3)
    doc["other_energy_share"] = r(powers["other"] / total, 3)
    return doc


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--mix", required=True)
    ap.add_argument("--stems-dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--slug", default=None)
    args = ap.parse_args()
    doc = analyze(args.mix, args.stems_dir)
    if args.slug:
        doc["slug"] = args.slug
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=1)
        fh.write("\n")
    print(f"measured {args.slug or os.path.basename(args.mix)} -> {args.out}")
    print(f"  bpm={doc['bpm']} swing={doc['swing_ratio']} key={doc['harmony']['key']}"
          f" drums={doc['drums_energy_share']} bass={doc['bass_energy_share']}"
          f" other={doc['other_energy_share']}")


if __name__ == "__main__":
    main()
