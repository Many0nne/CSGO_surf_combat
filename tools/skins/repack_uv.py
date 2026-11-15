"""Redéplie les UV d'un matériau (pièces qui partagent une texture) pour remplir la texture (#335).

L'aplatissement d'origine est gardé : chaque îlot est seulement coupé en tronçons le long de son grand axe quand il est
trop long pour tenir à la densité visée, puis tous les morceaux sont rangés à plat par le packer de Blender (rotation
alignée sur les axes, échelle commune). Chaque tronçon ne subit donc qu'une similitude (rotation, échelle, translation) :
remap_textures.py y transpose exactement les cartes d'origine.

Écrit <sortie.blend> (UV remplacés, coutures marquées sur les coupes) et <correspondance.npz> : pour chaque objet, les
triangles de l'ancien et du nouveau dépliage (<objet>_old, <objet>_new, (N, 3, 2), v vers le haut).

Usage :
  blender -b assets/sniper/Sniper.blend --factory-startup --python tools/skins/repack_uv.py -- \
    <sortie.blend> <correspondance.npz> Stock,Handguard [--margin-px 6] [--max-len 1.1] [--fill 0.72]
"""

import math
import sys

import bpy
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1 :]
OUT_BLEND, OUT_NPZ, NAMES = argv[0], argv[1], argv[2].split(",")


# Cette méthode permet de lire une option --nom valeur de la ligne de commande lorsqu'elle est donnée.
def opt(name, default):
	return type(default)(argv[argv.index(name) + 1]) if name in argv else default


RES = 1024
MARGIN_PX = opt("--margin-px", 6.0)
# Longueur maximale d'un tronçon, en fraction de la texture à l'échelle estimée (l'échelle finale est plus petite :
# 1.1 donne sur l'AWP 4 coupes et la même densité que des tronçons plus courts)
MAX_LEN = opt("--max-len", 1.1)
FILL = opt("--fill", 0.72)  # remplissage visé, pour estimer l'échelle finale avant de couper


# Cette méthode permet de lire les UV par coin de face d'un maillage, en tableau (nb de coins, 2).
def get_uv(me, layer):
	a = np.empty(len(me.loops) * 2, np.float64)
	me.uv_layers[layer].uv.foreach_get("vector", a)
	return a.reshape(-1, 2)


# Cette méthode permet d'écrire les UV par coin de face d'un maillage depuis un tableau (nb de coins, 2).
def set_uv(me, layer, uv):
	me.uv_layers[layer].uv.foreach_set("vector", uv.astype(np.float32).ravel())
	me.update()


# Cette méthode permet de grouper les faces d'un maillage en îlots UV (faces reliées par une arête dont les deux coins
# ont les mêmes UV des deux côtés) ; renvoie l'îlot de chaque face.
def islands(me, uv):
	parent = list(range(len(me.polygons)))

	def find(i):
		while parent[i] != i:
			parent[i] = parent[parent[i]]
			i = parent[i]
		return i

	by_edge = {}
	for p in me.polygons:
		n = p.loop_total
		for k in range(n):
			li = p.loop_start + k
			lj = p.loop_start + (k + 1) % n
			v0, v1 = me.loops[li].vertex_index, me.loops[lj].vertex_index
			key = (min(v0, v1), max(v0, v1))
			uvs = {v0: uv[li], v1: uv[lj]}
			by_edge.setdefault(key, []).append((p.index, uvs))
	for (v0, v1), sides in by_edge.items():
		if len(sides) != 2:
			continue
		(fa, ua), (fb, ub) = sides
		if np.allclose(ua[v0], ub[v0], atol=1e-6) and np.allclose(ua[v1], ub[v1], atol=1e-6):
			parent[find(fa)] = find(fb)
	roots = [find(i) for i in range(len(me.polygons))]
	_, isl = np.unique(roots, return_inverse=True)
	return isl


# Cette méthode permet de calculer l'aire UV de chaque face (formule du lacet sur ses coins).
def face_uv_areas(me, uv):
	out = np.zeros(len(me.polygons))
	for p in me.polygons:
		q = uv[p.loop_start : p.loop_start + p.loop_total]
		out[p.index] = 0.5 * abs(np.dot(q[:, 0], np.roll(q[:, 1], -1)) - np.dot(q[:, 1], np.roll(q[:, 0], -1)))
	return out


objs = [bpy.data.objects[n] for n in NAMES]
for o in objs:
	me = o.data
	src = me.uv_layers.active.name
	if "UVMap_old" in me.uv_layers:
		me.uv_layers.remove(me.uv_layers["UVMap_old"])
	old = me.uv_layers.new(name="UVMap_old", do_init=False)
	old_uv = get_uv(me, src)
	set_uv(me, old.name, old_uv)
	me.uv_layers.active = me.uv_layers[src]
	me.uv_layers[src].active_render = True

# Échelle finale estimée (aire UV totale ramenée au remplissage visé) : sert à décider quels îlots couper
total_area = sum(face_uv_areas(o.data, get_uv(o.data, "UVMap_old")).sum() for o in objs)
scale = math.sqrt(FILL / total_area)
print(f"[repack] aire UV {total_area:.4f}, échelle estimée x{scale:.2f}")

group_offset = 0
for o in objs:
	me = o.data
	uv = get_uv(me, "UVMap_old")
	isl = islands(me, uv)
	face_group = np.zeros(len(me.polygons), np.int64)
	centers = np.array([uv[p.loop_start : p.loop_start + p.loop_total].mean(0) for p in me.polygons])
	n_cut = 0
	for i in range(isl.max() + 1):
		faces = np.nonzero(isl == i)[0]
		pts = np.concatenate([uv[me.polygons[f].loop_start : me.polygons[f].loop_start + me.polygons[f].loop_total] for f in faces])
		c = pts.mean(0)
		_, _, vt = np.linalg.svd(pts - c, full_matrices=False)
		axis = vt[0]
		proj = (pts - c) @ axis
		length = (proj.max() - proj.min()) * scale
		k = max(1, math.ceil(length / MAX_LEN))
		fproj = (centers[faces] - c) @ axis
		seg = np.clip(((fproj - proj.min()) / (proj.max() - proj.min() + 1e-12) * k).astype(int), 0, k - 1)
		face_group[faces] = group_offset + seg
		group_offset += k
		n_cut += k - 1
	# Coutures sur les coupes, et tronçons écartés les uns des autres pour que le packer les voie comme des îlots
	new_uv = uv.copy()
	for p in me.polygons:
		new_uv[p.loop_start : p.loop_start + p.loop_total, 0] += 4.0 * face_group[p.index]
	edge_faces = {}
	for p in me.polygons:
		for e in p.edge_keys:
			edge_faces.setdefault(e, []).append(p.index)
	cut_keys = {e for e, fs in edge_faces.items() if len(fs) == 2 and face_group[fs[0]] != face_group[fs[1]]}
	for e in me.edges:
		if e.key in cut_keys:
			e.use_seam = True
	set_uv(me, me.uv_layers.active.name, new_uv)
	print(f"[repack] {o.name} : {isl.max() + 1} îlots, {n_cut} coupes")

# Rangement : toutes les faces des pièces, en édition multi-objets
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
	o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.context.scene.tool_settings.use_uv_select_sync = True
bpy.ops.uv.select_all(action="SELECT")
bpy.ops.uv.pack_islands(
	udim_source="CLOSEST_UDIM",
	rotate=True,
	rotate_method="AXIS_ALIGNED",
	scale=True,
	merge_overlap=False,
	margin_method="FRACTION",
	margin=MARGIN_PX / RES,
	pin=False,
	shape_method="CONCAVE",
)
bpy.ops.object.mode_set(mode="OBJECT")

# Bilan (densité en px par unité, comme avant) et correspondance des triangles
dump = {}
area_uv = area_3d = old_area = 0.0
for o in objs:
	me = o.data
	me.calc_loop_triangles()
	tl = np.array([t.loops[:] for t in me.loop_triangles])
	new = get_uv(me, me.uv_layers.active.name)
	old = get_uv(me, "UVMap_old")
	dump[o.name + "_old"] = old[tl].astype(np.float32)
	dump[o.name + "_new"] = new[tl].astype(np.float32)
	if new.min() < -1e-4 or new.max() > 1 + 1e-4:
		raise SystemExit(f"[repack] {o.name} : UV hors de 0..1 ({new.min():.3f}..{new.max():.3f})")
	mw = o.matrix_world
	for t in me.loop_triangles:
		a, b, c = (mw @ me.vertices[v].co for v in t.vertices)
		area_3d += (b - a).cross(c - a).length / 2
	area_uv += face_uv_areas(me, new).sum()
	old_area += face_uv_areas(me, old).sum()
	me.uv_layers.remove(me.uv_layers["UVMap_old"])
np.savez_compressed(OUT_NPZ, **dump)
before = math.sqrt(old_area / area_3d) * RES
after = math.sqrt(area_uv / area_3d) * RES
print(f"[repack] couverture {old_area:.3f} -> {area_uv:.3f}, densité {before:.0f} -> {after:.0f} px/unité (x{after / before:.2f})")

# Chemins des textures relatifs au .blend (ils pointaient vers un ancien dossier de travail)
for img in bpy.data.images:
	name = bpy.path.basename(img.filepath)
	if img.filepath and name.split("_")[0] in ("WOOD", "METAL", "SCOPE"):
		img.filepath = "//textures/" + name
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print(f"[repack] {OUT_BLEND}")
