"""Construit les animations de l'AWP sans toucher au Blender ouvert, puis écrit leurs JSON.

Usage, depuis la racine du worktree :
  blender -b assets/awp_viewmodel/AWP_Viewmodel_Anims.blend --python assets/awp_viewmodel/run_build.py -- <sortie> <Nom1> [Nom2 ...]

Écrit dans <sortie> :
  anim_<Nom>.json    Transform de chaque Motor6D, lu par make_rbxm.luau
  frames_<Nom>.json  CFrame de chaque pièce dans le repère caméra (un pas de 1/60 s), lu par tools/anim/studio_render.luau
"""

import json
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(bpy.data.filepath))
out_dir, *names = sys.argv[sys.argv.index("--") + 1 :]
os.makedirs(out_dir, exist_ok=True)
ns = {"__name__": "lib"}
with open(os.path.join(HERE, "build_anims.py"), encoding="utf-8") as fh:
	exec(fh.read(), ns)

PARTS = [o for o in bpy.data.objects if o.type == "MESH"]
FAKE_CAMERA = bpy.data.objects["FakeCamera"]


# Cette méthode permet d'écrire la CFrame de chaque pièce par rapport à FakeCamera, à chaque image gardée de l'animation :
# en jeu, FakeCamera est recalé sur la caméra (PivotTo), donc ce repère est exactement celui que voit le joueur.
def dump_frames(name, out_path, step=1):
	act = bpy.data.actions["AWP_" + name]
	ns["RIG"].animation_data.action = act
	ns["RIG"].animation_data.action_slot = act.slots[0]
	f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
	data = {}
	scene = bpy.context.scene
	for f in range(f0, f1 + 1, step):
		scene.frame_set(f)
		cam = FAKE_CAMERA.matrix_world.inverted()
		data[f"{name}_{(f - f0) // step:03d}"] = {
			o.name: [round(v, 5) for v in ns["matrix_to_cframe"](cam @ o.matrix_world)] for o in PARTS
		}
	with open(out_path, "w", encoding="utf-8") as fh:
		json.dump(data, fh)
	return len(data)


ns["build"]()
for name in names:
	count = ns["export"](name, os.path.join(HERE, "rig.json"), os.path.join(out_dir, f"anim_{name}.json"))
	shots = dump_frames(name, os.path.join(out_dir, f"frames_{name}.json"))
	print(f"OK {name} : {count} keyframes, {shots} poses -> {out_dir}")
