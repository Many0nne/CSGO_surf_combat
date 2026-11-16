"""LEURRE (#476, commun) : camouflage « dazzle » des navires de 1917. La lame est coupée en deux champs par une diagonale ;
chaque champ porte des bandes parallèles noir, blanc cassé et gris bleu, d'une largeur réglée par une suite fixe, à un
angle différent de part et d'autre de la coupe : les bandes se cassent net sur la diagonale. Peinture mate, garde et
pommeau gris bleu, manche d'origine noir.
"""

import numpy as np
from common import fbm

WHITE = np.array([0.80, 0.81, 0.78])
GREY = np.array([0.36, 0.45, 0.55])
BLACK = np.array([0.13, 0.14, 0.16])  # posé en métal sombre mat : en non-métal il prenait un voile gris
WIDEN = 1.5  # à la taille d'un couteau, des bandes plus fines se lisent comme des rayures
# Coupe entre les deux champs : la droite passe par ces deux points (t, h), du dos vers le tranchant
CUT = ((-0.70, 0.30), (-1.05, -0.30))
# Champ de la pointe puis champ du talon : angle des bandes (degrés), décalage, suite (couleur, largeur en unités)
FIELDS = (
	(32.0, 0.00, (("k", 0.075), ("w", 0.045), ("g", 0.060), ("w", 0.030), ("k", 0.040), ("g", 0.085))),
	(-58.0, 0.03, (("w", 0.090), ("k", 0.050), ("g", 0.035), ("k", 0.070), ("w", 0.040), ("g", 0.065))),
)


def bands(t, h, angle, offset, seq):
	"""Cette méthode permet de donner, pour chaque point de toile, la couleur ("k", "w" ou "g") de la bande qui le couvre,
	les bandes se répétant selon la suite seq le long de la direction perpendiculaire à l'angle donné."""
	a = np.radians(angle)
	s = t * np.sin(a) + h * np.cos(a) + offset
	widths = np.array([w for _, w in seq]) * WIDEN
	ends = np.cumsum(widths)
	idx = np.searchsorted(ends, np.mod(s, ends[-1]), side="right")
	names = np.array([c for c, _ in seq])
	return names[np.clip(idx, 0, len(seq) - 1)]


def compose(kn):
	"""Cette méthode permet de calculer les masques noir, blanc et gris des deux champs, séparés par la coupe."""
	t, h = kn.grid()
	(t0, h0), (t1, h1) = CUT
	side = (t - t0) * (h1 - h0) - (h - h0) * (t1 - t0) > 0  # vrai du côté de la pointe
	tip = bands(t, h, *FIELDS[0])
	heel = bands(t, h, *FIELDS[1])
	col = np.where(side, tip, heel)
	return {c: col == c for c in "kwg"}


def paint(kn):
	"""Cette méthode permet de peindre la lame en bandes dazzle mates et de passer garde et pommeau au gris bleu."""
	m = kn.m
	masks = compose(kn)
	paint_coat = m.field(lambda p: fbm(p * 45, 2, 91))
	for c, rgb, metal in (("w", WHITE, 0.0), ("g", GREY, 0.0), ("k", BLACK, 1.0)):
		kn.put(c, masks[c])
		a = kn.sample(c, blur=0.6) * kn.blade
		kn.paint(a, rgb * (1 + 0.03 * paint_coat)[..., None], 0.62 if metal == 0 else 0.55, metal, detail=0.25, ao=0.5)
	kn.height = kn.height + paint_coat * 0.02 * kn.blade
	kn.edge(0.12)
	kn.paint(kn.guard | kn.pommel, GREY * 0.85, 0.6, 0.0, detail=0.5)
