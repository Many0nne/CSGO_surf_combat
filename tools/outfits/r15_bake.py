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
connu, et la tenue peut peindre dans la couleur un reflet figé (chrome de MERCURE : Roblox ne reflète que le ciel).

Les pièces d'un même groupe se partagent un atlas (leurs UV ne se recouvrent pas) : Torso (UpperTorso, LowerTorso),
LeftArm, RightArm (bras, avant-bras, main), LeftLeg, RightLeg (cuisse, jambe, pied). Les deux bras ont les mêmes UV,
d'où un atlas par côté. La tête du rig est une pièce à SpecialMesh, sans UV : elle n'est pas cuite ici.

Coque de tête (option --head) : la coque d'une tenue (MeshPart, cf. docs/assets.md) a ses propres UV. Exportée en JSON
par tools/outfits/head_mesh.py, elle se cuit comme une pièce de plus, nommée « Head » (espace de la coque en studs,
centrée), dans <sortie>/<variante>/Head/Head_*.png. Sa normal map reste plate : le JSON vient des axes du FBX.

Planche (option --rig-json) : écrit les meshs des pièces, placés au repos, pour tools/outfits/render_sheet.py.

Meshs : téléchargés par Open Cloud (clé ROBLOX_OPEN_CLOUD_KEY, scope legacy-asset:manage), gardés dans <cache>.

Usage (depuis la racine du worktree) :
  uv run tools/outfits/r15_bake.py assets/outfits/mercure/mercure.py <sortie> [--size 1024] [--cache <dossier>]
    [--variant <nom>] [--groups LeftArm,RightArm] [--head <coque.json>] [--rig-json <rig.json>]
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
	"Head": 2.3823,  # haut de l'UpperTorso + demi-hauteur de la tête (1,5882) : centre de la coque
}
# Écart latéral du centre des pièces (studs, gauche = -X) : bras contre le torse, jambes côte à côte
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
	soft = np.where(y < 0, soft_bottom, soft_top)
	edge = smoothstep(1.0, 1.0 - soft, d)
	return edge * (0.2 + 0.8 * np.sqrt(np.clip(1 - d * d, 0, 1)))


# Cette méthode permet de bomber légèrement chaque face d'un bloc (1 au centre, 0 sur les arêtes) lorsqu'une tenue
# métallique doit éviter les grandes faces planes, qui reflètent le décor comme un miroir uniforme.
# Avec `vertical` à False, la face ne se bombe qu'en largeur : le reflet continue d'une pièce à la suivante (cuisse,
# genou, jambe) au lieu de marquer une coupure à chaque articulation.
def pillow(part, face, u, v, vertical=True):
	sx, sy, sz = (s / 2 for s in PARTS[part][1])
	hu = np.where((face == RIGHT) | (face == LEFT), sz, sx)
	hv = np.where((face == TOP) | (face == BOTTOM), sz, sy)
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
# est une liste de (nom de pièce, positions, normales, UV, triangles), `flat` garde une normal map plate.
def bake_atlas(outfit, variant, out_dir, size, group, meshes, flat=False):
	os.makedirs(out_dir, exist_ok=True)
	eps = 0.004
	color = np.zeros((size, size, 3))
	normal = np.zeros((size, size, 3))
	metal = np.zeros((size, size))
	rough = np.zeros((size, size))
	filled = np.zeros((size, size), dtype=bool)
	for name, pos, nrm, uv, tris in meshes:
		r = rasterize(pos, nrm, uv, tris, size)
		p, n = r["p"], r["n"]
		t, b = tangentize(r["t"], n), tangentize(r["b"], n)
		s = outfit.surface(name, p, n, variant)
		h0 = s["height"]
		if flat:
			nt = np.tile([0.0, 0.0, 1.0], (len(p), 1))
		else:
			ht = outfit.surface(name, p + t * eps, n, variant)["height"]
			hb = outfit.surface(name, p + b * eps, n, variant)["height"]
			nt = np.stack([-(ht - h0) / eps, -(hb - h0) / eps, np.ones_like(h0)], axis=1)
			nt /= np.linalg.norm(nt, axis=1, keepdims=True)
		iy, ix = r["iy"], r["ix"]
		if hasattr(outfit, "shade"):
			# normale en relief dans l'espace de la pièce, pour une tenue qui peint son reflet dans la couleur
			bumped = nt[:, :1] * t + nt[:, 1:2] * b + nt[:, 2:] * n
			bumped /= np.linalg.norm(bumped, axis=1, keepdims=True)
			s["geo_normal"] = n
			s["color"] = outfit.shade(name, p, bumped, s, variant)
		color[iy, ix] = s["color"]
		normal[iy, ix] = nt * 0.5 + 0.5
		metal[iy, ix] = s["metal"]
		rough[iy, ix] = s["rough"]
		filled[iy, ix] = True
	normal[~filled] = (0.5, 0.5, 1.0)
	maps = {
		"Color": dilate(color, filled),
		"Normal": dilate(normal, filled),
		"Metal": dilate(metal, filled),
		"Rough": dilate(rough, filled),
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


# Cette méthode permet de lire la coque de tête exportée par head_mesh.py lorsqu'une tenue a une coque à cuire.
# Les triangles qui enjambent la couture du dépliage (u de 0,98 à 0,02 : la bande de 10° au milieu du visage de la
# coque de MERCURE) sont écartés : ils couvriraient toute la largeur de l'atlas. En jeu, cette bande lit toute la
# largeur de la carte : le décor d'une coque ne doit dépendre que de la hauteur (anneaux), cf. docs/assets.md.
def load_head(path):
	with open(path) as f:
		d = json.load(f)
	nrm = np.array(d["nrm"], dtype=np.float64)
	nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12
	uv = np.array(d["uv"], dtype=np.float64)
	tris = np.array(d["tris"], dtype=np.int64)
	tris = tris[np.ptp(uv[tris, 0], axis=1) < 0.5]
	return np.array(d["pos"], dtype=np.float64), nrm, uv, tris


# Cette méthode permet de donner la position d'une pièce au repos (centre, studs depuis la racine) lorsqu'on place le
# rig pour la planche ou qu'on cherche les faces d'une pièce cachées dans une autre.
def rest_offset(name):
	kind = name.removeprefix("Left").removeprefix("Right")
	side = -1 if name.startswith("Left") else 1
	return np.array([SIDE_X.get(kind, 0) * side, OFFSETS[kind], 0])


# Cette méthode permet de repérer les triangles d'une pièce cachés dans une pièce voisine au repos (dessus de la jambe
# dans la cuisse, biseaux du coude…) lorsqu'on cuit un atlas : les meshs du rig réutilisent pour eux l'espace UV de la
# face avant, et s'ils étaient cuits après elle, ils l'écraseraient (dessin coupé ou effacé au bas des jambes).
def hidden_triangles(name, pos, tris, margin=0.01):
	centers = pos[tris].mean(axis=1) + rest_offset(name)
	hidden = np.zeros(len(tris), dtype=bool)
	for other, (_, size, _) in PARTS.items():
		if other == name:
			continue
		half = np.array(size) / 2 - margin
		hidden |= np.all(np.abs(centers - rest_offset(other)) < half, axis=1)
	return hidden


# Cette méthode permet de cuire toutes les cartes d'une variante de tenue (un atlas par groupe, puis la coque de tête
# si elle est donnée) lorsqu'on lance le script sur un module de tenue. Les triangles cachés sont cuits d'abord, pour
# que les faces visibles qui partagent leurs UV l'emportent.
def bake(outfit, variant, out_dir, size, cache, key, groups=None, head=None):
	for group in groups or GROUPS:
		hidden, visible = [], []
		for name, (_, _, g) in PARTS.items():
			if g != group:
				continue
			pos, nrm, uv, tris = load_part(name, cache, key)
			mask = hidden_triangles(name, pos, tris)
			hidden.append((name, pos, nrm, uv, tris[mask]))
			visible.append((name, pos, nrm, uv, tris[~mask]))
		bake_atlas(outfit, variant, os.path.join(out_dir, "R15"), size, group, hidden + visible)
	if head:
		bake_atlas(outfit, variant, os.path.join(out_dir, "Head"), size // 2, "Head", [("Head", *load_head(head))], True)


# Cette méthode permet d'écrire les meshs des pièces placés au repos (positions en studs depuis la racine, UV,
# triangles) lorsqu'on prépare une planche de tenues (tools/outfits/render_sheet.py, Blender sans numpy à importer).
def export_rig(path, cache, key, head=None):
	rig = {}
	for name in PARTS:
		pos, _, uv, tris = load_part(name, cache, key)
		rig[name] = {"pos": (pos + rest_offset(name)).tolist(), "uv": uv.tolist(), "tris": tris.tolist()}
	if head:
		pos, _, uv, tris = load_head(head)
		rig["Head"] = {"pos": (pos + [0, OFFSETS["Head"], 0]).tolist(), "uv": uv.tolist(), "tris": tris.tolist()}
	with open(path, "w") as f:
		json.dump(rig, f)
	print(f"[r15_bake] rig -> {path}")


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("outfit")
	ap.add_argument("out")
	ap.add_argument("--size", type=int, default=1024)
	ap.add_argument("--cache", default=os.path.join(os.environ.get("TEMP", "/tmp"), "r15_meshes"))
	ap.add_argument("--variant", action="append")
	ap.add_argument("--groups", help="groupes à cuire, séparés par des virgules (défaut : tous)")
	ap.add_argument("--head", help="coque de tête à cuire aussi (JSON de tools/outfits/head_mesh.py)")
	ap.add_argument("--rig-json", help="écrit aussi les meshs du rig au repos, pour la planche")
	args = ap.parse_args()
	spec = importlib.util.spec_from_file_location("outfit", args.outfit)
	outfit = importlib.util.module_from_spec(spec)
	sys.modules["r15_bake"] = sys.modules[__name__]
	spec.loader.exec_module(outfit)
	key = os.environ["ROBLOX_OPEN_CLOUD_KEY"]
	if args.rig_json:
		export_rig(args.rig_json, args.cache, key, args.head)
	for variant in args.variant or list(outfit.VARIANTS):
		groups = args.groups.split(",") if args.groups else None
		bake(outfit, variant, os.path.join(args.out, variant), args.size, args.cache, key, groups, args.head)


if __name__ == "__main__":
	main()
