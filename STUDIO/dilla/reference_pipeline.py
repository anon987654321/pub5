#!/usr/bin/env python3
"""Reference pipeline: curated YouTube tracks -> stems -> measurements.

Operator directive 2026-11-22: the curated pub/index.html tracks are the
canon. Download them with yt-dlp, split them with demucs htdemucs, and
measure each layer with reference_stems.py (analyzer_version stems-1).

Usage:
    python3 reference_pipeline.py --slug players
    python3 reference_pipeline.py --all            # operator picks
    python3 reference_pipeline.py --slug fantastic --id a3ISYWWYgz8
    python3 reference_pipeline.py --slug players --skip-download   # reuse audio

Environment:
    DILLA_YT_COOKIES   path to the operator's cookies.txt; needed when
                       YouTube bot-checks this sandbox IP (default state).
    DILLA_REF_WORK     scratch dir for audio and stems
                       (default /tmp/dilla_ref).

YouTube bot-checks datacenter IPs. The pipeline tries player clients in
order (default web, android, ios, tv) and records which one worked. Dead
ids are recorded in curated_references.json probe_2026_11_22; pass --id
to try a live replacement.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import reference_stems  # noqa: E402

MANIFEST = os.path.join(HERE, "data", "curated_references.json")
MEASUREMENTS = os.path.join(HERE, "data", "reference_measurements")
WORK = os.environ.get("DILLA_REF_WORK", "/tmp/dilla_ref")
CLIENTS = [None, "android", "ios", "tv"]


def load_manifest():
    with open(MANIFEST, encoding="utf-8") as fh:
        return json.load(fh)


def picks_for(doc, slug=None):
    picks = doc.get("operator_picks") or []
    if slug:
        picks = [p for p in picks if p["slug"] == slug]
    return picks


def run(cmd, **kw):
    print("  $", " ".join(cmd[:8]) + (" ..." if len(cmd) > 8 else ""))
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def probe_id(video_id):
    """Return the first (client, title) that resolves, or (None, reason)."""
    url = f"https://www.youtube.com/watch?v={video_id}"
    for client in CLIENTS:
        cmd = ["/home/z/.venv/bin/yt-dlp", "--simulate", "--skip-download",
               "--print", "%(title)s|%(duration)s"]
        if client:
            cmd += ["--extractor-args", f"youtube:player_client={client}"]
        cookies = os.environ.get("DILLA_YT_COOKIES")
        if cookies and os.path.isfile(cookies):
            cmd += ["--cookies", cookies]
        cmd.append(url)
        proc = run(cmd)
        if proc.returncode == 0 and "|" in proc.stdout:
            title, dur = proc.stdout.strip().split("|", 1)
            return client, title, float(dur or 0)
        if "Video unavailable" in (proc.stderr or ""):
            return None, "dead_upload", 0.0
        reason = (proc.stderr or "").strip().splitlines()[-1] if (proc.stderr or "").strip() else "unknown"
        last = reason
    return None, last, 0.0


def download(video_id, client, out_base):
    url = f"https://www.youtube.com/watch?v={video_id}"
    cmd = ["/home/z/.venv/bin/yt-dlp", "-x", "--audio-format", "wav",
           "--audio-quality", "0", "-o", out_base + ".%(ext)s"]
    if client:
        cmd += ["--extractor-args", f"youtube:player_client={client}"]
    cookies = os.environ.get("DILLA_YT_COOKIES")
    if cookies and os.path.isfile(cookies):
        cmd += ["--cookies", cookies]
    cmd.append(url)
    proc = run(cmd)
    if proc.returncode == 0 and os.path.isfile(out_base + ".wav"):
        return out_base + ".wav", None
    return None, (proc.stderr or proc.stdout or "download failed").strip()[-400:]


def split_stems(audio_path):
    stems_root = os.path.join(WORK, "demucs")
    proc = run(["/home/z/.venv/bin/python3", "-m", "demucs", "-n", "htdemucs",
                "-o", stems_root, audio_path])
    if proc.returncode != 0:
        return None, (proc.stderr or proc.stdout or "demucs failed").strip()[-400:]
    track_dir = os.path.splitext(os.path.basename(audio_path))[0]
    stems_dir = os.path.join(stems_root, "htdemucs", track_dir)
    if not os.path.isdir(stems_dir):
        return None, f"expected stems dir missing: {stems_dir}"
    return stems_dir, None


def process(pick, doc, skip_download=False, forced_id=None):
    slug = pick["slug"]
    video_id = forced_id or pick.get("curated_youtube_id")
    if not video_id:
        video_id = (pick.get("candidate_ids") or [None])[0]
    out = {"slug": slug, "youtube_id": video_id}
    if not video_id:
        out["status"] = "no_video_id"
        return out
    print(f"[{slug}] id={video_id}")
    client, title, dur = probe_id(video_id)
    out["title"] = title
    out["duration_s"] = dur
    if client is None:
        out["status"] = f"unresolved: {title}"
        return out
    out["download_client"] = client or "web"
    os.makedirs(WORK, exist_ok=True)
    audio_path = os.path.join(WORK, f"{slug}.wav")
    if skip_download and os.path.isfile(audio_path):
        out["source"] = "reused existing audio"
    else:
        path, err = download(video_id, client, os.path.join(WORK, slug))
        if err:
            out["status"] = f"download_failed: {err}"
            return out
        shutil.move(path, audio_path)
        out["source"] = f"downloaded with client {client or 'web'}"
        time.sleep(2.0)
    print(f"[{slug}] splitting with demucs htdemucs ...")
    stems_dir, err = split_stems(audio_path)
    if err:
        out["status"] = f"split_failed: {err}"
        return out
    os.makedirs(MEASUREMENTS, exist_ok=True)
    meas_path = os.path.join(MEASUREMENTS, f"{slug}.json")
    doc_measured = reference_stems.analyze(audio_path, stems_dir)
    doc_measured["slug"] = slug
    doc_measured["source"] = {
        "youtube_id": video_id,
        "url": f"https://www.youtube.com/watch?v={video_id}",
        "title": title,
        "download_client": client or "web",
        "measured": time.strftime("%Y-%m-%d"),
        "curation": "pub/index.html a3185f4 YOUTUBE_TRACKS (operator picks)",
    }
    with open(meas_path, "w", encoding="utf-8") as fh:
        json.dump(doc_measured, fh, indent=1)
        fh.write("\n")
    out["status"] = "measured"
    out["measurement"] = meas_path
    out["bpm"] = doc_measured["bpm"]
    out["swing_ratio"] = doc_measured["swing_ratio"]
    out["key"] = doc_measured["harmony"]["key"]
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--slug")
    ap.add_argument("--id", dest="video_id")
    ap.add_argument("--all", action="store_true", help="every operator pick")
    ap.add_argument("--skip-download", action="store_true")
    args = ap.parse_args()

    doc = load_manifest()
    picks = picks_for(doc, args.slug) if args.slug else (doc.get("operator_picks") or [])
    if args.slug and not picks:
        picks = [{"slug": args.slug, "candidate_ids": [args.video_id] if args.video_id else []}]
    if not picks:
        print("no picks selected (use --slug or --all)")
        return 1
    results = []
    for pick in picks:
        results.append(process(pick, doc, skip_download=args.skip_download,
                               forced_id=args.video_id))
    print(json.dumps(results, indent=1))
    return 0 if all(r.get("status") == "measured" for r in results) else 2


if __name__ == "__main__":
    sys.exit(main())
