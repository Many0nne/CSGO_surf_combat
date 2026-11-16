"""MAQUIS (#417) : tactique / camo peint à la main. Camouflage sable, olive et brun posé en coups de pinceau allongés
le long de l'arme (bords effrangés, traînées de brosse), quelques petites taches sombres, peinture mate écaillée jusqu'au
polymère noir. Le motif est continu d'une pièce à l'autre (lunette et canon compris). Toile de jute enroulée sur le
canon et encoches de décompte grattées sur l'arrière de la crosse.
"""

import numpy as np

from common import X, chip, fbm
from common import paint as ink

SAND = (0.50, 0.44, 0.31)
OLIVE = (0.24, 0.27, 0.14)
BROWN = (0.32, 0.21, 0.12)
DARK = (0.10, 0.085, 0.065)
BLACK = (0.05, 0.05, 0.045)
JUTE = (0.46, 0.38, 0.25)
SCRATCH = (0.78, 0.75, 0.68)
STRETCH = np.array([0.35, 1.0, 1.0])  # coups de pinceau étirés le long du canon


def strokes(m, seed, level, cell):
	"""Cette méthode permet de calculer un masque de coups de pinceau (0 à 1) : bruit étiré et déformé, bord effrangé."""
	p = m.p * STRETCH
	warp = np.stack([fbm(p, cell * 0.8, seed + k, 2) for k in range(3)], 1) * cell * 0.35
	f = fbm(p + warp, cell, seed + 7, 4)
	fray = 0.06 * fbm(p * np.array([0.25, 1, 1]), 0.012, seed + 11, 2)  # traînées de brosse le long du coup
	return np.clip((f + fray - level) * 18, 0, 1)


def camo(m, sel, seed=101):
	"""Cette méthode permet de peindre le camouflage mat sur une sélection de texels."""
	sel = np.asarray(sel, float)
	brush = fbm(m.p * np.array([0.2, 1, 1]), 0.01, seed + 3, 2)  # stries de pinceau dans chaque teinte
	ink(m, sel, SAND, 0.78, 0.0)
	m.color *= (1 + 0.06 * brush * sel)[:, None]
	ink(m, sel * strokes(m, seed, 0.08, 0.55), OLIVE, 0.8, 0.0)
	ink(m, sel * strokes(m, seed + 20, 0.28, 0.45), BROWN, 0.8, 0.0)
	ink(m, sel * strokes(m, seed + 40, 0.42, 0.22), DARK, 0.8, 0.0)  # petites taches sombres
	m.height += 0.0003 * brush * sel


def draw(cv):
	"""Cette méthode permet de graver les encoches de décompte (quatre et une barrée, puis deux) sur la toile de profil."""
	x0, y0, h = 3395, 455, 46
	for i in range(4):
		cv.line("scratch", [(x0 + i * 13, y0), (x0 + i * 13 + 3, y0 + h)], 4)
	cv.line("scratch", [(x0 - 8, y0 + h - 6), (x0 + 50, y0 + 6)], 4)
	for i in range(2):
		cv.line("scratch", [(x0 + 70 + i * 13, y0), (x0 + 73 + i * 13, y0 + h)], 4)


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre MAQUIS sur les quatre matériaux de l'AWP."""
	draw(cv)
	w = maps["WOOD"]
	w.height *= 0.6
	camo(w, np.ones(len(w.p), bool))
	chip(w, -0.3, 103, BLACK, rough=0.7, metal=0.0)
	ink(w, cv.sample("scratch", w, blur=0.4), SCRATCH, 0.6, 0.0)

	a = maps["METAL_A"]
	ink(a, a.is_("Magazine") | a.is_("Trigger"), BLACK, 0.6, 0.0)

	b = maps["METAL_B"]
	x, z = b.p[:, 0], b.p[:, 2]
	barrel, fit = b.is_("Barrel"), b.is_("Fittings")
	camo(b, barrel & (x > -4.95) & (x < -0.7))
	chip(b, -0.35, 105, (0.30, 0.30, 0.31), rough=0.4, sel=barrel)
	# toile de jute enroulée : trame croisée, en relief
	wrap = barrel & (x > -4.3) & (x < -3.55)
	ang = np.arctan2(b.p[:, 2], b.p[:, 1])
	weave = np.sin(x / 0.018 * np.pi) * np.sin(ang * 40)
	frayed = 0.08 * fbm(b.p, 0.02, 107, 2)
	ink(b, wrap, JUTE, 0.9, 0.0)
	b.color[wrap] *= (0.72 + 0.28 * np.abs(weave[wrap]) + frayed[wrap])[:, None]
	b.height[wrap] = 0.0012 * np.abs(weave[wrap]) + 0.002
	mount = fit & (z > 0.14) & (x > X(2300)) & (x < X(2640))
	camo(b, mount)

	s = maps["SCOPE"]
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - 0.504
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	tx = X(2450)
	turret = ((np.hypot(xs - tx, y) < 0.09) & (zs > 0.142)) | ((np.hypot(xs - tx, zs) < 0.12) & (np.abs(y) > 0.142))
	ring = (xs > X(2700)) & (xs < X(2790))
	camo(s, ~inside & ~turret & ~ring)
	chip(s, -0.4, 109, BLACK, rough=0.5, metal=0.0, sel=~inside & ~turret & ~ring)
