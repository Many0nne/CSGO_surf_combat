"""Cuit les cartes utilitaires d'une arme pour fabriquer ses skins (#268).

Pour chaque matériau texturé, écrit dans <sortie>/<MATERIAU>.npz trois cartes à la résolution de ses textures :
  pos    : position monde du texel, normalisée dans la boîte de l'arme (0..1 par axe)
  nrm    : normale monde géométrique, encodée n * 0.5 + 0.5
  aux    : R = occlusion ambiante, G = arête (1 = arête vive, via le nœud Bevel), B = couverture (1 = texel utilisé)
  oid    : objet du texel (i + 1 pour objects[i], 0 hors îlots), pour distinguer les pièces d'un même matériau
plus bbox.json (boîte de l'arme, en unités Blender). Les motifs des skins se calculent ensuite en numpy à partir de
ces cartes (make_skins.py), sans dépendre du découpage UV.

Usage :
  blender -b assets/sniper/Sniper.blend --factory-startup --python tools/skins/bake_maps.py -- <sortie>
  blender -b --factory-startup --python tools/skins/bake_maps.py -- <sortie> --glb <m9.glb>
"""

import json
import os
import sys

import bpy
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
OUT = argv[0]
GLB = argv[argv.index("--glb") + 1] if "--glb" in argv else None
RES = 1024
os.makedirs(OUT, exist_ok=True)

if GLB:
	for o in list(bpy.data.objects):
		bpy.data.objects.remove(o)
	bpy.ops.import_scene.gltf(filepath=GLB)

scene = bpy.context.scene
try:
	scene.render.engine = "CYCLES"
except TypeError as e:
	print(e)
scene.cycles.device = "CPU"
scene.render.bake.margin = 0
scene.render.bake.use_clear = True


# Cette méthode permet de regrouper les objets maillés par matériau texturé lorsqu'on prépare la cuisson.
def meshes_by_material():
	groups = {}
	for o in scene.objects:
		if o.type != "MESH" or not o.data.uv_layers or not o.data.materials:
			continue
		m = o.data.materials[0]
		if m is None or not m.use_nodes:
			continue
		# Sans .glb, seuls les matériaux texturés comptent (le .blend de l'AWP garde des matériaux de travail)
		if not GLB and not any(n.type == "TEX_IMAGE" for n in m.node_tree.nodes):
			continue
		groups.setdefault(m.name, []).append(o)
	return groups


groups = meshes_by_material()
objs = [o for g in groups.values() for o in g]
pts = np.array([o.matrix_world @ v.co for o in objs for v in o.data.vertices])
bmin, bmax = pts.min(0), pts.max(0)
size = bmax - bmin
diag = float(np.linalg.norm(size))
json.dump({"min": bmin.tolist(), "max": bmax.tolist(), "diag": diag}, open(os.path.join(OUT, "bbox.json"), "w"), indent=1)
print("[bake] bbox", bmin, bmax, "diag", diag)


# Cette méthode permet de brancher sur un matériau une émission calculée (position, normale ou occlusion/arête) et une
# image cible active lorsqu'on cuit une passe ; renvoie les nœuds ajoutés pour les retirer ensuite.
def setup_pass(mat, kind, img):
	nt = mat.node_tree
	out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output)
	added = []

	def add(t):
		n = nt.nodes.new(t)
		added.append(n)
		return n

	geo = add("ShaderNodeNewGeometry")
	emit = add("ShaderNodeEmission")
	if kind == "pos":
		sub = add("ShaderNodeVectorMath")
		sub.operation = "SUBTRACT"
		sub.inputs[1].default_value = bmin
		div = add("ShaderNodeVectorMath")
		div.operation = "DIVIDE"
		div.inputs[1].default_value = size
		nt.links.new(geo.outputs["Position"], sub.inputs[0])
		nt.links.new(sub.outputs[0], div.inputs[0])
		nt.links.new(div.outputs[0], emit.inputs["Color"])
	elif kind == "oid":
		info = add("ShaderNodeObjectInfo")
		div = add("ShaderNodeMath")
		div.operation = "DIVIDE"
		div.inputs[1].default_value = 64.0
		nt.links.new(info.outputs["Object Index"], div.inputs[0])
		nt.links.new(div.outputs[0], emit.inputs["Color"])
	elif kind == "nrm":
		mul = add("ShaderNodeVectorMath")
		mul.operation = "MULTIPLY_ADD"
		mul.inputs[1].default_value = (0.5, 0.5, 0.5)
		mul.inputs[2].default_value = (0.5, 0.5, 0.5)
		nt.links.new(geo.outputs["Normal"], mul.inputs[0])
		nt.links.new(mul.outputs[0], emit.inputs["Color"])
	else:
		ao = add("ShaderNodeAmbientOcclusion")
		ao.samples = 16
		ao.inputs["Distance"].default_value = diag * 0.04
		bev = add("ShaderNodeBevel")
		bev.samples = 8
		bev.inputs["Radius"].default_value = diag * 0.0025
		dot = add("ShaderNodeVectorMath")
		dot.operation = "DOT_PRODUCT"
		edge = add("ShaderNodeMath")
		edge.operation = "SUBTRACT"
		edge.inputs[0].default_value = 1.0
		comb = add("ShaderNodeCombineXYZ")
		comb.inputs[2].default_value = 1.0
		nt.links.new(bev.outputs["Normal"], dot.inputs[0])
		nt.links.new(geo.outputs["Normal"], dot.inputs[1])
		nt.links.new(dot.outputs["Value"], edge.inputs[1])
		nt.links.new(ao.outputs["AO"], comb.inputs[0])
		nt.links.new(edge.outputs[0], comb.inputs[1])
		nt.links.new(comb.outputs[0], emit.inputs["Color"])
	prev = [l.from_socket for l in nt.links if l.to_socket == out.inputs["Surface"]]
	nt.links.new(emit.outputs[0], out.inputs["Surface"])
	tex = add("ShaderNodeTexImage")
	tex.image = img
	nt.nodes.active = tex
	return added, prev, out


for mat_name, group in groups.items():
	mat = bpy.data.materials[mat_name]
	result = {}
	for i, o in enumerate(group):
		o.pass_index = i + 1  # oid : 0 hors îlots, i + 1 pour le i-ème objet de « objects »
	for kind, samples in (("pos", 4), ("nrm", 4), ("oid", 1), ("aux", 48)):
		img = bpy.data.images.new(f"bake_{mat_name}_{kind}", RES, RES, alpha=True, float_buffer=True)
		img.colorspace_settings.name = "Non-Color"
		img.generated_color = (0, 0, 0, 0)
		added, prev, out = setup_pass(mat, kind, img)
		scene.cycles.samples = samples
		bpy.ops.object.select_all(action="DESELECT")
		for o in group:
			o.select_set(True)
		bpy.context.view_layer.objects.active = group[0]
		bpy.ops.object.bake(type="EMIT")
		px = np.array(img.pixels[:], dtype=np.float32).reshape(RES, RES, 4)[::-1]  # ligne 0 = haut de l'image
		result[kind] = px
		nt = mat.node_tree
		for n in added:
			nt.nodes.remove(n)
		if prev:
			nt.links.new(prev[0], out.inputs["Surface"])
		bpy.data.images.remove(img)
		print(f"[bake] {mat_name} {kind} ok")
	# L'alpha cuit vaut 1 partout : la couverture se lit sur le canal B de la passe aux (1 émis, 0 hors îlots)
	aux = result["aux"][..., :3].copy()
	cov = (aux[..., 2] > 0.5).astype(np.float32)
	aux[..., 2] = cov
	np.savez_compressed(
		os.path.join(OUT, f"{mat_name}.npz"),
		pos=result["pos"][..., :3].astype(np.float16),
		nrm=result["nrm"][..., :3].astype(np.float16),
		aux=aux.astype(np.float16),
		oid=np.rint(result["oid"][..., 0] * 64).astype(np.uint8),
		objects=np.array([o.name for o in group]),
	)
	print(f"[bake] {mat_name} -> {len(group)} objets, couverture {cov.mean():.3f}")
