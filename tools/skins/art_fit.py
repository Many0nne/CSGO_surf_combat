"""Recalage d'une illustration peinte hors du projet (modèle d'image) sur le masque d'un gabarit (#492, #505).

Le modèle ne respecte la silhouette qu'à quelques pixels près et rend son image à sa propre taille : `fit` trouve
l'échelle et le décalage par axe qui superposent au mieux sa silhouette au masque, `warp` applique ce recalage et
`extend` prolonge ses couleurs au-delà de son bord, pour qu'aucun blanc ne reste sous l'arme. Partagé par les skins
illustrés de l'AWP (`assets/awp/skins/illustration.py`) et de la M9 (`assets/m9/skins/illustration.py`).
"""

import numpy as np
from PIL import Image
from scipy import ndimage


def art_mask(rgb):
	"""Cette méthode permet de séparer le dessin du fond blanc laissé autour de la silhouette."""
	return rgb.min(axis=2) < 225


def warp(img, params, size):
	"""Cette méthode permet de recaler une image (échelle sx, sy puis décalage tx, ty, image -> gabarit)."""
	sx, sy, tx, ty = params
	return img.transform(size, Image.AFFINE, (1 / sx, 0, -tx / sx, 0, 1 / sy, -ty / sy), Image.BICUBIC, fillcolor=(255, 255, 255))


def fit(img, target, steps=(8.0, 4.0, 2.0, 1.0, 0.5)):
	"""Cette méthode permet de trouver l'échelle et le décalage qui superposent au mieux la silhouette de l'image au
	masque du gabarit : départ par les boîtes englobantes, puis descente coordonnée sur le recouvrement (IoU)."""
	art = art_mask(np.asarray(img.convert("RGB"), np.float64))
	ys, xs = np.nonzero(art)
	ty_, tx_ = np.nonzero(target)
	sx = (tx_.max() - tx_.min()) / (xs.max() - xs.min())
	sy = (ty_.max() - ty_.min()) / (ys.max() - ys.min())
	p = [sx, sy, tx_.min() - xs.min() * sx, ty_.min() - ys.min() * sy]
	alpha = Image.fromarray((art * 255).astype(np.uint8))

	def iou(q):
		"""Cette méthode permet de mesurer le recouvrement de la silhouette recalée et du masque."""
		sx_, sy_, tx, ty = q
		a = np.asarray(alpha.transform(target.shape[::-1], Image.AFFINE, (1 / sx_, 0, -tx / sx_, 0, 1 / sy_, -ty / sy_))) > 127
		return (a & target).sum() / (a | target).sum()

	best = iou(p)
	for step in steps:
		improved = True
		while improved:
			improved = False
			for i, d in ((0, step / 2000), (1, step / 1000), (2, step), (3, step)):
				for sign in (1, -1):
					q = list(p)
					q[i] += sign * d
					score = iou(q)
					if score > best:
						best, p, improved = score, q, True
	return p, best


def extend(rgb):
	"""Cette méthode permet de prolonger les couleurs du dessin (H x W x 3, 0 à 1) sur le fond blanc qui l'entoure."""
	_, idx = ndimage.distance_transform_edt(~art_mask(rgb * 255), return_indices=True)
	return rgb[idx[0], idx[1]]


def load(path, target):
	"""Cette méthode permet de charger une illustration, de la recaler sur le masque target (H x W, vrai dans l'arme)
	et de prolonger ses couleurs ; renvoie l'image (H x W x 3, 0 à 1) et le recouvrement obtenu."""
	img = Image.open(path).convert("RGB")
	params, score = fit(img, target)
	rgb = np.asarray(warp(img, params, target.shape[::-1]), np.float64) / 255
	return extend(rgb), score
