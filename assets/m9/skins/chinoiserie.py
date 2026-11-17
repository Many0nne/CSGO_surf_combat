"""CHINOISERIE (#505, exceptionnel de la série 2) : papier peint de soie vert jade. Illustration peinte par un modèle
d'image sur le gabarit de la M9 (`gabarit.py`, source `art/chinoiserie.png`, brief `art/chinoiserie.brief.md`) : un
héron blanc en vol vers la pointe sur le talon (vu en 1P), une branche de cerisier vers la pointe, bambous et rochers
dorés près de la garde. Les rehauts d'or du dessin sont posés en vraie feuille d'or (métal), le reste en soie ; filet
d'or le long du contour, garde et pommeau dorés, manche teinté jade sombre.
"""

import numpy as np

import illustration
from common import smooth

GOLD = np.array([0.90, 0.70, 0.34])
JADE_DARK = np.array([0.05, 0.17, 0.11])


def gold_leaf(col):
	"""Cette méthode permet de repérer les rehauts d'or de l'illustration (teinte jaune ocre, saturée, assez claire)."""
	mx, mn = col.max(-1), col.min(-1)
	sat = (mx - mn) / np.maximum(mx, 1e-3)
	r, g, b = col[..., 0], col[..., 1], col[..., 2]
	yellow = (r >= g) & (g > b) & ((g - b) > 0.6 * (r - b))  # teinte entre ~35 et 60°
	return yellow * smooth(0.35, 0.55, sat) * smooth(0.40, 0.60, mx)


def paint(kn):
	"""Cette méthode permet de peindre CHINOISERIE : illustration sur la lame, feuille d'or, filet, garde et manche."""
	g, rgb, score = illustration.load(kn, illustration.source("chinoiserie"))
	print(f"[chinoiserie] illustration recalée sur le gabarit, recouvrement {score:.3f}")
	col = illustration.sample(kn, g, rgb)
	illustration.print_blade(kn, col, rough=0.55, frame=0.012, frame_col=GOLD, frame_metal=1.0)
	leaf = gold_leaf(col) * kn.flat * (1 - kn.sample("cadre", blur=0.6))
	kn.paint(leaf, col * 1.05, 0.3, 1.0, detail=0.1, ao=0.3)
	kn.height = kn.height + leaf * 0.25
	kn.edge(0.1)
	kn.paint(kn.guard | kn.pommel, GOLD * (0.85 + 0.25 * smooth(0.2, 0.8, kn.m.edges))[..., None], 0.28, 1.0, detail=0.6)
	kn.tint_grip(JADE_DARK)
