"""Exporte le mesh d'une coque de tête de tenue (#521) en JSON pour tools/outfits/r15_bake.py (option --head).

La tête du rig est une pièce à SpecialMesh, sans UV : une tenue qui change la tête la recouvre d'une coque (MeshPart).
Ce script lit la coque (FBX) dans Blender sans interface et écrit, dans l'espace de la pièce Roblox en studs (X à
droite, Y en haut, avant = -Z, centrée sur sa boîte), les positions, normales, UV (v vers le bas, convention Roblox)
et triangles. Coque de MERCURE : assets/outfits/mercure/MercureHead.fbx (Model 92982065353684), réutilisable par les
autres tenues avec leur propre carte.

Usage :
  blender -b --factory-startup --python tools/outfits/head_mesh.py -- <coque.fbx> <sortie.json>
"""

import json
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1 :]
SRC, OUT = argv[0], argv[1]

for o in list(bpy.data.objects):
	bpy.data.objects.remove(o)
bpy.ops.import_scene.fbx(filepath=SRC)
obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
mesh = obj.data
mesh.calc_loop_triangles()
uv_layer = mesh.uv_layers.active.data
mw = obj.matrix_world
nw = mw.to_3x3().inverted().transposed()


# Cette méthode permet de repasser un vecteur de Blender (Z en haut) dans les axes du FBX, ceux que Roblox lit
# (Y en haut), en inversant la conversion de l'import FBX (avant -Z, haut Y) lorsqu'on écrit la coque pour la cuisson.
def to_roblox(v):
	return [v.x, v.z, -v.y]


pos, nrm, uv, tris = [], [], [], []
for tri in mesh.loop_triangles:
	for li in tri.loops:
		loop = mesh.loops[li]
		pos.append(to_roblox(mw @ mesh.vertices[loop.vertex_index].co))
		n = (nw @ loop.normal).normalized()
		nrm.append(to_roblox(n))
		u, v = uv_layer[li].uv
		uv.append([u, 1 - v])
	tris.append([len(pos) - 3, len(pos) - 2, len(pos) - 1])

lo = [min(p[i] for p in pos) for i in range(3)]
hi = [max(p[i] for p in pos) for i in range(3)]
center = [(a + b) / 2 for a, b in zip(lo, hi)]
pos = [[p[i] - center[i] for i in range(3)] for p in pos]
with open(OUT, "w") as f:
	json.dump({"pos": pos, "nrm": nrm, "uv": uv, "tris": tris}, f)
print(f"[head_mesh] {len(tris)} triangles, taille {[round(b - a, 3) for a, b in zip(lo, hi)]} -> {OUT}")
