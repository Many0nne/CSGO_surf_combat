# export_mesh_fbx.py
# Exporte les meshes d'un .blend en FBX pour tools/publish_asset.sh, avec les axes du dépôt : Roblox = (x, z, -y) Blender.
# Usage : blender -b <scene.blend> --factory-startup --python tools/export_mesh_fbx.py -- <sortie.fbx> [--only A,B]
#   [--no-turn]
#   --only : n'exporte que les objets nommés (ex. republier deux pièces de l'AWP, #335) ; sinon tous les meshes.
#   --no-turn : sans la rotation ci-dessous. Les meshes de l'AWP (assets/sniper) ont été publiés depuis un FBX brut :
#     une pièce qui les remplace (MeshPart:ApplyMesh) doit garder ce repère, sinon elle arrive tournée de 180°.
# Quels que soient axis_forward et bake_space_transform, l'importeur Roblox donne (-x, z, y) : seule une rotation de
# 180° autour de Z avant l'export corrige l'orientation. 1 unité Blender = 1 stud.
import math
import sys

import bpy
from mathutils import Matrix


# Cette méthode permet d'exporter la scène (ou les seuls objets nommés) en FBX lorsqu'elle est tournée pour compenser
# l'importeur Roblox. La scène reprend ensuite sa position d'origine, même si l'export échoue.
def export_scene(path, only=None, turned=True):
	roots = [obj for obj in bpy.context.scene.objects if obj.parent is None]
	saved = [obj.matrix_world.copy() for obj in roots]
	turn = Matrix.Rotation(math.pi if turned else 0.0, 4, "Z")
	if only:
		missing = [name for name in only if name not in bpy.context.scene.objects]
		if missing:
			sys.exit(f"export_mesh_fbx : objets introuvables {missing}")
		for obj in bpy.context.scene.objects:
			obj.select_set(obj.name in only)
	try:
		for obj in roots:
			obj.matrix_world = turn @ obj.matrix_world
		bpy.context.view_layer.update()
		bpy.ops.export_scene.fbx(
			filepath=path,
			apply_scale_options="FBX_SCALE_ALL",
			object_types={"MESH"},
			use_selection=bool(only),
		)
	finally:
		for obj, matrix in zip(roots, saved):
			obj.matrix_world = matrix


args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
if not args:
	sys.exit("usage : blender -b <scene.blend> --factory-startup --python tools/export_mesh_fbx.py -- <sortie.fbx> [--only A,B]")
export_scene(args[0], args[args.index("--only") + 1].split(",") if "--only" in args else None, "--no-turn" not in args)
