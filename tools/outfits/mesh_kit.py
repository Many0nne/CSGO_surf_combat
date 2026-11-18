"""Outils communs aux volumes ajoutés des tenues (#521), dans Blender sans interface : primitives arrondies, booléens,
pose sur le rig au repos, rapport pieces.json, export FBX et aperçu face / trois quarts / dos.

Repère Blender du dépôt : avant du personnage +Y, haut +Z, sa droite +X ; Roblox = (x, z, -y). Chaque volume est modelé
dans l'espace de la pièce du rig qui le porte, puis posé sur le rig au repos (REST).
Repris de assets/outfits/demineur/demineur_meshes.py (qui garde sa copie, déjà publiée).
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# Centre de chaque pièce du rig au repos (Roblox, studs, racine à l'origine), relevé sur le StarterCharacter
TORSO_W, LIMB = 3.1764, 1.5882
ARM_X, LEG_X = TORSO_W / 2 + LIMB / 2, TORSO_W / 4
REST = {"UpperTorso": (0, 0.3176), "LowerTorso": (0, -1.2706), "Head": (0, 2.3823)}
for _side, _sx in (("Left", -1), ("Right", 1)):
	REST[_side + "UpperArm"] = (_sx * ARM_X, 0.5855)
	REST[_side + "LowerArm"] = (_sx * ARM_X, -0.3559)
	REST[_side + "Hand"] = (_sx * ARM_X, -1.35)
	REST[_side + "UpperLeg"] = (_sx * LEG_X, -2.2565)
	REST[_side + "LowerLeg"] = (_sx * LEG_X, -3.4955)
	REST[_side + "Foot"] = (_sx * LEG_X, -4.5264)


# Cette méthode permet de lire les arguments placés après `--` sur la ligne de commande de Blender.
def args():
	return sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []


# Cette méthode permet de lire la valeur d'une option (`--fbx <chemin>`) en chemin absolu, ou None si elle manque.
def arg(name):
	a = args()
	return os.path.abspath(a[a.index(name) + 1]) if name in a else None


# Cette méthode permet de créer un objet maillé à partir d'un bmesh lorsqu'on modèle un volume.
def to_object(name, bm):
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	ob = bpy.data.objects.new(name, mesh)
	bpy.context.scene.collection.objects.link(ob)
	return ob


# Cette méthode permet d'appliquer les modificateurs d'un objet lorsqu'il est fini, pour exporter la forme vue.
def apply_all(ob):
	bpy.context.view_layer.objects.active = ob
	for m in list(ob.modifiers):
		bpy.ops.object.modifier_apply(modifier=m.name)


# Cette méthode permet d'ajouter un biseau à un objet et de l'appliquer lorsqu'on arrondit ses arêtes.
def bevel(ob, width, segments=2):
	m = ob.modifiers.new("bevel", "BEVEL")
	m.width = width
	m.segments = segments
	m.limit_method = "NONE"
	apply_all(ob)
	return ob


# Cette méthode permet de créer un pavé arrondi (min, max en studs) lorsqu'on modèle un sac ou une plaque.
def rounded_box(name, lo, hi, width, segments=3):
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1)
	size = Vector(hi) - Vector(lo)
	center = (Vector(hi) + Vector(lo)) / 2
	bmesh.ops.scale(bm, vec=size, verts=bm.verts)
	bmesh.ops.translate(bm, vec=center, verts=bm.verts)
	ob = to_object(name, bm)
	return bevel(ob, width, segments) if width > 0 else ob


# Cette méthode permet de soustraire un volume à un autre (booléen exact) lorsqu'on évide un cadre.
def cut(ob, tool):
	m = ob.modifiers.new("cut", "BOOLEAN")
	m.operation = "DIFFERENCE"
	m.solver = "EXACT"
	m.object = tool
	apply_all(ob)
	bpy.data.objects.remove(tool)


# Cette méthode permet de ne garder d'un volume que sa partie commune avec un autre (booléen exact) lorsqu'on découpe
# une coque selon un contour arrondi (visière, masque).
def intersect(ob, tool):
	m = ob.modifiers.new("keep", "BOOLEAN")
	m.operation = "INTERSECT"
	m.solver = "EXACT"
	m.object = tool
	apply_all(ob)
	bpy.data.objects.remove(tool)
	return ob


# Cette méthode permet de fusionner plusieurs objets en un seul (le premier) lorsqu'une MeshPart regroupe plusieurs
# formes de même couleur.
def join(obs):
	with bpy.context.temp_override(active_object=obs[0], selected_editable_objects=obs):
		bpy.ops.object.join()
	return obs[0]


# Cette méthode permet de créer une portion de cylindre vertical (angle en degrés autour de l'avant +Y, rayons r0 à
# r1, hauteur de z0 à z1) lorsqu'on modèle une visière ou un masque sur la tête.
def arc_shell(name, r0, r1, half_angle, z0, z1, steps=24):
	bm = bmesh.new()
	grid = {}
	for ri, r in enumerate((r0, r1)):
		for i in range(steps + 1):
			a = math.radians(-half_angle + 2 * half_angle * i / steps)
			for zi, z in enumerate((z0, z1)):
				grid[ri, zi, i] = bm.verts.new((math.sin(a) * r, math.cos(a) * r, z))
	for i in range(steps):
		for ri in range(2):
			bm.faces.new([grid[ri, 0, i], grid[ri, 0, i + 1], grid[ri, 1, i + 1], grid[ri, 1, i]])
		for zi in range(2):
			bm.faces.new([grid[0, zi, i], grid[0, zi, i + 1], grid[1, zi, i + 1], grid[1, zi, i]])
	for i in (0, steps):
		bm.faces.new([grid[0, 0, i], grid[1, 0, i], grid[1, 1, i], grid[0, 1, i]])
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return to_object(name, bm)


# Cette méthode permet d'importer la coque de tête classique (mesh de la tête Roblox, 1,98 × 1,99 × 1,98) agrandie de
# `scale` et remontée de `lift`, lorsqu'une tenue couvre la tête (casque, cagoule).
def head_shell(name, scale, lift=0.0):
	before = set(bpy.data.objects)
	bpy.ops.import_scene.fbx(filepath=os.path.join(ROOT, "assets", "outfits", "mercure", "MercureHead.fbx"))
	new = [o for o in bpy.data.objects if o not in before]
	shell = next(o for o in new if o.type == "MESH")
	for o in new:
		if o is not shell:
			bpy.data.objects.remove(o)
	shell.parent = None
	shell.name = name
	bpy.context.view_layer.update()
	ws = [shell.matrix_world @ v.co for v in shell.data.vertices]
	lo = Vector([min(w[i] for w in ws) for i in range(3)])
	hi = Vector([max(w[i] for w in ws) for i in range(3)])
	center, size = (lo + hi) / 2, hi - lo
	target = Vector((1.98 * scale[0], 1.98 * scale[1], 1.99 * scale[2]))
	mat = (
		Matrix.Translation((0, 0, lift))
		@ Matrix.Diagonal((target.x / size.x, target.y / size.y, target.z / size.z, 1))
		@ Matrix.Translation(-center)
	)
	shell.data.transform(mat @ shell.matrix_world)
	shell.matrix_world = Matrix.Identity(4)
	shell.data.materials.clear()
	return shell


# Cette méthode permet de lire le centre de la boîte englobante d'un objet (repère de sa pièce) lorsqu'on calcule le
# décalage de la MeshPart : Roblox place une MeshPart au centre de la boîte de son mesh.
def bbox_center(ob):
	ws = [v.co for v in ob.data.vertices]
	return Vector([(min(w[i] for w in ws) + max(w[i] for w in ws)) / 2 for i in range(3)])


# Cette méthode permet de donner à un objet une matière unie (aperçu) lorsqu'on rend la planche.
def flat_material(ob, rgb):
	mat = bpy.data.materials.new(ob.name)
	mat.diffuse_color = (*[(c / 255) ** 2.2 for c in rgb], 1)
	ob.data.materials.clear()
	ob.data.materials.append(mat)


# Cette méthode permet d'écrire pieces.json (pièce, décalage, aspect de chaque volume) puis de poser les volumes sur le
# rig au repos lorsqu'une tenue a fini de modeler ; `pieces` = [(objet, pièce du rig, aspect, cache la tête)].
def report(pieces, looks, out_json):
	entries = []
	for ob, attach, look, hides_head in pieces:
		c = bbox_center(ob)
		entry = {"name": ob.name, "attach": attach, "offset": [round(c.x, 4), round(c.z, 4), round(-c.y, 4)]}
		entry.update(looks[look])
		if hides_head:
			entry["hidesHead"] = True
		entries.append(entry)
		flat_material(ob, looks[look]["color"])
	with open(out_json, "w", encoding="utf-8") as f:
		json.dump(entries, f, indent=1, ensure_ascii=False)
	for ob, attach, _, _ in pieces:
		x, y = REST[attach]
		ob.matrix_world = Matrix.Translation((x, 0, y))


# Cette méthode permet d'exporter en FBX tous les volumes posés lorsqu'on publie le modèle des pièces.
def export_fbx(path):
	sys.argv = [sys.argv[0], "--", path]
	exec(compile(open(os.path.join(ROOT, "tools", "export_mesh_fbx.py"), encoding="utf-8").read(), "export", "exec"))


# Cette méthode permet d'importer le rig habillé des cartes cuites (couleur seule) lorsqu'on rend l'aperçu.
def import_rig(rig_dir, maps):
	groups = {"UpperTorso": "Torso", "LowerTorso": "Torso"}
	for side in ("Left", "Right"):
		for p in ("UpperArm", "LowerArm", "Hand"):
			groups[side + p] = side + "Arm"
		for p in ("UpperLeg", "LowerLeg", "Foot"):
			groups[side + p] = side + "Leg"
	for part, group in groups.items():
		bpy.ops.wm.obj_import(filepath=os.path.join(rig_dir, part + ".obj"), forward_axis="Y", up_axis="Z")
		ob = bpy.context.selected_objects[0]
		x, y = REST[part]
		ob.matrix_world = Matrix.Translation((x, 0, y))
		mat = bpy.data.materials.new(part)
		mat.use_nodes = True
		nodes = mat.node_tree.nodes
		bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
		tex = nodes.new("ShaderNodeTexImage")
		tex.image = bpy.data.images.load(os.path.join(maps, group + "_Color.png"), check_existing=True)
		mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
		nodes.active = tex
		ob.data.materials.clear()
		ob.data.materials.append(mat)


# Cette méthode permet de rendre l'aperçu (face, trois quarts, dos) en Workbench lorsqu'on compare la tenue à la
# planche de concept.
def render_preview(out_dir, prefix):
	scene = bpy.context.scene
	try:
		scene.render.engine = "BLENDER_WORKBENCH"
	except TypeError as e:
		print(e)
	sh = scene.display.shading
	sh.light = "STUDIO"
	sh.color_type = "TEXTURE"
	sh.show_cavity = True
	sh.show_object_outline = False
	sh.background_type = "VIEWPORT"
	sh.background_color = (1, 1, 1)
	scene.view_settings.view_transform = "Standard"
	scene.render.resolution_x = scene.render.resolution_y = 1024
	cam_data = bpy.data.cameras.new("cam")
	cam_data.type = "ORTHO"
	cam_data.ortho_scale = 11.5
	cam = bpy.data.objects.new("cam", cam_data)
	scene.collection.objects.link(cam)
	scene.camera = cam
	os.makedirs(out_dir, exist_ok=True)
	# Le personnage regarde vers +Y : la caméra de face est en +Y
	for name, angle, elev in (("face", 180, 0), ("trois_quarts", 180 - 35, 12), ("dos", 0, 0)):
		a, e = math.radians(angle), math.radians(elev)
		cam.location = (math.sin(a) * math.cos(e) * 40, -math.cos(a) * math.cos(e) * 40, -0.4 + math.sin(e) * 40)
		cam.rotation_euler = (math.radians(90) - e, 0, a)
		scene.render.filepath = os.path.join(out_dir, f"{prefix}_{name}.png")
		bpy.ops.render.render(write_still=True)
