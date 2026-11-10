# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Reconstruit en .glb un viewmodel tel qu'il est dans le jeu, pour les aperçus three.js, sans Studio ni Blender.

Lit la place construite par Rojo (pièces, positions, tailles, ids des meshs et des cartes de la SurfaceAppearance),
télécharge meshs et textures par Open Cloud, et écrit le même résultat qu'export_glb.py : <sortie>.glb (un matériau par
pièce, nommé comme elle), <sortie>.json (manifeste) et les textures en PNG à côté. Sert aux armes dont on n'a pas la
source Blender (la M9, mesh du Creator Store) et à vérifier ce que le jeu affiche vraiment.

Clé : variable d'environnement ROBLOX_OPEN_CLOUD_KEY, avec le scope legacy-asset:manage (Asset Delivery) en plus de ceux
de publish_asset.sh. Les fichiers téléchargés sont gardés dans <dossier de sortie>/cache.

Usage (depuis la racine du worktree) : uv run tools/preview/fetch_viewmodel.py <Viewmodel> <sortie.glb> [place.rbxlx]
Sans place, lance `rojo build default.project.json` dans un fichier temporaire. Les bras (LeftArm, RightArm) sont ignorés.
"""

import json
import os
import struct
import subprocess
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

MAPS = {"ColorMapContent": "Color", "RoughnessMapContent": "Rough", "MetalnessMapContent": "Metal", "NormalMapContent": "Normal"}
SKIP_MODELS = {"LeftArm", "RightArm"}
API = "https://apis.roblox.com/asset-delivery-api/v1/assetId/"


# ---------------------------------------------------------------------------------------------------------------------
# Lecture de la place


def prop(item, name):
	props = item.find("Properties")
	return next((c for c in props if c.get("name") == name), None) if props is not None else None


def item_name(item):
	p = prop(item, "Name")
	return p.text if p is not None else ""


def asset_id(node):
	if node is None:
		return None
	uri = node.find("uri")
	text = (uri.text if uri is not None else node.text) or ""
	digits = "".join(ch for ch in text.split("rbxassetid://")[-1] if ch.isdigit())
	return digits or None


def vec3(node):
	return [float(node.find(k).text) for k in "XYZ"]


def cframe(node):
	pos = vec3(node)
	rot = [float(node.find(k).text) for k in ("R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")]
	return pos, rot


# Cette méthode permet de lister les MeshParts visibles d'un viewmodel (hors bras) avec leur placement et leurs ids de
# mesh et de cartes, lorsqu'on lit la place XML produite par Rojo.
def read_viewmodel(place_path, name):
	root = ET.parse(place_path).getroot()
	target = None
	for item in root.iter("Item"):
		if item.get("class") == "Folder" and item_name(item) == "ViewModels":
			target = next((c for c in item.findall("Item") if item_name(c) == name), None)
			if target is not None:
				break
	if target is None:
		raise SystemExit(f"[fetch_viewmodel] viewmodel introuvable dans ReplicatedStorage.ViewModels : {name}")

	parts = []

	def walk(item):
		for child in item.findall("Item"):
			cls = child.get("class")
			if cls == "Model" and item_name(child) in SKIP_MODELS:
				continue
			if cls == "MeshPart":
				transparency = prop(child, "Transparency")
				if transparency is None or float(transparency.text) < 1:
					maps = {}
					sa = next((c for c in child.findall("Item") if c.get("class") == "SurfaceAppearance"), None)
					if sa is not None:
						for key, ch in MAPS.items():
							aid = asset_id(prop(sa, key))
							if aid:
								maps[ch] = aid
					if "Color" not in maps:
						tex = asset_id(prop(child, "TextureContent"))
						if tex:
							maps["Color"] = tex
					color = prop(child, "Color3uint8")
					rgb = int(color.text) if color is not None else 0xA3A2A5
					parts.append(
						{
							"name": item_name(child),
							"mesh": asset_id(prop(child, "MeshContent")),
							"cframe": cframe(prop(child, "CFrame")),
							"size": vec3(prop(child, "size")),
							"maps": maps,
							"color": [((rgb >> 16) & 255) / 255, ((rgb >> 8) & 255) / 255, (rgb & 255) / 255],
						}
					)
			walk(child)

	walk(target)
	return parts


# ---------------------------------------------------------------------------------------------------------------------
# Téléchargement


# Cette méthode permet de télécharger un asset Roblox par Open Cloud (lien signé, puis contenu) lorsqu'il n'est pas déjà
# dans le cache.
def download(aid, cache_dir, key):
	path = os.path.join(cache_dir, aid)
	if os.path.exists(path):
		with open(path, "rb") as f:
			return f.read()
	req = urllib.request.Request(API + aid, headers={"x-api-key": key})
	try:
		with urllib.request.urlopen(req) as r:
			location = json.load(r)["location"]
	except urllib.error.HTTPError as e:
		body = e.read().decode("utf-8", "replace")
		hint = " (ajouter le scope legacy-asset:manage à la clé)" if "Scope" in body else ""
		raise SystemExit(f"[fetch_viewmodel] asset {aid} : HTTP {e.code} {body.strip()}{hint}")
	with urllib.request.urlopen(location) as r:
		data = r.read()
	if data[:2] == b"\x1f\x8b":
		import gzip

		data = gzip.decompress(data)
	os.makedirs(cache_dir, exist_ok=True)
	with open(path, "wb") as f:
		f.write(data)
	return data


# ---------------------------------------------------------------------------------------------------------------------
# Format de mesh Roblox (versions 2 à 7, sans compression Draco)


def read_vertices(buf, off, count, stride):
	pos, nrm, uv = [], [], []
	for i in range(count):
		base = off + i * stride
		px, py, pz, nx, ny, nz, u, v = struct.unpack_from("<8f", buf, base)
		pos.append((px, py, pz))
		nrm.append((nx, ny, nz))
		uv.append((u, v))
	return pos, nrm, uv, off + count * stride


def read_faces(buf, off, count):
	faces = list(struct.unpack_from(f"<{count * 3}I", buf, off))
	return faces, off + count * 12


# Cette méthode permet de restreindre les faces au niveau de détail le plus fin lorsque le mesh en contient plusieurs.
def lod0(faces, lods):
	if len(lods) >= 2 and lods[1] > lods[0]:
		return faces[lods[0] * 3 : lods[1] * 3]
	return faces


# Cette méthode permet de décoder un mesh Roblox (positions, normales, UV, triangles du LOD 0) lorsqu'on reconstruit une
# pièce ; les versions 6 et 7 compressées en Draco ne sont pas prises en charge.
def parse_mesh(buf):
	nl = buf.index(b"\n")
	version = buf[:nl].decode("ascii").strip()
	off = nl + 1
	major = version.split(" ")[1].split(".")[0]
	if major in ("2", "3"):
		header_size, vsize = struct.unpack_from("<HB", buf, off)
		if major == "2":
			nverts, nfaces = struct.unpack_from("<II", buf, off + 4)
			nlods = 0
		else:
			nlods, nverts, nfaces = struct.unpack_from("<HII", buf, off + 6)
		off += header_size
		pos, nrm, uv, off = read_vertices(buf, off, nverts, vsize)
		faces, off = read_faces(buf, off, nfaces)
		lods = list(struct.unpack_from(f"<{nlods}I", buf, off)) if nlods else []
		return pos, nrm, uv, lod0(faces, lods)
	if major in ("4", "5"):
		header_size, _lod_type, nverts, nfaces, nlods, nbones = struct.unpack_from("<HHIIHH", buf, off)
		off += header_size
		pos, nrm, uv, off = read_vertices(buf, off, nverts, 40)
		if nbones:
			off += nverts * 8
		faces, off = read_faces(buf, off, nfaces)
		lods = list(struct.unpack_from(f"<{nlods}I", buf, off))
		return pos, nrm, uv, lod0(faces, lods)
	if major in ("6", "7"):
		pos = nrm = uv = faces = None
		lods = []
		while off + 16 <= len(buf):
			ctype = buf[off : off + 8].decode("ascii", "replace")
			cver, csize = struct.unpack_from("<II", buf, off + 8)
			data = off + 16
			if ctype == "COREMESH":
				if cver != 1:
					raise SystemExit("[fetch_viewmodel] mesh compressé (Draco) : non pris en charge")
				nverts = struct.unpack_from("<I", buf, data)[0]
				pos, nrm, uv, p = read_vertices(buf, data + 4, nverts, 40)
				nfaces = struct.unpack_from("<I", buf, p)[0]
				faces, _ = read_faces(buf, p + 4, nfaces)
			elif ctype == "LODS\0\0\0\0":
				nlods = struct.unpack_from("<I", buf, data + 3)[0]
				lods = list(struct.unpack_from(f"<{nlods}I", buf, data + 7))
			off = data + csize
		if pos is None:
			raise SystemExit("[fetch_viewmodel] mesh sans bloc COREMESH")
		return pos, nrm, uv, lod0(faces, lods)
	raise SystemExit(f"[fetch_viewmodel] version de mesh non prise en charge : {version}")


# ---------------------------------------------------------------------------------------------------------------------
# Écriture glTF


# Cette méthode permet de placer les sommets d'un mesh dans le monde comme Roblox le fait (boîte du mesh étirée à la
# taille de la pièce et centrée sur son CFrame) lorsqu'on assemble les pièces.
def place(pos, nrm, part):
	xs, ys, zs = zip(*pos)
	lo = (min(xs), min(ys), min(zs))
	hi = (max(xs), max(ys), max(zs))
	center = [(lo[i] + hi[i]) / 2 for i in range(3)]
	scale = [part["size"][i] / (hi[i] - lo[i]) if hi[i] > lo[i] else 1 for i in range(3)]
	(px, py, pz), r = part["cframe"]

	def rotate(x, y, z):
		return (r[0] * x + r[1] * y + r[2] * z, r[3] * x + r[4] * y + r[5] * z, r[6] * x + r[7] * y + r[8] * z)

	out_pos = []
	for x, y, z in pos:
		lx, ly, lz = ((x - center[0]) * scale[0], (y - center[1]) * scale[1], (z - center[2]) * scale[2])
		wx, wy, wz = rotate(lx, ly, lz)
		out_pos.append((wx + px, wy + py, wz + pz))
	out_nrm = []
	for x, y, z in nrm:
		nx, ny, nz = rotate(x / scale[0], y / scale[1], z / scale[2])
		length = (nx * nx + ny * ny + nz * nz) ** 0.5 or 1
		out_nrm.append((nx / length, ny / length, nz / length))
	return out_pos, out_nrm


def write_glb(path, meshes):
	blob = bytearray()
	views, accessors, gl_meshes, nodes, materials = [], [], [], [], []

	def add(data, target, comp, typ, count, minmax=None):
		while len(blob) % 4:
			blob.append(0)
		views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
		blob.extend(data)
		acc = {"bufferView": len(views) - 1, "componentType": comp, "count": count, "type": typ}
		if minmax:
			acc["min"], acc["max"] = minmax
		accessors.append(acc)
		return len(accessors) - 1

	for m in meshes:
		pos, nrm, uv, faces = m["pos"], m["nrm"], m["uv"], m["faces"]
		flat = [c for p in pos for c in p]
		mins = [min(p[i] for p in pos) for i in range(3)]
		maxs = [max(p[i] for p in pos) for i in range(3)]
		a_pos = add(struct.pack(f"<{len(flat)}f", *flat), 34962, 5126, "VEC3", len(pos), (mins, maxs))
		a_nrm = add(struct.pack(f"<{len(pos) * 3}f", *[c for n in nrm for c in n]), 34962, 5126, "VEC3", len(pos))
		a_uv = add(struct.pack(f"<{len(pos) * 2}f", *[c for t in uv for c in t]), 34962, 5126, "VEC2", len(pos))
		a_idx = add(struct.pack(f"<{len(faces)}I", *faces), 34963, 5125, "SCALAR", len(faces))
		materials.append(
			{
				"name": m["name"],
				"pbrMetallicRoughness": {"baseColorFactor": [*m["color"], 1], "metallicFactor": 0, "roughnessFactor": 1},
			}
		)
		gl_meshes.append(
			{
				"name": m["name"],
				"primitives": [
					{
						"attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv},
						"indices": a_idx,
						"material": len(materials) - 1,
					}
				],
			}
		)
		nodes.append({"name": m["name"], "mesh": len(gl_meshes) - 1})

	while len(blob) % 4:
		blob.append(0)
	gltf = {
		"asset": {"version": "2.0", "generator": "tools/preview/fetch_viewmodel.py"},
		"scene": 0,
		"scenes": [{"nodes": list(range(len(nodes)))}],
		"nodes": nodes,
		"meshes": gl_meshes,
		"materials": materials,
		"accessors": accessors,
		"bufferViews": views,
		"buffers": [{"byteLength": len(blob)}],
	}
	js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
	js += b" " * (-len(js) % 4)
	with open(path, "wb") as f:
		f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
		f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
		f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))


# Cette méthode permet d'écrire le dépliage UV d'une pièce en SVG (même rendu qu'export_glb.py) lorsqu'on prépare une
# texture pour elle.
def write_uv_svg(path, uv, faces):
	with open(path, "w", encoding="utf-8") as f:
		f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">\n')
		f.write('<rect width="1024" height="1024" fill="#202020"/>\n<g fill="#4a6" fill-opacity="0.25" stroke="#cfc" stroke-width="0.4">\n')
		for i in range(0, len(faces), 3):
			pts = " ".join(f"{uv[k][0] * 1024:.1f},{uv[k][1] * 1024:.1f}" for k in faces[i : i + 3])
			f.write(f'<polygon points="{pts}"/>\n')
		f.write("</g></svg>\n")


def image_ext(data):
	if data[:8] == b"\x89PNG\r\n\x1a\n":
		return ".png"
	if data[:3] == b"\xff\xd8\xff":
		return ".jpg"
	if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
		return ".webp"
	return ".bin"


def main():
	if len(sys.argv) not in (3, 4):
		raise SystemExit("usage : uv run tools/preview/fetch_viewmodel.py <Viewmodel> <sortie.glb> [place.rbxlx]")
	name, out = sys.argv[1], os.path.abspath(sys.argv[2])
	key = os.environ.get("ROBLOX_OPEN_CLOUD_KEY")
	if not key:
		raise SystemExit("[fetch_viewmodel] variable d'environnement ROBLOX_OPEN_CLOUD_KEY absente")
	out_dir = os.path.dirname(out)
	cache_dir = os.path.join(out_dir, "cache")
	os.makedirs(out_dir, exist_ok=True)

	if len(sys.argv) == 4:
		place_path = sys.argv[3]
	else:
		place_path = os.path.join(tempfile.mkdtemp(), "place.rbxlx")
		subprocess.run(["rojo", "build", "default.project.json", "-o", place_path], check=True, stdout=subprocess.DEVNULL)

	parts = read_viewmodel(place_path, name)
	base = os.path.splitext(out)[0]
	meshes, manifest = [], {"glb": os.path.basename(out), "textures": ".", "source": f"ViewModels.{name}", "materials": {}}
	for part in parts:
		if not part["mesh"]:
			print(f"[fetch_viewmodel] {part['name']} : pas de mesh, ignorée")
			continue
		pos, nrm, uv, faces = parse_mesh(download(part["mesh"], cache_dir, key))
		pos, nrm = place(pos, nrm, part)
		meshes.append({"name": part["name"], "pos": pos, "nrm": nrm, "uv": uv, "faces": faces, "color": part["color"]})
		maps = {}
		for ch, aid in part["maps"].items():
			data = download(aid, cache_dir, key)
			file = f"{os.path.basename(base)}_{part['name']}_{ch}{image_ext(data)}"
			with open(os.path.join(out_dir, file), "wb") as f:
				f.write(data)
			maps[ch] = file
		uv_file = f"{os.path.basename(base)}_uv_{part['name']}.svg"
		write_uv_svg(os.path.join(out_dir, uv_file), uv, faces)
		manifest["materials"][part["name"]] = {"objects": [part["name"]], "maps": maps, "assets": part["maps"], "uv": uv_file}
		print(f"[fetch_viewmodel] {part['name']} : {len(pos)} sommets, {len(faces) // 3} triangles, cartes {', '.join(maps) or 'aucune'}")
	if not meshes:
		raise SystemExit("[fetch_viewmodel] aucune pièce avec un mesh")
	write_glb(out, meshes)
	with open(base + ".json", "w", encoding="utf-8") as f:
		json.dump(manifest, f, indent=2, ensure_ascii=False)
	print(f"[fetch_viewmodel] {out}")


sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")
main()
