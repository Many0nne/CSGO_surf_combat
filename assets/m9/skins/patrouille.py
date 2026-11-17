"""PATROUILLE (#420) : livrée tactique deux tons. Lame en Cerakote vert OD mat, gravée au laser jusqu'au métal : un filet
qui suit le contour de la lame, une règle graduée (centimètres numérotés) le long du tranchant et, sur le talon, un
matricule dans un cartouche. Garde, pommeau et manche coyote ; la peinture s'use jusqu'à l'acier sur les arêtes.
"""

import numpy as np
from common import STEEL, fbm, font, smooth

OD = np.array([0.30, 0.32, 0.20])
COYOTE = np.array([0.56, 0.45, 0.31])
LASER = np.array([0.62, 0.62, 0.60])  # métal mis à nu par le laser
OUTLINE = (0.030, 0.036)  # filet laser : distances au bord de la lame
RULER = (-1.15, -0.20, -0.168)  # règle : début, fin (t), ligne de base (h)
TICK = 0.025  # pas des graduations


def bahn(size):
	"""Cette méthode permet de charger la police des marquages (Bahnschrift) à une taille en pixels de toile."""
	return font("bahnschrift.ttf", size)


def engrave(kn):
	"""Cette méthode permet de tracer sur la toile tout ce que le laser grave : filet de contour, règle, cartouche et textes."""
	kn.put("laser", (kn.dist > OUTLINE[0]) & (kn.dist < OUTLINE[1]))
	t0, t1, base = RULER
	kn.line("laser", [(t0, base), (t1, base)], 0.004)
	for i, t in enumerate(np.arange(t0, t1 + 1e-6, TICK)):
		size = 0.034 if i % 10 == 0 else 0.022 if i % 5 == 0 else 0.013
		kn.line("laser", [(t, base), (t, base + size)], 0.0035)
		if i % 10 == 0 and i:
			# Chiffre côté pointe du trait : une fois le couteau retourné en 1P, il se lit juste après la graduation
			kn.text("laser", str(i // 10), (t - 0.024, base + 0.052), 0.026, bahn, angle=180)
	# Cartouche du talon : matricule et lot. En 1P la M9 est tenue tranchant en haut : textes tournés d'un demi-tour,
	# et lignes rangées du tranchant vers le dos (le matricule, côté tranchant, paraît en haut). Le haut du cartouche
	# (h > 0,10) est mordu par les dents : rien n'y est écrit
	box = [(-0.10, -0.12), (0.19, -0.12), (0.19, 0.17), (-0.10, 0.17)]
	kn.line("laser", box + box[:1], 0.006)
	kn.text("laser", "PTL-420", (0.045, -0.072), 0.045, bahn, angle=180)
	kn.text("laser", "N° 0420-07", (0.045, -0.005), 0.034, bahn, angle=180)
	kn.line("laser", [(-0.06, 0.034), (0.15, 0.034)], 0.005)
	kn.text("laser", "M9 · OD", (0.045, 0.072), 0.03, bahn, angle=180)


def paint(kn):
	"""Cette méthode permet de peindre la lame en vert OD gravé au laser, le reste en coyote, et d'user les arêtes."""
	m = kn.m
	engrave(kn)
	laser = kn.sample("laser", blur=0.6) * kn.blade
	grain = m.field(lambda p: fbm(p * 40, 2, 71))
	kn.paint(kn.blade, OD * (1 + 0.05 * grain)[..., None], 0.62 + 0.04 * grain, 0.0, detail=0.3, ao=0.5)
	kn.paint(laser, LASER, 0.38, 1.0, detail=0.2, ao=0.2)
	kn.height = kn.height - laser * 0.25 + grain * 0.03 * kn.blade
	hw = kn.guard | kn.pommel
	kn.paint(hw, COYOTE, 0.55, 0.0, detail=0.5)
	kn.tint_grip(COYOTE * 0.75)
	# Usure : la peinture part sur les arêtes vives (lame, garde, pommeau), acier dessous
	brk = m.field(lambda p: fbm(p * 6, 3, 73)) * 0.5 + 0.5
	chips = smooth(0.5, 0.58, m.edges * (0.55 + 0.6 * brk)) * (kn.blade | hw)
	kn.paint(chips, STEEL * 0.8, 0.3, 1.0, detail=0.5)
	kn.edge(0.12)
