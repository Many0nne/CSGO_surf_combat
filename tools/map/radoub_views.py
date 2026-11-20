"""Vues de la planche Radoub, écrites dans le repère du plan, converties dans le monde (cf. docs/maps.md, Radoub)."""
import json, sys

PIVOT, SCALE = (-1764, 0, 220), 1.4  # OFFSET + CENTER et SCALE de build_radoub.luau


# Cette méthode permet de passer un point du plan (x, y, z) dans le monde lorsque la map est posée par PLACE puis
# agrandie de SCALE ; `eye` garde la hauteur d'œil (5 studs au-dessus du sol du plan) en vraie grandeur.
def world(p, eye=False):
    raw = (-1528 - p[0], p[1] - 5 if eye else p[1], 440 - p[2])
    out = [PIVOT[i] + (raw[i] - PIVOT[i]) * SCALE for i in range(3)]
    if eye:
        out[1] += 5
    return out

VIEWS = [
    ("quai_nord", (40, 65, 135), (300, 42, 230)),
    ("fond", (80, 5, 199), (440, 14, 196)),
    ("poupe", (70, 6, 262), (100, 16, 228)),
    ("etrave", (452, 8, 200), (410, 26, 232)),
    ("portique", (256, 117, 135), (90, 60, 300)),
    ("facades", (330, 65, 322), (130, 82, 70)),
    ("magasins", (300, 65, 140), (330, 78, 400)),
    ("atelier", (110, 65, 40), (110, 70, 115)),
    ("atelier_long", (60, 66, 60), (190, 78, 60)),
    ("magasin_int", (300, 65, 380), (380, 68, 432)),
    ("pompes_int", (40, 65, 260), (20, 66, 190)),
    ("bateau_porte", (467, 65, 232), (60, 40, 230)),
    ("pont", (260, 49.5, 212), (120, 62, 240)),
]

only = sys.argv[2].split(",") if len(sys.argv) > 2 else None
out = []
for name, pos, target in VIEWS:
    if only and name not in only:
        continue
    out.append({"name": name, "position": world(pos, True), "target": world(target), "res": [1280, 720], "radius": 700})
json.dump(out, open(sys.argv[1], "w"), indent=1)
