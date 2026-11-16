"""TOPO (#476, commun) : la lame imprimée comme une carte d'état-major. Papier vert pâle mat, quadrillage kilométrique bleu,
lignes de niveau brunes autour de deux sommets placés à la main (relief lisse, pas de bruit) : une ligne maîtresse plus
épaisse toutes les cinq, avec sa cote. Garde et pommeau olive, manche d'origine noir.
"""

import numpy as np
from common import font

# Papier vert pâle et quadrillage bleu : sur un fond sable, des courbes brunes allongées se lisaient comme du bois
PAPER = np.array([0.74, 0.79, 0.66])
BROWN = np.array([0.42, 0.28, 0.15])
GRIDC = np.array([0.22, 0.42, 0.62])
OLIVE = np.array([0.36, 0.36, 0.24])
# Sommets : centre (t, h), hauteur, étalements le long et en travers de leur axe, angle de l'axe (degrés) ; des
# sommets ronds donnaient des cercles concentriques (une cible, des cernes d'arbre), pas une carte
HILLS = (
	((-0.50, 0.04), 1.0, 0.42, 0.17, 18.0),
	((-1.35, -0.06), 0.8, 0.30, 0.13, -24.0),
	((-0.95, 0.00), 0.45, 0.30, 0.10, 0.0),  # crête entre les deux sommets (col)
	((0.05, -0.25), -0.35, 0.25, 0.20, 0.0),  # vallon au talon, côté tranchant
)
SLOPE = 0.12
STEP = 0.09  # équidistance des courbes (en hauteur de relief)
LINE = 0.0038  # demi-largeur d'une courbe ordinaire (unités de toile) ; une maîtresse fait le double
GRID = 0.25  # pas du quadrillage
LABELS = (("450", (-0.05, -0.12)), ("500", (-1.72, 0.06)))  # cotes posées sur le papier, près des courbes maîtresses
GRID_W = 0.0028


def relief(t, h):
	"""Cette méthode permet de calculer le relief lisse de la carte (somme de sommets gaussiens et d'une pente douce)."""
	z = SLOPE * (t + 2.2)
	for (ct, ch), amp, sa, sb, ang in HILLS:
		a = np.radians(ang)
		u = (t - ct) * np.cos(a) + (h - ch) * np.sin(a)
		v = -(t - ct) * np.sin(a) + (h - ch) * np.cos(a)
		z = z + amp * np.exp(-((u / sa) ** 2 + (v / sb) ** 2) / 2)
	return z


def compose(kn):
	"""Cette méthode permet de tracer les courbes de niveau à largeur constante (écart au niveau divisé par la pente), les
	maîtresses toutes les cinq, et le quadrillage."""
	t, h = kn.grid()
	z = relief(t, h)
	gz_h, gz_t = np.gradient(z, -1.0 / 640, 1.0 / 640)
	slope = np.maximum(np.hypot(gz_t, gz_h), 1e-4)
	k = np.round(z / STEP)
	d = np.abs(z - k * STEP) / slope
	master = np.mod(k, 5) == 0
	lines = d < np.where(master, 2 * LINE, LINE)
	grid = (np.abs(np.mod(t + GRID / 2, GRID) - GRID / 2) < GRID_W) | (np.abs(np.mod(h, GRID) - GRID / 2) < GRID_W)
	kn.put("courbes", lines)
	kn.put("grille", grid & ~lines)
	for label, c in LABELS:
		kn.text("courbes", label, c, 0.028, lambda s: font("bahnschrift.ttf", s), angle=180)  # lisibles en 1P
	for hill in HILLS[:2]:
		kn.disc("courbes", hill[0], 0.008)


def paint(kn):
	"""Cette méthode permet d'imprimer la carte (fond sable, quadrillage, courbes) sur la lame et de passer garde et pommeau
	à l'olive."""
	compose(kn)
	lines = kn.sample("courbes", blur=0.6) * kn.blade
	grid = kn.sample("grille", blur=0.6) * kn.blade
	kn.paint(kn.blade, PAPER, 0.65, 0.0, detail=0.3, ao=0.5)
	kn.paint(grid, GRIDC, 0.65, 0.0, detail=0.3, ao=0.5)
	kn.paint(lines, BROWN, 0.65, 0.0, detail=0.3, ao=0.5)
	kn.edge(0.12)
	kn.paint(kn.guard | kn.pommel, OLIVE, 0.6, 0.0, detail=0.5)
