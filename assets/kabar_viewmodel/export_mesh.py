"""Exporte les trois meshes du Ka-Bar en FBX, à l'échelle de la M9 et centrés sur le manche, pour tools/publish_asset.sh.

  blender -b --factory-startup --python assets/kabar_viewmodel/export_mesh.py -- <sortie.fbx>

Unité du modèle : le pouce. 1 pouce = 0,3125 stud donne 3,73 studs de long (la M9 en fait 3,72). L'origine est le centre du
manche en cuir : c'est l'origine de la Handle du viewmodel (repère de prise de build_viewmodel.py). Le FBX garde les axes de
Blender, tools/export_mesh_fbx.py compense l'importeur Roblox ; l'orientation finale se règle dans l'assemblage Studio.
"""

import os
import sys

import bpy

STUD_PER_INCH = 0.3125
HANDLE_CENTER_Y = -2.465  # centre du manche (y de -4,38 à -0,55) dans le repère du modèle, en pouces

root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
out = sys.argv[sys.argv.index("--") + 1]
with open(os.path.join(root, "assets", "kabar_knife", "build_knife.py"), encoding="utf-8") as fh:
	exec(fh.read(), {"__name__": "kabar_build"})

# Cette méthode permet de retirer le cube de la scène par défaut lorsque le FBX est exporté (sinon il devient un MeshPart de plus).
for ob in [o for o in bpy.data.objects if o.type == "MESH" and not o.name.startswith("KaBar_")]:
	bpy.data.objects.remove(ob, do_unlink=True)

# Cette méthode permet de recentrer et de réduire chaque objet lorsque le modèle est exporté (sommets modifiés, pas l'objet).
for ob in [o for o in bpy.data.objects if o.type == "MESH"]:
	for v in ob.data.vertices:
		v.co.y -= HANDLE_CENTER_Y
		v.co *= STUD_PER_INCH
	ob.data.update()

sys.argv = ["blender", "--", out]
with open(os.path.join(root, "tools", "export_mesh_fbx.py"), encoding="utf-8") as fh:
	exec(fh.read(), {"__name__": "export_mesh_fbx"})
print("OK", out)
