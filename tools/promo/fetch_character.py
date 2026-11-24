# /// script
# requires-python = ">=3.11"
# dependencies = ["DracoPy", "numpy", "pillow"]
# ///
"""Reconstruit en .glb le personnage du jeu (StarterCharacter), posé articulation par articulation, pour les miniatures.

Le StarterCharacter n'est que dans la place publiée (pas dans Rojo) : ses pièces, tailles, couleurs et articulations
sont relevées dans tools/promo/character.json. Les meshs R15 sont téléchargés par Open Cloud (comme
tools/preview/fetch_viewmodel.py, même clé ROBLOX_OPEN_CLOUD_KEY) ; la tête classique (SpecialMesh « Head ») et son
visage par défaut sont recréés ici. Écrit <sortie>.glb et <sortie>_face.png (carte de couleur de la tête, objet « Head »).

Usage : uv run tools/promo/fetch_character.py <sortie.glb> [pose.json]
Pose : { "<articulation>": [rx, ry, rz] } en degrés (CFrame.Angles dans le repère de l'articulation), par ex.
{"RightShoulder": [0, 0, 120], "LeftKnee": [-60, 0, 0]} ; racine à l'origine.
"""

import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "preview"))
import fetch_viewmodel as fv  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


# Cette méthode permet de construire une matrice 4x4 Roblox (translation puis CFrame.Angles X, Y, Z en degrés).
def cf(pos=(0, 0, 0), angles=(0, 0, 0)):
	rx, ry, rz = (math.radians(a) for a in angles)
	cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	mx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
	my = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
	mz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
	m = np.eye(4)
	m[:3, :3] = mx @ my @ mz
	m[:3, 3] = pos
	return m


# Cette méthode permet de placer chaque pièce dans le monde en suivant les articulations depuis la racine :
# Part1 = Part0 * C0 * pose * C1^-1, comme un Motor6D.
def solve(char, pose):
	world = {"HumanoidRootPart": np.eye(4)}
	pending = list(char["joints"])
	while pending:
		for j in list(pending):
			if j["p0"] in world:
				world[j["p1"]] = world[j["p0"]] @ cf(j["c0"]) @ cf(angles=pose.get(j["name"], (0, 0, 0))) @ np.linalg.inv(cf(j["c1"]))
				pending.remove(j)
	return world


# Cette méthode permet de générer la tête classique de Roblox (cylindre aux arêtes arrondies, axe vertical) avec un
# dépliage cylindrique dont le milieu (u = 0,5) est la face avant (-Z), là où se pose le visage.
def classic_head(size, scale):
	radius, height = size[0] * scale * 0.5, size[1] * scale
	bevel = radius * 0.45
	profile = []  # (rayon, y) du bas vers le haut
	for k in range(9):
		a = -math.pi / 2 + k * (math.pi / 2) / 8
		profile.append((radius - bevel + bevel * math.cos(a), -height / 2 + bevel + bevel * math.sin(a)))
	for k in range(9):
		a = k * (math.pi / 2) / 8
		profile.append((radius - bevel + bevel * math.cos(a), height / 2 - bevel + bevel * math.sin(a)))
	profile = [(0.0, -height / 2)] + profile + [(0.0, height / 2)]
	seg = 48
	pos, nrm, uv = [], [], []
	for i in range(seg + 1):
		t = i / seg
		ang = t * 2 * math.pi
		# u = 0,5 face à -Z
		dx, dz = -math.sin(ang), math.cos(ang)
		for r, y in profile:
			pos.append((r * dx, y, r * dz))
			uv.append((t, 1 - (y + height / 2) / height))
	n = len(profile)
	faces = []
	for i in range(seg):
		for k in range(n - 1):
			a, b, c, d = i * n + k, i * n + k + 1, (i + 1) * n + k, (i + 1) * n + k + 1
			faces += [a, c, b, b, c, d]
	nrm = fv.smooth_normals(pos, faces)
	return pos, nrm, uv, faces


# Cette méthode permet de dessiner la carte de couleur de la tête : peau, et visage souriant par défaut au milieu.
def face_texture(path, skin):
	from PIL import Image, ImageDraw

	w, h = 2048, 512
	img = Image.new("RGB", (w, h), tuple(skin))
	d = ImageDraw.Draw(img)
	cx, cy = w // 2, h // 2
	# Le quart de tour avant couvre w/4 px : yeux à ±0,1 tour, sourire en dessous
	eye_dx, eye_w, eye_h = int(w * 0.035), int(w * 0.011), int(h * 0.075)
	for sx in (-1, 1):
		x = cx + sx * eye_dx
		d.ellipse((x - eye_w, cy - h * 0.12 - eye_h, x + eye_w, cy - h * 0.12 + eye_h), fill=(20, 20, 20))
	mw, mh = int(w * 0.055), int(h * 0.2)
	d.arc((cx - mw, cy - mh + h * 0.02, cx + mw, cy + mh + h * 0.02), 20, 160, fill=(20, 20, 20), width=int(h * 0.025))
	img.save(path)


# Cette méthode permet de convertir une composante sRGB (Color3 de Roblox) en linéaire, comme glTF l'attend.
def srgb_to_linear(c):
	return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def main():
	if len(sys.argv) not in (2, 3):
		raise SystemExit("usage : uv run tools/promo/fetch_character.py <sortie.glb> [pose.json]")
	out = os.path.abspath(sys.argv[1])
	pose = {}
	if len(sys.argv) == 3:
		with open(sys.argv[2], encoding="utf-8") as f:
			pose = json.load(f)
	key = os.environ.get("ROBLOX_OPEN_CLOUD_KEY")
	if not key:
		raise SystemExit("[fetch_character] variable d'environnement ROBLOX_OPEN_CLOUD_KEY absente")
	with open(os.path.join(HERE, "character.json"), encoding="utf-8") as f:
		char = json.load(f)
	cache = os.path.join(os.path.dirname(out), "cache")
	world = solve(char, pose)
	meshes = []
	for name, p in char["parts"].items():
		if p.get("hidden"):
			continue
		m = world[name]
		part = {"size": p["size"], "cframe": (tuple(m[:3, 3]), tuple(m[:3, :3].reshape(-1)))}
		if p.get("head"):
			pos, nrm, uv, faces = classic_head(p["size"], p["scale"])
			# déjà à la bonne taille : rotation et position seules
			r = m[:3, :3]
			pos = [tuple(r @ np.array(v) + m[:3, 3]) for v in pos]
			nrm = [tuple(r @ np.array(v)) for v in nrm]
		else:
			pos, nrm, uv, faces = fv.parse_mesh(fv.download(p["mesh"], cache, key))
			pos, nrm = fv.place(pos, nrm, part)
		meshes.append({"name": name, "pos": pos, "nrm": nrm, "uv": uv, "faces": faces, "color": [srgb_to_linear(c / 255) for c in p["color"]]})
	fv.write_glb(out, meshes)
	face_texture(os.path.splitext(out)[0] + "_face.png", char["parts"]["Head"]["color"])
	print(f"[fetch_character] {out}")


if __name__ == "__main__":
	main()
