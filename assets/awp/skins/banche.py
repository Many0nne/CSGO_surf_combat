"""BANCHE : béton brut de décoffrage. Châssis gris clair lisse, découpé en panneaux de coffrage réguliers (joints fins en
creux, une teinte légèrement différente par panneau, un joint calé sur celui du garde-main et de la crosse) et percé de
trous de banche en grille régulière. Marquage de classe du béton au pochoir sur l'avant de la crosse (vu en 1P).
Lunette, montage et chargeur en tôle de coffrage anthracite ; canon d'origine.
"""

import numpy as np

from common import JOINT, X, chip, fbm, font, mt_px, mt_py
from common import paint as ink

CONCRETE = (0.60, 0.59, 0.56)  # presque blanc dans Cycles, gris moyen en jeu (à 0,36 : gris foncé en 1P)
STEEL = (0.32, 0.32, 0.33)
INK = (0.08, 0.08, 0.08)
PANEL_W, PANEL_H, TOP = 360, 180, 363  # panneau de coffrage (px photo), calé sur le joint et le dessus du châssis
TIE_DX, TIE_DY, TIE_R = 180, 90, 8.0  # trous de banche : 2 x 2 par panneau, rayon (px photo)


def panel_tone(col, row):
	"""Cette méthode permet de donner à chaque panneau une teinte fixe, un peu plus claire ou plus foncée (coulée par coulée)."""
	h = np.sin(col * 12.9898 + row * 78.233) * 43758.5453
	return 0.95 + 0.10 * (h - np.floor(h))


def stencil(cv):
	"""Cette méthode permet de poser au pochoir la classe du béton et le numéro de levée sur l'avant de la crosse."""
	f = lambda s: font("bahnschrift.ttf", s, "Bold Condensed")  # noqa: E731
	cv.text("stencil", "C35/45", (2612, 448), 22, f)
	cv.text("stencil", "LEVÉE 3", (2612, 476), 12, f)


def concrete(m, cv):
	"""Cette méthode permet de couler le béton sur le châssis : panneaux, joints en creux, trous de banche et pochoir."""
	px, py = mt_px(m.p[:, 0]), mt_py(m.p[:, 2])
	side = np.abs(m.n[:, 1]) > 0.6
	col, row = np.floor((px - JOINT) / PANEL_W), np.floor((py - TOP) / PANEL_H)
	mottle = fbm(m.p, 0.25, 121, 3) + 0.5 * fbm(m.p, 0.05, 127, 2)
	tone = panel_tone(col, row) * (1 + 0.07 * mottle)  # nuances de coulée dans la masse
	m.color[:] = np.outer(tone, CONCRETE) * (0.55 + 0.45 * np.clip(m.ao, 0, 1))[:, None]
	grain = fbm(m.p, 0.01, 123, 2)
	m.rough[:] = 0.86 + 0.04 * grain
	m.metal[:] = 0.0
	m.height[:] = 0.0003 * grain
	# joints de coffrage : lignes fines en creux (verticales sur tout le pourtour, horizontales sur les flancs)
	jx = np.abs((px - JOINT) / PANEL_W - np.round((px - JOINT) / PANEL_W)) * PANEL_W
	jy = np.abs((py - TOP) / PANEL_H - np.round((py - TOP) / PANEL_H)) * PANEL_H
	joint = (jx < 1.6) | (side & (jy < 1.6) & (py > TOP + 20))
	m.color[joint] *= 0.62
	m.height[joint] -= 0.0006
	# trous de banche : cône lisse puis fond sombre, en grille régulière sur les flancs
	tx = (px - JOINT - TIE_DX / 2) / TIE_DX
	ty = (py - TOP - TIE_DY / 2) / TIE_DY
	d = np.hypot((tx - np.round(tx)) * TIE_DX, (ty - np.round(ty)) * TIE_DY)
	cone = side & (d < TIE_R + 6)
	k = np.clip((TIE_R + 6 - d) / 6, 0, 1) * cone
	m.color *= (1 - 0.35 * k)[:, None]
	m.height -= 0.0012 * k
	hole = side & (d < TIE_R)
	m.color[hole] = np.outer(0.5 + 0.5 * (d[hole] / TIE_R), (0.16, 0.155, 0.15))
	m.height[hole] = -0.003
	m.rough[hole] = 0.95
	pore = fbm(m.p, 0.006, 129, 1) > 0.75  # bullage : à 0,7 de teinte, les pores faisaient des points noirs de saleté en 1P
	m.color[pore] *= 0.88
	m.height[pore] -= 0.0004
	sten = cv.sample("stencil", m, blur=0.4) * side * (0.8 + 0.2 * np.clip(fbm(m.p, 0.03, 125, 2) + 0.5, 0, 1))
	ink(m, sten * ~hole, INK, 0.9, 0.0)


def plate_steel(m, sel, seed):
	"""Cette méthode permet de peindre une tôle de coffrage anthracite mate, légèrement usée sur les arêtes."""
	ink(m, sel, STEEL, 0.55, 0.0)
	chip(m, -0.4, seed, (0.48, 0.48, 0.50), rough=0.35, sel=sel)


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre BANCHE sur les quatre matériaux de l'AWP."""
	stencil(cv)
	concrete(maps["WOOD"], cv)

	a = maps["METAL_A"]
	plate_steel(a, a.is_("Magazine") & (a.p[:, 2] > -0.76), 131)

	b = maps["METAL_B"]
	x, z = b.p[:, 0], b.p[:, 2]
	mount = b.is_("Fittings") & (z > 0.14) & (x > X(2300)) & (x < X(2640))
	plate_steel(b, mount, 133)

	s = maps["SCOPE"]
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - 0.504
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	tx = X(2450)
	turret = ((np.hypot(xs - tx, y) < 0.09) & (zs > 0.142)) | ((np.hypot(xs - tx, zs) < 0.12) & (np.abs(y) > 0.142))
	ring = (xs > X(2700)) & (xs < X(2790))
	tube = ~inside & ~turret & ~ring
	plate_steel(s, tube, 135)
	ink(s, tube & (np.abs(xs - X(2655)) < 0.03), CONCRETE, 0.86, 0.0)  # bague de béton devant la bague de grossissement
