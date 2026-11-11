"""Textures PBR du couteau (Color, Rough, Metal, Normal en PNG) peintes par script, puis branchées aux matériaux Blender.

À lancer dans Blender APRÈS build_knife.py (même espace de noms : `exec` des deux fichiers, avec `TEX_DIR` défini).
Tout est peint en coordonnées réelles (pouces) pour que le marquage, les gorges et l'usure tombent au bon endroit.
Les images sont écrites telles quelles (Non-Color) : les valeurs ci-dessous sont celles du PNG final.
Convention des normales : Y vers le haut de la texture (OpenGL) ; à vérifier dans Studio (sens du relief).
"""

import os

import bpy
import numpy as np

SEED = 7
GLYPHS = {
	"U": ["X...X", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."],
	"S": [".XXXX", "X....", "X....", ".XXX.", "....X", "....X", "XXXX."],
	"M": ["X...X", "XX.XX", "X.X.X", "X...X", "X...X", "X...X", "X...X"],
	"C": [".XXXX", "X....", "X....", "X....", "X....", "X....", ".XXXX"],
}


def upsample(a, h, w):
	"""Cette méthode permet d'agrandir une grille de bruit a en (h, w) par interpolation bilinéaire."""
	gh, gw = a.shape
	ys = np.linspace(0, gh - 1, h)
	xs = np.linspace(0, gw - 1, w)
	y0 = np.floor(ys).astype(int)
	x0 = np.floor(xs).astype(int)
	y1 = np.minimum(y0 + 1, gh - 1)
	x1 = np.minimum(x0 + 1, gw - 1)
	fy = (ys - y0)[:, None]
	fx = (xs - x0)[None, :]
	top = a[y0][:, x0] * (1 - fx) + a[y0][:, x1] * fx
	bot = a[y1][:, x0] * (1 - fx) + a[y1][:, x1] * fx
	return top * (1 - fy) + bot * fy


def fbm(rng, h, w, gh, gw, octaves=4):
	"""Cette méthode permet de produire un bruit fractal dans [-1, 1] de taille (h, w) à partir d'une grille de base (gh, gw)."""
	out = np.zeros((h, w))
	amp, tot = 1.0, 0.0
	for o in range(octaves):
		grid = rng.random((max(2, gh * 2**o), max(2, gw * 2**o)))
		out += amp * upsample(grid, h, w)
		tot += amp
		amp *= 0.5
	return (out / tot) * 2.0 - 1.0


def normal_from_height(height, strength):
	"""Cette méthode permet de calculer une carte de normales (RGB, 0 à 1) à partir d'une carte de hauteur, Y vers le haut."""
	dy, dx = np.gradient(height)
	nx, ny, nz = -dx * strength, -dy * strength, np.ones_like(height)
	n = np.sqrt(nx**2 + ny**2 + nz**2)
	return np.stack([nx / n * 0.5 + 0.5, ny / n * 0.5 + 0.5, nz / n * 0.5 + 0.5], axis=-1)


def gray(a):
	"""Cette méthode permet de convertir une carte (h, w) en RGB gris."""
	a = np.clip(a, 0.0, 1.0)
	return np.stack([a, a, a], axis=-1)


def save_png(name, rgb):
	"""Cette méthode permet d'écrire un tableau RGB (h, w, 3) en PNG dans TEX_DIR, sans conversion de couleur, et renvoie le chemin."""
	h, w, _ = rgb.shape
	img = bpy.data.images.new(name, w, h, alpha=False)
	img.colorspace_settings.name = "Non-Color"
	rgba = np.concatenate([np.clip(rgb, 0, 1), np.ones((h, w, 1))], axis=-1)
	img.pixels.foreach_set(rgba.astype(np.float32).ravel())
	img.filepath_raw = os.path.join(TEX_DIR, name + ".png")
	img.file_format = "PNG"
	img.save()
	bpy.data.images.remove(img)
	return os.path.join(TEX_DIR, name + ".png")


def stamp_mask(Y, Z):
	"""Cette méthode permet de dessiner « USMC » (police 5x7) sur le ricasso : lettres alignées le long de z (lecture vers le haut), sommet des lettres vers la poignée."""
	mask = np.zeros(Y.shape, dtype=bool)
	pz, py = 0.04, 0.034
	z_bot, y0 = -0.46, 0.30  # le texte se lit de bas en haut, sommet des lettres vers la poignée (vu du côté +x)
	for i, ch in enumerate("USMC"):
		for k, row in enumerate(GLYPHS[ch]):
			for j, cell in enumerate(row):
				if cell != "X":
					continue
				za = z_bot + (i * 6 + j) * pz
				ya = y0 + k * py
				mask |= (Y >= ya) & (Y < ya + py) & (Z >= za) & (Z < za + pz)
	return mask


def brushed(rng, h, w, gh, gw):
	"""Cette méthode permet de produire des stries fines et longues (brossage) : bruit très étiré le long des colonnes, dans [-1, 1]."""
	return fbm(rng, h, w, gh, gw, 2)


def paint_blade(rng):
	"""Cette méthode permet de peindre la lame en métal PBR : acier brossé gris sombre (métal 1, rugosité basse), usure vive au tranchant, rayures, marquage."""
	h, half = 512, 1024
	cols = np.arange(half)
	rows = np.arange(h)
	Y = np.broadcast_to(((cols + 0.5) / half * TIP_Y)[None, :], (h, half))
	Z = np.broadcast_to((BLADE_ZMIN + (rows + 0.5) / h * BLADE_ZH)[:, None], (h, half))
	ze = np.array([hermite(EDGE, y) for y in (cols + 0.5) / half * TIP_Y])[None, :]
	zs = np.array([hermite(SPINE, y) for y in (cols + 0.5) / half * TIP_Y])[None, :]
	u = (Z - ze) / (zs - ze)  # 0 au tranchant, 1 au dos
	outside = (u < 0) | (u > 1)

	def half_maps(with_stamp):
		fine = brushed(rng, h, half, 700, 5)
		med = brushed(rng, h, half, 110, 8)
		grit = rng.normal(0, 1, (h, half))
		longs = np.clip((brushed(rng, h, half, 160, 3) - 0.55) * 9, 0, 1)  # rayures longues, plus claires
		wear = np.clip((0.07 - (Z - ze)) / 0.07, 0, 1) * (0.8 + 0.2 * fbm(rng, h, half, 3, 14, 2))
		wear += np.clip((u - 0.95) / 0.05, 0, 1) * 0.5  # arête du dos
		wear = np.clip(wear + longs * 0.45, 0, 1)
		v = 0.38 * (1 + 0.10 * fine + 0.05 * med + 0.015 * grit)
		v = v * (1 - wear) + 0.70 * wear
		fz = (u > 0.50) & (u < 0.82) & (Y > FULLER_Y0) & (Y < FULLER_Y1)
		v = np.where(fz, v * 0.88, v)  # le fond de gouttière reflète moins
		color = v[..., None] * np.array([1.0, 1.02, 1.02])[None, None, :]
		rough = np.clip(0.38 + 0.05 * fine + 0.04 * med - 0.10 * wear + 0.12 * longs + 0.01 * grit, 0.15, 0.8)
		metal = np.ones((h, half))
		pits = rng.random((h, half)) > 0.9993  # points de corrosion épars
		color = np.where(pits[..., None], color * 0.4, color)
		rough = np.where(pits, 0.8, rough)
		metal = np.where(pits, 0.4, metal)
		height = 0.004 * fine + 0.003 * med + 0.0015 * grit
		if with_stamp:
			s = stamp_mask(Y, Z)
			color = np.where(s[..., None], color + 0.16, color)  # marquage poli par l'usure
			height = height - s * 0.06
			rough = np.where(s, 0.30, rough)
		color = np.where(outside[..., None], 0.04, color)
		return color, rough, metal, height

	right = half_maps(True)
	left = half_maps(False)
	return [np.concatenate([a, b], axis=1) for a, b in zip(right, left)]


def paint_handle(rng):
	"""Cette méthode permet de peindre le manche en cuir : grain à petites cellules et plis fins, strates des rondelles, gorges sombres, arêtes polies."""
	h, w = 1024, 1024
	v = (np.arange(h) + 0.5) / h
	Y = np.broadcast_to((HANDLE_Y0 - v * (HANDLE_Y0 - HANDLE_Y1))[:, None], (h, w))
	wash = (HANDLE_Y0 - HANDLE_Y1) / WASHERS
	idx = np.clip(((HANDLE_Y0 - Y) / wash).astype(int), 0, WASHERS - 1)
	tint = 1 + (rng.random(WASHERS) - 0.5) * 0.30
	base = np.array([0.20, 0.09, 0.065])
	crevice = np.clip(1 - np.abs(fbm(rng, h, w, 170, 170, 2)), 0, 1) ** 10  # fins plis du grain (1 au creux)
	cracks = np.exp(-((fbm(rng, h, w, 14, 36, 2) / 0.012) ** 2))  # rares craquelures fines
	layer_frac = ((HANDLE_Y0 - Y) / 0.075) % 1.0
	layer = np.exp(-(((layer_frac - 0.5) / 0.04) ** 2))  # joints entre les cuirs empilés
	frac = ((HANDLE_Y0 - Y) / wash) % 1.0
	d_groove = np.minimum(frac, 1 - frac)
	groove = np.clip(1 - d_groove / 0.05, 0, 1)
	edge = np.clip(1 - np.abs(d_groove - 0.11) / 0.07, 0, 1) * (0.5 + 0.5 * fbm(rng, h, w, 6, 40, 2))  # arête usée et polie
	pores = rng.random((h, w)) > 0.985
	col = tint[idx][..., None] * base[None, None, :]
	col = col * (1 - 0.35 * crevice[..., None]) * (1 - 0.25 * layer[..., None]) * (1 - 0.30 * cracks[..., None])
	col = col * (1 - 0.70 * groove[..., None]) * np.where(pores[..., None], 0.55, 1.0)
	col = col + edge[..., None] * np.array([0.16, 0.08, 0.05])[None, None, :]
	rough = np.clip(0.42 + 0.22 * crevice + 0.20 * groove + 0.12 * layer + 0.15 * cracks - 0.16 * edge, 0.2, 0.9)
	metal = np.zeros((h, w))
	height = 0.006 * (1 - crevice) - 0.008 * layer - 0.06 * groove - 0.006 * cracks
	return col, rough, metal, height


def paint_fittings(rng):
	"""Cette méthode permet de peindre les ferrures en acier tourné sombre : stries circulaires fines (métal 1, rugosité basse), usure claire aux endroits exposés."""
	h, w = 1024, 512
	fine = brushed(rng, h, w, 900, 3)
	grit = rng.normal(0, 1, (h, w))
	wear = np.clip(np.clip(fbm(rng, h, w, 30, 15, 3) - 0.55, 0, 1) * 1.2, 0, 1)
	v = 0.33 * (1 + 0.08 * fine + 0.02 * grit)
	v = v * (1 - wear) + 0.60 * wear
	color = v[..., None] * np.array([1.0, 1.0, 1.02])[None, None, :]
	rough = np.clip(0.34 + 0.06 * fine - 0.10 * wear + 0.01 * grit, 0.15, 0.8)
	metal = np.ones((h, w))
	height = 0.0012 * fine + 0.0006 * grit
	return color, rough, metal, height


def link_material(name, paths):
	"""Cette méthode permet de brancher Color, Rough, Metal et Normal (fichiers PNG) sur le matériau name, pour l'aperçu Blender."""
	mat = bpy.data.materials[name]
	mat.use_nodes = True
	nt = mat.node_tree
	bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
	for old in [n for n in nt.nodes if n.type in ("TEX_IMAGE", "NORMAL_MAP")]:  # relance : repartir de zéro
		nt.nodes.remove(old)

	def tex(path, srgb):
		img = bpy.data.images.load(path, check_existing=True)
		img.reload()
		img.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
		node = nt.nodes.new("ShaderNodeTexImage")
		node.image = img
		return node

	color = tex(paths["Color"], True)
	nt.links.new(color.outputs["Color"], bsdf.inputs["Base Color"])
	nt.links.new(tex(paths["Rough"], False).outputs["Color"], bsdf.inputs["Roughness"])
	nt.links.new(tex(paths["Metal"], False).outputs["Color"], bsdf.inputs["Metallic"])
	nmap = nt.nodes.new("ShaderNodeNormalMap")
	nt.links.new(tex(paths["Normal"], False).outputs["Color"], nmap.inputs["Color"])
	nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
	nt.nodes.active = color  # le mode Texture de Workbench lit ce nœud


def main_textures():
	"""Cette méthode permet de peindre, d'écrire et de brancher les textures des trois matériaux du couteau."""
	os.makedirs(TEX_DIR, exist_ok=True)
	rng = np.random.default_rng(SEED)
	jobs = [
		("KaBar_BladeSteel", "Blade", paint_blade(rng), 6.0),
		("KaBar_Leather", "Handle", paint_handle(rng), 5.0),
		("KaBar_FittingsSteel", "Fittings", paint_fittings(rng), 5.0),
	]
	for mat_name, part, (color, rough, metal, height), nstrength in jobs:
		paths = {
			"Color": save_png(f"KaBar_{part}_Color", color),
			"Rough": save_png(f"KaBar_{part}_Rough", gray(rough)),
			"Metal": save_png(f"KaBar_{part}_Metal", gray(metal)),
			"Normal": save_png(f"KaBar_{part}_Normal", normal_from_height(height, nstrength * 40)),
		}
		link_material(mat_name, paths)
		print(part, {k: os.path.basename(p) for k, p in paths.items()})


main_textures()
