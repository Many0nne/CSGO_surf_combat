"""Relève le plan de Dizzy (ar_dizzy) depuis sa collision Source 2 et l'écrit en pièces Roblox (tools/map/dizzy_layout.json).

À lancer dans Blender (MCP `execute_blender_code`), sources hors dépôt (cf. docs/maps.md, « Dizzy ») :
    SRC = r".../worktrees/.tools/dizzy_out"      # sortie de Source2Viewer-CLI (world_physics + entités)
    OUT = r".../tools/map/dizzy_layout.json"
    exec(open(r".../tools/map/extract_dizzy.py", encoding="utf-8").read())

Méthode (sans échantillonnage, donc sans trou) : le monde est un maillage fermé, pas des blocs. Chaque face plane
(triangles coplanaires voisins) devient une dalle collée à la face et épaissie vers l'intérieur du solide (moitié de
l'épaisseur locale au plus, pour que les deux faces d'un mur fin ne se chevauchent pas), en rectangles quand le contour
s'y prête, sinon deux WedgePart par triangle. Un bloc convexe qui est une boîte devient une seule Part.
"""

import bisect
import json
import math
import os

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

H_SCALE = 10.0  # studs par mètre en plan (×2 de la v1, retour de l'utilisateur : trop petite)
V_SCALE = 7.0  # studs par mètre en hauteur (même rapport que la v1 : rampes à ~62°, marches franchissables)
Z0 = 198.0  # hauteur du toit (m) ramenée à Y = 0
Z_CUT = 190.0  # le fût de la tour sous cette hauteur est écarté (décor du générateur)
INCH = 0.0254
T_MAX = 2.0  # épaisseur maximale d'une dalle (studs)
T_MIN = 0.05
T_OPEN = 0.4  # dalle d'une surface ouverte (pas de face opposée)
EPS = 0.03  # retrait des dalles sous leur face : évite le scintillement entre la tranche d'une dalle et la face voisine
DECOR_FILL = 0.6  # un bloc de décor qui remplit au moins cette part de sa boîte orientée devient cette boîte
SMALL_DECOR = 8.0  # studs : un bloc de décor plus petit devient sa boîte orientée quel que soit son remplissage (tuyaux)
WORLD_MIN_VERTS = 500  # au-delà, le morceau est le maillage du monde (non convexe), jamais réduit à une boîte

SKIP = ("physics_sky", "physics_ladder", "ent_unnamed_706")
CLIP = ("physics_npcclip_playerclip", "ent_unnamed_655", "ent_unnamed_657")
# brushes d'entité (rendu désactivé) : origine source en pouces
ENTITIES = {"unnamed_655": (-1303, 832, 8202), "unnamed_657": (-745, -832, 8202)}
KILL_TOP_INCH = 7040 + 256  # haut du trigger_hurt (182,07 m)


def to_roblox(p):
    """Cette méthode permet de passer un point Blender (m, Z vers le haut) en studs Roblox (Y vers le haut)."""
    return Vector((p.x * H_SCALE, (p.z - Z0) * V_SCALE, -p.y * H_SCALE))


def source_to_blender(x, y, z):
    """Cette méthode permet de passer une origine d'entité source (pouces) dans le repère Blender du glb (vérifié par
    raycast : les spawns tombent tous 0,406 m au-dessus d'un sol)."""
    return Vector((y * INCH, -x * INCH, z * INCH))


def load_scene(src):
    """Cette méthode permet d'importer la collision du monde et des brushes d'entité dans une scène dédiée,
    en mètres, sommets confondus soudés."""
    sc = bpy.data.scenes.get("DizzyHulls") or bpy.data.scenes.new("DizzyHulls")
    bpy.context.window.scene = sc
    for o in list(sc.objects):
        bpy.data.objects.remove(o)
    bpy.ops.import_scene.gltf(filepath=os.path.join(src, "maps", "ar_dizzy", "world_physics_physics.glb"))
    ents = os.path.join(src, "ents", "maps", "ar_dizzy", "entities")
    for name, origin in ENTITIES.items():
        before = set(sc.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(ents, name + "_physics.glb"))
        for o in set(sc.objects) - before:
            o.name = "ent_" + name
            o.data.transform(o.matrix_world)
            o.matrix_world.identity()
            o.data.transform(__import__("mathutils").Matrix.Translation(source_to_blender(*origin)))
    for o in sc.objects:
        if o.type != "MESH":
            continue
        o.data.transform(o.matrix_world)
        o.matrix_world.identity()
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
        bm.to_mesh(o.data)
        bm.free()
    return sc


def clip_triangle(tri):
    """Cette méthode permet de couper un triangle au plan z = Z_CUT lorsque la face descend dans le fût de la tour
    (façade d'un seul tenant) : renvoie le polygone gardé au-dessus, éventuellement vide."""
    out = []
    for i in range(3):
        a, b = tri[i], tri[(i + 1) % 3]
        ina, inb = a.z >= Z_CUT, b.z >= Z_CUT
        if ina:
            out.append(a)
        if ina != inb:
            t = (Z_CUT - a.z) / (b.z - a.z)
            out.append(a.lerp(b, t))
    return out


def components(bm):
    """Cette méthode permet de séparer un maillage en morceaux connexes (blocs convexes, ou le maillage du monde)."""
    seen, out = set(), []
    for v in bm.verts:
        if v in seen:
            continue
        stack, grp = [v], []
        seen.add(v)
        while stack:
            x = stack.pop()
            grp.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y not in seen:
                    seen.add(y)
                    stack.append(y)
        out.append(grp)
    return out


def tri_list(faces):
    """Cette méthode permet de lister les triangles d'un morceau en studs Roblox, coupés sous le toit et sans les
    triangles dégénérés."""
    tris = []
    for f in faces:
        poly = clip_triangle([v.co.copy() for v in f.verts])
        for i in range(1, len(poly) - 1):
            t = [to_roblox(poly[0]), to_roblox(poly[i]), to_roblox(poly[i + 1])]
            n = (t[1] - t[0]).cross(t[2] - t[0])
            if n.length > 1e-5:
                tris.append((t, n.normalized()))
    return tris


def plane_groups(tris):
    """Cette méthode permet de regrouper les triangles d'un même plan, voisins ou non : le maillage a des jonctions
    en T (sommet au milieu de l'arête du voisin), les arêtes ne suffisent pas à relier une face."""
    groups = {}
    for i, (t, n) in enumerate(tris):
        k = (round(n.x, 3), round(n.y, 3), round(n.z, 3), round(n.dot(t[0]), 1))
        groups.setdefault(k, []).append(i)
    return list(groups.values())


def point_in_tri2(p, a, b, c):
    """Cette méthode permet de savoir si un point 2D est dans un triangle 2D (bords compris, à 1e-6 près)."""

    def s(p1, p2, p3):
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])

    d1, d2, d3 = s(p, a, b), s(p, b, c), s(p, c, a)
    neg = d1 < -1e-6 or d2 < -1e-6 or d3 < -1e-6
    pos = d1 > 1e-6 or d2 > 1e-6 or d3 > 1e-6
    return not (neg and pos)


def tri_area2(a, b, c):
    """Cette méthode permet de calculer l'aire d'un triangle 2D."""
    return abs((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])) / 2


def directions(tris, grp, n):
    """Cette méthode permet de proposer les axes de la grille d'un plan : tangente horizontale (murs, rampes), axes du
    monde (sols), arête la plus longue (sols en biais)."""
    cands = []
    if abs(n.y) < 0.999:
        cands.append(Vector((0, 1, 0)).cross(n).normalized())
    else:
        cands += [Vector((1, 0, 0)), Vector((0, 0, 1))]
    t = max((tris[j][0] for j in grp), key=lambda t: max((t[a] - t[(a + 1) % 3]).length for a in range(3)))
    e = max(((t[a], t[(a + 1) % 3]) for a in range(3)), key=lambda e: (e[1] - e[0]).length)
    cands.append((e[1] - e[0]).normalized())
    return cands


def aligned(t, u, v):
    """Cette méthode permet de savoir si un triangle est la moitié d'un rectangle de la grille (deux côtés suivant les
    axes u et v du plan)."""
    along = 0
    for a in range(3):
        d = (t[(a + 1) % 3] - t[a]).normalized()
        if abs(d.dot(u)) > 0.9999 or abs(d.dot(v)) > 0.9999:
            along += 1
    return along >= 2


def rectangles(tris, grp, n):
    """Cette méthode permet de couvrir un plan de rectangles, d'abord en entier, sinon sur ses seuls triangles alignés
    sur la grille. Renvoie (rectangles, triangles restants à poser en coins), ou None si rien ne se couvre."""
    dirs = directions(tris, grp, n)
    for u in dirs:
        rects = cover(tris, grp, n, u)
        if rects is not None:
            return rects, []
    for u in dirs:
        v = n.cross(u).normalized()
        sub = [j for j in grp if aligned(tris[j][0], u, v)]
        if not sub or len(sub) == len(grp):
            continue
        rects = cover(tris, sub, n, u)
        if rects is not None:
            return rects, [j for j in grp if j not in set(sub)]
    return None


def cover(tris, grp, n, u):
    """Cette méthode permet de couvrir des triangles coplanaires de rectangles d'axe u : grille des coordonnées de leurs
    sommets, cellules dont le centre est dans un triangle, fusion gloutonne. None si l'aire couverte diffère."""
    v = n.cross(u).normalized()
    origin = tris[grp[0]][0][0]
    proj = [[((x - origin).dot(u), (x - origin).dot(v)) for x in tris[j][0]] for j in grp]
    area = sum(tri_area2(*p) for p in proj)
    us = sorted({round(c[0], 3) for p in proj for c in p})
    vs = sorted({round(c[1], 3) for p in proj for c in p})
    nu, nv = len(us) - 1, len(vs) - 1
    if nu < 1 or nv < 1 or nu * nv > 400000:
        return None
    cov = [bytearray(nv) for _ in range(nu)]
    for p in proj:
        i0 = max(bisect.bisect_right(us, min(c[0] for c in p) + 1e-6) - 1, 0)
        i1 = bisect.bisect_left(us, max(c[0] for c in p) - 1e-6)
        k0 = max(bisect.bisect_right(vs, min(c[1] for c in p) + 1e-6) - 1, 0)
        k1 = bisect.bisect_left(vs, max(c[1] for c in p) - 1e-6)
        for i in range(i0, min(i1, nu)):
            cu = (us[i] + us[i + 1]) / 2
            for k in range(k0, min(k1, nv)):
                if not cov[i][k] and point_in_tri2((cu, (vs[k] + vs[k + 1]) / 2), *p):
                    cov[i][k] = 1
    covered = sum((us[i + 1] - us[i]) * (vs[k + 1] - vs[k]) for i in range(nu) for k in range(nv) if cov[i][k])
    if abs(covered - area) > 1e-3 * area + 1e-3:
        return None
    rects = []
    for i in range(nu):
        for k in range(nv):
            if not cov[i][k]:
                continue
            k2 = k
            while k2 + 1 < nv and cov[i][k2 + 1]:
                k2 += 1
            i2 = i
            while i2 + 1 < nu and all(cov[i2 + 1][m] for m in range(k, k2 + 1)):
                i2 += 1
            for a in range(i, i2 + 1):
                for m in range(k, k2 + 1):
                    cov[a][m] = 0
            rects.append((us[i], us[i2 + 1], vs[k], vs[k2 + 1]))
    return [(origin, u, v, r) for r in rects]


def unique_dirs(vectors, cap):
    """Cette méthode permet de garder au plus cap directions distinctes (au signe près) parmi des vecteurs."""
    out = []
    for vec in vectors:
        if vec.length < 1e-3:  # résidu de projection (float32) : direction sans valeur
            continue
        vec = vec.normalized()
        if not any(abs(vec.dot(m)) > 0.999 for m in out):
            out.append(vec)
            if len(out) >= cap:
                break
    return out


def oriented_box(tris):
    """Cette méthode permet de trouver la plus petite boîte orientée d'un bloc convexe (un axe normal à une de ses
    faces, un autre le long d'une arête) et la part de cette boîte qu'il remplit."""
    pts = list({(round(p.x, 3), round(p.y, 3), round(p.z, 3)): p for t, _ in tris for p in t}.values())
    volume = abs(sum(t[0].dot(t[1].cross(t[2])) for t, _ in tris)) / 6
    edges = [t[(k + 1) % 3] - t[k] for t, _ in tris for k in range(3)]
    best = None
    for a in unique_dirs([n for _, n in tris], 8):
        for b in unique_dirs([e - a * e.dot(a) for e in edges], 8):
            b = (b - a * b.dot(a)).normalized()
            c = a.cross(b).normalized()
            ext = [(min(p.dot(x) for p in pts), max(p.dot(x) for p in pts)) for x in (a, b, c)]
            vol = (ext[0][1] - ext[0][0]) * (ext[1][1] - ext[1][0]) * (ext[2][1] - ext[2][0])
            if best is None or vol < best[0]:
                best = (vol, (a, b, c), ext)
    if best is None or best[0] < 1e-9:
        return None, 0
    vol, axes, ext = best
    x, y, z = axes
    # axe Y de la pièce = le plus vertical des trois
    order = sorted(range(3), key=lambda i: -abs(axes[i].y))
    y = axes[order[0]] * (1 if axes[order[0]].y >= 0 else -1)
    x = axes[order[1]]
    z = x.cross(y)
    mid = [(lo + hi) / 2 for lo, hi in ext]
    center = axes[0] * mid[0] + axes[1] * mid[1] + axes[2] * mid[2]
    size = [ext[order[1]][1] - ext[order[1]][0], ext[order[0]][1] - ext[order[0]][0], ext[order[2]][1] - ext[order[2]][0]]
    return block_entry(center, x, y, z, size), volume / vol


def thickness(tree, pts, n):
    """Cette méthode permet de choisir l'épaisseur d'une dalle : la moitié de la distance à la face opposée du solide
    (rayons vers l'intérieur depuis les points donnés), bornée ; surface ouverte : épaisseur fixe."""
    best = None
    for c in pts:
        hit = tree.ray_cast(c - n * 1e-3, -n, 1e4)
        if hit[0] is not None:
            best = hit[3] if best is None else min(best, hit[3])
    if best is None:
        return T_OPEN
    return max(T_MIN, min(T_MAX, best / 2))


def block_entry(center, x, y, z, size):
    """Cette méthode permet d'écrire une pièce (position, axes X Y Z de sa CFrame, taille) arrondie au millième."""
    r = [round(c, 4) for c in (x.x, x.y, x.z, y.x, y.y, y.z, z.x, z.y, z.z)]
    return [round(center.x, 3), round(center.y, 3), round(center.z, 3)] + r + [round(s, 3) for s in size]


def wedges(t, n, th):
    """Cette méthode permet de découper un triangle quelconque en deux triangles rectangles, chacun posé en WedgePart
    (côté haut en +Z local, épaisseur en X), retiré de EPS sous la face."""
    a, b, c = t
    edges = [(a, b, c), (b, c, a), (c, a, b)]
    p, q, o = max(edges, key=lambda e: (e[1] - e[0]).length)
    pq = q - p
    f = p + pq * ((o - p).dot(pq) / pq.dot(pq))
    out = []
    for leg in (p, q):
        za, yb = f - leg, o - f
        if za.length < 0.05 or yb.length < 0.05:
            continue
        zaxis, yaxis = za.normalized(), yb.normalized()
        xaxis = yaxis.cross(zaxis)
        center = f + (leg - f) / 2 + (o - f) / 2 - n * (EPS + th / 2)
        out.append(block_entry(center, xaxis, yaxis, zaxis, (th, yb.length, za.length)))
    return out


def classify(n, clip):
    """Cette méthode permet de donner un rôle à une face selon sa pente (sol, mur, rampe de surf, pente marchable,
    plafond) pour l'habillage du générateur ; les murs d'air sont à part."""
    if clip:
        return "clip"
    ny = n.y
    if ny > 0.999:
        return "floor"
    if ny < -0.999:
        return "ceiling"
    if abs(ny) < 0.02:
        return "wall"
    slope = math.degrees(math.acos(min(1.0, abs(ny))))
    if ny > 0 and 46 <= slope <= 84:
        return "surf"
    return "slope" if ny > 0 else "ceiling"


def is_box(tris):
    """Cette méthode permet de reconnaître un bloc en boîte (6 faces planes deux à deux perpendiculaires) et d'en
    rendre la pièce équivalente, sinon None."""
    planes = []
    for t, n in tris:
        d = n.dot(t[0])
        for pl in planes:
            if pl[0].dot(n) > 0.9999 and abs(pl[1] - d) < 0.01:
                break
        else:
            planes.append((n, d))
    if len(planes) != 6:
        return None
    ns = [pl[0] for pl in planes]
    if not all(abs(a.dot(b)) < 0.001 or abs(a.dot(b)) > 0.999 for a in ns for b in ns):
        return None
    axes = []
    for nv in ns:
        if not any(abs(nv.dot(a)) > 0.999 for a in axes):
            axes.append(nv)
    x, y = axes[0], axes[1]
    if abs(x.y) > abs(y.y):
        x, y = y, x
    z = x.cross(y)
    pts = [p for t, _ in tris for p in t]
    lo = [min(p.dot(a) for p in pts) for a in (x, y, z)]
    hi = [max(p.dot(a) for p in pts) for a in (x, y, z)]
    center = x * ((lo[0] + hi[0]) / 2) + y * ((lo[1] + hi[1]) / 2) + z * ((lo[2] + hi[2]) / 2)
    return block_entry(center, x, y, z, [hi[i] - lo[i] for i in range(3)])


def extract(src, out_path):
    """Cette méthode permet de relever tout le plan (pièces, spawns, hauteur de mort) et de l'écrire en JSON."""
    sc = load_scene(src)
    parts, stats = [], {}
    shaft = None
    for o in sc.objects:
        if o.type != "MESH" or o.name.startswith(SKIP):
            continue
        clip = o.name.startswith(CLIP)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.normal_update()
        all_tris = tri_list(bm.faces)
        if not all_tris:
            bm.free()
            continue
        verts = [p for t, _ in all_tris for p in t]
        tree = BVHTree.FromPolygons(verts, [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(all_tris))])
        group = o.name.split(".")[0].replace("physics_group_", "").replace("physics_", "")
        for comp in components(bm):
            faces = {f for v in comp for f in v.link_faces}
            if len(comp) >= WORLD_MIN_VERTS and not clip:
                # emprise du fût de la tour (coupe à 120 m), habillé par le générateur sous le toit
                cut = [to_roblox(v.co) for f in faces for v in f.verts if min(w.co.z for w in f.verts) < 120 < max(w.co.z for w in f.verts)]
                if cut:
                    shaft = [round(min(p.x for p in cut), 2), round(max(p.x for p in cut), 2),
                             round(min(p.z for p in cut), 2), round(max(p.z for p in cut), 2)]
            tris = tri_list(faces)
            if not tris:
                continue
            box = is_box(tris) if len(comp) == 8 else None
            if box is None and not clip and len(comp) < WORLD_MIN_VERTS:
                # bloc de décor : une seule pièce s'il est petit (tuyau) ou remplit assez sa boîte orientée ; jamais un
                # mur d'air (sa forme exacte compte pour le jeu). Exiger la convexité doublait le nombre de pièces (des
                # blocs voisins soudés ne sont plus convexes) pour un surplus à peine réduit.
                obox, fill = oriented_box(tris)
                if obox is not None and (max(obox[-3:]) < SMALL_DECOR or fill >= DECOR_FILL):
                    box = obox
            if box:
                role = "clip" if clip else "block"
                parts.append([group, role, 0] + box)
                stats[role] = stats.get(role, 0) + 1
                continue
            for grp in plane_groups(tris):
                n = tris[grp[0]][1]
                role = classify(n, clip)
                covered = rectangles(tris, grp, n)
                rects, rest = covered if covered is not None else ([], grp)
                if rects:
                    for origin, u, v, (u0, u1, v0, v1) in rects:
                        if u1 - u0 < 1e-3 or v1 - v0 < 1e-3:
                            continue
                        c = origin + u * ((u0 + u1) / 2) + v * ((v0 + v1) / 2)
                        du, dv = u * ((u1 - u0) * 0.4), v * ((v1 - v0) * 0.4)
                        th = thickness(tree, [c, c + du + dv, c + du - dv, c - du + dv, c - du - dv], n)
                        c = c - n * (EPS + th / 2)
                        parts.append([group, role, 0] + block_entry(c, u, n, u.cross(n), (u1 - u0, th, v1 - v0)))
                        stats[role] = stats.get(role, 0) + 1
                if rest:
                    for j in rest:
                        t = tris[j][0]
                        th = thickness(tree, [(t[0] + t[1] + t[2]) / 3], n)
                        for w in wedges(t, n, th):
                            parts.append([group, role, 1] + w)
                            stats[role + "_wedge"] = stats.get(role + "_wedge", 0) + 1
        bm.free()
    spawns = []
    for team, pts in SPAWNS.items():
        for x, y, z, yaw in pts:
            p = to_roblox(source_to_blender(x, y, z))
            look = Vector((math.sin(math.radians(yaw)), 0, math.cos(math.radians(yaw))))
            spawns.append([team, round(p.x, 2), round(p.y, 2), round(p.z, 2), round(look.x, 4), round(look.z, 4)])
    data = {
        "source": "ar_dizzy (CS2, collision world_physics + func_brush), relevé par tools/map/extract_dizzy.py",
        "scale": {"h": H_SCALE, "v": V_SCALE, "z0": Z0},
        "killY": round((KILL_TOP_INCH * INCH - Z0) * V_SCALE, 2),
        "spawns": spawns,
        "shaft": shaft,
        "cutY": round((Z_CUT - Z0) * V_SCALE, 2),
        "fields": "groupe, rôle, 0 = Part / 1 = WedgePart, position xyz, axes X Y Z de la CFrame, taille xyz",
        "parts": parts,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, separators=(",", ":"))
    print("pièces", len(parts), stats)
    return data


# info_player_* de default_ents.vents (pouces, yaw en degrés)
SPAWNS = {
    "T": [(x, y, 8048, 135) for x, y in [(-416, -720), (-496, -720), (-400, -800), (-320, -800), (-496, -960),
                                        (-416, -960), (-400, -880), (-320, -880), (-576, -880), (-496, -880),
                                        (-576, -800), (-496, -800)]],
    "CT": [(x, y, 8048, 315) for x, y in [(-1648, 960), (-1568, 960), (-1552, 880), (-1648, 880), (-1728, 880),
                                         (-1728, 800), (-1648, 800), (-1648, 720), (-1568, 720), (-1552, 800),
                                         (-1472, 800), (-1472, 880)]],
}

if "SRC" in globals() and "OUT" in globals():
    extract(SRC, OUT)  # noqa: F821
elif "--" in __import__("sys").argv:
    extract(*__import__("sys").argv[__import__("sys").argv.index("--") + 1 :][:2])
