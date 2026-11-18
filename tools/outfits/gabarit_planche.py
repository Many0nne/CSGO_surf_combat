# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Assemble les trois vues du rig (gabarit_rig.py) en une planche 1536 × 1024 sur fond blanc, à joindre au brief d'une
tenue (#521) : de face, de trois quarts, de dos, à la même échelle et posées sur la même ligne de sol.

Usage (depuis la racine du worktree) :
  uv run tools/outfits/gabarit_planche.py assets/outfits/concepts
Sortie : <dossier>/gabarit_rig.png
"""

import os
import sys

from PIL import Image, ImageChops

W, H, MARGIN = 1536, 1024, 16
VIEWS = ["rig_face", "rig_trois_quarts", "rig_dos"]


# Cette méthode permet de recadrer une vue sur le personnage (tout ce qui n'est pas blanc) lorsqu'on prépare la planche.
def crop(img):
	bg = Image.new("RGB", img.size, (255, 255, 255))
	box = ImageChops.difference(img, bg).convert("L").point(lambda v: 255 if v > 8 else 0).getbbox()
	return img.crop(box)


def main():
	folder = sys.argv[1]
	views = [crop(Image.open(os.path.join(folder, v + ".png")).convert("RGB")) for v in VIEWS]
	cell = W // len(views)
	# Même échelle pour les trois : la plus contraignante (largeur de cellule ou hauteur utile)
	scale = min(min((cell - 2 * MARGIN) / v.width, (H - 2 * MARGIN) / v.height) for v in views)
	sheet = Image.new("RGB", (W, H), (255, 255, 255))
	# Personnages posés bas : la place libre au-dessus sert aux casques et coiffes des tenues
	ground = H - 60
	for i, v in enumerate(views):
		v = v.resize((round(v.width * scale), round(v.height * scale)), Image.LANCZOS)
		sheet.paste(v, (i * cell + (cell - v.width) // 2, ground - v.height))
	out = os.path.join(folder, "gabarit_rig.png")
	sheet.save(out)
	print(out)


main()
