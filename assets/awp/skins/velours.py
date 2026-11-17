"""VELOURS (#492) : affiche pour lumière noire, scène de chasse nocturne. Illustration peinte par un modèle d'image sur
le gabarit de l'AWP (`gabarit.py`, source `art/velours.png`) : un grand-duc fond vers le canon, regard vers le joueur
sur l'avant de la crosse (vu en 1P) ; traînées fluo sur le garde-main ; pleine lune, pins et plumes sur l'arrière.
Les sombres sont posés en métal teinté (« candy », sinon voile gris en jeu), les clairs saturés en non-métal ; lueur
discrète sur les tons les plus clairs (yeux, lune, traînées). Cadre sombre sur le congé, qui absorbe les quelques
pixels d'écart entre la silhouette peinte et le châssis. Dessus, dessous et chargeur en velours nuit.
"""

import numpy as np
from PIL import Image

import illustration
from common import X, chassis, mt, outline, zone
from common import paint as ink

NIGHT = (0.10, 0.06, 0.20)  # velours nuit des faces sans dessin (métal teinté)
BLACK = (0.04, 0.03, 0.07)
FLUO = ((0.10, 0.88, 0.92), (1.00, 0.22, 0.60), (0.50, 1.00, 0.16))  # bagues de la lunette
FRAME = 9.0  # cadre sombre sur le congé (distance au bord, px photo)
GLOW = 0.35  # lueur des tons les plus clairs


def frame(cv):
	"""Cette méthode permet de tracer le cadre sombre qui suit le bord du châssis et le tour des trous."""
	dist = zone(cv, chassis(), [outline("GUARD_HOLE"), outline("THUMBHOLE")])
	img = Image.fromarray((((dist > 0) & (dist < FRAME)) * 255).astype(np.uint8))
	for layer in cv.layer("frame"):
		layer.paste(img, (0, 0))


def print_art(m, cv, rgb):
	"""Cette méthode permet de peindre le châssis : velours nuit partout, illustration sur les flancs, matière et
	lueur tirées de la luminance de chaque texel, puis cadre sombre."""
	ink(m, 1.0, NIGHT, 0.80, 1.0)
	m.height[:] = 0.0
	side = (np.abs(m.n[:, 1]) > 0.6).astype(np.float64)
	col = illustration.sample(rgb, m)
	lum = col @ np.array([0.2126, 0.7152, 0.0722])
	ao = 0.8 + 0.2 * np.clip(m.ao, 0, 1)
	m.color = m.color * (1 - side[:, None]) + col * ao[:, None] * side[:, None]
	dark = np.clip((0.30 - lum) / 0.15, 0, 1)  # fond sombre : métal teinté, sinon voile gris en jeu
	m.metal = m.metal * (1 - side) + dark * side
	m.rough = m.rough * (1 - side) + (0.62 + 0.18 * dark) * side
	m.emissive = np.clip((lum - 0.45) / 0.4, 0, 1) * GLOW * side
	k = cv.sample("frame", m, blur=0.5) * side
	ink(m, k, BLACK, 0.85, 1.0)
	m.emissive *= 1 - k


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre VELOURS sur les quatre matériaux de l'AWP."""
	rgb, score = illustration.load(illustration.source("velours"))
	print(f"[velours] illustration recalée sur le gabarit, recouvrement {score:.3f}")
	frame(cv)
	print_art(maps["WOOD"], cv, rgb)

	a = maps["METAL_A"]
	ink(a, a.is_("Magazine"), NIGHT, 0.80, 1.0)

	s = maps["SCOPE"]
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - mt.SCOPE_Z
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	ink(s, ~inside, BLACK, 0.80, 1.0)
	for x0, col in zip((X(1900), X(1990), X(2880)), FLUO):
		ink(s, ~inside & (np.abs(xs - x0) < 0.010), col, 0.55, 0.0)
