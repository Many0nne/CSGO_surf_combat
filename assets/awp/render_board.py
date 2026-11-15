"""Vues de planche de l'AWP (Workbench, quelques secondes), pour l'ancien comme pour le nouveau modèle.

`blender -b <scene.blend> --factory-startup --python assets/awp/render_board.py -- <dossier> <préfixe>`
Écrit <préfixe>_gauche.png (profil gauche orthographique, cadre fixe : se superpose à la photo de profil, voir
compose_board.py), _droite, _dessus, _trois_quarts, et _1p : la vue du joueur au repos (caméra du viewmodel, FOV vertical
90°, 16:9), à comparer à `references/skins/AWP/Default/01-repos.png`. Repère du modèle : celui de build_awp.py.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

SIDE_CENTER = (-0.9, 0.0)  # (X, Z) au centre des vues de profil
SIDE_SCALE = 10.2  # largeur de la vue de profil (unités)
SIDE_RES = (2040, 600)
CAM_1P = Vector((2.9, -1.09, 0.65))  # caméra du viewmodel dans le repère du modèle (origine = Joint)


def render_board(out_dir, prefix):
	"""Cette méthode permet de rendre les vues de la planche dans out_dir et d'en renvoyer les chemins."""
	os.makedirs(out_dir, exist_ok=True)
	sc = bpy.context.scene
	for ob in list(sc.objects):
		if ob.type in {"LIGHT", "CAMERA"}:
			ob.hide_render = True
	sc.render.engine = "BLENDER_WORKBENCH"
	sh = sc.display.shading
	textured = any(img.source == "FILE" for img in bpy.data.images)
	sh.light, sh.color_type, sh.show_object_outline = "STUDIO", "TEXTURE" if textured else "MATERIAL", False
	sh.show_cavity = True
	sh.cavity_type = "WORLD"
	world = sc.world or bpy.data.worlds.new("W")
	sc.world = world
	world.color = (0.82, 0.84, 0.86)
	sc.view_settings.view_transform = "Standard"
	cam_data = bpy.data.cameras.new("BoardCam")
	cam = bpy.data.objects.new("BoardCam", cam_data)
	sc.collection.objects.link(cam)
	sc.camera = cam
	paths = []

	def shoot(name, loc, target, res, ortho=None, fov_v=None):
		cam.location = Vector(loc)
		cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
		if ortho:
			cam_data.type, cam_data.ortho_scale = "ORTHO", ortho
		else:
			cam_data.type = "PERSP"
			cam_data.sensor_fit = "VERTICAL"
			cam_data.angle = math.radians(fov_v)
		cam_data.clip_start = 0.05
		sc.render.resolution_x, sc.render.resolution_y = res
		sc.render.filepath = os.path.join(out_dir, f"{prefix}_{name}.png")
		bpy.ops.render.render(write_still=True)
		paths.append(sc.render.filepath)

	cx, cz = SIDE_CENTER
	shoot("gauche", (cx, -30, cz), (cx, 0, cz), SIDE_RES, ortho=SIDE_SCALE)
	shoot("droite", (cx, 30, cz), (cx, 0, cz), SIDE_RES, ortho=SIDE_SCALE)
	shoot("dessus", (cx, 0, 30), (cx, 0.0001, cz), SIDE_RES, ortho=SIDE_SCALE)
	shoot("trois_quarts", (-9.5, -7.5, 4.0), (-0.6, 0, 0.0), (1600, 900), fov_v=32)
	shoot("1p", CAM_1P, CAM_1P + Vector((-1, 0, 0)), (1600, 900), fov_v=90)
	bpy.data.objects.remove(cam, do_unlink=True)
	return paths


args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
print("\n".join(render_board(args[0], args[1] if len(args) > 1 else "b")))
