"""Assemble des rendus (PNG à fond transparent) en une planche titrée, sur un fond sombre en dégradé (#268).

Usage : uv run --with pillow tools/skins/compose_board.py <sortie.jpg> <colonnes> "<titre>|<image>" ["<titre>|<image>" ...]
Une cellule fait la taille de la première image ; un titre vide laisse la cellule sans légende.
"""

import sys

from PIL import Image, ImageDraw, ImageFont

out, cols = sys.argv[1], int(sys.argv[2])
cells = [a.split("|", 1) for a in sys.argv[3:]]
first = Image.open(cells[0][1])
W, H = first.size
LABEL = 44
rows = (len(cells) + cols - 1) // cols
board = Image.new("RGB", (W * cols, (H + LABEL) * rows), (20, 22, 26))


# Cette méthode permet de fabriquer un fond en dégradé vertical (gris bleuté vers presque noir) pour une cellule.
def background(w, h):
	bg = Image.new("RGB", (w, h))
	d = ImageDraw.Draw(bg)
	for y in range(h):
		k = y / max(h - 1, 1)
		c = tuple(int(a + (b - a) * k) for a, b in zip((58, 62, 70), (18, 19, 23)))
		d.line([(0, y), (w, y)], fill=c)
	return bg


try:
	font = ImageFont.truetype("arialbd.ttf", 26)
except OSError:
	font = ImageFont.load_default()
for i, (title, path) in enumerate(cells):
	x, y = (i % cols) * W, (i // cols) * (H + LABEL)
	cell = background(W, H)
	im = Image.open(path).convert("RGBA").resize((W, H))
	cell.paste(im, (0, 0), im)
	board.paste(cell, (x, y + LABEL))
	ImageDraw.Draw(board).text((x + 14, y + 8), title, fill=(243, 233, 220), font=font)
board.save(out, quality=92)
print(out)
