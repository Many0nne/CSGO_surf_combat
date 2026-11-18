"""Rend le rig R15 habillé d'une ou plusieurs tenues (#521) pour une planche de variantes : Blender sans interface,
Workbench (couleur des textures, quelques secondes par vue), fond transparent. Lancé par tools/outfits/board.py :

  blender -b --factory-startup --python tools/outfits/board_render.py -- <config.json>

config.json : {"objs": {"<Pièce>": "<chemin.obj>", ..., "Head": "<coque.obj>"}, "positions": {"<Pièce>": [x, y, z]},
"rows": [{"name": ..., "textures": {"<Pièce>": "<image>"}}], "views": {"<vue>": angle en degrés}, "res": [l, h],
"ortho": échelle, "center": hauteur visée (repère du jeu), "out": "<dossier>"}. Chaque rendu est écrit dans
<out>/<rangée>_<vue>.png. Repère du jeu : Y en haut, avant = -Z (importé en Z en haut, avant = +Y de Blender).
"""

import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

cfg = json.load(open(sys.argv[sys.argv.index("--") + 1 :][0]))
scene = bpy.context.scene
for o in list(bpy.data.objects):
	bpy.data.objects.remove(o)

try:
	scene.render.engine = "BLENDER_WORKBENCH"
except TypeError as e:
	raise SystemExit(f"[board_render] moteur Workbench introuvable : {e}") from e
shading = scene.display.shading
shading.light = "STUDIO"
shading.color_type = "TEXTURE"
# pas de reflet spéculaire de Workbench : il fait des triangles clairs sur les grandes faces des jambes
shading.show_specular_highlight = False
scene.render.film_transparent = True
scene.render.resolution_x, scene.render.resolution_y = cfg["res"]
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "Standard"

# Pièces : importées une fois, un matériau par pièce dont on change l'image à chaque rangée
nodes = {}
for name, path in cfg["objs"].items():
	bpy.ops.wm.obj_import(filepath=path, forward_axis="NEGATIVE_Z", up_axis="Y")
	parts = bpy.context.selected_objects
	bpy.context.view_layer.objects.active = parts[0]
	if len(parts) > 1:
		bpy.ops.object.join()  # coque en plusieurs meshs : un seul objet, placé et texturé d'un coup
	obj = bpy.context.view_layer.objects.active
	# centre de la boîte englobante à l'origine, comme une MeshPart du jeu (et comme r15_bake.load_obj)
	bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
	obj.name = name
	x, y, z = cfg["positions"][name]
	obj.location = (x, -z, y)
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
	bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
	mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
	mat.node_tree.nodes.active = tex
	obj.data.materials.clear()
	obj.data.materials.append(mat)
	for poly in obj.data.polygons:
		poly.use_smooth = True
	nodes[name] = tex

cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = cfg["ortho"]
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
target = Vector((0, 0, cfg["center"]))


# Cette méthode permet de placer la caméra autour du personnage (angle 0 : de face, 180 : de dos, sens trigonométrique
# vu d'en haut) lorsqu'on rend une vue de la planche.
def place(angle):
	a = math.radians(angle)
	d = Vector((math.sin(a), math.cos(a), 0.12)).normalized()
	pos = target + d * 30
	cam.matrix_world = Matrix.Translation(pos) @ (target - pos).to_track_quat("-Z", "Y").to_matrix().to_4x4()


images = {}
for row in cfg["rows"]:
	for name, tex in nodes.items():
		path = row["textures"][name]
		if path not in images:
			img = bpy.data.images.load(path, check_existing=False)
			img.colorspace_settings.name = "sRGB"
			images[path] = img
		tex.image = images[path]
	for view, angle in cfg["views"].items():
		place(angle)
		scene.render.filepath = os.path.join(cfg["out"], f"{row['name']}_{view}.png")
		bpy.ops.render.render(write_still=True)
		print(f"[board_render] {row['name']} {view}")
