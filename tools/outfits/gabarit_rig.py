"""Rend le gabarit du rig R15 en blocs (#521) : le personnage nu, gris clair, vu de face, de trois quarts et de dos,
sur fond blanc. Sert de support aux planches de concept des tenues, peintes par un modèle d'image externe à partir d'un
brief (assets/outfits/concepts/*.brief.md).

Les blocs sont posés d'après les tailles et hauteurs de tools/outfits/r15_bake.py (PARTS, OFFSETS), légèrement
arrondis comme les meshs du rig ; la tête est le mesh de la tête classique (assets/outfits/mercure/MercureHead.fbx).

Usage (depuis la racine du worktree, Blender sans interface) :
  blender -b --factory-startup --python tools/outfits/gabarit_rig.py -- <dossier de sortie>
Sorties : rig_face.png, rig_trois_quarts.png, rig_dos.png (1024 × 1024), puis assemblées par gabarit_planche.py.
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.abspath(
	sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.join(ROOT, "assets", "outfits", "concepts")
)

# Taille (X, Y, Z en studs) et hauteur du centre au-dessus de la racine, reprises de r15_bake.py
TORSO_W, LIMB = 3.1764, 1.5882
BLOCKS = {
	"UpperTorso": ((TORSO_W, 2.5412, LIMB), 0.0, 0.3176),
	"LowerTorso": ((TORSO_W, 0.6354, LIMB), 0.0, -1.2706),
}
ARM_X = TORSO_W / 2 + LIMB / 2
LEG_X = TORSO_W / 4
for side, sx in (("Left", -1), ("Right", 1)):
	BLOCKS[side + "UpperArm"] = ((LIMB, 1.8561, LIMB), sx * ARM_X, 0.5855)
	BLOCKS[side + "LowerArm"] = ((LIMB, 1.6707, LIMB), sx * ARM_X, -0.3559)
	BLOCKS[side + "Hand"] = ((LIMB, 0.4765, LIMB), sx * ARM_X, -1.35)
	BLOCKS[side + "UpperLeg"] = ((LIMB, 1.9321, LIMB), sx * LEG_X, -2.2565)
	BLOCKS[side + "LowerLeg"] = ((LIMB, 1.8949, LIMB), sx * LEG_X, -3.4955)
	BLOCKS[side + "Foot"] = ((LIMB, 0.4765, LIMB), sx * LEG_X, -4.5264)
TORSO_TOP = 0.3176 + 2.5412 / 2


# Cette méthode permet de créer un bloc arrondi du rig lorsqu'on monte le personnage du gabarit (Blender : Z vers le
# haut, le personnage regarde vers -Y).
def add_block(name, size, x, y):
	bpy.ops.mesh.primitive_cube_add(size=1, location=(x, 0, y))
	ob = bpy.context.object
	ob.name = name
	# Les pièces du bas d'un membre chevauchent celle du haut au coude et au genou : un rien plus fines, leurs faces ne se
	# disputent pas l'affichage
	thin = 0.99 if name.endswith(("LowerArm", "Hand", "LowerLeg", "Foot")) else 1.0
	ob.scale = (size[0] * thin, size[2] * thin, size[1])
	bpy.ops.object.transform_apply(scale=True)
	bev = ob.modifiers.new("bevel", "BEVEL")
	bev.width = 0.06
	bev.segments = 3
	return ob


# Cette méthode permet de poser la tête classique sur le torse lorsqu'on monte le gabarit (mesh à la taille affichée
# par le rig, 1,98 × 1,99 × 1,98 studs).
def add_head():
	before = set(bpy.data.objects)
	bpy.ops.import_scene.fbx(filepath=os.path.join(ROOT, "assets", "outfits", "mercure", "MercureHead.fbx"))
	head = [o for o in bpy.data.objects if o not in before and o.type == "MESH"][0]
	dims = head.dimensions
	head.scale = [s * t / d for s, t, d in zip(head.scale, (1.98, 1.98, 1.99), dims)]
	bpy.context.view_layer.update()
	lo = min((head.matrix_world @ v.co).z for v in head.data.vertices)
	head.location.z += TORSO_TOP - lo
	head.location.x -= sum((head.matrix_world @ v.co).x for v in head.data.vertices) / len(head.data.vertices)
	head.location.y -= sum((head.matrix_world @ v.co).y for v in head.data.vertices) / len(head.data.vertices)
	return head


# Cette méthode permet de rendre le personnage depuis un angle donné (0 = de face, 180 = de dos), vu un peu d'en haut
# si `elev` (degrés) est donné, lorsqu'on produit une vue du gabarit.
def render(path, angle_deg, elev=0):
	scene = bpy.context.scene
	cam = scene.camera
	a, e = math.radians(angle_deg), math.radians(elev)
	dist = 40
	cam.location = (math.sin(a) * math.cos(e) * dist, -math.cos(a) * math.cos(e) * dist, -0.6 + math.sin(e) * dist)
	cam.rotation_euler = (math.radians(90) - e, 0, a)
	scene.render.filepath = path
	bpy.ops.render.render(write_still=True)


def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	mat = bpy.data.materials.new("rig")
	mat.diffuse_color = (0.78, 0.78, 0.78, 1)
	for name, (size, x, y) in BLOCKS.items():
		add_block(name, size, x, y).data.materials.append(mat)
	head = add_head()
	head.data.materials.clear()
	head.data.materials.append(mat)

	scene = bpy.context.scene
	try:
		scene.render.engine = "BLENDER_WORKBENCH"
	except TypeError as e:
		print(e)
	shading = scene.display.shading
	shading.light = "STUDIO"
	shading.color_type = "MATERIAL"
	shading.show_cavity = True
	shading.cavity_type = "BOTH"
	shading.show_object_outline = True
	shading.object_outline_color = (0.15, 0.15, 0.15)
	scene.render.film_transparent = False
	scene.world = bpy.data.worlds.new("w")
	scene.display.shading.background_type = "VIEWPORT"
	scene.display.shading.background_color = (1, 1, 1)
	scene.view_settings.view_transform = "Standard"
	scene.render.resolution_x = scene.render.resolution_y = 1024

	cam_data = bpy.data.cameras.new("cam")
	cam_data.type = "ORTHO"
	cam_data.ortho_scale = 11.5
	cam = bpy.data.objects.new("cam", cam_data)
	scene.collection.objects.link(cam)
	scene.camera = cam

	os.makedirs(OUT, exist_ok=True)
	for name, angle, elev in (("rig_face", 0, 0), ("rig_trois_quarts", 35, 12), ("rig_dos", 180, 0)):
		render(os.path.join(OUT, name + ".png"), angle, elev)


main()
