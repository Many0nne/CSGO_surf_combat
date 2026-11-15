"""AWP (Accuracy International AW / AWM) : modèle Blender procédural, formes et dépliage UV (#403).

Lancé en arrière-plan : `blender -b --factory-startup --python assets/awp/build_awp.py -- [sortie.blend]`
(ou dans Blender par `exec(open(chemin).read())`, sans argument : la scène reste ouverte, rien n'est enregistré).

Repère, hérité de l'ancien modèle (`assets/sniper/Sniper.blend`) pour que le rig et les pistes publiées restent valables :
bouche du canon vers -X, haut +Z, côté droit du tireur +Y (levier de culasse) ; 1 unité = 1 stud du viewmodel 1P ;
origine = `Joint` du viewmodel. L'œilleton de la lunette (X 1,42, axe à Z 0,5) et la bouche du canon (X -5,45, Z 0),
les deux points mesurés par `assets/awp_viewmodel/build_anims.py`, sont à la même place que sur l'ancien modèle.
Pivots gardés : culasse (0,95 ; 0 ; 0) sur l'axe du canon, chargeur (0,29 ; 0 ; -0,45), détente (1,06 ; 0 ; -0,36).

Proportions relevées sur une photo de profil (L115A3, Wikimedia Commons, `references/awp_reel/`) : PX_S unités par pixel,
X = 1,42 + (px - 2940) * PX_S, Z = (355 - py) * PX_S. La lunette est montée 0,10 plus haut que sur la photo (axe à 0,5).

Pièces (noms et matériaux attendus par le rig et les skins) : Handle (boîtier, rail), Bolt, Magazine, Trigger (METAL_A),
Barrel (canon et frein de bouche), Fittings (embase et colliers, busc, plaque de couche, vis) (METAL_B), Stock et
Handguard (châssis polymère, matériau WOOD gardé pour les outils de skins), Scope (SCOPE), ScopeLens (verres).
Dépliage : îlots en unités monde (densité homogène), rangés par un empaquetage déterministe, un atlas par matériau.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector, geometry

PX_S = 0.002865  # unités par pixel de la photo de profil
SCOPE_LIFT = 0.10  # lunette plus haute que sur la photo : axe à Z 0,5 comme l'ancien modèle
SCOPE_Z = 0.504
TEX = 1024  # côté des cartes de chaque matériau (taille maximale d'une image Roblox)
MARGIN_PX = 6  # marge entre îlots, en pixels de la carte
STRIP_MAX = 1.5  # longueur maximale d'un îlot en bande (unités), au-delà il est coupé en tronçons
SHARP = math.radians(38)


def X(px):
	"""Cette méthode permet de convertir une abscisse de la photo de profil en X du modèle."""
	return 1.42 + (px - 2940) * PX_S


def Z(py):
	"""Cette méthode permet de convertir une ordonnée de la photo de profil en Z du modèle."""
	return (355 - py) * PX_S


def P(px, py, r=0.0):
	"""Cette méthode permet d'écrire un coin de contour (X, Z, rayon de congé) à partir de pixels de la photo."""
	return (X(px), Z(py), r * PX_S)


# ------------------------------------------------------------------------------------------------
# Contours 2D (plan X-Z)
# ------------------------------------------------------------------------------------------------


def fillet(corners, step_deg=12.0):
	"""Cette méthode permet de remplacer chaque coin (x, z, r) d'un contour fermé par un arc tangent de rayon r."""
	n = len(corners)
	out = []
	for i in range(n):
		p0 = Vector(corners[i - 1][:2])
		p1 = Vector(corners[i][:2])
		p2 = Vector(corners[(i + 1) % n][:2])
		r = corners[i][2]
		d0 = (p0 - p1).normalized()
		d2 = (p2 - p1).normalized()
		ang = math.acos(max(-1.0, min(1.0, d0.dot(d2))))
		if r <= 0 or ang < 1e-3 or ang > math.pi - 1e-3:
			out.append(p1)
			continue
		t = r / math.tan(ang / 2)
		t = min(t, 0.45 * (p0 - p1).length, 0.45 * (p2 - p1).length)
		r = t * math.tan(ang / 2)
		a = p1 + d0 * t
		b = p1 + d2 * t
		bis = (d0 + d2).normalized()
		c = p1 + bis * (r / math.sin(ang / 2))
		va, vb = a - c, b - c
		sweep = math.atan2(va.x * vb.y - va.y * vb.x, va.dot(vb))
		steps = max(2, int(abs(math.degrees(sweep)) / step_deg) + 1)
		a0 = math.atan2(va.y, va.x)
		for k in range(steps + 1):
			th = a0 + sweep * k / steps
			out.append(c + Vector((math.cos(th), math.sin(th))) * r)
	return out


def catmull_closed(points, per=8):
	"""Cette méthode permet de lisser un contour fermé passant par points (spline de Catmull-Rom)."""
	pts = [Vector(p) for p in points]
	n = len(pts)
	out = []
	for i in range(n):
		p0, p1, p2, p3 = pts[i - 1], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
		for k in range(per):
			t = k / per
			out.append(
				0.5
				* (
					2 * p1
					+ (-p0 + p2) * t
					+ (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
					+ (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t
				)
			)
	return out


def resample(loop, step):
	"""Cette méthode permet de recouper les côtés d'un contour fermé plus longs que step."""
	out = []
	n = len(loop)
	for i in range(n):
		a, b = loop[i], loop[(i + 1) % n]
		k = max(1, math.ceil((b - a).length / step))
		for j in range(k):
			out.append(a.lerp(b, j / k))
	return [p for i, p in enumerate(out) if (p - out[i - 1]).length > 1e-5]


def signed_area(loop):
	"""Cette méthode permet de calculer l'aire signée d'un contour (positive s'il tourne dans le sens direct)."""
	return 0.5 * sum(loop[i - 1].x * loop[i].y - loop[i].x * loop[i - 1].y for i in range(len(loop)))


def oriented(loop, ccw):
	"""Cette méthode permet de renvoyer le contour dans le sens demandé (direct si ccw)."""
	return loop if (signed_area(loop) > 0) == ccw else list(reversed(loop))


def vertex_normals(loop):
	"""Cette méthode permet de calculer la normale sortante (à droite du sens de parcours) de chaque sommet d'un contour."""
	n = len(loop)
	out = []
	for i in range(n):
		e0 = (loop[i] - loop[i - 1]).normalized()
		e1 = (loop[(i + 1) % n] - loop[i]).normalized()
		n0 = Vector((e0.y, -e0.x))
		n1 = Vector((e1.y, -e1.x))
		m = n0 + n1
		m = m.normalized() if m.length > 1e-6 else n0
		c = max(0.5, m.dot(n0))
		out.append(m / c)
	return out


def arclengths(loop):
	"""Cette méthode permet de renvoyer l'abscisse curviligne de chaque sommet d'un contour fermé, puis sa longueur totale."""
	s = [0.0]
	for i in range(1, len(loop)):
		s.append(s[-1] + (loop[i] - loop[i - 1]).length)
	return s, s[-1] + (loop[0] - loop[-1]).length


# ------------------------------------------------------------------------------------------------
# Constructeurs de géométrie : chacun renvoie la liste des faces créées (dépliées ensuite par îlots)
# ------------------------------------------------------------------------------------------------


class Part:
	"""Cette classe permet d'accumuler la géométrie d'une pièce (un bmesh) et ses îlots UV, un dépliage par sous-pièce."""

	def __init__(self, name):
		self.name = name
		self.bm = bmesh.new()
		self.uv = self.bm.loops.layers.uv.new("UVMap")

	def set_uv(self, loop, u, v):
		"""Cette méthode permet d'écrire les coordonnées UV (en unités monde) d'un coin de face."""
		loop[self.uv].uv = (u, v)


def slab(part, outer, holes=(), hw=0.17, r=0.03, yc=0.0, step=0.05, nb=4):
	"""Cette méthode permet d'extruder un contour X-Z (avec trous) sur une épaisseur 2*hw en Y, arêtes arrondies de rayon r.

	Faces latérales planes (dépliées à plat), pourtour en bandes (abscisse curviligne x tour de l'arrondi, coupées en tronçons).
	"""
	bm = part.bm
	loops = [oriented(resample(outer, step), True)] + [oriented(resample(h, step), False) for h in holes]
	prof = []  # (décalage le long de la normale, y) du haut vers le bas
	for k in range(nb + 1):
		phi = math.pi / 2 * (1 - k / nb)
		prof.append((-r + r * math.cos(phi), hw - r + r * math.sin(phi)))
	for k in range(1, nb + 1):
		phi = -math.pi / 2 * k / nb
		prof.append((-r + r * math.cos(phi), -(hw - r) + r * math.sin(phi)))
	tlen = [0.0]
	for a, b in zip(prof, prof[1:]):
		tlen.append(tlen[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
	rims = []
	faces = []
	for lp in loops:
		nrm = vertex_normals(lp)
		ring = [[bm.verts.new((p.x + nv.x * o, yc + y, p.y + nv.y * o)) for o, y in prof] for p, nv in zip(lp, nrm)]
		rims.append(ring)
		s, total = arclengths(lp)
		n = len(lp)
		for i in range(n):
			j = (i + 1) % n
			s0, s1 = s[i], (s[j] if j else total)
			seg = math.floor(0.5 * (s0 + s1) / STRIP_MAX)
			for k in range(len(prof) - 1):
				f = bm.faces.new((ring[i][k], ring[i][k + 1], ring[j][k + 1], ring[j][k]))
				for lo, (ss, tt) in zip(f.loops, ((s0, tlen[k]), (s0, tlen[k + 1]), (s1, tlen[k + 1]), (s1, tlen[k]))):
					part.set_uv(lo, ss - seg * STRIP_MAX, tt)
				faces.append(f)
	for side, kk in ((1, 0), (-1, len(prof) - 1)):
		polys = [[Vector((ring[i][kk].co.x, ring[i][kk].co.z, 0.0)) for i in range(len(ring))] for ring in rims]
		verts = [ring[i][kk] for ring in rims for i in range(len(ring))]
		for tri in geometry.tessellate_polygon(polys):
			vs = [verts[t] for t in tri]
			if len(set(vs)) < 3:
				continue
			try:
				f = bm.faces.new(vs)
			except ValueError:
				continue
			for lo in f.loops:
				part.set_uv(lo, lo.vert.co.x * side, lo.vert.co.z)
			faces.append(f)
	bmesh.ops.recalc_face_normals(bm, faces=faces)
	return faces


def frame(axis, seam):
	"""Cette méthode permet de construire un repère (A, U, V) autour de l'axe A, l'angle 0 opposé à la direction de couture."""
	a = Vector(axis).normalized()
	u = -(Vector(seam) - a * a.dot(Vector(seam))).normalized()
	return a, u, a.cross(u)


def lathe(part, origin, axis, profile, segs=32, seam=(0, 0, -1), closed=False, uv=True):
	"""Cette méthode permet de tourner un profil [(a, r)] autour de l'axe (origine, direction) ; r = 0 donne un pôle.

	Le profil part de l'arrière (a croissant vers l'avant de la pièce) en longeant l'extérieur : normales sortantes.
	Dépliage : u = abscisse le long du profil, v = angle x rayon (couture du côté seam), tronçons de STRIP_MAX.
	"""
	bm = part.bm
	o = Vector(origin)
	a_, u_, v_ = frame(axis, seam)
	prof = list(profile) + ([profile[0]] if closed else [])
	rings = []
	for a, r in prof:
		if r < 1e-6:
			rings.append([bm.verts.new(o + a_ * a)] * (segs + 1))
		else:
			ring = []
			for k in range(segs + 1):
				th = math.pi * (2 * k / segs - 1)
				if k == segs:
					ring.append(ring[0])
				else:
					ring.append(bm.verts.new(o + a_ * a + (u_ * math.cos(th) + v_ * math.sin(th)) * r))
			rings.append(ring)
	s = [0.0]
	for p, q in zip(prof, prof[1:]):
		s.append(s[-1] + math.hypot(q[0] - p[0], q[1] - p[1]))
	faces = []
	for i in range(len(prof) - 1):
		seg = math.floor(0.5 * (s[i] + s[i + 1]) / STRIP_MAX)
		for k in range(segs):
			quad = [rings[i][k], rings[i][k + 1], rings[i + 1][k + 1], rings[i + 1][k]]
			idx = [(i, k), (i, k + 1), (i + 1, k + 1), (i + 1, k)]
			keep = [(v, ij) for n, (v, ij) in enumerate(zip(quad, idx)) if v not in quad[:n]]
			if len(keep) < 3:
				continue
			f = bm.faces.new([v for v, _ in keep])
			if uv:
				for lo, (ii, kk) in zip(f.loops, [ij for _, ij in keep]):
					rr = prof[ii][1]
					rref = rr if rr > 1e-6 else max(prof[i][1], prof[i + 1][1])
					th = math.pi * (2 * kk / segs - 1)
					part.set_uv(lo, s[ii] - seg * STRIP_MAX, th * rref)
			faces.append(f)
	return faces


def prism_x(part, section, x0, x1, chamfer=0.0):
	"""Cette méthode permet d'extruder une section fermée (y, z) le long de X entre x0 et x1, bouchée aux deux bouts."""
	bm = part.bm
	sec = oriented([Vector(p) for p in section], True)
	n = len(sec)
	xs = [x0, x0 + chamfer, x1 - chamfer, x1] if chamfer > 0 else [x0, x1]
	cen = sum(sec, Vector((0, 0))) / n
	rings = []
	for j, x in enumerate(xs):
		k = 1.0 if (chamfer <= 0 or 0 < j < len(xs) - 1) else 0.0
		ring = []
		for p in sec:
			q = p if k else cen + (p - cen) * max(0.0, 1 - chamfer / max(1e-6, (p - cen).length))
			ring.append(bm.verts.new((x, q.x, q.y)))
		rings.append(ring)
	faces = []
	for a, b in zip(rings, rings[1:]):
		for i in range(n):
			faces.append(bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i])))
	faces.append(bm.faces.new(rings[0]))
	faces.append(bm.faces.new(list(reversed(rings[-1]))))
	bmesh.ops.recalc_face_normals(bm, faces=faces)
	return faces


def box(part, lo, hi):
	"""Cette méthode permet d'ajouter un pavé aligné sur les axes entre les coins lo et hi."""
	bm = part.bm
	(x0, y0, z0), (x1, y1, z1) = lo, hi
	v = [bm.verts.new(c) for c in ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))]
	idx = ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7))
	faces = [bm.faces.new([v[i] for i in f]) for f in idx]
	bmesh.ops.recalc_face_normals(bm, faces=faces)
	return faces


def sweep(part, path, rad_y, rad_n, segs=12, cap=True):
	"""Cette méthode permet de balayer une section elliptique (demi-axes rad_y selon Y et rad_n dans le plan X-Z) le long de path."""
	bm = part.bm
	pts = [Vector(p) for p in path]
	rings = []
	ref = Vector((0, 1, 0))
	for i, p in enumerate(pts):
		t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
		b = (ref - t * t.dot(ref)).normalized()
		nrm = t.cross(b)
		ring = []
		for k in range(segs):
			th = 2 * math.pi * k / segs
			ring.append(bm.verts.new(p + b * math.cos(th) * rad_y + nrm * math.sin(th) * rad_n))
		rings.append(ring)
	faces = []
	for a, c in zip(rings, rings[1:]):
		for k in range(segs):
			faces.append(bm.faces.new((a[k], a[(k + 1) % segs], c[(k + 1) % segs], c[k])))
	if cap:
		faces.append(bm.faces.new(rings[0]))
		faces.append(bm.faces.new(list(reversed(rings[-1]))))
	bmesh.ops.recalc_face_normals(bm, faces=faces)
	return faces


def disc(part, center, axis, radius, segs=40):
	"""Cette méthode permet d'ajouter un disque plat (verre de lunette) tourné vers +axis."""
	bm = part.bm
	a, u, v = frame(axis, (0, 0, -1) if abs(Vector(axis).z) < 0.9 else (1, 0, 0))
	c = Vector(center)
	ring = [bm.verts.new(c + (u * math.cos(2 * math.pi * k / segs) + v * math.sin(2 * math.pi * k / segs)) * radius) for k in range(segs)]
	f = bm.faces.new(ring)
	f.normal_update()
	if f.normal.dot(a) < 0:
		f.normal_flip()
	for lo in f.loops:
		d = lo.vert.co - c
		part.set_uv(lo, d.dot(u), d.dot(v))
	return [f]


def uv_cube(part, faces):
	"""Cette méthode permet de déplier des faces par projection sur le plan de leur axe dominant (unités monde)."""
	for f in faces:
		f.normal_update()
		n = f.normal
		ax = max(range(3), key=lambda i: abs(n[i]))
		sg = 1 if n[ax] >= 0 else -1
		for lo in f.loops:
			c = lo.vert.co
			if ax == 0:
				part.set_uv(lo, -sg * c.y, c.z)
			elif ax == 1:
				part.set_uv(lo, sg * c.x, c.z)
			else:
				part.set_uv(lo, c.x, sg * c.y)


def uv_axial(part, faces, origin, axis, seam=(0, 0, -1)):
	"""Cette méthode permet de déplier des faces autour d'un axe : cylindre (a, angle x rayon) ou plan pour les faces de bout."""
	o = Vector(origin)
	a_, u_, v_ = frame(axis, seam)
	for f in faces:
		f.normal_update()
		if abs(f.normal.dot(a_)) > 0.7:
			for lo in f.loops:
				d = lo.vert.co - o
				part.set_uv(lo, d.dot(u_) + 10.0 * (1 if f.normal.dot(a_) > 0 else -1), d.dot(v_))
			continue
		th, rr = [], []
		for lo in f.loops:
			d = lo.vert.co - o
			x, y = d.dot(u_), d.dot(v_)
			th.append(math.atan2(y, x))
			rr.append(math.hypot(x, y))
		if max(th) - min(th) > math.pi:
			th = [t + 2 * math.pi if t < 0 else t for t in th]
		rm = sum(rr) / len(rr)
		amid = sum((lo.vert.co - o).dot(a_) for lo in f.loops) / len(f.loops)
		seg = math.floor(amid / STRIP_MAX)
		for lo, t in zip(f.loops, th):
			part.set_uv(lo, (lo.vert.co - o).dot(a_) - seg * STRIP_MAX, t * rm)


# ------------------------------------------------------------------------------------------------
# Pièces
# ------------------------------------------------------------------------------------------------

HANDGUARD = [P(1703, 363, 22), P(2430, 363), P(2430, 537), P(2245, 489, 40), P(1703, 489, 18)]
STOCK = [
	P(2430, 363),
	P(2835, 363, 30),
	P(2885, 404, 30),
	P(3560, 400),
	P(3560, 698),
	P(3508, 698, 8),
	P(3505, 617, 10),
	P(3290, 617, 40),
	P(3180, 689, 30),
	P(3040, 721, 40),
	P(2950, 737, 25),
	P(2918, 735, 18),
	P(2903, 670),
	P(2879, 590, 10),
	P(2850, 601, 12),
	P(2735, 601, 20),
	P(2706, 572, 10),
	P(2705, 545, 6),
	P(2665, 545),
	P(2430, 537),
]
GUARD_HOLE = [P(2722, 505, 18), P(2852, 505, 14), P(2852, 586, 14), P(2740, 586, 24)]
THUMBHOLE = [(2968, 545), (2985, 503), (3015, 489), (3080, 488), (3116, 508), (3130, 560), (3112, 600), (3068, 616), (3020, 610), (2984, 588)]
SCREWS = [  # (px, py, rayon px) vis du châssis, visibles des deux côtés
	(1815, 440, 9), (2090, 440, 9), (2382, 465, 9), (2685, 457, 9), (2810, 440, 9),
	(2985, 447, 8), (3125, 447, 8), (3330, 440, 16), (3410, 440, 9), (3290, 580, 8), (3510, 580, 8), (2960, 665, 9),
]
STOCK_HW = 0.17
HANDGUARD_HW = 0.16


def build_stock():
	"""Cette méthode permet de construire la crosse à trou de pouce (châssis arrière, pontet compris)."""
	part = Part("Stock")
	hole = catmull_closed([(X(px), Z(py)) for px, py in THUMBHOLE], per=6)
	slab(part, fillet(STOCK), [fillet(GUARD_HOLE), hole], hw=STOCK_HW, r=0.035)
	return part


def build_handguard():
	"""Cette méthode permet de construire le fût (châssis avant), dans lequel le canon s'enfonce à moitié."""
	part = Part("Handguard")
	slab(part, fillet(HANDGUARD), hw=HANDGUARD_HW, r=0.035)
	return part


RECV_X0, RECV_X1 = X(2180), X(2780)
RECV_TOP, RAIL_TOP = Z(322), Z(302)


def receiver_section():
	"""Cette méthode permet de calculer la section (y, z) du boîtier : flancs droits, dessus plat, dessous arrondi."""
	hw, top, bot = 0.115, RECV_TOP, -0.135
	return fillet([(-hw, top, 0.03), (hw, top, 0.03), (hw, bot, 0.08), (-hw, bot, 0.08)], step_deg=15)


def build_handle():
	"""Cette méthode permet de construire le boîtier de culasse seul (la fenêtre d'éjection y est creusée ensuite)."""
	part = Part("Handle")
	prism_x(part, receiver_section(), RECV_X0, RECV_X1, chamfer=0.012)
	return part


def build_rail():
	"""Cette méthode permet de construire le rail du boîtier (semelle et dents), ajouté après le booléen."""
	part = Part("_Rail")
	rail_base = RECV_TOP + 0.035
	box(part, (RECV_X0 + 0.01, -0.072, RECV_TOP - 0.005), (RECV_X1 - 0.02, 0.072, rail_base))
	x = RECV_X0 + 0.03
	while x + 0.034 < RECV_X1 - 0.03:
		box(part, (x, -0.072, rail_base - 0.001), (x + 0.034, 0.072, RAIL_TOP))
		x += 0.067
	return part


EJECT_PORT = ((-0.06, 0.04, -0.045), (0.50, 0.30, 0.07))  # fenêtre d'éjection, côté droit (+Y)


def build_bolt():
	"""Cette méthode permet de construire la culasse : corps, manchon arrière, levier abaissé et boule (côté droit)."""
	part = Part("Bolt")
	prof = [(-0.45, 0.0), (-0.45, 0.055), (-0.44, 0.068), (0.955, 0.068), (0.962, 0.081), (1.16, 0.081), (1.2, 0.065), (1.205, 0.014), (1.25, 0.012), (1.255, 0.0)]
	faces = lathe(part, (0, 0, 0), (1, 0, 0), prof, segs=28, seam=(0, 0, -1))
	uv_axial(part, faces, (0, 0, 0), (1, 0, 0))
	stem = [(0.90, 0.03, 0.0), (0.915, 0.13, -0.02), (0.94, 0.22, -0.06), (0.965, 0.29, -0.10)]
	f = sweep(part, stem, 0.028, 0.028, segs=12)
	uv_axial(part, f, stem[0], Vector(stem[-1]) - Vector(stem[0]), seam=(0, 0, -1))
	ball = (0.98, 0.325, -0.125)
	rb = 0.072
	sph = [(-rb, 0.0)] + [(-rb * math.cos(math.pi * k / 12), rb * math.sin(math.pi * k / 12)) for k in range(1, 12)] + [(rb, 0.0)]
	f = lathe(part, ball, (0.3, 0.8, -0.5), sph, segs=20, seam=(-1, 0, 0))
	return part


def build_magazine():
	"""Cette méthode permet de construire le chargeur (boîte, fond en pente), vu sous le châssis."""
	part = Part("Magazine")
	outline = [(X(2422), -0.30, 0), (X(2665), -0.30, 0), (X(2665), Z(640), 0.012), (X(2422), Z(615), 0.012)]
	slab(part, fillet(outline), hw=0.095, r=0.012, step=0.04, nb=2)
	plate = [(X(2418), Z(600), 0), (X(2669), Z(625), 0), (X(2669), Z(645), 0.01), (X(2418), Z(620), 0.01)]
	slab(part, fillet(plate), hw=0.1, r=0.008, step=0.04, nb=2)
	return part


def build_trigger():
	"""Cette méthode permet de construire la queue de détente, courbe, dans le pontet."""
	part = Part("Trigger")
	path = [(X(2800), 0.0, Z(470)), (X(2802), 0.0, Z(505)), (X(2806), 0.0, Z(528)), (X(2800), 0.0, Z(553)), (X(2783), 0.0, Z(573))]
	f = sweep(part, path, 0.022, 0.011, segs=10)
	uv_cube(part, f)
	return part


def build_barrel():
	"""Cette méthode permet de construire le canon (légèrement conique) et le frein de bouche à évents latéraux."""
	part = Part("Barrel")
	a0 = -RECV_X0 - 0.1  # a = -X : le profil va de l'arrière vers la bouche
	crown = -X(740)
	prof = [(a0, 0.0), (a0, 0.094), (-X(1705), 0.094), (crown - 0.01, 0.080), (crown, 0.07), (crown, 0.0)]
	f = lathe(part, (0, 0, 0), (-1, 0, 0), prof, segs=28, seam=(0, 0, -1), uv=False)
	uv_axial(part, f, (0, 0, 0), (-1, 0, 0))
	return part


def build_brake():
	"""Cette méthode permet de construire le frein de bouche seul (ses évents y sont creusés ensuite)."""
	part = Part("_Brake")
	crown = -X(740)
	b0, b1 = crown - 0.06, 5.45
	brake = [(b0, 0.0), (b0, 0.09), (b0 + 0.02, 0.112), (b1 - 0.03, 0.112), (b1, 0.096), (b1, 0.045), (b1 - 0.12, 0.045), (b1 - 0.12, 0.0)]
	lathe(part, (0, 0, 0), (-1, 0, 0), brake, segs=28, seam=(0, 0, -1), uv=False)
	return part


def barrel_cutters():
	"""Cette méthode permet de renvoyer les pavés des évents du frein de bouche (traversants, de part et d'autre)."""
	out = []
	for x in (-5.06, -5.19, -5.32):
		out.append(((x - 0.035, -0.3, -0.055), (x + 0.035, 0.3, 0.055)))
	return out


def build_scope():
	"""Cette méthode permet de construire la lunette (tube, objectif, oculaire, tourelles et molette de parallaxe)."""
	part = Part("Scope")
	# Oculaire resserré avant son évasement final (retour utilisateur #403 : trop large juste avant l'extrémité, CS2).
	# Le profil part d'un fond fermé derrière le verre de l'oculaire et finit sur celui de l'objectif : sans ces fonds,
	# on voyait le décor à travers le tube (verre ScopeLens en Glass transparent, retour utilisateur #403).
	sp = [
		(2930, 0.0), (2930, 0.105),
		(2938, 0.105), (2945, 0.112), (2945, 0.125), (2938, 0.140), (2925, 0.146), (2900, 0.138), (2860, 0.128),
		(2810, 0.122), (2790, 0.122), (2786, 0.130), (2730, 0.130), (2726, 0.118), (2705, 0.118), (2700, 0.126),
		(2630, 0.126), (2625, 0.117), (2497, 0.117),
		(2495, 0.138), (2402, 0.138), (2400, 0.117), (2300, 0.117), (2280, 0.120), (2260, 0.129), (2240, 0.138),
		(2220, 0.146), (2200, 0.155), (2180, 0.163), (2160, 0.172), (2140, 0.180), (2120, 0.189), (2100, 0.200),
		(2080, 0.214), (1874, 0.214), (1868, 0.205), (1868, 0.193), (1876, 0.188),
		(1886, 0.188), (1886, 0.0),
	]
	prof = [(-X(px), r) for px, r in sp]  # a = -X : de l'oculaire vers l'objectif
	axis_o = (0.0, 0.0, SCOPE_Z)
	f = lathe(part, axis_o, (-1, 0, 0), prof, segs=40, seam=(0, 0, -1))
	tx = X(2450)
	# Tourelles basses, comme sur l'AWP de CS2 (la tourelle d'élévation de la photo, 0,42 au-dessus de l'axe, rendait
	# bizarrement au repos : retour utilisateur #403).
	elev = [(0.10, 0.0), (0.10, 0.06), (0.15, 0.06), (0.155, 0.08), (0.22, 0.08), (0.232, 0.068), (0.232, 0.0)]
	lathe(part, (tx, 0, SCOPE_Z), (0, 0, 1), elev, segs=28, seam=(1, 0, 0))
	wind = [(0.10, 0.0), (0.10, 0.06), (0.13, 0.06), (0.135, 0.072), (0.21, 0.072), (0.22, 0.062), (0.22, 0.0)]
	lathe(part, (tx, 0, SCOPE_Z), (0, 1, 0), wind, segs=28, seam=(1, 0, 0))
	para = [(0.10, 0.0), (0.10, 0.07), (0.13, 0.07), (0.135, 0.11), (0.18, 0.11), (0.19, 0.095), (0.19, 0.0)]
	lathe(part, (tx, 0, SCOPE_Z), (0, -1, 0), para, segs=32, seam=(1, 0, 0))
	return part


def build_lens():
	"""Cette méthode permet de construire les deux verres de la lunette (objectif et oculaire)."""
	part = Part("ScopeLens")
	disc(part, (X(1880), 0, SCOPE_Z), (-1, 0, 0), 0.19)
	disc(part, (X(2936), 0, SCOPE_Z), (1, 0, 0), 0.106)
	return part


def build_fittings():
	"""Cette méthode permet de construire embase et colliers de lunette, busc, plaque de couche et vis du châssis."""
	part = Part("Fittings")
	f = box(part, (X(2312), -0.085, RAIL_TOP), (X(2625), 0.085, RAIL_TOP + 0.085))
	uv_cube(part, f)
	for x0, x1 in ((X(2320), X(2370)), (X(2575), X(2625))):
		f = box(part, (x0, -0.065, RAIL_TOP + 0.08), (x1, 0.065, SCOPE_Z - 0.10))
		uv_cube(part, f)
		ring = [(-x1, 0.117), (-x1, 0.152), (-x0, 0.152), (-x0, 0.117)]
		lathe(part, (0, 0, SCOPE_Z), (-1, 0, 0), ring, segs=40, seam=(0, 0, -1), closed=True)
		for zz in (SCOPE_Z + 0.06, SCOPE_Z - 0.06):
			f = lathe(part, ((x0 + x1) / 2, -0.15, zz), (0, -1, 0), [(0.0, 0.0), (0.0, 0.016), (0.022, 0.016), (0.022, 0.0)], segs=12)
	cheek = [P(3198, 388), P(3198, 356, 10), P(3225, 343, 10), P(3532, 343, 10), P(3545, 352, 6), P(3545, 388)]
	slab(part, fillet(cheek), hw=0.15, r=0.02, step=0.05, nb=3)
	for px in (3262, 3470):
		f = lathe(part, (X(px), 0, Z(402)), (0, 0, 1), [(0.0, 0.0), (0.0, 0.032), (Z(388) - Z(402), 0.032), (Z(388) - Z(402), 0.0)], segs=14)
	butt = [P(3560, 375, 6), P(3722, 370, 12), P(3737, 722, 12), P(3560, 712, 6)]
	slab(part, fillet(butt), hw=0.185, r=0.035, step=0.05, nb=3)
	for px, py, rp in SCREWS:
		r = rp * PX_S
		hw = HANDGUARD_HW if px < 2430 else STOCK_HW
		prof = [(0.0, 0.0), (0.0, r), (0.008, r), (0.016, r * 0.8), (0.016, 0.0)]
		for sgn in (1, -1):
			lathe(part, (X(px), sgn * (hw - 0.006), Z(py)), (0, sgn, 0), prof, segs=14, seam=(1, 0, 0))
	return part


# ------------------------------------------------------------------------------------------------
# Objets, booléens, empaquetage UV
# ------------------------------------------------------------------------------------------------

MATERIALS = {  # nom : (couleur de planche, métal, rugosité)
	"WOOD_PBR": ((0.20, 0.23, 0.13), 0.0, 0.6),  # polymère vert olive (nom gardé pour les outils de skins)
	"METAL_A_PBR": ((0.06, 0.06, 0.065), 1.0, 0.45),
	"METAL_B_PBR": ((0.045, 0.045, 0.05), 1.0, 0.5),
	"SCOPE_PBR": ((0.035, 0.035, 0.04), 0.0, 0.45),
	"Lens": ((0.05, 0.08, 0.12), 0.0, 0.05),
}
PART_MATERIAL = {
	"Stock": "WOOD_PBR",
	"Handguard": "WOOD_PBR",
	"Handle": "METAL_A_PBR",
	"Bolt": "METAL_A_PBR",
	"Magazine": "METAL_A_PBR",
	"Trigger": "METAL_A_PBR",
	"Barrel": "METAL_B_PBR",
	"Fittings": "METAL_B_PBR",
	"Scope": "SCOPE_PBR",
	"ScopeLens": "Lens",
}


try:
	TEX_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "textures")
except NameError:  # exec() depuis la console de Blender
	TEX_DIR = globals().get("TEX_DIR", "")


def material(name):
	"""Cette méthode permet de créer (ou relire) un matériau Principled, ses cartes branchées si make_textures.py les a écrites.

	Sans cartes, un nœud d'image vide est quand même posé : bake_maps.py ne cuit que les matériaux texturés.
	"""
	rgb, metal, rough = MATERIALS[name]
	mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
	mat.diffuse_color = (*rgb, 1.0)
	mat.use_nodes = True
	nt = mat.node_tree
	bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
	bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
	bsdf.inputs["Metallic"].default_value = metal
	bsdf.inputs["Roughness"].default_value = rough
	if name == "Lens" or any(n.type == "TEX_IMAGE" for n in nt.nodes):
		return mat
	prefix = name.removesuffix("_PBR")
	found = False
	for i, (kind, socket) in enumerate((("Color", "Base Color"), ("Rough", "Roughness"), ("Metal", "Metallic"), ("Normal", None))):
		path = os.path.join(TEX_DIR, f"{prefix}_{kind}.png")
		tex = nt.nodes.new("ShaderNodeTexImage")
		tex.location = (-700, 300 - 280 * i)
		if not os.path.exists(path):
			if not found:
				tex.image = bpy.data.images.new(f"{prefix}_vide", 8, 8)
				found = True
			else:
				nt.nodes.remove(tex)
			continue
		tex.image = bpy.data.images.load(path, check_existing=True)
		if kind != "Color":
			tex.image.colorspace_settings.name = "Non-Color"
		if socket:
			nt.links.new(tex.outputs["Color"], bsdf.inputs[socket])
		else:
			nm = nt.nodes.new("ShaderNodeNormalMap")
			nm.location = (-300, -500)
			nt.links.new(tex.outputs["Color"], nm.inputs["Color"])
			nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
	return mat


def to_object(part, coll, mat=None):
	"""Cette méthode permet de créer l'objet de la pièce (remplace l'ancien du même nom) avec son matériau."""
	old = bpy.data.objects.get(part.name)
	if old:
		bpy.data.objects.remove(old, do_unlink=True)
	mesh = bpy.data.meshes.new(part.name)
	part.bm.to_mesh(mesh)
	part.bm.free()
	mesh.materials.append(material(mat or PART_MATERIAL[part.name]))
	ob = bpy.data.objects.new(part.name, mesh)
	coll.objects.link(ob)
	return ob


def merge(ob, part):
	"""Cette méthode permet d'ajouter la géométrie d'une pièce (déjà dépliée) au maillage d'un objet."""
	tmp = bpy.data.meshes.new("_tmp")
	part.bm.to_mesh(tmp)
	part.bm.free()
	bm = bmesh.new()
	bm.from_mesh(ob.data)
	bm.from_mesh(tmp)
	bm.to_mesh(ob.data)
	bm.free()
	bpy.data.meshes.remove(tmp)


def merge_object(ob, other):
	"""Cette méthode permet de verser le maillage d'un objet auxiliaire dans ob, puis de supprimer l'auxiliaire."""
	bm = bmesh.new()
	bm.from_mesh(ob.data)
	bm.from_mesh(other.data)
	bm.to_mesh(ob.data)
	bm.free()
	mesh = other.data
	bpy.data.objects.remove(other, do_unlink=True)
	bpy.data.meshes.remove(mesh)


def subtract(ob, boxes):
	"""Cette méthode permet de creuser des pavés dans un objet (booléen exact), puis de supprimer les pavés."""
	for i, (lo, hi) in enumerate(boxes):
		cut = Part(f"_cut{i}")
		box(cut, lo, hi)
		mesh = bpy.data.meshes.new(cut.name)
		cut.bm.to_mesh(mesh)
		cut.bm.free()
		cob = bpy.data.objects.new(cut.name, mesh)
		bpy.context.scene.collection.objects.link(cob)
		mod = ob.modifiers.new("cut", "BOOLEAN")
		mod.operation = "DIFFERENCE"
		mod.solver = "EXACT"
		mod.object = cob
		bpy.context.view_layer.objects.active = ob
		bpy.ops.object.modifier_apply(modifier=mod.name)
		bpy.data.objects.remove(cob, do_unlink=True)
		bpy.data.meshes.remove(mesh)


def reuv(ob, method):
	"""Cette méthode permet de redéplier toutes les faces d'un objet (après un booléen) avec la méthode donnée."""
	bm = bmesh.new()
	bm.from_mesh(ob.data)
	part = Part(ob.name)
	part.bm.free()
	part.bm = bm
	part.uv = bm.loops.layers.uv.verify()
	method(part, list(bm.faces))
	bm.to_mesh(ob.data)
	bm.free()


def islands(bm, uv):
	"""Cette méthode permet de regrouper les faces en îlots (faces voisines dont les UV coïncident sur l'arête commune)."""
	parent = {f.index: f.index for f in bm.faces}

	def find(i):
		while parent[i] != i:
			parent[i] = parent[parent[i]]
			i = parent[i]
		return i

	for e in bm.edges:
		lf = e.link_loops
		if len(lf) != 2:
			continue
		l1, l2 = lf
		# l1 va de v1 à v2, l2 en sens inverse : comparer les UV des mêmes sommets
		a1, b1 = l1[uv].uv, l1.link_loop_next[uv].uv
		a2, b2 = l2.link_loop_next[uv].uv, l2[uv].uv
		if (a1 - a2).length < 1e-5 and (b1 - b2).length < 1e-5:
			parent[find(l1.face.index)] = find(l2.face.index)
	groups = {}
	for f in bm.faces:
		groups.setdefault(find(f.index), []).append(f)
	return list(groups.values())


def shelf_pack(rects, side, margin):
	"""Cette méthode permet de ranger des rectangles (l, h) en étagères dans un carré de côté side ; None s'ils ne tiennent pas."""
	order = sorted(range(len(rects)), key=lambda i: -rects[i][1])
	pos = [None] * len(rects)
	x = y = shelf_h = 0.0
	for i in order:
		w, h = rects[i]
		if x + w + margin > side:
			x, y = 0.0, y + shelf_h
			shelf_h = 0.0
		if y + h + margin > side or w + margin > side:
			return None
		pos[i] = (x + margin, y + margin)
		x += w + margin
		shelf_h = max(shelf_h, h + margin)
	return pos


class Atlas:
	"""Cette classe permet de ranger les îlots (UV en unités monde) de plusieurs objets dans une même carte carrée."""

	def __init__(self, objs):
		self.meshes = []
		self.data = []  # (uv, faces, u0, v0, largeur, hauteur d'origine, tourné)
		for ob in objs:
			bm = bmesh.new()
			bm.from_mesh(ob.data)
			bm.faces.ensure_lookup_table()
			uv = bm.loops.layers.uv.verify()
			self.meshes.append((ob, bm))
			for grp in islands(bm, uv):
				us = [lo[uv].uv.copy() for f in grp for lo in f.loops]
				u0, v0 = min(p.x for p in us), min(p.y for p in us)
				w, h = max(p.x for p in us) - u0, max(p.y for p in us) - v0
				self.data.append((uv, grp, u0, v0, w, h, h > w))
		self.rects = [(h, w) if rot else (w, h) for _, _, _, _, w, h, rot in self.data]

	def best_side(self):
		"""Cette méthode permet de trouver le plus petit côté (unités monde) où tous les îlots tiennent."""
		area = sum(w * h for w, h in self.rects)
		lo_s, hi_s = math.sqrt(area), math.sqrt(area) * 3
		for _ in range(40):
			side = 0.5 * (lo_s + hi_s)
			if shelf_pack(self.rects, side, MARGIN_PX * side / TEX):
				hi_s = side
			else:
				lo_s = side
		return hi_s

	def apply(self, side):
		"""Cette méthode permet d'écrire les UV rangés dans un carré de côté side (densité TEX / side) et de libérer les bmesh."""
		pos = shelf_pack(self.rects, side, MARGIN_PX * side / TEX)
		if pos is None:
			raise RuntimeError(f"îlots trop grands pour un côté de {side:.3f}")
		for (uv, grp, u0, v0, w, _h, rot), (px, py) in zip(self.data, pos):
			for f in grp:
				for lo in f.loops:
					u, v = lo[uv].uv.x - u0, lo[uv].uv.y - v0
					if rot:
						u, v = v, w - u
					lo[uv].uv = ((px + u) / side, (py + v) / side)
		for ob, bm in self.meshes:
			bm.to_mesh(ob.data)
			bm.free()
		return TEX / side


def finish_normals(ob):
	"""Cette méthode permet d'adoucir l'objet en gardant vives les arêtes plus anguleuses que SHARP (sommets séparés)."""
	bm = bmesh.new()
	bm.from_mesh(ob.data)
	sharp =[e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > SHARP]
	bmesh.ops.split_edges(bm, edges=sharp)
	for f in bm.faces:
		f.smooth = True
	bm.to_mesh(ob.data)
	bm.free()


def main(out_path=None):
	"""Cette méthode permet de (re)générer toutes les pièces de l'AWP, leurs UV, et d'enregistrer le .blend si demandé."""
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	coll = bpy.data.collections.get("AWP") or bpy.data.collections.new("AWP")
	if coll.name not in bpy.context.scene.collection.children:
		bpy.context.scene.collection.children.link(coll)
	objs = {}
	for builder in (build_stock, build_handguard, build_handle, build_bolt, build_magazine, build_trigger, build_barrel, build_scope, build_lens, build_fittings):
		part = builder()
		objs[part.name] = to_object(part, coll)
	ob = objs["Handle"]
	subtract(ob, [EJECT_PORT])
	reuv(ob, uv_cube)
	rail = build_rail()
	uv_cube(rail, list(rail.bm.faces))
	merge(ob, rail)
	brake = build_brake()
	bob = to_object(brake, coll, "METAL_B_PBR")
	subtract(bob, barrel_cutters())
	reuv(bob, lambda part, faces: uv_axial(part, faces, (0, 0, 0), (-1, 0, 0)))
	merge_object(objs["Barrel"], bob)
	by_mat = {}
	for name, ob in objs.items():
		by_mat.setdefault(PART_MATERIAL[name], []).append(ob)
	atlases = {m: Atlas(o) for m, o in by_mat.items() if m != "Lens"}
	best = {m: TEX / a.best_side() for m, a in atlases.items()}
	common = min(best.values()) * 0.995  # même densité pour toutes les pièces : celle du matériau le plus chargé
	for m, a in atlases.items():
		print(f"DENSITE {m} {a.apply(TEX / common):.0f} px/unite (maximum seul : {best[m]:.0f})")
	for ob in objs.values():
		finish_normals(ob)  # après l'empaquetage : les arêtes séparées couperaient les îlots
	bpy.context.view_layer.update()
	for name, ob in objs.items():
		tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
		print(f"PIECE {name} triangles {tris} dims {tuple(round(v, 3) for v in ob.dimensions)}")
	if out_path:
		bpy.ops.wm.save_as_mainfile(filepath=out_path)
		bpy.ops.file.make_paths_relative()  # cartes en chemins relatifs : le .blend reste valable hors de ce checkout
		bpy.ops.wm.save_mainfile()


if __name__ == "__main__":
	argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
	main(argv[0] if argv else None)
