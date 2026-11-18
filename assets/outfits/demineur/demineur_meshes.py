"""DÉMINEUR (#521) : volumes ajoutés au rig (casque, col, épaulières, plastron, tablier), d'après la planche de concept
validée (assets/outfits/concepts/demineur.png). Une MeshPart par couleur et par pièce du rig qui la porte ; couleur et
matière posées dans Studio d'après pieces.json (pas de texture).

Chaque volume est modelé dans l'espace de la pièce du rig qui le porte (repère Blender du dépôt : avant +Y, haut +Z,
droite du personnage +X ; Roblox = (x, z, -y)), puis posé sur le rig au repos pour l'export et l'aperçu.

Usage (Blender sans interface, depuis la racine du worktree) :
  blender -b --factory-startup --python assets/outfits/demineur/demineur_meshes.py -- <dossier des OBJ du rig>
    [--fbx <sortie.fbx>] [--preview <dossier>]
Écrit toujours assets/outfits/demineur/pieces.json (pièce du rig, décalage, couleur et matière de chaque volume).
Les OBJ du rig viennent de tools/outfits/rig_obj.py ; l'aperçu pose sur eux les cartes cuites (maps/base/R15).
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
ARGS = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
RIG_DIR = os.path.abspath(ARGS[0]) if ARGS else None


def arg(name):
	return os.path.abspath(ARGS[ARGS.index(name) + 1]) if name in ARGS else None


# Centre de chaque pièce du rig au repos (Roblox, studs, racine à l'origine) : hauteurs de r15_bake.OFFSETS, bras
# contre le torse, jambes sous chaque moitié du bassin (relevés sur le StarterCharacter le 18/11/2026)
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

# Couleurs (sRGB 0-255) et matières Roblox, reprises de la planche
OLIVE = (84, 92, 52)
BLACK = (34, 34, 32)
SAND = (184, 156, 96)
SMOKE = (30, 34, 38)
LOOK = {
	"olive": {"color": OLIVE, "material": "Plastic"},
	"black": {"color": BLACK, "material": "Fabric"},
	"plate": {"color": BLACK, "material": "Plastic"},
	"sand": {"color": SAND, "material": "SmoothPlastic"},
	"visor": {"color": SMOKE, "material": "SmoothPlastic", "reflectance": 0.25},
}

# Casque : la tête classique (1,98 × 1,99 × 1,98) agrandie
HELMET_SCALE = (1.13, 1.13, 1.1)
HELMET_R = 0.99 * 1.13


# Cette méthode permet de créer un objet maillé à partir d'un bmesh lorsqu'on modèle un volume.
def to_object(name, bm):
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	ob = bpy.data.objects.new(name, mesh)
	bpy.context.scene.collection.objects.link(ob)
	return ob


# Cette méthode permet d'appliquer les modificateurs d'un objet (biseau, booléen) lorsqu'il est fini, pour exporter
# la forme vue.
def apply_all(ob):
	bpy.context.view_layer.objects.active = ob
	for m in list(ob.modifiers):
		bpy.ops.object.modifier_apply(modifier=m.name)


# Cette méthode permet de créer un pavé arrondi (min, max en studs) lorsqu'on modèle une plaque ou un rembourrage.
def rounded_box(name, lo, hi, bevel, segments=3):
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1)
	size = Vector(hi) - Vector(lo)
	center = (Vector(hi) + Vector(lo)) / 2
	bmesh.ops.scale(bm, vec=size, verts=bm.verts)
	bmesh.ops.translate(bm, vec=center, verts=bm.verts)
	ob = to_object(name, bm)
	if bevel > 0:
		m = ob.modifiers.new("bevel", "BEVEL")
		m.width = bevel
		m.segments = segments
		m.limit_method = "NONE"
	apply_all(ob)
	return ob


# Cette méthode permet de créer une plaque plate de contour polygonal (points (x, z) dans le plan de la face avant),
# extrudée de y0 à y1, lorsqu'on modèle le plastron, le tablier et leurs liserés.
def slab(name, outline, y0, y1, bevel=0.0):
	bm = bmesh.new()
	verts = [bm.verts.new((x, y0, z)) for x, z in outline]
	face = bm.faces.new(verts)
	ext = bmesh.ops.extrude_face_region(bm, geom=[face])
	moved = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
	bmesh.ops.translate(bm, vec=(0, y1 - y0, 0), verts=moved)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	ob = to_object(name, bm)
	if bevel > 0:
		m = ob.modifiers.new("bevel", "BEVEL")
		m.width = bevel
		m.segments = 2
		m.limit_method = "NONE"
		apply_all(ob)
	return ob


# Cette méthode permet de donner le contour d'un octogone (rectangle aux coins coupés) lorsqu'on dessine une plaque.
def octagon(cx, cz, hw, hh, cut):
	return [
		(cx - hw + cut, cz - hh),
		(cx + hw - cut, cz - hh),
		(cx + hw, cz - hh + cut),
		(cx + hw, cz + hh - cut),
		(cx + hw - cut, cz + hh),
		(cx - hw + cut, cz + hh),
		(cx - hw, cz + hh - cut),
		(cx - hw, cz - hh + cut),
	]


# Cette méthode permet de soustraire un volume à un autre (booléen exact) lorsqu'on évide un cadre ou un liseré.
def cut(ob, tool):
	m = ob.modifiers.new("cut", "BOOLEAN")
	m.operation = "DIFFERENCE"
	m.solver = "EXACT"
	m.object = tool
	apply_all(ob)
	bpy.data.objects.remove(tool)


# Cette méthode permet de créer un liseré qui suit le contour d'une plaque (anneau entre deux contours) lorsqu'on borde
# le plastron ou le tablier.
def trim(name, outer, inner, y0, y1):
	ob = slab(name, outer, y0, y1)
	cut(ob, slab(name + "_hole", inner, y0 - 0.05, y1 + 0.05))
	return ob


# Cette méthode permet de créer une portion de cylindre vertical (angle en degrés autour de l'avant +Y, rayons r0 à
# r1, hauteur de z0 à z1) lorsqu'on modèle la visière et son cadre sur le casque.
def arc_shell(name, r0, r1, half_angle, z0, z1, steps=24):
	bm = bmesh.new()
	rings = []
	for r in (r0, r1):
		row = []
		for i in range(steps + 1):
			a = math.radians(-half_angle + 2 * half_angle * i / steps)
			row.append((math.sin(a) * r, math.cos(a) * r))
		rings.append(row)
	grid = {}
	for ri, row in enumerate(rings):
		for zi, z in enumerate((z0, z1)):
			for i, (x, y) in enumerate(row):
				grid[ri, zi, i] = bm.verts.new((x, y, z))
	for i in range(steps):
		for ri in range(2):
			bm.faces.new([grid[ri, 0, i], grid[ri, 0, i + 1], grid[ri, 1, i + 1], grid[ri, 1, i]])
		for zi in range(2):
			bm.faces.new([grid[0, zi, i], grid[0, zi, i + 1], grid[1, zi, i + 1], grid[1, zi, i]])
	for i in (0, steps):
		bm.faces.new([grid[0, 0, i], grid[1, 0, i], grid[1, 1, i], grid[0, 1, i]])
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return to_object(name, bm)


# Cette méthode permet de créer le casque (coque olive, cadre noir de la visière et oreillettes, visière fumée) dans
# l'espace de la tête.
def helmet():
	before = set(bpy.data.objects)
	bpy.ops.import_scene.fbx(filepath=os.path.join(ROOT, "assets", "outfits", "mercure", "MercureHead.fbx"))
	new = [o for o in bpy.data.objects if o not in before]
	shell = next(o for o in new if o.type == "MESH")
	for o in new:
		if o is not shell:
			bpy.data.objects.remove(o)
	shell.parent = None
	shell.name = "Helmet"
	bpy.context.view_layer.update()
	ws = [shell.matrix_world @ v.co for v in shell.data.vertices]
	lo = Vector([min(w[i] for w in ws) for i in range(3)])
	hi = Vector([max(w[i] for w in ws) for i in range(3)])
	center, size = (lo + hi) / 2, hi - lo
	target = Vector((1.98 * HELMET_SCALE[0], 1.98 * HELMET_SCALE[1], 1.99 * HELMET_SCALE[2]))
	mat = Matrix.Translation((0, 0, 0.06)) @ Matrix.Diagonal(
		(target.x / size.x, target.y / size.y, target.z / size.z, 1)
	) @ Matrix.Translation(-center)
	shell.data.transform(mat @ shell.matrix_world)
	shell.matrix_world = Matrix.Identity(4)
	shell.data.materials.clear()

	r = HELMET_R
	frame = arc_shell("HelmetFrame", r - 0.12, r + 0.1, 66, -0.62, 0.42)
	cut(frame, arc_shell("hole", r - 0.3, r + 0.3, 56, -0.5, 0.3))
	frame_bevel = frame.modifiers.new("bevel", "BEVEL")
	frame_bevel.width = 0.03
	frame_bevel.segments = 2
	apply_all(frame)
	for sx in (-1, 1):
		bpy.ops.mesh.primitive_cylinder_add(
			radius=0.36, depth=0.16, location=(sx * (r + 0.02), -0.05, -0.08), rotation=(0, math.radians(90), 0)
		)
		ear = bpy.context.object
		bev = ear.modifiers.new("bevel", "BEVEL")
		bev.width = 0.04
		bev.segments = 2
		apply_all(ear)
		with bpy.context.temp_override(active_object=frame, selected_editable_objects=[frame, ear]):
			bpy.ops.object.join()
	visor = arc_shell("Visor", r - 0.1, r + 0.05, 58, -0.52, 0.32)
	return [(shell, "Head", "olive", True), (frame, "Head", "plate", False), (visor, "Head", "visor", False)]


# Cette méthode permet de créer le col rembourré (anneau noir autour du haut du torse) dans l'espace de l'UpperTorso.
def collar():
	bpy.ops.mesh.primitive_torus_add(major_radius=1.1, minor_radius=0.33, major_segments=48, minor_segments=16)
	ob = bpy.context.object
	ob.name = "Collar"
	ob.scale = (1.12, 0.84, 1.0)
	ob.location = (0, 0, 1.2706 + 0.16)
	bpy.ops.object.transform_apply(location=True, scale=True)
	return [(ob, "UpperTorso", "black", False)]


# Cette méthode permet de créer une épaulière rembourrée et son liseré dans l'espace du bras (`out` : +1 bras droit,
# -1 bras gauche, vers l'extérieur).
def pad(side, out):
	half = LIMB / 2
	inner, outer = -half - 0.01, half + 0.24
	xs = sorted((out * inner, out * outer))
	body = rounded_box(side + "Pad", (xs[0], -half - 0.14, 0.02), (xs[1], half + 0.14, 0.928 + 0.3), 0.16)
	t_xs = sorted((out * (inner + 0.02), out * (outer + 0.035)))
	band = rounded_box(side + "PadTrim", (t_xs[0], -half - 0.175, 0.04), (t_xs[1], half + 0.175, 0.13), 0.03, 2)
	cut(band, rounded_box("hole", (t_xs[0] + 0.07, -half - 0.1, -0.1), (t_xs[1] - 0.07, half + 0.1, 0.3), 0, 1))
	return [(body, side + "UpperArm", "black", False), (band, side + "UpperArm", "sand", False)]


# Cette méthode permet de créer le plastron (plaque noire bordée de sable) dans l'espace de l'UpperTorso, et le tablier
# dans celui du LowerTorso.
def plates():
	front = LIMB / 2
	chest = octagon(0, -0.095, 1.17, 1.025, 0.3)
	plate = slab("ChestPlate", chest, front - 0.02, front + 0.15, 0.04)
	ring = trim(
		"ChestTrim", octagon(0, -0.095, 1.07, 0.925, 0.26), octagon(0, -0.095, 1.0, 0.855, 0.23), front + 0.13, front + 0.175
	)
	apron_out = [(-0.95, 0.3), (0.95, 0.3), (0.78, -0.7), (0.58, -0.8), (-0.58, -0.8), (-0.78, -0.7)]
	apron_in = [(-0.85, 0.22), (0.85, 0.22), (0.7, -0.64), (0.53, -0.72), (-0.53, -0.72), (-0.7, -0.64)]
	apron_hole = [(-0.78, 0.16), (0.78, 0.16), (0.64, -0.59), (0.49, -0.66), (-0.49, -0.66), (-0.64, -0.59)]
	flap = slab("Flap", apron_out, front - 0.02, front + 0.13, 0.035)
	flap_ring = trim("FlapTrim", apron_in, apron_hole, front + 0.11, front + 0.155)
	return [
		(plate, "UpperTorso", "plate", False),
		(ring, "UpperTorso", "sand", False),
		(flap, "LowerTorso", "plate", False),
		(flap_ring, "LowerTorso", "sand", False),
	]


# Cette méthode permet de lire le centre de la boîte englobante d'un objet (repère Blender de sa pièce) lorsqu'on
# calcule le décalage de la MeshPart : Roblox place une MeshPart au centre de la boîte de son mesh.
def bbox_center(ob):
	ws = [v.co for v in ob.data.vertices]
	return Vector([(min(w[i] for w in ws) + max(w[i] for w in ws)) / 2 for i in range(3)])


# Cette méthode permet de poser chaque volume sur le rig au repos lorsqu'on exporte ou rend l'aperçu.
def place(pieces):
	for ob, attach, _, _ in pieces:
		x, y = REST[attach]
		ob.matrix_world = Matrix.Translation((x, 0, y))


# Cette méthode permet de donner à un objet une matière unie (aperçu) lorsqu'on rend la planche.
def flat_material(ob, rgb):
	mat = bpy.data.materials.new(ob.name)
	mat.diffuse_color = (*[(c / 255) ** 2.2 for c in rgb], 1)
	ob.data.materials.clear()
	ob.data.materials.append(mat)


# Cette méthode permet d'importer le rig habillé des cartes cuites (couleur seule) lorsqu'on rend l'aperçu.
def import_rig():
	groups = {
		"UpperTorso": "Torso",
		"LowerTorso": "Torso",
	}
	for side in ("Left", "Right"):
		for p in ("UpperArm", "LowerArm", "Hand"):
			groups[side + p] = side + "Arm"
		for p in ("UpperLeg", "LowerLeg", "Foot"):
			groups[side + p] = side + "Leg"
	maps = os.path.join(HERE, "maps", "base", "R15")
	for part, group in groups.items():
		bpy.ops.wm.obj_import(filepath=os.path.join(RIG_DIR, part + ".obj"), forward_axis="Y", up_axis="Z")
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


# Cette méthode permet de rendre l'aperçu (face, trois quarts, dos) lorsqu'on compare la tenue à la planche de concept.
def render_preview(out_dir):
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
		scene.render.filepath = os.path.join(out_dir, f"demineur_{name}.png")
		bpy.ops.render.render(write_still=True)


def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	pieces = helmet() + collar() + pad("Left", -1) + pad("Right", 1) + plates()
	report = []
	for ob, attach, look, hides_head in pieces:
		c = bbox_center(ob)
		entry = {"name": ob.name, "attach": attach, "offset": [round(c.x, 4), round(c.z, 4), round(-c.y, 4)]}
		entry.update(LOOK[look])
		if hides_head:
			entry["hidesHead"] = True
		report.append(entry)
		flat_material(ob, LOOK[look]["color"])
	with open(os.path.join(HERE, "pieces.json"), "w", encoding="utf-8") as f:
		json.dump(report, f, indent=1, ensure_ascii=False)
	place(pieces)
	fbx = arg("--fbx")
	if fbx:
		sys.argv = [sys.argv[0], "--", fbx]
		exec(compile(open(os.path.join(ROOT, "tools", "export_mesh_fbx.py"), encoding="utf-8").read(), "export", "exec"))
	preview = arg("--preview")
	if preview:
		import_rig()
		render_preview(preview)


main()
