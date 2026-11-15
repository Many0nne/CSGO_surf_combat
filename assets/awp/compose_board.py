# /// script
# dependencies = ["pillow"]
# ///
"""Planche de validation de l'AWP : vues de render_board.py, superposition à la photo de profil, vue 1P contre CS2.

`uv run assets/awp/compose_board.py <dossier des vues> <photo de profil> <capture CS2 au repos> <sortie.jpg>`
La photo de profil est ramenée au cadre de la vue gauche avec la correspondance de build_awp.py (PX_S, ancrage).
"""

import sys

from PIL import Image, ImageDraw

PX_S = 0.002865  # unités par pixel de la photo (build_awp.py)
SIDE_CENTER = (-0.9, 0.0)  # cadre de la vue gauche (render_board.py)
SIDE_SCALE = 10.2


def photo_in_frame(photo, size):
	"""Cette méthode permet de ramener la photo de profil dans le cadre (taille, centre, échelle) de la vue gauche."""
	w, h = size
	k = SIDE_SCALE / w  # unités par pixel du rendu
	cx, cz = SIDE_CENTER
	a = k / PX_S
	c = 2940 + (cx - w / 2 * k - 1.42) / PX_S
	f = 355 - cz / PX_S - (h / 2) * k / PX_S
	return photo.transform(size, Image.AFFINE, (a, 0, c, 0, a, f), resample=Image.BICUBIC, fillcolor=(255, 255, 255))


def label(im, text):
	"""Cette méthode permet d'écrire une étiquette lisible en haut à gauche d'une vue."""
	d = ImageDraw.Draw(im)
	d.rectangle((0, 0, 9 * len(text) + 12, 22), fill=(20, 20, 20))
	d.text((6, 5), text, fill=(255, 255, 255))
	return im


def main():
	"""Cette méthode permet d'assembler la planche (profils, superposition, trois-quarts, dessus, 1P nouveau / ancien / CS2)."""
	views, photo_path, cs2_path, out = sys.argv[1:5]
	g = Image.open(f"{views}/new_gauche.png").convert("RGB")
	photo = Image.open(photo_path).convert("RGB")
	ph = photo_in_frame(photo, g.size)
	over = Image.blend(g, ph, 0.5)
	rows = [
		label(g.copy(), "1 profil gauche"),
		label(over, "2 superposition photo L115A3 (50 %)"),
		label(Image.open(f"{views}/new_droite.png").convert("RGB"), "3 profil droit"),
		label(Image.open(f"{views}/new_dessus.png").convert("RGB"), "4 dessus"),
	]
	W = g.width
	small = []
	for name, path in (("5 trois-quarts", f"{views}/new_trois_quarts.png"), ("6 vue 1P, nouveau", f"{views}/new_1p.png"), ("7 vue 1P, ancien", f"{views}/old_1p.png"), ("8 CS2 Default, repos", cs2_path)):
		im = Image.open(path).convert("RGB")
		im = im.resize((W // 2, int(im.height * (W // 2) / im.width)))
		small.append(label(im, name))
	grid_h = sum(r.height for r in rows) + small[0].height + small[2].height
	board = Image.new("RGB", (W, grid_h), (255, 255, 255))
	y = 0
	for r in rows:
		board.paste(r, (0, y))
		y += r.height
	board.paste(small[0], (0, y))
	board.paste(small[1], (W // 2, y))
	y += small[0].height
	board.paste(small[2], (0, y))
	board.paste(small[3].resize((W // 2, small[2].height)), (W // 2, y))
	board.save(out, quality=90)


main()
