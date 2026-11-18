"""PLÂTRE (#521, commune) : le corps devient une statue de plâtre d'atelier. Cuit par tools/outfits/r15_bake.py.

Matière : plâtre blanc cassé, très mat, sans métal. Même anatomie que MERCURE (ses reliefs, repris de mercure.py),
avec les creux un peu plus sombres (la lumière du jeu n'y fait pas d'occlusion : on la peint, de façon ordonnée, d'après
le relief). Coque de tête lisse, sans visage. Pas de fissures ni de taches tirées au hasard (rejetées sur les skins).

Variantes :
- lisse : plâtre seul ;
- atelier : traits de sanguine d'une étude d'atelier, ordonnés (axe du corps, lignes de construction des masses,
  repères de proportion aux articulations, croix de construction de la tête) ;
- mannequin : mannequin articulé, muscles adoucis, rainures aux articulations et rotules en demi-cercles qui se
  rejoignent d'une pièce à l'autre.

Coordonnées : celles de r15_bake (studs, avant = -Z, gauche = -X) ; demi-tailles dans mercure.py.
"""

import numpy as np
from r15_bake import (
	BACK,
	BOTTOM,
	FRONT,
	LEFT,
	PARTS,
	RIGHT,
	TOP,
	face_coords,
	lin,
	lit_relief,
	mercure,
	outline,
	pillow,
	segment,
	smoothstep,
)

MERCURE = mercure()

VARIANTS = {
	"lisse": {"lines": False, "joints": False, "anatomy": 1.0},
	"atelier": {"lines": True, "joints": False, "anatomy": 1.0},
	"mannequin": {"lines": False, "joints": True, "anatomy": 0.55},
}

HEAD = True  # coque de tête lisse (mesh de la coque de MERCURE)
# blanc cassé plus bas que le vrai plâtre : à 0,87, la lumière chaude et le bloom de l'accueil le saturaient au blanc
PLASTER = lin(0.76, 0.74, 0.69)
SANGUINE = lin(0.62, 0.27, 0.2)
BULGE = 0.1  # bombé de chaque face (studs)
RELIEF = MERCURE.RELIEF
CAVITY = 0.24  # assombrissement des creux entre les masses
LINE = 0.016  # demi-largeur d'un trait de sanguine (studs)
JOINT = 0.05  # demi-largeur d'une rainure d'articulation
JOINT_DEPTH = 0.045
JOINT_SHADE = 0.55  # assombrissement au fond d'une rainure
# Relief peint (vu en jeu le 18/11/2026 : sous la lumière douce du couchant, la normal map seule laissait un aplat gris
# clair) : part du relief ombrée dans la couleur, lumière venue d'en haut
PAINTED_RELIEF = 1.3


# Cette méthode permet de peindre dans la couleur une part du relief ombré lorsque r15_bake connaît la normale en
# relief : le plâtre mat se lit alors comme une sculpture, même sous une lumière douce.
def shade(part, p, bumped, s, variant):
	return lit_relief(np.asarray(s["color"]), bumped, s["geo_normal"], PAINTED_RELIEF, 0.55, 1.25)


# Cette méthode permet de donner les traits de construction d'une étude d'atelier sur une pièce (0 à 1) lorsque la
# variante atelier les dessine : axe médian, contours des masses de MERCURE en trait fin, repères de proportion.
def study_lines(part, face, u, v):
	au = np.abs(u)
	front_back = (face == FRONT) | (face == BACK)
	zero = np.zeros_like(u)
	if part == "UpperTorso":
		axis = segment(u, v, (0, 1.27), (0, -1.27), LINE)
		chest = segment(u, v, (-1.58, 0.52), (1.58, 0.52), LINE * 0.8)  # ligne des pectoraux
		ribs = segment(u, v, (-1.58, -0.66), (1.58, -0.66), LINE * 0.8)
		contours = np.maximum.reduce([
			outline(au, v, 0.8, 0.52, 0.82, 0.52, LINE, 195, 345),
			outline(au, v, 1.28, -0.95, 0.42, 0.42, LINE, 110, 190),
		])
		back = np.maximum.reduce([
			outline(au, v, 0.72, 0.3, 0.58, 0.48, LINE, 160, 330),
			segment(u, v, (-1.58, 0.3), (1.58, 0.3), LINE * 0.8),
		])
		lines = np.where(face == FRONT, np.maximum.reduce([axis, chest, ribs, contours]), zero)
		lines = np.where(face == BACK, np.maximum(axis, back), lines)
		return np.where((face == LEFT) | (face == RIGHT), segment(u, v, (0, 1.27), (0, -1.27), LINE), lines)
	if part == "LowerTorso":
		axis = segment(u, v, (0, 0.32), (0, -0.32), LINE)
		hip = segment(au, v, (1.45, 0.3), (0.45, -0.28), LINE)
		return np.where(face == FRONT, np.maximum(axis, hip), np.where(face == BACK, axis, zero))
	if part == "LeftHand" or part == "RightHand" or "Foot" in part:
		return zero
	sides = front_back | (face == LEFT) | (face == RIGHT)
	half = PARTS[part][1][1] / 2
	axis = segment(u, v, (0, half), (0, -half), LINE * 0.9)
	# repères de proportion : petits traits horizontaux au quart, au milieu et aux trois quarts du membre
	ticks = np.maximum.reduce([segment(u, v, (-0.2, t * half), (0.2, t * half), LINE * 0.8) for t in (-0.5, 0.0, 0.5)])
	# ellipse d'articulation au bas de la pièce (coude, poignet, genou, cheville) : construction des volumes
	joint = outline(u, v, 0, -half, 0.62, 0.2, LINE * 0.9, 0, 180)
	return np.where(sides, np.maximum.reduce([axis, ticks, joint]), zero)


# Cette méthode permet de donner les rainures du mannequin articulé (0 à 1) lorsque la variante mannequin les marque :
# anneaux aux bouts des membres, rotules en demi-cercles d'une pièce à l'autre, taille entre buste et bassin.
def joints(part, face, u, v):
	zero = np.zeros_like(u)
	if part == "UpperTorso":
		return np.where((face != TOP) & (face != BOTTOM), segment(u, v, (-9, -1.12), (9, -1.12), JOINT), zero)
	if part == "LowerTorso" or "Hand" in part:
		return zero
	half = PARTS[part][1][1] / 2
	sides = (face == FRONT) | (face == BACK) | (face == LEFT) | (face == RIGHT)
	rings = np.zeros_like(u)
	ends = []
	if "Upper" in part:
		ends = [-1]  # coude ou genou
	elif "Lower" in part:
		ends = [1, -1]  # coude ou genou en haut, poignet ou cheville en bas
	elif "Foot" in part:
		ends = [1]
	for e in ends:
		rings = np.maximum(rings, segment(u, v, (-9, e * (half - 0.09)), (9, e * (half - 0.09)), JOINT))
	# rotule : demi-cercle sur les faces de côté, à cheval sur l'articulation
	ball = zero
	if "Upper" in part or "Lower" in part:
		e = -1 if "Upper" in part else 1
		ball = outline(u, v, 0, e * half, 0.42, 0.42, JOINT)
	if "UpperArm" in part:
		# épaule : disque sur la face extérieure
		ball = np.maximum(ball, outline(u, v, 0, half - 0.48, 0.38, 0.38, JOINT))
	knee_sides = (face == LEFT) | (face == RIGHT)
	return np.where(sides, np.maximum(rings, np.where(knee_sides, ball, zero)), zero)


# Cette méthode permet de donner la surface de PLÂTRE en chaque point d'une pièce (relief, couleur, métal, rugosité)
# lorsque r15_bake cuit un atlas.
def surface(part, p, n, variant):
	spec = VARIANTS[variant]
	if part == "Head":
		return head(p, n, spec)
	face, u, v = face_coords(p, n)
	painter = MERCURE.PAINTERS.get(part)
	anatomy = painter(face, u, v)[0] * spec["anatomy"] if painter else np.zeros_like(u)
	vertical = "Leg" not in part and "Foot" not in part
	h = anatomy + pillow(part, face, u, v, vertical=vertical) * BULGE
	# creux entre les masses : là où le relief musculaire est bas (ou en sillon), le plâtre est un peu plus sombre
	mass = np.clip(anatomy / (RELIEF * spec["anatomy"]), -1, 1) if painter else np.ones_like(u) * 0.6
	tone = 1 - CAVITY * (1 - smoothstep(-0.4, 0.55, mass))
	# pied de statue : bas des jambes un peu plus sombre (lumière d'atelier venue d'en haut)
	if "Foot" in part:
		tone = tone * 0.93
	ink = np.zeros_like(u)
	if spec["lines"]:
		ink = np.clip(study_lines(part, face, u, v), 0, 1) * 0.85
	if spec["joints"]:
		groove = np.clip(joints(part, face, u, v), 0, 1)
		h = h - groove * JOINT_DEPTH
		tone = tone * (1 - JOINT_SHADE * groove)
	color = PLASTER[None] * tone[:, None]
	color = color * (1 - ink[:, None]) + SANGUINE[None] * ink[:, None]
	return {"height": h, "color": np.clip(color, 0, 1), "metal": np.zeros_like(u), "rough": 0.93 - 0.05 * ink}


# Cette méthode permet de donner la surface de la coque de tête lorsque r15_bake la cuit : plâtre lisse, dessous plus
# sombre ; atelier : croix de construction (plan x = 0, mi-hauteur) ; mannequin : rainure du cou.
def head(p, n, spec):
	x, y, z = p[:, 0], p[:, 1], p[:, 2]
	tone = 0.84 + 0.16 * smoothstep(-1.0, 0.3, y)
	h = np.zeros_like(x)
	ink = np.zeros_like(x)
	if spec["lines"]:
		ink = np.maximum(1 - smoothstep(0, LINE, np.abs(x)), 1 - smoothstep(0, LINE, np.abs(y + 0.05))) * 0.85
		ink = np.where(y < -0.8, 0.0, ink)
	if spec["joints"]:
		groove = 1 - smoothstep(0, JOINT, np.abs(y + 0.8))
		h = h - groove * JOINT_DEPTH
		tone = tone * (1 - JOINT_SHADE * groove)
	color = PLASTER[None] * tone[:, None]
	color = color * (1 - ink[:, None]) + SANGUINE[None] * ink[:, None]
	return {"height": h, "color": np.clip(color, 0, 1), "metal": np.zeros_like(x), "rough": 0.93 - 0.05 * ink}
