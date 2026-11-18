"""DÉMINEUR (#521, légendaire) : combinaison de déminage, d'après la planche de concept validée
(assets/outfits/concepts/demineur.png). Cuit par tools/outfits/r15_bake.py : tissu matelassé olive, plaques
d'avant-bras et de genoux noires bordées de sable, gants, bottes, ceinture et sangles du dos. Les volumes (casque,
col, épaulières, plastron, tablier) sont des MeshParts à part (demineur_meshes.py).

Coordonnées : espace de la pièce en studs, avant du personnage = -Z, sa droite = +X (cf. r15_bake.face_coords).
Les membres sont dessinés selon la hauteur au-dessus de la racine (`height_of`) : bras et avant-bras se chevauchent
au coude, cuisse et jambe au genou ; à hauteur égale, les deux pièces portent le même dessin.
"""

import numpy as np
from r15_bake import BACK, FRONT, LEFT, RIGHT, TOP, face_coords, height_of, pillow, smoothstep

VARIANTS = {"base": {}}

# Couleurs relevées sur la planche (sRGB 0-255), converties en linéaire : r15_bake applique le gamma à l'écriture
def srgb(r, g, b):
	return (np.array([r, g, b]) / 255) ** 2.2


OLIVE = srgb(84, 92, 52)
OLIVE_SEAM = srgb(56, 62, 34)
BLACK = srgb(34, 34, 32)
BLACK_SEAM = srgb(20, 20, 19)
SAND = srgb(184, 156, 96)

QUILT = 0.3  # pas du matelassage (studs)
PUFF = 0.035  # bombé d'un boudin du matelassage
PLATE = 0.045  # relief d'une plaque
BULGE = 0.05  # bombé des faces
BORDER = 0.035  # demi-largeur du liseré sable

# Hauteurs (au-dessus de la racine) des zones des membres, relevées sur la planche
FOREARM_PLATE = (-0.94, -0.12)
GLOVE_TOP = -0.69
KNEE_PLATE = (-3.62, -2.80)
BOOT_TOP = -3.85


# Cette méthode permet de donner le relief et l'intensité des coutures du matelassage horizontal lorsqu'une zone est en
# tissu : boudins de QUILT studs, coutures fines entre eux.
def quilt(h):
	q = np.mod(h, QUILT) / QUILT
	seam = 1 - smoothstep(0.0, 0.09, np.minimum(q, 1 - q))
	return PUFF * np.sqrt(np.sin(np.pi * q).clip(0, 1)), seam


# Cette méthode permet de donner l'intérieur (1) et le liseré (1 sur le trait) d'un rectangle arrondi lorsqu'on dessine
# une plaque bordée ; (cu, cv) centre, (hu, hv) demi-tailles, r rayon des coins.
def rounded_rect(u, v, cu, cv, hu, hv, r):
	du = np.maximum(np.abs(u - cu) - (hu - r), 0)
	dv = np.maximum(np.abs(v - cv) - (hv - r), 0)
	d = np.hypot(du, dv) - r
	inside = 1 - smoothstep(-0.01, 0.01, d)
	ring = 1 - smoothstep(0, BORDER, np.abs(d + BORDER * 1.6))
	return inside, ring


# Cette méthode permet de donner un grain de tissu très fin (variation de teinte de quelques %) lorsqu'une zone est en
# toile, pour qu'elle ne paraisse pas en plastique.
def grain(p):
	return 1 + 0.035 * np.sin(p[:, 0] * 97 + p[:, 1] * 13) * np.sin(p[:, 1] * 89 - p[:, 2] * 71)


# Cette méthode permet de tracer une couture horizontale (1 sur la ligne, 0 à `width` studs) lorsqu'une zone porte
# une couture à hauteur fixe (poignet, semelle).
def line(h, at, width):
	return 1 - smoothstep(0, width, np.abs(h - at))


def mix(a, b, t):
	return a * (1 - t[:, None]) + b * t[:, None]


# Cette méthode permet de donner la surface du DÉMINEUR en chaque point d'une pièce (relief, couleur, métal, rugosité)
# lorsque r15_bake cuit un atlas.
def surface(part, p, n, variant):
	face, u, v = face_coords(p, n)
	h = height_of(part, p)
	sides = (face == FRONT) | (face == BACK) | (face == LEFT) | (face == RIGHT)
	puff, seam = quilt(h)
	puff = np.where(sides, puff, 0.0)
	seam = np.where(sides, seam, 0.0)

	black = np.zeros_like(u)  # 1 : toile ou plaque noire
	plate = np.zeros_like(u)  # 1 : plaque rigide (pas de matelassage)
	trim = np.zeros_like(u)  # 1 : liseré sable

	if part == "UpperTorso":
		# dos : deux sangles noires du haut au milieu du dos, boucles sable ; dessus : leur passage sur les épaules
		au = np.abs(u)
		strap = (np.abs(au - 0.62) < 0.13) & (((face == BACK) & (v > -0.55)) | (face == TOP))
		black = np.where(strap, 1.0, black)
		buckle = (face == BACK) & strap
		_, ring = rounded_rect(au, v, 0.62, 0.05, 0.2, 0.13, 0.03)
		trim = np.where(buckle, np.maximum(trim, ring * (np.abs(v - 0.05) < 0.2)), trim)
		plate = np.where(strap, 0.5, plate)
	elif part == "LowerTorso":
		black = np.ones_like(u)  # ceinture noire tout autour
	elif "Arm" in part or "Hand" in part:
		lo, hi = FOREARM_PLATE
		band = (h > lo) & (h < hi) & sides
		black = np.where(band | (h < GLOVE_TOP) | ("Hand" in part), 1.0, black)
		plate = np.where(band, 1.0, plate)
		outer = face == (RIGHT if part.startswith("Right") else LEFT)
		inside, ring = rounded_rect(u, h, 0, (lo + hi) / 2, 0.66, (hi - lo) / 2 - 0.06, 0.12)
		trim = np.where(outer & band, ring, trim)
		plate = np.where(outer & band, plate + inside * 0.4, plate)
		# gant : pas de matelassage, une couture au poignet
		glove = h < GLOVE_TOP
		puff = np.where(glove | band, 0.0, puff)
		seam = np.where(glove, line(h, GLOVE_TOP - 0.06, 0.025), seam)
		seam = np.where(band, 0.0, seam)
	elif "Leg" in part or "Foot" in part:
		boot = (h < BOOT_TOP) | ("Foot" in part)
		lo, hi = KNEE_PLATE
		inside, ring = rounded_rect(u, h, 0, (lo + hi) / 2, 0.64, (hi - lo) / 2, 0.14)
		knee = (face == FRONT) & (inside > 0.5) & ~boot
		black = np.where(boot | knee, 1.0, black)
		plate = np.where(knee, 1.0, plate)
		trim = np.where((face == FRONT) & ~boot, ring, trim)
		puff = np.where(boot | knee, 0.0, puff)
		# bottes : semelle marquée par une couture, rien d'autre
		seam = np.where(boot, line(h, -4.62, 0.03), np.where(knee, 0.0, seam))

	height = puff + plate * PLATE + trim * 0.012 + pillow(part, face, u, v, vertical=False) * BULGE
	height = height - seam * 0.012
	base = mix(OLIVE, BLACK, black)
	seam_col = mix(OLIVE_SEAM, BLACK_SEAM, black)
	color = mix(base, seam_col, seam * 0.8) * grain(p)[:, None]
	color = mix(color, SAND, np.clip(trim, 0, 1))
	rough = 0.88 - plate.clip(0, 1) * 0.25 - trim * 0.2
	return {"height": height, "color": np.clip(color, 0, 1), "metal": np.zeros_like(u), "rough": rough}
