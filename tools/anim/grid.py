# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow", "imageio-ffmpeg"]
# ///
"""Planche d'images numérotées d'une vidéo, avec une grille pour mesurer des positions à l'écran.

Usage : uv run tools/anim/grid.py <video> <sortie.jpg> <debut> <fin> <pas> [colonnes=5] [xmin=0] [xmax=1]
La grille est graduée en coordonnées normalisées de l'image entière (0,0 = haut gauche, 1,1 = bas droite), même
recadrée : xmin et xmax permettent de zoomer sur la zone où se trouve l'arme pour mesurer plus précisément.
"""

import io
import subprocess
import sys

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFont

args = sys.argv[1:]
video, out = args[0], args[1]
start, end, step = float(args[2]), float(args[3]), float(args[4])
cols = int(args[5]) if len(args) > 5 else 5
xmin = float(args[6]) if len(args) > 6 else 0.0
xmax = float(args[7]) if len(args) > 7 else 1.0

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
TITLE = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 18)
SMALL = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 13)
CELL_W = 400


# Cette méthode permet d'extraire l'image de la vidéo à l'instant t, en pleine résolution.
def frame_at(t):
	cmd = [FFMPEG, "-v", "error", "-ss", f"{t:.4f}", "-i", video, "-frames:v", "1", "-f", "image2pipe", "-c:v", "png", "-"]
	return Image.open(io.BytesIO(subprocess.run(cmd, capture_output=True, check=True).stdout)).convert("RGB")


# Cette méthode permet de tracer la grille graduée et le temps sur une image recadrée.
def annotate(im, index, t):
	draw = ImageDraw.Draw(im)
	w, h = im.size
	for k in range(11):
		u = k / 10
		if xmin <= u <= xmax:
			x = (u - xmin) / (xmax - xmin) * w
			draw.line((x, 0, x, h), fill=(255, 0, 0) if k == 5 else (255, 140, 0))
			draw.text((x + 2, h - 15), f".{k}", fill=(255, 255, 0), font=SMALL)
		draw.line((0, u * h, w, u * h), fill=(255, 0, 0) if k == 5 else (255, 140, 0))
		draw.text((2, u * h + 1), f".{k}", fill=(255, 255, 0), font=SMALL)
	draw.rectangle((w - 110, 0, w, 24), fill=(180, 20, 20))
	draw.text((w - 106, 2), f"{index + 1}  {t:.2f}", fill="white", font=TITLE)


times = []
t = start
while t <= end + 1e-6:
	times.append(round(t, 3))
	t += step
sheet = None
for i, t in enumerate(times):
	im = frame_at(t)
	w, h = im.size
	crop = im.crop((int(xmin * w), 0, int(xmax * w), h))
	cell_h = int(CELL_W * crop.size[1] / crop.size[0])
	crop = crop.resize((CELL_W, cell_h))
	annotate(crop, i, t)
	if sheet is None:
		rows = (len(times) + cols - 1) // cols
		sheet = Image.new("RGB", (cols * CELL_W, rows * cell_h), "black")
	sheet.paste(crop, ((i % cols) * CELL_W, (i // cols) * cell_h))
sheet.save(out, quality=90)
print(f"OK {len(times)} images -> {out}")
