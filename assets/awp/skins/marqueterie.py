"""MARQUETERIE (#508, remplace VELOURS de #492 sous le même id) : panneau Art nouveau en bois incrusté, dans l'esprit
de l'École de Nancy. Illustration peinte par un modèle d'image sur le gabarit de l'AWP (`gabarit.py`, source
`art/marqueterie.png`, brief `art/marqueterie.brief.md`) : fond de wengé presque noir, héron cendré dans les roseaux sur
l'avant de la crosse (vu en 1P), ombelles le long du garde-main, lune de nacre sur l'arrière. Bois verni satiné, sans
lueur ; les sombres en métal teinté (sinon voile gris en jeu), la nacre assourdie (sinon un disque blanc qui se lit
comme un trou). Cadre de wengé sur le congé, qui absorbe l'écart entre la silhouette peinte et le châssis. Dessus et
dessous en wengé, lunette noire baguée de laiton.
"""

import numpy as np
from PIL import Image

import illustration
from common import X, chassis, mt, outline, zone
from common import paint as ink

WENGE = (0.075, 0.048, 0.034)  # fond du panneau, faces sans dessin et cadre (métal teinté)
BLACK = (0.03, 0.025, 0.022)
BRASS = (0.78, 0.60, 0.32)  # bagues de la lunette, comme les filets de laiton d'un meuble
FRAME = 9.0  # cadre sombre sur le congé (distance au bord, px photo)
NACRE_LUM, NACRE_TINT = 0.55, 2.0  # nacre de la lune : luminance gardée, reflets colorés amplifiés


def frame(cv):
	"""Cette méthode permet de tracer le cadre sombre qui suit le bord du châssis et le tour des trous."""
	dist = zone(cv, chassis(), [outline("GUARD_HOLE"), outline("THUMBHOLE")])
	img = Image.fromarray((((dist > 0) & (dist < FRAME)) * 255).astype(np.uint8))
	for layer in cv.layer("frame"):
		layer.paste(img, (0, 0))


def print_art(m, cv, rgb):
	"""Cette méthode permet de peindre le châssis : wengé partout, panneau sur les flancs, matière tirée de la
	luminance (sombres en métal teinté, bois clairs et nacre en vernis satiné), puis cadre de wengé."""
	ink(m, 1.0, WENGE, 0.70, 1.0)
	m.height[:] = 0.0
	side = (np.abs(m.n[:, 1]) > 0.6).astype(np.float64)
	col = illustration.sample(rgb, m)
	lum = col @ np.array([0.2126, 0.7152, 0.0722])
	sat = col.max(axis=1) - col.min(axis=1)
	ao = 0.85 + 0.15 * np.clip(m.ao, 0, 1)
	m.color = m.color * (1 - side[:, None]) + col * ao[:, None] * side[:, None]
	dark = np.clip((0.22 - lum) / 0.12, 0, 1)  # fond de wengé : métal teinté, sinon voile gris en jeu
	nacre = np.clip((lum - 0.62) / 0.1, 0, 1) * np.clip((0.14 - sat) / 0.06, 0, 1)
	# nacre : blanc uni = troisième trou ; baissée et reflets rose-vert accentués pour se lire comme une matière
	pearl = np.clip(NACRE_LUM * lum[:, None] + NACRE_TINT * (col - lum[:, None]), 0, 1)
	pick = (nacre * side)[:, None]
	m.color = m.color * (1 - pick) + pearl * ao[:, None] * pick
	m.metal = m.metal * (1 - side) + dark * side
	m.rough = m.rough * (1 - side) + (0.48 + 0.22 * dark) * side
	k = cv.sample("frame", m, blur=0.5) * side
	ink(m, k, WENGE, 0.70, 1.0)


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre MARQUETERIE sur les quatre matériaux de l'AWP."""
	rgb, score = illustration.load(illustration.source("marqueterie"))
	print(f"[marqueterie] illustration recalée sur le gabarit, recouvrement {score:.3f}")
	frame(cv)
	print_art(maps["WOOD"], cv, rgb)

	a = maps["METAL_A"]
	ink(a, a.is_("Magazine"), WENGE, 0.70, 1.0)

	s = maps["SCOPE"]
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - mt.SCOPE_Z
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	ink(s, ~inside, BLACK, 0.55, 1.0)
	for x0 in (X(1900), X(2880)):
		ink(s, ~inside & (np.abs(xs - x0) < 0.008), BRASS, 0.35, 1.0)
