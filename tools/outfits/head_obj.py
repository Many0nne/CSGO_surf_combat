"""Convertit la coque de tête d'une tenue (#521, FBX publié en Model) en OBJ lisible par r15_bake.py, dans le repère
du jeu : Y vers le haut, avant = -Z, en studs (centrée à la lecture par r15_bake et board_render). Lancé par
Blender sans interface :

  blender -b --factory-startup --python tools/outfits/head_obj.py -- assets/outfits/mercure/MercureHead.fbx <sortie.obj>

Le FBX est importé tel quel (Blender le passe en Z vers le haut), puis réexporté en Y vers le haut et -Z devant, comme
le lit l'importeur de Roblox. Les UV sont celles du FBX (dépliage cylindrique de MERCURE).
"""

import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1 :]
src, dst = argv[0], argv[1]

for o in list(bpy.data.objects):
	bpy.data.objects.remove(o)
bpy.ops.import_scene.fbx(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in meshes:
	o.select_set(True)
	dims = o.dimensions
	print(f"[head_obj] {o.name} {len(o.data.vertices)} sommets, dimensions {tuple(round(d, 3) for d in dims)}")
bpy.ops.wm.obj_export(
	filepath=dst,
	export_selected_objects=True,
	export_uv=True,
	export_normals=True,
	export_materials=False,
	export_triangulated_mesh=True,
	forward_axis="NEGATIVE_Z",
	up_axis="Y",
)
print(f"[head_obj] -> {dst}")
