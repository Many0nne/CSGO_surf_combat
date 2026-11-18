"""PAN ! en volume (#566) : l'explosion de BD de la crosse du skin PAN ! (assets/awp/skins/pan.py) construite en relief,
calque par calque comme sur la crosse : plaque de contour noire à l'arrière, étoile rouge, cœur jaune, puis l'onomatopée
« PAN ! » en relief, blanche cernée de noir. Même contour à pointes (fonction `burst`, mêmes graines), mêmes couleurs.

Blender sans interface (une commande, parallélisable) :

    blender -b --factory-startup --python assets/effects/pan_burst_3d.py -- <sortie.blend> [planche.png]

Repère : face montrée vers -Y (vers la caméra de face de Blender), haut +Z ; 1 unité = 1 stud, largeur PAN_WIDTH.
Planche : rendu Workbench (quelques secondes) de face, de trois quarts et de profil, pour juger le relief.
"""

import math
import sys

import bmesh
import bpy
import numpy as np

RED = (0.88, 0.10, 0.10)
YELLOW = (0.98, 0.80, 0.10)
BLACK = (0.025, 0.025, 0.03)
WHITE = (0.95, 0.95, 0.93)

WIDTH = 4.0  # studs : largeur de la plaque noire (410 px photo sur la crosse)
K = WIDTH / 410.0  # studs par px photo
# Épaisseurs (studs) et avancée de la face avant de chaque calque vers la caméra (-Y)
LAYERS = (
	# nom, rayons (px), pointes, graine, couleur, épaisseur, avancée de la face avant
	("Contour", (205, 128), 13, 3, BLACK, 0.30, 0.00),
	("Etoile", (190, 116), 13, 3, RED, 0.30, 0.08),
	("Coeur", (128, 78), 11, 7, YELLOW, 0.30, 0.16),
)
# Corps de police en px photo (Canvas.text de common.py), corrigé : à corps égal, le texte de Blender sort ~1,45 fois
# plus petit que celui de PIL (mesuré sur la planche, largeur de « PAN ! » rapportée à l'étoile)
TEXT_HEIGHT = 76 * 1.38 * 1.45
TEXT_ANGLE = 8  # degrés, comme sur la crosse
TEXT_DEPTH = 0.16  # relief des lettres devant le cœur
TEXT_OUTLINE = 8  # cerne noir autour des lettres (px photo), fait par le biseau des lettres noires
TEXT_BEVEL = 1.2  # arrondi des arêtes des lettres (px photo)


def burst(rx, ry, spikes, seed):
	"""Cette méthode permet d'obtenir le contour d'une explosion de BD : pointes irrégulières autour d'une ellipse
	(copie de pan.py, mêmes tirages)."""
	rng = np.random.default_rng(seed)
	pts = []
	for i in range(spikes * 2):
		a = i / (spikes * 2) * 2 * math.pi
		k = (1.0 if i % 2 == 0 else 0.62) * (0.88 + 0.24 * rng.random())
		# image : y vers le bas ; Blender : z vers le haut
		pts.append((rx * k * math.cos(a), -ry * k * math.sin(a)))
	return pts


def material(name, color):
	"""Cette méthode permet de créer un matériau mat d'une couleur (Principled et couleur d'affichage Workbench)."""
	mat = bpy.data.materials.new(name)
	mat.diffuse_color = (*color, 1.0)
	mat.use_nodes = True
	bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
	bsdf.inputs["Base Color"].default_value = (*color, 1.0)
	bsdf.inputs["Roughness"].default_value = 0.6
	return mat


def prism(name, pts, depth, front, mat):
	"""Cette méthode permet d'extruder un contour (px photo) en prisme : face avant à y = -front, épaisseur `depth` vers
	l'arrière."""
	mesh = bpy.data.meshes.new(name)
	bm = bmesh.new()
	verts = [bm.verts.new((x * K, -front, z * K)) for x, z in pts]
	face = bm.faces.new(verts)
	ext = bmesh.ops.extrude_face_region(bm, geom=[face])
	moved = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
	bmesh.ops.translate(bm, verts=moved, vec=(0, depth, 0))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bm.to_mesh(mesh)
	bm.free()
	obj = bpy.data.objects.new(name, mesh)
	obj.data.materials.append(mat)
	bpy.context.collection.objects.link(obj)
	return obj


def text(name, offset, depth, front, mat):
	"""Cette méthode permet de poser « PAN ! » en relief (Impact, incliné comme sur la crosse), épaissi de `offset` px
	photo pour le cerne, converti en maillage ; face avant à y = -front."""
	curve = bpy.data.curves.new(name, "FONT")
	curve.body = "PAN !"
	curve.font = bpy.data.fonts.load("C:/Windows/Fonts/impact.ttf")
	curve.size = TEXT_HEIGHT * K
	curve.align_x = "CENTER"
	curve.align_y = "CENTER"
	curve.extrude = depth / 2
	# Cerne : le biseau grossit chaque lettre tout autour de son contour (le décalage `offset` de Blender les soude en
	# pavé) ; lettres blanches : simple arrondi des arêtes
	curve.bevel_depth = (offset if offset > 0 else TEXT_BEVEL) * K
	curve.bevel_resolution = 2
	obj = bpy.data.objects.new(name, curve)
	bpy.context.collection.objects.link(obj)
	# texte posé dans XY : le relever face à -Y, l'incliner, le décaler comme sur la crosse (4, 2 px)
	obj.rotation_euler = (math.radians(90), math.radians(-TEXT_ANGLE), 0)
	obj.location = (4 * K, -front + depth / 2, -2 * K)
	bpy.context.view_layer.objects.active = obj
	obj.select_set(True)
	bpy.ops.object.convert(target="MESH")
	obj.select_set(False)
	obj.data.materials.clear()
	obj.data.materials.append(mat)
	return obj


def build():
	"""Cette méthode permet de construire l'explosion en volume dans une scène vide et de la regrouper sous un parent."""
	for obj in list(bpy.data.objects):
		bpy.data.objects.remove(obj)
	parts = []
	for name, (rx, ry), spikes, seed, color, depth, front in LAYERS:
		parts.append(prism(name, burst(rx, ry, spikes, seed), depth, front, material(name, color)))
	core_front = LAYERS[-1][6]
	parts.append(text("Cerne", TEXT_OUTLINE, TEXT_DEPTH, core_front + TEXT_DEPTH * 0.9, material("Cerne", BLACK)))
	# le biseau du cerne l'épaissit aussi vers l'avant : les lettres blanches passent devant lui
	letters_front = core_front + TEXT_DEPTH * 0.9 + TEXT_OUTLINE * K + 0.02
	parts.append(text("Lettres", 0, TEXT_DEPTH, letters_front, material("Lettres", WHITE)))
	root = bpy.data.objects.new("PanBurst", None)
	bpy.context.collection.objects.link(root)
	for part in parts:
		part.parent = root
	return root


def planche(path):
	"""Cette méthode permet de rendre la planche Workbench (face, trois quarts, profil) côte à côte dans un seul PNG."""
	scene = bpy.context.scene
	try:
		scene.render.engine = "BLENDER_WORKBENCH"
	except TypeError as err:
		print("moteur Workbench introuvable :", err)
	shading = scene.display.shading
	shading.light = "STUDIO"
	shading.color_type = "MATERIAL"
	shading.show_shadows = True
	shading.show_cavity = True
	scene.display.shading.show_object_outline = False
	scene.render.film_transparent = False
	world = bpy.data.worlds.new("Fond")
	world.color = (0.12, 0.12, 0.14)
	scene.world = world
	scene.render.resolution_x, scene.render.resolution_y = 640, 480
	cam_data = bpy.data.cameras.new("Cam")
	cam_data.lens = 50
	cam = bpy.data.objects.new("Cam", cam_data)
	bpy.context.collection.objects.link(cam)
	scene.camera = cam
	views = (("face", 0), ("trois_quarts", 35), ("profil", 70))
	files = []
	for label, yaw in views:
		a = math.radians(yaw)
		dist = 9.0
		cam.location = (dist * math.sin(a), -dist * math.cos(a), 0.4)
		direction = -cam.location.normalized() if hasattr(cam.location, "normalized") else None
		cam.rotation_euler = (math.radians(87), 0, a)
		out = path.replace(".png", f"_{label}.png")
		scene.render.filepath = out
		bpy.ops.render.render(write_still=True)
		files.append(out)
	return files


def main():
	"""Cette méthode permet de lire les arguments, construire le modèle, l'enregistrer et rendre la planche."""
	args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
	out = args[0] if args else "pan_burst_3d.blend"
	build()
	bpy.ops.wm.save_as_mainfile(filepath=bpy.path.abspath("//") + out if not out[1:3] == ":/" else out)
	if len(args) > 1:
		print("planche :", planche(args[1]))


main()
