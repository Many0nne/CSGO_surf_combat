"""NÉOPRÈNE (#521, commune) : le corps devient une combinaison de surf. Cuit par tools/outfits/r15_bake.py.

Matière : néoprène doublé de jersey, mat, au grain fin et régulier (maille), sans métal. Panneaux qui suivent les
blocs du rig (flancs, empiècement des épaules, bandes extérieures des jambes), coutures en relief bordées de points
réguliers, fermeture éclair dans le dos, genouillères à quadrillage. La musculature de MERCURE s'y devine, adoucie
(la combinaison la moule). Coque de tête : cagoule intégrale, sans visage, en quatre panneaux.

Variantes (deux couleurs au plus) : noir (corps noir, panneaux bleu canard), nuit (bleu nuit, panneaux noirs), vive
(orange vif uni, panneaux marqués par les seules coutures).

Coordonnées : celles de r15_bake (studs, avant = -Z, gauche = -X) ; demi-tailles dans mercure.py.
"""

import numpy as np
from r15_bake import BACK, FRONT, LEFT, RIGHT, TOP, face_coords, lin, lit_relief, mercure, pillow, smoothstep

MERCURE = mercure()

VARIANTS = {
	# noir : anthracite plutôt que noir pur, sinon le relief disparaît sous la lumière du jeu
	"noir": {"base": lin(0.15, 0.155, 0.165), "accent": lin(0.0, 0.58, 0.64)},
	"nuit": {"base": lin(0.11, 0.17, 0.38), "accent": lin(0.07, 0.075, 0.09)},
	"vive": {"base": lin(0.95, 0.36, 0.07), "accent": lin(0.95, 0.36, 0.07)},
}

HEAD = True  # coque de tête : cagoule (mesh de la coque de MERCURE)
ANATOMY = 0.45  # part du relief musculaire de MERCURE (la combinaison moule le corps sans le sculpter)
BULGE = 0.08  # bombé de chaque face (studs)
SEAM = 0.028  # demi-largeur d'une couture (studs)
RIDGE = 0.012  # hauteur d'une couture
STITCH_OFF = 0.055  # distance des points de couture au milieu de la couture
STITCH_STEP = 0.07  # pas des points
GRAIN_STEP = 0.06  # pas de la maille du jersey
GRAIN = 0.0016  # profondeur de la maille
FAR = 9.0  # bord de panneau hors de la face (pas de couture sur l'arête du bloc)
# Relief peint (vu en jeu le 18/11/2026 : côté ombre, l'anthracite tombait au noir et les muscles disparaissaient) :
# part du relief ombrée dans la couleur, faible pour ne pas trop marquer la maille
PAINTED_RELIEF = 0.6


# Cette méthode permet de peindre dans la couleur une part du relief ombré lorsque r15_bake connaît la normale en
# relief : muscles et coutures restent lisibles sur le néoprène sombre.
def shade(part, p, bumped, s, variant):
	return lit_relief(np.asarray(s["color"]), bumped, s["geo_normal"], PAINTED_RELIEF, 0.7, 1.3)


# Cette méthode permet de donner la distance signée au bord d'un rectangle de face (négative dedans) lorsqu'une
# tenue découpe un panneau.
def rect(u, v, u0, u1, v0, v1):
	return np.maximum(np.maximum(u0 - u, u - u1), np.maximum(v0 - v, v - v1))


# Cette méthode permet de donner, pour un point d'une face, la distance signée au panneau de couleur (négative dans le
# panneau) et la distance à une couture supplémentaire, lorsqu'on découpe la combinaison pièce par pièce.
def panels(part, face, u, v):
	none = np.full_like(u, FAR)
	sd = none.copy()
	extra = none.copy()
	front_back = (face == FRONT) | (face == BACK)
	sides = (face == LEFT) | (face == RIGHT)
	if part == "UpperTorso":
		# flancs (sur les côtés et le bord de l'avant/arrière) et empiècement des épaules
		flank = rect(np.abs(u), v, 1.22, FAR, -FAR, FAR)
		yoke = rect(u, v, -FAR, FAR, 0.6, FAR)
		sd = np.where(front_back, np.minimum(flank, yoke), sd)
		sd = np.where(sides | (face == TOP), -1.0, sd)
	elif part == "LowerTorso":
		sd = np.where(front_back, rect(np.abs(u), v, 1.22, FAR, -FAR, FAR), sd)
		sd = np.where(sides, -1.0, sd)
		# couture de la ceinture
		extra = np.where(front_back | sides, np.abs(v - 0.12), extra)
	elif "UpperArm" in part:
		# l'empiècement couvre le haut du bras (continuité avec les épaules)
		sd = np.where(face == TOP, -1.0, rect(u, v, -FAR, FAR, 0.32, FAR))
	elif "LowerArm" in part:
		# poignet : couture du revers
		extra = np.where(face != TOP, np.abs(v + 0.62), extra)
	elif "UpperLeg" in part or "LowerLeg" in part:
		outer = face == (LEFT if part.startswith("Left") else RIGHT)
		# face extérieure dans la couleur des panneaux, prolongement des flancs (couture sur l'arête du bloc)
		sd = np.where(outer, -1.0, none)
		# genouillère : rectangle à quadrillage sur l'avant, à cheval sur le genou (sa couture)
		extra = np.where(face == FRONT, np.abs(knee_rect(part, u, v)), extra)
	elif "Foot" in part:
		# chausson : couture de la cheville (cachée en jeu : le haut du pied est sous la jambe, cf. docs/assets.md)
		extra = np.where(face != TOP, np.abs(v - 0.12), extra)
	return sd, extra


# Genouillère sur l'avant de la cuisse (bas) et de la jambe (haut) : (u0, u1, v0, v1) dans la face
KNEE_PADS = {"UpperLeg": (-0.56, 0.56, -FAR, -0.62), "LowerLeg": (-0.56, 0.56, 0.05, 0.8)}


# Cette méthode permet de donner la distance signée au bord de la genouillère d'une pièce de jambe (négative dedans)
# lorsqu'on trace sa couture ou son quadrillage ; FAR hors des jambes.
def knee_rect(part, u, v):
	key = part.removeprefix("Left").removeprefix("Right")
	if key not in KNEE_PADS:
		return np.full_like(u, FAR)
	return rect(u, v, *KNEE_PADS[key])


# Cette méthode permet de dire si un point est sur une genouillère (pièce et face) lorsqu'on lui donne son quadrillage.
def knee_pad(part, face, u, v):
	return (face == FRONT) & (knee_rect(part, u, v) < 0)


# Cette méthode permet de donner le relief et l'intensité d'une couture (arête en relief, points réguliers de part et
# d'autre) lorsqu'on trace une couture, à partir de la distance à son milieu et d'une coordonnée qui la longe.
def seam(dist, along):
	ridge = 1 - smoothstep(0, SEAM, dist)
	dots = (1 - smoothstep(0.008, 0.018, np.abs(dist - STITCH_OFF))) * (0.5 + 0.5 * np.cos(2 * np.pi * along / STITCH_STEP))
	return ridge, smoothstep(0.55, 0.9, dots)


# Cette méthode permet de donner la maille régulière du jersey (relief de -1 à 1) en un point d'une face lorsqu'on
# donne son grain au néoprène.
def grain(u, v):
	k = 2 * np.pi / GRAIN_STEP
	return np.sin(u * k) * np.sin(v * k)


# Cette méthode permet de mélanger deux couleurs selon un masque (0 : a, 1 : b) lorsqu'on colorie les panneaux.
def mix(a, b, m):
	return a[None] * (1 - m[:, None]) + b[None] * m[:, None]


# Cette méthode permet de donner la surface de NÉOPRÈNE en chaque point d'une pièce (relief, couleur, métal,
# rugosité) lorsque r15_bake cuit un atlas.
def surface(part, p, n, variant):
	spec = VARIANTS[variant]
	if part == "Head":
		return head(p, n, spec)
	face, u, v = face_coords(p, n)
	painter = MERCURE.PAINTERS.get(part)
	anatomy = painter(face, u, v)[0] * ANATOMY if painter else np.zeros_like(u)
	vertical = "Leg" not in part and "Foot" not in part
	h = anatomy + pillow(part, face, u, v, vertical=vertical) * BULGE
	sd, extra = panels(part, face, u, v)
	accent = 1 - smoothstep(-0.006, 0.006, sd)
	r1, s1 = seam(np.abs(sd), u + v)
	r2, s2 = seam(extra, u + v)
	ridge, stitch = np.maximum(r1, r2), np.maximum(s1, s2)
	pad = knee_pad(part, face, u, v)
	# genouillère : caoutchouc en relief, quadrillage de losanges réguliers
	diamonds = np.abs(np.sin((u + v) * np.pi / 0.11)) * np.abs(np.sin((u - v) * np.pi / 0.11))
	if part == "UpperTorso":
		# fermeture éclair dans le dos : ruban et dents alternées
		zip_tape = (face == BACK) & (np.abs(u) < 0.07) & (v > -1.0)
		teeth = zip_tape & (np.abs(u) < 0.035) & (np.cos(2 * np.pi * v / 0.06) > 0)
	else:
		zip_tape = teeth = np.zeros_like(u, dtype=bool)
	h = h + ridge * RIDGE - stitch * 0.004 + grain(u, v) * GRAIN * (1 - ridge)
	h = h + np.where(pad, 0.018 + diamonds * 0.008, 0.0) + np.where(teeth, 0.006, 0.0) - np.where(zip_tape, 0.004, 0.0)
	color = mix(spec["base"], spec["accent"], accent)
	tone = 1 + 0.05 * grain(u, v) + 0.12 * ridge + 0.55 * stitch - np.where(pad, 0.25 - diamonds * 0.12, 0.0)
	tone = tone * np.where(zip_tape, 0.55, 1.0) + np.where(teeth, 0.25, 0.0)
	color = color * tone[:, None] + np.where(teeth, 0.05, 0.0)[:, None]
	rough = 0.78 - 0.12 * ridge + np.where(pad, 0.1, 0.0) - np.where(teeth, 0.35, 0.0)
	metal = np.where(teeth, 0.6, 0.0)
	return {"height": h, "color": np.clip(color, 0, 1), "metal": metal, "rough": np.clip(rough, 0, 1)}


# Cette méthode permet de donner la surface de la cagoule lorsque r15_bake cuit la coque : quatre panneaux (coutures
# x = 0 et z = 0, justes même si la coque tourne d'un quart de tour), couture du cou, dessus dans la couleur des panneaux.
def head(p, n, spec):
	x, y, z = p[:, 0], p[:, 1], p[:, 2]
	cross = np.minimum(np.abs(x), np.abs(z))
	ring = np.abs(y + 0.72)
	along = np.arctan2(x, z) * 0.95 + y
	r1, s1 = seam(np.where(y > -0.72, cross, 9.0), along + x + z)
	r2, s2 = seam(ring, np.arctan2(x, z) * 0.95)
	ridge, stitch = np.maximum(r1, r2), np.maximum(s1, s2)
	top = smoothstep(0.62, 0.66, y)
	g = np.sin(x * 2 * np.pi / GRAIN_STEP) * np.sin(y * 2 * np.pi / GRAIN_STEP) * np.sin(z * 2 * np.pi / GRAIN_STEP)
	h = ridge * RIDGE - stitch * 0.004 + g * GRAIN
	color = mix(spec["base"], spec["accent"], top)
	tone = (1 + 0.05 * g + 0.12 * ridge + 0.55 * stitch) * (0.82 + 0.18 * smoothstep(-1.0, 0.2, y))
	return {"height": h, "color": np.clip(color * tone[:, None], 0, 1), "metal": np.zeros_like(x), "rough": 0.78 - 0.12 * ridge}
