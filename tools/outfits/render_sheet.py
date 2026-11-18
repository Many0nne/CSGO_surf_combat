"""Planche de tenues de personnage (#521) : le rig R15 habillé de chaque variante, de face, de trois quarts et de dos,
côte à côte et au même cadrage, en Workbench (couleur des textures, quelques secondes ; pas d'EEVEE, trop lent ici).

Workbench montre la carte de couleur sous un éclairage de studio, pas la normal map : le relief ne s'y lit que s'il
est peint dans la couleur (reflet figé de MERCURE, creux et arêtes des autres tenues). C'est une planche de
comparaison, pas le rendu du jeu : le comparer ensuite en jeu, au même cadrage.

Entrées : le rig au repos (JSON de `r15_bake.py --rig-json`) et, par colonne, « Titre=<dossier> », le dossier d'une
variante cuite (sous-dossiers R15/ et, s'il y a une coque, Head/). Sans Head/, la tête reste grise comme celle du rig.

Usage (depuis la racine du worktree) :
  blender -b --factory-startup --python tools/outfits/render_sheet.py -- <rig.json> <planche.png> \
    "PATINE=assets/outfits/bronze/maps/patine" "MERCURE=assets/outfits/mercure/maps/lisse" [--width 360]
(--width : largeur d'une colonne en pixels ; la hauteur suit le cadrage.)
"""

import json
import math
import os
import sys

import bpy
from mathutils import Matrix

argv = sys.argv[sys.argv.index("--") + 1 :]
RIG, OUT = argv[0], argv[1]
CELL_W = int(argv[argv.index("--width") + 1]) if "--width" in argv else 360
COLUMNS = [a.split("=", 1) for a in argv[2:] if "=" in a]
VIEWS = [("FACE", 0), ("TROIS QUARTS", -35), ("DOS", 180)]
STEP_X, STEP_Y = 7.5, 10.0  # écart entre deux personnages (studs)


# Cette méthode permet de créer le matériau d'un atlas (carte de couleur) lorsqu'une variante a cette carte, gris du
# rig sinon.
def material(folder, group):
	sub = "Head" if group == "Head" else "R15"
	path = os.path.abspath(os.path.join(folder, sub, f"{group}_Color.png"))
	mat = bpy.data.materials.new(f"{folder}_{group}")
	mat.use_nodes = True
	bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
	if os.path.exists(path):
		tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
		tex.image = bpy.data.images.load(path, check_existing=True)
		mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
		mat.node_tree.nodes.active = tex
	else:
		mat.diffuse_color = (0.38, 0.37, 0.39, 1)
		bsdf.inputs["Base Color"].default_value = (0.38, 0.37, 0.39, 1)
	return mat


# Cette méthode permet de construire un mesh de Blender depuis une pièce du rig (axes Roblox : Y en haut, avant = -Z ;
# Blender : Z en haut, le personnage regarde +Y) lorsqu'on habille un personnage de la planche.
def part_mesh(name, data):
	me = bpy.data.meshes.new(name)
	verts = [(x, -z, y) for x, y, z in data["pos"]]
	me.from_pydata(verts, [], [tuple(t) for t in data["tris"]])
	layer = me.uv_layers.new(name="UV")
	for poly in me.polygons:
		for li in poly.loop_indices:
			u, v = data["uv"][me.loops[li].vertex_index]
			layer.data[li].uv = (u, 1 - v)
	return me


for o in list(bpy.data.objects):
	bpy.data.objects.remove(o)
with open(RIG) as f:
	rig = json.load(f)
scene = bpy.context.scene
meshes = {name: part_mesh(name, data) for name, data in rig.items()}

for col, (title, folder) in enumerate(COLUMNS):
	mats = {}
	for row, (_, angle) in enumerate(VIEWS):
		pivot = bpy.data.objects.new(f"{title}_{row}", None)
		scene.collection.objects.link(pivot)
		pivot.matrix_world = Matrix.Translation((-col * STEP_X, 0, -row * STEP_Y)) @ Matrix.Rotation(
			math.radians(angle), 4, "Z"
		)
		for name, me in meshes.items():
			group = rig[name]["group"]  # atlas de la pièce (r15_bake.PARTS)
			if group not in mats:
				mats[group] = material(folder, group)
			mesh = me.copy()
			mesh.materials.append(mats[group])
			obj = bpy.data.objects.new(f"{title}_{row}_{name}", mesh)
			scene.collection.objects.link(obj)
			obj.parent = pivot
	label = bpy.data.curves.new(f"label_{col}", "FONT")
	label.body = title
	label.align_x = "CENTER"
	label.size = 0.9
	text = bpy.data.objects.new(f"label_{col}", label)
	text.data.materials.append(bpy.data.materials.new("label"))
	text.rotation_euler = (math.radians(90), 0, math.radians(180))
	text.location = (-col * STEP_X, 0, 4.4)
	scene.collection.objects.link(text)

# Caméra orthographique de face (le long de -Y), qui cadre toute la grille
n_cols, n_rows = len(COLUMNS), len(VIEWS)
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
width, height = n_cols * STEP_X, n_rows * STEP_Y + 0.8
cx, cz = -(n_cols - 1) * STEP_X / 2, -(n_rows - 1) * STEP_Y / 2 + 0.2
cam.location = (cx, 40, cz)
cam.rotation_euler = (math.radians(90), 0, math.radians(180))  # regarde -Y, Z en haut : l'écran a sa droite en -X
scene.render.resolution_x = CELL_W * n_cols
scene.render.resolution_y = int(CELL_W * n_cols * height / width)
cam_data.ortho_scale = max(width, height)  # Blender cadre la plus grande dimension de l'image
cam_data.clip_start, cam_data.clip_end = 1, 100

scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.display.shading.show_cavity = False
scene.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("fond")
world.color = (0.16, 0.17, 0.19)
scene.world = world
scene.render.resolution_percentage = 100
scene.render.filepath = os.path.abspath(OUT)
bpy.ops.render.render(write_still=True)
print(f"[render_sheet] {n_cols} colonnes x {n_rows} vues -> {scene.render.filepath}")
