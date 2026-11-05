"""Mesure le scintillement possible (z-fighting) du plan relevé de Dizzy, sans Studio : faces de pièces de même sens,
dans le même plan à TOL près, qui se recouvrent et sont visibles depuis l'air (hors des solides d'origine).

    blender -b --factory-startup --python tools/map/zfight_dizzy.py -- <dossier dizzy_out> tools/map/dizzy_layout.json [TOL]

TOL (studs, défaut 0.005) : 0.005 compte les faces confondues (doublons), 0.1 aussi les tranches posées à EPS devant
une face voisine (arêtes saillantes). Affiche le total, le bilan par paire de rôles et les plus grandes paires, avec
leur position dans le monde (décalage de 2000 en X compris, comme dans Studio). Historique et lecture : docs/maps.md.
"""

import json
import os
import sys

from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else "tools/map"
exec(open(os.path.join(HERE, "verify_dizzy.py"), encoding="utf-8").read().split('if "--" in sys.argv')[0])

OFFSET_X = 2000  # décalage de la map dans Studio (build_dizzy.luau)


def part_faces(e):
    """Cette méthode permet de rendre les faces (normale, polygone) d'une pièce du plan, Part ou WedgePart (côté haut
    en +Z local)."""
    c = Vector(e[3:6])
    X, Y, Z = Vector(e[6:9]), Vector(e[9:12]), Vector(e[12:15])
    sx, sy, sz = e[15] / 2, e[16] / 2, e[17] / 2

    def P(a, b, d):
        return c + X * (a * sx) + Y * (b * sy) + Z * (d * sz)

    if e[2] != 1:
        out = []
        for ax, s, (u, su), (v, sv) in ((X, sx, (Y, sy), (Z, sz)), (Y, sy, (X, sx), (Z, sz)), (Z, sz, (X, sx), (Y, sy))):
            for sg in (1, -1):
                o = c + ax * (s * sg)
                out.append((ax * sg, [o + u * (su * a) + v * (sv * b) for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]))
        return out
    slope = X.cross(P(0, 1, 1) - P(0, -1, -1)).normalized()
    if slope.dot(Y) < 0:
        slope = -slope
    return [
        (-Y, [P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1), P(-1, -1, 1)]),
        (Z, [P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1)]),
        (X, [P(1, -1, -1), P(1, -1, 1), P(1, 1, 1)]),
        (-X, [P(-1, -1, -1), P(-1, -1, 1), P(-1, 1, 1)]),
        (slope, [P(-1, -1, -1), P(1, -1, -1), P(1, 1, 1), P(-1, 1, 1)]),
    ]


def area2(p):
    """Cette méthode permet de calculer l'aire signée d'un polygone 2D (positive dans le sens trigonométrique)."""
    return 0.5 * sum(p[i - 1][0] * p[i][1] - p[i][0] * p[i - 1][1] for i in range(len(p)))


def intersect(subj, clipper):
    """Cette méthode permet d'intersecter deux polygones convexes 2D (Sutherland-Hodgman) : rend l'aire commune et le
    polygone commun."""
    if area2(clipper) < 0:
        clipper = clipper[::-1]
    out = subj
    for i in range(len(clipper)):
        a, b = clipper[i - 1], clipper[i]
        inp, out = out, []
        if not inp:
            break

        def side(p):
            return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])

        for j in range(len(inp)):
            p, q = inp[j - 1], inp[j]
            sp, sq = side(p), side(q)
            if sq >= -1e-9:
                if sp < -1e-9:
                    out.append(cut(p, q, sp, sq))
                out.append(q)
            elif sp >= -1e-9:
                out.append(cut(p, q, sp, sq))
    return (abs(area2(out)), out) if len(out) >= 3 else (0.0, out)


def cut(p, q, sp, sq):
    """Cette méthode permet de couper un segment 2D sur le bord du polygone de découpe."""
    t = sp / (sp - sq)
    return (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)


def overlaps(parts, tol):
    """Cette méthode permet de lister les paires de faces de même sens, à tol près du même plan, qui se recouvrent de
    plus de 0,05 stud² : (aire, pièce a, pièce b, écart, centre de la zone commune, normale)."""
    buckets = {}
    for i, e in enumerate(parts):
        if e[1] == "clip":
            continue
        for n, poly in part_faces(e):
            n = n.normalized()
            key = tuple(round(x, 2) + 0.0 for x in n)  # + 0.0 : -0.0 et 0.0 dans le même seau
            buckets.setdefault(key, []).append((n.dot(poly[0]), i, poly, n))
    pairs, seen = [], set()
    for faces in buckets.values():
        faces.sort(key=lambda f: f[0])
        for a in range(len(faces)):
            da, ia, pa, n = faces[a]
            u = n.cross(Vector((0, 1, 0)) if abs(n.y) < 0.9 else Vector((1, 0, 0))).normalized()
            v = n.cross(u)
            A = [(p.dot(u), p.dot(v)) for p in pa]
            for b in range(a + 1, len(faces)):
                db, ib, pb, _ = faces[b]
                if db - da > tol:
                    break
                if ia == ib or (min(ia, ib), max(ia, ib)) in seen:
                    continue
                B = [(p.dot(u), p.dot(v)) for p in pb]
                if max(x for x, _ in A) < min(x for x, _ in B) or max(x for x, _ in B) < min(x for x, _ in A):
                    continue
                if max(y for _, y in A) < min(y for _, y in B) or max(y for _, y in B) < min(y for _, y in A):
                    continue
                ar, poly = intersect(A, B)
                if ar > 0.05:
                    seen.add((min(ia, ib), max(ia, ib)))
                    cu = sum(x for x, _ in poly) / len(poly)
                    cv = sum(y for _, y in poly) / len(poly)
                    pairs.append((ar, ia, ib, db - da, u * cu + v * cv + n * da, n))
    return pairs


def visible(orig, center, n):
    """Cette méthode permet de savoir si une zone commune est vue depuis l'air : un rayon tiré devant elle le long de
    sa normale sort à l'air libre ou touche l'endroit d'une face d'origine (pas son envers)."""
    hit = orig.ray_cast(center + n * 0.2, n, 1e4)
    return hit[0] is None or hit[1].dot(n) < 0


def report(src, layout_path, tol):
    """Cette méthode permet de lancer toute la mesure et d'afficher le bilan."""
    parts = json.load(open(layout_path, encoding="utf-8"))["parts"]
    orig = original_tree(src)  # noqa: F821 (verify_dizzy.py)
    pairs = [p for p in overlaps(parts, tol) if visible(orig, p[4], p[5])]
    print(f"faces superposées visibles (écart <= {tol}) : {len(pairs)} paires, {sum(p[0] for p in pairs):.0f} studs²")

    def label(e):
        return e[1] + ("/coin" if e[2] else "")

    kinds = {}
    for ar, ia, ib, *_ in pairs:
        k = " + ".join(sorted([label(parts[ia]), label(parts[ib])]))
        n, a = kinds.get(k, (0, 0.0))
        kinds[k] = (n + 1, a + ar)
    for k, (n, a) in sorted(kinds.items(), key=lambda kv: -kv[1][1])[:12]:
        print(f"  {k:28s} {n:6d} paires {a:9.0f} studs²")
    for ar, ia, ib, dd, c, n in sorted(pairs, key=lambda p: -p[0])[:15]:
        ea, eb = parts[ia], parts[ib]
        pos = [round(c.x) + OFFSET_X, round(c.y), round(c.z)]
        print(f"  {ar:6.1f} studs² écart {dd:.3f} en {pos} n={[round(x, 2) for x in n]} : "
              f"{ea[0]}/{label(ea)} {ea[15:18]}  /  {eb[0]}/{label(eb)} {eb[15:18]}")


if "--" in sys.argv:
    args = sys.argv[sys.argv.index("--") + 1 :]
    report(args[0], args[1], float(args[2]) if len(args) > 2 else 0.005)
