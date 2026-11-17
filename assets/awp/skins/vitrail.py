"""VITRAIL (#487) : les flancs du châssis sont un vitrail serti de plomb. Une bordure de verres rubis et ambre en
alternance suit le contour (et le tour du pontet et du trou de pouce), le champ est un losangé de verres cobalt et bleu
ciel en damier, continu à travers le joint garde-main / crosse. Deux rosaces : une petite sur l'avant de la crosse (vue
en 1P), une grande sur l'arrière (cœur ambre, pétales rubis, couronne émeraude et opale). Verres plus clairs au centre
qu'au pied des plombs, comme traversés de lumière. Dessus, dessous, chargeur et lunette en étain sombre.
"""

import math

import numpy as np
from PIL import Image
from scipy import ndimage

from common import JOINT, PX0, PY0, SS, X, chassis, fbm, mt, outline, zone
from common import paint as ink

GLASS = {
	"ruby": (0.70, 0.06, 0.10),
	"amber": (0.95, 0.60, 0.12),
	"cobalt": (0.12, 0.26, 0.80),
	"sky": (0.32, 0.58, 0.92),
	"emerald": (0.08, 0.55, 0.30),
	"opal": (0.86, 0.84, 0.76),
}
PEWTER = (0.24, 0.24, 0.26)  # plomb et étain : métal sombre, ~0,2 au moins pour ne pas tomber au noir en jeu
TOP = 363  # dessus du châssis (px photo)
LEAD = 2.6  # demi-largeur d'un plomb (px photo, ~3,5 texels en tout)
FRAME, BORDER = 8.0, 30.0  # cadre de plomb puis bordure de verres, distances au bord (px photo)
STEP = 40.0  # pas des plombs qui découpent la bordure (px photo)
Q = 46.0  # côté d'un losange du champ (px photo)
ROSES = (((2592, 450), 62.0), ((3352, 508), 86.0))  # centre et rayon des rosaces (px photo)


def put(cv, name, arr):
	"""Cette méthode permet d'écrire un tableau (0 à 1, taille de la toile) dans une couche, sur les deux flancs."""
	img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
	for layer in cv.layer(name):
		layer.paste(img, (0, 0))


def came(d):
	"""Cette méthode permet de donner le profil arrondi d'un plomb (1 en son milieu, 0 au bord) à la distance d de son axe."""
	return np.sqrt(np.clip(1 - (d / LEAD) ** 2, 0, 1))


def rose(x, y, c, r):
	"""Cette méthode permet de calculer une rosace gothique de centre c et de rayon r : huit lobes circulaires qui se
	chevauchent autour d'un cœur (pétales rubis, recouvrements ambre), écoinçons émeraude entre les lobes et le cercle.
	Renvoie le disque, les plombs (profil) et la couleur de chaque verre. Des anneaux concentriques faisaient une cible."""
	dx, dy = x - c[0], y - c[1]
	rr = np.hypot(dx, dy)
	r0, dl, rl = 0.22 * r, 0.56 * r, 0.30 * r  # cœur, distance et rayon des lobes
	lead = np.maximum(came(rr - r0), came(rr - r))
	count = np.zeros_like(rr)
	for k in range(8):
		a = k * math.pi / 4 + math.pi / 8
		dk = np.hypot(dx - dl * math.cos(a), dy - dl * math.sin(a))
		count += dk < rl
		lead = np.maximum(lead, came(dk - rl) * (rr > r0))
	ring = (rr >= r0) & (rr < r)
	colors = {
		"amber": (rr < r0) | (ring & (count >= 2)),
		"ruby": ring & (count == 1),
		"emerald": ring & (count == 0),
	}
	return rr < r + LEAD, lead, colors


def draw(cv):
	"""Cette méthode permet de composer le vitrail sur la toile : une couche par verre, les plombs (profil) et la lueur
	(distance aux plombs) qui éclaire le centre de chaque verre."""
	holes = [outline("GUARD_HOLE"), outline("THUMBHOLE")]
	dist = zone(cv, chassis(), holes)
	yy, xx = np.mgrid[0 : cv.h, 0 : cv.w].astype(np.float32)
	x, y = xx / SS + PX0, yy / SS + PY0
	inside = dist > 0

	# bordure : plombs à pas fixe calés sur le joint et le dessus, verres rubis et ambre en damier
	gx, gy = (x - JOINT) / STEP, (y - TOP) / STEP
	grid = np.minimum(np.abs(gx - np.round(gx)), np.abs(gy - np.round(gy))) * STEP
	border = (dist >= FRAME) & (dist < BORDER)
	parity = np.mod(np.floor(gx) + np.floor(gy), 2) == 0
	lead = np.maximum(came(dist - FRAME), came(dist - BORDER)) * inside
	lead = np.maximum(lead, came(grid) * border)
	lead = np.maximum(lead, (dist < FRAME) * inside * 0.55)  # cadre de plomb plat sur le congé

	# champ : losangé cobalt et bleu ciel en damier, nœud sur le joint
	a = ((x - JOINT) + (y - TOP)) / math.sqrt(2) / Q
	b = ((x - JOINT) - (y - TOP)) / math.sqrt(2) / Q
	diag = np.minimum(np.abs(a - np.round(a)), np.abs(b - np.round(b))) * Q
	field = dist >= BORDER
	lead = np.maximum(lead, came(diag) * field)
	checker = np.mod(np.floor(a) + np.floor(b), 2) == 0
	colors = {
		"ruby": border & parity,
		"amber": border & ~parity,
		"cobalt": field & checker,
		"sky": field & ~checker,
	}
	for c, r in ROSES:
		disc, rlead, rcol = rose(x, y, c, r)
		disc &= inside
		lead = np.where(disc, rlead, lead)
		for name in colors:
			colors[name] &= ~disc
		for name, sel in rcol.items():
			colors[name] = colors.get(name, np.zeros_like(disc)) | (sel & disc)
	glow = np.clip(ndimage.distance_transform_edt(lead < 0.05) / SS / 14.0, 0, 1)
	put(cv, "lead", lead)
	put(cv, "glow", glow)
	for name, sel in colors.items():
		put(cv, name, sel & (lead < 0.05))


def glaze(m, cv):
	"""Cette méthode permet de peindre le châssis : étain sombre partout, puis verres et plombs sur les flancs."""
	ink(m, 1.0, PEWTER, 0.5, 1.0)
	m.height[:] = 0.0
	side = np.abs(m.n[:, 1]) > 0.6
	glow = cv.sample("glow", m, blur=0.5)
	ripple = fbm(m.p, 0.012, 181, 2)  # verre cathédrale : ondulation large
	hammer = fbm(m.p, 0.0045, 183, 2)  # martelage fin : les reflets se brisent d'un verre à l'autre
	ao = 0.65 + 0.35 * np.clip(m.ao, 0, 1)
	m.emissive = np.zeros(len(m.p))
	for name, rgb in GLASS.items():
		k = cv.sample(name, m, blur=0.5) * side
		light = np.minimum((0.72 + 0.38 * glow) * (0.94 + 0.12 * ripple) * ao, 1.0)
		col = np.outer(light, rgb)
		m.color = m.color * (1 - k[:, None]) + col * k[:, None]
		# verre brillant non métallique : mat (0,42), il faisait peinture ; en métal (« candy »), il ne renvoyait que
		# le ciel sombre du jeu et paraissait éteint
		m.rough = m.rough * (1 - k) + 0.10 * k
		m.metal = m.metal * (1 - k)
		m.height += k * (0.0006 * ripple + 0.00035 * hammer - 0.0008)
		# lueur : le verre semble traversé par le jour, plus fort au centre qu'au pied des plombs
		m.emissive += k * (0.30 + 0.35 * glow)
	lead = cv.sample("lead", m, blur=0.4) * side
	ink(m, np.clip(lead * 3, 0, 1), PEWTER, 0.45, 1.0)
	m.color *= (0.8 + 0.2 * lead)[:, None]
	m.height += 0.0014 * lead


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre VITRAIL sur les quatre matériaux de l'AWP."""
	draw(cv)
	glaze(maps["WOOD"], cv)

	a = maps["METAL_A"]
	ink(a, a.is_("Magazine"), PEWTER, 0.45, 1.0)

	s = maps["SCOPE"]
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - mt.SCOPE_Z
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	ink(s, ~inside, PEWTER, 0.42, 1.0)
	for x0 in (X(1900), X(1990), X(2880)):
		ink(s, ~inside & (np.abs(xs - x0) < 0.012), GLASS["ruby"], 0.3, 1.0)
