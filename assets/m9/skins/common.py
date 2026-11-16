"""Outils communs des skins dessinés de la M9 Bayonet (#420).

La M9 vient du Creator Store (pas de source Blender) : ses cartes d'origine et son mesh sortent du jeu
(`tools/preview/fetch_viewmodel.py`) et `tools/skins/bake_maps.py --glb` cuit la position de chaque texel. Un skin
repeint ces cartes d'origine (`m9_Handle_*.png`) zone par zone (lame, biseau, garde, manche, pommeau : `Knife` de
`tools/skins/make_skins.py`).

Le dessin se fait sur une toile de profil dans le repère propre du couteau (t le long de l'axe, pointe à gauche ;
h vers le dos de la lame, en haut), tracée avec PIL puis lue sur chaque texel par sa position : le motif suit la
silhouette quel que soit le dépliage UV, et traverse l'épaisseur à la même place sur les deux faces. Une couche est
une paire (face gauche, face droite) : le texte est retourné sur la face droite pour rester lisible.
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(ROOT, "tools", "skins"))
import make_skins as ms  # noqa: E402

mix, smooth, fbm, add_relief = ms.mix, ms.smooth, ms.fbm, ms.add_relief
T0, T1, H0, H1 = -2.16, 1.63, -0.46, 0.54  # étendue de la toile dans le repère du couteau (unités monde)
S = 640  # pixels de toile par unité (~3 fois la densité de la texture sur la lame : bords nets)
FONT_DIR = "C:/Windows/Fonts"  # génération hors CI, sur le poste Windows
STEEL = ms.STEEL


def font(name, size):
	"""Cette méthode permet de charger une police système à une taille en pixels de toile."""
	return ImageFont.truetype(os.path.join(FONT_DIR, name), size)


def to_px(t, h):
	"""Cette méthode permet de convertir une position du repère du couteau (t, h) en pixels de toile."""
	return (np.asarray(t) - T0) * S, (H1 - np.asarray(h)) * S


class Knife:
	"""La M9 prête à repeindre : cartes d'origine (couleur, rugosité, métal, normale) en cours de peinture, zones de
	`make_skins.Knife`, et pour chaque texel sa place sur la toile de profil et sa face (droite si right)."""

	def __init__(self, bake_dir, orig_dir):
		"""Cette méthode permet de charger la cuisson et les cartes d'origine et de placer chaque texel sur la toile."""
		maps = {k: os.path.join(orig_dir, f"m9_Handle_{k}.png") for k in ("Color", "Rough", "Metal", "Normal")}
		self.m = m = ms.Mat("m9", "Handle", os.path.join(bake_dir, "m9"), maps)
		self.k = k = ms.Knife(m)
		self.t = k.t
		self.h = (m.pos - k.c) @ k.height
		if np.mean(self.h[k.grind]) > np.mean(self.h[k.flatm]):
			k.height = -k.height  # le tranchant (poli) doit être en bas de la toile
			self.h = -self.h
		self.right = (m.nrm @ k.flat) >= 0
		self.u, self.v = to_px(self.t, self.h)
		self.w, self.hpx = int((T1 - T0) * S), int((H1 - H0) * S)
		self.color, self.rough, self.metal = m.color.copy(), m.rough.copy(), m.metal.copy()
		self.height = np.zeros((m.H, m.W), np.float32)
		self.blade, self.grind, self.flat = k.blade, k.grind, k.flatm
		self.guard, self.grip, self.pommel = k.guard, k.grip, k.pommel
		self.layers = {}
		self._silhouette()

	def _silhouette(self):
		"""Cette méthode permet de rastériser la lame vue de profil (texels de la lame projetés, trous comblés) et sa
		distance au bord en unités, pour limiter un motif ou tracer un filet qui suit le contour."""
		sil = np.zeros((self.hpx, self.w), bool)
		sel = self.blade & self.m.cov
		sil[np.clip(self.v[sel].astype(int), 0, self.hpx - 1), np.clip(self.u[sel].astype(int), 0, self.w - 1)] = True
		sil = ndimage.binary_closing(sil, iterations=4)
		self.sil = ndimage.binary_opening(sil, iterations=2)
		self.dist = ndimage.distance_transform_edt(self.sil) / S
		# Plus basse et plus haute ligne de la lame à chaque abscisse : tranchant (bas) et dos (haut) de la toile
		cols = np.where(self.sil.any(0))[0]
		self.x0, self.x1 = cols.min(), cols.max()

	def edges_at(self, t):
		"""Cette méthode permet de donner, à une abscisse t de la lame, la hauteur h du tranchant et celle du dos."""
		x = int(np.clip((t - T0) * S, self.x0, self.x1))
		ys = np.where(self.sil[:, x])[0]
		return H1 - ys.max() / S, H1 - ys.min() / S

	# --- Toile -------------------------------------------------------------------------------------------------------

	def layer(self, name):
		"""Cette méthode permet d'obtenir (en la créant vide) la couche nommée, une paire (face gauche, face droite)."""
		if name not in self.layers:
			self.layers[name] = (Image.new("L", (self.w, self.hpx), 0), Image.new("L", (self.w, self.hpx), 0))
		return self.layers[name]

	def put(self, name, arr):
		"""Cette méthode permet de remplacer une couche par un masque calculé (tableau 0 à 1 à la taille de la toile)."""
		img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
		self.layers[name] = (img, img.copy())

	def xy(self, pts):
		"""Cette méthode permet de convertir une liste de points (t, h) en pixels de toile pour PIL."""
		return [tuple(float(c) for c in to_px(t, h)) for t, h in pts]

	def line(self, name, pts, width, value=255):
		"""Cette méthode permet de tracer une ligne brisée d'épaisseur width (unités) sur les deux faces."""
		for img in self.layer(name):
			ImageDraw.Draw(img).line(self.xy(pts), fill=value, width=max(1, int(round(width * S))), joint="curve")

	def poly(self, name, pts, value=255):
		"""Cette méthode permet de remplir un polygone (points (t, h)) sur les deux faces."""
		for img in self.layer(name):
			ImageDraw.Draw(img).polygon(self.xy(pts), fill=value)

	def disc(self, name, c, r, value=255):
		"""Cette méthode permet de remplir un disque de centre c (t, h) et de rayon r (unités) sur les deux faces."""
		(cx, cy), = self.xy([c])
		for img in self.layer(name):
			ImageDraw.Draw(img).ellipse((cx - r * S, cy - r * S, cx + r * S, cy + r * S), fill=value)

	def text(self, name, s, c, height, fnt, angle=0.0, value=255):
		"""Cette méthode permet d'écrire un texte lisible sur chaque face, centré en c (t, h), de hauteur de capitale
		height (unités) ; sur la face droite (vue de l'autre côté), le tampon est retourné en miroir."""
		f = fnt(int(height * S * 1.38))
		bb = f.getbbox(s, anchor="ls")
		stamp = Image.new("L", (bb[2] - bb[0] + 8, bb[3] - bb[1] + 8), 0)
		ImageDraw.Draw(stamp).text((4 - bb[0], 4 - bb[1]), s, font=f, fill=value, anchor="ls")
		(cx, cy), = self.xy([c])
		for side, img in enumerate(self.layer(name)):
			st = stamp.transpose(Image.FLIP_LEFT_RIGHT) if side else stamp
			st = st.rotate(-angle if side else angle, resample=Image.BICUBIC, expand=True)
			img.paste(value, (int(cx - st.width / 2), int(cy - st.height / 2)), st)

	def grid(self):
		"""Cette méthode permet d'obtenir les coordonnées (t, h) de chaque pixel de toile, pour un motif calculé."""
		yy, xx = np.mgrid[0 : self.hpx, 0 : self.w].astype(np.float32)
		return xx / S + T0, H1 - yy / S

	def sample(self, name, blur=0.5):
		"""Cette méthode permet de lire une couche (0 à 1) sur les texels : face droite si leur normale regarde +flat."""
		left, right = (np.asarray(i, np.float32) / 255 for i in self.layer(name))
		if blur:
			left, right = ndimage.gaussian_filter(left, blur), ndimage.gaussian_filter(right, blur)
		coords = [self.v.ravel(), self.u.ravel()]
		a = ndimage.map_coordinates(left, coords, order=1, mode="constant").reshape(self.v.shape)
		b = ndimage.map_coordinates(right, coords, order=1, mode="constant").reshape(self.v.shape)
		return np.where(self.right, b, a) * self.m.cov

	def sample_array(self, arr, order=1):
		"""Cette méthode permet de lire un tableau de toile (scalaire par pixel) sur les texels, sans distinction de face."""
		coords = [self.v.ravel(), self.u.ravel()]
		return ndimage.map_coordinates(arr, coords, order=order, mode="nearest").reshape(self.v.shape)

	def preview(self, path):
		"""Cette méthode permet d'écrire les couches de la face gauche superposées en couleurs, pour régler le dessin."""
		rgb = np.dstack([self.sil * 0.15] * 3)
		for i, (left, _) in enumerate(self.layers.values()):
			col = np.array([(i * 0.37 + 0.2) % 1, (i * 0.61 + 0.5) % 1, (i * 0.83 + 0.8) % 1])
			a = np.asarray(left, np.float32)[..., None] / 255
			rgb = rgb * (1 - a) + col * a
		Image.fromarray((rgb * 255).astype(np.uint8)).resize((self.w // 2, self.hpx // 2)).save(path)

	# --- Peinture ----------------------------------------------------------------------------------------------------

	def paint(self, a, rgb, rough, metal, detail=0.4, ao=0.5):
		"""Cette méthode permet de poser une encre (couleur, rugosité, métal) avec une opacité a (0 à 1) par texel, en
		gardant une part du détail d'origine (rayures, saleté) et de l'occlusion cuite."""
		a = np.clip(np.broadcast_to(np.asarray(a, np.float32), self.rough.shape), 0, 1)
		col = np.broadcast_to(np.asarray(rgb, np.float32), self.color.shape)
		col = col * mix(1, self.m.detail, detail)[..., None] * mix(1, self.m.ao, ao)[..., None]
		self.color = mix(self.color, col, a)
		self.rough = mix(self.rough, np.broadcast_to(np.asarray(rough, np.float32), self.rough.shape), a)
		self.metal = mix(self.metal, np.broadcast_to(np.asarray(metal, np.float32), self.metal.shape), a)

	def tint_grip(self, rgb, sel=None):
		"""Cette méthode permet de teinter le manche d'origine (noir quadrillé) en gardant son grain par sa luminance."""
		sel = self.grip if sel is None else sel
		lum = self.m.lum / max(float(self.m.lum[self.grip].mean()), 1e-3)
		col = np.asarray(rgb, np.float32) * np.clip(lum, 0.4, 1.8)[..., None]
		self.color = mix(self.color, col, sel)

	def edge(self, rough=0.1):
		"""Cette méthode permet de repolir le fil (bas du biseau) en acier nu, ce qu'un skin peint garde toujours."""
		hb = ms.blade_height(self.m, self.k)
		e = self.grind & (hb < 0.1)
		self.paint(e, STEEL, rough, 1.0, detail=0.5)
		return e

	def save(self, out_dir, relief=0.8):
		"""Cette méthode permet d'écrire les quatre cartes Handle_<Carte>.png du skin dans out_dir."""
		normal = add_relief(self.m, self.height, relief)
		ms.write(out_dir, "Handle", self.m, self.color, self.rough, self.metal, normal)
