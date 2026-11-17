"""CANNAGE (#482) : panneaux de rotin blond tressé (cannage à huit pans, comme une chaise de bistrot) tendus dans un
cadre laqué noir satiné qui suit le contour du châssis et le tour du pontet et du trou de pouce. Paires de brins
horizontales et verticales, brins diagonaux qui passent aux coins des trous ; à chaque croisement, le brin du dessus
alterne en damier. Le tressage court d'une pièce à l'autre sans décalage au joint. Lunette et chargeur laqués noirs,
deux ligatures de rotin sur le tube de la lunette.
"""

import numpy as np
from PIL import Image

from common import JOINT, X, band, chassis, chip, fbm, mt, mt_px, mt_py, outline, zone
from common import paint as ink

CANE = (0.80, 0.63, 0.38)  # rotin blond, assez clair pour rester lisible sous l'éclairage du jeu
LACQUER = (0.045, 0.045, 0.05)
P = 56.0  # pas du tressage (px photo, ~36 texels) : un trou à huit pans par maille ; à 34, les trous faisaient un panneau perforé
FRAME = 16.0  # largeur du cadre laqué autour des panneaux (px photo)
TOP = 363  # dessus du châssis (px photo)
HOLE, CUT = 0.32, 0.54  # demi-côté du trou et coupe de ses coins (|x| + |y|), en pas


def panels(cv):
	"""Cette méthode permet de tracer la zone cannée (le châssis moins le cadre, pontet et trou de pouce exclus) et la
	gorge sombre où le rotin s'enfonce sous le cadre."""
	holes = [outline("GUARD_HOLE"), outline("THUMBHOLE")]
	dist = zone(cv, chassis(), holes)
	mask = Image.fromarray(((dist > FRAME) * 255).astype(np.uint8))
	for img in cv.layer("cane"):
		img.paste(255, (0, 0), mask)
	band(cv, "groove", chassis(), holes, FRAME - 1.5, FRAME + 1.5)


def weave(px, py):
	"""Cette méthode permet de calculer le tressage en un point de profil : présence de rotin (0 ou 1), éclairage du brin
	(arrondi, 0 à 1), teinte selon le sens du brin et relief. Trous centrés sur les mailles ; à chaque nœud de la grille,
	les deux brins diagonaux se croisent en X par-dessus les paires et coupent les coins des quatre trous (huit pans)."""
	u, v = (px - JOINT) / P, (py - TOP) / P
	i, j = np.floor(u), np.floor(v)
	cx, cy = u - i - 0.5, v - j - 0.5  # -0,5 à 0,5 autour du centre du trou
	ax, ay = np.abs(cx), np.abs(cy)
	nx, ny = ax - 0.5, ay - 0.5  # depuis le nœud le plus proche (symétrie : un seul quadrant)
	dd = (2 * HOLE - CUT) / np.sqrt(2)  # demi-largeur d'un brin diagonal : couvre juste le coin coupé du trou
	acr_d = np.abs(nx - ny) / np.sqrt(2) / dd
	square = (ax < HOLE) & (ay < HOLE)
	diag = (acr_d < 1) & ((ax + ay >= CUT) | ~square)
	hole = square & ~diag
	horiz, vert = (ay >= HOLE) & ~diag, (ax >= HOLE) & ~diag
	node = horiz & vert  # croisement des paires sous le X : le brin du dessus alterne en damier
	ni, nj = i + (cx > 0), j + (cy > 0)
	h_on_top = np.mod(ni + nj, 2) == 0
	horiz &= ~node | h_on_top
	vert &= ~node | ~h_on_top
	w = (0.5 - HOLE) / 2  # largeur d'un brin d'une paire (en pas)
	# position en travers du brin (-1 à 1) : deux brins par paire, séparés sur la limite de maille
	acr_h = (ay - (0.5 - w)) / w
	acr_v = (ax - (0.5 - w)) / w
	acr = np.where(diag, acr_d, np.where(horiz, acr_h, acr_v))
	light = np.sqrt(np.clip(1 - acr**2, 0, 1))
	tone = np.where(diag, 1.12, np.where(horiz, 1.0, 0.84)) * np.where(np.abs(acr) > 0.82, 0.55, 1.0)  # fente entre brins
	height = 0.0010 * light + 0.0005 * diag
	return ~hole, light, tone, height


def chassis_paint(m, cv):
	"""Cette méthode permet de laquer tout le châssis en noir satiné puis d'y tendre le cannage sur les flancs."""
	ink(m, 1.0, LACQUER, 0.38, 0.0)
	m.height[:] = 0.0
	chip(m, -0.55, 151, (0.30, 0.20, 0.10), rough=0.6, metal=0.0)  # bois brun sous la laque, sur quelques arêtes
	side = np.abs(m.n[:, 1]) > 0.6
	px, py = mt_px(m.p[:, 0]), mt_py(m.p[:, 2])
	cane, light, tone, height = weave(px, py)
	k = cv.sample("cane", m, blur=0.4) * side
	fibre = 1 + 0.05 * fbm(m.p, 0.02, 153, 2)
	col = np.outer(tone * (0.62 + 0.38 * light) * fibre, CANE) * (0.6 + 0.4 * np.clip(m.ao, 0, 1))[:, None]
	a = k * cane
	m.color = m.color * (1 - a[:, None]) + col * a[:, None]
	m.rough = m.rough * (1 - a) + (0.32 + 0.12 * (1 - light)) * a
	m.metal = m.metal * (1 - a)
	m.height += a * height - 0.002 * k * ~cane  # le fond des trous s'enfonce
	pit = k * ~cane  # fond des trous : noyer sombre ; en noir, les trous dominaient et faisaient un panneau perforé
	ink(m, pit, (0.12, 0.07, 0.04), 0.75, 0.0)
	gr = cv.sample("groove", m, blur=0.4) * side
	m.color *= (1 - 0.6 * gr)[:, None]
	m.height -= 0.0008 * gr


def binding(s, sel, center):
	"""Cette méthode permet de poser une ligature de rotin enroulée en hélice autour du tube de la lunette."""
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - mt.SCOPE_Z
	on = sel & (np.abs(xs - center) < 0.035)
	th = np.arctan2(zs, y)
	turn = (xs - center) / 0.0105 + th / (2 * np.pi) * 2  # brins de ~7 texels, légèrement inclinés
	acr = 2 * (turn - np.floor(turn)) - 1
	light = np.sqrt(np.clip(1 - acr**2, 0, 1))
	col = np.outer(0.62 + 0.38 * light, CANE)
	s.color[on] = col[on] * (0.6 + 0.4 * np.clip(s.ao[on], 0, 1))[:, None]
	s.rough[on] = 0.36
	s.metal[on] = 0.0
	s.height[on] = 0.0012 * light[on]


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre CANNAGE sur les quatre matériaux de l'AWP."""
	panels(cv)
	chassis_paint(maps["WOOD"], cv)

	a = maps["METAL_A"]
	mag = a.is_("Magazine") & (a.p[:, 2] > -0.76)
	ink(a, mag, LACQUER, 0.38, 0.0)

	s = maps["SCOPE"]
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - mt.SCOPE_Z
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	tx = X(2450)
	turret = ((np.hypot(xs - tx, y) < 0.09) & (zs > 0.142)) | ((np.hypot(xs - tx, zs) < 0.12) & (np.abs(y) > 0.142))
	ring = (xs > X(2700)) & (xs < X(2790))
	tube = ~inside & ~turret & ~ring
	ink(s, tube, LACQUER, 0.38, 0.0)
	for c in (X(2200), X(2640)):
		binding(s, tube, c)
