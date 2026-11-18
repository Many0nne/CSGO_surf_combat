"""PAN ! (#566) : image de l'effet de tir PAN !, l'explosion de BD peinte sur l'arrière de crosse du skin PAN ! de l'AWP
(assets/awp/skins/pan.py) reprise à l'identique : même contour à pointes (fonction `burst`, mêmes graines), mêmes
couches (contour noir, rouge, cœur jaune, onomatopée blanche cerclée de noir), mêmes couleurs, fond transparent.

    uv run --with pillow --with numpy assets/effects/pan_burst.py assets/effects/pan_burst.png

Publier ensuite en Decal (docs/assets.md, « Publier un asset ») et reporter l'id de l'image dans
ShotEffectRules.PAN_IMAGE.
"""

import math
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

RED = (0.88, 0.10, 0.10)
YELLOW = (0.98, 0.80, 0.10)
BLACK = (0.025, 0.025, 0.03)
WHITE = (0.95, 0.95, 0.93)

SS = 4  # suréchantillonnage, réduit à la fin (bords lissés)
SCALE = 1.2  # px de l'image par px photo du skin
SIZE = (512, 320)  # image finale


def burst(center, rx, ry, spikes=13, seed=3):
	"""Cette méthode permet d'obtenir le contour d'une explosion de BD : pointes irrégulières autour d'une ellipse
	(copie de pan.py, mêmes tirages)."""
	rng = np.random.default_rng(seed)
	pts = []
	for i in range(spikes * 2):
		a = i / (spikes * 2) * 2 * math.pi
		k = (1.0 if i % 2 == 0 else 0.62) * (0.88 + 0.24 * rng.random())
		pts.append((center[0] + rx * k * math.cos(a), center[1] + ry * k * math.sin(a)))
	return pts


def rgba(col):
	"""Cette méthode permet de convertir une couleur 0..1 de pan.py en RGBA opaque 8 bits."""
	return tuple(int(round(c * 255)) for c in col) + (255,)


def text_layer(size, s, center, height, angle, stroke):
	"""Cette méthode permet de tamponner un texte Impact centré, tourné de `angle` degrés, épaissi de `stroke` px, en
	masque (comme Canvas.text de common.py, flanc gauche)."""
	f = ImageFont.truetype("C:/Windows/Fonts/impact.ttf", int(height * 1.38))
	bb = f.getbbox(s, anchor="ls", stroke_width=stroke)
	tw, th = bb[2] - bb[0] + 8, bb[3] - bb[1] + 8
	stamp = Image.new("L", (tw, th), 0)
	ImageDraw.Draw(stamp).text((4 - bb[0], 4 - bb[1]), s, font=f, fill=255, anchor="ls", stroke_width=stroke, stroke_fill=255)
	stamp = stamp.rotate(angle, resample=Image.BICUBIC, expand=True)
	mask = Image.new("L", size, 0)
	mask.paste(255, (int(center[0] - stamp.width / 2), int(center[1] - stamp.height / 2)), stamp)
	return mask


def main(out):
	"""Cette méthode permet de peindre l'explosion couche par couche, dans l'ordre de pan.py, et d'écrire le PNG."""
	w, h = SIZE[0] * SS, SIZE[1] * SS
	k = SCALE * SS
	c = (w / 2, h / 2)

	def scaled(pts):
		return [(c[0] + x * k, c[1] + y * k) for x, y in pts]

	img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	draw = ImageDraw.Draw(img)
	draw.polygon(scaled(burst((0, 0), 205, 128)), fill=rgba(BLACK))
	draw.polygon(scaled(burst((0, 0), 190, 116)), fill=rgba(RED))
	draw.polygon(scaled(burst((0, 0), 128, 78, spikes=11, seed=7)), fill=rgba(YELLOW))
	# texte décalé de (4, 2) px photo comme sur la crosse
	at = (c[0] + 4 * k, c[1] + 2 * k)
	img.paste(Image.new("RGBA", (w, h), rgba(BLACK)), (0, 0), text_layer((w, h), "PAN !", at, 76 * k, 8, int(8 * k)))
	img.paste(Image.new("RGBA", (w, h), rgba(WHITE)), (0, 0), text_layer((w, h), "PAN !", at, 76 * k, 8, 0))
	img.resize(SIZE, Image.LANCZOS).save(out)


if __name__ == "__main__":
	main(sys.argv[1] if len(sys.argv) > 1 else "pan_burst.png")
