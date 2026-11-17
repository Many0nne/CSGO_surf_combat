"""CUIR DE CORDOUE (#515, légendaire de la série 2) : tenture de cuir doré espagnole (guadamecí, XVIIe siècle).
Illustration peinte par un modèle d'image sur le gabarit de la M9 (`gabarit.py`, source `art/cordoue.png`, brief
`art/cordoue.brief.md`) : un paon vers la pointe sur le talon (vu en 1P), volute d'acanthe et grenades vers la pointe,
sur fond d'or bruni piqué au poinçon. Comme sur le vrai cuir, les couleurs sont des glacis sur la feuille d'or : tout le
dessin est posé en métal teinté, les cernes brun sombre en métal plus mat.

Marche au-dessus des exceptionnels : le manche est gainé du même cuir, tanné rouge sang de bœuf et gaufré en losanges
dont les filets et les fleurons sont dorés au fer ; garde et pommeau en or bruni piqué au poinçon.
"""

import numpy as np

import illustration
from common import fbm, smooth

GOLD = np.array([0.90, 0.70, 0.34])
LEATHER = np.array([0.30, 0.085, 0.055])  # cuir tanné « sang de bœuf », posé en métal teinté (voile gris sinon)
OUTLINE = np.array([0.12, 0.06, 0.03])
LOZENGE = 0.105  # pas du gaufrage du manche (unités, le long de l'axe et du tour)
AROUND = 9  # losanges sur un tour du manche (2π × 0,15 / 0,105 ≈ 9)
FILET = 0.0075  # demi-largeur d'un filet doré au fer (unités)
FLEURON = 0.014  # rayon du fleuron doré au centre de chaque losange (unités)
PUNCH = 0.016  # pas du piqué au poinçon de la garde et du pommeau (unités)


def gilt(col):
	"""Cette méthode permet de repérer le fond d'or de l'illustration (teinte jaune ocre, assez claire) : 0 à 1."""
	mx, mn = col.max(-1), col.min(-1)
	sat = (mx - mn) / np.maximum(mx, 1e-3)
	r, g, b = col[..., 0], col[..., 1], col[..., 2]
	yellow = (r >= g) & (g > b) & ((g - b) > 0.45 * (r - b))  # teinte entre ~30 et 60°
	return yellow * smooth(0.25, 0.45, sat) * smooth(0.30, 0.50, mx)


def blade(kn):
	"""Cette méthode permet d'imprimer l'illustration sur la lame : fond d'or et glacis en métal, cernes plus mats."""
	g, rgb, score = illustration.load(kn, illustration.source("cordoue"))
	print(f"[cordoue] illustration recalée sur le gabarit, recouvrement {score:.3f}")
	col = illustration.sample(kn, g, rgb)
	lum = illustration.print_blade(kn, col, rough=0.5, frame=0.012, frame_col=GOLD * 0.75, frame_metal=1.0)
	flat = kn.blade * (1 - kn.sample("cadre", blur=0.6))
	gold = gilt(col)
	# glacis : tout ce qui n'est pas cerne passe en métal teinté, le fond d'or plus poli que les couleurs
	ink = smooth(0.06, 0.16, lum)
	kn.paint(flat * ink, col * 1.05, 0.42 - 0.12 * gold, 1.0, detail=0.08, ao=0.3)
	kn.paint(flat * (1 - ink), OUTLINE, 0.55, 0.6, detail=0.08, ao=0.3)
	# relief du cuir repoussé : les motifs colorés un peu en saillie, les cernes en creux
	kn.height = kn.height + flat * ((1 - gold) * ink * 0.2 - (1 - ink) * 0.25)
	kn.edge(0.1)


def grip(kn):
	"""Cette méthode permet de gainer le manche de cuir gaufré en losanges, filets et fleurons dorés au fer : le motif
	suit le tour du manche (angle autour de l'axe) pour rester régulier sur tout son pourtour."""
	m, z = kn.m, kn.grip
	f = (m.pos - kn.k.c) @ kn.k.flat
	ang = np.arctan2(f, kn.h)
	# abscisse autour du manche (rayon moyen ~0,15) : un nombre entier de losanges par tour, sans couture sous le manche
	s = ang / (2 * np.pi) * AROUND * LOZENGE
	u1, u2 = (kn.t + s) / LOZENGE, (kn.t - s) / LOZENGE
	d1 = np.abs(u1 - np.round(u1)) * LOZENGE  # distance au filet le plus proche, dans chaque sens
	d2 = np.abs(u2 - np.round(u2)) * LOZENGE
	filet = np.maximum(smooth(FILET, FILET * 0.6, d1), smooth(FILET, FILET * 0.6, d2))
	c1, c2 = np.abs(u1 - np.floor(u1) - 0.5), np.abs(u2 - np.floor(u2) - 0.5)
	fleuron = smooth(FLEURON, FLEURON * 0.7, np.hypot(c1, c2) * LOZENGE / np.sqrt(2))
	gilt_ = np.maximum(filet, fleuron) * z
	grain = m.field(lambda p: fbm(p * 60, 2, 91)) * 0.5 + 0.5
	m.normal[z] = (0.0, 0.0, 1.0)  # efface le quadrillage d'origine, le gaufrage le remplace
	kn.paint(z, LEATHER * (0.85 + 0.3 * grain)[..., None], 0.55, 0.7, detail=0.0, ao=0.5)
	kn.paint(gilt_, GOLD, 0.3, 1.0, detail=0.1, ao=0.4)
	# gaufrage : losanges bombés, filets et fleurons enfoncés au fer
	pad = np.minimum(d1, d2) / (LOZENGE / 2)
	kn.height = kn.height + z * (0.35 * np.sqrt(np.clip(pad, 0, 1)) - 0.3 * gilt_)


def hardware(kn):
	"""Cette méthode permet de dorer garde et pommeau à l'or bruni, piqué au poinçon sur les plats, arêtes lisses."""
	m = kn.m
	hw = kn.guard | kn.pommel
	q = m.pos / PUNCH
	d = np.linalg.norm(q - np.round(q), axis=-1) * PUNCH
	punch = smooth(PUNCH * 0.22, PUNCH * 0.12, d) * (1 - smooth(0.2, 0.6, m.edges))
	kn.paint(hw, GOLD * (0.85 + 0.25 * smooth(0.2, 0.8, m.edges))[..., None], 0.26, 1.0, detail=0.5)
	kn.paint(hw * punch, GOLD * 0.55, 0.5, 1.0, detail=0.2)
	kn.height = kn.height - hw * punch * 0.3


def paint(kn):
	"""Cette méthode permet de peindre CUIR DE CORDOUE : illustration sur la lame, manche gainé, garde et pommeau dorés."""
	blade(kn)
	grip(kn)
	hardware(kn)
