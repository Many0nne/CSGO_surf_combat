"""Rendu Blender (sans interface) des vues de la planche des tenues : lancé par tools/outfits/board.py, qui lui passe
un fichier de configuration JSON. Workbench, couleur des textures, caméra orthographique au même cadrage pour toutes
les tenues. Les OBJ sont dans l'espace du jeu (Y en haut, avant = -Z) avec des UV en convention Roblox (v vers le bas
de l'image) : l'import les tourne (Z en haut, avant = +Y) et la planche retourne les UV.
"""

import json
import math
import sys

import bpy

cfg = json.load(open(sys.argv[sys.argv.index("--") + 1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


# Cette méthode permet d'importer un OBJ du jeu, de retourner ses UV et de le poser à sa place du rig lorsque la
# planche construit le personnage.
def import_obj(path, name, position):
	bpy.ops.wm.obj_import(filepath=path, forward_axis="NEGATIVE_Z", up_axis="Y")
	obj = bpy.context.selected_objects[0]
	obj.name = name
	for loop_uv in obj.data.uv_layers.active.data:
		loop_uv.uv.y = 1 - loop_uv.uv.y
	x, y, z = position
	obj.location = (x, -z, y)
	return obj


# Cette méthode permet de créer un matériau à la couleur d'une image (ou unie, sans image) lorsqu'on habille une
# pièce pour la planche.
def material(name, image_path, rgb=(0.5, 0.5, 0.5)):
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
	if image_path:
		tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
		tex.image = bpy.data.images.load(image_path, check_existing=True)
		mat.node_tree.links.new(tex.outputs[0], bsdf.inputs[0])
		mat.node_tree.nodes.active = tex
	else:
		bsdf.inputs[0].default_value = (*rgb, 1)
	mat.diffuse_color = (*rgb, 1)
	return mat


parts = {name: import_obj(path, name, cfg["positions"][name]) for name, path in cfg["rig"].items()}
head = import_obj(cfg["head_mesh"], "Head", cfg["positions"]["Head"]) if cfg["head_mesh"] else None

# Rendu Workbench : couleur des textures, éclairage studio, fond gris neutre
try:
	scene.render.engine = "BLENDER_WORKBENCH"
except TypeError as e:
	print("[board] moteurs :", e)
shading = scene.display.shading
shading.light = "STUDIO"
shading.color_type = "TEXTURE"
shading.background_type = "VIEWPORT"
shading.background_color = (0.32, 0.32, 0.34)
shading.show_specular_highlight = True
scene.render.resolution_y = cfg["size"]
scene.render.resolution_x = int(cfg["size"] * 0.82)
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "Standard"

cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 8.6
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
center_z = -0.75

for i, outfit in enumerate(cfg["outfits"]):
	mats = {}
	for name, obj in parts.items():
		group = cfg["groups"][name]
		if group not in mats:
			mats[group] = material(f"{i}_{group}", f"{outfit['maps']}/{group}_Color.png")
		obj.data.materials.clear()
		obj.data.materials.append(mats[group])
	if head:
		head.data.materials.clear()
		head.data.materials.append(material(f"{i}_Head", outfit["head"], (0.55, 0.55, 0.55)))
	for j, (_, angle) in enumerate(cfg["views"]):
		a = math.radians(angle)
		# le personnage regarde vers +Y : caméra devant lui, tournée de `angle` autour de lui (vers sa gauche)
		cam.location = (-20 * math.sin(a), 20 * math.cos(a), center_z + 1.0)
		cam.rotation_euler = (math.radians(87), 0, math.pi + a)
		scene.render.filepath = f"{cfg['out_dir']}/view_{i}_{j}.png"
		bpy.ops.render.render(write_still=True)
print("[board] vues rendues")
