# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow", "imageio-ffmpeg"]
# ///
"""Vidéo référence / rendu Studio côte à côte : 3 passages à vitesse réelle, puis 1 au ralenti ×4, images numérotées.

C'est ce fichier qu'on fait valider AVANT de publier : des images fixes justes ne garantissent pas un mouvement juste.

Usage : uv run tools/anim/side_by_side.py <reference.mp4> <debut_video> <ralenti> <captures> <Animation> <x0,y0,x1,y1> <sortie.mp4>
  debut_video  instant de la référence qui correspond à la frame 0
  ralenti      durée vidéo / durée réelle (1 si la référence n'est pas ralentie)
  x0,y0,x1,y1  viewport Studio en pixels dans les captures (à relever sur une capture, il dépend de la disposition)
"""

import glob
import io
import os
import subprocess
import sys

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFont

video, start, slow, cap_dir, anim, viewport, out = sys.argv[1:8]
start, slow = float(start), float(slow)
x0, y0, x1, y1 = (int(v) for v in viewport.split(","))

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
FONT = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 24)
W, H = 640, 360
FPS = 60
crop_w = (y1 - y0) * 16 / 9  # le joueur est en 16:9 : on juge le même cadre que le jeu, pas le viewport de Studio
center = (x0 + x1) / 2
files = sorted(glob.glob(os.path.join(cap_dir, anim + "_*.png")))
assert files, "aucune capture pour " + anim


# Cette méthode permet d'extraire l'image de référence qui correspond à la frame i du rendu.
def reference(i):
	t = start + i / FPS * slow
	cmd = [FFMPEG, "-v", "error", "-ss", f"{t:.4f}", "-i", video, "-frames:v", "1", "-vf", f"scale={W}:{H}"]
	cmd += ["-f", "image2pipe", "-c:v", "png", "-"]
	return Image.open(io.BytesIO(subprocess.run(cmd, capture_output=True, check=True).stdout)).convert("RGB")


# Cette méthode permet de composer une image côte à côte avec le numéro de frame et la vitesse de lecture.
def compose(ref, rendered, i, label):
	im = Image.new("RGB", (W * 2, H))
	im.paste(ref, (0, 0))
	im.paste(rendered, (W, 0))
	draw = ImageDraw.Draw(im)
	draw.rectangle((0, 0, 330, 34), fill=(180, 20, 20))
	draw.text((6, 3), f"Reference {i:02d} {label}", fill="white", font=FONT)
	draw.rectangle((W, 0, W + 330, 34), fill=(20, 90, 180))
	draw.text((W + 6, 3), f"Roblox {i:02d} {label}", fill="white", font=FONT)
	return im.tobytes()


rows = []
for i, path in enumerate(files):
	rendered = Image.open(path).convert("RGB").crop((int(center - crop_w / 2), y0, int(center + crop_w / 2), y1))
	rows.append((reference(i), rendered.resize((W, H))))

cmd = [FFMPEG, "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W * 2}x{H}", "-r", str(FPS), "-i", "-"]
cmd += ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", "-movflags", "+faststart", out]
encoder = subprocess.Popen(cmd, stdin=subprocess.PIPE)
last = len(rows) - 1
for _ in range(3):
	for i, (ref, rendered) in enumerate(rows):
		encoder.stdin.write(compose(ref, rendered, i, "x1"))
	encoder.stdin.write(compose(*rows[last], last, "x1") * 30)
for i, (ref, rendered) in enumerate(rows):
	encoder.stdin.write(compose(ref, rendered, i, "x0.25") * 4)
encoder.stdin.close()
encoder.wait()
print(f"OK {len(rows)} frames -> {out}")
