"""TARTAN : châssis habillé d'un tissu écossais sombre. Sett inventé pour le jeu (vert sapin et bleu nuit séparés de
noir, filets rouge et ocre), en carreaux réguliers alignés sur l'arme, tissé en sergé (fines diagonales en relief).
Plaque ovale en laiton gravée sur l'avant de la crosse (vue en 1P). Lunette et chargeur vert sapin, métaux d'origine.
"""

import numpy as np

from common import X, chip, font, mt_px, mt_py
from common import paint as ink

# teintes claires exprès : sous l'éclairage du jeu, un tissu à 0,25 sur le canal dominant tombait au noir en 1P
K = (0.07, 0.075, 0.08)
G = (0.13, 0.42, 0.25)
B = (0.09, 0.16, 0.42)  # bleu nuit (Cycles et le ciel du jeu le tirent vers le lavande)
R = (0.80, 0.13, 0.10)
Y = (0.92, 0.74, 0.26)
# demi-sett (couleur, nombre de fils), répété en miroir ; filets fins d'au moins 3 fils pour couvrir 2 texels
HALF = [(K, 10), (G, 20), (K, 3), (G, 3), (K, 3), (Y, 2), (K, 10), (B, 16), (R, 2), (B, 16), (K, 3)]
THREAD = 0.0055  # largeur d'un fil en unités (sett complet ~0,93 : de grands carreaux, filets d'au moins 2 texels)
BRASS = (0.78, 0.58, 0.28)
FIR = (0.13, 0.34, 0.20)
PLATE = ((2590, 440), 62, 34)  # centre (px photo), demi-axes de la plaque


def sett():
	"""Cette méthode permet de dérouler le sett complet (demi-sett puis son miroir) en une couleur par fil."""
	half = [c for c, n in HALF for _ in range(n)]
	return np.array(half + half[-2:0:-1])


def stripes(t):
	"""Cette méthode permet d'obtenir la couleur des fils à la coordonnée t (unités) le long d'une direction du tissu."""
	threads = sett()
	return threads[np.floor(t / THREAD).astype(int) % len(threads)]


def cloth(m, sel):
	"""Cette méthode permet de tisser le tartan sur une sélection : chaîne le long de l'arme, trame sur la hauteur des flancs
	(ou la largeur des dessus), couleurs mêlées à parts égales et sergé en relief."""
	x, y, z = m.p[sel, 0], m.p[sel, 1], m.p[sel, 2]
	flat = np.abs(m.n[sel, 2]) > 0.7  # dessus et dessous : la trame court sur la largeur
	v = np.where(flat, y + 0.3, z)
	warp, weft = stripes(x - X(2430)), stripes(v + 1.0)  # calé sur le joint : les carreaux le traversent sans décalage
	col = 0.5 * (warp + weft)
	twill = np.sin((x + v) / 0.011 * np.pi)  # diagonales du sergé (~2,5 texels)
	lum = 1 + 0.10 * twill
	m.color[sel] = col * lum[:, None] * (0.55 + 0.45 * np.clip(m.ao[sel], 0, 1))[:, None]
	m.rough[sel] = 0.88
	m.metal[sel] = 0.0
	m.height[sel] = 0.0004 * twill


def plate(cv):
	"""Cette méthode permet de tracer la plaque ovale de laiton et sa gravure (filet et nom) sur la toile de profil."""
	(cx, cy), rx, ry = PLATE
	cv.poly("plate", ellipse(cx, cy, rx, ry))
	cv.poly("engrave", ellipse(cx, cy, rx - 7, ry - 7), width=2.5)
	cv.text("engrave", "TARTAN", (cx, cy + 1), 15, lambda s: font("bahnschrift.ttf", s, "SemiBold Condensed"))


def ellipse(cx, cy, rx, ry, n=72):
	"""Cette méthode permet d'obtenir le contour d'une ellipse en points de la photo."""
	a = np.linspace(0, 2 * np.pi, n, endpoint=False)
	return list(zip(cx + rx * np.cos(a), cy + ry * np.sin(a)))


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre TARTAN sur les quatre matériaux de l'AWP."""
	plate(cv)
	w = maps["WOOD"]
	cloth(w, np.ones(len(w.p), bool))
	side = np.abs(w.n[:, 1]) > 0.5  # la plaque n'est rivée que sur les flancs
	pl = cv.sample("plate", w, blur=0.3) * side
	ink(w, pl, BRASS, 0.35, 1.0)
	w.height += 0.0012 * pl
	eng = cv.sample("engrave", w, blur=0.3) * pl
	ink(w, eng, (0.22, 0.16, 0.07), 0.6, 1.0)
	w.height -= 0.0006 * eng
	# rivets aux deux bouts de la plaque
	(cx, cy), rx, _ = PLATE
	px, py = mt_px(w.p[:, 0]), mt_py(w.p[:, 2])
	for dx in (-rx + 14, rx - 14):
		riv = side & (np.hypot(px - cx - dx, py - cy) < 4.5)
		ink(w, riv, BRASS, 0.3, 1.0)

	a = maps["METAL_A"]
	mag = a.is_("Magazine")
	ink(a, mag & (a.p[:, 2] > -0.76), FIR, 0.5, 0.0)
	chip(a, -0.45, 91, (0.40, 0.40, 0.42), rough=0.35, sel=mag)

	s = maps["SCOPE"]
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - 0.504
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	tx = X(2450)
	turret = ((np.hypot(xs - tx, y) < 0.09) & (zs > 0.142)) | ((np.hypot(xs - tx, zs) < 0.12) & (np.abs(y) > 0.142))
	ring = (xs > X(2700)) & (xs < X(2790))
	tube = ~inside & ~turret & ~ring
	ink(s, tube, FIR, 0.5, 0.0)
	ink(s, tube & (np.abs(xs - X(2655)) < 0.012), R, 0.5, 0.0)  # filet rouge du sett devant la bague
	ink(s, tube & (np.abs(xs - X(2675)) < 0.006), Y, 0.5, 0.0)
	chip(s, -0.45, 93, (0.40, 0.40, 0.42), rough=0.35, sel=tube)
