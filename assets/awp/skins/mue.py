"""MUE (#417) : organique. Toute l'arme se couvre d'écailles de serpent imbriquées (losanges en quinconce, chacun relevé
vers l'arrière comme une tuile, sillons sombres) noir verdâtre à reflets ; une chaîne de grands losanges cramoisis
cerclés d'orange court sur les flancs du châssis, écaille par écaille, et le dessous prend les écailles crème d'un
ventre. Plaque de couche, busc et culasse d'origine.
"""

import numpy as np

from common import X, outline, zone
from common import paint as ink

DORSAL = np.array((0.22, 0.32, 0.25))  # posé en métal : reflet sombre sans voile gris
CRIMSON = np.array((0.46, 0.05, 0.035))
RIM = np.array((0.80, 0.34, 0.05))
BELLY = np.array((0.66, 0.58, 0.42))
CW, CH = 0.064, 0.044  # taille d'une écaille : le long de l'arme, en travers (unités monde)


def hash2(i, j, seed):
	"""Cette méthode permet de tirer une valeur pseudo-aléatoire dans [0, 1] par écaille (indices entiers du quinconce)."""
	h = (i * 73856093) ^ (j * 19349663) ^ (seed * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def lattice(a, b):
	"""Cette méthode permet de placer chaque point dans le quinconce d'écailles (a le long de l'arme, b en travers) :
	indices de l'écaille, position dans l'écaille (0 à 1 de l'avant vers l'arrière) et distance au bord, et son centre."""
	s, t = a / CW + b / CH, a / CW - b / CH
	i, j = np.floor(s), np.floor(t)
	fs, ft = s - i, t - j
	edge = np.minimum.reduce([fs, 1 - fs, ft, 1 - ft])
	back = (fs + ft) / 2  # 0 à l'avant de l'écaille (vers la bouche), 1 à l'arrière
	ca = ((i + 0.5) + (j + 0.5)) / 2 * CW
	cb = ((i + 0.5) - (j + 0.5)) / 2 * CH
	return i.astype(np.int64), j.astype(np.int64), back, edge, ca, cb


def coords(m, sel, cyl=None):
	"""Cette méthode permet de choisir les coordonnées de pose des écailles : sur la face dominante du texel (x, z ou
	x, y), ou autour d'un axe (canon, lunette : cyl = hauteur de l'axe) pour une pièce de révolution."""
	p, n = m.p[sel], np.abs(m.n[sel])
	if cyl is not None:
		ang = np.arctan2(p[:, 2] - cyl, p[:, 1])
		return -p[:, 0], ang * 0.12, np.zeros(len(p), bool)
	ax = np.argmax(n, axis=1)
	a = np.where(ax == 0, p[:, 1], -p[:, 0])  # -x : l'avant de l'écaille regarde la bouche
	b = np.where(ax == 2, p[:, 1], p[:, 2])
	return a, b, ax == 1


def scales(m, sel, seed, cyl=None, cv=None):
	"""Cette méthode permet de poser les écailles imbriquées sur une sélection ; avec une toile, chaque écaille de flanc
	prend la couleur du motif lue en son centre (losanges cramoisis), et les écailles du dessous celle du ventre."""
	sel = np.asarray(sel, bool)
	a, b, side = coords(m, sel, cyl)
	i, j, back, edge, ca, cb = lattice(a, b)
	tint = 0.8 + 0.4 * hash2(i, j, seed)
	groove = np.clip(edge / 0.07, 0, 1)  # 0 dans le sillon
	m.height[sel] = 0.0018 * back * groove + 0.0004 * groove
	shade = (0.3 + 0.7 * groove) * (0.75 + 0.25 * back)
	col = np.outer(tint, DORSAL)
	metal = np.ones(len(a))
	if cv is not None:
		right = m.n[sel][:, 1] > 0.35
		rim = cv.sample_at("rim", -ca, cb, right) * side
		crim = cv.sample_at("crimson", -ca, cb, right) * side
		col = col * (1 - rim[:, None]) + np.outer(rim * tint, RIM)
		col = col * (1 - crim[:, None]) + np.outer(crim * tint, CRIMSON)
		belly = np.clip((-m.n[sel][:, 2] - 0.55) * 4, 0, 1)
		col = col * (1 - belly[:, None]) + np.outer(belly * tint, BELLY)
		metal = 1 - belly
	m.color[sel] = col * shade[:, None]
	m.rough[sel] = 0.36 + 0.2 * (1 - groove)
	m.metal[sel] = metal


def diamonds(cv):
	"""Cette méthode permet de tracer la chaîne de grands losanges jointifs le long des flancs du châssis."""
	path = [(1720, 428), (2420, 432), (2880, 448), (3150, 478), (3560, 505)]
	for (x0, y0), (x1, y1) in zip(path, path[1:]):
		n = max(1, round((x1 - x0) / 120))
		for k in range(n):
			t = (k + 0.5) / n
			cx, cy = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
			hw, hh = (x1 - x0) / n / 2 + 2, 50
			cv.poly("rim", [(cx - hw, cy), (cx, cy - hh), (cx + hw, cy), (cx, cy + hh)])
			cv.poly("crimson", [(cx - hw * 0.62, cy), (cx, cy - hh * 0.62), (cx + hw * 0.62, cy), (cx, cy + hh * 0.62)])
	holes = [outline("GUARD_HOLE"), outline("THUMBHOLE")]
	keep = (zone(cv, outline("STOCK"), holes) > 6) | (zone(cv, outline("HANDGUARD")) > 6)
	cv.clip("rim", keep)
	cv.clip("crimson", keep)


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre MUE sur les quatre matériaux de l'AWP."""
	diamonds(cv)
	w = maps["WOOD"]
	scales(w, np.ones(len(w.p), bool), 121, cv=cv)

	a = maps["METAL_A"]
	scales(a, ~a.is_("Bolt") & ~a.is_("Handle"), 123)
	ink(a, a.is_("Handle"), DORSAL * 0.6, 0.35, 1.0)

	b = maps["METAL_B"]
	x, z = b.p[:, 0], b.p[:, 2]
	fit = b.is_("Fittings")
	pad = fit & ((x > X(3555)) | ((z > -0.106) & (x > X(3190))))
	scales(b, b.is_("Barrel"), 125, cyl=0.0)
	ink(b, fit & ~pad, DORSAL * 0.6, 0.35, 1.0)

	s = maps["SCOPE"]
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - 0.504
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	scales(s, ~inside, 127, cyl=0.504)
