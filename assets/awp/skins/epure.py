"""ÉPURE : l'AWP dessinée sur son propre plan. Papier bleu de tirage mat, quadrillage fin et quadrillage majeur plus
clairs, trait de contour blanc qui suit le châssis et le tour des trous, ligne d'axe mixte, cercles de centrage autour
des vis, chaîne de cotes sur le dessus (visible en 1P) et cartouche sur l'arrière de la crosse. Canon gradué, lunette
bleue à bouts blancs, chargeur bleu à talon blanc. Tous les tracés sont réguliers (aucun trait au hasard).
Coordonnées en pixels de la photo de profil (build_awp.py : STOCK, HANDGUARD, SCREWS).
"""

import numpy as np

from common import JOINT, PX0, PX1, PY0, PY1, X, band, chassis, chip, font, outline
from common import paint as ink

PAPER = (0.11, 0.25, 0.47)  # bleu de tirage (>= 0,2 sur le canal dominant : lisible sous l'éclairage du jeu)
FINE = (0.25, 0.40, 0.62)
MAJOR = (0.36, 0.52, 0.74)
CHALK = (0.86, 0.90, 0.95)  # trait blanc bleuté du tirage
PRIMER = (0.16, 0.17, 0.19)
MATTE = 0.78

def mono(size):
	"""Cette méthode permet d'obtenir la police des cotes et du cartouche (Bahnschrift léger condensé, trait d'épure)."""
	return font("bahnschrift.ttf", size, "Light Condensed")


def grid(cv, name, step, width, x0=JOINT, y0=363):
	"""Cette méthode permet de tracer un quadrillage régulier calé sur le joint et le dessus du châssis (pas en px photo)."""
	for x in np.arange(x0 - step * np.ceil((x0 - PX0) / step), PX1, step):
		cv.line(name, [(x, PY0), (x, PY1)], width)
	for y in np.arange(y0 - step * np.ceil((y0 - PY0) / step), PY1, step):
		cv.line(name, [(PX0, y), (PX1, y)], width)


def arrow(cv, name, tip, toward):
	"""Cette méthode permet de poser une pointe de flèche de cote en tip, orientée vers l'extérieur (toward = -1 ou 1)."""
	x, y = tip
	cv.poly(name, [(x, y), (x - toward * 22, y - 6), (x - toward * 22, y + 6)])


def dimension(cv, x0, x1, y, label, ext_top=380):
	"""Cette méthode permet de tracer une cote horizontale : lignes d'attache, ligne de cote à flèches, valeur au-dessus."""
	for x in (x0, x1):
		cv.line("chalk", [(x, ext_top), (x, y + 10)], 3)
	cv.line("chalk", [(x0 + 4, y), (x1 - 4, y)], 3)
	arrow(cv, "chalk", (x0, y), -1)
	arrow(cv, "chalk", (x1, y), 1)
	cv.text("chalk", label, ((x0 + x1) / 2, y - 15), 17, mono)


def chain_line(cv, y, x0, x1):
	"""Cette méthode permet de tracer une ligne d'axe mixte (trait long, point) à la hauteur y, de x0 à x1."""
	x = x0
	while x < x1:
		cv.line("chalk", [(x, y), (min(x + 46, x1), y)], 3)
		if x + 58 < x1:
			cv.line("chalk", [(x + 54, y), (x + 60, y)], 3)
		x += 70


def draw(cv):
	"""Cette méthode permet de tracer quadrillages, contour, axe, centrages, cotes et cartouche sur la toile de profil."""
	grid(cv, "fine", 25, 3)
	grid(cv, "major", 125, 5)
	holes = [outline("GUARD_HOLE"), outline("THUMBHOLE")]
	band(cv, "chalk", chassis(), holes, 20, 28)  # le congé du bord prend les 7 premiers px : trait franc dedans
	chain_line(cv, 452, 1735, 2240)  # axe du garde-main, arrêté avant la vis 2382 et repris après le joint
	chain_line(cv, 520, 3150, 3535)
	for px, py in outline("SCREWS"):  # vis du châssis (rayons de 8 à 16 px) : un cercle de centrage commun
		cv.circle("chalk", (px, py), 25, width=3)
		cv.line("chalk", [(px - 34, py), (px + 34, py)], 2.5)
		cv.line("chalk", [(px, py - 34), (px, py + 34)], 2.5)
	# chaîne de cotes sur le dessus : la seconde traverse le joint d'un seul trait (vue en 1P sur l'avant de la crosse)
	dimension(cv, 1735, 2240, 418, "505")
	dimension(cv, 2240, 2700, 418, "460")
	# cartouche de l'épure, entre les vis de l'arrière de crosse
	x0, x1, y0, y1, xm, ym = 3190, 3535, 462, 568, 3400, 520
	cv.poly("chalk", [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], width=4)
	cv.line("chalk", [(x0, ym), (x1, ym)], 2.5)
	cv.line("chalk", [(xm, y0), (xm, y1)], 2.5)
	cv.text("chalk", "ÉPURE", ((x0 + xm) / 2, (y0 + ym) / 2 + 1), 30, mono)
	cv.text("chalk", "PL. 07", ((xm + x1) / 2, (y0 + ym) / 2), 20, mono)
	cv.text("chalk", "AWP  ·  ÉCH. 1:1", ((x0 + xm) / 2, (ym + y1) / 2), 17, mono)
	cv.text("chalk", "F. 3 / 12", ((xm + x1) / 2, (ym + y1) / 2), 17, mono)


def body(m, cv):
	"""Cette méthode permet de peindre crosse et garde-main en papier de tirage quadrillé et tracé."""
	m.height *= 0.3  # le papier lisse le granité
	ink(m, 1.0, PAPER, MATTE, 0.0)
	ink(m, 0.55 * cv.sample("fine", m), FINE, MATTE, 0.0)
	ink(m, 0.7 * cv.sample("major", m), MAJOR, MATTE, 0.0)
	ink(m, cv.sample("chalk", m, blur=0.4), CHALK, 0.7, 0.0)
	chip(m, -0.48, 81, PRIMER, rough=0.7, metal=0.0)


def rings(x, step, width, x0=0.0):
	"""Cette méthode permet de sélectionner des anneaux réguliers le long de l'axe (graduations), pas et largeur en unités."""
	t = (x - x0) / step
	return np.abs(t - np.round(t)) * step < width / 2


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre ÉPURE sur les quatre matériaux de l'AWP."""
	draw(cv)
	body(maps["WOOD"], cv)

	a = maps["METAL_A"]
	mag = a.is_("Magazine")
	ink(a, mag, PAPER, MATTE, 0.0)
	ink(a, mag & (a.p[:, 2] < -0.76), CHALK, 0.7, 0.0)
	ink(a, a.is_("Trigger"), CHALK, 0.7, 0.0)
	chip(a, -0.45, 83, PRIMER, rough=0.7, metal=0.0, sel=mag)

	b = maps["METAL_B"]
	x, z = b.p[:, 0], b.p[:, 2]
	barrel, fit = b.is_("Barrel"), b.is_("Fittings")
	tube = barrel & (x > -4.95)
	ink(b, tube, PAPER, 0.6, 0.0)
	ink(b, tube & rings(x, 0.5, 0.012) & (x < -0.8), MAJOR, 0.6, 0.0)  # graduations discrètes tous les 0,5
	ink(b, tube & rings(x, 1.5, 0.02, -0.9) & (x < -0.8), CHALK, 0.55, 0.0)
	ink(b, barrel & (x < -4.95), CHALK, 0.6, 0.0)
	mount = fit & (z > 0.14) & (x > X(2300)) & (x < X(2640))
	ink(b, mount, PAPER, 0.6, 0.0)
	chip(b, -0.4, 85, PRIMER, rough=0.6, metal=0.0, sel=tube | mount)

	s = maps["SCOPE"]
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - 0.504
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	tx = X(2450)
	turret = ((np.hypot(xs - tx, y) < 0.09) & (zs > 0.142)) | ((np.hypot(xs - tx, zs) < 0.12) & (np.abs(y) > 0.142))
	ring = (xs > X(2700)) & (xs < X(2790))
	tube = ~inside & ~turret & ~ring
	ink(s, tube, PAPER, 0.6, 0.0)
	ink(s, tube & ((xs < X(1915)) | (xs > X(2895))), CHALK, 0.6, 0.0)
	ink(s, tube & rings(xs, 0.12, 0.012, X(2450)) & (xs > X(1960)) & (xs < X(2680)) & (np.abs(xs - tx) > 0.15), FINE, 0.6, 0.0)
	ink(s, turret & ~inside, CHALK, 0.55, 0.0)
	chip(s, -0.45, 87, PRIMER, rough=0.6, metal=0.0, sel=tube)
