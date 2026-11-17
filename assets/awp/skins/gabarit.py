# /// script
# dependencies = ["numpy", "pillow", "scipy"]
# ///
"""Gabarit d'illustration de l'AWP (#492) : silhouette exacte du châssis (garde-main et crosse, flanc gauche, vu en 1P),
à donner à un modèle d'image pour qu'il dessine un skin illustré aux bonnes proportions.

`uv run assets/awp/skins/gabarit.py <dossier> [largeur] [hauteur]` écrit :
- `gabarit_masque.png` : silhouette noire sur blanc, trous en blanc (image de contrôle à joindre au modèle) ;
- `gabarit_annote.png` : la même, avec le joint, la marge du filet de contour, la zone vue en 1P et le sens de l'arme ;
- `gabarit.json` : échelle et décalage photo -> image, pour replacer l'illustration sur la toile de profil.
"""

import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import JOINT, chassis, outline  # noqa: E402

MARGIN = 15.0  # cadre et filet posés par le jeu le long du contour (px photo) : rien d'important dessous
FOCUS = (2440, 2720)  # avant de la crosse, ce que le joueur voit le plus en 1P (px photo, en x)


def mapping(w, h):
	"""Cette méthode permet d'obtenir l'échelle et le décalage qui placent la photo de profil dans un gabarit w x h
	(châssis centré, 92 % de la largeur) : pixel du gabarit = pixel photo * échelle + décalage."""
	xs, ys = zip(*chassis())
	x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
	scale = 0.92 * w / (x1 - x0)
	return scale, (w - (x1 - x0) * scale) / 2 - x0 * scale, (h - (y1 - y0) * scale) / 2 - y0 * scale


def silhouette(w, h):
	"""Cette méthode permet de dessiner le masque du gabarit w x h : châssis noir sur blanc, trous en blanc."""
	scale, ox, oy = mapping(w, h)
	mask = Image.new("L", (w, h), 255)
	d = ImageDraw.Draw(mask)
	d.polygon([(px * scale + ox, py * scale + oy) for px, py in chassis()], fill=0)
	for hole in (outline("GUARD_HOLE"), outline("THUMBHOLE")):
		d.polygon([(px * scale + ox, py * scale + oy) for px, py in hole], fill=255)
	return mask


def main():
	"""Cette méthode permet d'écrire le masque, le gabarit annoté et la correspondance photo -> image."""
	out = sys.argv[1]
	w = int(sys.argv[2]) if len(sys.argv) > 2 else 2520
	h = int(sys.argv[3]) if len(sys.argv) > 3 else 1080
	os.makedirs(out, exist_ok=True)
	shape = chassis()
	holes = [outline("GUARD_HOLE"), outline("THUMBHOLE")]
	scale, ox, oy = mapping(w, h)

	def to(pts):
		"""Cette méthode permet de convertir des points de la photo de profil en pixels du gabarit."""
		return [(px * scale + ox, py * scale + oy) for px, py in pts]

	mask = silhouette(w, h)
	mask.save(os.path.join(out, "gabarit_masque.png"))

	# gabarit annoté : silhouette grise, bande de marge plus sombre, joint en tirets, zone 1P encadrée
	from scipy import ndimage

	inside = np.asarray(mask) == 0
	dist = ndimage.distance_transform_edt(inside) / scale
	rgb = np.full((h, w, 3), 255, np.uint8)
	rgb[inside] = (200, 200, 205)
	rgb[inside & (dist < MARGIN)] = (120, 120, 130)
	img = Image.fromarray(rgb)
	d = ImageDraw.Draw(img)
	d.polygon(to(shape), outline=(20, 20, 20), width=3)
	for hole in holes:
		d.polygon(to(hole), outline=(20, 20, 20), width=3)
	jx = JOINT * scale + ox
	for yy in np.arange(363 * scale + oy, 537 * scale + oy, 18):
		d.line([(jx, yy), (jx, yy + 9)], fill=(20, 20, 20), width=2)
	fx0, fx1 = FOCUS[0] * scale + ox, FOCUS[1] * scale + ox
	d.rectangle([fx0, 360 * scale + oy, fx1, 548 * scale + oy], outline=(230, 120, 0), width=4)
	try:
		f = ImageFont.truetype("C:/Windows/Fonts/bahnschrift.ttf", int(h * 0.03))
	except OSError:
		f = ImageFont.load_default()
	d.text((fx0, 548 * scale + oy + 8), "VISIBLE IN FIRST PERSON (focal point)", fill=(230, 120, 0), font=f)
	d.text((20, h / 2 - 20), "<- MUZZLE", fill=(20, 20, 20), font=f)
	d.text((w - 20, h / 2 - 20), "BUTT ->", fill=(20, 20, 20), font=f, anchor="ra")
	d.text((20, h - 50), "dark band: border painted by the game, keep empty  |  dashed: two-piece joint, art crosses it", fill=(80, 80, 80), font=f)
	img.save(os.path.join(out, "gabarit_annote.png"))

	with open(os.path.join(out, "gabarit.json"), "w", encoding="utf-8") as fh:
		json.dump({"width": w, "height": h, "scale": scale, "offset": [ox, oy]}, fh, indent=1)
	print(f"[gabarit] {w}x{h}, échelle {scale:.3f} px par px photo -> {out}")


if __name__ == "__main__":
	main()
