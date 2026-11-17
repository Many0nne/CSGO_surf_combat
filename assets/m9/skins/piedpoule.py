"""PIED-DE-POULE (#495, commun de la série 2) : la lame habillée d'un drap de laine tailleur en pied-de-poule anthracite
et gris perle, dents alignées sur l'axe du couteau, bordée d'un biais anthracite uni qui suit tout le contour (tranchant,
pointe, dos et trou). Laine mate au grain fin ; fil repoli. Garde et pommeau anthracite satiné, manche d'origine noir.
"""

import numpy as np
from common import fbm

PERIOD = 0.095  # côté d'un motif complet (unités) : quatre à cinq dents à la hauteur du talon, ~5 texels par demi-carreau
DARK = np.array([0.20, 0.20, 0.21])  # anthracite : plus sombre, la laine tombe au noir en jeu (docs/assets.md)
LIGHT = np.array([0.66, 0.65, 0.62])  # gris perle
BIAS = 0.024  # largeur du biais uni le long du contour
METAL_DARK = np.array([0.15, 0.15, 0.17])  # garde et pommeau : métal sombre satiné, pas de voile gris


def houndstooth(t, h):
	"""Cette méthode permet de donner le masque sombre du pied-de-poule en chaque point (t, h) : carré sombre et carré
	clair en damier, les deux autres carrés de chaque motif rayés en diagonale, ce qui dessine la dent."""
	fx, fy = (t / PERIOD) % 1, (h / PERIOD) % 1
	a, b = fx < 0.5, fy < 0.5
	return (a & b) | ((a != b) & ((2 * (fx - fy)) % 1 < 0.5))


def paint(kn):
	"""Cette méthode permet de tisser le pied-de-poule sur la lame, de poser le biais anthracite le long du contour, de
	repolir le fil et de noircir garde et pommeau."""
	m = kn.m
	t, h = kn.grid()
	field = kn.dist > BIAS
	kn.put("sombre", (field & houndstooth(t, h)) | (kn.sil & ~field))
	dark = kn.sample("sombre", blur=0.7) * kn.blade
	grain = m.field(lambda p: fbm(p * 70, 2, 131))
	wool = (1 + 0.05 * grain)[..., None]
	kn.paint(kn.blade, LIGHT * wool, 0.78, 0.0, detail=0.15, ao=0.5)
	kn.paint(dark, DARK * wool, 0.8, 0.0, detail=0.15, ao=0.5)
	kn.height = kn.height + (grain * 0.02 + dark * 0.04) * kn.blade
	kn.edge(0.12)
	kn.paint(kn.guard | kn.pommel, METAL_DARK, 0.45, 1.0, detail=0.5)
