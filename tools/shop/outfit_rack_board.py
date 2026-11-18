# Planche du portant des tenues (#543, cf. docs/ui.md, « Shop : salle de présentation ») : reconstruit la salle du shop
# d'après les cotes de ShopScene (sol, murs, socle, suspension, racks et vitrine, vraie caisse de crate_model.py), pose
# un portant à vêtements blanc (référence de l'utilisateur : montants perforés, deux barres) et rend, en Workbench (quelques
# secondes par vue), au FOV vertical du jeu (40°) :
#   - q1_<présentation> : trois façons de montrer une tenue au même emplacement et au même cadrage (cintre, buste,
#     personnage complet) ;
#   - q2_<emplacement>_* : trois emplacements dans la salle (vue de face, vue détail des caisses, plan vu de dessus) ;
#   - q3_detail : vue détail d'une tenue portée par le personnage sur le socle.
# Écrit aussi labels.json (nom, prix, survol et position à l'image de l'étiquette de chaque tenue) pour sheet.
# Les tenues : vraies cartes de MERCURE (assets/outfits/mercure/maps/lisse) sur les meshs du rig, couleurs unies pour les
# autres (tenues prévues, pas encore au catalogue). Coordonnées : celles de Roblox (Y en haut), converties à la fin.
#   uv run tools/shop/outfit_rig_obj.py <rig>          (meshs du rig en OBJ, une fois)
#   blender -b --factory-startup --python tools/shop/outfit_rack_board.py -- <rig> <sortie> [vue ...]
#   python -I tools/shop/outfit_sheet.py <sortie>      (planches avec l'esquisse d'interface)
import bpy, bmesh, json, math, os, runpy, sys
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
if len(ARGS) < 2:
    sys.exit("usage : blender -b --factory-startup --python tools/shop/outfit_rack_board.py -- <rig> <sortie> [vue ...]")
RIG, OUT = os.path.abspath(ARGS[0]), os.path.abspath(ARGS[1])
ONLY = set(ARGS[2:])
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MERCURE = os.path.join(ROOT, "assets", "outfits", "mercure")
os.makedirs(OUT, exist_ok=True)

# Roblox (x, y, z) -> Blender (x, -z, y)
C = Matrix.Rotation(math.radians(90), 4, "X")
CI = C.inverted()
RES = (1600, 900)
FOV = 40  # FOV vertical de la caméra du shop (ShopScene.VERTICAL_FOV)


# Cette méthode permet de construire les matrices d'un repère Roblox (translation, lacet, roulis, échelle) lorsqu'on
# pose une pièce.
def T(x, y, z):
    return Matrix.Translation((x, y, z))


def Ry(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Y")


def Rz(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Z")


def S(x, y, z):
    return Matrix.Diagonal((x, y, z, 1.0))


# Cette méthode permet de construire un CFrame.lookAt de Roblox (avant -Z, haut +Y) lorsqu'on place une caméra.
def look_at(eye, target, up=(0, 1, 0)):
    eye, target, up = Vector(eye), Vector(target), Vector(up)
    back = (eye - target).normalized()
    right = up.cross(back).normalized()
    upv = back.cross(right)
    m = Matrix.Identity(4)
    for i in range(3):
        m[i][0], m[i][1], m[i][2], m[i][3] = right[i], upv[i], back[i], eye[i]
    return m


# ---- matières : une image unie par couleur (Workbench « texture » partout, cartes de MERCURE comprises) ---------------
MATS = {}


# Cette méthode permet de créer ou retrouver une matière à texture lorsqu'une pièce prend une couleur (image unie 4 × 4)
# ou une carte (chemin d'image).
def mat(color=None, image=None):
    key = image or tuple(color)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new(str(key))
    m.use_nodes = True
    nt = m.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    if image:
        tex.image = bpy.data.images.load(image)
    else:
        img = bpy.data.images.new(f"c{key}", 4, 4)
        img.pixels = [color[0] / 255, color[1] / 255, color[2] / 255, 1.0] * 16
        tex.image = img
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.nodes.active = tex
    MATS[key] = m
    return m


# ---- formes de base partagées (unitaires, comme une Part Roblox) ----------------------------------------------------
# Cette méthode permet de créer un mesh unitaire (boîte, cylindre couché sur X, boule) une fois, avec une case de
# matière que chaque objet remplace.
def unit_mesh(kind):
    me = bpy.data.meshes.new(kind)
    bm = bmesh.new()
    bm.loops.layers.uv.new("UVMap")  # sans calque d'UV, Workbench ne lit pas l'image (pièce blanche)
    if kind == "Block":
        bmesh.ops.create_cube(bm, size=1.0, calc_uvs=True)
    elif kind == "Cylinder":
        bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=0.5, radius2=0.5, depth=1.0, calc_uvs=True)
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    else:
        bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=0.5, calc_uvs=True)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(None)
    return me


UNIT = {k: unit_mesh(k) for k in ("Block", "Cylinder", "Ball")}
COLLS = {}


# Cette méthode permet de ranger les objets d'un ensemble (salle, portant d'une variante…) dans sa collection, pour
# l'afficher ou le masquer selon la vue.
def coll(name):
    if name not in COLLS:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
        COLLS[name] = c
    return COLLS[name]


# Cette méthode permet de poser un objet (mesh, repère Roblox, matière) dans une collection lorsqu'on construit la scène.
def place(group, mesh, m, material, name="p"):
    ob = bpy.data.objects.new(name, mesh)
    coll(group).objects.link(ob)
    ob.matrix_world = C @ m
    if ob.material_slots:
        ob.material_slots[0].link = "OBJECT"
        ob.material_slots[0].material = material
    return ob


# Cette méthode permet de poser une pièce à la manière de ShopScene.box (repère, centre, taille, couleur ; cylindre
# couché sur X, dressé sur Y si `upright`).
def box(group, frame, pos, size, color, shape="Block", upright=False):
    m = frame @ T(*pos)
    sx, sy, sz = size
    if upright:
        m = m @ Rz(90)
        sx, sy = sy, sx
    return place(group, UNIT[shape], m @ S(sx, sy, sz), mat(color))


# ---- caisse : modèle de tools/shop/crate_model.py, converti dans le repère Roblox de la caisse ----------------------
CRATE_LOOK = {
    "Interior": (34, 26, 18),
    "BodyPlanks": (150, 104, 62),
    "LidPlanks": (150, 104, 62),
    "BodyFrame": (128, 90, 56),
    "LidFrame": (128, 90, 56),
    "BodySteel": (62, 64, 68),
    "LidSteel": (62, 64, 68),
    "Rope": (176, 156, 116),
}
_argv = sys.argv
sys.argv = [_argv[0], "--", os.path.join(OUT, "_crate.fbx")]
runpy.run_path(os.path.join(HERE, "crate_model.py"))
sys.argv = _argv
CRATE = {}
bpy.context.view_layer.update()  # matrix_world des pièces fusionnées (position posée par script, pas encore évaluée)
for ob in list(bpy.data.objects):
    me = ob.data.copy()
    me.transform(ob.matrix_world)
    me.transform(CI)
    me.materials.clear()
    me.materials.append(None)
    CRATE[ob.name] = me
    bpy.data.objects.remove(ob, do_unlink=True)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)


# Cette méthode permet de poser une caisse (origine au centre du dessous, avant vers +z) à la manière de ShopScene.crate :
# largeur `width` (4 par défaut), bande de la collection `stripe` (sans : pas de bande).
def crate(group, frame, stripe=None, width=4.0):
    k = width / 4.0
    for name, me in CRATE.items():
        if name == "LidStripe" and not stripe:
            continue
        place(group, me, frame @ S(k, 1, 1), mat(stripe if name == "LidStripe" else CRATE_LOOK[name]), name)


# ---- salle (ShopScene.buildRoom, buildVitrine) ------------------------------------------------------------------------
BONE, AMBER, GLOW = (243, 233, 220), (242, 169, 0), (215, 85, 20)
WOOD, WOOD_LIGHT, STEEL_DARK = (128, 94, 64), (150, 112, 76), (70, 74, 80)
I = Matrix.Identity(4)


# Cette méthode permet de construire un rack de stock garni de six caisses (ShopScene.rack et fillRack).
def stock_rack(group, frame, colors, twist, width=8.4):
    D, H = 3.0, 8.2
    for sx in (-1, 1):
        for sz in (-1, 1):
            box(group, frame, (sx * (width / 2 - 0.15), H / 2, sz * (D / 2 - 0.15)), (0.3, H, 0.3), STEEL_DARK)
    for y in (0.25, 2.95, 5.65):
        box(group, frame, (0, y, 0), (width, 0.16, D), (88, 92, 98))
        box(group, frame, (0, y + 0.02, D / 2 - 0.08), (width, 0.3, 0.12), AMBER)
    box(group, frame, (0, H - 0.1, 0), (width, 0.2, D), STEEL_DARK)
    for level, y in enumerate((0.33, 3.03, 5.73)):
        for k, x in enumerate((-2.05, 2.05)):
            crate(group, frame @ T(x, y, 0.05) @ Ry((x * twist) % 5 - 2.5), colors[level * 2 + k], 3.4)


# Cette méthode permet de construire la pièce, le socle, les racks de stock et la suspension (ShopScene.buildRoom) ; la
# caisse du socle et la cloche sont à part (masquées dans la vue détail d'une tenue, cloche remontée).
def build_room():
    g = "room"
    box(g, I, (0, -0.5, 4), (40, 1, 48), (58, 56, 54))
    for i in range(-9, 10):
        box(g, I, (i * 2, 0.005, 4), (0.06, 0.02, 48), (40, 39, 38))
    box("walls", I, (0, 9, -9), (40, 18, 0.5), (150, 154, 156))
    for i in range(-25, 26):
        box("walls", I, (i * 0.8, 9, -8.7), (0.25, 18, 0.25), (172, 176, 178))
    box("walls", I, (0, 1.6, -8.55), (40, 3.2, 0.12), (200, 156, 72))
    for sx in (-1, 1):
        box("walls", I, (sx * 16, 9, 7), (0.5, 18, 34), (128, 132, 134))
    for i in range(-12, 30):
        box("walls", I, (15.7, 9, i * 0.8), (0.25, 18, 0.25), (150, 154, 156))
    box("front", I, (0, 9, 24.25), (40, 18, 0.5), (128, 132, 134))
    box("ceiling", I, (0, 18, 7), (40, 0.5, 34), (40, 42, 46))
    for x in (-8, 0, 8):
        box("ceiling", I, (x, 17, 7), (0.8, 1.2, 34), WOOD)
    for y in (0.25, 0.85):
        for z in (-1.6, 0, 1.6):
            box(g, I, (0, y + 0.1, z), (5.2, 0.2, 0.9), WOOD_LIGHT)
        for x in (-2.2, 0, 2.2):
            box(g, I, (x, y - 0.12, 0), (0.6, 0.26, 4.2), WOOD)
    box(g, I, (0, 1.25, 0), (5.4, 0.18, 4.4), STEEL_DARK)
    box(g, I, (0, 1.25, 2.21), (5.4, 0.2, 0.04), AMBER)
    for sx in (-1, 1):
        box(g, I, (sx * 4, 0.03, 0), (0.14, 0.04, 7), GLOW)
        box(g, I, (0, 0.03, sx * 3.5), (8.14, 0.04, 0.14), GLOW)
    stock_rack("back_rack", T(9.8, 0, -6.9), [(40, 150, 160), (150, 70, 170), (190, 140, 60), (226, 58, 40), (90, 120, 200), (40, 150, 160)], 1.7)
    stock_rack("left_rack", T(-14.3, 0, -2.6) @ Ry(90), [(226, 58, 40), (90, 120, 200), (40, 150, 160), (190, 140, 60), (150, 70, 170), (226, 58, 40)], 1.3)
    crate("podium_crate", T(0, 1.34, 0) @ Ry(-14), (226, 58, 40))
    for lift, group in ((0.7, "lamp"), (2.7, "lamp_high")):
        lf = T(0, lift, 0)
        top = 17.75 - lift
        box(group, lf, (0, (top + 10.35) / 2, 0), (0.06, top - 10.35, 0.06), (20, 20, 20))
        box(group, lf, (0, 10.15, 0), (0.45, 0.4, 0.45), (30, 32, 34), "Cylinder", True)
        box(group, lf, (0, 9.85, 0), (1, 0.3, 1), (52, 58, 54), "Cylinder", True)
        box(group, lf, (0, 9.6, 0), (1.9, 0.25, 1.9), (52, 58, 54), "Cylinder", True)
        box(group, lf, (0, 9.42, 0), (2.4, 0.14, 2.4), (52, 58, 54), "Cylinder", True)
        box(group, lf, (0, 9.36, 0), (2.2, 0.04, 2.2), BONE, "Cylinder", True)
        box(group, lf, (0, 9.3, 0), (0.6, 0.6, 0.6), (255, 241, 224), "Ball")


VITRINE = T(14.2, 0, 7.3) @ Ry(-90)
# Caisses en vente (ShopCatalog.CRATES, dans l'ordre de la vitrine : deux par étage, l'étage à hauteur d'œil d'abord)
SALE = [(226, 58, 40), (40, 150, 160), (205, 150, 55), (70, 160, 90)]


# Cette méthode permet de construire la vitrine des caisses (ShopScene.buildVitrine) avec les quatre caisses en vente.
def build_vitrine():
    g, f, W, H, D = "vitrine", VITRINE, 13.2, 8.4, 3.0
    for sx in (-1, 0, 1):
        for sz in (-1, 1):
            if sx or sz < 0:
                box(g, f, (sx * (W / 2 - 0.15), H / 2, sz * (D / 2 - 0.15)), (0.3, H, 0.3), STEEL_DARK)
    for y in (4.95, 1.45):
        box(g, f, (0, y, 0), (W, 0.16, D), (88, 92, 98))
        box(g, f, (0, y + 0.02, D / 2 - 0.08), (W, 0.3, 0.12), AMBER)
    box(g, f, (0, H - 0.1, 0), (W, 0.2, D), STEEL_DARK)
    for i, stripe in enumerate(SALE):
        level = (4.95, 1.45)[i // 2]
        x = (i % 2 - 0.5) * 4.3
        crate(g, f @ T(x, level + 0.08, -0.1) @ Ry(((i + 1) * 7) % 5 - 2), stripe, 3.4)
        box(g, f, (x, level - 0.12, D / 2 + 0.03), (3.4, 0.62, 0.05), BONE)


# ---- tenues sur le rig R15 -------------------------------------------------------------------------------------------
RIG_PARTS = json.load(open(os.path.join(RIG, "rig.json"), encoding="utf-8"))
RIG_MESH = {}
for name in RIG_PARTS:
    # axes par défaut de l'importeur (fichier Y en haut, comme Roblox) : la conversion inverse ramène au repère Roblox
    bpy.ops.wm.obj_import(filepath=os.path.join(RIG, name + ".obj"))
    bpy.context.view_layer.update()
    ob = bpy.context.selected_objects[0]
    me = ob.data
    me.transform(ob.matrix_world)
    me.transform(CI)
    me.materials.clear()
    me.materials.append(None)
    RIG_MESH[name] = me
    bpy.data.objects.remove(ob, do_unlink=True)
# Coque de tête de MERCURE (mesh de la tête classique à la taille du rig, docs/assets.md) : sert de tête à toutes les
# tenues, centrée sur la pièce Head du rig (posée sur le haut du torse)
bpy.ops.import_scene.fbx(filepath=os.path.join(MERCURE, "MercureHead.fbx"))
bpy.context.view_layer.update()
_head = [o for o in bpy.context.selected_objects if o.type == "MESH"][0]
HEAD_MESH = _head.data
HEAD_MESH.transform(_head.matrix_world)
HEAD_MESH.transform(CI)
_lo = Vector([min(v.co[k] for v in HEAD_MESH.vertices) for k in range(3)])
_hi = Vector([max(v.co[k] for v in HEAD_MESH.vertices) for k in range(3)])
HEAD_MESH.transform(Matrix.Translation(-(_lo + _hi) / 2))
HEAD_MESH.materials.clear()
HEAD_MESH.materials.append(None)
print("coque de tête (studs) :", tuple(round(c, 3) for c in (_hi - _lo)))
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
HEAD_Y = 1.5882 + 1.5882 / 2  # haut du torse + demi-tête du rig
TORSO_TOP, PELVIS_TOP, FEET = 1.5882, -0.953, -4.765
TOP = {"UpperTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"}
BOTTOM = {"LowerTorso", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"}
BUST = {"UpperTorso", "LowerTorso", "Head"}
FULL = TOP | BOTTOM | {"Head"}

# Tenues du portant, dans l'ordre du catalogue (prix puis nom, InventoryRules.outfits) : MERCURE existe, les autres sont
# celles prévues cette nuit (#543), en couleurs unies plausibles (torse, membres, tête)
LISSE = os.path.join(MERCURE, "maps", "lisse")
OUTFITS = [
    {"name": "NÉOPRÈNE", "rarity": "COMMUN", "price": 600, "colors": ((30, 34, 40), (24, 26, 30), (30, 34, 40))},
    {"name": "PLÂTRE", "rarity": "COMMUN", "price": 600, "colors": ((224, 216, 200), (214, 206, 190), (226, 218, 204))},
    {"name": "BRONZE", "rarity": "RARE", "price": 1200, "colors": ((160, 104, 52), (140, 88, 44), (166, 110, 58))},
    {"name": "PORCELAINE", "rarity": "RARE", "price": 1200, "colors": ((236, 236, 240), (52, 82, 168), (236, 236, 240))},
    {"name": "MERCURE", "rarity": "EXCEPTIONNEL", "price": 2500, "maps": LISSE},
    {"name": "CHITINE", "rarity": "LÉGENDAIRE", "price": 5000, "colors": ((52, 60, 44), (34, 40, 30), (40, 46, 34))},
]
HOVER = "MERCURE"


# Cette méthode permet de donner la matière d'une pièce du rig pour une tenue (carte de son atlas, ou couleur unie du
# torse, des membres ou de la tête).
def outfit_mat(outfit, part):
    group = "Head" if part == "Head" else RIG_PARTS[part]["group"]
    if "maps" in outfit:
        sub = "Head" if group == "Head" else "R15"
        return mat(image=os.path.join(outfit["maps"], sub, f"{group}_Color.png"))
    torso, limbs, head = outfit["colors"]
    return mat(head if group == "Head" else torso if group == "Torso" else limbs)


# Cette méthode permet de poser des pièces du rig habillées d'une tenue dans un repère (racine du rig au repos à
# l'origine du repère, avant du personnage vers -z du repère).
def figure(group, frame, outfit, parts):
    for name in parts:
        if name == "Head":
            place(group, HEAD_MESH, frame @ T(0, HEAD_Y, 0), outfit_mat(outfit, "Head"), "Head")
        else:
            c = RIG_PARTS[name]["center"]
            place(group, RIG_MESH[name], frame @ T(*c), outfit_mat(outfit, name), name)


# ---- portant ---------------------------------------------------------------------------------------------------------
WHITE, CHROME, HOLE = (236, 236, 232), (196, 200, 206), (60, 62, 66)
HANGER = (176, 128, 80)
LABELS = {}  # vue -> étiquettes ; repères 3D par portant, projetés au rendu
TAGS = {}  # collection -> [(tenue, centre, bord droit)] en coordonnées Roblox


# Cette méthode permet de construire le cadre blanc du portant (repère : x le long, y en haut, z vers la pièce) : quatre
# montants perforés, traverses et écharpes sur les côtés, barres chromées et plateaux éventuels.
def portant(g, f, W, H, D, bars=(), shelves=()):
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * (W / 2 - 0.15), sz * (D / 2 - 0.15)
            box(g, f, (x, H / 2, z), (0.3, H, 0.3), WHITE)
            box(g, f, (x, 0.03, z), (0.6, 0.06, 0.6), STEEL_DARK)
            for k in range(int((H - 0.6) / 0.45)):
                box(g, f, (x, 0.45 + k * 0.45, z + sz * 0.151), (0.1, 0.22, 0.02), HOLE)
        # côté : traverses haute et basse, écharpe en diagonale (référence)
        x = sx * (W / 2 - 0.15)
        for y in (0.35, H - 0.15):
            box(g, f, (x, y, 0), (0.22, 0.22, D - 0.3), WHITE)
        span = Vector((0, H - 0.8, D - 0.6))
        ang = math.degrees(math.atan2(span.z, span.y))
        place(g, UNIT["Block"], f @ T(x, H / 2, 0) @ Matrix.Rotation(math.radians(-ang), 4, "X") @ S(0.14, span.length, 0.14), mat(WHITE))
    for z in (-1, 1):
        box(g, f, (0, H - 0.15, z * (D / 2 - 0.15)), (W, 0.22, 0.22), WHITE)
    for y in bars:
        box(g, f, (0, y, 0), (W - 0.3, 0.16, 0.16), CHROME, "Cylinder")
        for sx in (-1, 1):
            box(g, f, (sx * (W / 2 - 0.15), y, 0), (0.24, 0.24, D - 0.3), WHITE)
    for y in shelves:
        box(g, f, (0, y, 0), (W - 0.3, 0.12, D - 0.1), WHITE)
        box(g, f, (0, y - 0.1, D / 2 - 0.05), (W - 0.3, 0.3, 0.06), WHITE)
        for sx in (-1, 1):
            box(g, f, (sx * (W / 2 - 0.15), y, 0), (0.24, 0.24, D - 0.3), WHITE)


# Cette méthode permet de noter l'étiquette d'une tenue (centre et bord droit, repère du portant) pour l'esquisse.
def tag(g, f, outfit, x, y, z, w=2.6, h=0.5):
    box(g, f, (x, y, z), (w, h, 0.04), (226, 58, 40) if outfit["name"] == HOVER else BONE)
    TAGS.setdefault(g, []).append((outfit, f @ Vector((x, y, z + 0.03)), f @ Vector((x + w / 2, y, z + 0.03))))


# Cette méthode permet de construire la présentation « sur cintre » : haut (torse et bras) sur la barre du haut, bas
# (bassin et jambes) sur la barre du bas, chaque tenue tournée de trois quarts comme sur un vrai portant.
def rack_hangers(g, f):
    W, H, D = 13.2, 9.8, 2.6
    upper, lower = 9.0, 4.75
    portant(g, f, W, H, D, bars=(upper, lower))
    n = len(OUTFITS)
    step = (W - 3.0) / (n - 1)
    for i, o in enumerate(OUTFITS):
        x = -(W - 3.0) / 2 + i * step
        # de trois quarts, serrées comme sur un portant ; la tenue survolée sort du rang, de face
        out = o["name"] == HOVER
        yaw, z = (176, 1.9) if out else (145, 0)
        hang_top = f @ T(x, upper - 0.55 - TORSO_TOP, z) @ Ry(yaw)
        figure(g, hang_top, o, TOP)
        hang_bottom = f @ T(x, lower - 0.45 - PELVIS_TOP, z) @ Ry(yaw)
        figure(g, hang_bottom, o, BOTTOM)
        for top_y, hf in ((TORSO_TOP + 0.08, hang_top), (PELVIS_TOP + 0.06, hang_bottom)):
            # cintre en bois sur les épaules (ou pince du bas) et crochet jusqu'à la barre
            box(g, hf, (0, top_y, 0), (3.5, 0.14, 0.3), HANGER)
            box(g, hf, (0, top_y + 0.24, 0), (0.06, 0.4, 0.06), CHROME, "Cylinder", True)
        tag(g, f, o, x, H - 0.15, D / 2 + 0.02, w=step - 0.25, h=0.42)


# Cette méthode permet de construire la présentation « sur buste » : torse et tête sur un pied, trois par étage sur deux
# plateaux (même rangement que la vitrine des caisses).
def rack_busts(g, f):
    # buste de 5 studs (bas du bassin au haut de la tête) sur un pied court : l'étage du haut passe juste au-dessus des
    # têtes du bas
    W, H, D = 13.2, 12.2, 2.2
    shelves = (0.55, 6.3)
    portant(g, f, W, H, D, shelves=shelves)
    for i, o in enumerate(OUTFITS):
        level = shelves[i // 3]
        x = (i % 3 - 1) * 4.3
        base = level + 0.06
        box(g, f, (x, base + 0.05, 0), (1.3, 0.1, 1.3), (40, 40, 42), "Cylinder", True)
        box(g, f, (x, base + 0.25, 0), (0.14, 0.3, 0.14), CHROME, "Cylinder", True)
        figure(g, f @ T(x, base + 0.4 + 1.588, 0) @ Ry(180 - 12 * (i % 3 - 1)), o, BUST)
        tag(g, f, o, x, level - 0.1, D / 2 + 0.01, w=3.4, h=0.42)


# Cette méthode permet de construire la présentation « personnage complet » : six mannequins debout sur une estrade à
# deux marches devant le cadre du portant (trois devant, trois derrière décalés).
def rack_full(g, f):
    W, H, D = 13.2, 11.0, 1.2
    portant(g, f, W, H, D, bars=(H - 0.6,))
    box(g, f, (0, 0.15, 1.6), (15.0, 0.3, 3.4), (88, 92, 98))
    box(g, f, (0, 0.65, -0.9), (15.0, 1.3, 1.8), (88, 92, 98))
    box(g, f, (0, 0.31, 3.3), (15.0, 0.04, 0.06), AMBER)
    for i, o in enumerate(OUTFITS):
        back = i % 2 == 1
        x = (i - 2.5) * 2.35
        floor = 1.3 if back else 0.3
        z = -0.9 if back else 1.6
        figure(g, f @ T(x, floor - FEET, z) @ Ry(180 + (10 if x > 0 else -10)), o, FULL)
        if not back:
            tag(g, f, o, x, 0.17, 3.31, w=2.1, h=0.26)
        else:
            tag(g, f, o, x, 0.8, 0.01, w=2.1, h=0.26)


PRESENTATIONS = {"cintre": rack_hangers, "buste": rack_busts, "complet": rack_full}
# Emplacements du portant : repère (z local vers la pièce), à 2,9 studs du mur pour que les tenues de trois quarts n'y
# entrent pas
PLACES = {
    "p1": T(-12.85, 0, 16.8) @ Ry(90),  # mur de gauche, à l'avant de la salle, face à la vitrine
    "p2": T(-8.9, 0, -5.85),  # mur du fond, à gauche du socle (à la place du rack de stock de gauche)
    "p3": T(8.9, 0, -5.85),  # mur du fond, à droite du socle (à la place du rack de stock du fond)
}
HIDES = {"p2": {"left_rack"}, "p3": {"back_rack"}}


# Cette méthode permet de donner la caméra de face d'un emplacement, comme la vue d'ensemble de la vitrine (décalée de
# 2,8 studs : le portant au tiers droit, la colonne de l'interface à gauche), assez reculée pour le plus haut des
# portants (bustes sur deux étages).
def front_camera(f):
    return (f @ Vector((-2.8, 6.0, 22)), f @ Vector((-2.8, 5.4, 0)))


DETAIL_CAM = (Vector((4, 5.2, 20)), Vector((-4.5, 4.5, 0)))
VITRINE_CAM = (VITRINE @ Vector((-2.8, 5.2, 17)), VITRINE @ Vector((-2.8, 3.6, 0)))

build_room()
build_vitrine()
for p, f in PLACES.items():
    for k, fn in PRESENTATIONS.items():
        fn(f"{p}_{k}", f)
# Vue détail d'une tenue : MERCURE debout sur le socle, tourné vers la caméra de trois quarts (cloche remontée de 2 studs :
# la tête passe à 0,6 stud de la cloche à sa hauteur actuelle)
figure("podium_figure", T(0, 1.34 - FEET, 0) @ Ry(180 + 28), OUTFITS[4], FULL)

# ---- rendu ------------------------------------------------------------------------------------------------------------
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "STUDIO"
sh.color_type = "TEXTURE"
sh.show_shadows = True
sh.shadow_intensity = 0.6
sh.show_cavity = True
sh.cavity_type = "WORLD"
sh.background_type = "VIEWPORT"
sh.background_color = (0.01, 0.01, 0.015)
sc.display.light_direction = Vector((0.35, -0.25, 0.9)).normalized()
sc.view_settings.view_transform = "Standard"
sc.view_settings.exposure = 0.45  # la salle est sombre (tôle, béton) : sans lumière des lampes, on n'y verrait rien
sc.render.resolution_x, sc.render.resolution_y = RES
cam_data = bpy.data.cameras.new("Cam")
cam_data.sensor_fit = "VERTICAL"
cam_data.angle_y = math.radians(FOV)
cam_data.clip_start = 0.3
cam_data.clip_end = 500
cam = bpy.data.objects.new("Cam", cam_data)
sc.collection.objects.link(cam)
sc.camera = cam

ALWAYS = {"room", "walls", "front", "ceiling", "back_rack", "left_rack", "vitrine", "podium_crate", "lamp"}


# Cette méthode permet de rendre une vue : collections visibles, caméra (perspective au FOV du jeu, ou plan vu de dessus),
# étiquettes des tenues projetées dans l'image.
def render(name, show, cam_pose, ortho=None, res=RES):
    if ONLY and name not in ONLY:
        return
    # collections exclues de la couche de vue (pas seulement masquées au rendu) : le test d'occultation des étiquettes
    # ne voit ainsi que la scène rendue
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = lc.name not in show
    sc.render.resolution_x, sc.render.resolution_y = res
    if ortho:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = ortho
        cam_data.sensor_fit = "AUTO"
    else:
        cam_data.type = "PERSP"
        cam_data.sensor_fit = "VERTICAL"
        cam_data.angle_y = math.radians(FOV)
    eye, target = cam_pose[:2]
    up = cam_pose[2] if len(cam_pose) > 2 else (0, 1, 0)
    cam.matrix_world = C @ look_at(eye, target, up)
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    bpy.context.view_layer.update()
    labels = []
    for cname in show:
        for outfit, center, edge in TAGS.get(cname, []):
            a = world_to_camera_view(sc, cam, C @ center)
            b = world_to_camera_view(sc, cam, C @ edge)
            if a.z <= 0 or not (0 <= a.x <= 1 and 0 <= a.y <= 1):
                continue
            # étiquette cachée par une tenue ou le portant : pas de texte posé par-dessus
            origin = cam.matrix_world.translation
            target = C @ center
            ray = target - origin
            hit, loc, *_ = sc.ray_cast(bpy.context.evaluated_depsgraph_get(), origin, ray.normalized(), distance=ray.length)
            if hit and (loc - origin).length < ray.length - 0.15:
                continue
            labels.append({
                "name": outfit["name"],
                "price": outfit["price"],
                "rarity": outfit["rarity"],
                "hover": outfit["name"] == HOVER,
                "xy": [a.x * res[0], (1 - a.y) * res[1]],
                "half": (b.x - a.x) * res[0],
            })
    LABELS[name] = labels
    print("vue", name, "->", sc.render.filepath)


# Q1 : trois présentations, même emplacement (p1, face à la vitrine) et même cadrage
for k in PRESENTATIONS:
    render(f"q1_{k}", ALWAYS | {f"p1_{k}"}, front_camera(PLACES["p1"]))
# Q2 : trois emplacements (présentation sur cintre), vue de face, vue détail des caisses, plan
Q2 = "cintre"
for p, f in PLACES.items():
    show = (ALWAYS - HIDES.get(p, set())) | {f"{p}_{Q2}"}
    render(f"q2_{p}_face", show, front_camera(f))
    render(f"q2_{p}_detail", show, DETAIL_CAM)
render("q2_vitrine", ALWAYS | {f"p1_{Q2}"}, VITRINE_CAM)
plan = (ALWAYS - {"ceiling", "lamp", "front", "left_rack", "back_rack"}) | {f"{p}_{Q2}" for p in PLACES}
render("q2_plan", plan, (Vector((0, 60, 7.6)), Vector((0, 0, 7.6)), (0, 0, -1)), ortho=36, res=(1200, 1200))
# Q3 : vue détail d'une tenue (caisse du socle retirée, MERCURE debout dessus)
show = (ALWAYS - {"podium_crate", "lamp"}) | {"lamp_high", "podium_figure", "p1_cintre"}
# caméra de la vue détail des caisses, visée relevée d'un stud : personnage entier et cloche dans le cadre
render("q3_detail", show, (Vector((4, 5.6, 20)), Vector((-4.5, 5.5, 0))))
render("q3_proche", show, (Vector((2.6, 5.8, 13.5)), Vector((-2.2, 5.4, 0))))
old = {}
path = os.path.join(OUT, "labels.json")
if os.path.exists(path):
    old = json.load(open(path, encoding="utf-8"))
old.update(LABELS)
json.dump(old, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("ok")
