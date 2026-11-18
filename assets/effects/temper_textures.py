"""TREMPE (#566) : textures de l'effet de tir TREMPE, d'après la planche de concept validée (2e instant : ruban d'acier
torsadé qui refroidit par bandes, écailles d'oxyde qui s'en détachent). En niveaux de gris : la couleur vient du Beam
(dégradé paille → bronze → pourpre → bleu, ShotEffectRules.TEMPER_STOPS) et des particules.

- temper_ribbon.png : une demi-torsion du ruban vue de côté, à répéter le long du rayon (Beam.Texture, TextureMode
  Wrap). Silhouette en losange (le ruban de face s'élargit, de chant il s'amincit), deux facettes d'éclairage séparées
  par une diagonale, comme le ruban low-poly de la planche.
- temper_flake.png : une écaille d'oxyde en losange irrégulier à deux facettes (ParticleEmitter.Texture).

    uv run --with pillow --with numpy assets/effects/temper_textures.py assets/effects

Publier ensuite chaque PNG en Decal (docs/assets.md, « Publier un asset ») et reporter les ids d'image dans
ShotEffectRules (TEMPER_RIBBON_IMAGE, TEMPER_FLAKE_IMAGE).
"""

import os
import sys

import numpy as np
from PIL import Image

SS = 4  # suréchantillonnage (bords lissés)


def ribbon(w=512, h=64):
	"""Cette méthode permet de dessiner une torsion complète du ruban (deux demi-torsions) : losanges pleins en x (nœuds
	aux bords et au milieu, ruban de chant), coupés en deux facettes par une diagonale, la facette claire passant du haut
	au bas d'un losange à l'autre (le ruban montre l'autre face) ; épaisseur minimale au nœud."""
	W, H = w * SS, h * SS
	x = (np.arange(W) + 0.5) / W * 2  # deux losanges sur la largeur
	v = (np.arange(H) + 0.5) / H
	xx, vv = np.meshgrid(x, v)
	lobe = np.floor(xx)
	fx = xx - lobe  # position dans le losange
	half = 0.06 + 0.44 * (1 - np.abs(2 * fx - 1))  # demi-largeur : 0,06 au nœud, 0,5 au milieu
	inside = np.abs(vv - 0.5) <= half
	# diagonale d'une facette à l'autre, retournée d'un losange au suivant
	slope = np.where(lobe == 0, 0.9, -0.9)
	upper = (vv - 0.5) < (0.5 - fx) * slope
	shade = np.where(upper, 1.0, 0.72)
	# léger reflet sur l'arête vive
	edge = np.abs((vv - 0.5) - (0.5 - fx) * slope) < 0.02
	shade = np.where(edge & inside, 1.0, shade)
	rgb = (shade * 255).astype(np.uint8)
	alpha = (inside * 255).astype(np.uint8)
	img = Image.fromarray(np.dstack([rgb, rgb, rgb, alpha]), "RGBA")
	# Un Beam pose la HAUTEUR de l'image le long du rayon et sa LARGEUR en travers (vérifié en jeu) : dessinée à plat
	# (torsions en x), la texture donnait deux rangées de losanges côte à côte, soit deux traits. Tournée d'un quart de tour.
	return img.resize((w, h), Image.LANCZOS).transpose(Image.ROTATE_90)


def flake(size=64):
	"""Cette méthode permet de dessiner une écaille : losange irrégulier (pointes inégales), deux facettes d'éclairage."""
	S = size * SS
	c = (np.arange(S) + 0.5) / S * 2 - 1
	xx, yy = np.meshgrid(c, c)
	# losange étiré : |x|/a + |y|/b <= 1, pointe droite plus longue
	a = np.where(xx > 0, 0.95, 0.6)
	b = np.where(yy > 0, 0.55, 0.45)
	inside = np.abs(xx) / a + np.abs(yy) / b <= 1
	shade = np.where(yy < xx * 0.3, 1.0, 0.7)
	rgb = (shade * 255).astype(np.uint8)
	alpha = (inside * 255).astype(np.uint8)
	img = Image.fromarray(np.dstack([rgb, rgb, rgb, alpha]), "RGBA")
	return img.resize((size, size), Image.LANCZOS)


def main(out_dir):
	"""Cette méthode permet d'écrire les deux textures dans le dossier donné."""
	ribbon().save(os.path.join(out_dir, "temper_ribbon.png"))
	flake().save(os.path.join(out_dir, "temper_flake.png"))


if __name__ == "__main__":
	main(sys.argv[1] if len(sys.argv) > 1 else ".")
