# Planche du shop (#347, cf. docs/ui.md, « Shop : salle de présentation ») : ajoute aux pièces de Dizzy les props de
# trois mises en scène (A rack du stockage, B salle de présentation dédiée, retenue, C caisse à côté du personnage de
# l'accueil), au format de tools/map/render_dizzy.py, et écrit <dossier>/{A,B,C}_parts.json et _views.json.
# Coordonnées et tailles en studs : B sert de cote pour construire la salle dans Roblox. Depuis la racine du worktree :
#   lune run tools/map/dump_parts.luau -- <dossier>/storage.json 1925 72 -345 120
#   lune run tools/map/dump_parts.luau -- <dossier>/menu.json 1760 104 -375 120
#   python -I tools/shop/board.py <dossier>
#   blender -b --factory-startup --python tools/map/render_dizzy.py -- <dossier>/B_parts.json <dossier>/B_views.json <sortie>
#   (rendu éclairé validé : DIZZY_EEVEE=1 DIZZY_AMBIENT=0.12 DIZZY_SPOT_GAIN=3, ~6 s par vue)
#   python -I tools/shop/sheet.py <sortie> [B_salle.png]   (esquisse d'interface ; sans 2e argument : planche A/B/C)
import json, math, os, sys

D = sys.argv[1]
UP = (0.0, 1.0, 0.0)


# Cette méthode permet d'additionner, soustraire et mettre à l'échelle des vecteurs 3D (tuples).
def add(*vs):
    return tuple(sum(c) for c in zip(*vs))


def mul(v, k):
    return tuple(c * k for c in v)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def norm(v):
    l = math.sqrt(sum(c * c for c in v))
    return tuple(c / l for c in v)


# Cette méthode permet de tourner un vecteur autour d'un axe unitaire (Rodrigues) lorsqu'on oriente un prop.
def rot(v, axis, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    d = sum(x * y for x, y in zip(axis, v))
    cr = cross(axis, v)
    return tuple(v[i] * c + cr[i] * s + axis[i] * d * (1 - c) for i in range(3))


class Frame:
    # Repère local : origine, axes droite (x), haut (y), avant (z, vers la caméra).
    def __init__(self, o, f, r=None, u=UP):
        self.o, self.f, self.u = o, norm(f), u
        self.r = r or norm(cross(u, self.f))

    # Cette méthode permet de convertir un point local en point du monde.
    def p(self, x, y, z):
        return add(self.o, mul(self.r, x), mul(self.u, y), mul(self.f, z))

    # Cette méthode permet de créer un sous-repère décalé et tourné (lacet, puis roulis autour de l'avant).
    def sub(self, x, y, z, yaw=0, roll=0, pitch=0):
        r, u, f = self.r, self.u, self.f
        if yaw:
            r, f = rot(r, u, yaw), rot(f, u, yaw)
        if roll:
            r, u = rot(r, f, roll), rot(u, f, roll)
        if pitch:
            u, f = rot(u, r, pitch), rot(f, r, pitch)
        return Frame(self.p(x, y, z), f, r, u)


PARTS = []


# Cette méthode permet d'ajouter une pièce (centre local, taille) dans un repère, au format de dump_parts.luau.
def box(fr, x, y, z, sx, sy, sz, col, mat="SmoothPlastic", shape="Block", transp=0.0, axis="x"):
    r, u, f = fr.r, fr.u, fr.f
    if shape == "Cylinder" and axis != "x":  # l'axe des cylindres Roblox est X : on le couche sur l'axe voulu
        if axis == "y":
            r, u = u, mul(r, -1)
            sx, sy = sy, sx
        else:  # z
            r, f = f, mul(r, -1)
            sx, sz = sz, sx
    pos = fr.p(x, y, z)
    PARTS.append([shape, *pos, *r, *u, *f, sx, sy, sz, *col, mat, transp])


BONE = (243, 233, 220)
AMBER = (242, 169, 0)
RED = (226, 58, 40)
GRAPHITE = (44, 48, 54)
STEEL = (120, 126, 132)
SKINS = {  # teinte principale, accent (relevées dans les textures METAL_A des AWP)
    "couchant": ((69, 14, 70), (190, 90, 60)),
    "impact": ((25, 26, 28), (138, 26, 18)),
    "releve": ((40, 40, 42), (153, 120, 65)),
    "recuit": ((23, 34, 76), (110, 84, 101)),
    "strate": ((95, 73, 49), (168, 136, 90)),
    "sillage": ((16, 16, 18), (182, 178, 175)),
}
RARITY = {"commun": (150, 160, 172), "rare": (70, 120, 230), "exceptionnel": (170, 70, 220)}


# Cette méthode permet de construire une caisse d'armes (origine : centre du dessous, face avant vers +z) aux couleurs
# d'une collection : coque graphite, coins et fermoirs os, bande de la collection sur le couvercle.
def crate(fr, stripe, W=4.0, H=2.0, Dp=2.4):
    box(fr, 0, H / 2, 0, W - 0.16, H - 0.16, Dp - 0.16, GRAPHITE, "Metal")
    seam = H * 0.62
    box(fr, 0, seam, 0, W - 0.1, 0.07, Dp - 0.1, (14, 15, 17))
    # couvercle légèrement bombé
    box(fr, 0, H - 0.02, 0, W - 0.5, 0.08, Dp - 0.5, (54, 58, 64), "Metal")
    for sx in (-1, 1):
        for sy in (0, 1):
            for sz in (-1, 1):
                box(fr, sx * (W / 2 - 0.22), 0.22 + sy * (H - 0.44), sz * (Dp / 2 - 0.22), 0.5, 0.5, 0.5, BONE, "Metal")
    # bande de collection sur l'avant du couvercle et sur le dessus
    box(fr, 0, (seam + H) / 2, Dp / 2 - 0.05, W - 1.1, (H - seam) * 0.55, 0.06, stripe, "SmoothPlastic")
    box(fr, 0, H + 0.03, 0, W - 1.1, 0.04, 0.45, stripe, "SmoothPlastic")
    # fermoirs et poignées
    for sx in (-0.9, 0.9):
        box(fr, sx, seam, Dp / 2 - 0.02, 0.32, 0.42, 0.12, BONE, "Metal")
    for sx in (-1, 1):
        box(fr, sx * (W / 2 - 0.02), seam - 0.25, 0, 0.1, 0.12, 0.9, (20, 20, 22), "Metal")
    # pochoir : trois traits os sur la face avant du bas (numéro de série)
    for i in range(3):
        box(fr, -W / 2 + 0.75 + i * 0.32, seam * 0.45, Dp / 2 - 0.05, 0.18, 0.5, 0.04, (200, 196, 186))


# Cette méthode permet de poser une silhouette d'AWP (origine au centre, canon vers +x local) à la teinte d'un skin.
def awp(fr, skin, k=1.0):
    main, acc = SKINS[skin]
    box(fr, -1.6 * k, -0.05 * k, 0, 1.3 * k, 0.55 * k, 0.24 * k, main)  # crosse
    box(fr, -0.35 * k, 0.02 * k, 0, 1.4 * k, 0.36 * k, 0.26 * k, acc, "Metal")  # carcasse
    box(fr, -0.2 * k, -0.32 * k, 0, 0.32 * k, 0.45 * k, 0.2 * k, main)  # chargeur
    box(fr, -0.75 * k, -0.33 * k, 0, 0.18 * k, 0.4 * k, 0.16 * k, (20, 20, 22))  # poignée
    box(fr, 1.45 * k, 0.05 * k, 0, 2.3 * k, 0.13 * k, 0.13 * k, (30, 30, 32), "Metal", "Cylinder")  # canon
    box(fr, -0.25 * k, 0.4 * k, 0, 1.3 * k, 0.24 * k, 0.24 * k, (24, 24, 26), "Metal", "Cylinder")  # lunette
    box(fr, 0.75 * k, 0.05 * k, 0, 0.5 * k, 0.3 * k, 0.28 * k, main)  # garde-main


# Cette méthode permet de poser une silhouette de baïonnette M9 (origine au centre, lame vers +x local).
def m9(fr, skin, k=1.0):
    main, acc = SKINS[skin]
    box(fr, 0.45 * k, 0.02 * k, 0, 0.95 * k, 0.24 * k, 0.05 * k, acc, "Metal")  # lame
    box(fr, 0.95 * k, 0.06 * k, 0, 0.18 * k, 0.12 * k, 0.05 * k, acc, "Metal")  # pointe
    box(fr, -0.05 * k, 0.0, 0, 0.08 * k, 0.4 * k, 0.12 * k, (30, 30, 32), "Metal")  # garde
    box(fr, -0.42 * k, -0.02 * k, 0, 0.66 * k, 0.2 * k, 0.14 * k, main)  # manche


# Cette méthode permet de construire un personnage en blocs R6 (pieds à l'origine, regard vers +z local).
def character(fr):
    cloth, pants, skin, gear = (62, 66, 58), (46, 46, 44), (196, 150, 120), (30, 32, 30)
    for sx in (-0.5, 0.5):
        box(fr, sx, 1.0, 0, 1, 2, 1, pants)
        box(fr, sx, 0.2, 0.08, 1.02, 0.4, 1.12, (26, 24, 22))  # chaussures
    box(fr, 0, 3.0, 0, 2, 2, 1, cloth)
    box(fr, 0, 3.1, 0.05, 1.7, 1.4, 1.1, gear)  # gilet
    for sx in (-1.5, 1.5):
        box(fr, sx, 3.0, 0, 1, 2, 1, cloth)
    box(fr, 0, 4.6, 0, 1.15, 1.15, 1.15, skin)
    box(fr, 0, 5.15, 0, 1.25, 0.45, 1.25, gear)  # bonnet


def rack(fr, W=10.4, Dp=3.0, levels=(0.25, 2.95, 5.65), H=8.2):
    for sx in (-1, 1):
        for sz in (-1, 1):
            box(fr, sx * (W / 2 - 0.15), H / 2, sz * (Dp / 2 - 0.15), 0.3, H, 0.3, (70, 74, 80), "Metal")
    for y in levels:
        box(fr, 0, y, 0, W, 0.16, Dp, (88, 92, 98), "DiamondPlate")
        box(fr, 0, y + 0.02, Dp / 2 - 0.08, W, 0.3, 0.12, AMBER, "Metal")  # longeron avant peint
    box(fr, 0, H - 0.1, 0, W, 0.2, Dp, (70, 74, 80), "Metal")


def load(name):
    return json.load(open(os.path.join(D, name), encoding="utf-8"))


def write(name, parts, lights, views):
    json.dump({"parts": parts, "lights": lights}, open(os.path.join(D, name + "_parts.json"), "w", encoding="utf-8"))
    json.dump(views, open(os.path.join(D, name + "_views.json"), "w", encoding="utf-8"))


# Cette méthode permet de garder les pièces de la map hors d'une boîte (zone dégagée pour poser un prop).
def clear(parts, fr, x0, x1, z0, z1, maxsize=12):
    out = []
    for p in parts:
        rel = tuple(p[1 + i] - fr.o[i] for i in range(3))
        lx = sum(a * b for a, b in zip(rel, fr.r))
        lz = sum(a * b for a, b in zip(rel, fr.f))
        if x0 <= lx <= x1 and z0 <= lz <= z1 and max(p[13:16]) < maxsize and rel[1] > 0.3:
            continue
        out.append(p)
    return out


RES = [1600, 900]
FOV = 40  # FOV vertical de la caméra du menu (MenuScene.VERTICAL_FOV)

# ---- A : rack de caisses dans la zone de stockage T, contre le mur en tôle -------------------------------------
wall = Frame((1918.72, 70.56, -357.63), (0.894, 0, -0.447))  # avant = hors du mur
rk = wall.sub(-14, 0, 2.1)
crates_a = [
    (rk.sub(-2.6, 0.33, 0, yaw=4), (226, 58, 40)),
    (rk.sub(2.6, 0.33, 0.1, yaw=-3), (40, 150, 160)),
    (rk.sub(-2.5, 3.03, 0, yaw=-2), (150, 70, 170)),
    (rk.sub(2.7, 3.03, 0, yaw=5), (190, 140, 60)),
    (rk.sub(-2.6, 5.73, 0, yaw=3), (90, 120, 200)),
    (rk.sub(2.5, 5.73, 0.05, yaw=-4), (226, 58, 40)),
]
PARTS.clear()
rack(rk)
for fr, col in crates_a:
    crate(fr, col)
# caisse choisie, sortie du rack sur une palette au sol
pal = wall.sub(-8.5, 0, 5.5, yaw=-18)
for i, x in enumerate((-1.9, 0, 1.9)):
    box(pal, x, 0.25, 0, 0.5, 0.5, 3.6, (128, 94, 64))
for z in (-1.4, 0, 1.4):
    box(pal, 0, 0.56, z, 4.4, 0.12, 0.7, (150, 112, 76))
crate(pal.sub(0, 0.62, 0), (242, 169, 0))
base = clear(load("storage.json")["parts"], wall, -27, 4, 0, 14, maxsize=40)
lights_a = load("storage.json").get("lights", [])
# cadrage : le sujet au tiers droit, le mur fuit à gauche sous l'interface
eye = wall.p(2, 5.6, 22)
write("A", base + PARTS, lights_a, [{"name": "A_rack", "position": eye, "target": wall.p(-24, 3, -2), "fov": FOV, "res": RES}])

# ---- B : salle de présentation dédiée (hors map) -------------------------------------------------------------
PARTS.clear()
room = Frame((0, 500, 0), (0, 0, 1))
box(room, 0, -0.5, 0, 40, 1, 40, (58, 56, 54), "Concrete")
for i in range(-9, 10):  # joints du sol
    box(room, i * 2.0, 0.005, 0, 0.06, 0.02, 40, (40, 39, 38))
# mur du fond en tôle nervurée, bande basse ocre
box(room, 0, 9, -9, 40, 18, 0.5, (150, 154, 156), "Metal")
for i in range(-25, 26):
    box(room, i * 0.8, 9, -8.7, 0.25, 18, 0.25, (172, 176, 178), "Metal")
box(room, 0, 1.6, -8.55, 40, 3.2, 0.12, (200, 156, 72), "Metal")
for sx in (-1, 1):  # murs latéraux
    box(room, sx * 16, 9, 2, 0.5, 18, 24, (128, 132, 134), "Metal")
box(room, 0, 18, 2, 40, 0.5, 24, (40, 42, 46), "Metal")
for x in (-8, 0, 8):  # poutres du plafond
    box(room, x, 17, 2, 0.8, 1.2, 24, (128, 94, 64), "WoodPlanks")
# socle : plateau d'acier sur deux palettes, liseré ambre
for y in (0.25, 0.85):
    for z in (-1.6, 0, 1.6):
        box(room, 0, y + 0.1, z, 5.2, 0.2, 0.9, (150, 112, 76))
    for x in (-2.2, 0, 2.2):
        box(room, x, y - 0.12, 0, 0.6, 0.26, 4.2, (128, 94, 64))
box(room, 0, 1.25, 0, 5.4, 0.18, 4.4, (70, 74, 80), "DiamondPlate")
box(room, 0, 1.25, 2.21, 5.4, 0.2, 0.04, AMBER, "Metal")
crate(room.sub(0, 1.34, 0, yaw=-14), (226, 58, 40))
# tableau du contenu sur le mur du fond : contreplaqué, une ligne AWP et une ligne M9, rareté sous chaque arme
# liseré ambré lumineux au sol autour du socle (plateau de jeu télévisé)
for sx in (-1, 1):
    box(room, sx * 4.0, 0.03, 0, 0.14, 0.04, 7.0, AMBER, "Neon")
    box(room, 0, 0.03, sx * 3.5, 8.14, 0.04, 0.14, AMBER, "Neon")
# stock : rack de caisses contre le mur du fond, à droite du tableau
srk = room.sub(9.8, 0, -6.9)
rack(srk, W=8.4)
for y, cols in ((0.33, ((40, 150, 160), (150, 70, 170))), (3.03, ((190, 140, 60), (226, 58, 40))), (5.73, ((90, 120, 200), (40, 150, 160)))):
    for x, c in zip((-2.05, 2.05), cols):
        crate(srk.sub(x, y, 0.05, yaw=(x * 1.7) % 5 - 2.5), c, W=3.7)
board = room.sub(-3, 6.6, -8.3)
box(board, 0, 0, 0, 15.5, 7.6, 0.2, (206, 170, 118), "WoodPlanks")
for i in range(-15, 16):
    box(board, i * 0.5, 3.8, 0.12, 0.05, 0.05, 0.05, (90, 70, 50))
items = [("couchant", "commun"), ("impact", "rare"), ("releve", "exceptionnel")]
for j, (skin, rar) in enumerate(items):
    x = -4.9 + j * 4.9
    awp(board.sub(x, 1.9, 0.35), skin, 0.95)
    box(board, x, 0.75, 0.13, 3.8, 0.18, 0.06, RARITY[rar])
    m9(board.sub(x, -1.4, 0.3), skin, 1.5)
    box(board, x, -2.6, 0.13, 3.8, 0.18, 0.06, RARITY[rar])
# stock à gauche : second rack contre le mur latéral, derrière la colonne de texte
lrk = room.sub(-14.3, 0, -2.6, yaw=90)
rack(lrk, W=8.4)
for y, cols in ((0.33, ((226, 58, 40), (90, 120, 200))), (3.03, ((40, 150, 160), (190, 140, 60))), (5.73, ((150, 70, 170), (226, 58, 40)))):
    for x, c in zip((-2.05, 2.05), cols):
        crate(lrk.sub(x, y, 0.05, yaw=(x * 1.3) % 5 - 2.5), c, W=3.7)
# suspension industrielle au-dessus de la caisse : câble, cloche émaillée, ampoule
box(room, 0, 14.0, 0, 0.06, 8.0, 0.06, (20, 20, 20))
box(room, 0, 10.15, 0, 0.45, 0.4, 0.45, (30, 32, 34), "Metal", "Cylinder", axis="y")  # douille
box(room, 0, 9.85, 0, 1.0, 0.3, 1.0, (52, 58, 54), "Metal", "Cylinder", axis="y")  # haut de la cloche
box(room, 0, 9.6, 0, 1.9, 0.25, 1.9, (52, 58, 54), "Metal", "Cylinder", axis="y")
box(room, 0, 9.42, 0, 2.4, 0.14, 2.4, (52, 58, 54), "Metal", "Cylinder", axis="y")  # bord
box(room, 0, 9.36, 0, 2.2, 0.04, 2.2, (243, 233, 220), "SmoothPlastic", "Cylinder", axis="y")  # intérieur émaillé
box(room, 0, 9.3, 0, 0.6, 0.6, 0.6, (255, 241, 224), "Neon", "Ball")
spot = [list(room.p(0, 11.9, 0)) + [0, -1, 0] + [60, 30, 2.5] + [255, 228, 190]]
spot += [list(room.p(8.5, 9.5, 3)) + list(norm((0.15, -0.45, -1))) + [55, 30, 0.8] + [200, 214, 255]]  # rack, plus froid, de face
spot += [list(room.p(-3, 16, -2)) + list(norm((0, -1, -0.6))) + [80, 30, 0.9] + [255, 236, 210]]  # tableau
# appoint de face (anciens projecteurs sur trépied, retirés de l'image) : gardé, l'éclairage a été validé avec
spots = [list(room.p(sx * 6.5, 4.3, 3.5)) + list(norm(add(room.p(0, 2.5, 0), mul(room.p(sx * 6.5, 4.3, 3.5), -1)))) + [50, 30, 1.6] + [255, 220, 170] for sx in (-1, 1)]
eye = room.p(4, 5.2, 20)
write("B", PARTS[:], spot + spots, [{"name": "B_salle", "position": eye, "target": room.p(-4.5, 4.5, 0), "fov": FOV, "res": RES, "radius": 100000}])

# ---- C : caisse posée près du personnage de l'accueil (plan Dizzy de MenuScene) ----------------------------------
PARTS.clear()
feet = (1768, 104.65, -375)
me = Frame(feet, (-1, 0, 0))  # regarde la caméra (-X)
character(me)
awp(me.sub(0, 3.2, 0.75, roll=38), "impact", 0.95)
crate(me.sub(-3.0, 0, 1.6, yaw=24), (226, 58, 40))  # x local négatif = gauche de l'image
eye = (1751, 107.8, -375)
look = rot(norm((17, 0.8, 0)), UP, 20)
write("C", load("menu.json")["parts"] + PARTS, [], [{"name": "C_accueil", "position": eye, "target": add(eye, look), "fov": FOV, "res": RES}])
print("ok")
