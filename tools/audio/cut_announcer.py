# /// script
# dependencies = ["imageio-ffmpeg"]
# ///
"""Découpe l'enregistrement de l'annonceur en un mp3 par phrase (bornes mesurées par silencedetect à -35 dB).

Usage (racine du worktree) : uv run tools/audio/cut_announcer.py assets/sounds/Announcer/source.mp3 assets/sounds/Announcer
Puis publier chaque clip (tools/publish_asset.sh <clip> Audio <nom>) et reporter les ids dans KillAnnouncer.SOUND_IDS.
"""
import subprocess
import sys
from pathlib import Path

import imageio_ffmpeg

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
SOURCE, OUT = sys.argv[1], Path(sys.argv[2])
# nom, début, fin de la phrase (s) ; "Godlike" (7,95 à 9,21 s) n'est pas utilisé
CLIPS = [
    ("Headshot", 0.00, 1.03),
    ("DoubleKill", 1.32, 2.45),
    ("TripleKill", 2.79, 4.06),
    ("QuadrupleKill", 4.35, 5.91),
    ("MonsterKill", 6.20, 7.68),
    ("Dominating", 9.48, 11.62),
    ("Divine", 11.91, 13.04),
]
PAD_IN, PAD_OUT, FADE = 0.03, 0.08, 0.06

OUT.mkdir(parents=True, exist_ok=True)
for name, start, end in CLIPS:
    a = max(0.0, start - PAD_IN)
    d = end + PAD_OUT - a
    subprocess.run(
        [FFMPEG, "-v", "error", "-y", "-ss", f"{a:.3f}", "-t", f"{d:.3f}", "-i", SOURCE,
         "-af", f"afade=t=out:st={d - FADE:.3f}:d={FADE}", "-ac", "1", "-b:a", "128k", str(OUT / f"{name}.mp3")],
        check=True,
    )
    print(f"{name}: {a:.2f} -> {a + d:.2f} ({d:.2f} s)")
