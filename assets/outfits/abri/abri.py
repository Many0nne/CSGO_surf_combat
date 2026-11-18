"""ABRI (#521, exceptionnel) : combinaison de protection chimique, d'après la planche de concept validée
(assets/outfits/concepts/abri.png). Cuit par tools/outfits/r15_bake.py : caoutchouc moutarde semi-brillant à plis
souples, rabat de fermeture sur la poitrine, ceinture cousue à la taille, tours de ruban gris aux poignets et aux
chevilles, gants et bottes noirs, sangles noires du sac sur le dos et les épaules. Les volumes (cagoule, masque, filtres,
visière, sac du dos) sont des MeshParts à part (abri_meshes.py).

Coordonnées : espace de la pièce en studs, avant du personnage = -Z, sa droite = +X (cf. r15_bake.face_coords).
Les membres sont dessinés selon la hauteur au-dessus de la racine (`height_of`).
"""

import numpy as np
from r15_bake import BACK, FRONT, LEFT, RIGHT, TOP, face_coords, height_of, pillow, smoothstep

VARIANTS = {"base": {}}


# Couleurs relevées sur la planche (sRGB 0-255), converties en linéaire : r15_bake applique le gamma à l'écriture
def srgb(r, g, b):
	return (np.array([r, g, b]) / 255) ** 2.2


YELLOW = srgb(224, 168, 20)
YELLOW_FOLD = srgb(150, 104, 10)
BLACK = srgb(32, 32, 31)
BLACK_SEAM = srgb(16, 16, 15)
TAPE = srgb(178, 178, 174)
TAPE_EDGE = srgb(110, 110, 108)

BULGE = 0.05  # bombé des faces
FOLD = 0.03  # profondeur d'un pli
TAPE_H = 0.035  # épaisseur du ruban

# Hauteurs (au-dessus de la racine) relevées sur la planche (76,5 px par stud)
ARM_TAPE = (-0.71, -0.23)
LEG_TAPE = (-3.79, -3.32)
BELT = (-1.21, -0.81)


def mix(a, b, t):
	return a * (1 - t[:, None]) + b * t[:, None]


# Cette méthode permet de tracer une ligne horizontale (1 sur la ligne, 0 à `width` studs) lorsqu'une zone porte une
# couture à hauteur fixe.
def line(h, at, width):
	return 1 - smoothstep(0, width, np.abs(h - at))


# Hauteurs des articulations où le caoutchouc se plisse (épaule, coude, hanche, genou)
JOINTS = (1.15, 0.48, -1.55, -2.9)


# Cette méthode permet de donner les plis souples du caoutchouc lorsqu'une zone est en combinaison : un pli large et
# ondulé à chaque articulation, qui s'efface sur une partie de la largeur (pas de motif régulier) ; `seed` décale le
# dessin d'une pièce et d'une face à l'autre.
def folds(u, h, seed):
	crease = np.zeros_like(u)
	for k, at in enumerate(JOINTS):
		wave = at + 0.08 * np.sin(u * 2.6 + seed + k)
		fade = np.clip(0.35 + 0.65 * np.sin(u * 1.9 + seed * 2.1 + k * 1.3), 0, 1)
		crease = np.maximum(crease, line(h, wave, 0.09) * fade)
	return crease


# Cette méthode permet de donner le léger gonflement du caoutchouc (grandes bosses molles, sans arête) lorsqu'une zone
# est en combinaison.
def slack(u, h, seed):
	return 0.5 + 0.5 * np.sin(u * 1.3 + seed) * np.sin(h * 0.9 + seed * 0.7)


# Cette méthode permet de donner le ruban adhésif (relief, tracé des tours croisés) lorsqu'une bande de ruban scelle un
# gant ou une botte : deux ou trois tours qui se croisent en X sur chaque face.
def tape(u, h, lo, hi):
	inside = (h > lo) & (h < hi)
	mid, half = (lo + hi) / 2, (hi - lo) / 2
	t = (h - mid) / half
	cross = np.minimum(np.abs(t - u * 0.55), np.abs(t + u * 0.55))
	cross = np.minimum(cross, np.abs(t - u * 0.55 + 0.9))
	edges = 1 - smoothstep(0.0, 0.05, np.minimum(np.abs(cross), 1 - np.abs(t)))
	return inside.astype(float), edges * inside


# Cette méthode permet de donner la surface de l'ABRI en chaque point d'une pièce (relief, couleur, métal, rugosité)
# lorsque r15_bake cuit un atlas.
def surface(part, p, n, variant):
	face, u, v = face_coords(p, n)
	h = height_of(part, p)
	sides = (face == FRONT) | (face == BACK) | (face == LEFT) | (face == RIGHT)
	seed = sum(map(ord, part)) * 0.37 + face * 1.3

	black = np.zeros_like(u)  # 1 : caoutchouc noir (gant, botte, sangle)
	taped = np.zeros_like(u)  # 1 : ruban gris
	edge = np.zeros_like(u)  # 1 : bord ou croisement d'un tour de ruban
	seam = np.zeros_like(u)  # 1 : couture soudée (trait sombre)
	raised = np.zeros_like(u)  # relief ajouté (rabat, ceinture, sangle)
	crease = np.where(sides, folds(u, h, seed), 0.0)

	if part == "UpperTorso":
		front = face == FRONT
		# rabat de fermeture : bande verticale légèrement en relief, couture de chaque côté
		flap = front & (np.abs(u) < 0.16)
		raised = np.where(flap, 0.025, raised)
		seam = np.where(front, np.maximum(seam, line(np.abs(u), 0.16, 0.02)), seam)
		crease = np.where(flap, crease * 0.3, crease)
		# dos : deux sangles noires verticales et une sangle de taille ; dessus : leur passage sur les épaules
		au = np.abs(u)
		strap_v = (np.abs(au - 1.1) < 0.09) & (((face == BACK) & (h > -0.85)) | (face == TOP))
		strap_h = (face == BACK) & (np.abs(h - (-0.72)) < 0.08)
		side_strap = ((face == LEFT) | (face == RIGHT)) & (np.abs(h - (-0.72)) < 0.08)
		strap = strap_v | strap_h | side_strap
		black = np.where(strap, 1.0, black)
		raised = np.where(strap, 0.03, raised)
		crease = np.where(strap, 0.0, crease)
	if part in ("UpperTorso", "LowerTorso"):
		lo, hi = BELT
		belt = sides & (h > lo) & (h < hi)
		raised = np.where(belt & (black < 0.5), np.maximum(raised, 0.02), raised)
		seam = np.where(sides, np.maximum(seam, line(h, lo, 0.02) + line(h, hi, 0.02)), seam)
		crease = np.where(belt, crease * 0.4, crease)
		if part == "LowerTorso":
			# rabat de fermeture prolongé sous la ceinture, jusqu'à l'entrejambe
			flap = (face == FRONT) & (np.abs(u) < 0.16)
			raised = np.where(flap, np.maximum(raised, 0.025), raised)
			seam = np.where(face == FRONT, np.maximum(seam, line(np.abs(u), 0.16, 0.02)), seam)
	elif "Arm" in part or "Hand" in part:
		lo, hi = ARM_TAPE
		inside, cross = tape(u, h, lo, hi)
		taped = np.where(sides, inside, 0.0)
		edge = np.where(sides, cross, 0.0)
		black = np.where((h < lo) | ("Hand" in part), 1.0, black)
		crease = np.where((h < hi), 0.0, crease)
	elif "Leg" in part or "Foot" in part:
		lo, hi = LEG_TAPE
		inside, cross = tape(u, h, lo, hi)
		taped = np.where(sides, inside, 0.0)
		edge = np.where(sides, cross, 0.0)
		boot = (h < lo) | ("Foot" in part)
		black = np.where(boot, 1.0, black)
		crease = np.where(h < hi, 0.0, crease)
		seam = np.where(boot, line(h, -4.62, 0.03), seam)
		# bout de la botte légèrement rehaussé sur l'avant
		raised = np.where((face == FRONT) & boot & (h < -4.45), 0.02, raised)

	crease = np.clip(crease, 0, 1)
	height = (
		pillow(part, face, u, v, vertical=False) * BULGE
		+ raised
		+ taped * TAPE_H
		- crease * FOLD
		+ np.where(sides & (black < 0.5) & (taped < 0.5), slack(u, h, seed), 0.0) * 0.025
		- seam * 0.012
		- edge * 0.01
	)
	base = mix(YELLOW, BLACK, black)
	base = mix(base, mix(YELLOW_FOLD, BLACK_SEAM, black), crease * 0.12 + seam * 0.7)
	tape_col = mix(TAPE, TAPE_EDGE, edge)
	color = mix(base, tape_col, taped)
	rough = np.where(taped > 0.5, 0.7, np.where(black > 0.5, 0.55, 0.42)) + crease * 0.1
	return {"height": height, "color": np.clip(color, 0, 1), "metal": np.zeros_like(u), "rough": rough}
