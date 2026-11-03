# build_turn_mesh.py
# Construit dans Blender le mesh d'un virage de l'Arène (demi-tour de la dune surfable) et sauvegarde le .blend,
# à exporter ensuite avec tools/export_mesh_fbx.py (cf. docs/maps.md, « Virages en mesh »).
# Usage : blender -b --factory-startup --python tools/map/build_turn_mesh.py -- <sortie.blend>
#
# Mêmes valeurs que tools/map/build_arena.luau (RING_W, BANK_H, BANK_SLOPE). Repère local (Roblox) : centre du
# virage à l'origine, arc de θ = 0 (x = +RING_W) à θ = π (x = -RING_W) côté +Z, sol à y = 0. Blender reçoit
# (x, -z, y) : Roblox = (x, z, -y) Blender, 1 unité = 1 stud.
# Deux objets : TurnBank (talus : pente, dos vertical, dessous, bouts) et TurnRidge (arête ambrée en haut de pente).
# Visuel seulement : la collision reste faite de WedgePart invisibles dans le générateur (une collision en mesh, même
# en tranches convexes, fait s'arrêter le surfeur : cf. docs/maps.md).
import math
import sys

import bmesh
import bpy

RING_W = 120.0
BANK_H = 55.0
BANK_SLOPE = 55.0
SEGMENTS = 256  # facettes du visuel
UV_STUDS = 16.0  # studs par unité d'UV (répétition de la texture de sable)
RIDGE = 0.6  # section carrée de l'arête ambrée
RIDGE_IN = 0.6  # retrait de l'arête vers l'intérieur, comme dans build_arena.luau
RIDGE_UP = 0.2

RUN = BANK_H / math.tan(math.radians(BANK_SLOPE))
TOE = RING_W - RUN


# Cette méthode permet de convertir un point du plan Roblox (rayon, hauteur, angle) en coordonnées Blender
# lorsqu'on pose un sommet du virage.
def at(radius, y, theta):
	return (radius * math.cos(theta), -radius * math.sin(theta), y)


# Cette méthode permet de balayer une section (liste de (rayon, hauteur) par paires d'arêtes) le long de l'arc
# lorsqu'on construit une face lisse : chaque bande a ses propres sommets, d'où des arêtes vives entre bandes.
def sweep(bm, uv_layer, a, b):
	ring = []
	for i in range(SEGMENTS + 1):
		theta = math.pi * i / SEGMENTS
		ring.append((bm.verts.new(at(a[0], a[1], theta)), bm.verts.new(at(b[0], b[1], theta))))
	width = math.hypot(b[0] - a[0], b[1] - a[1])
	radius = (a[0] + b[0]) / 2
	for i in range(SEGMENTS):
		va0, vb0 = ring[i]
		va1, vb1 = ring[i + 1]
		face = bm.faces.new((va0, va1, vb1, vb0))
		face.smooth = True
		u0 = radius * math.pi * i / SEGMENTS / UV_STUDS
		u1 = radius * math.pi * (i + 1) / SEGMENTS / UV_STUDS
		for loop, uv in zip(face.loops, ((u0, 0), (u1, 0), (u1, width / UV_STUDS), (u0, width / UV_STUDS))):
			loop[uv_layer].uv = uv
	return ring


# Cette méthode permet de fermer une section aux deux bouts de l'arc lorsqu'on veut un solide sans trou.
def caps(bm, section):
	for theta in (0.0, math.pi):
		verts = [bm.verts.new(at(r, y, theta)) for r, y in section]
		face = bm.faces.new(verts if theta > 0 else list(reversed(verts)))
		face.smooth = False


# Cette méthode permet de créer un objet maillé à partir d'une section fermée (sommets dans l'ordre) lorsqu'on
# construit le talus ou l'arête, puis d'orienter ses normales vers l'extérieur.
def build(name, section):
	bm = bmesh.new()
	uv_layer = bm.loops.layers.uv.new("UVMap")
	for i in range(len(section)):
		sweep(bm, uv_layer, section[i], section[(i + 1) % len(section)])
	caps(bm, section)
	# solide fermé : normales orientées vers l'extérieur ; arêtes vives entre la pente, le dos et les bouts
	# (lissage seulement le long de l'arc, où deux facettes voisines font 180°/SEGMENTS)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	for edge in bm.edges:
		if edge.is_manifold and edge.calc_face_angle() > math.radians(30):
			edge.smooth = False
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	obj = bpy.data.objects.new(name, mesh)
	bpy.context.scene.collection.objects.link(obj)
	return obj


if "--" not in sys.argv or len(sys.argv) <= sys.argv.index("--") + 1:
	sys.exit("usage : blender -b --factory-startup --python tools/map/build_turn_mesh.py -- <sortie.blend>")
out = sys.argv[sys.argv.index("--") + 1]

for obj in list(bpy.data.objects):
	bpy.data.objects.remove(obj)

# section du talus (rayon, hauteur) : pied de pente, haut du dos, bas du dos
build("TurnBank", [(TOE, 0.0), (RING_W, BANK_H), (RING_W, 0.0)])
# section de l'arête ambrée : carré au sommet, légèrement en retrait vers l'intérieur
rc, yc, h = RING_W - RIDGE_IN, BANK_H + RIDGE_UP, RIDGE / 2
build("TurnRidge", [(rc - h, yc - h), (rc - h, yc + h), (rc + h, yc + h), (rc + h, yc - h)])

bpy.ops.wm.save_as_mainfile(filepath=out)
print("virage sauvegardé :", out, "pied", round(TOE, 3), "segments", SEGMENTS)
