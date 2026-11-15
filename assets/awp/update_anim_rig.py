"""Remplace les pièces de l'arme du rig d'animation (AWP_Viewmodel_Anims.blend) par celles de assets/awp/AWP.blend (#403).

`blender -b assets/awp_viewmodel/AWP_Viewmodel_Anims.blend --python assets/awp/update_anim_rig.py -- assets/awp/AWP.blend`
Enregistre le .blend du rig. Chaque objet garde son os et son orientation ; son origine passe au centre de la nouvelle
pièce (la CFrame d'une MeshPart Roblox est le centre de sa boîte), ce que lit run_build.py pour frames_<Nom>.json.
Repère : caméra du viewmodel au repos = (1,09 + Y, 2,9 - X, -0,65 + Z) du modèle (origine du modèle = Joint).
"""

import os
import sys

import bpy
from mathutils import Matrix, Vector

PARTS = ("Barrel", "Bolt", "Fittings", "Handguard", "Handle", "Magazine", "Scope", "ScopeLens", "Stock", "Trigger")


def to_cam(v):
	"""Cette méthode permet de passer un point du repère du modèle au repère caméra du rig au repos."""
	return Vector((1.09 + v.y, 2.9 - v.x, -0.65 + v.z))


def main(src):
	"""Cette méthode permet de charger les maillages du nouveau modèle et de les poser sur les objets du rig."""
	with bpy.data.libraries.load(src, link=False) as (data_from, data_to):
		data_to.meshes = [m for m in data_from.meshes if m in PARTS]
	new = {m.name.split(".")[0]: m for m in data_to.meshes}
	rig = bpy.data.objects["Rig"]
	saved = rig.data.pose_position
	rig.data.pose_position = "REST"
	bpy.context.view_layer.update()
	for name in PARTS:
		ob = bpy.data.objects[name]
		mesh = new[name]
		vs = [v.co.copy() for v in mesh.vertices]
		lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
		hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
		center = to_cam((lo + hi) / 2)
		rot = ob.matrix_world.to_3x3().normalized()
		inv = rot.inverted()
		for v in mesh.vertices:
			v.co = inv @ (to_cam(v.co) - center)
		old = ob.data
		ob.data = mesh
		mesh.name = name
		if old.users == 0:
			bpy.data.meshes.remove(old)
		ob.matrix_world = Matrix.Translation(center) @ rot.to_4x4()
		print(f"[rig] {name} centre {tuple(round(c, 3) for c in center)}")
	rig.data.pose_position = saved
	bpy.ops.wm.save_mainfile()


main(os.path.abspath(sys.argv[sys.argv.index("--") + 1]))
