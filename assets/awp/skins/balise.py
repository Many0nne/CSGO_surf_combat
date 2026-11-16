"""BALISE (#417) : livrée technique. Châssis blanc céramique, arrière de crosse noir barré de chevrons orange,
nez du garde-main balisé, graduations et marquages au pochoir, chargeur, frein et tourelles orange signal.
Coordonnées des panneaux en pixels de la photo de profil (build_awp.py : STOCK, HANDGUARD, SCREWS).
"""

import numpy as np

from common import X, chip, font
from common import paint as ink

WHITE = (0.80, 0.79, 0.76)
ORANGE = (0.95, 0.31, 0.04)
BLACK = (0.04, 0.04, 0.045)
PRIMER = (0.16, 0.16, 0.17)  # sous-couche vue sur les éclats


def stencil(size):
	"""Cette méthode permet d'obtenir la police des marquages (Bahnschrift gras condensé)."""
	return font("bahnschrift.ttf", size, "Bold Condensed")


def draw(cv):
	"""Cette méthode permet de tracer les couches de la livrée sur la toile de profil."""
	# arrière de crosse noir, coupé en biais devant la poignée, souligné d'un filet orange
	cut = [(2895, 340), (2995, 790)]
	cv.poly("black", [cut[0], cut[1], (3800, 790), (3800, 340)])
	cv.line("orange", [(2869, 340), (2969, 790)], 7)
	# deux chevrons orange pointés vers la bouche, sur le noir
	for dx, w in ((0, 46), (78, 18)):
		x0 = 3245 + dx
		cv.poly("orange", [(x0, 395), (x0 + w, 395), (x0 - 92 + w, 552), (x0 + w, 708), (x0, 708), (x0 - 92, 552)])
	# numéro de série au pochoir
	cv.text("white", "07", (3425, 515), 64, stencil)
	cv.text("white", "AW-338 / LM", (3420, 655), 15, stencil)
	# nez du garde-main : balisage orange et noir
	nose = [(1690, 350), (1790, 350), (1745, 550), (1690, 550)]
	cv.poly("orange", nose)
	cv.stripes("hazard", nose, 26, 0.5, 60)
	cv.line("hazard", [(1790, 350), (1745, 550)], 6)
	# filet orange le long du garde-main, terminé en flèche vers la poignée
	cv.line("orange", [(1800, 472), (2300, 472)], 6)
	cv.poly("orange", [(2300, 462), (2330, 472), (2300, 482)])
	cv.text("black", "BALISE", (2080, 403), 34, stencil)
	cv.text("black", "CHARGE MAX 5  ·  .338", (2235, 453), 11, stencil)
	# graduations sur le dessus de la crosse avant
	for i, x in enumerate(range(2450, 2860, 20)):
		cv.line("black", [(x, 372), (x, 388 if i % 5 else 398)], 3)
	# pictogramme de mire
	cv.circle("black", (2560, 455), 30, width=5)
	cv.circle("black", (2560, 455), 6)
	for a, b in (((2520, 455), (2545, 455)), ((2575, 455), (2600, 455)), ((2560, 415), (2560, 440)), ((2560, 470), (2560, 495))):
		cv.line("black", [a, b], 4)


def chassis(m, cv):
	"""Cette méthode permet de peindre crosse et garde-main (peinture céramique satinée sur le granité d'origine)."""
	m.height *= 0.45  # la peinture lisse le granité
	ink(m, 1.0, WHITE, 0.48, 0.0)
	ink(m, cv.sample("black", m), BLACK, 0.55, 0.0)
	ink(m, cv.sample("orange", m), ORANGE, 0.45, 0.0)
	ink(m, cv.sample("white", m), WHITE, 0.48, 0.0)
	ink(m, cv.sample("hazard", m), BLACK, 0.55, 0.0)
	chip(m, -0.42, 71, PRIMER, rough=0.7, metal=0.0)


def metal_a(m):
	"""Cette méthode permet de peindre chargeur et détente en orange signal (boîtier noir et culasse nue d'origine)."""
	mag = m.is_("Magazine")
	ink(m, mag & (m.p[:, 2] > -0.76), ORANGE, 0.42, 0.0)
	ink(m, m.is_("Trigger"), ORANGE, 0.42, 0.0)
	chip(m, -0.45, 73, (0.45, 0.45, 0.47), rough=0.35, sel=mag)


def metal_b(m):
	"""Cette méthode permet de peindre le frein de bouche et le montage de lunette en orange signal."""
	x, z = m.p[:, 0], m.p[:, 2]
	fit = m.is_("Fittings")
	brake = m.is_("Barrel") & (x < -4.95)
	mount = fit & (z > 0.14) & (x > X(2300)) & (x < X(2640))
	ink(m, brake, ORANGE, 0.4, 0.0)
	ink(m, mount, ORANGE, 0.42, 0.0)
	chip(m, -0.4, 75, (0.42, 0.42, 0.44), rough=0.35, sel=brake | mount)


def scope(m):
	"""Cette méthode permet de peindre la lunette en blanc, bouts noirs, tourelles anodisées orange."""
	x, y, z = m.p[:, 0], m.p[:, 1], m.p[:, 2] - 0.504
	tx = X(2450)
	r = np.hypot(y, z)
	knob = (np.hypot(x - tx, y) < 0.09) & (z > 0.142)
	side = (np.hypot(x - tx, z) < 0.12) & (np.abs(y) > 0.142)
	ring = (x > X(2700)) & (x < X(2790))
	inside = ((x < X(1888)) & (r < 0.1885)) | ((x > X(2928)) & (r < 0.1055))
	tube = ~knob & ~side & ~ring & ~inside
	ink(m, tube, WHITE, 0.45, 0.0)
	ends = tube & ((x < X(1915)) | (x > X(2895)))
	ink(m, ends, BLACK, 0.5, 0.0)
	band = tube & (x > X(2655)) & (x < X(2672))
	ink(m, band, ORANGE, 0.42, 0.0)
	turret = (knob | side) & ~inside
	ink(m, turret, ORANGE, 0.5, 0.0)
	chip(m, -0.45, 77, (0.42, 0.42, 0.44), rough=0.35, sel=tube)


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre BALISE sur les quatre matériaux de l'AWP."""
	draw(cv)
	chassis(maps["WOOD"], cv)
	metal_a(maps["METAL_A"])
	metal_b(maps["METAL_B"])
	scope(maps["SCOPE"])
