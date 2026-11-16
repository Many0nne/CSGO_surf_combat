"""CISELURE (#417) : gravure ornementale. Châssis en acier bleui presque noir, fond maté au poinçon, rinceaux de
volutes gravés et incrustés d'or qui courent le long du garde-main et de la crosse, encadrés d'un double filet d'or
qui suit le contour de chaque pièce (et le tour du pontet et du trou de pouce). Canon et lunette bleuis, bagues d'or.
"""

import math

import numpy as np

from common import X, band, fbm, outline
from common import paint as ink

BLUED = (0.105, 0.115, 0.14)  # acier bleui (métal : teinte du reflet)
GOLD = (0.86, 0.66, 0.32)
GROOVE = -0.0011  # profondeur de la gravure (unités monde)


def spiral(cv, name, base, tangent, side, radius, turns=1.6, width=6.0):
	"""Cette méthode permet de tracer une volute qui naît sur la tige en base et s'enroule d'un côté (side = ±1),
	trait de plus en plus fin vers le cœur, avec de petites feuilles sur son pourtour."""
	tx, ty = tangent
	nx, ny = -ty * side, tx * side
	cx, cy = base[0] + nx * radius, base[1] + ny * radius
	phi0 = math.atan2(base[1] - cy, base[0] - cx)
	n = 48
	pts = []
	for i in range(n + 1):
		u = i / n
		th = u * turns * 2 * math.pi
		r = radius * (1 - u) ** 1.25
		a = phi0 + th * (1 if side > 0 else -1) * (1 if tx >= 0 else -1)
		pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
	for i in range(n):
		w = max(2.0, width * (1 - i / n) ** 0.6)
		cv.line(name, [pts[i], pts[i + 1]], w)
	for i in (10, 20):  # feuilles : virgules sur le pourtour
		x, y = pts[i]
		dx, dy = x - cx, y - cy
		ln = math.hypot(dx, dy) or 1
		ox, oy = dx / ln, dy / ln
		tip = (x + ox * radius * 0.55 - oy * radius * 0.3, y + oy * radius * 0.55 + ox * radius * 0.3)
		cv.poly(name, [(x - oy * 3, y + ox * 3), tip, (x + oy * 3, y - ox * 3)])


def vine(cv, name, x0, x1, y, amp, period, radius, phase=0.0, width=5.0):
	"""Cette méthode permet de tracer un rinceau : une tige ondulante de x0 à x1 autour de y, avec une volute qui naît à
	chaque demi-période, alternativement au-dessus et au-dessous."""
	pts = [(x, y + amp * math.sin((x - x0) / period * 2 * math.pi + phase)) for x in np.arange(x0, x1 + 1, 4.0)]
	cv.line(name, pts, width)
	k = 0
	x = x0 + period * 0.25
	while x < x1 - radius:
		xx = x
		yy = y + amp * math.sin((xx - x0) / period * 2 * math.pi + phase)
		dy = amp * 2 * math.pi / period * math.cos((xx - x0) / period * 2 * math.pi + phase)
		ln = math.hypot(1, dy)
		side = 1 if k % 2 else -1
		spiral(cv, name, (xx, yy), (1 / ln, dy / ln), side, radius, width=width + 1)
		# volute secondaire, plus petite, de l'autre côté de la tige un quart de période plus loin
		x2 = xx + period / 4
		if x2 < x1 - radius * 0.6:
			y2 = y + amp * math.sin((x2 - x0) / period * 2 * math.pi + phase)
			d2 = amp * 2 * math.pi / period * math.cos((x2 - x0) / period * 2 * math.pi + phase)
			l2 = math.hypot(1, d2)
			spiral(cv, name, (x2, y2), (1 / l2, d2 / l2), -side, radius * 0.58, turns=1.3, width=width - 1)
		k += 1
		x += period / 2


def draw(cv):
	"""Cette méthode permet de tracer filets et rinceaux sur la toile de profil (couches « gold » et « field »)."""
	hg, stock = outline("HANDGUARD"), outline("STOCK")
	holes = [outline("GUARD_HOLE"), outline("THUMBHOLE")]
	keep = np.zeros((cv.h, cv.w), bool)
	for outer, hs in ((hg, []), (stock, holes)):
		band(cv, "gold", outer, hs, 9, 13)
		dist = band(cv, "gold", outer, hs, 17, 19)
		keep |= dist > 26
		band(cv, "field", outer, hs, 19, 1e9)
	vine(cv, "scroll", 1775, 2400, 428, 16, 150, 26)
	vine(cv, "scroll", 2450, 2870, 455, 18, 140, 26, phase=math.pi)
	vine(cv, "scroll", 3150, 3540, 515, 22, 170, 32)
	vine(cv, "scroll", 2915, 3040, 650, 12, 110, 22, phase=math.pi / 2)  # poignée
	cv.clip("scroll", keep)


def engrave(m, cv):
	"""Cette méthode permet de peindre le châssis : acier bleui poli, fond maté entre les filets, or incrusté dans la gravure."""
	m.height *= 0.1
	ink(m, 1.0, BLUED, 0.26, 1.0)
	field = cv.sample("field", m)
	matte = fbm(m.p, 0.006, 91, 2)
	m.height += field * 0.00035 * matte
	m.rough += field * 0.14
	for layer in ("gold", "scroll"):
		a = cv.sample(layer, m, blur=0.4)
		m.height += GROOVE * a
		ink(m, a, GOLD, 0.24, 1.0)


def rings(m, sel, xs, half):
	"""Cette méthode permet de poser des bagues d'or autour des abscisses xs (demi-largeur half, unités monde)."""
	x = m.p[:, 0]
	for x0 in xs:
		ink(m, sel & (np.abs(x - x0) < half), GOLD, 0.24, 1.0)


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre CISELURE sur les quatre matériaux de l'AWP."""
	draw(cv)
	engrave(maps["WOOD"], cv)

	a = maps["METAL_A"]
	bolt = a.is_("Bolt")
	ink(a, ~bolt, BLUED, 0.3, 1.0)
	ink(a, a.is_("Trigger"), GOLD, 0.24, 1.0)
	mag = a.is_("Magazine")
	ink(a, mag & (a.p[:, 2] < -0.74), GOLD, 0.24, 1.0)

	b = maps["METAL_B"]
	x, z = b.p[:, 0], b.p[:, 2]
	fit = b.is_("Fittings")
	pad = fit & ((x > X(3555)) | ((z > -0.106) & (x > X(3190))))
	barrel = b.is_("Barrel")
	ink(b, barrel | (fit & ~pad), BLUED, 0.28, 1.0)
	rings(b, barrel, (-5.0, -4.6, -1.0), 0.025)
	screws = fit & ~pad & ~((z > 0.14) & (x > X(2300)) & (x < X(2640)))
	ink(b, screws, GOLD, 0.24, 1.0)

	s = maps["SCOPE"]
	y, zs, xs = s.p[:, 1], s.p[:, 2] - 0.504, s.p[:, 0]
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	ink(s, ~inside, BLUED, 0.28, 1.0)
	rings(s, ~inside, (X(1900), X(1990), X(2880)), 0.012)
	tx = X(2450)
	turret = ((np.hypot(xs - tx, y) < 0.09) & (zs > 0.142)) | ((np.hypot(xs - tx, zs) < 0.12) & (np.abs(y) > 0.142))
	ink(s, turret & ~inside, GOLD, 0.3, 1.0)
