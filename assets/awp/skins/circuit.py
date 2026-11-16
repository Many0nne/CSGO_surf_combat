"""CIRCUIT (#417) : noir et filet néon. Châssis en carbone tissé noir (sergé 2/2), parcouru de pistes magenta tracées
comme un circuit imprimé (lignes droites, coudes à 45°, pastilles et vias) qui convergent vers une puce sur l'arrière
de la crosse, avec un léger halo. Métaux noir mat, bagues et tourelles magenta.
"""

import numpy as np

from common import X
from common import paint as ink

NEON = (0.98, 0.10, 0.62)
HALO = (0.55, 0.02, 0.32)
MATTE = (0.13, 0.13, 0.14)  # noir satiné, posé en métal (pas de voile gris)

# pistes en pixels de la photo de profil (build_awp.py) ; chaque coude fait 45°. Les deux pistes du garde-main
# traversent le joint (JOINT) à l'horizontale et continuent sur la crosse : pas de pastille ni de coude sur le joint.
TRACES = [
	[(1722, 395), (1950, 395), (1975, 420), (2250, 420), (2270, 400), (2650, 400), (2675, 425), (2860, 425), (2890, 455), (3170, 455), (3200, 485), (3345, 485)],
	[(1760, 470), (2050, 470), (2070, 452), (2490, 452), (2538, 500), (2705, 500)],
	[(3140, 545), (3230, 545), (3250, 525), (3345, 525)],
	[(3415, 485), (3440, 460), (3545, 460)],
	[(3415, 525), (3445, 555), (3545, 555)],
	[(2918, 610), (2935, 665), (2950, 715)],
]
CHIP = (3345, 470, 3415, 540)  # puce : x0, y0, x1, y1


def draw(cv):
	"""Cette méthode permet de tracer pistes, pastilles, vias et puce sur la toile de profil."""
	for tr in TRACES:
		cv.line("neon", tr, 4)
		cv.line("halo", tr, 16)
		for end in (tr[0], tr[-1]):
			cv.circle("neon", end, 8, width=3)
			cv.circle("halo", end, 14)
		for p in tr[1:-1]:
			cv.circle("neon", p, 4)
	x0, y0, x1, y1 = CHIP
	cv.poly("halo", [(x0 - 10, y0 - 10), (x1 + 10, y0 - 10), (x1 + 10, y1 + 10), (x0 - 10, y1 + 10)])
	cv.poly("chip", [(x0, y0), (x1, y0), (x1, y1), (x0, y1)])
	cv.poly("neon", [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], width=3)
	for i in range(5):  # broches
		y = y0 + 8 + i * (y1 - y0 - 16) / 4
		cv.line("neon", [(x0 - 9, y), (x0, y)], 3)
		cv.line("neon", [(x1, y), (x1 + 9, y)], 3)
	cv.circle("neon", (x0 + 12, y0 + 12), 4)


def carbon(m, cell=0.035):
	"""Cette méthode permet de peindre un carbone tissé (sergé 2/2) projeté sur la face dominante de chaque texel."""
	n = np.abs(m.n)
	ax = np.argmax(n, axis=1)  # 0 : bout (y, z) ; 1 : flanc (x, z) ; 2 : dessus/dessous (x, y)
	a = np.where(ax == 0, m.p[:, 1], m.p[:, 0])
	b = np.where(ax == 2, m.p[:, 1], m.p[:, 2])
	u, v = a / cell, b / cell
	iu, iv = np.floor(u), np.floor(v)
	warp = ((iu + iv) // 2) % 2 == 0  # sens de la mèche visible : chaîne ou trame
	f = np.where(warp, v - iv, u - iu)  # position à travers la mèche
	tow = np.sin(f * np.pi)  # bombé de la mèche
	shade = np.where(warp, 0.28, 0.18) * (0.7 + 0.3 * tow)
	m.color[:] = np.outer(shade, (1.0, 1.0, 1.08)) * (0.6 + 0.4 * np.clip(m.ao, 0, 1))[:, None]
	# en métal sombre (docs/assets.md, pièges) : un non-métal sombre prend un voile gris sous les reflets
	m.rough[:] = 0.4 - 0.08 * tow
	m.metal[:] = 1.0
	m.height[:] = 0.0004 * tow


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre CIRCUIT sur les quatre matériaux de l'AWP."""
	draw(cv)
	w = maps["WOOD"]
	carbon(w)
	halo = cv.sample("halo", w, blur=5)
	w.color += np.outer(halo * 0.35, HALO)
	ink(w, cv.sample("chip", w), (0.02, 0.02, 0.025), 0.5, 0.0, keep_ao=False)
	ink(w, cv.sample("neon", w, blur=0.4), NEON, 0.35, 0.0, keep_ao=False)

	a = maps["METAL_A"]
	ink(a, ~a.is_("Bolt"), MATTE, 0.5, 1.0)
	ink(a, a.is_("Trigger"), NEON, 0.35, 0.0)

	b = maps["METAL_B"]
	x, z = b.p[:, 0], b.p[:, 2]
	fit, barrel = b.is_("Fittings"), b.is_("Barrel")
	pad = fit & ((x > X(3555)) | ((z > -0.106) & (x > X(3190))))
	ink(b, barrel | (fit & ~pad), MATTE, 0.46, 1.0)
	for x0 in (-5.0, -4.7, -1.0):
		ink(b, barrel & (np.abs(x - x0) < 0.012), NEON, 0.35, 0.0)

	s = maps["SCOPE"]
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - 0.504
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	ink(s, ~inside, MATTE, 0.46, 1.0)
	for x0 in (X(1905), X(1990), X(2885)):
		ink(s, ~inside & (np.abs(xs - x0) < 0.008), NEON, 0.35, 0.0)
	tx = X(2450)
	turret = ((np.hypot(xs - tx, y) < 0.09) & (zs > 0.142)) | ((np.hypot(xs - tx, zs) < 0.12) & (np.abs(y) > 0.142))
	ink(s, turret & ~inside, NEON, 0.4, 0.0)
