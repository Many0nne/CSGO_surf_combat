"""Rend une arme avec un jeu de cartes PBR, sous un éclairage HDRI, pour juger un skin (#268).

Les cartes sont lues dans <dossier> sous les noms <PREFIXE>_Color.png, _Rough.png, _Metal.png, _Normal.png, comme dans
assets/sniper/textures (préfixes METAL_A, METAL_B, SCOPE, WOOD) ou en sortie de fetch_viewmodel.py pour la M9 (Handle,
fichiers m9_Handle_*.png acceptés). Une vue = un PNG <sortie>_<vue>.png, fond transparent (la planche compose ensuite).

Usage :
  blender -b assets/sniper/Sniper.blend --factory-startup --python tools/skins/render_views.py -- awp <dossier> <sortie>
  blender -b --factory-startup --python tools/skins/render_views.py -- m9 <dossier> <sortie> --glb <m9.glb>
Options : --samples N (64), --res LxH (1200x800), --hdri <nom> (studiolights/world : city, courtyard, interior...),
--views a,b (toutes par défaut).
"""

import math
import os
import sys
import time

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :]
WEAPON, TEX, OUT = argv[0], argv[1], argv[2]


# Cette méthode permet de lire une option --nom valeur de la ligne de commande lorsqu'elle est donnée.
def opt(name, default):
	return argv[argv.index(name) + 1] if name in argv else default


SAMPLES = int(opt("--samples", "64"))
RES = [int(v) for v in opt("--res", "1200x800").split("x")]
HDRI = opt("--hdri", "interior")
VIEWS = opt("--views", "")

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.render.film_transparent = True
scene.render.resolution_x, scene.render.resolution_y = RES
scene.render.resolution_percentage = 100
# Standard : les couleurs peintes restent telles quelles (AgX désature les rouges vifs en saumon)
scene.view_settings.view_transform = opt("--view", "Standard")


# Cette méthode permet de trouver la carte d'un préfixe dans le dossier de textures, sous l'un des noms acceptés.
def tex_path(prefix, kind):
	for name in (f"{prefix}_{kind}.png", f"m9_{prefix}_{kind}.png"):
		p = os.path.join(TEX, name)
		if os.path.exists(p):
			return os.path.abspath(p)
	raise FileNotFoundError(f"{prefix}_{kind}.png dans {TEX}")


# Cette méthode permet de charger une image en remplaçant une éventuelle version déjà chargée lorsqu'on relance un rendu.
def load(path, color):
	img = bpy.data.images.load(path, check_existing=False)
	img.colorspace_settings.name = "sRGB" if color else "Non-Color"
	return img


# Cette méthode permet de construire un matériau PBR (Color, Rough, Metal, Normal en tangent) pour un préfixe de cartes.
def pbr_material(name, prefix):
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	nt = mat.node_tree
	bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
	for kind, sock, color in (("Color", "Base Color", True), ("Rough", "Roughness", False), ("Metal", "Metallic", False)):
		t = nt.nodes.new("ShaderNodeTexImage")
		t.image = load(tex_path(prefix, kind), color)
		nt.links.new(t.outputs["Color"], bsdf.inputs[sock])
	t = nt.nodes.new("ShaderNodeTexImage")
	t.image = load(tex_path(prefix, "Normal"), False)
	nm = nt.nodes.new("ShaderNodeNormalMap")
	nt.links.new(t.outputs["Color"], nm.inputs["Color"])
	nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
	return mat


if WEAPON == "m9":
	for o in list(bpy.data.objects):
		bpy.data.objects.remove(o)
	bpy.ops.import_scene.gltf(filepath=opt("--glb", ""))
	mat = pbr_material("Handle_skin", "Handle")
	meshes = [o for o in scene.objects if o.type == "MESH"]
	for o in meshes:
		o.data.materials.clear()
		o.data.materials.append(mat)
else:
	meshes = [o for o in scene.objects if o.type == "MESH" and o.visible_get()]
	for o in meshes:
		m = o.data.materials[0] if o.data.materials else None
		if m and m.name.endswith("_PBR"):
			o.data.materials[0] = pbr_material(m.name + "_skin", m.name[: -len("_PBR")])
	for o in list(scene.objects):
		if o.type == "LIGHT":
			bpy.data.objects.remove(o)

# Éclairage : HDRI de Blender (reflets) + une lumière de découpe douce
world = bpy.data.worlds.new("skin_world")
scene.world = world
world.use_nodes = True
wnt = world.node_tree
bg = next(n for n in wnt.nodes if n.type == "BACKGROUND")
env = wnt.nodes.new("ShaderNodeTexEnvironment")
hdri_dir = os.path.join(bpy.utils.system_resource("DATAFILES"), "studiolights", "world")
env.image = bpy.data.images.load(os.path.join(hdri_dir, HDRI + ".exr"))
mapping = wnt.nodes.new("ShaderNodeMapping")
coord = wnt.nodes.new("ShaderNodeTexCoord")
wnt.links.new(coord.outputs["Generated"], mapping.inputs["Vector"])
wnt.links.new(mapping.outputs["Vector"], env.inputs["Vector"])
wnt.links.new(env.outputs["Color"], bg.inputs["Color"])
bg.inputs["Strength"].default_value = 1.0
mapping.inputs["Rotation"].default_value = (0, 0, math.radians(float(opt("--hdri-rot", "40"))))

pts = np.array([o.matrix_world @ v.co for o in meshes for v in o.data.vertices])
center = Vector(pts.mean(0))
_, _, vt = np.linalg.svd(pts - pts.mean(0), full_matrices=False)
axis, side, flat = (Vector(v) for v in vt)  # longueur, hauteur, épaisseur
proj = (pts - pts.mean(0)) @ vt[0]
length = float(proj.max() - proj.min())

cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

key_data = bpy.data.lights.new("key", "AREA")
key_data.energy = 60 * length**2
key_data.size = length * 0.6
key = bpy.data.objects.new("key", key_data)
scene.collection.objects.link(key)


# Cette méthode permet de placer la caméra (droite r, haut u à l'écran) à une distance donnée du centre visé, et la
# lumière principale au-dessus à gauche, lorsqu'on rend une vue.
def place(r, u, dist, focal, target=None, shift=(0, 0)):
	r, u = r.normalized(), u.normalized()
	f = u.cross(r)  # direction de visée
	t = target if target is not None else center
	cam.matrix_world = Matrix.Translation(t - f * dist) @ Matrix((r, u, -f)).transposed().to_4x4()
	cam_data.lens = focal
	cam_data.shift_x, cam_data.shift_y = shift
	cam_data.clip_start = dist * 0.01
	cam_data.clip_end = dist * 10
	kp = t - f * dist * 0.8 + u * dist * 0.9 - r * dist * 0.5
	key.matrix_world = Matrix.Translation(kp) @ (t - kp).to_track_quat("-Z", "Y").to_matrix().to_4x4()


views = {}
if WEAPON == "m9":
	# La pointe est du côté des projections négatives sur l'axe principal (cf. bake : lame en bas du dépliage)
	tip = -axis
	other = flat.cross(axis)
	# Pointe en haut à gauche de l'image, comme les vignettes d'inventaire de référence ; « revers » = autre face
	views["inventaire"] = lambda: place(axis + other, tip + other, length * 1.85, 50)
	views["revers"] = lambda: place(axis - other, tip - other, length * 1.85, 50)
	views["lame"] = lambda: place(axis + other * 0.3, other - axis * 0.3 + flat * 0.4, length * 1.3, 60, center + tip * length * 0.22)
else:
	X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
	views["profil"] = lambda: place(X, Z, length * 1.15, 50)
	views["profil_droit"] = lambda: place(-X, Z, length * 1.15, 50)
	act = center + X * (-length * 0.12)
	views["trois_quarts"] = lambda: place(X + Y * 0.55, Z + Y * -0.35, length * 0.95, 50, act)
	views["crosse"] = lambda: place(-X * 0.8 - Y * 0.6, Z + Y * 0.3, length * 0.75, 50, center + X * (-length * 0.3))

wanted = VIEWS.split(",") if VIEWS else list(views)
for name in wanted:
	views[name]()
	scene.render.filepath = os.path.abspath(f"{OUT}_{name}.png")
	t0 = time.time()
	bpy.ops.render.render(write_still=True)
	print(f"[render] {name} {time.time() - t0:.1f}s -> {scene.render.filepath}")
