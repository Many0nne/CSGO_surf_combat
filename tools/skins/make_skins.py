"""Fabrique les cartes PBR des skins de l'AWP et de la M9 (#268), à partir des cartes cuites par bake_maps.py.

Chaque motif se calcule sur la position 3D du texel (continu d'une pièce à l'autre, indépendant du découpage UV) ou se
projette depuis la vue de profil (livrée). Le détail des cartes d'origine (normales, rayures, quadrillage du manche) est
gardé : un skin repeint l'arme, il ne la lisse pas.

Usage (depuis la racine du worktree) :
  uv run --with numpy --with pillow --with scipy tools/skins/make_skins.py <bake> <m9_orig> <sortie> [skin ...]
    <bake>     dossier de bake_maps.py, avec les sous-dossiers awp/ et m9/
    <m9_orig>  dossier des cartes d'origine de la M9 (sortie de fetch_viewmodel.py : m9_Handle_*.png)
    <sortie>   écrit <sortie>/<skin>/AWP/<MAT>_<Carte>.png et <sortie>/<skin>/M9Bayonet/Handle_<Carte>.png
Skins : couchant, impact, releve (#268), recuit, strate, sillage (#337) ; tous par défaut.
"""

import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
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
		blur = ndimage.gaussian_filter(lum, 6) + 1e-3
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


# Cette méthode permet de convertir un relief (hauteur en pixels) en normale tangente et de la combiner à la normale
# d'origine (mélange « whiteout »), lorsqu'un skin ajoute gravure, incrustation ou brossage.
def add_relief(normal, height, strength, cov):
	h = dilate(height, cov)
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
	return col, rough, metal, add_relief(mat.normal, height, 0.6, mat.cov)


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
	return col, rough, metal, add_relief(mat.normal, height, 0.6, mat.cov)


# ---------------------------------------------------------------------------------------------------------------------
# Skin « Impact » : céramique couleur os, aplats rouge d'impact et noir, réticule et impact de balle écaillé

IMP_BONE = np.array([218, 206, 186]) / 255
IMP_RED = np.array([206, 38, 26]) / 255
IMP_BLACK = np.array([24, 24, 26]) / 255


# Cette méthode permet de dessiner un impact de balle (cratère, écaillage irrégulier, fissures radiales) et un réticule
# autour, dans un repère local (x, y en unités du rayon R) ; renvoie les masques chip, crack, crater et reticle.
def impact_masks(x, y, seed=7, reticle=True, lw=0.09):
	r = np.hypot(x, y)
	a = np.arctan2(y, x)
	rng = np.random.default_rng(seed)
	# Contour d'écaillage : rayon modulé par l'angle (somme d'harmoniques aléatoires)
	edge = np.ones_like(r) * 0.6
	for k in range(2, 11):
		edge = edge + rng.uniform(0.03, 0.12) / (k * 0.45) * np.cos(k * a + rng.uniform(0, 6.28))
	chip = smooth(edge + 0.02, edge - 0.02, r)
	crater = smooth(0.24, 0.14, r)
	# Fissures : rayons fins aux angles aléatoires, qui s'amincissent vers l'extérieur, avec une branche chacun
	crack = np.zeros_like(r)
	for _ in range(11):
		ang = rng.uniform(-np.pi, np.pi)
		length = rng.uniform(1.2, 2.3)
		wob = ang + 0.1 * np.sin(r * rng.uniform(4, 9) + rng.uniform(0, 6))
		d = np.abs(np.angle(np.exp(1j * (a - wob)))) * r
		w = 0.05 * (1 - r / length)
		crack = np.maximum(crack, smooth(w, w * 0.3, d) * (r < length) * (r > 0.45))
		br = ang + rng.choice([-1, 1]) * rng.uniform(0.25, 0.5)
		r0 = rng.uniform(0.8, 1.2)
		d2 = np.abs(np.angle(np.exp(1j * (a - br)))) * r
		w2 = 0.035 * (1 - (r - r0) / 0.7)
		crack = np.maximum(crack, smooth(w2, w2 * 0.3, d2) * (r > r0) * (r < r0 + 0.7))
	ret = np.zeros_like(r)
	if reticle:
		ring = smooth(lw, lw * 0.5, np.abs(r - 1.85))
		arm = lambda u, w_: smooth(w_, w_ * 0.5, np.abs(u))  # noqa: E731
		cross = arm(x, lw) * ((np.abs(y) > 1.05) & (np.abs(y) < 2.7)) + arm(y, lw) * ((np.abs(x) > 1.05) & (np.abs(x) < 2.7))
		ticks = np.zeros_like(r)
		for tr in (1.3, 1.55, 2.15, 2.4):
			ticks = np.maximum(ticks, smooth(lw * 0.7, lw * 0.35, np.abs(r - tr)) * (np.minimum(np.abs(x), np.abs(y)) < 0.16))
		ret = np.clip(ring + cross + ticks, 0, 1)
	return chip, np.clip(crack, 0, 1), crater, ret


# Cette méthode permet de calculer le grain « peau d'orange » de la céramique et l'écaillage des arêtes (masque 0..1).
def ceramic(mat, freq, wear=0.5):
	speck = mat.field(lambda p: fbm(p * freq * 45, 2, 31))
	breakup = mat.field(lambda p: fbm(p * freq * 5, 4, 33)) * 0.5 + 0.5
	chips = smooth(wear, wear + 0.06, mat.edges * (0.5 + 1.0 * breakup))
	return speck, chips


# Cette méthode permet de produire les cartes « Impact » de la M9 : lame céramique os, talon rouge coupé en biais
# (liseré noir), impact écaillé et réticule noir à mi-lame, tranchant et arêtes à nu.
def impact_m9(mat, k):
	speck, chips = ceramic(mat, 1.0, 0.42)
	col = np.broadcast_to(IMP_BONE, (mat.H, mat.W, 3)) * (1 + 0.04 * speck[..., None]) * mix(1, mat.detail, 0.3)[..., None]
	rough = 0.42 + 0.06 * speck
	metal = np.zeros((mat.H, mat.W))
	height = speck * 0.2
	# Hauteur dans la lame (0 tranchant, 1 dos), pour couper les aplats en biais
	hb = (mat.pos - k.c) @ k.height
	hb = (hb - hb[k.blade].min()) / (np.ptp(hb[k.blade]) + 1e-6)
	if np.mean(hb[k.grind]) > 0.5:
		hb = 1 - hb  # le tranchant (poli) doit être du côté 0
	cut = k.g - 0.16 * hb
	red = k.flatm * smooth(0.585, 0.59, cut)
	black = k.flatm * (smooth(0.008, 0.004, np.abs(cut - 0.567)) + smooth(0.006, 0.003, np.abs(cut - 0.535)))
	# Impact et réticule sur chaque face, à mi-lame
	R = 52.0
	ii, jj = np.mgrid[0 : mat.H, 0 : mat.W].astype(np.float32)
	chip = np.zeros((mat.H, mat.W))
	crack = np.zeros((mat.H, mat.W))
	crater = np.zeros((mat.H, mat.W))
	ret = np.zeros((mat.H, mat.W))
	for side, (cy, cx) in enumerate(k.blade_points(mat, -0.8)):
		x = (jj - cx) / R
		y = (ii - cy) / R
		near = (np.abs(x) < 3) & (np.abs(y) < 3)
		c1, c2, c3, c4 = impact_masks(np.where(near, x, 9), np.where(near, y, 9), seed=7 + side, lw=0.075)
		chip, crack, crater, ret = np.maximum(chip, c1), np.maximum(crack, c2), np.maximum(crater, c3), np.maximum(ret, c4)
	on = k.flatm
	chip, crack, crater, ret = chip * on, crack * on, crater * on, ret * on
	black = np.clip(black + ret * (1 - chip), 0, 1)
	col = mix(col, IMP_RED * mix(1, mat.detail, 0.2)[..., None], red)
	col = mix(col, IMP_BLACK, black)
	rough = mix(rough, 0.34, red)
	rough = mix(rough, 0.45, black)
	col = mix(col, col * 0.3, crack * (1 - chip))
	height = height - crack * 1.0 + (red + black) * 0.3
	# Écaillage (impact et arêtes) : acier brossé sous la céramique, cratère sombre
	bare = np.clip(np.maximum(chip, chips * k.blade), 0, 1)
	steel = STEEL * mix(1, mat.detail, 0.5)[..., None]
	col = mix(col, steel, bare)
	rough = mix(rough, 0.2, bare)
	metal = mix(metal, 1, bare)
	height = height - bare * 1.2 - crater * 3.0
	col = mix(col, np.array([0.14, 0.13, 0.13]), crater * 0.9)
	rough = mix(rough, 0.5, crater)
	# Tranchant : acier poli
	col = mix(col, STEEL * mix(1, mat.detail, 0.5)[..., None], k.grind)
	rough = mix(rough, 0.12, k.grind)
	metal = mix(metal, 1, k.grind)
	# Garde : acier noirci aux arêtes usées, pommeau rouge laqué ; manche d'origine
	gcol = mix(IMP_BLACK * 1.4 * mix(1, mat.detail, 0.6)[..., None], STEEL * 0.8, mat.edges * 0.6)
	col = mix(col, gcol, k.guard)
	rough = mix(rough, 0.32, k.guard)
	metal = mix(metal, 1, k.guard)
	col = mix(col, mix(IMP_RED * mix(1, mat.detail, 0.4)[..., None], STEEL * 0.8, mat.edges * 0.5), k.pommel)
	rough = mix(rough, 0.3, k.pommel)
	metal = mix(metal, mat.edges * 0.5 > 0.25, k.pommel)
	col = mix(col, mat.color, k.grip)
	rough = mix(rough, mat.rough, k.grip)
	metal = mix(metal, mat.metal, k.grip)
	col = col * mix(1, mat.ao, 0.5)[..., None]
	return col, rough, metal, add_relief(mat.normal, height * k.blade, 0.9, mat.cov)


# Cette méthode permet de dessiner la livrée « Impact » de profil sur une toile (u le long de l'arme, 0 = bouche du
# canon ; v de haut en bas de la boîte de l'arme), texte lisible du côté voulu ; renvoie les masques rouge et noir.
def impact_livery(w, h, flip_text):
	sc = 3
	W, H = w * sc, h * sc
	red = Image.new("L", (W, H), 0)
	blk = Image.new("L", (W, H), 0)
	dr, db = ImageDraw.Draw(red), ImageDraw.Draw(blk)

	def P(u, v):
		return (int(u * W), int(v * H))

	# Talon de crosse rouge, coupé en biais, liseré noir parallèle et filet rouge
	dr.polygon([P(0.795, 0.30), P(1.01, 0.30), P(1.01, 1.01), P(0.855, 1.01)], fill=255)
	db.polygon([P(0.776, 0.30), P(0.786, 0.30), P(0.846, 1.01), P(0.836, 1.01)], fill=255)
	dr.polygon([P(0.758, 0.30), P(0.764, 0.30), P(0.824, 1.01), P(0.818, 1.01)], fill=255)
	# Ligne de mire : filet rouge le long de la crosse, flèche vers la bouche du canon, filet noir dessous
	# Bande plate de la crosse entre u 0,40 et 0,65 : v de 0,48 à 0,66 (silhouette mesurée sur la cuisson)
	yl = 0.535
	dr.rectangle([P(0.36, yl - 0.009), P(0.755, yl + 0.009)], fill=255)
	dr.polygon([P(0.33, yl), P(0.36, yl - 0.03), P(0.36, yl + 0.03)], fill=255)
	db.rectangle([P(0.42, 0.637), P(0.64, 0.643)], fill=255)
	try:
		font = ImageFont.truetype("arialbd.ttf", int(0.075 * H))
		small = ImageFont.truetype("arialbd.ttf", int(0.03 * H))
	except OSError:
		font = small = ImageFont.load_default()
	txt = Image.new("L", (W, H), 0)
	td = ImageDraw.Draw(txt)
	td.text(P(0.44, 0.553), "IMPACT", fill=255, font=font)
	td.text(P(0.44, 0.493), "LIGNE DE MIRE  /  N° 001", fill=255, font=small)
	if flip_text:
		# La toile est vue en miroir de ce côté : on retourne le texte autour de son propre centre pour qu'il se lise
		bbox = txt.getbbox()
		if bbox:
			crop = txt.crop(bbox).transpose(Image.FLIP_LEFT_RIGHT)
			txt = Image.new("L", (W, H), 0)
			txt.paste(crop, bbox[:2])
	blk = Image.fromarray(np.maximum(np.asarray(blk), np.asarray(txt)))
	out = []
	for im in (red, blk):
		out.append(np.asarray(im.resize((w, h), Image.LANCZOS), dtype=np.float32) / 255)
	return out


# Cette méthode permet d'échantillonner une toile de profil sur les texels d'un matériau de l'AWP (projection selon
# x et z, toile miroir pour la face +y), avec un poids qui s'éteint sur les faces du dessus et du dessous.
def sample_side(mat, canvas_left, canvas_right):
	ch, cw = canvas_left.shape
	u = (mat.pos[..., 0] - mat.bmin[0]) / (mat.bmax[0] - mat.bmin[0])
	v = 1 - (mat.pos[..., 2] - mat.bmin[2]) / (mat.bmax[2] - mat.bmin[2])
	x = np.clip((u * (cw - 1)).astype(int), 0, cw - 1)
	y = np.clip((v * (ch - 1)).astype(int), 0, ch - 1)
	left = mat.nrm[..., 1] < 0
	val = np.where(left, canvas_left[y, x], canvas_right[y, cw - 1 - x])
	weight = smooth(0.15, 0.4, np.abs(mat.nrm[..., 1]))
	return val * weight


# Cette méthode permet de produire les cartes « Impact » d'un matériau de l'AWP : crosse céramique os à aplats rouge et
# noir et impact écaillé sur le bois, métal nitruré noir, culasse, détente et bague de lunette rouges anodisées.
def impact_awp(mat, livery):
	speck, chips = ceramic(mat, 0.35, 0.42)
	if mat.name == "WOOD":
		col = np.broadcast_to(IMP_BONE, (mat.H, mat.W, 3)) * (1 + 0.04 * speck[..., None]) * mix(1, mat.detail, 0.15)[..., None]
		rough = 0.42 + 0.06 * speck
		metal = np.zeros((mat.H, mat.W))
		red = sample_side(mat, *livery["red"])
		blk = sample_side(mat, *livery["black"])
		# Le talon rouge fait le tour de la crosse (dessus et dessous compris)
		u = (mat.pos[..., 0] - mat.bmin[0]) / (mat.bmax[0] - mat.bmin[0])
		v = 1 - (mat.pos[..., 2] - mat.bmin[2]) / (mat.bmax[2] - mat.bmin[2])
		wrap = smooth(0.0005, 0.0015, u - (0.795 + (v - 0.30) * 0.0845))
		red = np.maximum(red, wrap * (np.abs(mat.nrm[..., 1]) < 0.4))
		col = mix(col, IMP_RED, red)
		col = mix(col, IMP_BLACK, blk)
		rough = mix(rough, 0.36, red)
		height = speck * 0.5 + (red + blk) * 0.3
		# Impact au bord du talon rouge (côtés gauche et droit), dans le plan x, z
		cxw = mat.bmin[0] + 0.80 * (mat.bmax[0] - mat.bmin[0])
		R = 0.2
		x = (mat.pos[..., 0] - cxw) / R
		y = (mat.pos[..., 2] - (-0.42)) / R
		chip, crack, crater, ret = impact_masks(x, y, seed=11)
		w = smooth(0.15, 0.4, np.abs(mat.nrm[..., 1]))
		chip, crack, crater, ret = chip * w, crack * w, crater * w, ret * w
		col = mix(col, IMP_BLACK, ret * (1 - chip))
		col = mix(col, col * 0.3, crack * (1 - chip))
		height = height - crack * 1.0
		# Sous la céramique : le bois d'origine (écaillage aux arêtes et autour de l'impact)
		bare = np.clip(np.maximum(chip, chips), 0, 1)
		col = mix(col, mat.color * 1.1, bare)
		rough = mix(rough, mat.rough, bare)
		height = height - bare * 1.2 - crater * 3.0
		col = mix(col, np.array([0.10, 0.07, 0.05]), crater * 0.9)
	else:
		col = IMP_BLACK * 1.6 * mix(1, mat.detail, 0.6)[..., None]
		rough = 0.34 + 0.04 * speck
		metal = np.ones((mat.H, mat.W))
		col = mix(col, STEEL * 0.85, chips * 0.8)
		rough = mix(rough, 0.2, chips)
		height = speck * 0.2
		accent = np.zeros((mat.H, mat.W), bool)
		for name in ("Bolt", "Trigger"):
			accent |= mat.obj(name)
		if mat.name == "SCOPE":
			# Bague rouge à l'avant de la lunette (côté bouche du canon)
			sx = mat.pos[..., 0]
			lo = mat.pos[mat.cov][:, 0].min()
			accent |= mat.cov & (sx > lo + 0.12) & (sx < lo + 0.3)
		acol = IMP_RED * mix(1, mat.detail, 0.4)[..., None]
		col = mix(col, mix(acol, STEEL, chips * 0.7), accent)
		rough = mix(rough, 0.22, accent)
	col = col * mix(1, mat.ao, 0.5)[..., None]
	return col, rough, metal, add_relief(mat.normal, height, 0.9, mat.cov)


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
	wdt = width_px * np.where(major, 1.9, 1.0)
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
	return col, rough, metal, add_relief(mat.normal, height, 0.7, mat.cov)


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
	return col, rough, metal, add_relief(mat.normal, height, 0.7, mat.cov)


# Cette méthode permet de donner la hauteur dans la lame de la M9 (0 au tranchant, 1 au dos) lorsqu'un motif suit le
# profil de la lame.
def blade_height(mat, k):
	hb = (mat.pos - k.c) @ k.height
	hb = (hb - hb[k.blade].min()) / (np.ptp(hb[k.blade]) + 1e-6)
	if np.mean(hb[k.grind]) > 0.5:
		hb = 1 - hb
	return hb


# Cette méthode permet de donner la position de profil de l'AWP (u le long de l'arme, 0 = bouche du canon ; v de haut
# en bas de la boîte de l'arme), le repère des livrées.
def awp_uv(mat):
	u = (mat.pos[..., 0] - mat.bmin[0]) / (mat.bmax[0] - mat.bmin[0])
	v = 1 - (mat.pos[..., 2] - mat.bmin[2]) / (mat.bmax[2] - mat.bmin[2])
	return u, v


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
	return col, rough, metal, add_relief(mat.normal, height, 0.6, mat.cov)


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
	return col, rough, metal, add_relief(mat.normal, height, 0.6, mat.cov)


# ---------------------------------------------------------------------------------------------------------------------
# Skin « Strate » : mokume (acier, cuivre, shakudō sombre, laiton), couches ondulées comme les strates du canyon ; crosse
# en bois lamellé aux couleurs du grès

MOKUME = [
	(0.00, (176, 176, 172)),
	(0.17, (168, 168, 164)),
	(0.21, (178, 92, 56)),
	(0.39, (156, 76, 46)),
	(0.43, (40, 34, 33)),
	(0.60, (50, 40, 37)),
	(0.64, (200, 156, 78)),
	(0.83, (182, 138, 64)),
	(0.87, (176, 176, 172)),
	(1.00, (176, 176, 172)),
]
MOK_ROUGH = [(0.0, 0.14), (0.21, 0.14), (0.23, 0.2), (0.45, 0.2), (0.47, 0.34), (0.60, 0.34), (0.62, 0.18), (0.85, 0.18), (0.87, 0.14), (1.0, 0.14)]
GRES = [
	(0.00, (178, 128, 80)),
	(0.08, (170, 120, 74)),
	(0.12, (158, 66, 32)),
	(0.40, (140, 56, 26)),
	(0.44, (74, 36, 18)),
	(0.60, (66, 32, 16)),
	(0.64, (186, 112, 40)),
	(0.86, (172, 102, 36)),
	(0.90, (178, 128, 80)),
	(1.00, (178, 128, 80)),
]


# Cette méthode permet de calculer les couches (coordonnée de strate, 1 période = 1 cycle des quatre métaux) : un axe de
# strate, ondulé par un bruit déformé et percé de « gouttes » (anneaux concentriques du mokume martelé).
def strata(mat, direction, period, freq, amp, seed=101, drops=0.0):
	direction = np.asarray(direction, dtype=np.float32)
	direction = direction / np.linalg.norm(direction)

	def layer(p):
		q = p * freq
		w = np.stack([fbm(q + 2.2, 3, seed), fbm(q + 6.6, 3, seed + 4), fbm(q + 9.9, 3, seed + 8)], 1)
		warp = fbm(q + w * 1.2, 4, seed + 12) * amp
		d = (p @ direction) / period + warp
		if drops:
			bump = fbm(p * freq * 4.5, 2, seed + 20)
			d = d + drops * np.clip(bump, 0, None) ** 1.5 * 6
		return d

	return mat.field(layer)


# Cette méthode permet de colorer et de régler la rugosité des couches : rampe nette, relief en marches (les métaux
# tendres sont plus creusés par l'attaque à l'acide).
def strata_maps(mat, d, stops, rough_stops, detail=0.3):
	f = d - np.floor(d)
	col = ramp(f, stops) * mix(1, mat.detail, detail)[..., None]
	rough = np.interp(f, [s[0] for s in rough_stops], [s[1] for s in rough_stops])
	height = -smooth(0.2, 0.24, f) * smooth(0.62, 0.6, f) * 0.8
	return col, rough, height


# Cette méthode permet de produire les cartes « Strate » de la M9 : lame en mokume (couches le long du dos, ondulées),
# tranchant en acier poli, garde et pommeau en laiton, manche d'origine.
def strate_m9(mat, k):
	direction = k.height * 1.0 + k.axis * 0.35
	d = strata(mat, direction, 0.034, 1.6, 2.2, drops=0.45)
	col, rough, height = strata_maps(mat, d, MOKUME, MOK_ROUGH)
	metal = np.ones((mat.H, mat.W))
	col = mix(col, STEEL * mix(1, mat.detail, 0.5)[..., None], k.grind)
	rough = mix(rough, 0.1, k.grind)
	height = height * (k.blade & ~k.grind)
	hw = k.guard | k.pommel
	col = mix(col, np.array([214, 168, 86]) / 255 * mix(1, mat.detail, 0.5)[..., None], hw)
	rough = mix(rough, 0.18, hw)
	col = mix(col, mat.color, k.grip)
	rough = mix(rough, mat.rough, k.grip)
	metal = mix(metal, mat.metal, k.grip)
	col = col * mix(1, mat.ao, 0.5)[..., None]
	return col, rough, metal, add_relief(mat.normal, height, 0.8, mat.cov)


# Cette méthode permet de produire les cartes « Strate » d'un matériau de l'AWP : carcasse et canon en mokume (strates
# horizontales), lunette en shakudō sombre à bagues de laiton, crosse en bois lamellé couleur grès.
def strate_awp(mat):
	if mat.name == "WOOD":
		d = strata(mat, (0.12, 0, 1), 0.1, 0.5, 1.4, seed=131)
		# Bois d'origine (grain, rugosité) teinté couche par couche : des couleurs posées à plat viraient au pastel
		# sous le voile du vernis
		col, _, height = strata_maps(mat, d, GRES, MOK_ROUGH, 0.0)
		col = col * np.clip(mat.lum / mat.lum[mat.cov].mean(), 0.5, 1.5)[..., None] * 0.9
		rough = mat.rough * 0.9
		metal = np.zeros((mat.H, mat.W))
		height = height * 0.5
	elif mat.name == "SCOPE":
		u, _ = awp_uv(mat)
		dark = np.array([46, 40, 38]) / 255 * mix(1, mat.detail, 0.5)[..., None]
		col = mix(dark, STEEL * 0.7, mat.edges * 0.35)
		rough = np.full((mat.H, mat.W), 0.3)
		metal = np.ones((mat.H, mat.W))
		rings = mat.cov & (((u > 0.335) & (u < 0.37)) | ((u > 0.64) & (u < 0.68)) | (mat.pos[..., 2] > mat.bmin[2] + 0.93 * (mat.bmax[2] - mat.bmin[2])))
		col = mix(col, np.array([214, 168, 86]) / 255 * mix(1, mat.detail, 0.5)[..., None], rings)
		rough = mix(rough, 0.18, rings)
		height = np.zeros((mat.H, mat.W))
	else:
		d = strata(mat, (0.1, 0, 1), 0.03, 0.6, 2.0, seed=101, drops=0.4)
		col, rough, height = strata_maps(mat, d, MOKUME, MOK_ROUGH)
		metal = np.ones((mat.H, mat.W))
		trig = mat.obj("Trigger") | mat.obj("Bolt")
		col = mix(col, np.array([214, 168, 86]) / 255 * mix(1, mat.detail, 0.5)[..., None], trig)
		rough = mix(rough, 0.18, trig)
	col = col * mix(1, mat.ao, 0.5)[..., None]
	return col, rough, metal, add_relief(mat.normal, height, 0.8, mat.cov)


# ---------------------------------------------------------------------------------------------------------------------
# Skin « Sillage » : nacre blanche, traînées de vitesse noires qui balaient l'arme de la crosse vers la bouche (le
# sillage d'un surfeur), filet ambre, marquages techniques

PEARL = np.array([238, 235, 230]) / 255
INK = np.array([20, 20, 23]) / 255


# Cette méthode permet de calculer la nacre : blanc cassé dont la teinte dérive doucement vers le rose et le bleu
# (irisation peinte), et un grain très fin de laque.
def pearl(mat, freq):
	a = smooth(0.0, 0.45, mat.field(lambda p: fbm(p * freq, 3, 151)))
	b = smooth(0.0, 0.45, mat.field(lambda p: fbm(p * freq * 1.3 + 5, 3, 157)))
	rose, ciel = np.array([1.0, 0.94, 0.975]), np.array([0.94, 0.975, 1.0])
	tint = mix(mix(np.ones(3), rose, a), ciel, b * (1 - a * 0.5))
	speck = mat.field(lambda p: fbm(p * freq * 50, 2, 163))
	return PEARL * tint * (1 + 0.015 * speck[..., None]), speck


# Cette méthode permet de donner, pour une position u le long de l'AWP, la hauteur v du bord de l'aplat noir « Sillage ».
def sillage_curve(u):
	# Bord de l'aplat noir : bas du fût à l'avant, remonte en arc jusqu'à mi-hauteur du talon de crosse
	q = np.clip((u - 0.58) / 0.42, 0, 1)
	return 0.63 - 0.1 * q**1.3 - 0.03 * np.clip((0.58 - u) / 0.58, 0, 1)


# Cette méthode permet de dessiner la livrée « Sillage » de profil (u, v en 0..1, cf. awp_uv) : aplat noir sous la courbe
# de la crosse, traînées parallèles qui s'affinent vers la bouche du canon, filet ambre ; renvoie les masques noir et ambre.
def sillage_livery(u, v):
	f = v - sillage_curve(u)  # > 0 sous la courbe
	black = smooth(-0.002, 0.002, f) * smooth(0.6, 0.63, u)
	px = 1.0 / 2048
	ink = black
	amber = np.zeros_like(u)
	for i, (off, w0) in enumerate(((0.026, 0.011), (0.05, 0.006), (0.068, 0.004), (0.1, 0.005))):
		# Chaque traînée s'affine et s'arrête plus tôt vers l'avant (sillage qui se dissipe)
		stop = 0.12 + 0.06 * i
		w = w0 * smooth(stop, stop + 0.25, u)
		line = smooth(w + px, w - px, np.abs(f + off)) * (u > stop)
		if i == 1:
			amber = np.maximum(amber, line)
		else:
			ink = np.maximum(ink, line)
	return np.clip(ink, 0, 1), np.clip(amber, 0, 1)


# Cette méthode permet de dessiner les marquages de la livrée « Sillage » (nom, numéro, graduations) sur une toile de
# profil, lisibles du côté voulu ; renvoie un masque (h, w).
def sillage_marks(w, h, flip_text):
	sc = 3
	W, H = w * sc, h * sc
	txt = Image.new("L", (W, H), 0)
	td = ImageDraw.Draw(txt)
	try:
		font = ImageFont.truetype("arialbd.ttf", int(0.085 * H))
		small = ImageFont.truetype("arialbd.ttf", int(0.03 * H))
	except OSError:
		font = small = ImageFont.load_default()

	def P(u, v):
		return (int(u * W), int(v * H))

	# Fût (bande plate entre u 0,18 et 0,38, v 0,45 à 0,58) : nom et numéro ; graduations le long de la traînée
	td.text(P(0.19, 0.448), "SILLAGE", fill=255, font=font)
	td.text(P(0.19, 0.548), "LIGNE DE MIRE  //  N° 002", fill=255, font=small)
	for i in range(16):
		x = 0.19 + i * 0.0105
		td.rectangle([P(x, 0.43), P(x + 0.0016, 0.43 + (0.016 if i % 5 == 0 else 0.008))], fill=255)
	# Repère de visée sur la crosse : chevrons « >> » au-dessus de la traînée
	for i in range(3):
		x0 = 0.8 + i * 0.022
		td.polygon([P(x0, 0.47), P(x0 + 0.012, 0.495), P(x0, 0.52), P(x0 + 0.006, 0.52), P(x0 + 0.018, 0.495), P(x0 + 0.006, 0.47)], fill=255)
	if flip_text:
		bbox = txt.getbbox()
		if bbox:
			crop = txt.crop(bbox).transpose(Image.FLIP_LEFT_RIGHT)
			txt = Image.new("L", (W, H), 0)
			txt.paste(crop, bbox[:2])
	return np.asarray(txt.resize((w, h), Image.LANCZOS), dtype=np.float32) / 255


# Cette méthode permet de produire les cartes « Sillage » de la M9 : lame laquée nacre, aplat noir au talon et traînées
# qui filent vers la pointe, filet ambre, tranchant poli ; garde et pommeau noirs.
def sillage_m9(mat, k):
	col, speck = pearl(mat, 2.5)
	col = col * mix(1, mat.detail, 0.15)[..., None]
	rough = 0.2 + 0.03 * speck
	metal = np.zeros((mat.H, mat.W))
	hb = blade_height(mat, k)
	# Aplat noir en coin au talon, côté tranchant, qui s'effile vers la pointe ; traînées parallèles au-dessus
	q = np.clip((k.g - 0.45) / 0.55, 0, 1)
	base = 0.12 + 0.5 * q**2
	f = base - hb  # > 0 sous la courbe (côté tranchant)
	black = smooth(-0.004, 0.004, f) * smooth(0.5, 0.56, k.g)
	amber = np.zeros((mat.H, mat.W))
	for i, (off, w) in enumerate(((0.08, 0.03), (0.14, 0.016), (0.19, 0.012))):
		stop = 0.06 + 0.07 * i
		ww = w * smooth(stop, stop + 0.3, k.g)
		line = smooth(ww + 0.004, ww - 0.004, np.abs(f + off)) * (k.g > stop)
		if i == 1:
			amber = np.maximum(amber, line)
		else:
			black = np.maximum(black, line)
	# Seul un filet de tranchant reste poli : le grand biseau est laqué comme le plat
	edge = k.grind & (hb < 0.1)
	paint = k.blade & ~edge
	black, amber = black * paint, amber * paint
	col = mix(col, INK, black)
	col = mix(col, AMBER, amber)
	rough = mix(rough, 0.38, black)  # laque noire satinée : brillante, elle passait pour du chrome
	height = (black + amber) * 0.25 + speck * 0.05
	# Laque écaillée aux arêtes vives : acier dessous
	chips = smooth(0.55, 0.62, mat.edges * (0.5 + mat.field(lambda p: fbm(p * 6, 3, 171)) * 0.5 + 0.25))
	col = mix(col, STEEL * mix(1, mat.detail, 0.5)[..., None], chips * k.blade)
	metal = mix(metal, 1, chips * k.blade)
	col = mix(col, STEEL * mix(1, mat.detail, 0.5)[..., None], edge)
	rough = mix(rough, 0.1, edge)
	metal = mix(metal, 1, edge)
	hw = k.guard | k.pommel
	col = mix(col, mix(INK * 1.6, STEEL * 0.7, mat.edges * 0.4) * mix(1, mat.detail, 0.4)[..., None], hw)
	rough = mix(rough, 0.22, hw)
	metal = mix(metal, 1, hw)
	col = mix(col, mat.color, k.grip)
	rough = mix(rough, mat.rough, k.grip)
	metal = mix(metal, mat.metal, k.grip)
	col = col * mix(1, mat.ao, 0.5)[..., None]
	return col, rough, metal, add_relief(mat.normal, height * k.blade, 0.6, mat.cov)


# Cette méthode permet de produire les cartes « Sillage » d'un matériau de l'AWP : laque nacre sur toute l'arme, livrée
# de profil (aplat noir de crosse, traînées, filet ambre, marquages), culasse, détente et chargeur noirs, bagues noires.
def sillage_awp(mat, marks):
	col, speck = pearl(mat, 0.8)
	col = col * mix(1, mat.detail, 0.12)[..., None]
	rough = 0.2 + 0.03 * speck
	metal = np.zeros((mat.H, mat.W))
	u, v = awp_uv(mat)
	side = smooth(0.15, 0.4, np.abs(mat.nrm[..., 1]))
	ink, amber = sillage_livery(u, v)
	# L'aplat noir fait le tour de la crosse ; les traînées et marquages restent sur les flancs
	full = smooth(-0.002, 0.002, v - sillage_curve(u)) * smooth(0.6, 0.63, u)
	ink = np.maximum(ink * side, full * (mat.name == "WOOD"))
	amber = amber * side
	ink = np.maximum(ink, sample_side(mat, *marks) * (mat.name == "WOOD"))
	parts = np.zeros((mat.H, mat.W), bool)
	for name in ("Bolt", "Trigger", "Magazine", "Fittings"):
		parts |= mat.obj(name)
	parts |= mat.cov & (u < 0.025)  # bouche du canon
	if mat.name == "SCOPE":
		parts |= mat.cov & (((u > 0.335) & (u < 0.37)) | ((u > 0.64) & (u < 0.68)) | (mat.pos[..., 2] > mat.bmin[2] + 0.93 * (mat.bmax[2] - mat.bmin[2])))
	ink = np.maximum(ink, parts)
	col = mix(col, INK * mix(1, mat.detail, 0.3)[..., None], ink)
	col = mix(col, AMBER, amber * (1 - ink))
	rough = mix(rough, 0.26, ink)
	height = (ink + amber) * 0.2 + speck * 0.05
	chips = smooth(0.55, 0.62, mat.edges * (0.5 + mat.field(lambda p: fbm(p * 2, 3, 171)) * 0.5 + 0.25))
	if mat.name != "WOOD":
		col = mix(col, STEEL * 0.8 * mix(1, mat.detail, 0.5)[..., None], chips)
		metal = mix(metal, 1, chips)
		metal = mix(metal, 0.6, parts)
	col = col * mix(1, mat.ao, 0.5)[..., None]
	return col, rough, metal, add_relief(mat.normal, height, 0.6, mat.cov)


# ---------------------------------------------------------------------------------------------------------------------


# Cette méthode permet de fabriquer tous les matériaux d'un skin pour les deux armes et de les écrire.
def build(skin, bake, m9_orig, out):
	m9 = Mat("m9", "Handle", os.path.join(bake, "m9"), {k: os.path.join(m9_orig, f"m9_Handle_{k}.png") for k in ("Color", "Rough", "Metal", "Normal")})
	k = Knife(m9)
	m9_fns = {"couchant": couchant_m9, "impact": impact_m9, "releve": releve_m9, "recuit": recuit_m9, "strate": strate_m9, "sillage": sillage_m9}
	write(os.path.join(out, skin, "M9Bayonet"), "Handle", m9, *m9_fns[skin](m9, k))
	print(f"[skins] {skin} M9Bayonet")
	cw, ch = 2048, 375  # proportions de la boîte de l'AWP vue de profil (x, z)
	livery = marks = None
	if skin == "impact":
		left, right = impact_livery(cw, ch, False), impact_livery(cw, ch, True)
		livery = {"red": (left[0], np.fliplr(right[0])), "black": (left[1], np.fliplr(right[1]))}
	if skin == "sillage":
		marks = (sillage_marks(cw, ch, False), np.fliplr(sillage_marks(cw, ch, True)))
	awp_fns = {
		"couchant": couchant_awp,
		"impact": lambda m: impact_awp(m, livery),
		"releve": releve_awp,
		"recuit": recuit_awp,
		"strate": strate_awp,
		"sillage": lambda m: sillage_awp(m, marks),
	}
	for name in AWP_MATS:
		mat = Mat("awp", name + "_PBR", os.path.join(bake, "awp"), {k2: os.path.join(AWP_TEX, f"{name}_{k2}.png") for k2 in ("Color", "Rough", "Metal", "Normal")})
		mat.name = name
		maps = awp_fns[skin](mat)
		write(os.path.join(out, skin, "AWP"), name, mat, *maps)
		print(f"[skins] {skin} AWP {name}")


if __name__ == "__main__":
	bake, m9_orig, out = sys.argv[1:4]
	skins = sys.argv[4:] or ["couchant", "impact", "releve", "recuit", "strate", "sillage"]
	for s in skins:
		build(s, bake, m9_orig, out)
