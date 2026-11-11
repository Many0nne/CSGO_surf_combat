"""Couteau de base (type USMC Mark 2 / Ka-Bar) : modèle Blender procédural, forme seule (sans UV ni textures).

Lancé dans Blender (`exec(open(chemin).read())`) ou en arrière-plan (`blender -b --factory-startup --python ...`).
Unités : pouces (1 unité = 1 pouce), à remettre à l'échelle de la M9 à l'export. Axes : pointe vers +Y, dos de lame vers +Z,
épaisseur de lame sur X (convention de docs/assets.md). Origine : face avant de la garde, au pied de la lame.
Références : trois photos fournies (USMC Mark 2 d'époque : lame clip point à gouttière, garde plate, manche en rondelles
de cuir, pommeau rond). Produit trois objets, un par matériau : KaBar_Blade, KaBar_Fittings (garde, collet, pommeau),
KaBar_Handle (cuir).
"""

import math

import bmesh
import bpy

SHARP_ANGLE_BLADE = math.radians(35)  # arêtes vives de la lame
SHARP_ANGLE_ROUND = math.radians(70)  # pièces arrondies (cuir, pommeau)


def smoothstep(a, b, x):
	"""Cette méthode permet de lisser une transition entre a et b lorsque x les traverse (0 avant a, 1 après b)."""
	t = max(0.0, min(1.0, (x - a) / (b - a)))
	return t * t * (3 - 2 * t)


def hermite(pts, y):
	"""Cette méthode permet de lire une courbe z(y) lissée (Hermite, tangentes de Catmull-Rom) lorsque pts est trié par y."""
	n = len(pts)
	if y <= pts[0][0]:
		return pts[0][1]
	if y >= pts[-1][0]:
		return pts[-1][1]
	i = 0
	while not (pts[i][0] <= y <= pts[i + 1][0]):
		i += 1

	def slope(j):
		a = max(j - 1, 0)
		b = min(j + 1, n - 1)
		return (pts[b][1] - pts[a][1]) / (pts[b][0] - pts[a][0])

	y0, z0 = pts[i]
	y1, z1 = pts[i + 1]
	h = y1 - y0
	t = (y - y0) / h
	m0 = slope(i) * h
	m1 = slope(i + 1) * h
	return (
		(2 * t**3 - 3 * t**2 + 1) * z0
		+ (t**3 - 2 * t**2 + t) * m0
		+ (-2 * t**3 + 3 * t**2) * z1
		+ (t**3 - t**2) * m1
	)


# Profil de la lame (y, z) : dos droit puis fausse arête concave jusqu'à la pointe, tranchant droit puis ventre.
SPINE = [(0, 0.62), (1.0, 0.62), (5.4, 0.62), (6.0, 0.58), (6.6, 0.48), (7.05, 0.30)]
EDGE = [(0, -0.65), (3.6, -0.65), (4.6, -0.61), (5.6, -0.45), (6.4, -0.17), (7.05, 0.30)]
THICK = [(0, 0.22), (5.4, 0.22), (6.4, 0.16), (7.05, 0.08)]  # épaisseur du dos
TIP_Y, TIP_Z = 7.05, 0.30  # pointe haute, près du dos (photos : environ 80 % de la hauteur)
FULLER_Y0, FULLER_Y1, FULLER_DEPTH = 0.95, 4.7, 0.05  # gouttière estampée, évitée sur le ricasso


def blade_ring(y):
	"""Cette méthode permet de calculer les 13 sommets de la section de lame à l'abscisse y (affûtage plat + gouttière)."""
	zs = hermite(SPINE, y)
	ze = hermite(EDGE, y)
	h = zs - ze
	th = hermite(THICK, y) / 2
	d = FULLER_DEPTH * smoothstep(FULLER_Y0, FULLER_Y0 + 0.3, y) * (1 - smoothstep(FULLER_Y1 - 0.3, FULLER_Y1, y))

	def zu(u):
		return ze + u * h

	eb = min(0.05, 0.25 * h)  # hauteur du petit biseau d'affûtage (reflet net sur le tranchant)
	cv = min(0.035, 0.1 * h)  # chanfrein du dos
	ch = min(0.035, th * 0.6)
	right = [
		(0.014, ze + eb),
		(th, zu(0.38)),
		(th, zu(0.46)),
		(th - d, zu(0.52)),
		(th - d, zu(0.80)),
		(th, zu(0.86)),
		(th, zs - cv),
		(th - ch, zs),
	]
	left = [(-x, z) for x, z in reversed(right)]
	return [(0.0, ze)] + right + left


def build_blade(bm):
	"""Cette méthode permet de construire la lame dans bm lorsque les tables de profil sont définies."""
	ys = [i * 0.15 for i in range(47)]  # 0 à 6,9
	rings = [[bm.verts.new((x, y, z)) for x, z in blade_ring(y)] for y in ys]
	n = len(rings[0])
	for a, b in zip(rings, rings[1:]):
		for k in range(n):
			bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
	bm.faces.new(rings[0])  # pied de la lame (caché dans la garde)
	tip = bm.verts.new((0.0, TIP_Y, TIP_Z))
	last = rings[-1]
	for k in range(n):
		bm.faces.new((last[k], last[(k + 1) % n], tip))


def revolve(bm, profile, segs=32, sx=1.0, sz=1.0, zoff=0.0):
	"""Cette méthode permet de tourner un profil (rayon, y) autour de Y, écrasé en ovale (sx, sz), lorsqu'il commence et finit à r=0."""
	rings = []
	for r, y in profile:
		if r < 1e-6:
			rings.append([bm.verts.new((0.0, y, zoff))])
		else:
			ring = []
			for k in range(segs):
				a = 2 * math.pi * k / segs
				ring.append(bm.verts.new((r * sx * math.cos(a), y, zoff + r * sz * math.sin(a))))
			rings.append(ring)
	for a, b in zip(rings, rings[1:]):
		if len(a) == 1:
			for k in range(segs):
				bm.faces.new((a[0], b[(k + 1) % segs], b[k]))
		elif len(b) == 1:
			for k in range(segs):
				bm.faces.new((a[k], a[(k + 1) % segs], b[0]))
		else:
			for k in range(segs):
				bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))


def build_fittings(bm):
	"""Cette méthode permet de construire garde plate, collet évasé et pommeau dans bm."""
	# Garde : plaque ovale mince, haute de 2,4 pouces dans le plan de la lame, bords adoucis.
	guard = [(0, -0.08), (0.92, -0.08), (1.0, -0.04), (1.0, 0.04), (0.92, 0.08), (0, 0.08)]
	revolve(bm, guard, segs=40, sx=0.28, sz=1.2, zoff=-0.03)
	# Collet : cône concave qui relie la garde au cuir.
	ferrule = [(0, -0.10), (0.26, -0.10), (0.265, -0.20), (0.30, -0.30), (0.35, -0.42), (0.41, -0.55), (0, -0.55)]
	revolve(bm, ferrule, segs=32, sx=0.85)
	# Pommeau : capuchon rond, plus large que le manche, fond plat chanfreiné.
	pommel = [(0, -4.38), (0.52, -4.38), (0.56, -4.43), (0.56, -4.62), (0.50, -4.74), (0.38, -4.78), (0, -4.78)]
	revolve(bm, pommel, segs=32, sx=0.9)
	# Boss de rivure : le bout de la soie, mis en forme à la rivure, dépasse du fond du pommeau.
	boss = [(0, -4.78), (0.30, -4.78), (0.30, -4.84), (0.25, -4.88), (0, -4.88)]
	revolve(bm, boss, segs=24, sx=0.9)


HANDLE_Y0, HANDLE_Y1, WASHERS = -0.55, -4.38, 6
# Décalage de rayon d'une rondelle selon sa fraction de hauteur : gorge, bombé, gorge.
WASHER_SHAPE = [(0.0, -0.06), (0.03, -0.06), (0.07, 0.0), (0.50, 0.012), (0.93, 0.0), (0.97, -0.06)]


def build_handle(bm):
	"""Cette méthode permet de construire le manche en rondelles de cuir (rayon qui grossit vers l'arrière) dans bm."""
	w = (HANDLE_Y0 - HANDLE_Y1) / WASHERS
	profile = [(0, HANDLE_Y0)]
	for i in range(WASHERS):
		y_top = HANDLE_Y0 - i * w
		for f, off in WASHER_SHAPE:
			y = y_top - f * w
			s = (HANDLE_Y0 - y) / (HANDLE_Y0 - HANDLE_Y1)
			profile.append((0.46 + 0.07 * s + off, y))
	profile += [(0.46 + 0.07 - 0.06, HANDLE_Y1), (0, HANDLE_Y1)]
	revolve(bm, profile, segs=32, sx=0.88)


BLADE_ZMIN, BLADE_ZH = -0.65, 1.27  # cadre (z) couvert par la texture de lame
FITTINGS_Y_TOP, FITTINGS_Y_BOT = 0.08, -4.88  # étendue en y des ferrures (v de leur texture)


def uv_blade(bm):
	"""Cette méthode permet de déplier la lame à plat par côté : moitié droite de la texture (u 0 à 0,5) pour x >= 0, gauche ensuite."""
	uv = bm.loops.layers.uv.verify()
	for f in bm.faces:
		right = sum(v.co.x for v in f.verts) >= 0
		for loop in f.loops:
			c = loop.vert.co
			u = c.y / TIP_Y * 0.5 + (0.0 if right else 0.5)
			loop[uv].uv = (u, (c.z - BLADE_ZMIN) / BLADE_ZH)


def uv_cylinder(bm, y_top, y_bot):
	"""Cette méthode permet de déplier une pièce de révolution autour de Y : u = angle, v = position entre y_top et y_bot (pôles et couture gérés)."""
	uv = bm.loops.layers.uv.verify()
	for f in bm.faces:
		us = {}
		for i, loop in enumerate(f.loops):
			c = loop.vert.co
			if abs(c.x) < 1e-6 and abs(c.z) < 0.04:  # pôle d'un capuchon : pas d'angle propre
				continue
			zc = 0.03 if abs(c.y) <= 0.0805 else 0.0  # la garde est décalée de -0,03 en z : recentrer son angle
			us[i] = (math.atan2(c.z + zc, c.x) / (2 * math.pi)) % 1.0
		vals = list(us.values())
		wraps = bool(vals) and max(vals) - min(vals) > 0.5
		mean = 0.0
		if vals:
			shifted = [u + 1.0 if wraps and u < 0.5 else u for u in vals]
			mean = sum(shifted) / len(shifted)
		for i, loop in enumerate(f.loops):
			u = us.get(i)
			if u is None:
				u = mean
			elif wraps and u < 0.5:
				u += 1.0
			loop[uv].uv = (u, (y_top - loop.vert.co.y) / (y_top - y_bot))


def uv_handle(bm):
	"""Cette méthode permet de déplier le manche en cylindre sur toute sa longueur."""
	uv_cylinder(bm, HANDLE_Y0, HANDLE_Y1)


def uv_fittings(bm):
	"""Cette méthode permet de déplier les ferrures en cylindre, sauf la garde et les fonds plats qui vont à plat dans la zone médiane de la texture."""
	uv_cylinder(bm, FITTINGS_Y_TOP, FITTINGS_Y_BOT)
	uv = bm.loops.layers.uv.verify()
	for f in bm.faces:
		in_guard = all(abs(v.co.y) <= 0.0805 for v in f.verts)
		if not (in_guard or abs(f.normal.y) > 0.95):
			continue
		for loop in f.loops:
			c = loop.vert.co
			loop[uv].uv = (0.5 + c.x / 1.2, 0.575 + (c.z + 0.03 if in_guard else c.z) / 2.6 * 0.5)


def finish(bm, angle):
	"""Cette méthode permet d'orienter les normales vers l'extérieur et de marquer vives les arêtes plus anguleuses que angle."""
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
	for f in bm.faces:
		f.smooth = True
	for e in bm.edges:
		if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > angle:
			e.smooth = False


def material(name, rgb, metallic, rough):
	"""Cette méthode permet de créer un matériau Principled (couleur de vue = couleur de base) lorsqu'il n'existe pas encore."""
	mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
	mat.diffuse_color = (*rgb, 1.0)
	mat.use_nodes = True
	bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
	bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
	bsdf.inputs["Metallic"].default_value = metallic
	bsdf.inputs["Roughness"].default_value = rough
	return mat


def make_object(name, builder, uv_builder, angle, mat, coll):
	"""Cette méthode permet de créer l'objet name (avec ses UV) dans coll en remplaçant l'ancien du même nom."""
	old = bpy.data.objects.get(name)
	if old:
		bpy.data.objects.remove(old, do_unlink=True)
	bm = bmesh.new()
	builder(bm)
	finish(bm, angle)
	uv_builder(bm)
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	mesh.materials.append(mat)
	ob = bpy.data.objects.new(name, mesh)
	coll.objects.link(ob)
	return ob


def main():
	"""Cette méthode permet de (re)générer les trois objets du couteau dans la collection KaBar."""
	coll = bpy.data.collections.get("KaBar") or bpy.data.collections.new("KaBar")
	if coll.name not in bpy.context.scene.collection.children:
		bpy.context.scene.collection.children.link(coll)
	steel = material("KaBar_BladeSteel", (0.30, 0.31, 0.31), 1.0, 0.40)  # métal : 1 ou 0, comme la M9
	fittings = material("KaBar_FittingsSteel", (0.26, 0.26, 0.26), 1.0, 0.38)
	leather = material("KaBar_Leather", (0.20, 0.09, 0.065), 0.0, 0.48)
	make_object("KaBar_Blade", build_blade, uv_blade, SHARP_ANGLE_BLADE, steel, coll)
	make_object("KaBar_Fittings", build_fittings, uv_fittings, SHARP_ANGLE_ROUND, fittings, coll)
	make_object("KaBar_Handle", build_handle, uv_handle, SHARP_ANGLE_ROUND, leather, coll)


main()
