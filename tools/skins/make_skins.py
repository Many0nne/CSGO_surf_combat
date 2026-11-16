"""Fabrique les cartes PBR des skins de l'AWP et de la M9 (#268), à partir des cartes cuites par bake_maps.py.

Chaque motif se calcule sur la position 3D du texel (continu d'une pièce à l'autre, indépendant du découpage UV) ou se
projette depuis la vue de profil (livrée). Le détail des cartes d'origine (normales, rayures, quadrillage du manche) est
gardé : un skin repeint l'arme, il ne la lisse pas.

Usage (depuis la racine du worktree) :
  uv run --with numpy --with pillow --with scipy tools/skins/make_skins.py <bake> <m9_orig> <sortie> [skin ...]
    <bake>     dossier de bake_maps.py, avec les sous-dossiers awp/ et m9/
    <m9_orig>  dossier des cartes d'origine de la M9 (sortie de fetch_viewmodel.py : m9_Handle_*.png)
    <sortie>   écrit <sortie>/<skin>/AWP/<MAT>_<Carte>.png et <sortie>/<skin>/M9Bayonet/Handle_<Carte>.png
Skins : couchant, releve (#268), recuit (#337) ; tous par défaut. Impact, strate et sillage, retirés en #420, sont
remplacés par des skins dessinés pour la M9 (assets/m9/skins/).
"""

import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AWP_TEX = os.path.join(ROOT, "assets", "sniper", "textures")
AWP_MATS = ["METAL_A", "METAL_B", "SCOPE", "WOOD"]

# Palette du jeu (UITheme) et matières de base, en sRGB 0..1
BONE = np.array([236, 226, 211]) / 255
HIT_RED = np.array([226, 58, 40]) / 255
AMBER = np.array([242, 169, 0]) / 255
STEEL = np.array([200, 203, 208]) / 255
BLACK_STEEL = np.array([58, 60, 66]) / 255
GOLD = np.array([228, 178, 96]) / 255

# Densité de texels d'un matériau rapportée à celle pour laquelle ses réglages en pixels (flou du détail, épaisseur des
# courbes de niveau, force du relief) ont été choisis. La crosse de l'AWP a été redépliée (#335 : 111 -> 205 px par
# unité) : ses réglages sont multipliés d'autant pour garder leur taille dans le monde, donc le même rendu, plus net.
PX_SCALE = {("awp", "WOOD_PBR"): 1.846}


# ---------------------------------------------------------------------------------------------------------------------
# Bruit


# Cette méthode permet de construire une table de permutation reproductible pour le bruit de gradient d'une graine donnée.
def _perm(seed):
	rng = np.random.default_rng(seed)
	p = rng.permutation(256)
	return np.concatenate([p, p])


_GRAD = np.array(
	[[1, 1, 0], [-1, 1, 0], [1, -1, 0], [-1, -1, 0], [1, 0, 1], [-1, 0, 1], [1, 0, -1], [-1, 0, -1], [0, 1, 1], [0, -1, 1], [0, 1, -1], [0, -1, -1]],
	dtype=np.float32,
)


# Cette méthode permet d'évaluer un bruit de gradient 3D (type Perlin, valeurs ~ -1..1) en un lot de points (N, 3).
def perlin3(p, seed=0):
	perm = _perm(seed)
	pi = np.floor(p).astype(np.int64)
	pf = (p - pi).astype(np.float32)
	pi &= 255
	f = pf * pf * pf * (pf * (pf * 6 - 15) + 10)
	out = 0
	acc = []
	for dx in (0, 1):
		for dy in (0, 1):
			for dz in (0, 1):
				h = perm[perm[perm[pi[:, 0] + dx] + pi[:, 1] + dy] + pi[:, 2] + dz] % 12
				g = _GRAD[h]
				d = pf - np.array([dx, dy, dz], dtype=np.float32)
				acc.append((g * d).sum(1))
	# Interpolation trilinéaire lissée des 8 coins (ordre dx, dy, dz)
	x, y, z = f[:, 0], f[:, 1], f[:, 2]
	c = [a for a in acc]
	l00 = c[0] + (c[4] - c[0]) * x
	l01 = c[1] + (c[5] - c[1]) * x
	l10 = c[2] + (c[6] - c[2]) * x
	l11 = c[3] + (c[7] - c[3]) * x
	l0 = l00 + (l10 - l00) * y
	l1 = l01 + (l11 - l01) * y
	out = l0 + (l1 - l0) * z
	return out


# Cette méthode permet de sommer plusieurs octaves de bruit (fbm) lorsqu'un motif a besoin de détail à plusieurs échelles.
def fbm(p, octaves=4, seed=0, gain=0.5, lac=2.03):
	total, amp, norm = 0, 1.0, 0
	for i in range(octaves):
		total = total + amp * perlin3(p * (lac**i), seed + i * 17)
		norm += amp
		amp *= gain
	return total / norm


# ---------------------------------------------------------------------------------------------------------------------
# Lecture, écriture, utilitaires d'image


# Cette méthode permet de lire une image en flottants 0..1 (RGB ou niveaux de gris) lorsqu'on charge une carte d'origine.
def read(path, gray=False):
	im = Image.open(path)
	im = im.convert("L" if gray else "RGB")
	return np.asarray(im, dtype=np.float32) / 255


class Mat:
	"""Un matériau texturé : cartes cuites, cartes d'origine et masques utiles aux skins."""

	# Cette méthode permet de charger les cartes cuites et d'origine d'un matériau lorsqu'on fabrique ses skins.
	def __init__(self, weapon, name, bake_dir, orig):
		d = np.load(os.path.join(bake_dir, f"{name}.npz"))
		bb = json.load(open(os.path.join(bake_dir, "bbox.json")))
		self.weapon, self.name = weapon, name
		self.px = PX_SCALE.get((weapon, name), 1.0)
		self.bmin, self.bmax = np.array(bb["min"]), np.array(bb["max"])
		self.npos = d["pos"].astype(np.float32)
		self.pos = self.npos * (self.bmax - self.bmin) + self.bmin
		self.nrm = d["nrm"].astype(np.float32) * 2 - 1
		aux = d["aux"].astype(np.float32)
		self.ao, self.edge, self.cov = aux[..., 0], aux[..., 1], aux[..., 2] > 0.5
		self.oid = d["oid"] if "oid" in d else np.zeros(self.cov.shape, np.uint8)
		self.objects = [str(o) for o in d["objects"]]
		self.color = read(orig["Color"])
		self.rough = read(orig["Rough"], True)
		self.metal = read(orig["Metal"], True)
		self.normal = read(orig["Normal"]) * 2 - 1
		self.H, self.W = self.cov.shape
		self.idx = np.nonzero(self.cov)
		lum = self.color @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
		self.lum = lum
		# Détail d'origine : luminance rapportée à sa moyenne locale (rayures, quadrillage, saleté cuite)
		blur = ndimage.gaussian_filter(lum, 6 * self.px) + 1e-3
		self.detail = np.clip(lum / blur, 0.6, 1.4)
		# Arêtes : nœud Bevel cuit + écart de la normale d'origine (biseaux peints dans la carte)
		dev = np.clip((1 - self.normal[..., 2]) * 6, 0, 1)
		e = np.clip(self.edge / max(np.percentile(self.edge[self.cov], 99), 1e-4), 0, 1)
		self.edges = np.clip(np.maximum(e, dev), 0, 1)

	# Cette méthode permet de renvoyer le masque des texels d'un objet donné (par son nom) dans ce matériau.
	def obj(self, name):
		return self.oid == (self.objects.index(name) + 1) if name in self.objects else np.zeros_like(self.cov)

	# Cette méthode permet d'évaluer un champ de bruit sur les positions 3D des texels couverts, en image pleine.
	def field(self, fn):
		out = np.zeros((self.H, self.W), np.float32)
		out[self.idx] = fn(self.pos[self.idx])
		return out


# Cette méthode permet de prolonger les valeurs des îlots UV sur les texels vides voisins, pour éviter les coutures
# sombres quand Roblox réduit la texture (mipmaps).
def dilate(img, cov):
	_, (iy, ix) = ndimage.distance_transform_edt(~cov, return_indices=True)
	return img[iy, ix]


# Cette méthode permet de convertir un relief (hauteur par pixel, à la densité de référence du matériau) en normale
# tangente et de la combiner à la normale d'origine (mélange « whiteout »), lorsqu'un skin ajoute gravure ou brossage.
def add_relief(mat, height, strength):
	normal = mat.normal
	strength = strength * mat.px
	h = dilate(height, mat.cov)
	gy, gx = np.gradient(h)
	n2 = np.stack([-gx * strength, gy * strength, np.ones_like(h)], -1)  # +V vers le haut de l'image
	n2 /= np.linalg.norm(n2, axis=-1, keepdims=True)
	n = np.stack([normal[..., 0] + n2[..., 0], normal[..., 1] + n2[..., 1], normal[..., 2] * n2[..., 2]], -1)
	return n / np.linalg.norm(n, axis=-1, keepdims=True)


# Cette méthode permet d'interpoler une rampe de couleurs (liste de (position, rgb 0..255)) en un champ de valeurs 0..1.
def ramp(v, stops):
	xs = np.array([s[0] for s in stops])
	cols = np.array([s[1] for s in stops], dtype=np.float32) / 255
	v = np.clip(v, 0, 1)
	return np.stack([np.interp(v, xs, cols[:, i]) for i in range(3)], -1)


# Cette méthode permet de mélanger deux valeurs (scalaires, couleurs ou cartes) selon un masque 0..1.
def mix(a, b, m):
	m = np.asarray(m, dtype=np.float32)
	if np.ndim(a) in (1, 3) or np.ndim(b) in (1, 3):  # couleur (rgb seul ou carte) : masque étendu aux canaux
		m = m[..., None] if m.ndim == 2 else m
	return a * (1 - m) + b * m


# Cette méthode permet de lisser un seuil (0 sous a, 1 au-dessus de b), comme smoothstep.
def smooth(a, b, x):
	t = np.clip((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)


# Cette méthode permet d'écrire les quatre cartes d'un matériau (après prolongement hors îlots) au format attendu
# par la SurfaceAppearance.
def write(out_dir, prefix, mat, color, rough, metal, normal):
	os.makedirs(out_dir, exist_ok=True)
	c = dilate(np.clip(color, 0, 1), mat.cov)
	r = dilate(np.clip(rough, 0, 1) * np.ones((mat.H, mat.W)), mat.cov)
	m = dilate(np.clip(metal, 0, 1) * np.ones((mat.H, mat.W)), mat.cov)
	n = dilate(normal, mat.cov)
	Image.fromarray((c * 255 + 0.5).astype(np.uint8)).save(os.path.join(out_dir, f"{prefix}_Color.png"))
	Image.fromarray((r * 255 + 0.5).astype(np.uint8)).save(os.path.join(out_dir, f"{prefix}_Rough.png"))
	Image.fromarray((m * 255 + 0.5).astype(np.uint8)).save(os.path.join(out_dir, f"{prefix}_Metal.png"))
	Image.fromarray(((n * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8)).save(os.path.join(out_dir, f"{prefix}_Normal.png"))


# ---------------------------------------------------------------------------------------------------------------------
# Repères propres à chaque arme


class Knife:
	"""Repère de la M9 : axe de la lame (t, pointe vers les t négatifs) et zones lame, tranchant, garde, manche, pommeau."""

	GUARD_T, GRIP_T, POMMEL_T = 0.30, 0.35, 1.50

	# Cette méthode permet de calculer l'axe du couteau et les masques de zones à partir des positions cuites.
	def __init__(self, mat):
		P = mat.pos[mat.cov]
		self.c = P.mean(0)
		_, _, vt = np.linalg.svd(P - self.c, full_matrices=False)
		self.axis, self.height, self.flat = vt
		t = (mat.pos - self.c) @ self.axis
		left = mat.cov.copy()
		left[:, int(mat.W * 0.35) :] = False
		if t[left].mean() > 0:  # la lame (îlots de gauche) doit être du côté négatif
			self.axis = -self.axis
			t = -t
		self.t = t
		self.tmin = t[mat.cov].min()
		cov = mat.cov
		self.blade = cov & (t < self.GUARD_T)
		self.guard = cov & (t >= self.GUARD_T) & (t < self.GRIP_T)
		self.grip = cov & (t >= self.GRIP_T) & (t < self.POMMEL_T)
		self.pommel = cov & (t >= self.POMMEL_T)
		self.grind = self.blade & (ndimage.gaussian_filter(mat.metal, 1.5) > 0.5)
		self.flatm = self.blade & ~self.grind
		# Position le long de la lame : 0 à la pointe, 1 au talon
		self.g = np.clip((t - self.tmin) / (self.GUARD_T - self.tmin), 0, 1)

	# Cette méthode permet de trouver, pour chacune des deux faces de la lame (îlots gauche et droit du dépliage), le
	# texel du plat le plus proche d'une position t donnée au milieu de la hauteur de lame.
	def blade_points(self, mat, t_target):
		pts = []
		half = int(mat.W * 0.35 / 2)
		for x0, x1 in ((0, half), (half, int(mat.W * 0.35))):
			m = self.flatm.copy()
			m[:, :x0] = False
			m[:, x1:] = False
			sel = m & (np.abs(self.t - t_target) < 0.04)
			ys, xs = np.nonzero(sel)
			pts.append((float(ys.mean()), float(xs.mean())))
		return pts


# Cette méthode permet de donner, pour l'AWP, la position le long de l'arme (0 à la bouche du canon, 1 au talon de crosse).
def awp_s(mat):
	return np.clip((mat.pos[..., 0] - mat.bmin[0]) / (mat.bmax[0] - mat.bmin[0]), 0, 1)


# ---------------------------------------------------------------------------------------------------------------------
# Skin « Couchant » : anodisé sur métal poli, du ciel bleu nuit à l'ambre du couchant (pièce maîtresse, façon Doppler)

SUNSET = [
	(0.00, (255, 206, 120)),
	(0.14, (255, 138, 28)),
	(0.32, (226, 40, 64)),
	(0.50, (170, 22, 130)),
	(0.68, (92, 26, 176)),
	(0.84, (30, 40, 168)),
	(1.00, (10, 18, 82)),
]


# Cette méthode permet de calculer les volutes de l'anodisation (bruit déformé, grandes nappes), le marbrage clair/sombre
# qui donne la profondeur d'un Doppler, et les veines sombres, sur les positions 3D, pour une fréquence donnée.
def sunset_fields(mat, freq, seed=3):
	def swirl(p):
		q = p * freq
		w = np.stack([fbm(q + 11.3, 3, seed), fbm(q + 47.1, 3, seed + 5), fbm(q + 83.7, 3, seed + 9)], 1)
		return fbm(q + w * 1.8, 5, seed + 21)

	def marble(p):
		q = p * freq * 1.6
		w = np.stack([fbm(q + 2.7, 3, seed + 30), fbm(q + 6.1, 3, seed + 31), fbm(q + 9.4, 3, seed + 32)], 1)
		return fbm(q + w * 2.2, 6, seed + 35)

	def vein(p):
		q = p * freq * 2.4
		w = np.stack([fbm(q + 5.1, 2, seed + 40), fbm(q + 9.9, 2, seed + 41), fbm(q + 2.2, 2, seed + 42)], 1)
		return fbm(q + w * 0.9, 4, seed + 50)

	sw = mat.field(swirl)
	lum = smooth(-0.22, 0.30, mat.field(marble))
	vn = mat.field(vein)
	veins = np.exp(-(vn**2) / (2 * 0.010**2))
	return sw, lum, veins


# Cette méthode permet de colorer l'anodisation : teinte de la rampe, assombrie par le marbrage (zones presque noires,
# nappes lumineuses saturées) et les veines ; le métal poli fait le reste avec les reflets.
def sunset_color(v, lum, veins):
	col = ramp(v, SUNSET)
	shade = 0.16 + 0.9 * lum
	return col * shade[..., None] * (1 - 0.6 * veins[..., None])


# Cette méthode permet de produire les cartes « Couchant » de la M9.
def couchant_m9(mat, k):
	sw, lum, veins = sunset_fields(mat, 1.3)
	v = np.clip(k.g * 0.78 + sw * 0.6 - 0.06, 0, 1)
	col = sunset_color(v, lum, veins) * mix(1, mat.detail, 0.25)[..., None]
	rough = 0.05 + 0.04 * (1 - lum) + 0.08 * veins
	metal = np.ones((mat.H, mat.W))
	# Brossage très fin le long de l'axe (relief à peine visible, il casse les reflets trop parfaits)
	brush = mat.field(lambda p: perlin3(np.stack([(p @ k.axis) * 3, (p @ k.height) * 260, (p @ k.flat) * 260], 1), 5))
	height = brush * 0.25
	# Tranchant poli : acier clair teinté par l'anodisation
	gcol = mix(ramp(v, SUNSET), np.array([240, 228, 210]) / 255, 0.6)
	col = mix(col, gcol, k.grind)
	rough = mix(rough, 0.05, k.grind)
	height = height + brush * 0.4 * k.grind
	# Garde et pommeau : même anodisation, poussée vers le bleu nuit
	hw = k.guard | k.pommel
	hcol = sunset_color(np.clip(0.82 + sw * 0.4, 0, 1), lum, veins) * mix(1, mat.detail, 0.4)[..., None]
	col = mix(col, hcol, hw)
	rough = mix(rough, 0.08, hw)
	# Manche : caoutchouc d'origine, refroidi
	gripcol = mat.color * np.array([0.55, 0.58, 0.72])
	col = mix(col, gripcol, k.grip)
	rough = mix(rough, mat.rough, k.grip)
	metal = mix(metal, mat.metal, k.grip)
	height = height * (k.blade | hw)
	col = col * mix(1, mat.ao, 0.5)[..., None]
	return col, rough, metal, add_relief(mat, height, 0.6)


# Cette méthode permet de produire les cartes « Couchant » d'un matériau de l'AWP : métal anodisé marbré en dégradé de
# la bouche (ambre) au talon (bleu nuit), crosse en bois teinté bleu nuit, vernis brillant.
def couchant_awp(mat):
	s = awp_s(mat)
	sw, lum, veins = sunset_fields(mat, 0.5)
	v = np.clip(s * 0.95 + sw * 0.45 + 0.02, 0, 1)
	if mat.name == "WOOD":
		# Peinture candy métallique sur la crosse : même marbrure, plus sombre vers le talon ; un bois mat sombre
		# prenait un voile gris plastique sous les reflets
		vw = np.clip(0.55 + s * 0.4 + sw * 0.35, 0, 1)
		col = sunset_color(vw, lum * (1.15 - 0.55 * s), veins) * mix(1, mat.detail, 0.2)[..., None]
		rough = 0.12 + 0.06 * (1 - lum) + 0.08 * veins
		metal = np.ones((mat.H, mat.W))
		height = np.zeros((mat.H, mat.W))
	else:
		col = sunset_color(v, lum, veins) * mix(1, mat.detail, 0.3)[..., None]
		rough = 0.07 + 0.05 * (1 - lum) + 0.08 * veins
		metal = np.ones((mat.H, mat.W))
		height = np.zeros((mat.H, mat.W))
		# Arêtes polies plus claires (usure du film anodisé)
		col = mix(col, ramp(v, SUNSET) * 0.5 + 0.45 * np.array([0.93, 0.89, 0.82]), mat.edges * 0.4)
	col = col * mix(1, mat.ao, 0.5)[..., None]
	return col, rough, metal, add_relief(mat, height, 0.6)


# ---------------------------------------------------------------------------------------------------------------------
# Skin « Relevé » : courbes de niveau incrustées d'or sur acier noirci (et ébène pour la crosse)


# Cette méthode permet de calculer les courbes de niveau d'un relief 3D (lignes d'épaisseur constante en pixels, une
# courbe maîtresse sur cinq plus épaisse), à partir d'une fréquence et d'un nombre de niveaux par unité de relief.
def contours(mat, freq, levels, width_px=1.3, squash_y=0.25, seed=61, min_gap=0.08):
	def relief(p):
		q = p * freq
		q[:, 1] *= squash_y  # les deux flancs de l'arme portent presque le même relevé
		w = np.stack([fbm(q + 3.3, 2, seed + 1), fbm(q + 7.7, 2, seed + 2), fbm(q + 1.1, 2, seed + 3)], 1)
		return fbm(q + w * 0.35, 4, seed)

	hgt = mat.field(relief)
	c = hgt * levels
	gy, gx = np.gradient(dilate(c, mat.cov))
	gpx = np.hypot(gx, gy) + 1e-4
	frac = np.abs(c - np.round(c))  # distance au niveau le plus proche, en niveaux
	major = (np.round(c).astype(int) % 5) == 0
	wdt = width_px * mat.px * np.where(major, 1.9, 1.0)
	line = smooth(wdt * 0.5 + 0.6, wdt * 0.5 - 0.4, frac / gpx)
	# Écart entre deux courbes en unités monde (pixels x taille monde d'un pixel, propre à chaque îlot UV) : sous
	# min_gap, les intermédiaires s'effacent, puis les maîtresses, comme sur une vraie carte
	py, px = np.gradient(dilate(mat.pos, mat.cov), axis=(0, 1))
	wpp = np.sqrt((np.linalg.norm(py, axis=-1) ** 2 + np.linalg.norm(px, axis=-1) ** 2) / 2) + 1e-6
	gap = wpp / gpx
	keep = np.where(major, smooth(min_gap * 1.2, min_gap * 2.2, gap * 5), smooth(min_gap, min_gap * 1.6, gap))
	return np.clip(line * keep, 0, 1) * mat.cov, hgt


# Cette méthode permet de produire les cartes « Relevé » de la M9.
def releve_m9(mat, k):
	lines, hgt = contours(mat, 0.75, 26, width_px=1.3, min_gap=0.03)
	brush = mat.field(lambda p: perlin3(np.stack([(p @ k.axis) * 3, (p @ k.height) * 200, (p @ k.flat) * 200], 1), 9))
	base = BLACK_STEEL * (0.95 + 0.12 * hgt[..., None]) * mix(1, mat.detail, 0.45)[..., None]
	col = mix(base, GOLD, lines)
	rough = mix(0.30 + 0.03 * brush, 0.16, lines)
	metal = np.ones((mat.H, mat.W))
	height = brush * 0.35 + lines * 1.2
	col = mix(col, STEEL * mix(1, mat.detail, 0.5)[..., None], k.grind)
	rough = mix(rough, 0.12, k.grind)
	height = height * k.blade
	# Garde et pommeau en laiton poli, manche d'origine
	hw = k.guard | k.pommel
	col = mix(col, GOLD * 0.92 * mix(1, mat.detail, 0.5)[..., None], hw)
	rough = mix(rough, 0.2, hw)
	col = mix(col, mat.color, k.grip)
	rough = mix(rough, mat.rough, k.grip)
	metal = mix(metal, mat.metal, k.grip)
	col = col * mix(1, mat.ao, 0.5)[..., None]
	return col, rough, metal, add_relief(mat, height, 0.7)


# Cette méthode permet de produire les cartes « Relevé » d'un matériau de l'AWP.
def releve_awp(mat):
	lines, hgt = contours(mat, 0.22, 30, width_px=1.15, min_gap=0.09)
	if mat.name == "WOOD":
		grain = np.clip((mat.lum - mat.lum[mat.cov].mean()) / (mat.lum[mat.cov].std() * 3) + 0.5, 0, 1)
		base = np.array([0.15, 0.12, 0.105]) * (0.6 + 0.8 * grain[..., None])
		rough0 = 0.32 + 0.08 * (1 - grain)
		metal = mix(0, 1, lines)
	else:
		base = BLACK_STEEL * mix(1, mat.detail, 0.5)[..., None]
		rough0 = 0.30 + 0.0 * hgt
		metal = np.ones((mat.H, mat.W))
	col = mix(base, GOLD, lines)
	rough = mix(rough0, 0.16, lines)
	height = lines * 1.2
	gold_parts = mat.obj("Bolt") | mat.obj("Trigger")
	col = mix(col, GOLD * mix(1, mat.detail, 0.5)[..., None], gold_parts)
	rough = mix(rough, 0.18, gold_parts)
	col = col * mix(1, mat.ao, 0.5)[..., None]
	return col, rough, metal, add_relief(mat, height, 0.7)


# Cette méthode permet de donner la hauteur dans la lame de la M9 (0 au tranchant, 1 au dos) lorsqu'un motif suit le
# profil de la lame.
def blade_height(mat, k):
	hb = (mat.pos - k.c) @ k.height
	hb = (hb - hb[k.blade].min()) / (np.ptp(hb[k.blade]) + 1e-6)
	if np.mean(hb[k.grind]) > 0.5:
		hb = 1 - hb
	return hb


# ---------------------------------------------------------------------------------------------------------------------
# Skin « Recuit » : acier trempé en caisse (façon Case Hardened), marbrures d'oxydation bleu nuit, violet, bronze et
# paille sur acier gris ; le bleu domine

TEMPER = [
	(0.00, (18, 30, 84)),
	(0.18, (34, 62, 150)),
	(0.32, (58, 96, 182)),
	(0.42, (104, 66, 146)),
	(0.52, (150, 84, 92)),
	(0.62, (168, 112, 56)),
	(0.74, (214, 172, 88)),
	(0.86, (178, 176, 168)),
	(1.00, (122, 124, 128)),
]


# Cette méthode permet de calculer les marbrures de la trempe (nappes déformées à grande échelle, taches et mouchetures
# sombres à petite échelle) sur les positions 3D, pour une fréquence donnée ; renvoie la teinte (0..1) et les taches.
def temper_fields(mat, freq, seed=71, bias=0.0):
	def flow(p):
		q = p * freq
		w = np.stack([fbm(q + 4.1, 3, seed), fbm(q + 8.3, 3, seed + 3), fbm(q + 1.7, 3, seed + 6)], 1)
		w2 = np.stack([fbm(q * 2.1 + w * 1.5 + 3.3, 3, seed + 9), fbm(q * 2.1 + w * 1.5 + 9.1, 3, seed + 12), fbm(q * 2.1 + 5.5, 2, seed + 15)], 1)
		return fbm(q + w * 1.6 + w2 * 0.6, 5, seed + 20)

	def spots(p):
		return fbm(p * freq * 7, 4, seed + 40)

	v = mat.field(flow)
	v = np.clip(0.5 + v * 1.25 + bias, 0, 1)
	sp = smooth(0.18, 0.34, mat.field(spots))
	return v, sp


# Cette méthode permet de colorer la trempe : rampe d'oxydation, mouchetures sombres, et le grain de l'acier gardé.
def temper_color(mat, v, sp, detail=0.35):
	col = ramp(v, TEMPER) * (1 - 0.45 * sp[..., None])
	return col * mix(1, mat.detail, detail)[..., None]


# Cette méthode permet de produire les cartes « Recuit » de la M9 : lame, garde et pommeau trempés, tranchant repoli plus
# clair, manche d'origine.
def recuit_m9(mat, k):
	v, sp = temper_fields(mat, 1.1, bias=-0.08)
	col = temper_color(mat, v, sp)
	rough = 0.18 + 0.08 * sp + 0.05 * smooth(0.6, 0.9, v)
	metal = np.ones((mat.H, mat.W))
	brush = mat.field(lambda p: perlin3(np.stack([(p @ k.axis) * 3, (p @ k.height) * 220, (p @ k.flat) * 220], 1), 13))
	height = brush * 0.3 - sp * 0.15
	# Tranchant repoli : l'oxydation part, il reste un voile paille et bleu clair
	gcol = mix(temper_color(mat, v, sp, 0.5), STEEL * mix(1, mat.detail, 0.5)[..., None], 0.62)
	col = mix(col, gcol, k.grind)
	rough = mix(rough, 0.1, k.grind)
	hw = k.guard | k.pommel
	v2, sp2 = temper_fields(mat, 2.2, seed=91, bias=-0.12)
	col = mix(col, temper_color(mat, v2, sp2, 0.5), hw)
	rough = mix(rough, 0.2, hw)
	col = mix(col, mat.color, k.grip)
	rough = mix(rough, mat.rough, k.grip)
	metal = mix(metal, mat.metal, k.grip)
	height = height * (k.blade | hw)
	col = col * mix(1, mat.ao, 0.5)[..., None]
	return col, rough, metal, add_relief(mat, height, 0.6)


# Cette méthode permet de produire les cartes « Recuit » d'un matériau de l'AWP : carcasse, canon et garnitures trempés,
# lunette en acier bleui, fût et crosse en noyer huilé (l'arme de chasse classique).
def recuit_awp(mat):
	if mat.name == "WOOD":
		# Noyer : le bois d'origine, plus rouge et plus contrasté (un bois plus sombre prend un voile gris sous les reflets)
		figure = mat.field(lambda p: fbm(p * np.array([0.6, 3.0, 3.0]), 4, 77)) * 0.5 + 0.5
		col = mat.color * np.array([0.92, 0.72, 0.6]) * (0.85 + 0.3 * figure[..., None])
		rough = mat.rough * 0.9
		metal = np.zeros((mat.H, mat.W))
		height = np.zeros((mat.H, mat.W))
	elif mat.name == "SCOPE":
		# Acier bleui : bleu nuit profond, reflets bleutés, arêtes usées vers l'acier
		blue = mat.field(lambda p: fbm(p * 1.2, 3, 83)) * 0.5 + 0.5
		col = mix(np.array([0.05, 0.08, 0.17]), np.array([0.10, 0.16, 0.34]), blue) * mix(1, mat.detail, 0.5)[..., None]
		col = mix(col, STEEL * 0.75, mat.edges * 0.5)
		rough = 0.2 + 0.06 * blue
		metal = np.ones((mat.H, mat.W))
		height = np.zeros((mat.H, mat.W))
	else:
		v, sp = temper_fields(mat, 0.42, bias=-0.06)
		col = temper_color(mat, v, sp)
		rough = 0.2 + 0.08 * sp + 0.05 * smooth(0.6, 0.9, v)
		metal = np.ones((mat.H, mat.W))
		height = -sp * 0.2
		col = mix(col, STEEL * 0.8, mat.edges * 0.3)
	col = col * mix(1, mat.ao, 0.5)[..., None]
	return col, rough, metal, add_relief(mat, height, 0.6)


# ---------------------------------------------------------------------------------------------------------------------


# Cette méthode permet de fabriquer tous les matériaux d'un skin pour les deux armes et de les écrire.
def build(skin, bake, m9_orig, out):
	m9 = Mat("m9", "Handle", os.path.join(bake, "m9"), {k: os.path.join(m9_orig, f"m9_Handle_{k}.png") for k in ("Color", "Rough", "Metal", "Normal")})
	k = Knife(m9)
	m9_fns = {"couchant": couchant_m9, "releve": releve_m9, "recuit": recuit_m9}
	write(os.path.join(out, skin, "M9Bayonet"), "Handle", m9, *m9_fns[skin](m9, k))
	print(f"[skins] {skin} M9Bayonet")
	awp_fns = {"couchant": couchant_awp, "releve": releve_awp, "recuit": recuit_awp}
	for name in AWP_MATS:
		mat = Mat("awp", name + "_PBR", os.path.join(bake, "awp"), {k2: os.path.join(AWP_TEX, f"{name}_{k2}.png") for k2 in ("Color", "Rough", "Metal", "Normal")})
		mat.name = name
		maps = awp_fns[skin](mat)
		write(os.path.join(out, skin, "AWP"), name, mat, *maps)
		print(f"[skins] {skin} AWP {name}")


if __name__ == "__main__":
	bake, m9_orig, out = sys.argv[1:4]
	skins = sys.argv[4:] or ["couchant", "releve", "recuit"]
	for s in skins:
		build(s, bake, m9_orig, out)
