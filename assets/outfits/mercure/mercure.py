"""MERCURE (#521) : corps de chrome liquide, musculature dessinée sur les blocs du rig R15 (hommage au surfeur d'argent
des comics, sans reprise directe). Cuit par tools/outfits/r15_bake.py.

Variante retenue (17/11/2026) : lisse, le relief seul dessine les muscles par les reflets du chrome. Piste rejetée :
encre (mêmes reliefs et traits sombres sur les contours, façon comics), gardée ici pour d'autres tenues.

Jambes et pieds : chrome sans muscles, bombés en largeur seulement (retour du 17/11/2026 : les muscles
dessinés coupaient net aux genoux).

Coordonnées : espace de la pièce en studs, avant du personnage = -Z, sa gauche = -X (cf. r15_bake.face_coords).
Demi-tailles : UpperTorso 1,59 × 1,27 × 0,79 ; LowerTorso hauteur 0,32 ; membres 0,79 de côté, bras 0,93, avant-bras
0,84, main 0,24, cuisse 0,97, jambe 0,95, pied 0,24.
"""

import numpy as np
from r15_bake import BACK, BOTTOM, FRONT, LEFT, RIGHT, TOP, face_coords, height_of, muscle, outline, pillow, segment

VARIANTS = {"lisse": {"ink": False}}
REJECTED_VARIANTS = {"encre": {"ink": True}}

CHROME = np.array([0.86, 0.88, 0.93])
INK = np.array([0.03, 0.035, 0.06])
RELIEF = 0.085  # hauteur d'une masse musculaire (studs)
GROOVE = 0.05  # profondeur d'un sillon
LINE = 0.045  # demi-largeur d'un trait d'encre (studs)
BULGE = 0.12  # bombé de chaque face (studs)


# Cette méthode permet de réunir plusieurs masses (la plus haute l'emporte) lorsqu'une face en porte plusieurs.
def union(*hs):
	return np.maximum.reduce([np.asarray(h, dtype=np.float64) for h in hs])


# Cette méthode permet de choisir, face par face, le dessin à appliquer lorsqu'une pièce en a plusieurs ; `rules`
# est une liste de (masque de face, (relief, encre)).
def by_face(u, rules):
	h = np.zeros_like(u)
	ink = np.zeros_like(u)
	for mask, (hr, ir) in rules:
		h = np.where(mask, hr, h)
		ink = np.where(mask, ir, ink)
	return h, ink


def upper_torso(face, u, v):
	au = np.abs(u)
	pecs = muscle(au, v, 0.8, 0.52, 0.82, 0.52, 0.9, 0.12)
	abs_ = union(*[muscle(au, v, 0.38, cv, 0.36, 0.27, 0.7, 0.45) for cv in (-0.22, -0.66, -1.08)])
	serr = union(*[muscle(au, v, 1.38, cv, 0.22, 0.1, 0.5, 0.3) for cv in (-0.05, -0.3, -0.55)])
	obl = muscle(au, v, 1.28, -0.95, 0.42, 0.42, 0.6, 0.6)
	front_h = union(pecs, abs_ * 0.75, serr * 0.55, obl * 0.6) * RELIEF - segment(u, v, (0, 1.3), (0, -1.3), 0.07) * GROOVE
	front_i = union(
		outline(au, v, 0.8, 0.52, 0.82, 0.52, LINE, 195, 345),
		*[outline(au, v, 0.38, cv, 0.36, 0.27, LINE * 0.8, 215, 325) for cv in (-0.22, -0.66)],
		segment(u, v, (0, 0.05), (0, -1.25), LINE * 0.8),
		*[segment(au, v, (1.2, cv + 0.03), (1.48, cv - 0.06), LINE * 0.7) for cv in (-0.1, -0.35)],
		outline(au, v, 1.28, -0.95, 0.42, 0.42, LINE * 0.8, 110, 190),
	)
	traps = muscle(u, v, 0, 1.05, 1.25, 0.5, 0.7, 0.4)
	blades = muscle(au, v, 0.72, 0.3, 0.58, 0.48, 0.5, 0.25)
	lats = muscle(au, v, 1.08, -0.5, 0.55, 0.78, 0.5, 0.45)
	back_h = union(traps, blades, lats * 0.9) * RELIEF - segment(u, v, (0, 1.3), (0, -1.3), 0.09) * GROOVE * 1.3
	back_i = union(
		outline(au, v, 0.72, 0.3, 0.58, 0.48, LINE, 160, 330),
		outline(au, v, 1.08, -0.5, 0.55, 0.78, LINE * 0.8, 200, 300),
		segment(u, v, (0, 0.7), (0, -1.25), LINE * 0.7),
	)
	top_h = muscle(au, v, 0.85, 0, 0.75, 0.7, 0.7, 0.7) * RELIEF * 0.7
	side_h = muscle(u, v, 0.1, -0.4, 0.6, 0.75, 0.6, 0.5) * RELIEF * 0.6
	side_i = outline(u, v, 0.1, -0.4, 0.6, 0.75, LINE * 0.8, 210, 330)
	return by_face(u, [
		(face == FRONT, (front_h, front_i)),
		(face == BACK, (back_h, back_i)),
		(face == TOP, (top_h, 0 * u)),
		((face == LEFT) | (face == RIGHT), (side_h, side_i)),
	])


def lower_torso(face, u, v):
	au = np.abs(u)
	front_h = muscle(au, v, 0.33, 0.12, 0.3, 0.2, 0.5, 0.4) * RELIEF * 0.7 - segment(
		au, v, (1.45, 0.32), (0.42, -0.3), 0.07
	) * GROOVE
	front_i = union(segment(au, v, (1.45, 0.3), (0.45, -0.28), LINE), segment(u, v, (0, 0.32), (0, -0.05), LINE * 0.7))
	back_h = muscle(au, v, 0.75, -0.05, 0.78, 0.42, 0.6, 0.6) * RELIEF * 0.6
	back_i = segment(u, v, (0, 0.32), (0, -0.32), LINE)
	return by_face(u, [(face == FRONT, (front_h, front_i)), (face == BACK, (back_h, back_i))])


def upper_arm(face, u, v, out):
	outer = face == (RIGHT if out > 0 else LEFT)
	inner = face == (LEFT if out > 0 else RIGHT)
	delt = muscle(u, v, 0, 0.62, 0.9, 0.45, 0.6, 0.15)
	bic = muscle(u, v, 0, -0.28, 0.55, 0.6, 0.5, 0.35)
	tri = muscle(u, v, 0, -0.1, 0.62, 0.68, 0.4, 0.3)
	front = (union(delt * 0.85, bic) * RELIEF, union(outline(u, v, 0, -0.28, 0.55, 0.6, LINE, 185, 355), outline(u, v, 0, 0.62, 0.9, 0.45, LINE * 0.8, 210, 330)))
	back = (
		union(delt * 0.85, tri) * RELIEF - segment(u, v, (0, -0.55), (0, 0.15), 0.08) * GROOVE,
		union(outline(u, v, 0, -0.1, 0.62, 0.68, LINE, 190, 350), segment(u, v, (0, -0.55), (0, 0.1), LINE * 0.7)),
	)
	side_o = (
		muscle(u, v, 0, 0.42, 0.68, 0.6, 0.5, 0.12) * RELIEF - segment(u, v, (0, -0.2), (0, -0.9), 0.07) * GROOVE,
		union(outline(u, v, 0, 0.42, 0.68, 0.6, LINE, 205, 335), segment(u, v, (0, -0.25), (0, -0.85), LINE * 0.7)),
	)
	side_i = (muscle(u, v, 0, -0.2, 0.55, 0.6, 0.6, 0.6) * RELIEF * 0.5, 0 * u)
	top = (muscle(u, v, 0, 0, 0.85, 0.85, 0.7, 0.7) * RELIEF * 0.8, 0 * u)
	return by_face(u, [(face == FRONT, front), (face == BACK, back), (outer, side_o), (inner, side_i), (face == TOP, top)])


def lower_arm(face, u, v, out):
	outer = face == (RIGHT if out > 0 else LEFT)
	sides = (face == FRONT) | (face == BACK) | (face == LEFT) | (face == RIGHT)
	mass = muscle(u, v, 0, 0.3, 0.64, 0.62, 0.5, 0.6)
	brachio = muscle(u, v, 0, 0.5, 0.52, 0.42, 0.5, 0.3)
	h = np.where(outer, union(mass, brachio), mass) * RELIEF * 0.9 - segment(u, v, (-0.8, -0.72), (0.8, -0.72), 0.06) * GROOVE
	ink = union(outline(u, v, 0, 0.3, 0.64, 0.62, LINE * 0.9, 195, 345), segment(u, v, (-0.8, -0.72), (0.8, -0.72), LINE * 0.7))
	return by_face(u, [(sides, (h, ink))])


def hand(face, u, v, out):
	outer = face == (RIGHT if out > 0 else LEFT)
	inner = face == (LEFT if out > 0 else RIGHT)
	fingers = union(*[segment(u, v, (x, 0.04), (x, -0.3), 0.035) for x in (-0.36, -0.12, 0.12, 0.36)])
	knuckles = union(*[muscle(u, v, x, 0.1, 0.12, 0.08, 0.6, 0.6) for x in (-0.48, -0.24, 0.0, 0.24, 0.48)])
	under = union(*[segment(u, v, (x, -0.8), (x, 0.8), 0.035) for x in (-0.36, -0.12, 0.12, 0.36)])
	thumb = muscle(u, v, 0, -0.02, 0.45, 0.16, 0.6, 0.4)
	return by_face(u, [
		(outer, (knuckles * RELIEF * 0.6 - fingers * GROOVE, fingers)),
		(inner, (-fingers * GROOVE * 0.7, fingers)),
		(face == BOTTOM, (-under * GROOVE, under * 0.8)),
		(face == FRONT, (thumb * RELIEF * 0.6, outline(u, v, 0, -0.02, 0.45, 0.16, LINE * 0.7, 180, 360))),
	])


PAINTERS = {"UpperTorso": lambda f, u, v: upper_torso(f, u, v), "LowerTorso": lambda f, u, v: lower_torso(f, u, v)}
for _side, _out in (("Left", -1), ("Right", 1)):
	PAINTERS[_side + "UpperArm"] = lambda f, u, v, o=_out: upper_arm(f, u, v, o)
	PAINTERS[_side + "LowerArm"] = lambda f, u, v, o=_out: lower_arm(f, u, v, o)
	PAINTERS[_side + "Hand"] = lambda f, u, v, o=_out: hand(f, u, v, o)


# Cette méthode permet de donner la surface de MERCURE en chaque point d'une pièce (relief, couleur, métal,
# rugosité) lorsque r15_bake cuit un atlas.
def surface(part, p, n, variant):
	face, u, v = face_coords(p, n)
	painter = PAINTERS.get(part)
	if painter:
		h, ink = painter(face, u, v)
		h = h + pillow(part, face, u, v) * BULGE
	else:
		h, ink = pillow(part, face, u, v, vertical=False) * BULGE, np.zeros_like(u)
	ink = np.clip(ink, 0, 1) if {**VARIANTS, **REJECTED_VARIANTS}[variant]["ink"] else np.zeros_like(h)
	color = CHROME[None] * (1 - ink[:, None]) + INK[None] * ink[:, None]
	return {"height": h, "color": color, "metal": 0.35 * (1 - ink), "rough": 0.25 + ink * 0.3}


# Reflet figé du chrome : Roblox ne fait refléter au métal que le ciel, si bien qu'un chrome uni paraît mat et pâle.
# La couleur porte donc le reflet d'un décor imaginaire, vu de face : ciel clair, ligne d'horizon nette, sol sombre
# (le motif classique d'une pièce chromée, et des planches de comics). Hauteur de la direction réfléchie -> couleur.
ENV = [
	(-1.0, (0.25, 0.27, 0.33)),
	(-0.3, (0.05, 0.06, 0.09)),
	(-0.04, (0.20, 0.23, 0.31)),
	(0.04, (0.95, 0.96, 1.0)),
	(0.35, (0.68, 0.76, 0.92)),
	(1.0, (0.33, 0.40, 0.58)),
]


# Cette méthode permet de lire la couleur du décor imaginaire dans une direction (sa hauteur y, de -1 à 1) lorsqu'on
# peint le reflet figé du chrome.
def environment(y):
	keys = np.array([k for k, _ in ENV])
	cols = np.array([c for _, c in ENV])
	return np.stack([np.interp(y, keys, cols[:, i]) for i in range(3)], axis=1)


# Cette méthode permet de peindre dans la couleur le reflet figé du chrome lorsque r15_bake connaît la normale en
# relief : regard de face (le long de -n de la face), direction réfléchie R = 2(n·V)n - V.
def shade(part, p, bumped, s, variant):
	view = s["geo_normal"]  # œil en face de la surface (normale du bloc sans relief : continue sur les arêtes)
	nv = np.sum(bumped * view, axis=1, keepdims=True)
	refl = 2 * nv * bumped - view
	up = view[:, 1]
	y = refl[:, 1] * 2.5
	if part not in PAINTERS:
		# jambes : pas de relief en hauteur, une ondulation d'horizon continue d'une pièce à l'autre (#521 : pas de
		# coupure au genou)
		y = y + 0.16 * np.sin((height_of(part, p) + 2.3) * 2.0)
	# dessus et dessous des blocs : ciel ou sol en entier
	y = np.where(np.abs(up) > 0.7, np.sign(up) * (0.6 + 0.4 * np.abs(refl[:, 1])), y)
	return environment(np.clip(y, -1, 1))
