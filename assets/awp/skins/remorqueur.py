"""REMORQUEUR (#433) : hommage au cargo minier du film de science-fiction de 1979 (design industriel de Ron Cobb), sans
rien en reprendre tel quel. Coque crème jaunie et salie, découpée en plaques rivetées ; pictogrammes carrés à coins
arrondis dessinés pour le jeu (cadre rouge, bleu ou noir sur fond crème) ; hexagone d'accès au pochoir ; étiquette de
danger jaune ; sur l'arrière de crosse, un écran à texte vert phosphore. Chargeur rouge extincteur, lunette crème.
Coordonnées en pixels de la photo de profil (build_awp.py : STOCK, HANDGUARD, SCREWS).
"""

import math

import numpy as np

from common import JOINT, X, chassis, chip, fbm, font, outline, zone
from common import paint as ink

CREAM = (0.72, 0.68, 0.57)  # plastique blanc cassé jauni
CREAM_DIRT = (0.50, 0.46, 0.37)  # coulures de crasse
SEAM = (0.12, 0.11, 0.10)  # fond des joints de plaques
RED = (0.72, 0.09, 0.07)
BLUE = (0.09, 0.19, 0.52)
BLACK = (0.035, 0.035, 0.04)
YELLOW = (0.92, 0.70, 0.08)
GREEN = (0.42, 1.0, 0.50)  # texte de l'écran
SCREEN = (0.025, 0.055, 0.035)
PRIMER = (0.30, 0.30, 0.31)  # sous-couche grise vue sur les éclats
SEAMS_X = (1965, 2215, 2905, 3150)  # joints verticaux de plaques (le joint garde-main / crosse JOINT en est un aussi)


def stencil(size):
	"""Cette méthode permet d'obtenir la police des marquages au pochoir (Bahnschrift gras condensé)."""
	return font("bahnschrift.ttf", size, "Bold Condensed")


def terminal(size):
	"""Cette méthode permet d'obtenir la police de l'écran (Consolas gras, chasse fixe de terminal)."""
	return font("consolab.ttf", size)


def rounded(c, half, r, steps=4):
	"""Cette méthode permet d'obtenir le contour d'un carré à coins arrondis de centre c et de demi-côté half (px photo)."""
	pts = []
	for k, (sx, sy) in enumerate(((1, -1), (1, 1), (-1, 1), (-1, -1))):
		ox, oy = c[0] + sx * (half - r), c[1] + sy * (half - r)
		for i in range(steps + 1):
			a = math.radians(-90 + 90 * k + 90 * i / steps)
			pts.append((ox + r * math.cos(a), oy + r * math.sin(a)))
	return pts


def icon(cv, c, half, color, glyph):
	"""Cette méthode permet de poser un pictogramme : cadre plein de la couleur, champ crème, symbole de la couleur."""
	cv.poly(color, rounded(c, half, half * 0.32))
	cv.poly("field", rounded(c, half * 0.6, half * 0.16))
	x, y, s = c[0], c[1], half * 0.42
	g = "glyph_" + color
	if glyph == "volt":  # éclair : haute tension
		cv.poly(g, [(x + 0.2 * s, y - s), (x - 0.45 * s, y + 0.1 * s), (x - 0.02 * s, y + 0.1 * s), (x - 0.25 * s, y + s), (x + 0.45 * s, y - 0.15 * s), (x + 0.02 * s, y - 0.15 * s)])
	elif glyph == "load":  # charge suspendue : flèche vers le bas sur une barre
		cv.poly(g, [(x - 0.75 * s, y - 0.2 * s), (x + 0.75 * s, y - 0.2 * s), (x, y + 0.55 * s)])
		cv.line(g, [(x, y - s), (x, y - 0.2 * s)], s * 0.32)
		cv.line(g, [(x - 0.85 * s, y + 0.85 * s), (x + 0.85 * s, y + 0.85 * s)], s * 0.26)
	elif glyph == "vent":  # ventilation : trois barres et un point
		for k in (-0.6, 0.0, 0.6):
			cv.line(g, [(x - 0.8 * s, y + k * s), (x + 0.35 * s, y + k * s)], s * 0.28)
		cv.circle(g, (x + 0.72 * s, y), s * 0.22)


def hexagon(c, r):
	"""Cette méthode permet d'obtenir le contour d'un hexagone à pointes en haut et en bas, de centre c et de rayon r."""
	return [(c[0] + r * math.cos(math.radians(90 + 60 * k)), c[1] + r * math.sin(math.radians(90 + 60 * k))) for k in range(6)]


def draw(cv):
	"""Cette méthode permet de tracer joints, rivets, pictogrammes, marquages et écran sur la toile de profil."""
	whole = chassis()
	holes = [outline("GUARD_HOLE"), outline("THUMBHOLE")]
	inside = zone(cv, whole, holes)
	# joints de plaques : un trait creux de haut en bas, bordé de rivets de part et d'autre
	for x in SEAMS_X + (JOINT,):
		if x != JOINT:
			cv.line("seam", [(x, 340), (x, 760)], 4)
		for y in range(380, 740, 26):
			for dx in (-11, 11):
				cv.circle("rivet", (x + dx, y), 3.2)
	cv.line("seam", [(SEAMS_X[0], 426), (JOINT, 426)], 4)  # joint horizontal du garde-main, derrière les pictogrammes
	cv.clip("seam", inside > 3)
	cv.clip("rivet", inside > 12)
	# pictogrammes sur le nez du garde-main (grands, cadre épais : lisibles de loin)
	for k, (color, glyph) in enumerate((("red", "volt"), ("blue", "load"), ("black", "vent"))):
		icon(cv, (1758 + 70 * k, 402), 31, color, glyph)
	# nom au pochoir et ligne de jauge sur l'arrière du garde-main
	cv.text("black", "REMORQUEUR", (2090, 397), 22, stencil)
	cv.line("red", [(1985, 452), (2195, 452)], 4)
	cv.line("red", [(1985, 462), (2195, 462)], 2)
	cv.text("black", "CHARGE 20 000 000 T  ·  ÉQUIPAGE 7", (2322, 400), 9, stencil)
	cv.text("black", "M-CLASS  /  2122", (2322, 455), 12, stencil)
	# hexagone d'accès au pochoir sur l'avant de la crosse
	hx = (2560, 452)
	cv.poly("red", hexagon(hx, 50), width=7)
	cv.text("black", "06", hx, 30, stencil)
	# étiquette de danger jaune bordée de noir
	cv.poly("black", [(2722, 378), (2822, 378), (2822, 420), (2722, 420)])
	cv.poly("yellow", [(2726, 382), (2818, 382), (2818, 416), (2726, 416)])
	cv.text("glyph_black", "DANGER", (2772, 399), 15, stencil)
	# écran à texte vert sur l'arrière de crosse (cadre noir, dalle, lignes de terminal)
	cv.poly("bezel", [(3172, 463), (3478, 463), (3478, 571), (3172, 571)])
	cv.poly("screen", [(3180, 470), (3470, 470), (3470, 564), (3180, 564)])
	lines = ("CIBLE     VERROUILLÉE", "VENT      0.4 / 270", "DISTANCE  0812 M", "ÉQUIPAGE  7 / 7 _")
	width = max(len(s) for s in lines)
	for i, s in enumerate(lines):  # chasse fixe : lignes complétées et centrées = alignées à gauche sur chaque flanc
		cv.text("phosphor", s.ljust(width), (3318, 487 + 22 * i), 12, terminal)


def chassis_paint(m, cv):
	"""Cette méthode permet de peindre crosse et garde-main : coque crème, coulures, encres du dessin, joints et éclats."""
	m.height *= 0.4  # la peinture lisse le granité
	ink(m, 1.0, CREAM, 0.55, 0.0)
	# coulures verticales de crasse, plus fortes vers le bas
	streak = fbm(m.p * np.array([1.0, 1.0, 0.3]), 0.16, 91, octaves=2)  # larges et peu nombreuses (pas un veinage)
	low = np.clip((0.2 - m.p[:, 2]) / 0.6, 0, 1)
	ink(m, np.clip(streak * 1.4 - 0.15, 0, 1) * (0.15 + 0.45 * low), CREAM_DIRT, 0.7, 0.0)
	for layer, col, rough in (
		("red", RED, 0.5),
		("blue", BLUE, 0.5),
		("black", BLACK, 0.6),
		("yellow", YELLOW, 0.5),
		("field", CREAM, 0.55),
		("glyph_red", RED, 0.5),
		("glyph_blue", BLUE, 0.5),
		("glyph_black", BLACK, 0.6),
		("bezel", BLACK, 0.55),
		("screen", SCREEN, 0.4),  # dalle mate : un reflet du ciel noyait le texte de trois quarts
		("phosphor", GREEN, 0.4),
	):
		ink(m, cv.sample(layer, m, blur=0.5), col, rough, 0.0)
	m.height *= 1 - cv.sample("bezel", m, blur=0.5)  # dalle lisse, sans le granité de la crosse
	seam = cv.sample("seam", m, blur=0.6)
	ink(m, seam, SEAM, 0.8, 0.0)
	m.height -= seam * 0.004
	rivet = cv.sample("rivet", m, blur=0.5)
	ink(m, rivet, (0.42, 0.40, 0.36), 0.4, 1.0)
	m.height += rivet * 0.003
	chip(m, -0.36, 81, PRIMER, rough=0.7, metal=0.0)


def metal_a(m):
	"""Cette méthode permet de peindre le chargeur en rouge extincteur (boîtier noir et culasse nue d'origine)."""
	mag = m.is_("Magazine")
	ink(m, mag & (m.p[:, 2] > -0.76), RED, 0.45, 0.0)
	chip(m, -0.45, 83, (0.45, 0.45, 0.47), rough=0.35, sel=mag)


def metal_b(m):
	"""Cette méthode permet de peindre le montage de lunette en crème (canon et frein noirs d'origine)."""
	x, z = m.p[:, 0], m.p[:, 2]
	mount = m.is_("Fittings") & (z > 0.14) & (x > X(2300)) & (x < X(2640))
	ink(m, mount, CREAM, 0.55, 0.0)
	chip(m, -0.4, 85, (0.42, 0.42, 0.44), rough=0.35, sel=mount)


def scope(m):
	"""Cette méthode permet de peindre la lunette en crème, bouts noirs, bague rouge et filet bleu, tourelles noires."""
	x, y, z = m.p[:, 0], m.p[:, 1], m.p[:, 2] - 0.504
	tx = X(2450)
	r = np.hypot(y, z)
	knob = (np.hypot(x - tx, y) < 0.09) & (z > 0.142)
	side = (np.hypot(x - tx, z) < 0.12) & (np.abs(y) > 0.142)
	inside = ((x < X(1888)) & (r < 0.1885)) | ((x > X(2928)) & (r < 0.1055))
	tube = ~knob & ~side & ~inside
	ink(m, tube, CREAM, 0.55, 0.0)
	ink(m, tube & ((x < X(1915)) | (x > X(2895))), BLACK, 0.55, 0.0)
	ink(m, tube & (x > X(2700)) & (x < X(2790)), RED, 0.5, 0.0)
	ink(m, tube & (x > X(2205)) & (x < X(2218)), BLUE, 0.5, 0.0)
	ink(m, (knob | side) & ~inside, (0.12, 0.12, 0.13), 0.5, 0.0)
	chip(m, -0.42, 87, PRIMER, rough=0.7, metal=0.0, sel=tube)


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre REMORQUEUR sur les quatre matériaux de l'AWP."""
	draw(cv)
	chassis_paint(maps["WOOD"], cv)
	metal_a(maps["METAL_A"])
	metal_b(maps["METAL_B"])
	scope(maps["SCOPE"])
