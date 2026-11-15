# /// script
# dependencies = ["numpy", "pillow", "scipy"]
# ///
"""Cartes PBR d'origine de l'AWP (Color, Rough, Metal, Normal en PNG, 1024), peintes à partir des cartes cuites (#403).

`uv run assets/awp/make_textures.py <cuisson> <sortie>` où <cuisson> vient de
`blender -b assets/awp/AWP.blend --factory-startup --python tools/skins/bake_maps.py -- <cuisson>`.
Tout est calculé sur la position 3D de chaque texel (continu d'un îlot à l'autre) : polymère vert olive granité, métaux
noirs revêtus, usure claire sur les arêtes, crasse dans les creux, culasse en acier nu, moletage de la lunette.
Valeurs des PNG en sRGB direct (docs/assets.md) : métal à 0 ou 1, rugosité 0,3 à 0,5 pour le métal nu.
Normales : tangent-space OpenGL (Y vers le haut de la texture), relief en unités monde converti par la densité de texels.
"""

import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

PX_S = 0.002865  # repère de build_awp.py


def X(px):
	"""Cette méthode permet de convertir une abscisse de la photo de profil en X du modèle (build_awp.py)."""
	return 1.42 + (px - 2940) * PX_S


def Z(py):
	"""Cette méthode permet de convertir une ordonnée de la photo de profil en Z du modèle (build_awp.py)."""
	return (355 - py) * PX_S


SCOPE_Z = 0.504
OLIVE = np.array([0.25, 0.265, 0.18])  # vert olive tirant sur le kaki (AWP Default de CS2, éclairage retiré à l'œil)
SCOPE_OLIVE = np.array([0.26, 0.245, 0.185])  # lunette peinte, un peu plus chaude que le châssis (CS2)


def hash3(ix, iy, iz, seed):
	"""Cette méthode permet de tirer une valeur pseudo-aléatoire dans [0, 1] par point entier du réseau 3D."""
	h = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def vnoise(p, seed):
	"""Cette méthode permet d'évaluer un bruit de valeur 3D lissé (dans [0, 1]) aux points p (N, 3)."""
	i = np.floor(p).astype(np.int64)
	f = p - i
	f = f * f * (3 - 2 * f)
	out = 0.0
	for dx in (0, 1):
		for dy in (0, 1):
			for dz in (0, 1):
				w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
				out = out + w * hash3(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
	return out


def fbm(p, cell, seed, octaves=4):
	"""Cette méthode permet d'évaluer un bruit fractal 3D centré (dans [-1, 1]) de taille de motif cell (unités monde)."""
	out, amp, tot = 0.0, 1.0, 0.0
	for o in range(octaves):
		out = out + amp * vnoise(p / (cell / 2**o), seed + o)
		tot += amp
		amp *= 0.5
	return (out / tot) * 2 - 1


class Maps:
	"""Cette classe permet de tenir les texels couverts d'un matériau (position, normale, occlusion, arête, objet) et ses cartes."""

	def __init__(self, bake_dir, mat):
		d = np.load(os.path.join(bake_dir, f"{mat}_PBR.npz"))
		bb = json.load(open(os.path.join(bake_dir, "bbox.json")))
		self.res = d["pos"].shape[0]
		self.cov = d["aux"][..., 2] > 0.5
		lo, hi = np.array(bb["min"]), np.array(bb["max"])
		self.p = d["pos"][self.cov].astype(np.float64) * (hi - lo) + lo
		self.n = d["nrm"][self.cov].astype(np.float64) * 2 - 1
		self.ao = d["aux"][..., 0][self.cov].astype(np.float64)
		self.edge = d["aux"][..., 1][self.cov].astype(np.float64)
		names = list(d["objects"])
		oid = d["oid"][self.cov]
		self.obj = np.array([names[i - 1] if 0 < i <= len(names) else "" for i in oid])
		k = len(self.p)
		self.color = np.zeros((k, 3))
		self.rough = np.zeros(k)
		self.metal = np.zeros(k)
		self.height = np.zeros(k)

	def is_(self, name):
		"""Cette méthode permet de sélectionner les texels d'une pièce."""
		return self.obj == name

	def fill(self, sel, rgb, rough, metal):
		"""Cette méthode permet de poser une matière de base (couleur, rugosité, métal) sur une sélection de texels."""
		self.color[sel] = rgb
		self.rough[sel] = rough
		self.metal[sel] = metal

	def image(self, values, fill_value=0.0):
		"""Cette méthode permet de replacer des valeurs par texel dans l'image et de les étendre aux marges (texel le plus proche)."""
		shape = (self.res, self.res) + values.shape[1:]
		img = np.full(shape, fill_value, dtype=np.float64)
		img[self.cov] = values
		_, idx = ndimage.distance_transform_edt(~self.cov, return_indices=True)
		return img[idx[0], idx[1]]

	def save(self, out_dir, prefix, density):
		"""Cette méthode permet d'écrire les quatre PNG du matériau (normales tirées du relief, en unités monde)."""
		col = self.image(np.clip(self.color, 0, 1))
		h = self.image(self.height)
		gy, gx = np.gradient(h)  # par pixel ; ligne 0 = haut de la carte, v vers le haut
		nx, ny = -gx * density, gy * density
		nz = np.ones_like(nx)
		ln = np.sqrt(nx**2 + ny**2 + nz**2)
		nrm = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5
		out = {
			"Color": col,
			"Rough": self.image(np.clip(self.rough, 0, 1)),
			"Metal": self.image(np.clip(self.metal, 0, 1)),
			"Normal": nrm,
		}
		for kind, img in out.items():
			arr = np.rint(np.clip(img, 0, 1) * 255).astype(np.uint8)
			Image.fromarray(arr, "RGB" if arr.ndim == 3 else "L").save(os.path.join(out_dir, f"{prefix}_{kind}.png"))


def wear(m, amount, seed):
	"""Cette méthode permet de calculer un masque d'usure (0 à 1) sur les arêtes, morcelé par un bruit."""
	nz = fbm(m.p, 0.05, seed, 3)
	return np.clip((m.edge - 0.25) * 3, 0, 1) * np.clip((nz + amount) * 3, 0, 1)


def grime(m):
	"""Cette méthode permet de calculer l'assombrissement des creux (occlusion) à appliquer sur la couleur."""
	return 0.55 + 0.45 * np.clip(m.ao, 0, 1)


def coat(m, sel, base, rough, seed, wear_amount=-0.35):
	"""Cette méthode permet de peindre un revêtement noir non métallique, usé jusqu'à l'acier sur quelques arêtes."""
	var = 1 + 0.08 * fbm(m.p[sel], 0.12, seed, 3)
	m.fill(sel, np.outer(var, base) * grime(m)[sel][:, None], rough + 0.04 * fbm(m.p[sel], 0.06, seed + 3, 3), 0.0)
	m.height[sel] = 0.0004 * fbm(m.p[sel], 0.01, seed + 5, 2)
	w = wear(m, wear_amount, seed + 9)[sel]
	worn = w > 0.5
	idx = np.flatnonzero(sel)[worn]
	m.fill(idx, (0.50, 0.50, 0.52), 0.32, 1.0)


def wood(bake_dir):
	"""Cette méthode permet de peindre le châssis polymère vert olive (granité, arêtes patinées, crasse dans les creux)."""
	m = Maps(bake_dir, "WOOD")
	allp = np.ones(len(m.p), bool)
	tint = 1 + 0.05 * fbm(m.p, 0.4, 11, 3)
	m.color[:] = np.outer(tint, OLIVE) * grime(m)[:, None]
	stip = fbm(m.p, 0.012, 21, 2)
	m.height[:] = 0.0012 * stip
	m.rough[:] = 0.70 + 0.05 * stip
	w = wear(m, -0.1, 31)
	m.color += w[:, None] * 0.06
	m.rough -= w * 0.15
	m.metal[allp] = 0.0
	return m


def metal_a(bake_dir):
	"""Cette méthode permet de peindre boîtier, culasse, chargeur et détente (noir revêtu, corps de culasse en acier nu)."""
	m = Maps(bake_dir, "METAL_A")
	coat(m, np.ones(len(m.p), bool), np.array([0.105, 0.105, 0.11]), 0.42, 41)
	mag = m.is_("Magazine")
	coat(m, mag, np.array([0.085, 0.085, 0.09]), 0.48, 43, wear_amount=-0.45)
	r = np.hypot(m.p[:, 1], m.p[:, 2])
	body = m.is_("Bolt") & (r < 0.075) & (m.p[:, 0] < 0.955)
	brush = fbm(m.p[body] * np.array([0.05, 1, 1]), 0.004, 47, 2)  # stries le long de l'axe
	m.fill(body, np.outer(1 + 0.05 * brush, (0.60, 0.60, 0.61)) * grime(m)[body][:, None], 0.26 + 0.05 * brush, 1.0)
	m.height[body] = 0.0002 * brush
	return m


def metal_b(bake_dir):
	"""Cette méthode permet de peindre canon, frein de bouche, montage de lunette, busc, plaque de couche et vis."""
	m = Maps(bake_dir, "METAL_B")
	coat(m, np.ones(len(m.p), bool), np.array([0.075, 0.075, 0.08]), 0.40, 51)
	x, y, z = m.p[:, 0], m.p[:, 1], m.p[:, 2]
	fit = m.is_("Fittings")
	mount = fit & (z > 0.14) & (x > X(2300)) & (x < X(2640))
	coat(m, mount, np.array([0.09, 0.09, 0.095]), 0.38, 53, wear_amount=-0.2)
	pad = fit & ((x > X(3555)) | ((z > Z(392)) & (x > X(3190))))
	stip = fbm(m.p[pad], 0.014, 57, 2)
	m.fill(pad, np.outer(1 + 0.06 * stip, (0.065, 0.065, 0.068)) * grime(m)[pad][:, None], 0.82 + 0.04 * stip, 0.0)
	m.height[pad] = 0.0015 * stip
	screws = fit & ~mount & ~pad
	m.fill(screws, np.array([0.14, 0.14, 0.145]) * grime(m)[screws][:, None], 0.45, 1.0)
	soot = m.is_("Barrel") & (x < -4.95)
	k = np.clip(fbm(m.p[soot], 0.08, 59, 2) + 0.3, 0, 1) * 0.5
	m.color[soot] *= (1 - k)[:, None]
	return m


def scope(bake_dir):
	"""Cette méthode permet de peindre la lunette (peinte vert olive comme sur CS2, bagues et tourelles noires moletées)."""
	m = Maps(bake_dir, "SCOPE")
	x, y, z = m.p[:, 0], m.p[:, 1], m.p[:, 2] - SCOPE_Z
	tx = X(2450)
	knob = (np.hypot(x - tx, y) < 0.09) & (z > 0.142)  # tourelle d'élévation (au-dessus de la selle, rayon 0,138)
	side = (np.hypot(x - tx, z) < 0.12) & (np.abs(y) > 0.142)  # dérive (droite) et parallaxe (gauche)
	ring = (x > X(2730)) & (x < X(2786)) & (np.hypot(y, z) > 0.124)  # bague de grossissement
	coat(m, np.ones(len(m.p), bool), np.array([0.055, 0.055, 0.06]), 0.46, 61, wear_amount=-0.5)
	painted = ~knob & ~side & ~((x > X(2700)) & (x < X(2790)))
	coat(m, painted, SCOPE_OLIVE, 0.6, 63, wear_amount=-0.3)
	th = np.arctan2(z, y)
	m.height[ring] = 0.0025 * np.sin(th[ring] * 90)
	m.rough[ring] = 0.55
	m.height[knob] = 0.0025 * np.sin(np.arctan2(y[knob], x[knob] - tx) * 48)
	m.height[side] = 0.0025 * np.sin(np.arctan2(z[side], x[side] - tx) * 56)
	# fonds du tube derrière les verres : intérieur noir mat, vu à travers le verre teinté
	r = np.hypot(y, z)
	inside = ((x < X(1888)) & (r < 0.1885)) | ((x > X(2928)) & (r < 0.1055))  # l'extérieur est plus large aux deux bouts
	m.fill(inside, (0.02, 0.022, 0.025), 0.9, 0.0)
	m.height[inside] = 0.0
	return m


def main():
	"""Cette méthode permet de peindre et d'écrire les cartes des quatre matériaux texturés."""
	bake_dir, out_dir = sys.argv[1], sys.argv[2]
	os.makedirs(out_dir, exist_ok=True)
	density = float(sys.argv[3]) if len(sys.argv) > 3 else 226.0  # pixels de carte par unité (build_awp.py)
	for prefix, painter in (("WOOD", wood), ("METAL_A", metal_a), ("METAL_B", metal_b), ("SCOPE", scope)):
		m = painter(bake_dir)
		m.save(out_dir, prefix, density)
		print(f"[textures] {prefix} : {len(m.p)} texels")


main()
