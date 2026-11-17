# /// script
# dependencies = ["numpy", "pillow", "scipy"]
# ///
"""Gabarit d'illustration de la M9 (#505) : silhouette exacte de la lame, à donner à un modèle d'image pour qu'il
dessine un skin illustré aux bonnes proportions (même méthode que l'AWP, `assets/awp/skins/gabarit.py`).

Le gabarit montre la lame comme le joueur la voit en 1P : la face droite du couteau, tenu tranchant en haut, soit la
toile de profil retournée de haut en bas (pointe à gauche, tranchant en haut, dents du dos en bas, garde à droite).
Lue sans distinction de face, l'illustration paraît aussi à l'endroit (en miroir) sur la face gauche.

`uv run assets/m9/skins/gabarit.py <cuisson> <cartes_origine> <dossier> [largeur] [hauteur]` écrit :
- `gabarit_masque.png` : lame noire sur blanc, trou et creux des dents en blanc (image de contrôle à joindre au modèle) ;
- `gabarit_annote.png` : la même, avec le fil d'acier nu, la marge du cadre, la zone vue en 1P et le sens de la lame.
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

FRAME = 0.012  # cadre sombre posé par le skin le long du contour (unités) : rien d'important dessous
FIL = 0.045  # fil repoli en acier nu au-dessus du tranchant (unités, cf. `Knife.edge`) : non peint
FOCUS = (-1.05, 0.22)  # talon de la lame, du trou exclu à la garde : ce que le joueur voit le plus en 1P (t, unités)
GROOVE = (-1.03, -0.16, 0.02)  # arête basse de la gouttière (t début, t fin, h) : trait sombre du maillage


class Gabarit:
	"""La correspondance entre la toile de profil de la M9 (pixels de `common.Knife`) et un gabarit w x h retourné de
	haut en bas : lame centrée sur 92 % de la largeur."""

	def __init__(self, kn, w=2520, h=1080):
		"""Cette méthode permet de calculer l'échelle et le décalage qui placent la lame dans le gabarit w x h."""
		self.kn, self.w, self.h = kn, w, h
		rows = np.where(kn.sil.any(1))[0]
		self.c0, self.c1 = kn.x0, kn.x1
		self.r0, self.r1 = rows.min(), rows.max()
		self.scale = 0.92 * w / (self.c1 - self.c0)
		self.ox = (w - (self.c1 - self.c0) * self.scale) / 2
		self.oy = (h - (self.r1 - self.r0) * self.scale) / 2

	def to_gab(self, cx, cy):
		"""Cette méthode permet de convertir des pixels de toile (x, y) en pixels du gabarit (retournement vertical)."""
		return (np.asarray(cx) - self.c0) * self.scale + self.ox, (self.r1 - np.asarray(cy)) * self.scale + self.oy

	def from_gab(self):
		"""Cette méthode permet d'obtenir, pour chaque pixel du gabarit, sa position (x, y) sur la toile de profil."""
		gy, gx = np.mgrid[0 : self.h, 0 : self.w].astype(np.float32)
		return (gx - self.ox) / self.scale + self.c0, self.r1 - (gy - self.oy) / self.scale

	def pull(self, arr, order=1):
		"""Cette méthode permet de lire un tableau de toile (scalaire par pixel) sur chaque pixel du gabarit."""
		cx, cy = self.from_gab()
		return ndimage.map_coordinates(arr.astype(np.float32), [cy, cx], order=order, mode="constant", cval=0)

	def mask(self):
		"""Cette méthode permet d'obtenir le masque du gabarit (vrai dans la lame, trou et creux des dents exclus)."""
		return self.pull(self.kn.sil) > 0.5

	def fil(self):
		"""Cette méthode permet d'obtenir, sur la toile, la bande du fil en acier nu (hauteur FIL au-dessus du
		tranchant, mesurée colonne par colonne)."""
		kn = self.kn
		y = np.arange(kn.hpx)[:, None]
		low = np.where(kn.sil, y, -1).max(0)  # ligne du tranchant (bas de la toile) à chaque abscisse
		return kn.sil & (low[None, :] - y < FIL * common.S)


def main():
	"""Cette méthode permet d'écrire le masque et le gabarit annoté de la lame de la M9."""
	bake_dir, orig_dir, out = sys.argv[1:4]
	w = int(sys.argv[4]) if len(sys.argv) > 4 else 2520
	h = int(sys.argv[5]) if len(sys.argv) > 5 else 1080
	os.makedirs(out, exist_ok=True)
	kn = common.Knife(bake_dir, orig_dir)
	g = Gabarit(kn, w, h)
	inside = g.mask()
	Image.fromarray(np.where(inside, 0, 255).astype(np.uint8)).save(os.path.join(out, "gabarit_masque.png"))

	# gabarit annoté : lame grise, cadre plus sombre, fil d'acier hachuré, zone 1P encadrée, gouttière en tirets
	frame = inside & (g.pull(kn.dist) < FRAME)
	fil = inside & (g.pull(g.fil()) > 0.5)
	rgb = np.full((h, w, 3), 255, np.uint8)
	rgb[inside] = (200, 200, 205)
	rgb[frame] = (120, 120, 130)
	yy, xx = np.mgrid[0:h, 0:w]
	rgb[fil] = (165, 185, 205)
	rgb[fil & ((xx + yy) % 14 < 4)] = (90, 110, 140)
	img = Image.fromarray(rgb)
	d = ImageDraw.Draw(img)
	try:
		f = ImageFont.truetype("C:/Windows/Fonts/bahnschrift.ttf", int(h * 0.028))
	except OSError:
		f = ImageFont.load_default()

	def at(t, hh):
		"""Cette méthode permet de convertir une position du repère du couteau (t, h) en pixels du gabarit."""
		cx, cy = common.to_px(t, hh)
		return tuple(float(c) for c in g.to_gab(cx, cy))

	t0, t1 = GROOVE[0], GROOVE[1]
	gx0, gyg = at(t0, GROOVE[2])
	gx1, _ = at(t1, GROOVE[2])
	for x in np.arange(gx0, gx1, 22):
		d.line([(x, gyg), (min(x + 11, gx1), gyg)], fill=(60, 60, 70), width=2)
	fx0, _ = at(FOCUS[0], 0)
	fx1, _ = at(FOCUS[1], 0)
	top = g.oy - 12
	bottom = g.oy + (g.r1 - g.r0) * g.scale + 12
	d.rectangle([fx0, top, fx1, bottom], outline=(230, 120, 0), width=4)
	d.text((fx0, bottom + 8), "MAIN SUBJECT HERE: seen the most in first person", fill=(230, 120, 0), font=f)
	d.text((20, top - 50), "<- TIP", fill=(20, 20, 20), font=f)
	d.text((w - 20, top - 50), "GUARD / HANDLE ->", fill=(20, 20, 20), font=f, anchor="ra")
	d.text((20, h - 120), "top edge, hatched blue: bare steel cutting edge, not painted", fill=(60, 80, 120), font=f)
	d.text((20, h - 85), "dark band: border painted by the game, keep empty  |  white: hole and saw teeth", fill=(80, 80, 80), font=f)
	d.text((20, h - 50), "dashed: faint groove line on the blade, keep eyes and faces off it", fill=(80, 80, 80), font=f)
	img.save(os.path.join(out, "gabarit_annote.png"))
	print(f"[gabarit] {w}x{h}, lame {(g.c1 - g.c0) * g.scale:.0f} x {(g.r1 - g.r0) * g.scale:.0f} px -> {out}")


if __name__ == "__main__":
	main()
