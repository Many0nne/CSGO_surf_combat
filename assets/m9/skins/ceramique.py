"""CÉRAMIQUE (#476, commun) : revêtement céramique bicolore, comme un couteau d'atelier. Haut de la lame bleu acier mat,
bas noir côté tranchant, séparés par un filet clair sur une ligne qui suit la forme de la lame jusqu'à la pointe ; fil
repoli. Garde et pommeau noirs, manche d'origine noir.

Pistes écartées : une bande noire le long du dos (les dents ne laissent que 0,015 unité entre la gouttière et leur
creux : invisible) et le grand biseau en noir (de profil il ne fait qu'un liseré).
"""

import numpy as np
from common import H1, S, fbm
from scipy import ndimage

BLUE = np.array([0.27, 0.38, 0.50])
BLACK = np.array([0.15, 0.15, 0.17])  # métal sombre satiné : en non-métal il prenait un voile gris
PIN = np.array([0.82, 0.82, 0.78])
SPLIT = 0.33  # part de la hauteur de la lame, depuis le tranchant, couverte de noir
PIN_W = 0.008  # largeur du filet clair (unités)
TEETH = 0.12  # fenêtre (unités) du maximum glissant qui comble les creux des dents


def split_line(kn):
	"""Cette méthode permet de donner, pour chaque colonne de toile, la hauteur h de la séparation : à SPLIT de la hauteur
	de la lame au-dessus du tranchant, le dos étant lissé par-dessus les dents."""
	has = kn.sil.any(0)
	rows = np.arange(kn.hpx)[:, None]
	top = np.where(has, H1 - np.argmax(kn.sil, axis=0) / S, -1.0)
	bottom = np.where(has, H1 - np.max(np.where(kn.sil, rows, 0), axis=0) / S, -1.0)
	top = ndimage.maximum_filter1d(top, int(TEETH * S))
	return ndimage.gaussian_filter1d(bottom + SPLIT * (top - bottom), 8)


def compose(kn):
	"""Cette méthode permet de calculer le noir (sous la séparation) et le filet clair posé dessus."""
	_, h = kn.grid()
	cut = split_line(kn)[None, :]
	kn.put("noir", (h < cut) & kn.sil)
	kn.put("filet", (np.abs(h - cut) < PIN_W / 2) & (kn.dist > PIN_W) & kn.sil)


def paint(kn):
	"""Cette méthode permet de poser le revêtement bleu, le noir côté tranchant et le filet sur leur séparation, puis de
	noircir garde et pommeau."""
	m = kn.m
	compose(kn)
	black = kn.sample("noir", blur=0.6) * kn.blade
	pin = kn.sample("filet", blur=0.6) * kn.blade
	grain = m.field(lambda p: fbm(p * 60, 2, 97))
	kn.paint(kn.blade, BLUE * (1 + 0.03 * grain)[..., None], 0.55, 0.0, detail=0.25, ao=0.5)
	kn.paint(black, BLACK, 0.5, 1.0, detail=0.25, ao=0.5)
	kn.paint(pin, PIN, 0.45, 0.0, detail=0.2, ao=0.3)
	kn.height = kn.height + grain * 0.015 * kn.blade
	kn.edge(0.12)
	kn.paint(kn.guard | kn.pommel, BLACK, 0.5, 1.0, detail=0.5)
