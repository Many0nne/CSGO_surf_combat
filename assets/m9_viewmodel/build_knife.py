# build_knife.py
# Modélise la baïonnette M9 (lame, garde, manche, pommeau) pour le viewmodel Roblox.
# À lancer dans Blender : exec(open(path).read(), {"__name__": "__main__", "ASSET_DIR": dossier}).
#
# Repère de modélisation = repère local de la pièce Roblox « Handle » (unités = studs) :
#   +Z : axe du couteau (du pommeau vers la pointe), -X : dos de la lame, +X : tranchant, Y : épaisseur.
# L'origine est le centre de la poignée, là où la main droite du viewmodel la tient.

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

# --- Dimensions (studs ; ~0.118 stud par cm pour un viewmodel aux bras R15) ---------------------
GRIP_BACK, GRIP_FRONT = -0.74, 0.62  # poignée caoutchouc
POMMEL_BACK = -0.9
GUARD_BACK, GUARD_FRONT = 0.62, 0.74
BLADE_LEN = 2.12
BLADE_BASE = GUARD_FRONT - 0.04  # la lame s'enfonce un peu dans la garde
SPINE_V, EDGE_V, TIP_V = 0.185, -0.25, -0.02
BLADE_T = 0.07
EDGE_T = 0.004
TEETH = (0.1, 0.52, 0.085, 0.065)  # début, fin (fraction de lame), période, profondeur

KNIFE_PARTS = ("Blade", "Guard", "Handle", "Pommel")


# Cette méthode permet de convertir un point (axe u, hauteur v, épaisseur w) du couteau en
# coordonnées du repère local Roblox de la Handle.
def P(u, v, w):
	return Vector((-v, -w, u))


# Cette méthode permet d'appliquer une courbe smoothstep à s ∈ [0, 1].
def smooth(s):
	s = min(max(s, 0.0), 1.0)
	return s * s * (3 - 2 * s)


# Cette méthode permet de créer (ou remplacer) un objet maillé à partir d'un bmesh.
def mesh_object(name, bm, material):
	old = bpy.data.objects.get(name)
	if old:
		bpy.data.objects.remove(old, do_unlink=True)
	me = bpy.data.meshes.new(name)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bm.to_mesh(me)
	bm.free()
	ob = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(ob)
	me.materials.append(material)
	return ob


# Cette méthode permet de créer un matériau Principled de prévisualisation (le rendu final est fait
# par les matériaux Roblox appliqués aux MeshParts dans Studio).
def material(name, color, metallic, roughness):
	mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
	mat.use_nodes = True
	bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
	bsdf.inputs["Base Color"].default_value = (*color, 1)
	bsdf.inputs["Metallic"].default_value = metallic
	bsdf.inputs["Roughness"].default_value = roughness
	mat.diffuse_color = (*color, 1)
	return mat


# Cette méthode permet de relier deux anneaux de sommets de même taille par des quads.
def bridge(bm, ring_a, ring_b):
	n = len(ring_a)
	for i in range(n):
		j = (i + 1) % n
		bm.faces.new((ring_a[i], ring_a[j], ring_b[j], ring_b[i]))


# ------------------------------------------------------------------------------------------------
# Lame
# ------------------------------------------------------------------------------------------------


# Cette méthode permet de donner la hauteur du dos de lame (sans les dents) à la fraction s de la
# lame : dos droit puis « clip point » qui plonge vers la pointe.
def spine_v(s):
	if s <= 0.6:
		return SPINE_V
	k = (s - 0.6) / 0.4
	return SPINE_V - (SPINE_V - TIP_V) * (k**1.35)


# Cette méthode permet de donner la hauteur du tranchant à la fraction s : droit puis remontée
# progressive (ventre) jusqu'à la pointe ; le ricasso près de la garde est un peu plus haut.
def edge_v(s):
	v = EDGE_V
	if s > 0.52:
		k = (s - 0.52) / 0.48
		v = EDGE_V + (TIP_V - EDGE_V) * (k**2.1)
	return v + 0.025 * (1 - smooth(s / 0.06))


# Cette méthode permet de lister les échantillons (s, profondeur de dent) le long de la lame, avec
# des points exacts sur chaque dent de scie du dos pour garder des arêtes nettes.
def blade_samples():
	t0, t1, period, depth = TEETH
	pts = []
	s = 0.0
	while s < t0:
		pts.append((s, 0.0))
		s += 0.02
	u = t0 * BLADE_LEN
	while u + period <= t1 * BLADE_LEN:
		for off, d in ((0.0, 0.0), (0.3, 0.0), (0.82, depth), (0.9, depth)):
			pts.append(((u + off * period) / BLADE_LEN, d))
		u += period
	s = u / BLADE_LEN
	while s < 1.0:
		pts.append((s, 0.0))
		s += 0.015
	pts.append((1.0, 0.0))
	return pts


# Cette méthode permet de construire la lame par sections pentagonales (dos plat, émouture plate
# jusqu'au fil) balayées le long de l'axe, refermées sur la pointe.
def build_blade(mat):
	bm = bmesh.new()
	rings = []
	samples = blade_samples()
	for s, tooth in samples[:-1]:
		u = BLADE_BASE + s * BLADE_LEN
		vt = spine_v(s) - tooth
		ve = edge_v(s)
		# émouture : nulle sur le ricasso, puis aux ~55 % de la hauteur
		g = smooth((s - 0.03) / 0.05)
		vg = ve + (spine_v(s) - ve) * (1 - 0.45 * g)
		t = BLADE_T * (1 - 0.55 * smooth((s - 0.55) / 0.45))
		e = EDGE_T + (t / 2 - EDGE_T) * (1 - g)
		ring = [
			bm.verts.new(P(u, vt, t / 2)),
			bm.verts.new(P(u, vg, t / 2)),
			bm.verts.new(P(u, ve, e)),
			bm.verts.new(P(u, ve, -e)),
			bm.verts.new(P(u, vg, -t / 2)),
			bm.verts.new(P(u, vt, -t / 2)),
		]
		rings.append(ring)
	for a, b in zip(rings, rings[1:], strict=False):
		bridge(bm, a, b)
	tip = bm.verts.new(P(BLADE_BASE + BLADE_LEN, TIP_V, 0))
	last = rings[-1]
	for i in range(len(last)):
		bm.faces.new((last[i], last[(i + 1) % len(last)], tip))
	bm.faces.new(list(reversed(rings[0])))
	ob = mesh_object("Blade", bm, mat)

	# trou coupe-fil (ovale) et gouttières de part et d'autre, par booléens
	cutters = []
	hole = cutter_cylinder("cut_hole", P(BLADE_BASE + 0.17 * BLADE_LEN, -0.035, 0), (0.125, 0.06, 0.2), "w")
	cutters.append(hole)
	for side in (1, -1):
		c = cutter_cylinder(
			"cut_fuller_%d" % side,
			P(BLADE_BASE + 0.44 * BLADE_LEN, 0.075, side * BLADE_T / 2),
			(0.32 * BLADE_LEN, 0.022, 0.013),
			"u",
		)
		cutters.append(c)
	for c in cutters:
		mod = ob.modifiers.new(c.name, "BOOLEAN")
		mod.operation = "DIFFERENCE"
		mod.solver = "EXACT"
		mod.object = c
	apply_modifiers(ob)
	for c in cutters:
		bpy.data.objects.remove(c, do_unlink=True)
	return ob


# Cette méthode permet de créer un cylindre de découpe elliptique centré en `center`, de demi-axes
# (u, v, w) donnés, orienté selon l'axe du couteau indiqué ("u" ou "w").
def cutter_cylinder(name, center, half, axis):
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, segments=32, radius1=1, radius2=1, depth=2)
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	ob = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(ob)
	hu, hv, hw = half
	# cylindre Blender : axe local Z ; on le transforme dans le repère Roblox de la Handle
	if axis == "w":  # axe = épaisseur (Y Roblox), section ovale (u, v)
		# colonnes : X local → u (Z Roblox), Y local → v (-X Roblox), Z local → w (-Y Roblox)
		basis = Matrix(((0, -hv, 0), (0, 0, -hw), (hu, 0, 0))).to_4x4()
	else:  # axe = longueur (Z Roblox), section (v, w)
		basis = Matrix(((-hv, 0, 0), (0, -hw, 0), (0, 0, hu))).to_4x4()
	ob.matrix_world = Matrix.Translation(center) @ basis
	return ob


# Cette méthode permet d'appliquer tous les modificateurs d'un objet.
def apply_modifiers(ob):
	deps = bpy.context.evaluated_depsgraph_get()
	ev = ob.evaluated_get(deps)
	me = bpy.data.meshes.new_from_object(ev)
	old = ob.data
	ob.modifiers.clear()
	ob.data = me
	me.materials.clear()
	for m in old.materials:
		me.materials.append(m)
	bpy.data.meshes.remove(old)
	old_name = me.name
	me.name = ob.name
	return old_name


# ------------------------------------------------------------------------------------------------
# Manche, garde, pommeau
# ------------------------------------------------------------------------------------------------
GRIP_SEG = 48


# Cette méthode permet de donner le demi-profil (hauteur, épaisseur) de la poignée à la position u :
# léger renflement au centre, rétreint près de la garde, évasé vers le pommeau.
def grip_radii(u):
	s = (u - GRIP_BACK) / (GRIP_FRONT - GRIP_BACK)
	swell = 1 + 0.06 * math.sin(math.pi * s) - 0.08 * smooth((s - 0.85) / 0.15) + 0.05 * (1 - smooth(s / 0.12))
	return 0.2 * swell, 0.165 * swell


# Cette méthode permet de calculer le relief du quadrillage (pyramides) à une position (u, angle) de
# la poignée, estompé aux deux extrémités.
def checker(u, theta):
	a = u / 0.075 + theta / (2 * math.pi / 14)
	b = u / 0.075 - theta / (2 * math.pi / 14)
	fa = abs(a - math.floor(a) - 0.5) * 2
	fb = abs(b - math.floor(b) - 0.5) * 2
	h = 1 - max(fa, fb)
	s = (u - GRIP_BACK) / (GRIP_FRONT - GRIP_BACK)
	fade = smooth((s - 0.06) / 0.08) * (1 - smooth((s - 0.82) / 0.08))
	return 0.014 * h * fade


# Cette méthode permet de construire la poignée caoutchouc (section elliptique, quadrillée).
def build_grip(mat):
	bm = bmesh.new()
	rings = []
	n_u = 92
	for i in range(n_u + 1):
		u = GRIP_BACK + (GRIP_FRONT - GRIP_BACK) * i / n_u
		rv, rw = grip_radii(u)
		ring = []
		for j in range(GRIP_SEG):
			th = 2 * math.pi * j / GRIP_SEG
			k = 1 + checker(u, th) / rv
			ring.append(bm.verts.new(P(u, rv * k * math.cos(th), rw * k * math.sin(th))))
		rings.append(ring)
	for a, b in zip(rings, rings[1:], strict=False):
		bridge(bm, a, b)
	bm.faces.new(list(reversed(rings[0])))
	bm.faces.new(rings[-1])
	return mesh_object("Handle", bm, mat)


# Cette méthode permet de créer une boîte biseautée (garde, pommeau) entre deux bornes (u, v, w).
def bevel_box(name, lo, hi, bevel, mat, segments=3):
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1)
	(u0, v0, w0), (u1, v1, w1) = lo, hi
	for vtx in bm.verts:
		x, y, z = vtx.co
		vtx.co = P(u0 + (x + 0.5) * (u1 - u0), v0 + (y + 0.5) * (v1 - v0), w0 + (z + 0.5) * (w1 - w0))
	bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segments, affect="EDGES", profile=0.5)
	return bm


# Cette méthode permet de construire la garde : plaque (avec quillon côté tranchant) et anneau de
# canon côté dos, comme sur la baïonnette M9.
def build_guard(mat):
	bm = bevel_box("Guard", (GUARD_BACK, -0.4, -0.1), (GUARD_FRONT, 0.27, 0.1), 0.035, mat)
	# anneau de canon : tube (rayons ext/int) d'axe parallèle à la lame
	ring_c, r_out, r_in = 0.44, 0.17, 0.115
	segs = 32
	outer_b, outer_f, inner_b, inner_f = [], [], [], []
	for j in range(segs):
		th = 2 * math.pi * j / segs
		cv, sw = math.cos(th), math.sin(th)
		outer_b.append(bm.verts.new(P(GUARD_BACK, ring_c + r_out * cv, r_out * sw)))
		outer_f.append(bm.verts.new(P(GUARD_FRONT, ring_c + r_out * cv, r_out * sw)))
		inner_b.append(bm.verts.new(P(GUARD_BACK, ring_c + r_in * cv, r_in * sw)))
		inner_f.append(bm.verts.new(P(GUARD_FRONT, ring_c + r_in * cv, r_in * sw)))
	bridge(bm, outer_b, outer_f)
	bridge(bm, inner_f, inner_b)
	bridge(bm, outer_f, inner_f)
	bridge(bm, inner_b, outer_b)
	return mesh_object("Guard", bm, mat)


# Cette méthode permet de construire le pommeau métal (capuchon arrondi, fente de verrou et bouton
# de déverrouillage latéral).
def build_pommel(mat):
	bm = bmesh.new()
	rings = []
	n_u = 10
	for i in range(n_u + 1):
		s = i / n_u
		u = GRIP_BACK + 0.02 - (GRIP_BACK + 0.02 - POMMEL_BACK) * s
		rv, rw = grip_radii(GRIP_BACK)
		k = 1.06 * math.sqrt(max(0.0, 1 - (max(0.0, s - 0.45) / 0.55) ** 2 * 0.75))
		ring = []
		for j in range(GRIP_SEG):
			th = 2 * math.pi * j / GRIP_SEG
			ring.append(bm.verts.new(P(u, rv * k * math.cos(th), rw * k * math.sin(th))))
		rings.append(ring)
	for a, b in zip(rings, rings[1:], strict=False):
		bridge(bm, a, b)
	bm.faces.new(rings[0])
	bm.faces.new(list(reversed(rings[-1])))
	# bouton de déverrouillage (côté +w)
	btn = bmesh.new()
	bmesh.ops.create_cone(btn, cap_ends=True, segments=16, radius1=0.045, radius2=0.04, depth=0.06)
	me_tmp = bpy.data.meshes.new("tmp")
	btn.to_mesh(me_tmp)
	btn.free()
	rot = Matrix.Translation(P(GRIP_BACK - 0.07, 0.02, 0.2)) @ Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0))).to_4x4()
	me_tmp.transform(rot)
	bm.from_mesh(me_tmp)
	bpy.data.meshes.remove(me_tmp)
	return mesh_object("Pommel", bm, mat)


# Cette méthode permet de lisser l'ombrage d'un objet en gardant les arêtes vives (angle > 35°).
def shade(ob, angle=35):
	ob.data.shade_smooth()
	try:
		ob.data.set_sharp_from_angle(angle=math.radians(angle))
	except AttributeError:
		pass


# Cette méthode permet de (re)construire les quatre pièces du couteau et de les renvoyer par nom.
def build_knife():
	steel = material("M9_Steel", (0.62, 0.63, 0.65), 1.0, 0.32)
	dark = material("M9_DarkSteel", (0.12, 0.12, 0.13), 0.8, 0.45)
	rubber = material("M9_Rubber", (0.03, 0.03, 0.03), 0.0, 0.85)
	parts = {
		"Blade": build_blade(steel),
		"Guard": build_guard(dark),
		"Handle": build_grip(rubber),
		"Pommel": build_pommel(dark),
	}
	for name, ob in parts.items():
		shade(ob, 50 if name == "Handle" else 35)
	return parts


if __name__ == "__main__":
	build_knife()
