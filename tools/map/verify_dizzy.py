"""Vérifie que le plan relevé de Dizzy (tools/map/dizzy_layout.json) n'a ni trou ni surplus par rapport à la collision
d'origine, sans Studio : mêmes rayons tirés dans les deux géométries, premier impact comparé.

    blender -b --factory-startup --python tools/map/verify_dizzy.py -- <dossier dizzy_out> tools/map/dizzy_layout.json

Trou : un rayon passe (ou touche plus loin) dans la reconstruction là où l'original l'arrête. Surplus : l'inverse.
Rayons verticaux tous les STEP studs, horizontaux (axes X et Z) tous les STEP studs et tous les 4 studs de hauteur.
Code de sortie 1 s'il reste des écarts au-delà de la tolérance.
"""

import json
import os
import sys

from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else "tools/map"
exec(open(os.path.join(HERE, "extract_dizzy.py"), encoding="utf-8").read().split("# info_player_*")[0])

STEP = 1.0  # studs entre deux rayons
TOL = 0.6  # studs : retrait EPS des dalles, arrondis, épaisseur des surfaces ouvertes
MIN_CLUSTER = 3  # un écart isolé (rayon rasant une arête) n'est pas compté


def original_tree(src):
    """Cette méthode permet de construire l'arbre de rayons de la collision d'origine (mêmes objets, même coupe sous le
    toit que l'extracteur)."""
    sc = load_scene(src)  # noqa: F821
    verts, polys = [], []
    for o in sc.objects:
        if o.type != "MESH" or o.name.startswith(SKIP):  # noqa: F821
            continue
        bm = bmesh.new()  # noqa: F821
        bm.from_mesh(o.data)
        for t, _ in tri_list(bm.faces):  # noqa: F821
            polys.append((len(verts), len(verts) + 1, len(verts) + 2))
            verts += t
        bm.free()
    return BVHTree.FromPolygons(verts, polys)


def rebuilt_tree(layout):
    """Cette méthode permet de construire l'arbre de rayons des pièces relevées (boîtes et WedgePart, côté haut en +Z
    local)."""
    verts, polys, owner = [], [], []
    for index, e in enumerate(layout["parts"]):
        c = Vector(e[3:6])
        x, y, z = Vector(e[6:9]), Vector(e[9:12]), Vector(e[12:15])
        sx, sy, sz = e[15] / 2, e[16] / 2, e[17] / 2
        b = len(verts)
        if e[2] == 0:
            for i in (-1, 1):
                for j in (-1, 1):
                    for k in (-1, 1):
                        verts.append(c + x * (i * sx) + y * (j * sy) + z * (k * sz))
            # sommets : indice 4i'+2j'+k' (i', j', k' = 0 pour -1, 1 pour +1)
            quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        else:
            # section : (y-, z-), (y-, z+), (y+, z+) ; extrusion en X
            for i in (-1, 1):
                for j, k in ((-1, -1), (-1, 1), (1, 1)):
                    verts.append(c + x * (i * sx) + y * (j * sy) + z * (k * sz))
            quads = [(0, 1, 2, 2), (3, 5, 4, 4), (0, 3, 4, 1), (1, 4, 5, 2), (0, 2, 5, 3)]
        for q in quads:
            polys.append((b + q[0], b + q[1], b + q[2]))
            owner.append(index)
            if q[2] != q[3]:
                polys.append((b + q[0], b + q[2], b + q[3]))
                owner.append(index)
    return BVHTree.FromPolygons(verts, polys), owner


def first_hit(tree, origin, direction, far):
    """Cette méthode permet de mesurer la distance au premier impact d'un rayon (far s'il ne touche rien)."""
    hit = tree.ray_cast(origin, direction, far)
    return far if hit[0] is None else hit[3]


def compare(orig, new, owner, rays, far):
    """Cette méthode permet de tirer chaque rayon dans les deux géométries et de garder les écarts (trou, surplus),
    avec pour chaque surplus l'indice de la pièce relevée qui arrête le rayon."""
    holes, extras, culprits = [], [], []
    for o, d in rays:
        a = first_hit(orig, o, d, far)
        hit = new.ray_cast(o, d, far)
        b = far if hit[0] is None else hit[3]
        if b > a + TOL:
            holes.append(o + d * min(a, far))
        elif a > b + TOL:
            extras.append(o + d * min(b, far))
            culprits.append(owner[hit[2]])
    return holes, extras, culprits


def clusters(points, cell=4.0):
    """Cette méthode permet de regrouper les écarts proches (cellules de 4 studs) pour ne pas compter un rayon rasant
    isolé, et de rendre les groupes du plus gros au plus petit."""
    cells = {}
    for p in points:
        cells.setdefault((int(p.x // cell), int(p.y // cell), int(p.z // cell)), []).append(p)
    out = [(len(v), sum(v, Vector()) / len(v)) for v in cells.values() if len(v) >= MIN_CLUSTER]
    return sorted(out, key=lambda c: -c[0])


def verify(src, layout_path):
    """Cette méthode permet de lancer toute la vérification et de rendre le nombre d'écarts groupés."""
    layout = json.load(open(layout_path, encoding="utf-8"))
    orig = original_tree(src)
    new, owner = rebuilt_tree(layout)
    xs = [e[3] for e in layout["parts"]]
    zs = [e[5] for e in layout["parts"]]
    x0, x1, z0, z1 = min(xs) - 20, max(xs) + 20, min(zs) - 20, max(zs) + 20
    y0, y1 = layout["cutY"] + 2, 140.0
    rays = []
    x = x0
    while x < x1:
        z = z0
        while z < z1:
            rays.append((Vector((x, 700, z)), Vector((0, -1, 0))))
            z += STEP
        x += STEP
    y = y0
    while y < y1:
        z = z0
        while z < z1:
            rays.append((Vector((x0, y, z)), Vector((1, 0, 0))))
            rays.append((Vector((x1, y, z)), Vector((-1, 0, 0))))
            z += STEP
        x = x0
        while x < x1:
            rays.append((Vector((x, y, z0)), Vector((0, 0, 1))))
            rays.append((Vector((x, y, z1)), Vector((0, 0, -1))))
            x += STEP
        y += 4
    holes, extras, culprits = compare(orig, new, owner, rays, 2000.0)
    ch, ce = clusters(holes), clusters(extras)
    print(f"rayons {len(rays)}, trous {len(holes)} ({len(ch)} groupes), surplus {len(extras)} ({len(ce)} groupes)")
    for name, cs in (("trou", ch), ("surplus", ce)):
        for n, c in cs[:15]:
            print(f"  {name} x{n} vers ({c.x:.0f}, {c.y:.0f}, {c.z:.0f})")
    # pièces responsables des surplus : rôle, type, taille
    count = {}
    for i in culprits:
        count[i] = count.get(i, 0) + 1
    by_role = {}
    for i, n in count.items():
        e = layout["parts"][i]
        k = f"{e[0]}/{e[1]}/{'coin' if e[2] else 'bloc'}"
        by_role[k] = by_role.get(k, 0) + n
    print("  surplus par pièce :", sorted(by_role.items(), key=lambda kv: -kv[1])[:10])
    for i, n in sorted(count.items(), key=lambda kv: -kv[1])[:8]:
        e = layout["parts"][i]
        print(f"    x{n} {e[0]}/{e[1]} {'coin' if e[2] else 'bloc'} centre {[round(v) for v in e[3:6]]} taille {e[15:18]}")
    return len(ch) + len(ce)


if "--" in sys.argv:
    args = sys.argv[sys.argv.index("--") + 1 :]
    sys.exit(1 if verify(args[0], args[1]) else 0)
