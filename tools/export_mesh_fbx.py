# export_mesh_fbx.py
# Exporte les meshes d'un .blend en FBX pour tools/publish_asset.sh, avec les axes du dépôt : Roblox = (x, z, -y) Blender.
# Usage : blender -b <scene.blend> --factory-startup --python tools/export_mesh_fbx.py -- <sortie.fbx>
# Quels que soient axis_forward et bake_space_transform, l'importeur Roblox donne (-x, z, y) : seule une rotation de
# 180° autour de Z avant l'export corrige l'orientation. 1 unité Blender = 1 stud.
import math
import sys

import bpy
from mathutils import Matrix


# Cette méthode permet d'exporter la scène en FBX lorsqu'elle est tournée pour compenser l'importeur Roblox.
# La scène reprend ensuite sa position d'origine, même si l'export échoue.
def export_scene(path):
	roots = [obj for obj in bpy.context.scene.objects if obj.parent is None]
	saved = [obj.matrix_world.copy() for obj in roots]
	turn = Matrix.Rotation(math.pi, 4, "Z")
	try:
		for obj in roots:
			obj.matrix_world = turn @ obj.matrix_world
		bpy.context.view_layer.update()
		bpy.ops.export_scene.fbx(
			filepath=path,
			apply_scale_options="FBX_SCALE_ALL",
			object_types={"MESH"},
		)
	finally:
		for obj, matrix in zip(roots, saved):
			obj.matrix_world = matrix


if "--" not in sys.argv or len(sys.argv) <= sys.argv.index("--") + 1:
	sys.exit("usage : blender -b <scene.blend> --factory-startup --python tools/export_mesh_fbx.py -- <sortie.fbx>")
export_scene(sys.argv[sys.argv.index("--") + 1])
