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


def _sdf(mask, clip):
	"""Cette méthode permet d'obtenir la distance signée au bord d'un masque (positive dedans), bornée à ±clip px."""
	d = ndimage.distance_transform_edt(mask) - ndimage.distance_transform_edt(~mask)
	return np.clip(d, -clip, clip)


def refine(rgb, target, down=4, sigma=4.0, iters=400):
	"""Cette méthode permet de déformer en douceur une illustration déjà recalée pour que son contour épouse celui du
	masque, lorsque le modèle d'image a redessiné la silhouette (trou décalé, pointe plus fine) : recalage « demons »
	sur les distances signées des deux silhouettes, à basse résolution, déplacement lissé ; renvoie l'image déformée."""
	h, w = target.shape
	small = (w // down, h // down)
	fix_m = np.asarray(Image.fromarray(target.astype(np.uint8) * 255).resize(small, Image.BILINEAR)) > 127
	mov_m = np.asarray(Image.fromarray(art_mask(rgb * 255).astype(np.uint8) * 255).resize(small, Image.BILINEAR)) > 127
	fix, mov = _sdf(fix_m, 12.0), _sdf(mov_m, 12.0)
	gy, gx = np.gradient(fix)
	yy, xx = np.mgrid[0 : small[1], 0 : small[0]].astype(np.float64)
	uy, ux = np.zeros_like(fix), np.zeros_like(fix)
	for _ in range(iters):
		m = ndimage.map_coordinates(mov, [yy + uy, xx + ux], order=1, mode="nearest")
		diff = fix - m
		den = gx * gx + gy * gy + diff * diff + 1e-6
		ux = ndimage.gaussian_filter(ux + diff * gx / den, sigma)
		uy = ndimage.gaussian_filter(uy + diff * gy / den, sigma)
	big_y = ndimage.zoom(uy, (h / small[1], w / small[0]), order=1)[:h, :w] * down
	big_x = ndimage.zoom(ux, (h / small[1], w / small[0]), order=1)[:h, :w] * down
	Y, X = np.mgrid[0:h, 0:w].astype(np.float64)
	coords = [Y + big_y, X + big_x]
	return np.stack([ndimage.map_coordinates(rgb[..., c], coords, order=1, mode="nearest", cval=1.0) for c in range(3)], -1)


def overlap(rgb, target):
	"""Cette méthode permet de mesurer le recouvrement (IoU) de la silhouette d'une image recalée et du masque."""
	a = art_mask(rgb * 255)
	return (a & target).sum() / (a | target).sum()


def load(path, target, deform=False):
	"""Cette méthode permet de charger une illustration, de la recaler sur le masque target (H x W, vrai dans l'arme),
	de la déformer en douceur si deform (silhouette redessinée par le modèle) et de prolonger ses couleurs ; renvoie
	l'image (H x W x 3, 0 à 1) et le recouvrement obtenu."""
	img = Image.open(path).convert("RGB")
	params, score = fit(img, target)
	rgb = np.asarray(warp(img, params, target.shape[::-1]), np.float64) / 255
	if deform:
		rgb = refine(rgb, target)
		score = overlap(rgb, target)
	return extend(rgb), score
