"""ORAGE (#417) : candy à éclairs. Peinture candy vert émeraude très profonde (métal sombre saturé, vernis brillant),
traversée d'éclairs ramifiés blanc glacé qui s'entourent d'un halo turquoise fondu dans le vernis : un grand éclair
plonge en travers de la crosse, un autre court le long du garde-main, un troisième descend de la plaque de couche.
"""

import math

import numpy as np

from common import JOINT, X
from common import paint as ink

CANDY = (0.04, 0.38, 0.23)
GLOW = (0.10, 0.85, 0.75)
CORE = (0.88, 1.0, 0.96)


def bolt(rng, a, b, rough=0.2, depth=6):
	"""Cette méthode permet de tracer un éclair de a à b par déplacement du point milieu (zigzag de plus en plus fin)."""
	pts = [a, b]
	for d in range(depth):
		out = [pts[0]]
		for p, q in zip(pts, pts[1:]):
			mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
			ln = math.hypot(q[0] - p[0], q[1] - p[1])
			nx, ny = -(q[1] - p[1]) / (ln or 1), (q[0] - p[0]) / (ln or 1)
			off = rng.normal(0, rough) * ln
			out += [(mx + nx * off, my + ny * off), q]
		pts = out
	return pts


def strike(cv, rng, a, b, width, branches=3, via=None):
	"""Cette méthode permet de tracer un éclair et ses branches (cœur et halo), branches de plus en plus fines ; via
	force un point de passage (mi-hauteur d'un joint entre deux pièces) et renvoie le tracé principal."""
	if via is None:
		main = bolt(rng, a, b)
	else:  # deux demi-éclairs : autant de points et de tirages qu'un seul, les éclairs suivants ne changent pas
		main = bolt(rng, a, via, rough=0.14, depth=5) + bolt(rng, via, b, rough=0.14, depth=5)[1:]
		rng.normal()
	cv.line("glow", main, width * 5)
	cv.line("core", main, width)
	for _ in range(branches):
		i = int(rng.uniform(0.15, 0.7) * len(main))
		p = main[i]
		dx, dy = b[0] - a[0], b[1] - a[1]
		ang = math.atan2(dy, dx) + rng.choice([-1, 1]) * rng.uniform(0.4, 0.9)
		ln = math.hypot(dx, dy) * rng.uniform(0.2, 0.4)
		q = (p[0] + math.cos(ang) * ln, p[1] + math.sin(ang) * ln)
		br = bolt(rng, p, q, depth=5)
		cv.line("glow", br, width * 3)
		cv.line("core", br, max(2.0, width * 0.5))
	return main


def draw(cv):
	"""Cette méthode permet de placer les trois éclairs sur la toile de profil ; celui du garde-main traverse le joint
	et se branche sur le grand éclair de la crosse (jamais un éclair qui s'arrête net sur le joint)."""
	rng = np.random.default_rng(17)
	big = strike(cv, rng, (2600, 372), (3000, 715), 6, branches=4)  # en travers de la crosse
	join = min(big, key=lambda p: abs(p[0] - 2690) + 10 * max(0.0, p[1] - 495))  # sur la crosse, au-dessus du pontet
	strike(cv, rng, (1715, 400), join, 5, branches=3, via=(JOINT, 450))  # le long du garde-main, jusqu'au grand éclair
	strike(cv, rng, (3545, 410), (3240, 610), 5, branches=2)  # depuis la plaque de couche


def candy(m, sel, rough=0.18):
	"""Cette méthode permet de poser la peinture candy (métal 1, teinte saturée sombre, vernis brillant, creux plus sombres)."""
	ink(m, sel, CANDY, rough, 1.0)


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre ORAGE sur les quatre matériaux de l'AWP."""
	draw(cv)
	w = maps["WOOD"]
	w.height *= 0.1
	candy(w, np.ones(len(w.p), bool))
	glow = cv.sample("glow", w, blur=7)
	w.color += np.outer(glow**1.5, GLOW) * 0.85
	core = cv.sample("core", w, blur=0.5)
	ink(w, core, CORE, 0.3, 0.0, keep_ao=False)

	a = maps["METAL_A"]
	candy(a, ~a.is_("Bolt") & ~a.is_("Handle"))
	ink(a, a.is_("Handle"), (0.035, 0.05, 0.045), 0.32, 1.0)

	b = maps["METAL_B"]
	x, z = b.p[:, 0], b.p[:, 2]
	fit = b.is_("Fittings")
	pad = fit & ((x > X(3555)) | ((z > -0.106) & (x > X(3190))))
	candy(b, b.is_("Barrel") | (fit & ~pad), rough=0.14)
	ink(b, b.is_("Barrel") & (x < -4.95), GLOW, 0.2, 1.0)

	s = maps["SCOPE"]
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - 0.504
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	candy(s, ~inside)
	for x0 in (X(1905), X(2885)):
		ink(s, ~inside & (np.abs(xs - x0) < 0.01), GLOW, 0.2, 1.0)
