"""ART DÉCO (#420) : composition géométrique en laque noire et ivoire, filets d'argent poli. Au talon, un éventail en
gradins : des arcs concentriques ivoire et noir autour d'un demi-disque d'argent, l'arc extérieur découpé en tuiles (pas
de rayons alternés depuis le centre : ils rappelaient le drapeau du Soleil levant). De l'éventail partent trois lignes de
fuite qui convergent vers la pointe, celle du milieu en ivoire. Un filet d'argent suit le contour de la lame. Garde et
pommeau chromés, manche d'origine noir.
"""

import numpy as np
from common import STEEL, fbm

# Noir posé en métal sombre satiné : en non-métal il prenait un voile gris, en brillant il passait pour du chrome
BLACK = np.array([0.10, 0.10, 0.11])
IVORY = np.array([0.90, 0.85, 0.74])
SILVER = np.array([0.86, 0.87, 0.89])
SUN = (0.26, 0.01)  # centre de l'éventail (t, h), au talon
R0 = 0.045  # rayon du demi-disque d'argent
# Arcs ivoire (rayon intérieur, extérieur), le dernier ajouré ; l'éventail tient dans la hauteur de la lame (±0,21)
ARCS = ((0.062, 0.088), (0.104, 0.130), (0.146, 0.172))
SLOTS = 11  # fentes de l'arc extérieur, entre 95° et 265°
R1 = ARCS[-1][1]
LINE = 0.006  # largeur d'un filet d'argent
FRAME = (0.028, 0.034)  # filet de contour : distances au bord de la lame
START = SUN[0] - R1 - 0.03  # abscisse où la composition quitte l'éventail
VANISH = (-1.97, -0.005)  # point de fuite des lignes, juste avant la pointe
LINES = (-0.02, -0.08, -0.14)  # hauteurs de départ des lignes de fuite, au bord de l'éventail ; celle du milieu en ivoire
IVORY_W = 0.011  # demi-largeur de la ligne ivoire


def seg(t, h, p0, p1):
	"""Cette méthode permet de donner la distance de chaque point de toile au segment p0-p1 (unités)."""
	(t0, h0), (t1, h1) = p0, p1
	dt, dh = t1 - t0, h1 - h0
	u = np.clip(((t - t0) * dt + (h - h0) * dh) / (dt * dt + dh * dh), 0, 1)
	return np.hypot(t - t0 - u * dt, h - h0 - u * dh)


def vanishing_lines(t, h, ivory, silver):
	"""Cette méthode permet de tracer les trois lignes de fuite de l'éventail vers la pointe, celle du milieu en ivoire
	bordée d'un filet d'argent, les autres en filets d'argent."""
	for i, h0 in enumerate(LINES):
		d = seg(t, h, (START, h0), VANISH)
		if i == 1:
			ivory |= d < IVORY_W
			silver |= np.abs(d - IVORY_W) < LINE / 3
		else:
			silver |= d < LINE / 2


def compose(kn):
	"""Cette méthode permet de calculer sur la toile les masques ivoire et argent de la composition."""
	t, h = kn.grid()
	ivory = np.zeros(t.shape, bool)
	silver = np.zeros(t.shape, bool)
	# Éventail : demi-disque d'argent, arcs ivoire bordés d'argent, arc extérieur découpé en tuiles
	dt, dh = t - SUN[0], h - SUN[1]
	r = np.hypot(dt, dh)
	a = np.degrees(np.arctan2(dh, dt)) % 360
	half = (a > 95) & (a < 265)
	silver |= (r < R0) & (dt < 0.02)
	for r0, r1 in ARCS:
		ivory |= half & (r > r0) & (r < r1)
		silver |= half & ((np.abs(r - r0) < LINE / 2) | (np.abs(r - r1) < LINE / 2))
	# Arc extérieur découpé en tuiles par des fentes noires (une ligne d'argent sur de l'ivoire ne se voyait pas)
	slot = np.abs(((a - 95) / (170 / SLOTS)) % 1 - 0.5) * np.radians(170 / SLOTS) * r  # distance au milieu d'une fente
	ivory &= ~(half & (r > ARCS[-1][0]) & (r < R1) & (slot < 0.006))
	silver |= half & (np.abs(r - R1 - 0.022) < LINE / 3)
	vanishing_lines(t, h, ivory, silver)
	frame = (kn.dist > FRAME[0]) & (kn.dist < FRAME[1])
	keep = kn.dist > FRAME[1] + 0.006  # la composition reste à l'intérieur du filet de contour
	return ivory & keep & ~silver, (silver & keep) | frame


def paint(kn):
	"""Cette méthode permet de laquer la lame en noir, d'y poser la composition ivoire et argent et de chromer garde et pommeau."""
	m = kn.m
	ivory, silver = compose(kn)
	kn.put("ivoire", ivory)
	kn.put("argent", silver)
	iv = kn.sample("ivoire", blur=0.6) * kn.blade
	ag = kn.sample("argent", blur=0.6) * kn.blade
	orange_peel = m.field(lambda p: fbm(p * 50, 2, 81))
	kn.paint(kn.blade, BLACK, 0.38 + 0.03 * orange_peel, 1.0, detail=0.2, ao=0.5)
	kn.paint(iv, IVORY, 0.3, 0.0, detail=0.15, ao=0.4)
	kn.paint(ag, SILVER, 0.1, 1.0, detail=0.3, ao=0.3)
	kn.height = kn.height + ag * 0.4 + orange_peel * 0.02 * kn.blade
	kn.edge(0.08)
	hw = kn.guard | kn.pommel
	kn.paint(hw, STEEL * 1.05, 0.08, 1.0, detail=0.4)
