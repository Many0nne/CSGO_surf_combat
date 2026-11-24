"""Rend une miniature de la page du jeu (#524) : viewmodel du jeu (bras compris) habillé d'un skin, sous un ciel de jour.

Le viewmodel vient de `tools/preview/fetch_viewmodel.py <Viewmodel> <x.glb> --arms` (meshs, placement et couleurs des
pièces tels que dans le jeu) ; les cartes du skin sont celles du dépôt, `assets/skins/<skin>/<Viewmodel>/`. Rien n'est
redessiné : le skin rendu est celui du jeu. Le plan (caméra, pose de l'arme, lumière) est décrit par un JSON.

Usage :
  blender -b --factory-startup --python tools/promo/render_thumb.py -- <plan.json> <sortie.png> [--engine workbench]
    [--samples N] [--res LxH]

Plan (repère Roblox, studs ; exemples : tools/promo/shots/*.json, procédure : docs/promo.md « Fabrication ») :
  glb, skin_dir                  viewmodel et dossier des cartes du skin (relatifs à la racine du dépôt)
  parts                          pièce -> préfixe de cartes (AWP : _parts de assets/awp/texture_ids.json)
  hide                           pièces masquées (bras, lunette...)
  camera: {pos, look, fov, roll, pitch}  position, point visé, champ vertical, roulis et tangage ajouté (degrés)
  align: {...}                   pose automatique de l'arme : axe long selon dir (écran), flanc vers la caméra, avant-bras
                                 vers arm_dir, main posée en at_screen [x, y, distance] (anchor "hand")
  figures: [{glb, at|at_screen, rot, weapon: {glb, skin_dir, parts, aim_camera, aim_drop}}]  personnages armés
  shot: {to_figure|to, width, rgb, strength, flash: {size, strength}}  rayon de la balle et flamme de bouche
  sun: {elevation, azimuth, strength}  azimut 0 = soleil derrière une caméra qui regarde -Z (pas de contre-jour)
  sky, backdrop: {stops, glow_power, glow_color}, fills, exposure, view, look, plain_color, plain_roughness
  skin_glow                      émission de la couleur du skin (0,6 : motifs lisibles même où le métal reflète le ciel)
  shadows: false                 le soleil ne projette plus d'ombre
"""

import json
import math
import os
import sys

import bpy
from mathutils import Euler, Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :]
PLAN_PATH, OUT = argv[0], argv[1]
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


# Cette méthode permet de lire une option --nom valeur de la ligne de commande lorsqu'elle est donnée.
def opt(name, default):
	return argv[argv.index(name) + 1] if name in argv else default


with open(PLAN_PATH, encoding="utf-8") as f:
	PLAN = json.load(f)


# Cette méthode permet de résoudre un chemin du plan (relatif à la racine du dépôt, ou absolu).
def path(p):
	return p if os.path.isabs(p) else os.path.join(ROOT, p)


# Cette méthode permet de passer un point du repère Roblox (Y en haut) au repère de Blender après import glTF (Z en haut).
def rb(v):
	return Vector((v[0], -v[2], v[1]))


scene = bpy.context.scene
for o in list(bpy.data.objects):
	bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=path(PLAN["glb"]))
meshes = [o for o in scene.objects if o.type == "MESH"]


# Cette méthode permet de construire un matériau PBR à partir des quatre cartes d'un préfixe du skin.
def pbr_material(prefix, skin_dir=None):
	skin_dir = path(skin_dir or PLAN["skin_dir"])
	mat = bpy.data.materials.new(prefix)
	mat.use_nodes = True
	nt = mat.node_tree
	bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
	for kind, sock, color in (("Color", "Base Color", True), ("Rough", "Roughness", False), ("Metal", "Metallic", False)):
		t = nt.nodes.new("ShaderNodeTexImage")
		t.image = bpy.data.images.load(os.path.join(skin_dir, f"{prefix}_{kind}.png"))
		t.image.colorspace_settings.name = "sRGB" if color else "Non-Color"
		nt.links.new(t.outputs["Color"], bsdf.inputs[sock])
		# `skin_glow` : le skin émet sa propre couleur, lisible même quand le métal ne reflète que le ciel
		if color and PLAN.get("skin_glow"):
			nt.links.new(t.outputs["Color"], bsdf.inputs["Emission Color"])
			bsdf.inputs["Emission Strength"].default_value = PLAN["skin_glow"]
	t = nt.nodes.new("ShaderNodeTexImage")
	t.image = bpy.data.images.load(os.path.join(skin_dir, f"{prefix}_Normal.png"))
	t.image.colorspace_settings.name = "Non-Color"
	nm = nt.nodes.new("ShaderNodeNormalMap")
	nt.links.new(t.outputs["Color"], nm.inputs["Color"])
	nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
	return mat


# Cette méthode permet de donner aux pièces sans cartes (bras, verre de lunette) un matériau plat de la couleur du jeu,
# comme Roblox rend une MeshPart en SmoothPlastic.
def plain_material(obj, tint=True):
	src = obj.data.materials[0] if obj.data.materials else None
	color = (0.6, 0.6, 0.6, 1)
	if src and src.use_nodes:
		b = next((n for n in src.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
		if b:
			color = tuple(b.inputs["Base Color"].default_value)
	# Bras blancs dans le jeu, vus gris clair sous sa lumière : `plain_color` donne la teinte rendue
	if tint and "plain_color" in PLAN:
		color = (*PLAN["plain_color"], 1)
	mat = bpy.data.materials.new(obj.name + "_plain")
	mat.use_nodes = True
	b = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
	b.inputs["Base Color"].default_value = color
	b.inputs["Roughness"].default_value = PLAN.get("plain_roughness", 0.55)
	if obj.name == "ScopeLens":
		b.inputs["Base Color"].default_value = (0.02, 0.03, 0.05, 1)
		b.inputs["Roughness"].default_value = 0.05
	mat.diffuse_color = color
	return mat


cache = {}
hide = set(PLAN.get("hide", []))
for o in meshes:
	name = o.name.split(".")[0]
	if name in hide:
		o.hide_render = True
		continue
	prefix = PLAN["parts"].get(name)
	if prefix:
		cache.setdefault(prefix, pbr_material(prefix))
		mat = cache[prefix]
	else:
		mat = plain_material(o)
	o.data.materials.clear()
	o.data.materials.append(mat)

# Caméra
c = PLAN["camera"]
cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
pos, look = rb(c["pos"]), rb(c["look"])
cam.matrix_world = Matrix.Translation(pos) @ (look - pos).to_track_quat("-Z", "Y").to_matrix().to_4x4()
cam.matrix_world = cam.matrix_world @ Matrix.Rotation(math.radians(c.get("roll", 0)), 4, "Z")
# pitch : le joueur lève la tête ; caméra et viewmodel tournent ensemble autour de l'œil, comme en jeu
if c.get("pitch"):
	pm = (
		Matrix.Translation(pos)
		@ Matrix.Rotation(math.radians(c["pitch"]), 4, cam.matrix_world.to_3x3().col[0])
		@ Matrix.Translation(-pos)
	)
	cam.matrix_world = pm @ cam.matrix_world
	for o in meshes:
		o.matrix_world = pm @ o.matrix_world


# Cette méthode permet de donner un point du monde à partir d'une position dans l'image ([x, y] de -1 à 1, 16:9) et
# d'une distance à la caméra.
def screen_point(x, y, dist):
	cm = cam.matrix_world.to_3x3()
	ty = math.tan(math.radians(c.get("fov", 70)) / 2)
	return pos - cm.col[2] * dist + cm.col[0] * (x * dist * ty * 16 / 9) + cm.col[1] * (y * dist * ty)



# Cette méthode permet de poser l'arme face à la caméra lorsque le plan donne `align` : son grand axe suit une direction
# à l'écran (dir), son flanc (plus petit axe) regarde la caméra, puis la pose est inclinée (tilt, spin) ; le viewmodel
# entier tourne avec elle pour que la main reste sur la poignée, et le centre de l'arme vient en `at`.
def align_weapon(a):
	import numpy as np

	names = set(a.get("parts") or PLAN["parts"].keys())
	pts = np.array([o.matrix_world @ v.co for o in meshes if o.name.split(".")[0] in names for v in o.data.vertices])
	center = Vector(pts.mean(0))
	_, _, vt = np.linalg.svd(pts - pts.mean(0), full_matrices=False)
	axis, side, flat = (Vector(v) for v in vt)
	if a.get("flip_tip"):
		axis = -axis
	if a.get("flip_face"):
		flat = -flat
	src = Matrix((axis, flat.cross(axis), flat)).transposed()
	cm = cam.matrix_world.to_3x3()
	r, u, back = cm.col[0], cm.col[1], cm.col[2]
	sx, sy = a.get("dir", [-0.7, 0.7])
	d_axis = (r * sx + u * sy).normalized()
	d_flat = back.normalized()
	dst = Matrix((d_axis, d_flat.cross(d_axis), d_flat)).transposed()
	base = (dst @ src.inverted()).to_4x4()
	tilt_axis = (r * sx + u * sy).cross(back).normalized()

	# Cette méthode permet de composer la pose finale (pose de face, puis inclinaison et rotation autour de l'axe).
	def pose(tilt, spin):
		return Matrix.Rotation(math.radians(spin), 4, d_axis) @ Matrix.Rotation(math.radians(tilt), 4, tilt_axis) @ base

	tilt, spin = a.get("tilt", 0), a.get("spin", 0)
	# arm_dir : cherche l'inclinaison (±max_dev) qui envoie l'avant-bras (main -> coude) vers cette direction de l'écran,
	# sans qu'il vienne vers la caméra
	arm = a.get("arm_dir")
	by_name = {o.name.split(".")[0]: o for o in meshes}
	hand_name, fore_name = a.get("hand", "RightHand"), a.get("forearm", "RightLowerArm")

	# Cette méthode permet de donner le centre d'une pièce dans le monde (moyenne de ses sommets).
	def part_center(name):
		o = by_name[name]
		return sum((o.matrix_world @ v.co for v in o.data.vertices), Vector()) / len(o.data.vertices)

	hand0, fore0 = part_center(hand_name), part_center(fore_name)
	if arm:
		want = (r * arm[0] + u * arm[1]).normalized()
		dev = a.get("max_dev", 50)
		best = None
		for t in range(-dev, dev + 1, 5):
			for s in range(-dev, dev + 1, 5):
				m3 = pose(t, s).to_3x3()
				v = m3 @ (fore0 - hand0)
				toward = v.dot(back) / v.length  # > 0 : vers la caméra
				proj = (v - back * v.dot(back)).normalized()
				score = -proj.dot(want) + max(0, toward - a.get("max_toward", 0.3)) * 3 + (abs(t) + abs(s)) * 0.002
				if best is None or score < best[0]:
					best = (score, t, s)
		_, tilt, spin = best
		print(f"[render_thumb] align : tilt {tilt}, spin {spin}")
	rot = pose(tilt, spin)
	# Point posé en `at` : la main (hand_at) ou le centre de l'arme
	at = rb(a["at"]) if "at" in a else look
	if "at_screen" in a:
		# [x, y, distance] : x, y de -1 à 1 dans l'image (16:9), à cette distance de la caméra
		x, y, dist = a["at_screen"]
		ty = math.tan(math.radians(c.get("fov", 70)) / 2)
		at = pos - back * dist + r * (x * dist * ty * 16 / 9) + u * (y * dist * ty)
	anchor = hand0 if a.get("anchor") == "hand" else center
	m = Matrix.Translation(at) @ rot @ Matrix.Translation(-anchor)
	for o in meshes:
		o.matrix_world = m @ o.matrix_world


if "align" in PLAN:
	align_weapon(PLAN["align"])
cam_data.sensor_fit = "VERTICAL"
cam_data.angle_y = math.radians(c.get("fov", 70))
cam_data.clip_start = 0.01
cam_data.clip_end = 100000
dof = PLAN.get("dof")
if dof:
	cam_data.dof.use_dof = True
	cam_data.dof.focus_distance = dof["focus"]
	cam_data.dof.aperture_fstop = dof["fstop"]

# Ciel de jour : texture de ciel physique + soleil
sun = PLAN.get("sun", {})
elev, azim = math.radians(sun.get("elevation", 35)), math.radians(sun.get("azimuth", 200))
world = bpy.data.worlds.new("sky")
scene.world = world
world.use_nodes = True
wnt = world.node_tree
bg = next(n for n in wnt.nodes if n.type == "BACKGROUND")
sky = wnt.nodes.new("ShaderNodeTexSky")
sky_cfg = PLAN.get("sky", {})
for prop, val in (("sun_elevation", elev), ("sun_rotation", azim), ("air_density", sky_cfg.get("air", 1.0)), ("ozone_density", sky_cfg.get("ozone", 1.0)), ("aerosol_density", sky_cfg.get("dust", 0.6))):
	if hasattr(sky, prop):
		try:
			setattr(sky, prop, val)
		except (TypeError, AttributeError):
			pass
if hasattr(sky, "sun_disc"):
	# Pas de disque solaire dans le ciel d'éclairage : la lampe soleil s'en charge (sinon tout sature au blanc)
	sky.sun_disc = sky_cfg.get("sun_disc", False)
wnt.links.new(sky.outputs["Color"], bg.inputs["Color"])
bg.inputs["Strength"].default_value = sky_cfg.get("strength", 0.25)
sun_dir = Vector((math.cos(elev) * math.sin(azim), -math.cos(elev) * math.cos(azim), math.sin(elev)))


# Cette méthode permet de construire le fond vu par la caméra (ciel bleu saturé en dégradé, mer de nuages sous l'horizon,
# halo du soleil) lorsque le plan le demande ; l'éclairage reste celui du ciel physique.
def backdrop(cfg):
	out = next(n for n in wnt.nodes if n.type == "OUTPUT_WORLD")
	coord = wnt.nodes.new("ShaderNodeTexCoord")
	sep = wnt.nodes.new("ShaderNodeSeparateXYZ")
	wnt.links.new(coord.outputs["Generated"], sep.inputs["Vector"])
	ramp = wnt.nodes.new("ShaderNodeValToRGB")
	wnt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
	el = ramp.color_ramp.elements
	stops = cfg.get(
		"stops",
		[[0.0, [0.93, 0.95, 1.0]], [0.47, [0.86, 0.92, 1.0]], [0.5, [0.62, 0.85, 1.0]], [0.62, [0.18, 0.55, 1.0]], [1.0, [0.03, 0.2, 0.75]]],
	)
	# Generated d'un monde : direction de vue ; Z de -1 (sol) à 1 (zénith), ramené à 0..1 par la rampe
	map_z = wnt.nodes.new("ShaderNodeMapRange")
	map_z.inputs["From Min"].default_value = -1
	wnt.links.new(sep.outputs["Z"], map_z.inputs["Value"])
	wnt.links.new(map_z.outputs["Result"], ramp.inputs["Fac"])
	el[0].position, el[0].color = stops[0][0], (*stops[0][1], 1)
	el[1].position, el[1].color = stops[-1][0], (*stops[-1][1], 1)
	for pos, col in stops[1:-1]:
		e = el.new(pos)
		e.color = (*col, 1)
	# Nuages : bruit sous l'horizon, blanc sur le dégradé
	noise = wnt.nodes.new("ShaderNodeTexNoise")
	noise.inputs["Scale"].default_value = cfg.get("cloud_scale", 6)
	noise.inputs["Detail"].default_value = 8
	wnt.links.new(coord.outputs["Generated"], noise.inputs["Vector"])
	below = wnt.nodes.new("ShaderNodeMapRange")
	below.inputs["From Min"].default_value = 0.02
	below.inputs["From Max"].default_value = -0.15
	wnt.links.new(sep.outputs["Z"], below.inputs["Value"])
	cl = wnt.nodes.new("ShaderNodeMath")
	cl.operation = "MULTIPLY"
	wnt.links.new(noise.outputs["Fac"], cl.inputs[0])
	wnt.links.new(below.outputs["Result"], cl.inputs[1])
	mix_c = wnt.nodes.new("ShaderNodeMix")
	mix_c.data_type = "RGBA"
	mix_c.blend_type = "SCREEN"
	wnt.links.new(cl.outputs["Value"], mix_c.inputs["Factor"])
	wnt.links.new(ramp.outputs["Color"], mix_c.inputs["A"])
	mix_c.inputs["B"].default_value = (1, 1, 1, 1)
	# Halo du soleil
	dot = wnt.nodes.new("ShaderNodeVectorMath")
	dot.operation = "DOT_PRODUCT"
	wnt.links.new(coord.outputs["Generated"], dot.inputs[0])
	dot.inputs[1].default_value = sun_dir
	glow = wnt.nodes.new("ShaderNodeMath")
	glow.operation = "POWER"
	wnt.links.new(dot.outputs["Value"], glow.inputs[0])
	glow.inputs[1].default_value = cfg.get("glow_power", 40)
	add = wnt.nodes.new("ShaderNodeMix")
	add.data_type = "RGBA"
	add.blend_type = "ADD"
	wnt.links.new(glow.outputs["Value"], add.inputs["Factor"])
	wnt.links.new(mix_c.outputs["Result"], add.inputs["A"])
	add.inputs["B"].default_value = (*cfg.get("glow_color", [1.0, 0.95, 0.85]), 1)
	cam_bg = wnt.nodes.new("ShaderNodeBackground")
	wnt.links.new(add.outputs["Result"], cam_bg.inputs["Color"])
	cam_bg.inputs["Strength"].default_value = cfg.get("strength", 1.0)
	path_n = wnt.nodes.new("ShaderNodeLightPath")
	mix = wnt.nodes.new("ShaderNodeMixShader")
	wnt.links.new(path_n.outputs["Is Camera Ray"], mix.inputs["Fac"])
	wnt.links.new(bg.outputs["Background"], mix.inputs[1])
	wnt.links.new(cam_bg.outputs["Background"], mix.inputs[2])
	wnt.links.new(mix.outputs["Shader"], out.inputs["Surface"])


if "backdrop" in PLAN:
	backdrop(PLAN["backdrop"])

sun_data = bpy.data.lights.new("sun", "SUN")
sun_data.energy = sun.get("strength", 4.0)
sun_data.angle = math.radians(1.5)
sun_obj = bpy.data.objects.new("sun", sun_data)
scene.collection.objects.link(sun_obj)
sun_obj.matrix_world = sun_dir.to_track_quat("Z", "Y").to_matrix().to_4x4()
# `shadows: false` : le soleil n'ombre plus l'arme (bras, lunette, pièces entre elles)
if PLAN.get("shadows") is False:
	sun_data.use_shadow = False

# Lumière d'appoint (reflet sur l'arme), facultative : {pos, look, energy, size} en repère Roblox
for i, fill in enumerate(PLAN.get("fills", [])):
	ld = bpy.data.lights.new(f"fill{i}", "AREA")
	ld.energy = fill.get("energy", 50)
	ld.size = fill.get("size", 2)
	if "color" in fill:
		ld.color = fill["color"]
	lo = bpy.data.objects.new(f"fill{i}", ld)
	scene.collection.objects.link(lo)
	p = rb(fill["pos"])
	lo.matrix_world = Matrix.Translation(p) @ (rb(fill["look"]) - p).to_track_quat("-Z", "Y").to_matrix().to_4x4()

# Cette méthode permet d'importer un .glb et de renvoyer les objets maillés qu'il ajoute à la scène.
def import_glb(p):
	before = set(scene.objects)
	bpy.ops.import_scene.gltf(filepath=path(p))
	return [o for o in scene.objects if o not in before and o.type == "MESH"]


# Cette méthode permet de calculer l'axe principal (longueur) et le centre d'un groupe d'objets, pour poser une arme.
def principal(objs):
	import numpy as np

	pts = np.array([o.matrix_world @ v.co for o in objs for v in o.data.vertices])
	_, _, vt = np.linalg.svd(pts - pts.mean(0), full_matrices=False)
	return Vector(pts.mean(0)), [Vector(v) for v in vt]


# Cette méthode permet d'ajouter un personnage du jeu (tools/promo/fetch_character.py) : position et rotation de la
# racine (repère Roblox), visage sur la tête, et l'arme qu'il tient (viewmodel sans bras, posé dans sa main droite,
# canon dans la direction de son regard).
def add_figure(f):
	objs = import_glb(f["glb"])
	face = os.path.splitext(path(f["glb"]))[0] + "_face.png"
	r = f.get("rot", [0, 0, 0])
	rot = (
		Matrix.Rotation(math.radians(r[1]), 4, Vector((0, 0, 1)))
		@ Matrix.Rotation(math.radians(r[0]), 4, Vector((1, 0, 0)))
		@ Matrix.Rotation(math.radians(r[2]), 4, Vector((0, -1, 0)))
	)
	at = screen_point(*f["at_screen"]) if "at_screen" in f else rb(f["at"])
	m = Matrix.Translation(at) @ rot
	for o in objs:
		o.matrix_world = m @ o.matrix_world
		mat = plain_material(o, tint=False)
		if o.name.split(".")[0] == "Head" and os.path.exists(face):
			nt = mat.node_tree
			t = nt.nodes.new("ShaderNodeTexImage")
			t.image = bpy.data.images.load(face)
			nt.links.new(t.outputs["Color"], next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"])
		o.data.materials.clear()
		o.data.materials.append(mat)
	wpn = f.get("weapon")
	if not wpn:
		return objs
	wobjs = import_glb(wpn["glb"])
	keep = []
	for o in wobjs:
		name = o.name.split(".")[0]
		prefix = wpn["parts"].get(name)
		if prefix is None and name != "ScopeLens":
			bpy.data.objects.remove(o)
			continue
		mat = pbr_material(prefix, wpn["skin_dir"]) if prefix else plain_material(o, tint=False)
		o.data.materials.clear()
		o.data.materials.append(mat)
		keep.append(o)
	center, (axis, side, flat) = principal([o for o in keep if o.name.split(".")[0] in wpn["parts"]])
	barrel = next(o for o in keep if o.name.split(".")[0] == "Barrel")
	bc = sum((barrel.matrix_world @ v.co for v in barrel.data.vertices), Vector()) / len(barrel.data.vertices)
	if (bc - center).dot(axis) < 0:
		axis = -axis
	up = side if side.dot(Vector((0, 0, 1))) > 0 else -side
	hand = next(o for o in objs if o.name.split(".")[0] == "RightHand")
	hc = sum((hand.matrix_world @ v.co for v in hand.data.vertices), Vector()) / len(hand.data.vertices)
	fwd = (m.to_3x3() @ Vector((0, 1, 0))).normalized()  # -Z Roblox = +Y Blender
	aim = Vector(wpn.get("aim", fwd))
	if wpn.get("aim_camera"):
		# l'adversaire vise le joueur (caméra), un peu plus bas pour garder l'arme lisible
		aim = (pos - hc + Vector((0, 0, -wpn.get("aim_drop", 4)))).normalized()
	tgt_up = (m.to_3x3() @ Vector((0, 0, 1))).normalized()
	src = Matrix((axis, up, axis.cross(up))).transposed()
	tu = (tgt_up - aim * tgt_up.dot(aim)).normalized()
	dst = Matrix((aim, tu, aim.cross(tu))).transposed()
	wr = (dst @ src.inverted()).to_4x4()
	grip = center + axis * wpn.get("grip", -0.6) * 1.0
	wm = Matrix.Translation(hc + aim * wpn.get("forward", 0.4)) @ wr @ Matrix.Translation(-grip)
	for o in keep:
		o.matrix_world = wm @ o.matrix_world
	return objs


# Cette méthode permet de trouver le bout du canon du viewmodel de la scène (sommet du Barrel le plus loin du centre de
# l'arme le long de son axe), d'où partent la flamme et le rayon.
def muzzle():
	wobjs = [o for o in meshes if o.name.split(".")[0] in PLAN["parts"]]
	center, (axis, _, _) = principal(wobjs)
	barrel = next(o for o in meshes if o.name.split(".")[0] == "Barrel")
	pts = [barrel.matrix_world @ v.co for v in barrel.data.vertices]
	bc = sum(pts, Vector()) / len(pts)
	if (bc - center).dot(axis) < 0:
		axis = -axis
	return max(pts, key=lambda p: (p - center).dot(axis)), axis


# Cette méthode permet de créer un matériau émissif (rayon, flamme), comme une pièce Neon de Roblox.
def emissive(name, rgb, strength):
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	nt = mat.node_tree
	for n in list(nt.nodes):
		if n.type != "OUTPUT_MATERIAL":
			nt.nodes.remove(n)
	em = nt.nodes.new("ShaderNodeEmission")
	em.inputs["Color"].default_value = (*rgb, 1)
	em.inputs["Strength"].default_value = strength
	nt.links.new(em.outputs["Emission"], next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL").inputs["Surface"])
	return mat


figures = [add_figure(f) for f in PLAN.get("figures", [])]

shot = PLAN.get("shot")
if shot:
	tip, axis = muzzle()
	tip = tip + axis * shot.get("muzzle_offset", 0.05)
	if "to_figure" in shot:
		torso = next(o for o in figures[shot["to_figure"]] if o.name.split(".")[0] == "UpperTorso")
		target = sum((torso.matrix_world @ v.co for v in torso.data.vertices), Vector()) / len(torso.data.vertices)
	else:
		target = rb(shot["to"])
	# Rayon de la balle : ruban jaune pâle (TRACER_RGB, TRACER_WIDTH de ShotEffectRules)
	rgb = [c / 255 for c in shot.get("rgb", [255, 240, 180])]
	length = (target - tip).length
	bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=shot.get("width", 0.08) / 2, depth=length)
	ray = bpy.context.object
	ray.matrix_world = Matrix.Translation((tip + target) / 2) @ (target - tip).to_track_quat("Z", "Y").to_matrix().to_4x4()
	ray.data.materials.append(emissive("tracer", rgb, shot.get("strength", 6)))
	# Flamme : éclat chaud au bout du canon (le jeu émet MUZZLE_EMIT_COUNT particules)
	fl = shot.get("flash")
	if fl:
		size = fl.get("size", 0.25)
		fmat = emissive("flash", fl.get("rgb", [1.0, 0.62, 0.22]), fl.get("strength", 6))
		core = emissive("flash_core", [1.0, 0.92, 0.7], fl.get("strength", 6) * 1.5)
		orient = axis.to_track_quat("Z", "Y").to_matrix().to_4x4()
		# Cône vers l'avant et quatre pointes en étoile autour du canon, cœur clair
		bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=size * 0.7, radius2=0, depth=size * 4)
		cone = bpy.context.object
		cone.matrix_world = Matrix.Translation(tip + axis * size * 2) @ orient
		cone.data.materials.append(fmat)
		for k in range(4):
			bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=size * 0.25, radius2=0, depth=size * 2.4)
			spike = bpy.context.object
			spin = Matrix.Rotation(math.radians(45 + 90 * k), 4, axis)
			side_dir = (spin.to_3x3() @ orient.to_3x3().col[0]).normalized()
			d = (side_dir + axis * 0.5).normalized()
			spike.matrix_world = Matrix.Translation(tip + d * size * 1.2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
			spike.data.materials.append(fmat)
		bpy.ops.mesh.primitive_uv_sphere_add(radius=size * 0.45, segments=16, ring_count=8)
		ball = bpy.context.object
		ball.location = tip + axis * size * 0.3
		ball.data.materials.append(core)
		ld = bpy.data.lights.new("flash", "POINT")
		ld.energy = fl.get("light", 30)
		ld.color = fl.get("rgb", [1.0, 0.75, 0.35])
		lo = bpy.data.objects.new("flash", ld)
		lo.location = ball.location
		scene.collection.objects.link(lo)

# Rendu
res =[int(v) for v in opt("--res", "1920x1080").split("x")]
scene.render.resolution_x, scene.render.resolution_y = res
scene.render.resolution_percentage = 100
engine = opt("--engine", "cycles")
if engine == "workbench":
	scene.render.engine = "BLENDER_WORKBENCH"
	scene.display.shading.color_type = "TEXTURE"
	scene.display.shading.light = "STUDIO"
else:
	scene.render.engine = "CYCLES"
	scene.cycles.device = "CPU"
	scene.cycles.samples = int(opt("--samples", "64"))
	scene.cycles.use_denoising = True
	scene.view_settings.view_transform = PLAN.get("view", "AgX")
	try:
		scene.view_settings.look = PLAN.get("look", "AgX - Punchy")
	except TypeError:
		pass
scene.view_settings.exposure = PLAN.get("exposure", 0)
scene.render.film_transparent = PLAN.get("transparent", False)
scene.render.filepath = os.path.abspath(OUT)
bpy.ops.render.render(write_still=True)
print(f"[render_thumb] -> {scene.render.filepath}")
