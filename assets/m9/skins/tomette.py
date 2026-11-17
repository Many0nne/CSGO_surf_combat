"""TOMETTE (#495, commun de la série 2) : la lame pavée de tomettes hexagonales en terre cuite rouge, cirées, posées en
nid d'abeille aligné sur l'axe du couteau, joints de chaux clairs en léger creux. Chaque tomette a sa nuance de cuisson,
un peu plus claire en son centre usé. Fil repoli ; garde et pommeau en métal sombre satiné, manche d'origine noir.
"""

import numpy as np
from common import fbm, smooth

R = 0.078  # rayon d'une tomette (centre à sommet, unités) : trois rangées et demie au talon ; à 0,062 le pavage
# faisait peau de serpent en 1re personne
JOINT = 0.013  # largeur d'un joint
# Terre cuite, plus rouge que l'ocre de SPHINX. Saumon sur la planche Cycles, mais rouge sang en jeu à (0,55 ; 0,22 ;
# 0,13) : le crépuscule assombrit et rougit, d'où un ton plus clair et plus orangé
TERRA = np.array([0.72, 0.34, 0.19])
LIME = np.array([0.80, 0.76, 0.68])  # joint de chaux
METAL_DARK = np.array([0.15, 0.15, 0.17])
SQ3 = np.sqrt(3.0)


def hexagons(t, h):
	"""Cette méthode permet de donner, en chaque point (t, h), la distance au bord de sa tomette (unités) et un
	identifiant de tomette, sur un pavage d'hexagones à sommets vers le dos et le tranchant."""
	# Coordonnées axiales (hexagones « pointe en haut ») puis arrondi cubique à la tomette la plus proche
	q = (SQ3 / 3 * t - h / 3) / R
	r = (2 / 3 * h) / R
	x, z = q, r
	y = -x - z
	rx, ry, rz = np.round(x), np.round(y), np.round(z)
	dx, dy, dz = np.abs(rx - x), np.abs(ry - y), np.abs(rz - z)
	fix_x = (dx > dy) & (dx > dz)
	fix_y = ~fix_x & (dy > dz)
	rx = np.where(fix_x, -ry - rz, rx)
	ry = np.where(fix_y, -rx - rz, ry)
	rz = np.where(~fix_x & ~fix_y, -rx - ry, rz)
	ct = R * SQ3 * (rx + rz / 2)
	ch = R * 1.5 * rz
	pt, ph = np.abs(t - ct), np.abs(h - ch)
	# Hexagone pointe en haut : apothème R·√3/2 face aux côtés verticaux et obliques
	d_hex = np.maximum(pt, (pt * 0.5 + ph * SQ3 / 2))
	edge = R * SQ3 / 2 - d_hex
	ident = (rx.astype(np.int64) * 7919 + rz.astype(np.int64) * 104729) % 9973
	centre = np.clip(1 - np.hypot(t - ct, h - ch) / R, 0, 1)
	return edge, ident, centre


def paint(kn):
	"""Cette méthode permet de paver la lame de tomettes nuancées une à une, de creuser les joints de chaux, de repolir
	le fil et de noircir garde et pommeau."""
	m = kn.m
	t, h = kn.grid()
	edge, ident, centre = hexagons(t, h)
	joint = kn.sil & (edge < JOINT / 2)
	kn.put("joint", joint)
	# Nuance de cuisson par tomette (±8 % de clarté, rouge un peu plus ou moins brun) et centre usé plus clair
	shade = ((ident * 0.618) % 1.0) * 0.16 - 0.08
	brown = ((ident * 0.381) % 1.0) * 0.06
	lime = kn.sample("joint", blur=0.6) * kn.blade
	nuance = kn.sample_array(shade.astype(np.float32), order=0)
	brun = kn.sample_array(brown.astype(np.float32), order=0)
	usure = kn.sample_array(centre.astype(np.float32))
	clay = m.field(lambda p: fbm(p * 30, 3, 211))
	col = TERRA * (1 + nuance + 0.06 * usure + 0.04 * clay)[..., None]
	col = col * (1 - brun[..., None] * np.array([0.0, 0.6, 0.9]))
	kn.paint(kn.blade, col, 0.5 - 0.1 * usure, 0.0, detail=0.2, ao=0.5)
	kn.paint(lime, LIME * (0.95 + 0.05 * clay)[..., None], 0.85, 0.0, detail=0.2, ao=0.6)
	kn.height = kn.height + (clay * 0.03 + smooth(0.0, 1.0, usure) * 0.08 - lime * 0.4) * kn.blade
	kn.edge(0.12)
	kn.paint(kn.guard | kn.pommel, METAL_DARK, 0.45, 1.0, detail=0.5)
