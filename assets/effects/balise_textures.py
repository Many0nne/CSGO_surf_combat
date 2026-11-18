"""BALISE (#567) : textures de l'effet de tir BALISE, d'après la planche de concept retenue le 18/11/2026 (ruban de
chantier orange et noir qui se déroule du canon à la cible, boucle au canon, chevrons qui s'ouvrent à l'impact). Couleurs
de la livrée du skin BALISE (assets/awp/skins/balise.py : orange signal, noir, blanc céramique), posées dans l'image : le
Beam et les particules les gardent telles quelles (Color blanc, LightEmission 0).

- balise_tape.png : un tronçon de ruban, répété le long du rayon (Beam.Texture, TextureMode Wrap). Chevrons orange sur
  fond noir, liseré blanc des deux côtés. Dessiné debout : un Beam pose la hauteur de l'image le long du rayon.
- balise_ring.png : la boucle du canon, anneau zébré orange et noir cerné de blanc (ParticleEmitter, tourne sur lui-même).
- balise_mark.png : la marque d'impact, trois chevrons pointés vers le centre (vide : la cible reste visible).

    uv run --with pillow --with numpy assets/effects/balise_textures.py assets/effects

Publier ensuite chaque PNG en Decal (docs/assets.md, « Publier un asset ») et reporter les ids d'image dans
ShotEffectRules (BALISE_TAPE_IMAGE, BALISE_RING_IMAGE, BALISE_MARK_IMAGE).
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

SS = 4  # suréchantillonnage (bords lissés)
ORANGE = (242, 79, 10)
BLACK = (12, 12, 13)
WHITE = (236, 233, 226)


def tape(w=64, h=256):
	"""Cette méthode permet de dessiner un tronçon de ruban debout : fond noir, deux chevrons orange pointés vers le haut
	de l'image (le sens du défilement, vérifié en jeu), liseré blanc sur les deux bords."""
	W, H = w * SS, h * SS
	img = Image.new("RGBA", (W, H), BLACK + (255,))
	d = ImageDraw.Draw(img)
	border = int(W * 0.11)
	inner = (border, W - border)
	thick = H * 0.16  # épaisseur d'un chevron le long du ruban
	rise = (inner[1] - inner[0]) * 0.55  # hauteur de la pointe au-dessus des bras
	for k in range(2):
		y = H * (0.5 * k + 0.12)
		for dy in (0, H):  # recopie au bord pour un raccord sans couture
			yy = y + dy - H if dy else y
			left, right, mid = inner[0], inner[1], W / 2
			d.polygon(
				[
					(left, yy + rise),
					(mid, yy),
					(right, yy + rise),
					(right, yy + rise + thick),
					(mid, yy + thick),
					(left, yy + rise + thick),
				],
				fill=ORANGE + (255,),
			)
	d.rectangle([0, 0, border * 0.7, H], fill=WHITE + (255,))
	d.rectangle([W - border * 0.7, 0, W, H], fill=WHITE + (255,))
	return img.resize((w, h), Image.LANCZOS)


def ring(size=256):
	"""Cette méthode permet de dessiner la boucle du canon : anneau de 12 secteurs alternés orange et noir, cerné de blanc
	à l'extérieur et à l'intérieur, centre vide."""
	S = size * SS
	c = (np.arange(S) + 0.5) / S * 2 - 1
	xx, yy = np.meshgrid(c, c)
	r = np.hypot(xx, yy)
	a = (np.arctan2(yy, xx) + math.pi) / (2 * math.pi)
	outer, inner, edge = 0.96, 0.62, 0.06
	band = (r <= outer) & (r >= inner)
	white = band & ((r > outer - edge) | (r < inner + edge))
	stripe = (np.floor(a * 12 + (r - inner) * 2.5) % 2) == 0  # zébrures en biais
	rgb = np.zeros((S, S, 3), np.uint8)
	rgb[:] = BLACK
	rgb[stripe] = ORANGE
	rgb[white] = WHITE
	alpha = (band * 255).astype(np.uint8)
	return Image.fromarray(np.dstack([rgb, alpha]), "RGBA").resize((size, size), Image.LANCZOS)


def mark(size=256):
	"""Cette méthode permet de dessiner la marque d'impact : trois chevrons orange cernés de noir, à 120° les uns des
	autres, pointe vers le centre de l'image, qui reste vide (un tiers du rayon)."""
	S = size * SS
	img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
	d = ImageDraw.Draw(img)
	cx = cy = S / 2
	for k in range(3):
		ang = math.radians(90 + 120 * k)
		ux, uy = math.cos(ang), -math.sin(ang)  # du centre vers l'extérieur
		px, py = -uy, ux  # perpendiculaire

		def pt(along, side):
			return (cx + ux * along * S / 2 + px * side * S / 2, cy + uy * along * S / 2 + py * side * S / 2)

		shape = [pt(0.36, 0), pt(0.66, 0.36), pt(0.94, 0.36), pt(0.64, 0), pt(0.94, -0.36), pt(0.66, -0.36)]
		# cerne noir d'épaisseur égale tout autour du chevron orange
		d.polygon(shape, fill=ORANGE + (255,), outline=BLACK + (255,), width=int(S * 0.022))
	return img.resize((size, size), Image.LANCZOS)


def main(out_dir):
	"""Cette méthode permet d'écrire les trois textures dans le dossier donné."""
	tape().save(os.path.join(out_dir, "balise_tape.png"))
	ring().save(os.path.join(out_dir, "balise_ring.png"))
	mark().save(os.path.join(out_dir, "balise_mark.png"))


if __name__ == "__main__":
	main(sys.argv[1] if len(sys.argv) > 1 else ".")
