# /// script
# requires-python = ">=3.11"
# dependencies = ["DracoPy", "numpy", "pillow"]
# ///
"""Cuit les textures d'une tenue de personnage (#521) sur les meshs du rig R15 en blocs du jeu (StarterCharacter).

Une tenue est un module Python (assets/outfits/<nom>/<nom>.py) qui décrit sa surface en 3D, pièce par pièce, dans
l'espace de la pièce en studs (origine au centre, X vers la droite du personnage, Y vers le haut, Z vers l'arrière :
l'avant du personnage est -Z). Ce script trouve, pour chaque texel de l'atlas, le point du bloc qu'il couvre, demande
à la tenue sa hauteur (relief), sa couleur, son métal et sa rugosité, puis écrit les cartes d'une SurfaceAppearance :
<sortie>/<variante>/R15/<Groupe>_{Color,Normal,Metal,Rough}.png, la normal map étant tirée de la pente du relief
(espace tangent, convention OpenGL : vert vers le haut, celle de Roblox). Une carte uniforme est écrite en 8 × 8.
Le dossier <sortie>/<variante> se publie ensuite comme un skin d'arme (tools/skins/publish_skin.py).

Une tenue peut aussi définir shade(part, p, normale en relief, surface, variante) -> couleur : le relief est alors
connu, et la tenue peut peindre dans la couleur un reflet figé (chrome de MERCURE : Roblox ne reflète que le ciel) ou
une part du relief ombré (lit_relief : matières mates).

Les pièces d'un même groupe se partagent un atlas (leurs UV ne se recouvrent pas) : Torso (UpperTorso, LowerTorso),
LeftArm, RightArm (bras, avant-bras, main), LeftLeg, RightLeg (cuisse, jambe, pied). Les deux bras ont les mêmes UV,
d'où un atlas par côté. La tête du rig est une pièce à SpecialMesh, sans UV : elle n'est pas cuite ici.

Deux défauts du rig sont corrigés à la cuisson (cf. docs/assets.md) : les faces cachées dans la pièce voisine qui
partagent l'UV de la face avant sont cuites d'abord (la face visible l'emporte), et aux articulations les faces
confondues de deux pièces peignent comme la pièce propriétaire (sinon leurs dessins scintillent).

Coque de tête : une tenue qui pose `HEAD = True` reçoit aussi la pièce « Head » dans surface() (espace de la coque en
studs, centrée). Le mesh de la coque (MeshPart, ses propres UV) est donné par --head, en JSON écrit par
tools/outfits/head_mesh.py ; cartes dans <sortie>/<variante>/Head/Head_*.png. --groups Head ne cuit que la coque.

Planche (option --rig-json) : écrit les meshs des pièces, placés au repos, pour tools/outfits/render_sheet.py.

Meshs : téléchargés par Open Cloud (clé ROBLOX_OPEN_CLOUD_KEY, scope legacy-asset:manage), gardés dans <cache>.

Usage (depuis la racine du worktree) :
  uv run tools/outfits/r15_bake.py assets/outfits/bronze/bronze.py <sortie> [--size 1024] [--cache <dossier>]
    [--variant <nom>] [--groups LeftArm,RightArm,Head] [--head <coque.json>] [--rig-json <rig.json>]
"""

import argparse
import importlib.util
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "preview"))
import fetch_viewmodel as fv  # noqa: E402

# Pièces du StarterCharacter : id du mesh, taille de la pièce (studs, relevée dans Studio le 17/11/2026), groupe d'atlas
# (OFFSETS : hauteur du centre de chaque pièce au-dessus de la racine, rig au repos, pour un dessin continu d'une pièce
# à l'autre)
PARTS = {
	"UpperTorso": ("1699715593", (3.1764, 2.5412, 1.5882), "Torso"),
	"LowerTorso": ("1699715652", (3.1764, 0.6354, 1.5882), "Torso"),
	"LeftUpperArm": ("1699715550", (1.5882, 1.8561, 1.5882), "LeftArm"),
	"LeftLowerArm": ("1699715541", (1.5882, 1.6707, 1.5882), "LeftArm"),
	"LeftHand": ("1699715537", (1.5882, 0.4765, 1.5882), "LeftArm"),
	"RightUpperArm": ("1699715576", (1.5882, 1.8561, 1.5882), "RightArm"),
	"RightLowerArm": ("1699715562", (1.5882, 1.6707, 1.5882), "RightArm"),
	"RightHand": ("1699715557", (1.5882, 0.4765, 1.5882), "RightArm"),
	"LeftUpperLeg": ("1699715616", (1.5882, 1.9321, 1.5882), "LeftLeg"),
	"LeftLowerLeg": ("1699715610", (1.5882, 1.8949, 1.5882), "LeftLeg"),
	"LeftFoot": ("1699715602", (1.5882, 0.4765, 1.5882), "LeftLeg"),
	"RightUpperLeg": ("1699715641", (1.5882, 1.9321, 1.5882), "RightLeg"),
	"RightLowerLeg": ("1699715632", (1.5882, 1.8949, 1.5882), "RightLeg"),
	"RightFoot": ("1699715627", (1.5882, 0.4765, 1.5882), "RightLeg"),
}
GROUPS = ["Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg"]
OFFSETS = {
	"UpperTorso": 0.3176,
	"LowerTorso": -1.2706,
	"UpperArm": 0.5855,
	"LowerArm": -0.3559,
	"Hand": -1.35,
	"UpperLeg": -2.2565,
	"LowerLeg": -3.4955,
	"Foot": -4.5264,
	"Head": 2.3823,  # centre de la coque : haut de l'UpperTorso (1,5882) + demi-hauteur de la tête (0,7941)
}
# Écart latéral du centre des pièces (studs, gauche = -X) : bras contre le torse (demi-largeur du torse 1,5882 + du
# bras 0,7941), jambes côte à côte (demi-largeur d'une jambe)
SIDE_X = {"UpperArm": 2.3823, "LowerArm": 2.3823, "Hand": 2.3823, "UpperLeg": 0.7941, "LowerLeg": 0.7941, "Foot": 0.7941}


# Cette méthode permet de donner la hauteur d'un point au-dessus de la racine du personnage (rig au repos) lorsqu'une
# tenue dessine un motif continu le long d'un membre.
def height_of(part, p):
	key = part.removeprefix("Left").removeprefix("Right")
	return OFFSETS[key] + p[:, 1]

# Faces d'un bloc, selon l'axe dominant de la normale
FRONT, BACK, RIGHT, LEFT, TOP, BOTTOM = range(6)


# Cette méthode permet de classer chaque point sur une face du bloc et de lui donner des coordonnées 2D (studs) sur
# cette face lorsqu'une tenue dessine face par face : avant/arrière (u = x, v = y), côtés (u = z, v = y),
# dessus/dessous (u = x, v = z).
def face_coords(p, n):
	ax = np.abs(n)
	dom = np.argmax(ax, axis=1)
	face = np.where(
		dom == 2,
		np.where(n[:, 2] < 0, FRONT, BACK),
		np.where(dom == 0, np.where(n[:, 0] > 0, RIGHT, LEFT), np.where(n[:, 1] > 0, TOP, BOTTOM)),
	)
	u = np.where(dom == 0, p[:, 2], p[:, 0])
	v = np.where(dom == 1, p[:, 2], p[:, 1])
	return face, u, v


# Cette méthode permet de donner le relief d'un muscle elliptique (1 au centre, 0 au bord, pente nulle au bord si
# `power` >= 1) lorsqu'une tenue dessine une masse musculaire sur une face.
def dome(u, v, cu, cv, ru, rv, power=1.0):
	d2 = ((u - cu) / ru) ** 2 + ((v - cv) / rv) ** 2
	return np.where(d2 < 1, (1 - np.minimum(d2, 1)) ** power, 0.0)


# Cette méthode permet de donner le relief d'une masse musculaire (bord fondu, sommet légèrement bombé) lorsqu'une
# tenue sculpte une face ; `soft_top` et `soft_bottom` règlent la douceur du bord haut et bas (petit = bord net).
def muscle(u, v, cu, cv, ru, rv, soft_top=0.6, soft_bottom=0.25):
	x = (u - cu) / ru
	y = (v - cv) / rv
	d = np.hypot(x, y)
	# passage progressif d'un bord à l'autre : un changement net à mi-hauteur cassait la pente du relief (tirets clairs
	# au milieu de chaque muscle dans la normal map, et dans la couleur des tenues qui peignent leur relief)
	soft = soft_bottom + (soft_top - soft_bottom) * smoothstep(-0.2, 0.2, y)
	edge = smoothstep(1.0, 1.0 - soft, d)
	return edge * (0.2 + 0.8 * np.sqrt(np.clip(1 - d * d, 0, 1)))


# Cette méthode permet de donner les demi-dimensions de la face d'un bloc le long de u et de v (cf. face_coords)
# lorsqu'une tenue place un dessin par rapport aux bords de la face.
def half_sizes(part, face):
	sx, sy, sz = (s / 2 for s in PARTS[part][1])
	hu = np.where((face == RIGHT) | (face == LEFT), sz, sx)
	hv = np.where((face == TOP) | (face == BOTTOM), sz, sy)
	return hu, hv


# Cette méthode permet de bomber légèrement chaque face d'un bloc (1 au centre, 0 sur les arêtes) lorsqu'une tenue
# métallique doit éviter les grandes faces planes, qui reflètent le décor comme un miroir uniforme.
# Avec `vertical` à False, la face ne se bombe qu'en largeur : le reflet continue d'une pièce à la suivante (cuisse,
# genou, jambe) au lieu de marquer une coupure à chaque articulation.
def pillow(part, face, u, v, vertical=True):
	hu, hv = half_sizes(part, face)
	across = np.clip(1 - (u / hu) ** 2, 0, 1)
	if not vertical:
		return np.where((face == TOP) | (face == BOTTOM), 0.0, across)
	return across * np.clip(1 - (v / hv) ** 2, 0, 1)


# Cette méthode permet de donner l'intensité d'un trait (1 sur le segment, 0 à `width` studs) lorsqu'une tenue trace
# un sillon ou une ligne d'encre entre deux points d'une face.
def segment(u, v, a, b, width):
	ax, ay = a
	bx, by = b
	dx, dy = bx - ax, by - ay
	t = np.clip(((u - ax) * dx + (v - ay) * dy) / (dx * dx + dy * dy), 0, 1)
	d = np.hypot(u - (ax + t * dx), v - (ay + t * dy))
	return 1 - smoothstep(0, width, d)


# Cette méthode permet de donner l'intensité d'un trait qui suit le bord d'une ellipse, entre deux angles (degrés,
# 0 = droite, sens trigonométrique) lorsqu'une tenue souligne le contour d'un muscle.
def outline(u, v, cu, cv, ru, rv, width, a0=0, a1=360):
	x = (u - cu) / ru
	y = (v - cv) / rv
	d = np.abs(np.hypot(x, y) - 1) * min(ru, rv)
	ang = np.degrees(np.arctan2(y, x)) % 360
	a0, a1 = a0 % 360, a1 % 360
	inside = (ang >= a0) & (ang <= a1) if a0 <= a1 else (ang >= a0) | (ang <= a1)
	return np.where(inside, 1 - smoothstep(0, width, d), 0.0)


def smoothstep(e0, e1, x):
	t = np.clip((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)


# Cette méthode permet de passer une couleur sRGB (celle qu'on lit à l'écran) en linéaire lorsqu'une tenue donne ses
# couleurs, r15_bake travaillant en linéaire.
def lin(r, g, b):
	return np.array([r, g, b]) ** 2.2


# Lumière du relief peint des matières mates (lit_relief) : venue d'en haut, un peu de la gauche du personnage (-X), et
# de face pour chaque face
RELIEF_LIGHT = np.array([-0.35, 1.0, 0.0])


# Cette méthode permet d'ombrer dans la couleur une part du relief (lumière RELIEF_LIGHT, `gain` : force, bornée entre
# `lo` et `hi`) lorsqu'une tenue mate doit garder ses muscles lisibles sous une lumière douce, dans son shade().
def lit_relief(color, bumped, geo, gain, lo, hi):
	light = RELIEF_LIGHT[None] + geo * 0.8
	light /= np.linalg.norm(light, axis=1, keepdims=True)
	detail = np.sum((bumped - geo) * light, axis=1)
	return np.clip(color * np.clip(1 + gain * detail, lo, hi)[:, None], 0, 1)


# Cette méthode permet de charger un module de tenue (qui importe ses outils depuis r15_bake) lorsqu'on cuit une tenue
# ou qu'une tenue reprend l'anatomie de MERCURE.
def load_outfit(path, name="outfit"):
	sys.modules.setdefault("r15_bake", sys.modules[__name__])
	spec = importlib.util.spec_from_file_location(name, path)
	module = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(module)
	return module


_mercure = None


# Cette méthode permet de charger une fois le module de MERCURE lorsqu'une tenue reprend sa musculature dessinée
# (PAINTERS, RELIEF, BULGE).
def mercure():
	global _mercure
	if _mercure is None:
		_mercure = load_outfit(os.path.join(HERE, "..", "..", "assets", "outfits", "mercure", "mercure.py"), "mercure")
	return _mercure


# Cette méthode permet de donner le relief des muscles dessinés de MERCURE sur une pièce (0 si elle n'en a pas)
# lorsqu'une autre tenue reprend cette anatomie.
def muscles(part, face, u, v):
	painter = mercure().PAINTERS.get(part)
	return painter(face, u, v)[0] if painter else np.zeros_like(u)


# Cette méthode permet de mesurer le creux des muscles en un point (> 0 : plus bas que la moyenne du relief sur huit
# directions à `step` studs) lorsqu'une patine ou un vernis s'accumule entre les masses.
def cavity(part, face, u, v, step=0.26):
	if part not in mercure().PAINTERS:
		return np.zeros_like(u)
	around = np.zeros_like(u)
	for k in range(8):
		a = k * np.pi / 4
		around += muscles(part, face, u + step * np.cos(a), v + step * np.sin(a))
	return (around / 8 - muscles(part, face, u, v)) / mercure().RELIEF


# Cette méthode permet de lire un mesh du rig (positions ramenées à la taille de la pièce, normales, UV, triangles)
# lorsqu'on prépare la cuisson d'une pièce.
def load_part(name, cache, key):
	aid, size, _ = PARTS[name]
	buf = fv.download(aid, cache, key)
	pos, nrm, uv, faces = fv.parse_mesh(buf)
	pos = np.array(pos, dtype=np.float64)
	lo, hi = pos.min(axis=0), pos.max(axis=0)
	pos = (pos - (lo + hi) / 2) / (hi - lo) * np.array(size)
	nrm = np.array(nrm, dtype=np.float64)
	if not np.any(nrm):
		nrm = np.array(fv.smooth_normals(pos.tolist(), list(faces)))
	nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12
	tris = np.array(faces, dtype=np.int64).reshape(-1, 3)
	return pos, nrm, np.array(uv, dtype=np.float64), tris


# Cette méthode permet de remplir chaque texel couvert par un triangle (point 3D, normale, repère tangent) lorsqu'on
# cuit l'atlas d'un groupe ; renvoie les tableaux à plat des texels touchés.
def rasterize(pos, nrm, uv, tris, size):
	out = {"ix": [], "iy": [], "p": [], "n": [], "t": [], "b": []}
	for a, b, c in tris:
		ua, ub, uc = uv[a] * size, uv[b] * size, uv[c] * size
		x0 = int(max(np.floor(min(ua[0], ub[0], uc[0])) - 1, 0))
		x1 = int(min(np.ceil(max(ua[0], ub[0], uc[0])) + 1, size - 1))
		y0 = int(max(np.floor(min(ua[1], ub[1], uc[1])) - 1, 0))
		y1 = int(min(np.ceil(max(ua[1], ub[1], uc[1])) + 1, size - 1))
		if x1 < x0 or y1 < y0:
			continue
		xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
		xs, ys = xs.ravel(), ys.ravel()
		den = (ub[1] - uc[1]) * (ua[0] - uc[0]) + (uc[0] - ub[0]) * (ua[1] - uc[1])
		if abs(den) < 1e-9:
			continue
		w0 = ((ub[1] - uc[1]) * (xs - uc[0]) + (uc[0] - ub[0]) * (ys - uc[1])) / den
		w1 = ((uc[1] - ua[1]) * (xs - uc[0]) + (ua[0] - uc[0]) * (ys - uc[1])) / den
		w2 = 1 - w0 - w1
		tol = -0.02
		m = (w0 >= tol) & (w1 >= tol) & (w2 >= tol)
		if not m.any():
			continue
		w = np.stack([w0[m], w1[m], w2[m]], axis=1)
		p = w @ np.stack([pos[a], pos[b], pos[c]])
		n = w @ np.stack([nrm[a], nrm[b], nrm[c]])
		n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
		# Repère tangent du triangle : dP/du et dP/dv (v des UV Roblox vers le bas de l'image)
		e1, e2 = pos[b] - pos[a], pos[c] - pos[a]
		d1, d2 = (uv[b] - uv[a]), (uv[c] - uv[a])
		det = d1[0] * d2[1] - d2[0] * d1[1]
		if abs(det) < 1e-12:
			continue
		t = (e1 * d2[1] - e2 * d1[1]) / det
		bt = (e2 * d1[0] - e1 * d2[0]) / det
		out["ix"].append(xs[m].astype(np.int64))
		out["iy"].append(ys[m].astype(np.int64))
		out["p"].append(p)
		out["n"].append(n)
		out["t"].append(np.repeat(t[None], len(p), axis=0))
		out["b"].append(np.repeat(-bt[None], len(p), axis=0))  # vers le haut de l'image (OpenGL)
	if not out["p"]:
		return {k: np.zeros((0, 3)) if k in ("p", "n", "t", "b") else np.zeros(0, dtype=np.int64) for k in out}
	return {k: np.concatenate(v) for k, v in out.items()}


# Cette méthode permet de projeter un vecteur sur le plan tangent et de le normer lorsqu'on construit le repère des
# normal maps.
def tangentize(v, n):
	v = v - n * np.sum(v * n, axis=1, keepdims=True)
	return v / (np.linalg.norm(v, axis=1, keepdims=True) + 1e-12)


# Cette méthode permet d'étendre les texels remplis sur leurs voisins vides (quelques passes) lorsqu'on écrit un
# atlas, pour que le filtrage des textures ne fasse pas apparaître de coutures noires aux bords des îlots UV.
def dilate(img, filled, passes=8):
	img = img.copy()
	filled = filled.copy()
	for _ in range(passes):
		acc = np.zeros_like(img, dtype=np.float64)
		cnt = np.zeros(filled.shape, dtype=np.float64)
		for dy in (-1, 0, 1):
			for dx in (-1, 0, 1):
				if dx == 0 and dy == 0:
					continue
				sh = np.roll(np.roll(filled, dy, 0), dx, 1)
				si = np.roll(np.roll(img, dy, 0), dx, 1)
				acc += si * (sh[..., None] if img.ndim == 3 else sh)
				cnt += sh
		new = (~filled) & (cnt > 0)
		div = cnt[new][..., None] if img.ndim == 3 else cnt[new]
		img[new] = acc[new] / div
		filled = filled | new
	return img


# Cette méthode permet de cuire l'atlas d'un groupe (pièces qui se le partagent) lorsqu'on cuit une variante ; `meshes`
# est une liste de (nom de pièce, positions, normales, UV, triangles) ; la coque (« Head ») n'a pas d'articulation.
def bake_atlas(outfit, variant, out_dir, size, group, meshes):
	os.makedirs(out_dir, exist_ok=True)
	eps = 0.004
	head = group == "Head"
	color = np.zeros((size, size, 3))
	normal = np.zeros((size, size, 3))
	metal = np.zeros((size, size))
	rough = np.zeros((size, size))
	filled = np.zeros((size, size), dtype=bool)
	for name, pos, nrm, uv, tris in meshes:
		r = rasterize(pos, nrm, uv, tris, size)
		p, n = r["p"], r["n"]
		t, b = tangentize(r["t"], n), tangentize(r["b"], n)
		# Aux articulations, deux pièces ont des faces confondues : chacune y peint comme la pièce propriétaire, fixée
		# au texel (les points décalés du calcul de la normale gardent la même), sinon leurs dessins scintilleraient.
		owner = np.full(len(p), name, dtype=object) if head else owners(name, p, n)

		# Cette méthode permet de lire la surface de la tenue aux points `q` du texel lorsqu'on cuit ses cartes.
		def surf(q):
			return as_owner(outfit.surface, name, q, (n,), variant, owner=owner)

		s = surf(p)
		h0 = s["height"]
		ht = surf(p + t * eps)["height"]
		hb = surf(p + b * eps)["height"]
		nt = np.stack([-(ht - h0) / eps, -(hb - h0) / eps, np.ones_like(h0)], axis=1)
		nt /= np.linalg.norm(nt, axis=1, keepdims=True)
		iy, ix = r["iy"], r["ix"]
		if hasattr(outfit, "shade"):
			# normale en relief dans l'espace de la pièce, pour une tenue qui peint son reflet dans la couleur
			bumped = nt[:, :1] * t + nt[:, 1:2] * b + nt[:, 2:] * n
			bumped /= np.linalg.norm(bumped, axis=1, keepdims=True)
			s["geo_normal"] = n
			s["color"] = as_owner(outfit.shade, name, p, (bumped, s), variant, owner=owner)
		color[iy, ix] = s["color"]
		normal[iy, ix] = nt * 0.5 + 0.5
		metal[iy, ix] = s["metal"]
		rough[iy, ix] = s["rough"]
		filled[iy, ix] = True
	if not filled.any():
		raise SystemExit(f"[r15_bake] {variant} {group} : aucun texel couvert (mesh vide ou UV hors de la carte)")
	normal[~filled] = (0.5, 0.5, 1.0)
	passes = size // 8 if head else 8  # coque : combler aussi la couture du dépliage (triangles écartés)
	maps = {
		"Color": dilate(color, filled, passes),
		"Normal": dilate(normal, filled, passes),
		"Metal": dilate(metal, filled, passes),
		"Rough": dilate(rough, filled, passes),
	}
	for kind, img in maps.items():
		arr = np.clip(img * 255 + 0.5, 0, 255).astype(np.uint8)
		if kind == "Color":
			arr = np.clip((np.clip(img, 0, 1) ** (1 / 2.2)) * 255 + 0.5, 0, 255).astype(np.uint8)
		used = arr[filled]  # texels couverts par les pièces (le reste de l'atlas n'est jamais lu)
		if np.all(used.max(axis=0) - used.min(axis=0) <= 1):
			arr = np.empty((8, 8) + arr.shape[2:], dtype=np.uint8)  # carte uniforme : 8 × 8 suffit
			arr[...] = used[0]
		Image.fromarray(arr).save(os.path.join(out_dir, f"{group}_{kind}.png"))
	print(f"[r15_bake] {variant} {group} : {int(filled.sum())} texels")


# Cette méthode permet de lire la coque exportée par head_mesh.py (unités du FBX = studs de la MeshPart) lorsqu'une
# tenue a une coque à cuire, sans les triangles qui enjambent la couture du dépliage (cf. docs/assets.md).
def load_head(path, skip_seam=True):
	with open(path) as f:
		d = json.load(f)
	nrm = np.array(d["nrm"], dtype=np.float64)
	nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12
	uv = np.array(d["uv"], dtype=np.float64)
	tris = np.array(d["tris"], dtype=np.int64)
	if skip_seam:
		tris = tris[np.ptp(uv[tris, 0], axis=1) < 0.5]  # bande de 10° au milieu du visage : u de 0,976 à 0,024
	return np.array(d["pos"], dtype=np.float64), nrm, uv, tris


# Cette méthode permet de donner la position d'une pièce au repos (centre, studs depuis la racine) lorsqu'on place le
# rig pour la planche ou qu'on cherche les faces d'une pièce cachées dans une autre.
def rest_offset(name):
	kind = name.removeprefix("Left").removeprefix("Right")
	side = -1 if name.startswith("Left") else 1
	return np.array([SIDE_X.get(kind, 0) * side, OFFSETS[kind], 0])


# Cette méthode permet de repérer les triangles d'une pièce cachés dans une voisine au repos (dessus de la jambe…)
# lorsqu'on cuit un atlas : ils réutilisent l'UV de la face avant, qu'ils écraseraient s'ils étaient cuits après elle.
def hidden_triangles(name, pos, tris, margin=0.01):
	centers = pos[tris].mean(axis=1) + rest_offset(name)
	hidden = np.zeros(len(tris), dtype=bool)
	for other, (_, size, _) in PARTS.items():
		if other == name:
			continue
		half = np.array(size) / 2 - margin
		hidden |= np.all(np.abs(centers - rest_offset(other)) < half, axis=1)
	return hidden


# Cette méthode permet de trouver la pièce qui « possède » chaque point (la première de PARTS dont la boîte au repos le
# contient, face tournée du même côté) lorsque deux pièces ont là des faces confondues (coude, hanche…).
def owners(name, p, n, margin=0.01):
	world = p + rest_offset(name)
	axis = np.argmax(np.abs(n), axis=1)
	sign = np.sign(n[np.arange(len(n)), axis])
	owner = np.full(len(p), name, dtype=object)
	for other, (_, size, _) in PARTS.items():
		if other == name:
			break  # seules les pièces qui la précèdent peuvent la posséder : les deux côtés choisissent la même
		rel = world - rest_offset(other)
		half = np.array(size) / 2
		inside = np.all(np.abs(rel) <= half + margin, axis=1)
		# face collée à l'autre pièce mais tournée vers elle (intérieur du bras contre le torse) : pas partagée
		facing = rel[np.arange(len(p)), axis] * sign > -half[axis] + margin
		owner = np.where(inside & facing & (owner == name), other, owner)
	return owner


# Cette méthode permet d'appeler une fonction de la tenue (surface, shade) comme la pièce propriétaire de chaque point
# (owners) lorsque les deux pièces d'une articulation doivent y peindre le même dessin ; `extra` suit les points.
def as_owner(fn, name, p, extra, *args, owner=None):
	owner = owners(name, p, extra[0]) if owner is None else owner
	parts = list(dict.fromkeys(owner))
	if len(p) == 0 or parts == [name]:
		return fn(name, p, *extra, *args)
	out = None
	for part in parts:
		mask = owner == part
		local = p[mask] + rest_offset(name) - rest_offset(part)
		res = fn(part, local, *[e[mask] if isinstance(e, np.ndarray) else _sub(e, mask) for e in extra], *args)
		if out is None:
			out = _empty_like(res, len(p))
		_assign(out, mask, res)
	return out


# Cette méthode permet de garder les points d'un masque dans un résultat (tableau ou dictionnaire de tableaux)
# lorsqu'as_owner découpe les points par pièce.
def _sub(value, mask):
	if isinstance(value, dict):
		return {k: (v[mask] if isinstance(v, np.ndarray) and len(v) == len(mask) else v) for k, v in value.items()}
	return value[mask]


# Cette méthode permet de créer un résultat vide de la forme de `res` pour `n` points lorsqu'as_owner le remplit.
def _empty_like(res, n):
	if isinstance(res, dict):
		return {k: np.zeros((n,) + np.shape(v)[1:]) for k, v in res.items()}
	return np.zeros((n,) + np.shape(res)[1:])


# Cette méthode permet de recopier dans `out` les valeurs calculées pour les points d'un masque lorsqu'as_owner
# rassemble les résultats des différentes pièces.
def _assign(out, mask, res):
	if isinstance(res, dict):
		for k, v in res.items():
			out[k][mask] = v
	else:
		out[mask] = res


# Cette méthode permet de cuire toutes les cartes d'une variante (un atlas par groupe, puis la coque) lorsqu'on lance le
# script ; triangles cachés cuits d'abord, pour que les faces visibles qui partagent leurs UV l'emportent.
def bake(outfit, variant, out_dir, size, cache, key, groups=None, head=None):
	for group in GROUPS if groups is None else groups:
		if group == "Head":
			continue
		hidden, visible = [], []
		for name, (_, _, g) in PARTS.items():
			if g != group:
				continue
			pos, nrm, uv, tris = load_part(name, cache, key)
			mask = hidden_triangles(name, pos, tris)
			hidden.append((name, pos, nrm, uv, tris[mask]))
			visible.append((name, pos, nrm, uv, tris[~mask]))
		bake_atlas(outfit, variant, os.path.join(out_dir, "R15"), size, group, hidden + visible)
	if head and (groups is None or "Head" in groups):
		bake_atlas(outfit, variant, os.path.join(out_dir, "Head"), size // 2, "Head", [("Head", *load_head(head))])


# Cette méthode permet d'écrire les meshs des pièces placés au repos (positions en studs depuis la racine, UV,
# triangles) lorsqu'on prépare une planche de tenues (tools/outfits/render_sheet.py, Blender sans numpy à importer).
def export_rig(path, cache, key, head=None):
	rig = {}
	for name in PARTS:
		pos, _, uv, tris = load_part(name, cache, key)
		rig[name] = {"pos": (pos + rest_offset(name)).tolist(), "uv": uv.tolist(), "tris": tris.tolist(),
			"group": PARTS[name][2]}
	if head:
		pos, _, uv, tris = load_head(head, skip_seam=False)  # la planche montre la coque entière
		rig["Head"] = {"pos": (pos + [0, OFFSETS["Head"], 0]).tolist(), "uv": uv.tolist(), "tris": tris.tolist(),
			"group": "Head"}
	with open(path, "w") as f:
		json.dump(rig, f)
	print(f"[r15_bake] rig -> {path}")


# Cette méthode permet de cuire les variantes demandées d'une tenue (corps, puis coque si la tenue en a une) lorsqu'on
# lance le script en ligne de commande ; refuse une coque donnée à une tenue sans coque, et l'inverse.
def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("outfit")
	ap.add_argument("out")
	ap.add_argument("--size", type=int, default=1024)
	ap.add_argument("--cache", default=os.path.join(os.environ.get("TEMP", "/tmp"), "r15_meshes"))
	ap.add_argument("--variant", action="append")
	ap.add_argument("--groups", help="groupes à cuire, séparés par des virgules, Head pour la coque (défaut : tous)")
	ap.add_argument("--head", help="mesh de la coque de tête (JSON de tools/outfits/head_mesh.py)")
	ap.add_argument("--rig-json", help="écrit aussi les meshs du rig au repos, pour la planche")
	args = ap.parse_args()
	outfit = load_outfit(args.outfit)
	groups = None if args.groups is None else [g for g in args.groups.split(",") if g]
	unknown = set(groups or []) - set(GROUPS) - {"Head"}
	if unknown or groups == []:
		raise SystemExit(f"[r15_bake] --groups : groupes inconnus ou vides ({', '.join(sorted(unknown))})")
	has_head = getattr(outfit, "HEAD", False)
	wants_head = groups is None or "Head" in groups
	if (args.head or (groups and "Head" in groups)) and not has_head:
		raise SystemExit(f"[r15_bake] {args.outfit} n'a pas de coque (HEAD absent) : --head et --groups Head refusés")
	if has_head and wants_head and not args.head:
		# sans elle, les anciennes cartes de la coque resteraient en place, désaccordées du corps
		raise SystemExit("[r15_bake] la tenue a une coque (HEAD = True) : --head manque (ou --groups sans Head)")
	key = os.environ["ROBLOX_OPEN_CLOUD_KEY"]
	if args.rig_json:
		export_rig(args.rig_json, args.cache, key, args.head)
	for variant in args.variant or list(outfit.VARIANTS):
		bake(outfit, variant, os.path.join(args.out, variant), args.size, args.cache, key, groups, args.head)


if __name__ == "__main__":
	main()
