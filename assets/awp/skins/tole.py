"""TÔLE LARMÉE (#482) : châssis en aluminium antidérapant satiné. Larmes en relief (lentilles allongées) en grille
régulière, orientées à 45° et croisées d'une maille à l'autre, sur tout le châssis (flancs, dessus et dessous), continues à
travers le joint. Deux rangs de rivets bombés de part et d'autre du joint garde-main / crosse, marquage d'usine imprimé
à l'encre sur l'avant de la crosse (vu en 1P). Chargeur en aluminium lisse, tube de lunette anodisé noir.
"""

import numpy as np

from common import JOINT, X, fbm, font, mt, mt_px, mt_py
from common import paint as ink

ALU = (0.66, 0.67, 0.69)
ANOD = (0.07, 0.07, 0.075)
INK = (0.05, 0.07, 0.12)
P = 36.0  # pas de la grille des larmes (px photo, ~24 texels) : à 30, elles disparaissaient de profil
L, WD = 0.80, 0.12  # longueur d'une larme et demi-largeur en son milieu, en pas (~5 texels de large)
TOP = 363  # dessus du châssis (px photo)
RIVET_R, RIVET_DY = 6.0, 34.0  # rivets du joint : rayon et écart (px photo)


def tread(px, v):
	"""Cette méthode permet de calculer le relief des larmes (0 à 1) en un point (px, v en px photo) : une larme par maille,
	inclinée à +45° ou -45° en damier."""
	u, w = (px - JOINT) / P, (v - TOP) / P
	i, j = np.floor(u), np.floor(w)
	cx, cy = u - i - 0.5, w - j - 0.5
	sgn = np.where(np.mod(i + j, 2) == 0, 1.0, -1.0)
	s = (cx + sgn * cy) / np.sqrt(2)  # le long de la larme
	t = (cx - sgn * cy) / np.sqrt(2)  # en travers
	k = np.clip(1 - (2 * s / L) ** 2, 0, 1)
	half = WD * k
	return np.sqrt(np.clip(1 - (t / np.maximum(half, 1e-6)) ** 2, 0, 1)) * np.sqrt(k)


def marking(cv):
	"""Cette méthode permet de tracer le marquage d'usine (alliage, épaisseur, norme) sur l'avant de la crosse."""
	f = lambda s: font("bahnschrift.ttf", s, "Bold Condensed")  # noqa: E731
	cv.text("mark", "AlMg3 · 5754", (2592, 438), 18, f)
	cv.text("mark", "3/4,5 · LOT 0482", (2592, 464), 11, f)


def plate(m, cv):
	"""Cette méthode permet de poser la tôle sur le châssis : aluminium satiné, larmes en relief plus polies au sommet,
	rivets du joint et marquage imprimé."""
	px, py = mt_px(m.p[:, 0]), mt_py(m.p[:, 2])
	flat = np.abs(m.n[:, 2]) > 0.7
	v = np.where(flat, TOP + m.p[:, 1] / mt.PX_S, py)
	h = tread(px, v)
	tone = 1 + 0.04 * fbm(m.p, 0.3, 161, 3)
	lit = 1 + 0.10 * h  # sommet des larmes usé, plus clair
	m.color[:] = np.outer(tone * lit, ALU) * (0.6 + 0.4 * np.clip(m.ao, 0, 1))[:, None]
	m.metal[:] = 1.0
	m.rough[:] = 0.42 - 0.14 * h + 0.03 * fbm(m.p, 0.02, 163, 2)
	m.height[:] = 0.0020 * h
	side = np.abs(m.n[:, 1]) > 0.6
	# rivets bombés : un rang de chaque côté du joint, sur les flancs
	rv = np.zeros(len(px))
	for cx in (JOINT - 12, JOINT + 12):
		dy = (py - TOP - RIVET_DY / 2) / RIVET_DY
		d = np.hypot(px - cx, (dy - np.round(dy)) * RIVET_DY)
		row = side & (py > TOP + 8) & (py < 530)
		rv = np.maximum(rv, (row & (d < RIVET_R)) * np.sqrt(np.clip(1 - (d / RIVET_R) ** 2, 0, 1)))
		ring = row & (d >= RIVET_R) & (d < RIVET_R + 1.6)  # ombre au pied du rivet : sans elle, il se fondait dans la tôle
		m.color[ring] *= 0.45
		m.height[ring] -= 0.0004
	on = rv > 0
	m.height[on] = 0.0022 * rv[on]
	m.rough[on] = 0.3
	m.color[on] = np.outer(0.85 + 0.2 * rv[on], ALU)
	mk = cv.sample("mark", m, blur=0.5) * side * np.clip(0.75 + 0.5 * fbm(m.p, 0.02, 165, 2), 0, 1)
	ink(m, mk * 0.9, INK, 0.7, 0.0)


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre TÔLE LARMÉE sur les quatre matériaux de l'AWP."""
	marking(cv)
	plate(maps["WOOD"], cv)

	a = maps["METAL_A"]
	mag = a.is_("Magazine") & (a.p[:, 2] > -0.76)
	ink(a, mag, ALU, 0.38, 1.0)

	s = maps["SCOPE"]
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - mt.SCOPE_Z
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	tx = X(2450)
	turret = ((np.hypot(xs - tx, y) < 0.09) & (zs > 0.142)) | ((np.hypot(xs - tx, zs) < 0.12) & (np.abs(y) > 0.142))
	ring = (xs > X(2700)) & (xs < X(2790))
	tube = ~inside & ~turret & ~ring
	ink(s, tube, ANOD, 0.4, 1.0)
	ink(s, tube & (np.abs(xs - X(2655)) < 0.012), ALU, 0.35, 1.0)  # bague d'aluminium devant la bague de grossissement
