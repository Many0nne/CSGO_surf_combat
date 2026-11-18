"""CIRCUIT (#567) : texture de l'étincelle du tir de l'effet CIRCUIT, d'après la planche de concept retenue le
18/11/2026. Magenta du skin CIRCUIT (assets/awp/skins/circuit.py), cœur presque blanc, halo flou ; posée en sprite
lumineux (ParticleEmitter, LightEmission 1). Les composants en cube sont des Parts néon (CircuitCube) et le réseau de
pistes de l'impact des Beams (CircuitTrace) : des pastilles plates dessinées ici ont été rejetées (« une sorte de
composant 3D en cube, pas juste en 2D »).

- circuit_flash.png : étincelle du tir, cœur blanc et huit rayons fins (quatre longs, quatre courts).

    uv run --with pillow assets/effects/circuit_textures.py assets/effects

Publier ensuite chaque PNG en Decal (docs/assets.md, « Publier un asset ») et reporter les ids d'image dans
ShotEffectRules (CIRCUIT_FLASH_IMAGE).
"""

import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

SS = 4
NEON = (250, 26, 158)
CORE = (255, 225, 245)


def glow(img, radius, strength=2):
	"""Cette méthode permet d'ajouter un halo flou de la même couleur sous le dessin lorsqu'une texture est finie."""
	halo = img.filter(ImageFilter.GaussianBlur(radius))
	out = halo
	for _ in range(strength - 1):
		out = Image.alpha_composite(out, halo)
	return Image.alpha_composite(out, img)


def flash(size=256):
	"""Cette méthode permet de dessiner l'étincelle du tir : huit rayons effilés autour d'un cœur blanc."""
	S = size * SS
	img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
	d = ImageDraw.Draw(img)
	c = S / 2
	for k in range(8):
		a = math.radians(45 * k)
		length = S * (0.48 if k % 2 == 0 else 0.26)
		half = S * 0.025
		ux, uy = math.cos(a), math.sin(a)
		px, py = -uy, ux
		d.polygon(
			[
				(c + px * half, c + py * half),
				(c + ux * length, c + uy * length),
				(c - px * half, c - py * half),
				(c - ux * half * 2, c - uy * half * 2),
			],
			fill=NEON + (255,),
		)
	r = S * 0.1
	d.ellipse([c - r, c - r, c + r, c + r], fill=NEON + (255,))
	r = S * 0.06
	d.ellipse([c - r, c - r, c + r, c + r], fill=CORE + (255,))
	return glow(img, S * 0.03, 3).resize((size, size), Image.LANCZOS)


def main(out_dir):
	"""Cette méthode permet d'écrire la texture dans le dossier donné."""
	flash().save(os.path.join(out_dir, "circuit_flash.png"))


if __name__ == "__main__":
	main(sys.argv[1] if len(sys.argv) > 1 else ".")
