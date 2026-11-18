"""Convertit le FBX d'une coque de tête (#521) en OBJ dans l'espace de la tête du jeu, pour r15_bake.py --head.

Script Blender sans interface (un processus par commande) :
  "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup \
    --python tools/outfits/head_obj.py -- assets/outfits/mercure/MercureHead.fbx <sortie.obj>

Espace de sortie : studs, centre à l'origine, Y vers le haut, Z vers l'arrière (comme les pièces du rig dans
r15_bake). Le FBX a Z en haut dans Blender ; son avant et son arrière ne sont pas vérifiés dans le jeu : une coque
cuite par ce chemin doit être dessinée symétrique d'avant en arrière (cf. docs/assets.md, CHITINE). UV écrites en
convention Roblox (v vers le bas de l'image) : celle d'un FBX importé dans Studio.
"""

import sys

import bpy

src, out = sys.argv[sys.argv.index("--") + 1 :][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)
obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
me = obj.data
mw = obj.matrix_world
nm = mw.to_3x3().inverted().transposed()
uvl = me.uv_layers.active.data
with open(out, "w", encoding="utf-8") as f:
	for v in me.vertices:
		w = mw @ v.co
		f.write(f"v {-w.x:.6f} {w.z:.6f} {w.y:.6f}\n")  # Blender (x, y, z) -> jeu (-x, z, y) : rotation propre
	for loop in me.loops:
		uv = uvl[loop.index].uv
		n = (nm @ loop.normal).normalized()
		f.write(f"vt {uv.x:.6f} {1 - uv.y:.6f}\n")
		f.write(f"vn {-n.x:.6f} {n.z:.6f} {n.y:.6f}\n")
	for poly in me.polygons:
		corners = [f"{me.loops[li].vertex_index + 1}/{li + 1}/{li + 1}" for li in poly.loop_indices]
		f.write("f " + " ".join(corners) + "\n")
print(f"[head_obj] {len(me.vertices)} sommets, {len(me.polygons)} faces -> {out}")
