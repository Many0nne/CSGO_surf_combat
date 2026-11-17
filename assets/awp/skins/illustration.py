"""Illustration d'un skin de l'AWP peinte hors du projet (modèle d'image) sur le gabarit de `gabarit.py` (#492).

Le modèle ne respecte la silhouette qu'à quelques pixels près et rend son image à sa propre taille : `load` la recale
sur le gabarit (échelle et décalage par axe qui maximisent le recouvrement des silhouettes), prolonge ses couleurs
au-delà de son bord pour qu'aucun blanc ne reste sous le châssis, et la lit ensuite en coordonnées de la photo de profil.
"""

import os

import numpy as np
from PIL import Image
from scipy import ndimage

from common import mt_px, mt_py
from gabarit import mapping, silhouette

W, H = 2520, 1080  # taille du gabarit de référence


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


def load(path):
	"""Cette méthode permet de charger une illustration, de la recaler sur le gabarit et de prolonger ses couleurs
	hors de son bord ; renvoie l'image (H x W x 3, 0 à 1) et le recouvrement obtenu."""
	img = Image.open(path).convert("RGB")
	target = np.asarray(silhouette(W, H)) < 128
	params, score = fit(img, target)
	rgb = np.asarray(warp(img, params, (W, H)), np.float64) / 255
	_, idx = ndimage.distance_transform_edt(~art_mask(rgb * 255), return_indices=True)
	return rgb[idx[0], idx[1]], score


def sample(rgb, m):
	"""Cette méthode permet de lire l'illustration recalée sur les texels d'un matériau, par leur position de profil
	(le flanc droit la reçoit en miroir, comme les autres toiles)."""
	scale, ox, oy = mapping(W, H)
	u = mt_px(m.p[:, 0]) * scale + ox
	v = mt_py(m.p[:, 2]) * scale + oy
	return np.stack([ndimage.map_coordinates(rgb[..., c], [v, u], order=1, mode="nearest") for c in range(3)], axis=1)


def source(name):
	"""Cette méthode permet d'obtenir le chemin de l'illustration source d'un skin (`art/<skin>.png`)."""
	return os.path.join(os.path.dirname(os.path.abspath(__file__)), "art", f"{name}.png")
