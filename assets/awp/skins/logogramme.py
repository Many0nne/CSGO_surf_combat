"""LOGOGRAMME (#436) : hommage au film de science-fiction de 2016 (le vaisseau-pierre et son écriture circulaire), sans
rien en reprendre tel quel. Toute l'arme est taillée dans une roche graphite mate, striée de fines rainures verticales
régulières comme la paroi du tunnel du vaisseau. Trois anneaux d'encre noire dessinés pour le jeu (cercle irrégulier,
épaississements, vrilles et gouttes sur le pourtour) sur le garde-main, l'avant et l'arrière de la crosse. Un seul accent :
le chargeur orange combinaison. Canon, boîtier et plaque de couche d'origine.
Coordonnées en pixels de la photo de profil (build_awp.py : STOCK, HANDGUARD).
"""

import math

import numpy as np

from common import X, chassis, fbm, grime, outline, zone
from common import paint as ink

STONE = np.array((0.3, 0.305, 0.31))  # roche graphite : à 0,2 l'arme était presque noire en 1P (la planche paraît claire)
INK = (0.012, 0.012, 0.014)
ORANGE = (0.86, 0.30, 0.09)  # combinaison de décontamination
PERIOD = 0.016  # écart des fibres verticales (unités monde, ~3,6 px de texture)
# Anneaux : centre (px photo), rayon, graine du tracé, angles des deux renflements (degrés, 0 vers la crosse, 90 vers le
# bas). Un renflement en bas, vrilles pendantes, faisait lire un « Q » : renflements de côté.
# Le troisième, à l'avant de la crosse, est le seul visible en 1P.
RINGS = (((2090, 418), 40, 7, (-35, 160)), ((2590, 452), 46, 11, (200, -20)), ((3325, 505), 66, 3, (215, 25)))


def ring(cv, c, r, seed, blobs):
	"""Cette méthode permet de tracer un logogramme inventé : anneau d'encre à épaisseur variable (deux renflements, un
	amincissement presque jusqu'à la coupure), vrilles effilées vers l'extérieur et gouttes au bout de certaines."""
	rng = np.random.default_rng(seed)
	n = 240
	th = np.linspace(0, 2 * math.pi, n + 1)
	ph = rng.uniform(0, 2 * math.pi, 3)
	rad = r * (1 + 0.035 * np.sin(2 * th + ph[0]) + 0.02 * np.sin(5 * th + ph[1]))
	w = np.full(n + 1, 0.15 * r)
	blobs = np.radians(blobs)
	for k, a in enumerate(blobs):
		d = np.angle(np.exp(1j * (th - a)))
		w += (0.26 - 0.08 * k) * r * np.exp(-((d / 0.45) ** 2))
	thin = blobs[0] + math.pi * 0.9  # côté opposé au plus gros renflement : le pinceau s'essouffle
	d = np.angle(np.exp(1j * (th - thin)))
	w *= 1 - 0.8 * np.exp(-((d / 0.3) ** 2))
	cx, cy = c
	for i in range(n):
		a0, a1 = th[i], th[i + 1]
		ro0, ri0 = rad[i] + w[i] / 2, rad[i] - w[i] / 2
		ro1, ri1 = rad[i + 1] + w[i + 1] / 2, rad[i + 1] - w[i + 1] / 2
		cv.poly(
			"ink",
			[
				(cx + ro0 * math.cos(a0), cy + ro0 * math.sin(a0)),
				(cx + ro1 * math.cos(a1), cy + ro1 * math.sin(a1)),
				(cx + ri1 * math.cos(a1), cy + ri1 * math.sin(a1)),
				(cx + ri0 * math.cos(a0), cy + ri0 * math.sin(a0)),
			],
		)
	# vrilles : groupées autour des renflements, effilées et recourbées, une goutte au bout d'une sur deux
	for k, a in enumerate(blobs):
		for j in range(4 - k):
			ang = a + rng.uniform(-0.45, 0.45)
			i = int((ang % (2 * math.pi)) / (2 * math.pi) * n)
			base = rad[i] + w[i] * 0.3
			length = r * rng.uniform(0.3, 0.62)
			curl = rng.uniform(-0.9, 0.9)
			pts = []
			for s in np.linspace(0, 1, 9):
				rr = base + length * s
				aa = ang + curl * s * s * length / r
				pts.append((cx + rr * math.cos(aa), cy + rr * math.sin(aa)))
			for q in range(8):
				cv.line("ink", [pts[q], pts[q + 1]], max(0.8, r * 0.11 * (1 - q / 8)))
			if j % 2 == 0:
				ex, ey = pts[-1]
				ux, uy = (ex - cx) / math.hypot(ex - cx, ey - cy), (ey - cy) / math.hypot(ex - cx, ey - cy)
				gap = r * rng.uniform(0.07, 0.14)
				cv.circle("ink", (ex + ux * gap, ey + uy * gap), r * rng.uniform(0.03, 0.05))


def striate(m, sel, seed):
	"""Cette méthode permet de tailler la roche en fibres verticales régulières (fonction de x, donc continues d'une
	pièce à l'autre) : chaque fibre a sa propre teinte, et sa rainure s'efface et reprend le long de la hauteur, comme
	la paroi d'une roche sédimentaire."""
	p = m.p[sel]
	warp = 0.003 * fbm(p * np.array([1.0, 1.0, 0.3]), 0.05, seed, 2)
	u = (p[:, 0] + warp) / PERIOD
	fid = np.floor(u).astype(np.int64)
	f = u - fid
	groove = np.clip(np.abs(f - 0.5) * 2, 0, 1) ** 3  # 1 au fond de la rainure, entre deux fibres
	h = ((fid * 2654435761) ^ (seed * 97)) & 0xFFFF
	fiber = (h / 65535.0) * 2 - 1  # teinte propre à la fibre
	run = np.clip(0.55 + 0.8 * fbm(p * np.array([6.0, 6.0, 0.35]), 0.1, seed + 1, 3), 0, 1)  # la rainure s'efface par plages
	tone = 1 + 0.05 * fbm(p, 0.35, seed + 2, 3) + 0.22 * fiber * (0.5 + 0.5 * run)
	cut = groove * run
	m.color[sel] = np.outer(tone * (1.15 - 0.8 * cut), STONE)  # paroi du tunnel : fibres claires, rainures noires * grime(m)[sel][:, None]
	m.rough[sel] = 0.8 - 0.08 * fiber * run
	m.metal[sel] = 0.0
	m.height[sel] = -0.0014 * cut + 0.0003 * fiber * run + 0.0004 * fbm(p, 0.01, seed + 3, 2)


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre LOGOGRAMME sur les quatre matériaux de l'AWP."""
	for c, r, seed, blobs in RINGS:
		ring(cv, c, r, seed, blobs)
	cv.clip("ink", zone(cv, chassis(), [outline("GUARD_HOLE"), outline("THUMBHOLE")]) > 4)

	w = maps["WOOD"]
	striate(w, np.ones(len(w.p), bool), 201)
	a = cv.sample("ink", w, blur=0.5)
	ink(w, a, INK, 0.95, 0.0, keep_ao=False)  # encre mate : un reflet du ciel la blanchissait de trois quarts
	w.height -= a * 0.0012  # l'encre remplit les rainures

	a = maps["METAL_A"]
	mag = a.is_("Magazine") & (a.p[:, 2] > -0.76)
	ink(a, mag, ORANGE, 0.5, 0.0)

	b = maps["METAL_B"]
	x, z = b.p[:, 0], b.p[:, 2]
	mount = b.is_("Fittings") & (z > 0.14) & (x > X(2300)) & (x < X(2640))
	striate(b, mount, 203)

	s = maps["SCOPE"]
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - 0.504
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	tx = X(2450)
	knob = (np.hypot(xs - tx, y) < 0.09) & (zs > 0.142)
	side = (np.hypot(xs - tx, zs) < 0.12) & (np.abs(y) > 0.142)
	striate(s, ~inside & ~knob & ~side, 205)
