"""CAPITON (#487) : châssis tendu de cuir bordeaux capitonné comme un fauteuil Chesterfield. Coussins en losanges
réguliers (plis qui relient les boutons, bombé au centre), boutons recouverts du même cuir, en quinconce et jamais sur le
joint garde-main / crosse ; le capitonnage court d'une pièce à l'autre sans décalage. Un passepoil en relief suit le
contour du châssis et le tour du pontet et du trou de pouce, doublé d'une piqûre sellier au fil d'or. Plaque de laiton
gravée sur l'avant de la crosse (vue en 1P). Lunette et chargeur noir satiné, bagues, vis, détente et semelle en laiton.
"""

import numpy as np
from PIL import Image
from scipy import ndimage

from common import JOINT, SS, X, chassis, fbm, font, mt, mt_px, mt_py, outline, zone
from common import paint as ink

LEATHER = np.array((0.32, 0.035, 0.065))  # bordeaux lie-de-vin, teinte du reflet (~0,3 : une base plus sombre tombe au noir en jeu)
THREAD = (0.86, 0.66, 0.32)
BRASS = (0.80, 0.60, 0.28)
SATIN = (0.06, 0.055, 0.055)
HX, HY = 40.0, 48.0  # demi-pas du quinconce de boutons (px photo) : losanges de 80 x 96
X0, Y0 = JOINT + 20, 400  # un bouton de référence : les colonnes de boutons encadrent le joint sans le toucher
PIPE0, PIPE1 = 6.0, 15.0  # passepoil : distances au bord (px photo), le congé couvre les ~7 premiers px
STITCH = 19.0  # piqûre : distance au bord (px photo)
FIELD = 23.0  # capitonnage au-delà de cette distance au bord
BUTTON_R = 8.0  # rayon d'un bouton (px photo, ~5 texels)


def tufting(px, py):
	"""Cette méthode permet de calculer le capitonnage en un point de profil : bombé du coussin (0 au pli, 1 au centre),
	creux des plis qui relient les boutons, et présence d'un bouton (0 à 1) avec son anneau tiré autour."""
	s = (px - X0) / (2 * HX) + (py - Y0) / (2 * HY)
	t = (px - X0) / (2 * HX) - (py - Y0) / (2 * HY)
	fs, ft = s - np.floor(s), t - np.floor(t)
	pillow = np.sin(np.pi * fs) * np.sin(np.pi * ft)
	# distance au pli le plus proche, en px photo (un pli suit un bord du losange)
	edge = np.minimum.reduce([fs, 1 - fs, ft, 1 - ft]) / np.hypot(1 / (2 * HX), 1 / (2 * HY))
	crease = np.exp(-edge / 2.2)
	ds, dt = np.round(s) - s, np.round(t) - t
	r = np.hypot((ds + dt) * HX, (ds - dt) * HY)
	button = np.clip((BUTTON_R + 0.8 - r) / 1.6, 0, 1)
	dimple = np.exp(-np.maximum(r - BUTTON_R, 0) / 6.0) * (1 - button)
	dome = np.sqrt(np.clip(1 - (r / BUTTON_R) ** 2, 0, 1))
	return pillow, crease, button, dimple, dome


def draw(cv):
	"""Cette méthode permet de tracer sur la toile le passepoil, la piqûre, la zone capitonnée et la plaque de laiton."""
	holes = [outline("GUARD_HOLE"), outline("THUMBHOLE")]
	dist = zone(cv, chassis(), holes)
	# passepoil : cordon rond, la couche porte son profil (1 au sommet, 0 sur ses bords)
	mid, half = (PIPE0 + PIPE1) / 2, (PIPE1 - PIPE0) / 2
	cord = np.sqrt(np.clip(1 - ((dist - mid) / half) ** 2, 0, 1)) * (dist > 0)
	for img in cv.layer("pipe"):
		img.paste(Image.fromarray((cord * 255).astype(np.uint8)), (0, 0))
	# piqûre : points de 5 px tous les 8 px le long du contour (abscisse le long du bord tirée du gradient de distance)
	gy, gx = np.gradient(ndimage.gaussian_filter(dist, 3.0))
	yy, xx = np.mgrid[0 : cv.h, 0 : cv.w].astype(np.float32) / SS
	along = xx * np.abs(gy) + yy * np.abs(gx)
	norm = np.maximum(np.abs(gx) + np.abs(gy), 1e-6)
	dash = np.mod(along / norm, 8.0) < 5.0
	stitch = (np.abs(dist - STITCH) < 1.1) & dash
	for img in cv.layer("stitch"):
		img.paste(255, (0, 0), Image.fromarray((stitch * 255).astype(np.uint8)))
	for img in cv.layer("field"):
		img.paste(255, (0, 0), Image.fromarray(((dist > FIELD) * 255).astype(np.uint8)))
	# plaque de laiton à pans coupés, gravée, sur l'avant de la crosse
	cx, cy, hw, hh, c = 2592, 452, 74, 34, 9
	plate = [(cx - hw + c, cy - hh), (cx + hw - c, cy - hh), (cx + hw, cy - hh + c), (cx + hw, cy + hh - c),
		(cx + hw - c, cy + hh), (cx - hw + c, cy + hh), (cx - hw, cy + hh - c), (cx - hw, cy - hh + c)]
	cv.poly("plate", plate)
	cv.poly("plate_edge", plate, width=3.0)
	for sx in (-1, 1):
		for sy in (-1, 1):
			cv.circle("engrave", (cx + sx * (hw - 11), cy + sy * (hh - 10)), 3.2)
	f = lambda s: font("bahnschrift.ttf", s, "Bold Condensed")  # noqa: E731
	cv.text("engrave", "CAPITON", (cx, cy - 7), 20, f)
	cv.text("engrave", "CUIR PLEINE FLEUR", (cx, cy + 17), 9, f)


def upholster(m, cv):
	"""Cette méthode permet de tendre le cuir sur tout le châssis, de capitonner les flancs, puis de poser passepoil,
	piqûre et plaque de laiton."""
	px, py = mt_px(m.p[:, 0]), mt_py(m.p[:, 2])
	side = np.abs(m.n[:, 1]) > 0.6
	grain = fbm(m.p, 0.0035, 171, 2)
	ao = 0.6 + 0.4 * np.clip(m.ao, 0, 1)
	m.color[:] = np.outer((0.92 + 0.08 * grain) * ao, LEATHER)
	# posé en métal (« candy ») : en non-métal, le reflet du ciel voilait le bordeaux en rose
	m.rough[:] = 0.55 + 0.06 * grain
	m.metal[:] = 1.0
	m.height[:] = 0.00012 * grain

	field = cv.sample("field", m, blur=1.5) * side
	pillow, crease, button, dimple, dome = tufting(px, py)
	puff = np.sqrt(pillow)
	shade = (0.55 + 0.45 * puff) * (1 - 0.65 * crease) * (1 - 0.75 * dimple)  # cuir patiné : plis et creux bruns
	shade = shade * (1 - button) + button * (0.55 + 0.40 * dome)
	k = field
	m.color *= (1 - k + k * shade)[:, None]
	m.rough -= k * 0.12 * puff * (1 - button)  # le haut des coussins est lustré par l'usage
	m.rough += k * 0.15 * button  # boutons mats : lustrés, ils brillaient comme des perles
	m.height += k * (0.0045 * puff - 0.0012 * crease - 0.0015 * dimple + button * (0.0010 * dome - 0.0010))

	pipe = cv.sample("pipe", m, blur=0.5) * side  # profil du cordon
	on = np.clip(pipe * 4, 0, 1)
	m.color *= (1 - on * (0.35 - 0.25 * pipe))[:, None]  # cordon sombre à ses pieds, clair au sommet
	m.height += 0.0018 * pipe
	m.rough -= 0.08 * on
	st = cv.sample("stitch", m, blur=0.4) * side
	ink(m, st, THREAD, 0.45, 0.0)
	m.height += 0.0003 * st

	plate = cv.sample("plate", m, blur=0.4) * side
	ink(m, plate, BRASS, 0.30, 1.0, keep_ao=False)
	m.height = m.height * (1 - plate) + plate * 0.0035
	edge = cv.sample("plate_edge", m, blur=0.4) * side
	m.color *= (1 - 0.25 * edge)[:, None]
	eng = cv.sample("engrave", m, blur=0.4) * side * plate
	ink(m, eng, (0.16, 0.11, 0.05), 0.6, 0.6)
	m.height -= 0.0006 * eng


def rings(m, sel, xs, half):
	"""Cette méthode permet de poser des bagues de laiton autour des abscisses xs (demi-largeur half, unités monde)."""
	for x0 in xs:
		ink(m, sel & (np.abs(m.p[:, 0] - x0) < half), BRASS, 0.30, 1.0)


def paint(maps, cv):  # point d'entrée attendu par paint.py
	"""Cette méthode permet de peindre CAPITON sur les quatre matériaux de l'AWP."""
	draw(cv)
	upholster(maps["WOOD"], cv)

	a = maps["METAL_A"]
	mag = a.is_("Magazine")
	ink(a, mag, SATIN, 0.38, 1.0)
	ink(a, mag & (a.p[:, 2] < -0.74), BRASS, 0.30, 1.0)
	ink(a, a.is_("Trigger"), BRASS, 0.30, 1.0)

	b = maps["METAL_B"]
	x, z = b.p[:, 0], b.p[:, 2]
	fit = b.is_("Fittings")
	mount = fit & (z > 0.14) & (x > X(2300)) & (x < X(2640))
	pad = fit & ((x > X(3555)) | ((z > -0.106) & (x > X(3190))))
	ink(b, fit & ~mount & ~pad, BRASS, 0.30, 1.0)

	s = maps["SCOPE"]
	xs, y, zs = s.p[:, 0], s.p[:, 1], s.p[:, 2] - mt.SCOPE_Z
	r = np.hypot(y, zs)
	inside = ((xs < X(1888)) & (r < 0.1885)) | ((xs > X(2928)) & (r < 0.1055))
	ink(s, ~inside, SATIN, 0.38, 1.0)
	rings(s, ~inside, (X(1900), X(1990), X(2880)), 0.012)
