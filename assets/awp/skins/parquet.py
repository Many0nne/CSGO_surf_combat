"""PARQUET (#482) : châssis plaqué de chêne miel vitrifié, posé en bâtons rompus. Lames de même taille à 45° en rangées
qui courent le long de l'arme (zigzag régulier, continu à travers le joint garde-main / crosse), joints fins en creux,
une teinte un peu différente par lame et fil du bois le long de chaque lame. Marque au fer sur l'avant de la crosse
(vue en 1P). Métaux, lunette et chargeur d'origine.
"""

import numpy as np

from common import JOINT, X, Z, fbm, font, mt, mt_px, mt_py
from common import paint as ink

PX_S = mt.PX_S  # unités par px photo

OAK = (0.62, 0.42, 0.23)  # chêne miel : un non-métal sombre tombe au noir en jeu, viser ~0,4 et plus sur le canal dominant
BURN = (0.16, 0.08, 0.04)
BRASS = (0.78, 0.58, 0.28)
W, N = 26.0, 4  # largeur d'une lame (px photo, ~17 texels) et longueur en largeurs (lame de 96 x 24)
SEAM = 1.6  # demi-largeur d'un joint entre lames (px photo, ~2 texels en tout)
TOP = 363  # dessus du châssis (px photo) : une rangée de zigzag y commence


def herringbone(a, b):
	"""Cette méthode permet de situer chaque point dans le bâton rompu (coordonnées a, b en largeurs de lame, repère
	tourné de 45°) : identifiant de la lame, position le long de la lame (0 à N), en travers (0 à 1) et sens de la lame.
	Lames horizontales sur les cellules où (i - j) mod 2N < N, verticales sur les autres : le motif pave le plan."""
	i, j = np.floor(a), np.floor(b)
	fa, fb = a - i, b - j
	d = np.mod(i - j, 2 * N)
	band = np.floor((i - j) / (2 * N))
	horiz = d < N
	along = np.where(horiz, d + fa, (2 * N - 1 - d) + fb)
	across = np.where(horiz, fb, fa)
	ident = np.where(horiz, j * 7.31 + band * 3.17, i * 5.77 + band * 9.41 + 0.5)
	return ident, along, across, horiz


def plank_tone(ident):
	"""Cette méthode permet de donner à chaque lame une teinte fixe un peu plus claire ou plus foncée (lames triées)."""
	h = np.sin(ident * 12.9898 + 4.1) * 43758.5453
	return 0.80 + 0.28 * (h - np.floor(h))


def floor(m, cv):
	"""Cette méthode permet de poser le parquet sur tout le châssis : flancs en coordonnées de profil, dessus et dessous
	sur la largeur (le zigzag y continue), puis vitrification satinée et marque au fer."""
	px, py = mt_px(m.p[:, 0]), mt_py(m.p[:, 2])
	flat = np.abs(m.n[:, 2]) > 0.7
	v = np.where(flat, TOP + m.p[:, 1] / PX_S, py)
	x, y = (px - JOINT) / W, (v - TOP) / W
	ident, along, across, horiz = herringbone((x + y) / np.sqrt(2), (x - y) / np.sqrt(2))
	tone = plank_tone(ident)
	# fil du bois : veines le long de la lame, ondulées par un bruit propre à chaque lame
	t = np.where(horiz, m.p[:, 0] - m.p[:, 2], m.p[:, 0] + m.p[:, 2])  # coordonnée le long des lames (unités)
	q = across + 0.35 * fbm(np.stack([t * 0.4, ident, ident], 1), 0.25, 141, 2)
	vein = 0.5 + 0.5 * np.cos(q * 2 * np.pi * 3.0)
	grain = 1 - 0.22 * vein**4 - 0.05 * fbm(m.p, 0.03, 143, 2)
	m.color[:] = np.outer(tone * grain, OAK) * (0.55 + 0.45 * np.clip(m.ao, 0, 1))[:, None]
	m.rough[:] = 0.42 + 0.06 * vein
	m.metal[:] = 0.0
	m.height[:] = -0.00015 * vein**6
	# joints : bords de lame en travers (across) et bouts de lame (along), en creux et plus sombres
	ea = np.minimum(across, 1 - across) * W
	el = np.minimum(along, N - along) * W
	seam = np.clip((SEAM + 0.8 - np.minimum(ea, el)) / 0.8, 0, 1)
	m.color *= (1 - 0.55 * seam)[:, None]
	m.height -= 0.0006 * seam
	m.rough = m.rough * (1 - seam) + 0.8 * seam
	side = np.abs(m.n[:, 1]) > 0.6
	burn = cv.sample("brand", m, blur=0.5) * side
	ink(m, burn, BURN, 0.7, 0.0)
	m.height -= 0.0004 * burn


def brand(cv):
	"""Cette méthode permet de tracer la marque au fer de l'avant de la crosse : un cadre à pans coupés, le nom et l'essence."""
	cx, cy, hw, hh, c = 2590, 450, 78, 38, 11
	frame = [(cx - hw + c, cy - hh), (cx + hw - c, cy - hh), (cx + hw, cy - hh + c), (cx + hw, cy + hh - c),
		(cx + hw - c, cy + hh), (cx - hw + c, cy + hh), (cx - hw, cy + hh - c), (cx - hw, cy - hh + c)]
	cv.poly("brand", frame, width=4.5)
	f = lambda s: font("bahnschrift.ttf", s, "Bold Condensed")  # noqa: E731
	cv.text("brand", "PARQUET", (cx, cy - 8), 22, f)
	cv.text("brand", "CHÊNE · N°7", (cx, cy + 19), 12, f)


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre PARQUET sur le châssis de l'AWP (les autres matériaux gardent leurs cartes d'origine)."""
	brand(cv)
	floor(maps["WOOD"], cv)
	# vis du châssis en laiton (ce qui reste des garnitures hors montage de lunette et plaque de couche, cf. metal_b)
	b = maps["METAL_B"]
	x, z = b.p[:, 0], b.p[:, 2]
	fit = b.is_("Fittings")
	mount = fit & (z > 0.14) & (x > X(2300)) & (x < X(2640))
	pad = fit & ((x > X(3555)) | ((z > Z(392)) & (x > X(3190))))
	ink(b, fit & ~mount & ~pad, BRASS, 0.35, 1.0)
