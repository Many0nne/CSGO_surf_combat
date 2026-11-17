"""TAPISSERIE (#505, exceptionnel de la série 2) : tapisserie mille-fleurs sur fond de laine bleu nuit. Illustration
peinte par un modèle d'image sur le gabarit de la M9 (`gabarit.py`, source `art/tapisserie.png`, brief
`art/tapisserie.brief.md`) : un cerf blanc au collier d'or bondit vers la pointe sur le talon (vu en 1P), lapin et
oiseau parmi les fleurs vers la pointe, jeune chêne près de la garde. Laine mate, trame relevée en relief fin ; bordure
tissée brun sombre le long du contour, garde et pommeau en bronze patiné, manche teinté bleu nuit.
"""

import numpy as np

import illustration
from common import smooth

BORDER = np.array([0.10, 0.06, 0.04])
BRONZE = np.array([0.55, 0.40, 0.22])
NIGHT = np.array([0.05, 0.07, 0.15])
WEFT = 0.011  # pas de la trame (unités, ~2,5 texels) : rangs horizontaux le long de la lame


def paint(kn):
	"""Cette méthode permet de peindre TAPISSERIE : illustration en laine sur la lame, trame, bordure, garde et manche."""
	g, rgb, score = illustration.load(kn, illustration.source("tapisserie"))
	print(f"[tapisserie] illustration recalée sur le gabarit, recouvrement {score:.3f}")
	col = illustration.sample(kn, g, rgb)
	illustration.print_blade(kn, col, rough=0.78, frame=0.014, frame_col=BORDER, dark_gain=1.6)
	# Trame : rangs horizontaux, un peu plus marqués sur les clairs (fils de laine écrue du cerf et des fleurs)
	t, h = kn.grid()
	kn.put("trame", 0.5 + 0.5 * np.cos(2 * np.pi * h / WEFT))
	weft = kn.sample("trame", blur=0.0) * kn.blade
	kn.height = kn.height + (weft - 0.5) * 0.25
	kn.edge(0.1)
	kn.paint(kn.guard | kn.pommel, BRONZE * (0.85 + 0.25 * smooth(0.2, 0.8, kn.m.edges))[..., None], 0.42, 1.0, detail=0.6)
	kn.tint_grip(NIGHT)
