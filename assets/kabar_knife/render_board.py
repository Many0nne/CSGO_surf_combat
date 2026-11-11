"""Planche de rendu du couteau (Workbench, quelques secondes) : vues orthogonales et trois-quarts, PNG dans %TEMP%/kabar.

À lancer dans Blender après build_knife.py (+ make_textures.py pour les textures). Réglages de la scène restaurés ensuite.
Les couleurs de la planche sont celles des textures (mode Texture de Workbench), sans reflets PBR.
"""

import os
import tempfile

import bpy
from mathutils import Vector

BOARD_DIR = os.path.join(tempfile.gettempdir(), "kabar")


def render_board(prefix="b"):
	"""Cette méthode permet de rendre les vues de la planche dans BOARD_DIR et d'en renvoyer les chemins."""
	os.makedirs(BOARD_DIR, exist_ok=True)
	sc = bpy.context.scene
	sh = sc.display.shading
	saved = (sc.render.engine, sc.camera, sc.render.resolution_x, sc.render.resolution_y, sc.render.filepath)
	saved_sh = (sh.light, sh.color_type, sh.show_object_outline)
	world = sc.world or bpy.data.worlds.new("W")
	sc.world = world
	saved_world = tuple(world.color)
	sc.render.engine = "BLENDER_WORKBENCH"
	sh.light, sh.color_type, sh.show_object_outline = "STUDIO", "TEXTURE", False
	world.color = (0.82, 0.84, 0.86)
	sc.render.resolution_x, sc.render.resolution_y = 1400, 560
	cam_data = bpy.data.cameras.new("BoardCam")
	cam = bpy.data.objects.new("BoardCam", cam_data)
	sc.collection.objects.link(cam)
	sc.camera = cam
	paths = []

	def shoot(name, direction, ortho=True, scale=13.0, center=Vector((0, 1.13, 0))):
		d = Vector(direction).normalized()
		cam.location = center + d * 30
		cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
		cam_data.type = "ORTHO" if ortho else "PERSP"
		cam_data.ortho_scale = scale
		cam_data.lens = 70
		sc.render.filepath = os.path.join(BOARD_DIR, f"{prefix}_{name}.png")
		bpy.ops.render.render(write_still=True)
		paths.append(sc.render.filepath)

	shoot("droit", (1, 0, 0))
	shoot("gauche", (-1, 0, 0))
	shoot("trois_quarts", (1.0, -0.9, 0.55), ortho=False)
	shoot("ricasso", (1, 0, 0), scale=3.2, center=Vector((0, 0.6, 0)))
	shoot("manche", (1, 0, 0), scale=5.5, center=Vector((0, -2.2, 0)))
	bpy.data.objects.remove(cam, do_unlink=True)
	bpy.data.cameras.remove(cam_data)
	sc.render.engine, sc.camera, sc.render.resolution_x, sc.render.resolution_y, sc.render.filepath = saved
	sh.light, sh.color_type, sh.show_object_outline = saved_sh
	world.color = saved_world
	return paths


print("\n".join(render_board(globals().get("BOARD_PREFIX", "b"))))
