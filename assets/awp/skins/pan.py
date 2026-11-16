"""PAN ! (#417) : graphique BD / pop. Aplats francs sans reflet métallique, gros contour noir qui suit chaque pièce et le
tour des trous, trame de points qui fonce vers le bas. Garde-main cyan strié de traits de vitesse, crosse jaune, et sur
l'arrière une explosion rouge où claque l'onomatopée « PAN ! ». Lunette rouge, reflets de dessin animé en traits blancs.
"""

import math

import numpy as np

from common import X, band, font, halftone, outline, zone
from common import paint as ink

YELLOW = (0.98, 0.80, 0.10)
RED = (0.88, 0.10, 0.10)
CYAN = (0.08, 0.60, 0.86)
BLUE = (0.03, 0.25, 0.55)
ORANGE = (0.96, 0.45, 0.06)
BLACK = (0.025, 0.025, 0.03)
WHITE = (0.95, 0.95, 0.93)
FLAT = 0.62  # rugosité des aplats (peu de reflet : rendu de dessin)


def burst(center, rx, ry, spikes=13, seed=3):
	"""Cette méthode permet d'obtenir le contour d'une explosion de BD : pointes irrégulières autour d'une ellipse."""
	rng = np.random.default_rng(seed)
	pts = []
	for i in range(spikes * 2):
		a = i / (spikes * 2) * 2 * math.pi
		k = (1.0 if i % 2 == 0 else 0.62) * (0.88 + 0.24 * rng.random())
		pts.append((center[0] + rx * k * math.cos(a), center[1] + ry * k * math.sin(a)))
	return pts


def draw(cv):
	"""Cette méthode permet de tracer trames, traits de vitesse, explosion, texte et contours sur la toile de profil."""
	hg, stock = outline("HANDGUARD"), outline("STOCK")
	holes = [outline("GUARD_HOLE"), outline("THUMBHOLE")]
	in_hg, in_stock = zone(cv, hg) > 0, zone(cv, stock, holes) > 0
	halftone(cv, "dots_stock", in_stock, 11, 0.0, 4.6, 420, 720)
	halftone(cv, "dots_hg", in_hg, 10, 0.0, 4.0, 380, 520)
	# traits de vitesse vers la bouche, de plus en plus courts vers le bas
	for i, py in enumerate(range(385, 480, 14)):
		x1 = 2050 - 60 * (i % 3) - 25 * i
		cv.line("speed", [(1735, py), (x1, py)], 5 - 0.4 * i)
	# explosion sur l'arrière de crosse
	c = (3365, 512)
	cv.poly("burst_line", burst(c, 205, 128))
	cv.poly("burst", burst(c, 190, 116))
	cv.poly("burst_in", burst(c, 128, 78, spikes=11, seed=7))
	impact = lambda size: font("impact.ttf", size)  # noqa: E731
	cv.text("txt_line", "PAN !", (c[0] + 4, c[1] + 2), 76, impact, angle=8, stroke=8)
	cv.text("txt", "PAN !", (c[0] + 4, c[1] + 2), 76, impact, angle=8)
	# contour noir de dessin : tour de chaque pièce et des trous
	for outer, hs in ((hg, []), (stock, holes)):
		band(cv, "line", outer, hs, 0, 22)  # les 7 premiers px tombent sur le congé du bord


def chassis(m, cv):
	"""Cette méthode permet de peindre crosse et garde-main en aplats (couches tirées dans l'ordre de la BD)."""
	m.height *= 0.2
	ink(m, 1.0, YELLOW, FLAT, 0.0, keep_ao=False)
	ink(m, m.is_("Handguard"), CYAN, FLAT, 0.0, keep_ao=False)
	for layer, col in (
		("dots_stock", ORANGE),
		("dots_hg", BLUE),
		("speed", WHITE),
		("burst_line", BLACK),
		("burst", RED),
		("burst_in", YELLOW),
		("txt_line", BLACK),
		("txt", WHITE),
		("line", BLACK),
	):
		ink(m, cv.sample(layer, m, blur=0.4), col, FLAT, 0.0, keep_ao=False)


def shine(m, sel, axis_z, width=0.25):
	"""Cette méthode permet de poser un reflet de dessin animé : trait blanc sur le dessus d'une pièce cylindrique."""
	ink(m, sel & (m.n[:, 2] > 1 - width) & (m.p[:, 2] > axis_z), WHITE, FLAT, 0.0, keep_ao=False)


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre PAN ! sur les quatre matériaux de l'AWP."""
	draw(cv)
	chassis(maps["WOOD"], cv)

	a = maps["METAL_A"]
	ink(a, ~a.is_("Bolt"), (0.06, 0.08, 0.16), FLAT, 0.0)
	ink(a, a.is_("Magazine"), RED, FLAT, 0.0)
	ink(a, a.is_("Magazine") & (a.p[:, 2] < -0.76), BLACK, FLAT, 0.0)
	ink(a, a.is_("Trigger"), YELLOW, FLAT, 0.0)

	b = maps["METAL_B"]
	x, z = b.p[:, 0], b.p[:, 2]
	barrel, fit = b.is_("Barrel"), b.is_("Fittings")
	ink(b, barrel, BLACK, FLAT, 0.0)
	ink(b, barrel & (x < -4.95), RED, FLAT, 0.0)
	shine(b, barrel & (x > -4.9) & (x < -1.0), 0.0, width=0.12)
	mount = fit & (z > 0.14) & (x > X(2300)) & (x < X(2640))
	ink(b, mount, YELLOW, FLAT, 0.0)

	s = maps["SCOPE"]
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - 0.504
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	tube = ~inside
	ink(s, tube, RED, FLAT, 0.0)
	ink(s, tube & ((xs < X(1915)) | (xs > X(2895)) | ((xs > X(2700)) & (xs < X(2790)))), BLACK, FLAT, 0.0)
	tx = X(2450)
	turret = ((np.hypot(xs - tx, y) < 0.09) & (zs > 0.142)) | ((np.hypot(xs - tx, zs) < 0.12) & (np.abs(y) > 0.142))
	ink(s, turret & tube, YELLOW, FLAT, 0.0)
	shine(s, tube & ~turret & (xs > X(1930)) & (xs < X(2860)), 0.504, width=0.12)
