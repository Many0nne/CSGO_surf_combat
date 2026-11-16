"""TREMPE (#417) : anodisé dégradé. Toute l'arme prend les couleurs de revenu de l'acier chauffé, du bleu profond à la
bouche (le plus chaud) au violet, au bronze puis à la paille vers la crosse, en métal brossé le long du canon.
Le front des couleurs ondule (bruit 3D) et dessine de fines franges, comme une trempe au chalumeau.
Plaque de couche, busc et vis restent d'origine ; culasse polie.
"""

import numpy as np

from common import X, Z, fbm
from common import paint as ink

# couleurs de revenu, de la plus chaude (bouche) à la plus froide (crosse), en sRGB direct
STOPS = np.array(
	[
		(0.42, 0.58, 0.74),  # bleu pâle
		(0.12, 0.24, 0.60),  # bleu de roi
		(0.26, 0.16, 0.46),  # violet sombre
		(0.56, 0.30, 0.26),  # bronze cuivré
		(0.70, 0.54, 0.30),  # paille foncée
		(0.78, 0.71, 0.54),  # paille claire
		(0.62, 0.62, 0.63),  # acier nu (non chauffé)
	]
)
X0, X1 = -2.6, 3.5  # dégradé serré sur le châssis (vu en 1P) ; le canon reste bleu


def temper(m):
	"""Cette méthode permet de calculer la couleur de revenu de chaque texel (position le long de l'arme, front ondulé)."""
	p = m.p
	t = (p[:, 0] - X0) / (X1 - X0) + 0.10 * p[:, 2] + 0.07 * fbm(p, 0.9, 81, 3)
	t = np.clip(t, 0, 1) * (len(STOPS) - 1)
	i = np.minimum(t.astype(int), len(STOPS) - 2)
	f = t - i
	f = f * f * (3 - 2 * f)
	col = STOPS[i] * (1 - f)[:, None] + STOPS[i + 1] * f[:, None]
	edge = 1 - np.abs(f * 2 - 1)  # 1 au milieu d'une transition, 0 sur une teinte franche
	fringe = 0.5 + 0.5 * np.sin(t * 2 * np.pi * 4.0)  # franges fines dans les transitions
	return col * (1 - 0.22 * edge * fringe)[:, None]


def brushed(m, sel, seed):
	"""Cette méthode permet de poser des stries de brossage le long de l'arme (relief et rugosité)."""
	s = fbm(m.p[sel] * np.array([0.04, 1, 1]), 0.003, seed, 2)
	m.height[sel] += 0.00025 * s
	m.rough[sel] = m.rough[sel] + 0.04 * s


def anodize(m, sel, seed, rough=0.28):
	"""Cette méthode permet de peindre l'anodisé dégradé sur une sélection de texels (métal 1, creux assombris)."""
	sel = np.asarray(sel, bool)
	col = temper(m)
	ink(m, sel.astype(float), (1, 1, 1), rough, 1.0)
	m.color[sel] = col[sel] * (0.6 + 0.4 * np.clip(m.ao[sel], 0, 1))[:, None]
	brushed(m, sel, seed)


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre TREMPE sur les quatre matériaux de l'AWP."""
	wood = maps["WOOD"]
	wood.height *= 0.15  # l'anodisé lisse le granité du polymère
	anodize(wood, np.ones(len(wood.p), bool), 83, rough=0.3)

	a = maps["METAL_A"]
	bolt = a.is_("Bolt")
	anodize(a, ~bolt, 85)
	ink(a, bolt, (0.72, 0.72, 0.74), 0.16, 1.0)  # culasse polie miroir

	b = maps["METAL_B"]
	x, z = b.p[:, 0], b.p[:, 2]
	fit = b.is_("Fittings")
	pad = fit & ((x > X(3555)) | ((z > Z(392)) & (x > X(3190))))  # plaque de couche et busc (cf. make_textures.py)
	mount = fit & (z > 0.14) & (x > X(2300)) & (x < X(2640))
	screws = fit & ~mount & ~pad
	anodize(b, ~pad & ~screws, 87)

	s = maps["SCOPE"]
	y, zs = s.p[:, 1], s.p[:, 2] - 0.504
	r = np.hypot(y, zs)
	inside = ((s.p[:, 0] < X(1888)) & (r < 0.1885)) | ((s.p[:, 0] > X(2928)) & (r < 0.1055))
	anodize(s, ~inside, 89)
