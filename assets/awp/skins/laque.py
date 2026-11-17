"""LAQUE (#487) : châssis laqué rouge profond, décor à la poudre d'or. Un filet d'or suit le contour du châssis (et le
tour du pontet et du trou de pouce) ; à l'intérieur, un treillis de feuilles de chanvre (asanoha : triangles équilatéraux
dont chaque sommet est relié au centre) tracé à l'or, continu à travers le joint garde-main / crosse. Sur l'avant de la
crosse (vu en 1P), un médaillon de laque noire cerclé d'or porte une étoile d'asanoha. Chargeur et lunette laqués noir,
bagues, vis, détente et semelle d'or.
"""

import math

import numpy as np
from PIL import Image

from common import JOINT, SS, X, band, chassis, fbm, mt, mt_px, mt_py, outline, zone
from common import paint as ink

RED = (0.46, 0.035, 0.03)  # laque posée en métal (« candy ») : pas de voile gris, rouge profond sous le vernis
BLACK = (0.05, 0.045, 0.045)
GOLD = (0.88, 0.68, 0.30)
TOP = 363  # dessus du châssis (px photo)
L = 70.0  # côté d'un triangle du treillis (px photo, ~45 texels)
HW = 2.2  # demi-largeur d'un trait d'or (px photo, ~3 texels en tout)
EMBLEM, EMBLEM_R = (2592, 450), 46.0  # médaillon de l'avant de la crosse : centre et rayon (px photo)


def asanoha(px, py):
	"""Cette méthode permet de calculer la distance (px photo) au trait d'or le plus proche du treillis asanoha : côtés
	des triangles équilatéraux (un côté horizontal, un sommet sur le joint au dessus du châssis) et segments qui relient
	chaque sommet au centre de son triangle."""
	h = L * math.sqrt(3) / 2
	b = (py - TOP) / h
	a = (px - JOINT) / L - b / 2
	fa, fb = a - np.floor(a), b - np.floor(b)
	low = fa + fb < 1
	# coordonnées barycentriques dans le triangle qui contient le point
	b0 = np.where(low, 1 - fa - fb, fa + fb - 1)
	b1 = np.where(low, fa, 1 - fb)
	b2 = np.where(low, fb, 1 - fa)
	d = np.minimum.reduce([b0, b1, b2]) * h
	for bi, bj, bk in ((b0, b1, b2), (b1, b2, b0), (b2, b0, b1)):
		med = h * np.abs(bj - bk) / math.sqrt(3)  # distance à la médiane issue du sommet i
		d = np.minimum(d, np.where(bi >= 1 / 3, med, np.inf))
	return d


def draw(cv):
	"""Cette méthode permet de tracer le filet d'or du contour, la zone du treillis et le médaillon de l'avant de la crosse."""
	holes = [outline("GUARD_HOLE"), outline("THUMBHOLE")]
	band(cv, "gold", chassis(), holes, 12, 16)
	dist = zone(cv, chassis(), holes)
	keep = dist > 22
	yy, xx = np.mgrid[0 : cv.h, 0 : cv.w]
	(ex, ey), = cv.xy([EMBLEM])
	r = np.hypot(xx - ex, yy - ey) / SS
	keep &= r > EMBLEM_R + 8
	for img in cv.layer("field"):
		img.paste(255, (0, 0), Image.fromarray((keep * 255).astype(np.uint8)))
	cv.circle("black", EMBLEM, EMBLEM_R)
	cv.circle("gold", EMBLEM, EMBLEM_R, width=4.0)
	cv.circle("gold", EMBLEM, EMBLEM_R - 7, width=1.6)
	# étoile d'asanoha : hexagone, rayons vers ses sommets, et dans chacun des six triangles les segments sommet-centre
	rr = EMBLEM_R - 15
	cx, cy = EMBLEM
	hexa = [(cx + rr * math.cos(math.pi / 6 + k * math.pi / 3), cy + rr * math.sin(math.pi / 6 + k * math.pi / 3)) for k in range(6)]
	cv.poly("gold", hexa, width=2.6)
	for k in range(6):
		p, q = hexa[k], hexa[(k + 1) % 6]
		cv.line("gold", [EMBLEM, p], 2.6)
		g = ((cx + p[0] + q[0]) / 3, (cy + p[1] + q[1]) / 3)
		for v in (EMBLEM, p, q):
			cv.line("gold", [v, g], 2.0)


def lacquer(m, cv):
	"""Cette méthode permet de laquer le châssis en rouge, puis d'y poser l'or (filet, treillis, médaillon) sur les flancs."""
	m.height *= 0.05  # laque tendue : le granité d'origine disparaît
	ink(m, 1.0, RED, 0.32, 1.0)
	side = np.abs(m.n[:, 1]) > 0.6
	px, py = mt_px(m.p[:, 0]), mt_py(m.p[:, 2])
	d = asanoha(px, py)
	line = np.clip((HW + 0.6 - d) / 1.2, 0, 1)
	field = cv.sample("field", m, blur=0.8) * side
	black = cv.sample("black", m, blur=0.4) * side
	ink(m, black, BLACK, 0.34, 1.0)
	dust = 0.9 + 0.2 * fbm(m.p, 0.002, 191, 2)  # poudre d'or : grain fin
	gold = np.maximum(line * field, cv.sample("gold", m, blur=0.4) * side)
	ink(m, gold, np.array(GOLD), 0.40, 1.0)
	m.color *= (1 - gold + gold * dust)[:, None]
	m.height += 0.0004 * gold


def rings(m, sel, xs, half):
	"""Cette méthode permet de poser des bagues d'or autour des abscisses xs (demi-largeur half, unités monde)."""
	for x0 in xs:
		ink(m, sel & (np.abs(m.p[:, 0] - x0) < half), GOLD, 0.30, 1.0)


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre LAQUE sur les quatre matériaux de l'AWP."""
	draw(cv)
	lacquer(maps["WOOD"], cv)

	a = maps["METAL_A"]
	mag = a.is_("Magazine")
	ink(a, mag, BLACK, 0.36, 1.0)
	ink(a, mag & (a.p[:, 2] < -0.74), GOLD, 0.30, 1.0)
	ink(a, a.is_("Trigger"), GOLD, 0.30, 1.0)

	b = maps["METAL_B"]
	x, z = b.p[:, 0], b.p[:, 2]
	fit = b.is_("Fittings")
	mount = fit & (z > 0.14) & (x > X(2300)) & (x < X(2640))
	pad = fit & ((x > X(3555)) | ((z > -0.106) & (x > X(3190))))
	ink(b, fit & ~mount & ~pad, GOLD, 0.30, 1.0)

	s = maps["SCOPE"]
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - mt.SCOPE_Z
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	ink(s, ~inside, BLACK, 0.36, 1.0)
	rings(s, ~inside, (X(1900), X(1990), X(2880)), 0.012)
