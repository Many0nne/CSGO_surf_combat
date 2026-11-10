"""Exporte le modèle d'une arme en .glb pour les aperçus three.js, sans toucher au Blender ouvert.

Le .glb garde la géométrie, les UV et les noms de matériaux, sans images : les textures sont fournies à part, en PNG, par
make_preview.py. À côté du .glb, un manifeste <sortie>.json liste pour chaque matériau ses objets et ses textures
(Color, Rough, Metal, Normal), et un <sortie>_uv_<MATERIAU>.svg montre le dépliage UV, pour dessiner une texture qui tombe
au bon endroit.

Usage (depuis la racine du worktree) :
  blender -b <scene.blend> --factory-startup --python tools/preview/export_glb.py -- <sortie.glb> [dossier_textures]
"""

import json
import os
import sys

import addon_utils
import bpy

# Entrée du Principled BSDF -> nom de la carte (mêmes noms que les PNG du dépôt et que la SurfaceAppearance de Roblox).
CHANNELS = {"Base Color": "Color", "Roughness": "Rough", "Metallic": "Metal", "Normal": "Normal"}


# Cette méthode permet de retrouver le nœud image qui alimente une entrée du BSDF lorsque des nœuds intermédiaires
# (Normal Map, Separate Color…) s'intercalent entre les deux.
def image_feeding(socket, depth=0):
	if depth > 4 or not socket.is_linked:
		return None
	node = socket.links[0].from_node
	if node.type == "TEX_IMAGE":
		return node.image
	for inp in node.inputs:
		img = image_feeding(inp, depth + 1)
		if img:
			return img
	return None


# Cette méthode permet de lister les textures d'un matériau par carte lorsqu'il utilise un Principled BSDF.
def material_maps(mat):
	maps = {}
	if not mat or not mat.node_tree:
		return maps
	bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
	if not bsdf:
		return maps
	for inp in bsdf.inputs:
		if inp.name in CHANNELS:
			img = image_feeding(inp)
			if img:
				maps[CHANNELS[inp.name]] = os.path.basename(bpy.path.abspath(img.filepath))
	return maps


# Cette méthode permet d'écrire le dépliage UV de tous les objets d'un matériau en SVG (carré 1024, origine en haut à
# gauche comme dans une image) lorsqu'on prépare une texture.
def write_uv_svg(path, objects, mat_name):
	polys = []
	for obj in objects:
		me = obj.data
		uv = me.uv_layers.active
		if not uv:
			continue
		for poly in me.polygons:
			slot = obj.material_slots[poly.material_index] if obj.material_slots else None
			if not slot or not slot.material or slot.material.name != mat_name:
				continue
			pts = [uv.data[i].uv for i in poly.loop_indices]
			polys.append(" ".join(f"{p.x * 1024:.1f},{(1 - p.y) * 1024:.1f}" for p in pts))
	if not polys:
		return False
	with open(path, "w", encoding="utf-8") as f:
		f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">\n')
		f.write('<rect width="1024" height="1024" fill="#202020"/>\n<g fill="#4a6" fill-opacity="0.25" stroke="#cfc" stroke-width="0.4">\n')
		for p in polys:
			f.write(f'<polygon points="{p}"/>\n')
		f.write("</g></svg>\n")
	return True


def main():
	argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
	if not argv:
		raise SystemExit("usage : -- <sortie.glb> [dossier_textures]")
	out = os.path.abspath(argv[0])
	textures = os.path.abspath(argv[1]) if len(argv) > 1 else None
	os.makedirs(os.path.dirname(out), exist_ok=True)

	meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.visible_get()]
	by_mat = {}
	for obj in meshes:
		for slot in obj.material_slots:
			if slot.material:
				by_mat.setdefault(slot.material.name, []).append(obj)

	manifest = {"glb": os.path.basename(out), "textures": textures, "materials": {}}
	base = os.path.splitext(out)[0]
	for name, objs in sorted(by_mat.items()):
		maps = material_maps(bpy.data.materials[name])
		uv_svg = None
		if write_uv_svg(f"{base}_uv_{name}.svg", objs, name):
			uv_svg = os.path.basename(f"{base}_uv_{name}.svg")
		manifest["materials"][name] = {"objects": sorted(o.name for o in objs), "maps": maps, "uv": uv_svg}

	addon_utils.enable("io_scene_gltf2")
	bpy.ops.object.select_all(action="DESELECT")
	for obj in meshes:
		obj.select_set(True)
	bpy.ops.export_scene.gltf(
		filepath=out,
		export_format="GLB",
		use_selection=True,
		export_apply=True,
		export_materials="EXPORT",
		export_image_format="NONE",
		export_cameras=False,
		export_lights=False,
		export_animations=False,
	)
	with open(base + ".json", "w", encoding="utf-8") as f:
		json.dump(manifest, f, indent=2, ensure_ascii=False)
	print(f"[export_glb] {out} : {len(meshes)} objets, matériaux {', '.join(manifest['materials'])}")


main()
