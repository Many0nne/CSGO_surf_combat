"""CHANTIER (#476, commun) : la lame peinte comme un engin de travaux publics. Jaune signalisation mat ; sur le talon, un
bandeau de chevrons noirs et jaunes à 45° ; au milieu de la lame, un numéro de parc au pochoir. Garde et pommeau noirs ;
la peinture s'use jusqu'à l'acier sur les arêtes.
"""

import numpy as np
from common import STEEL, fbm, font, smooth

YELLOW = np.array([0.86, 0.66, 0.10])
BLACK = np.array([0.12, 0.12, 0.12])
HAZARD = (-0.16, 0.26)  # bandeau de chevrons : début et fin (t), sur toute la hauteur du talon
STRIPE = 0.055  # largeur d'une bande du bandeau
EDGE_GAP = 0.012  # liseré jaune entre le bandeau et le reste de la lame


def stencil(size):
	"""Cette méthode permet de charger la police pochoir (Stencil) à une taille en pixels de toile."""
	return font("STENCIL.TTF", size)


def compose(kn):
	"""Cette méthode permet de tracer le noir : bandes du bandeau de chevrons et numéro de parc au pochoir."""
	t, h = kn.grid()
	inside = (t > HAZARD[0]) & (t < HAZARD[1])
	stripes = np.mod((t + h) / (STRIPE * np.sqrt(2)), 2.0) < 1.0
	kn.put("noir", inside & stripes & (kn.dist > EDGE_GAP))
	kn.line("noir", [(HAZARD[0] - 0.02, -0.4), (HAZARD[0] - 0.02, 0.4)], 0.008)
	# En 1P la M9 est tenue tranchant en haut : textes tournés d'un demi-tour, le numéro côté tranchant pour rester au-dessus
	kn.text("noir", "07", (-0.62, -0.07), 0.11, stencil, angle=180)
	kn.text("noir", "CHARGE MAX 7 T", (-0.62, 0.075), 0.034, stencil, angle=180)


def paint(kn):
	"""Cette méthode permet de peindre la lame en jaune avec ses marquages noirs, de noircir garde et pommeau et d'user
	la peinture sur les arêtes."""
	m = kn.m
	compose(kn)
	black = kn.sample("noir", blur=0.6) * kn.blade
	grain = m.field(lambda p: fbm(p * 40, 2, 93))
	kn.paint(kn.blade, YELLOW * (1 + 0.04 * grain)[..., None], 0.6 + 0.04 * grain, 0.0, detail=0.3, ao=0.5)
	kn.paint(black, BLACK, 0.6, 0.0, detail=0.3, ao=0.5)
	kn.height = kn.height + black * 0.05 + grain * 0.03 * kn.blade
	hw = kn.guard | kn.pommel
	kn.paint(hw, BLACK * 1.3, 0.6, 0.0, detail=0.5)
	brk = m.field(lambda p: fbm(p * 6, 3, 95)) * 0.5 + 0.5
	chips = smooth(0.5, 0.58, m.edges * (0.55 + 0.6 * brk)) * (kn.blade | hw)
	kn.paint(chips, STEEL * 0.8, 0.3, 1.0, detail=0.5)
	kn.edge(0.12)
