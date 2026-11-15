"""Transpose les cartes d'un matériau d'un ancien dépliage UV vers le nouveau (#335), triangle par triangle.

Pour chaque texel du nouveau dépliage : triangle qui le contient, coordonnées barycentriques, point correspondant dans
l'ancien dépliage, échantillonnage de l'ancienne carte (spline cubique). La carte de normales (espace tangent) est en
plus tournée de la rotation de son triangle : le repère tangent suit le dépliage, sans quoi le relief d'un îlot tourné
s'éclaire de travers. Les texels hors îlots reçoivent la valeur de l'îlot le plus proche (pas de couture aux mipmaps).

Entrée : la correspondance écrite par repack_uv.py (<objet>_old, <objet>_new).
Usage (depuis la racine du worktree) :
  uv run --with numpy --with pillow --with scipy tools/skins/remap_textures.py <correspondance.npz> <dossier source> \
    <dossier sortie> WOOD [--check <rapport.png>]
  lit <dossier source>/WOOD_{Color,Rough,Metal,Normal}.png, écrit les mêmes noms dans <dossier sortie>.
"""

import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

MAPS = ("Color", "Rough", "Metal", "Normal")


# Cette méthode permet de rastériser les triangles du nouveau dépliage : renvoie pour chaque texel couvert l'indice du
# triangle et ses coordonnées barycentriques (texels dont le centre est dans le triangle, bords compris).
def rasterize(tris, res):
	tri_of = np.full((res, res), -1, np.int64)
	bary = np.zeros((res, res, 3), np.float64)
	for i, t in enumerate(tris):
		# Coordonnées pixel (x vers la droite, y vers le bas), centre du texel en +0,5
		p = np.stack([t[:, 0] * res, (1 - t[:, 1]) * res], 1)
		x0, y0 = np.floor(p.min(0) - 0.5).astype(int)
		x1, y1 = np.ceil(p.max(0) + 0.5).astype(int)
		x0, y0 = max(x0, 0), max(y0, 0)
		x1, y1 = min(x1, res - 1), min(y1, res - 1)
		if x1 < x0 or y1 < y0:
			continue
		ys, xs = np.mgrid[y0 : y1 + 1, x0 : x1 + 1]
		cx, cy = xs + 0.5, ys + 0.5
		(ax, ay), (bx, by), (qx, qy) = p
		den = (by - qy) * (ax - qx) + (qx - bx) * (ay - qy)
		if abs(den) < 1e-12:
			continue
		l0 = ((by - qy) * (cx - qx) + (qx - bx) * (cy - qy)) / den
		l1 = ((qy - ay) * (cx - qx) + (ax - qx) * (cy - qy)) / den
		l2 = 1 - l0 - l1
		inside = (l0 >= -1e-9) & (l1 >= -1e-9) & (l2 >= -1e-9)
		yy, xx = ys[inside], xs[inside]
		tri_of[yy, xx] = i
		bary[yy, xx] = np.stack([l0[inside], l1[inside], l2[inside]], 1)
	return tri_of, bary


# Cette méthode permet de calculer, pour chaque triangle, la rotation qui fait passer de l'ancien repère tangent au
# nouveau (partie orthogonale de la jacobienne nouveau -> ancien) ; renvoie (N, 2, 2) à appliquer en M^T.
def tangent_rotations(old, new):
	e_new = np.stack([new[:, 1] - new[:, 0], new[:, 2] - new[:, 0]], 2)  # colonnes : arêtes, (N, 2, 2)
	e_old = np.stack([old[:, 1] - old[:, 0], old[:, 2] - old[:, 0]], 2)
	jac = e_old @ np.linalg.inv(e_new)  # d(uv_old) / d(uv_new)
	s = np.sqrt(np.abs(np.linalg.det(jac)))[:, None, None]
	return jac / s


# Cette méthode permet d'échantillonner une image (H, W, C) en des positions UV (spline cubique, bords prolongés).
def sample(img, uv):
	res_y, res_x = img.shape[:2]
	x = uv[:, 0] * res_x - 0.5
	y = (1 - uv[:, 1]) * res_y - 0.5
	return np.stack([ndimage.map_coordinates(img[..., c], [y, x], order=3, mode="nearest") for c in range(img.shape[2])], 1)


# Cette méthode permet de prolonger les valeurs des îlots sur les texels vides, par le texel couvert le plus proche.
def dilate(img, cov):
	_, (iy, ix) = ndimage.distance_transform_edt(~cov, return_indices=True)
	return img[iy, ix]


if __name__ == "__main__":
	args = sys.argv[1:]
	check = args[args.index("--check") + 1] if "--check" in args else None
	npz, src, dst, prefix = args[:4]
	d = np.load(npz)
	names = sorted({k.rsplit("_", 1)[0] for k in d.files})
	old = np.concatenate([d[n + "_old"] for n in names]).astype(np.float64)
	new = np.concatenate([d[n + "_new"] for n in names]).astype(np.float64)
	res = Image.open(os.path.join(src, f"{prefix}_Color.png")).size[0]
	tri_of, bary = rasterize(new, res)
	cov = tri_of >= 0
	ti = tri_of[cov]
	b = bary[cov]
	uv_old = (old[ti] * b[:, :, None]).sum(1)
	rot = tangent_rotations(old, new)[ti]
	print(f"[remap] {len(names)} objets, {len(new)} triangles, couverture {cov.mean():.3f}")
	os.makedirs(dst, exist_ok=True)
	for kind in MAPS:
		path = os.path.join(src, f"{prefix}_{kind}.png")
		im = Image.open(path)
		mode = im.mode
		img = np.asarray(im.convert("RGB"), dtype=np.float64) / 255
		val = sample(img, uv_old)
		if kind == "Normal":
			n = val * 2 - 1
			xy = np.einsum("nji,nj->ni", rot, n[:, :2])  # M^T @ (x, y)
			n = np.concatenate([xy, n[:, 2:3]], 1)
			n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-9
			val = n * 0.5 + 0.5
		out = np.zeros((res, res, 3))
		out[cov] = np.clip(val, 0, 1)
		out = dilate(out, cov)
		Image.fromarray(np.rint(out * 255).astype(np.uint8)).convert(mode).save(os.path.join(dst, f"{prefix}_{kind}.png"))
		print(f"[remap] {prefix}_{kind}.png")
	if check:
		# Contrôle : nouvelle couleur reprojetée dans l'ancien dépliage, à comparer à l'ancienne carte
		tri_old, bary_old = rasterize(old, res)
		cov_old = tri_old >= 0
		uv_new = (new[tri_old[cov_old]] * bary_old[cov_old][:, :, None]).sum(1)
		before = np.asarray(Image.open(os.path.join(src, f"{prefix}_Color.png")).convert("RGB"), dtype=np.float64) / 255
		after = np.asarray(Image.open(os.path.join(dst, f"{prefix}_Color.png")).convert("RGB"), dtype=np.float64) / 255
		back = np.zeros_like(before)
		back[cov_old] = sample(after, uv_new)
		err = np.abs(back - before)[cov_old].mean(1) * 255
		print(f"[remap] aller-retour Color : écart moyen {err.mean():.2f}/255, 99e centile {np.percentile(err, 99):.2f}/255")
		Image.fromarray(np.rint(np.clip(back, 0, 1) * 255).astype(np.uint8)).save(check)
