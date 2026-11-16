"""Outils communs des skins dessinés de l'AWP (#417).

Un skin part des cartes d'origine (make_textures.py : granité, moletage, vis, crasse) et les repeint pièce par pièce.
Le dessin des flancs se fait sur une toile de profil en coordonnées de la photo (px, py, cf. build_awp.py), tracée avec
PIL puis échantillonnée sur chaque texel par sa position (x, z) : les panneaux suivent la silhouette de l'arme quel que
soit le dépliage UV. Le texte a une toile par flanc, retournée sur le flanc droit pour rester lisible.
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import make_textures as mt  # noqa: E402

X, Z, fbm, wear, grime = mt.X, mt.Z, mt.fbm, mt.wear, mt.grime
PAINTERS = (("WOOD", mt.wood), ("METAL_A", mt.metal_a), ("METAL_B", mt.metal_b), ("SCOPE", mt.scope))
PX0, PX1, PY0, PY1 = 450, 3800, 120, 780  # étendue de la toile en pixels de la photo (canon, crosse, lunette, pontet)
SS = 2  # suréchantillonnage de la toile (pixels de toile par pixel de photo : ~700 par unité, bords nets)
FONT_DIR = "C:/Windows/Fonts"  # génération hors CI, sur le poste Windows


def font(name, size, variation=None):
	"""Cette méthode permet de charger une police système à une taille en pixels de toile (variation : « Bold Condensed »…)."""
	f = ImageFont.truetype(os.path.join(FONT_DIR, name), size)
	if variation:
		f.set_variation_by_name(variation)
	return f


class Canvas:
	"""Cette classe permet de dessiner des masques de profil (0 à 1) en coordonnées de la photo et de les lire sur les texels."""

	def __init__(self):
		self.w, self.h = (PX1 - PX0) * SS, (PY1 - PY0) * SS
		self.layers = {}

	def layer(self, name):
		"""Cette méthode permet d'obtenir (en la créant vide) la couche nommée, une paire (flanc gauche, flanc droit)."""
		if name not in self.layers:
			self.layers[name] = (Image.new("L", (self.w, self.h), 0), Image.new("L", (self.w, self.h), 0))
		return self.layers[name]

	def xy(self, pts):
		"""Cette méthode permet de convertir des points de la photo (px, py) en pixels de toile."""
		return [((px - PX0) * SS, (py - PY0) * SS) for px, py in pts]

	def poly(self, name, pts, value=255, width=0):
		"""Cette méthode permet de remplir (ou de tracer, width > 0 en px photo) un polygone sur les deux flancs."""
		for img in self.layer(name):
			d = ImageDraw.Draw(img)
			if width:
				d.line(self.xy(list(pts) + [pts[0]]), fill=value, width=int(width * SS), joint="curve")
			else:
				d.polygon(self.xy(pts), fill=value)

	def line(self, name, pts, width, value=255):
		"""Cette méthode permet de tracer une ligne brisée d'épaisseur width (px photo) sur les deux flancs."""
		for img in self.layer(name):
			ImageDraw.Draw(img).line(self.xy(pts), fill=value, width=int(width * SS), joint="curve")

	def circle(self, name, c, r, value=255, width=0):
		"""Cette méthode permet de remplir (ou de cercler, width > 0) un disque de centre c et de rayon r en px photo."""
		(cx, cy), = self.xy([c])
		box = (cx - r * SS, cy - r * SS, cx + r * SS, cy + r * SS)
		for img in self.layer(name):
			d = ImageDraw.Draw(img)
			if width:
				d.ellipse(box, outline=value, width=int(width * SS))
			else:
				d.ellipse(box, fill=value)

	def text(self, name, s, c, height, fnt, angle=0.0, value=255, anchor="mm", stroke=0):
		"""Cette méthode permet d'écrire un texte lisible sur chaque flanc, centré en c (px photo), de hauteur de capitale height.
		Sur le flanc droit (vu depuis +Y, l'arme retournée), le tampon est retourné en miroir autour de son centre.
		stroke > 0 (px photo) : le texte est épaissi d'un contour (pour une couche de contour sous le texte)."""
		f = fnt(int(height * SS * 1.38))
		sw = int(stroke * SS)
		bb = f.getbbox(s, anchor="ls", stroke_width=sw)
		tw, th = bb[2] - bb[0] + 8, bb[3] - bb[1] + 8
		stamp = Image.new("L", (tw, th), 0)
		ImageDraw.Draw(stamp).text((4 - bb[0], 4 - bb[1]), s, font=f, fill=value, anchor="ls", stroke_width=sw, stroke_fill=value)
		(cx, cy), = self.xy([c])
		for side, img in enumerate(self.layer(name)):
			st = stamp.transpose(Image.FLIP_LEFT_RIGHT) if side else stamp
			st = st.rotate(-angle if side else angle, resample=Image.BICUBIC, expand=True)
			ox = int(cx - st.width / 2) if anchor == "mm" else int(cx - (st.width if side else 0))
			img.paste(255 if value else 0, (ox, int(cy - st.height / 2)), st)

	def stripes(self, name, pts, period, ratio=0.5, angle=45.0):
		"""Cette méthode permet de remplir un polygone de bandes obliques (balisage), période en px photo."""
		mask = Image.new("L", (self.w, self.h), 0)
		ImageDraw.Draw(mask).polygon(self.xy(pts), fill=255)
		yy, xx = np.mgrid[0 : self.h, 0 : self.w]
		a = np.radians(angle)
		t = ((xx * np.cos(a) + yy * np.sin(a)) / (period * SS)) % 1.0
		band = Image.fromarray(((t < ratio) * 255).astype(np.uint8))
		for img in self.layer(name):
			img.paste(255, (0, 0), Image.fromarray(np.minimum(np.array(mask), np.array(band))))

	def clip(self, name, keep):
		"""Cette méthode permet d'effacer une couche hors d'une zone (tableau booléen à la taille de la toile)."""
		k = Image.fromarray((~keep * 255).astype(np.uint8))
		for img in self.layer(name):
			img.paste(0, (0, 0), k)

	def sample(self, name, m, blur=0.6):
		"""Cette méthode permet de lire une couche (0 à 1) sur les texels d'un matériau : flanc gauche si la normale regarde
		-Y ou de côté, flanc droit si elle regarde nettement +Y."""
		left, right = (np.asarray(i, np.float64) / 255 for i in self.layer(name))
		if blur:
			left, right = ndimage.gaussian_filter(left, blur * SS), ndimage.gaussian_filter(right, blur * SS)
		px = mt_px(m.p[:, 0])
		py = mt_py(m.p[:, 2])
		u = (px - PX0) * SS
		v = (py - PY0) * SS
		a = ndimage.map_coordinates(left, [v, u], order=1, mode="constant")
		b = ndimage.map_coordinates(right, [v, u], order=1, mode="constant")
		return np.where(m.n[:, 1] > 0.35, b, a)

	def sample_at(self, name, x, z, right, blur=0.0):
		"""Cette méthode permet de lire une couche (0 à 1) en des points (x, z) du modèle donnés, sur le flanc droit là où
		right est vrai (couleur d'une écaille lue en son centre, par exemple)."""
		left, rgt = (np.asarray(i, np.float64) / 255 for i in self.layer(name))
		if blur:
			left, rgt = ndimage.gaussian_filter(left, blur * SS), ndimage.gaussian_filter(rgt, blur * SS)
		u, v = (mt_px(x) - PX0) * SS, (mt_py(z) - PY0) * SS
		a = ndimage.map_coordinates(left, [v, u], order=1, mode="constant")
		b = ndimage.map_coordinates(rgt, [v, u], order=1, mode="constant")
		return np.where(right, b, a)

	def preview(self, path):
		"""Cette méthode permet d'écrire les couches du flanc gauche superposées en couleurs, pour régler le dessin."""
		rgb = np.zeros((self.h, self.w, 3))
		for i, (left, _) in enumerate(self.layers.values()):
			col = np.array([(i * 0.37) % 1, (i * 0.61 + 0.3) % 1, (i * 0.83 + 0.6) % 1])
			a = np.asarray(left, np.float64)[..., None] / 255
			rgb = rgb * (1 - a) + col * a
		Image.fromarray((rgb * 255).astype(np.uint8)).resize((self.w // SS, self.h // SS)).save(path)


def outline(name):
	"""Cette méthode permet de relire un contour de build_awp.py (STOCK, HANDGUARD, THUMBHOLE…) en points de la photo,
	sans importer bpy : les appels P(px, py, r) et les couples (px, py) de son affectation sont lus dans le source."""
	import ast

	src = open(os.path.join(os.path.dirname(mt.__file__), "build_awp.py"), encoding="utf-8").read()
	for node in ast.parse(src).body:
		if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", None) == name:
			pts = []
			for e in node.value.elts:
				args = e.args if isinstance(e, ast.Call) else e.elts
				pts.append((ast.literal_eval(args[0]), ast.literal_eval(args[1])))
			return pts
	raise KeyError(name)


def band(cv, name, outer, holes, d0, d1, value=255):
	"""Cette méthode permet de tracer un filet intérieur qui suit un contour (et le tour de ses trous) entre les
	distances d0 et d1 du bord, en px photo ; renvoie aussi la distance au bord (px photo) pour limiter un motif."""
	mask = Image.new("L", (cv.w, cv.h), 0)
	d = ImageDraw.Draw(mask)
	d.polygon(cv.xy(outer), fill=255)
	for h in holes:
		d.polygon(cv.xy(h), fill=0)
	dist = ndimage.distance_transform_edt(np.asarray(mask) > 0) / SS
	sel = Image.fromarray((((dist > 0) & (dist >= d0) & (dist < d1)) * value).astype(np.uint8))  # jamais hors du contour
	for img in cv.layer(name):
		img.paste(value, (0, 0), sel)
	return dist


def halftone(cv, name, keep, spacing, r0, r1, y0, y1, angle=45.0):
	"""Cette méthode permet de poser une trame de points (style BD) dans une zone, rayon des points passant de r0 en
	py = y0 à r1 en py = y1 (px photo), grille tournée de angle degrés."""
	yy, xx = np.mgrid[0 : cv.h, 0 : cv.w].astype(np.float32) / SS
	a = np.radians(angle)
	u = (xx * np.cos(a) + yy * np.sin(a)) / spacing
	v = (-xx * np.sin(a) + yy * np.cos(a)) / spacing
	d = np.hypot(u - np.round(u), v - np.round(v)) * spacing
	t = np.clip((yy + PY0 - y0) / (y1 - y0), 0, 1)
	dots = (d < r0 + (r1 - r0) * t) & keep
	sel = Image.fromarray((dots * 255).astype(np.uint8))
	for img in cv.layer(name):
		img.paste(255, (0, 0), sel)


def zone(cv, outer, holes=()):
	"""Cette méthode permet d'obtenir la distance au bord (px photo, 0 dehors) d'un contour moins ses trous, sans rien tracer."""
	mask = Image.new("L", (cv.w, cv.h), 0)
	d = ImageDraw.Draw(mask)
	d.polygon(cv.xy(outer), fill=255)
	for h in holes:
		d.polygon(cv.xy(h), fill=0)
	return ndimage.distance_transform_edt(np.asarray(mask) > 0) / SS


def mt_px(x):
	"""Cette méthode permet de convertir une abscisse du modèle en pixel de la photo de profil (inverse de X)."""
	return 2940 + (x - 1.42) / mt.PX_S


def mt_py(z):
	"""Cette méthode permet de convertir une hauteur du modèle en ordonnée de la photo de profil (inverse de Z)."""
	return 355 - z / mt.PX_S


def paint(m, a, rgb, rough, metal, sel=None, keep_ao=True):
	"""Cette méthode permet de poser une encre (couleur, rugosité, métal) avec une opacité a (0 à 1) par texel."""
	a = np.broadcast_to(np.clip(np.asarray(a, np.float64), 0, 1), m.rough.shape) * (1.0 if sel is None else sel)
	col = np.asarray(rgb, np.float64)
	col = np.outer(grime(m), col) if keep_ao else np.broadcast_to(col, m.color.shape)
	m.color = m.color * (1 - a[:, None]) + col * a[:, None]
	m.rough = m.rough * (1 - a) + rough * a
	m.metal = m.metal * (1 - a) + metal * a


def chip(m, amount, seed, under, rough=0.4, metal=1.0, sel=None):
	"""Cette méthode permet d'écailler la peinture sur les arêtes (usure de skin) en laissant voir la couche « under »."""
	w = (wear(m, amount, seed) > 0.5).astype(np.float64)
	paint(m, w, under, rough, metal, sel)


def build(bake_dir, out_dir, skin, density=226.0):
	"""Cette méthode permet de peindre un skin (fonction skin(materiaux) qui reçoit les quatre Maps d'origine) et d'écrire ses cartes."""
	os.makedirs(out_dir, exist_ok=True)
	maps = {prefix: painter(bake_dir) for prefix, painter in PAINTERS}
	skin(maps)
	for prefix, m in maps.items():
		m.save(out_dir, prefix, density)
		print(f"[skin] {prefix} : {len(m.p)} texels")
