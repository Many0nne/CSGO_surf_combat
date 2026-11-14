# Propositions de modèles de caisses (#332, planche docs/ui/shop/planche_caisses.png, B retenue : tools/shop/crate_model.py) :
# la caisse en pièces d'avant et quatre variantes, même encombrement (4 x 2 x 2,4 studs), couvercle séparé pour
# l'ouverture, bande de collection recolorable. Rendus Workbench (~5 s), vue 3/4 avant et vue arrière par variante :
#   blender -b --factory-startup --python tools/shop/crate_designs.py -- <dossier absolu>
#   python -I tools/shop/crate_sheet.py <dossier> <planche.png>
import bpy, bmesh, math, os, sys

OUT = sys.argv[sys.argv.index("--") + 1]
os.makedirs(OUT, exist_ok=True)
W, H, D = 4.0, 2.0, 2.4

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)


# Cette méthode permet de convertir une couleur sRGB 0-255 en couleur linéaire Blender.
def lin(c):
    def f(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

    return (f(c[0]), f(c[1]), f(c[2]), 1.0)


MATS = {}


# Cette méthode permet de réutiliser un matériau par couleur (Workbench lit diffuse_color).
def mat(c, rough=0.6, metal=0.0):
    key = (c, rough, metal)
    if key not in MATS:
        m = bpy.data.materials.new(f"m{len(MATS)}")
        m.diffuse_color = lin(c)
        m.roughness = rough
        m.metallic = metal
        MATS[key] = m
    return MATS[key]


OX = 0.0  # décalage x de la caisse en cours


# Cette méthode permet de poser une boîte biseautée (centre, taille, rotation en degrés) dans la caisse en cours.
def B(x, y, z, sx, sy, sz, col, bev=0.02, seg=2, rot=(0, 0, 0), metal=0.0):
    me = bpy.data.meshes.new("b")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("b", me)
    bpy.context.collection.objects.link(ob)
    ob.location = (x + OX, y, z)
    ob.rotation_euler = tuple(math.radians(a) for a in rot)
    ob.data.materials.append(mat(col, metal=metal))
    if bev > 0:
        m = ob.modifiers.new("bev", "BEVEL")
        m.width = min(bev, min(sx, sy, sz) * 0.45)
        m.segments = seg
        m.limit_method = "ANGLE"
    return ob


# Cette méthode permet de poser un cylindre (axe x, y ou z) dans la caisse en cours.
def C(x, y, z, r, depth, col, axis="z", verts=24, metal=0.0):
    rot = {"x": (0, math.pi / 2, 0), "y": (math.pi / 2, 0, 0), "z": (0, 0, 0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, vertices=verts, location=(x + OX, y, z), rotation=rot)
    ob = bpy.context.active_object
    ob.data.materials.append(mat(col, metal=metal))
    return ob


# Cette méthode permet de poser une sphère (coin boule de flight case).
def S(x, y, z, r, col):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(x + OX, y, z), segments=20, ring_count=10)
    ob = bpy.context.active_object
    ob.data.materials.append(mat(col))
    bpy.ops.object.shade_smooth()
    return ob


# Cette méthode permet de poser un tore (poignée en corde) dans la caisse en cours.
def T(x, y, z, R, r, col, rot):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=R, minor_radius=r, location=(x + OX, y, z), rotation=tuple(math.radians(a) for a in rot)
    )
    ob = bpy.context.active_object
    ob.data.materials.append(mat(col))
    bpy.ops.object.shade_smooth()
    return ob


FONT = bpy.data.fonts.load("C:/Windows/Fonts/ARIALNB.TTF")


# Cette méthode permet d'écrire un pochoir (texte extrudé) sur une face : avant (-y) ou dessus (+z).
def TXT(s, x, y, z, size, col, face="front", align="CENTER"):
    cu = bpy.data.curves.new("t", "FONT")
    cu.body = s
    cu.font = FONT
    cu.size = size
    cu.extrude = 0.004
    cu.align_x = align
    cu.align_y = "CENTER"
    ob = bpy.data.objects.new("t", cu)
    bpy.context.collection.objects.link(ob)
    ob.location = (x + OX, y, z)
    ob.rotation_euler = (math.radians(90), 0, 0) if face == "front" else (0, 0, 0)
    ob.data.materials.append(mat(col))
    return ob


BONE = (243, 233, 220)
AMBER = (242, 169, 0)
RED = (226, 58, 40)  # bande de la collection (série 1)
GRAPHITE = (44, 48, 54)
INK = (14, 15, 17)


# Cette méthode permet de reconstruire la caisse actuelle (board.py, `crate`) pour la comparaison.
def current():
    B(0, 0, H / 2, W - 0.16, D - 0.16, H - 0.16, GRAPHITE, 0)
    seam = H * 0.62
    B(0, 0, seam, W - 0.1, D - 0.1, 0.07, INK, 0)
    B(0, 0, H - 0.02, W - 0.5, D - 0.5, 0.08, (54, 58, 64), 0)
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (0, 1):
                B(sx * (W / 2 - 0.22), sy * (D / 2 - 0.22), 0.22 + sz * (H - 0.44), 0.5, 0.5, 0.5, BONE, 0)
    B(0, -(D / 2 - 0.05), (seam + H) / 2, W - 1.1, 0.06, (H - seam) * 0.55, RED, 0)
    B(0, 0, H + 0.03, W - 1.1, 0.45, 0.04, RED, 0)
    for sx in (-0.9, 0.9):
        B(sx, -(D / 2 - 0.02), seam, 0.32, 0.12, 0.42, BONE, 0)
    for sx in (-1, 1):
        B(sx * (W / 2 - 0.02), 0, seam - 0.25, 0.1, 0.9, 0.12, (20, 20, 22), 0)
    for i in range(3):
        B(-W / 2 + 0.75 + i * 0.32, -(D / 2 - 0.05), seam * 0.45, 0.18, 0.04, 0.5, (200, 196, 186), 0)


# Cette méthode permet de construire la variante A, mallette en polymère (type valise étanche) : coque arrondie,
# nervures de ceinture, fermoirs à levier, poignées latérales, joint sombre où filtrera la lueur à l'ouverture.
def polymer():
    shell, lid = (40, 43, 48), (48, 52, 58)
    B(0, 0, 0.65, W, D, 1.18, shell, 0.16, 4)  # coque basse
    B(0, 0, 1.25, W - 0.12, D - 0.12, 0.07, INK, 0.01)  # joint
    B(0, 0, 1.64, W, D, 0.72, lid, 0.16, 4)  # couvercle
    for z in (0.42, 0.92):  # nervures de ceinture
        B(0, 0, z, W + 0.06, D + 0.06, 0.1, (34, 36, 40), 0.04, 2)
    for y in (-0.55, 0.55):  # nervures du couvercle
        B(0, y, 2.02, W - 0.9, 0.16, 0.08, (58, 62, 68), 0.03)
    B(0, 0, 2.0, W - 1.3, 0.8, 0.03, RED, 0.005)  # bande de collection, dessus
    B(0, -D / 2 - 0.004, 1.66, W - 1.7, 0.02, 0.32, RED, 0.005)  # bande de collection, avant
    for x in (-1.45, 1.45):  # fermoirs à levier
        B(x, -D / 2 - 0.05, 1.22, 0.46, 0.1, 0.62, BONE, 0.04)
        B(x, -D / 2 - 0.11, 1.12, 0.3, 0.04, 0.22, (205, 196, 184), 0.02)
        C(x, -D / 2 - 0.06, 1.5, 0.06, 0.5, (30, 30, 32), "x")
    for sx in (-1, 1):  # poignées latérales repliées
        for y in (-0.38, 0.38):
            B(sx * (W / 2 + 0.06), y, 1.02, 0.14, 0.12, 0.16, (30, 30, 32), 0.02)
        C(sx * (W / 2 + 0.15), 0, 1.02, 0.06, 0.88, (24, 24, 26), "y")
    C(-1.5, -D / 2 - 0.02, 0.7, 0.12, 0.06, (30, 30, 32), "y")  # valve de pression
    C(-1.5, -D / 2 - 0.05, 0.7, 0.07, 0.04, BONE, "y")
    TXT("S1-0332", -0.1, -D / 2 - 0.02, 0.68, 0.24, BONE)
    TXT("SÉRIE 1", 1.2, -D / 2 - 0.02, 0.68, 0.24, (150, 146, 140))
    for x in (-1.6, 1.6):  # patins
        for y in (-0.85, 0.85):
            B(x, y, 0.04, 0.5, 0.4, 0.08, (22, 22, 24), 0.02)


# Cette méthode permet de construire la variante B, caisse d'armes en bois (planches, cadre et écharpe, coins en acier,
# poignées en corde, pochoir peint aux couleurs de la collection), dans la matière des palettes et poutres de Dizzy.
def wood():
    woods = [(150, 104, 62), (163, 115, 70), (139, 95, 57), (156, 110, 66)]
    dark = (52, 38, 26)
    B(0, 0, 1.0, W - 0.16, D - 0.16, 1.9, (34, 26, 18), 0)  # intérieur sombre
    rows = [(0.08, 0.5), (0.53, 0.95), (0.98, 1.4), (1.47, 1.88)]  # 3 rangées de corps, 1 de couvercle
    for i, (z0, z1) in enumerate(rows):
        zc, h = (z0 + z1) / 2, z1 - z0
        for s in (-1, 1):
            B(0, s * (D / 2 - 0.04), zc, W, 0.08, h, woods[(i + (s > 0)) % 4], 0.015)
            B(s * (W / 2 - 0.04), 0, zc, 0.08, D - 0.16, h, woods[(i + 2) % 4], 0.015)
    for j in range(5):  # planches du couvercle
        y = -D / 2 + 0.24 + j * 0.48
        B(0, y, 1.94, W, 0.45, 0.12, woods[j % 4], 0.015)
    for s in (-1, 1):  # cadre : montants et traverses sur l'avant et l'arrière
        yf = s * (D / 2 + 0.04)
        for x in (-(W / 2 - 0.17), W / 2 - 0.17):
            B(x, yf, 0.74, 0.34, 0.08, 1.32, woods[1], 0.015)
            B(x, yf, 1.675, 0.34, 0.08, 0.41, woods[1], 0.015)
        B(0, yf, 0.23, W - 0.68, 0.08, 0.3, woods[3], 0.015)
        B(0, yf, 1.25, W - 0.68, 0.08, 0.3, woods[3], 0.015)
        ang = math.degrees(math.atan2(1.25 - 0.23 - 0.3, W - 0.68))
        B(0, yf, 0.74, math.hypot(W - 0.68, 0.72), 0.07, 0.28, woods[0], 0.015, rot=(0, -ang * s, 0))
    for s in (-1, 1):  # côtés : montants
        for y in (-(D / 2 - 0.17), D / 2 - 0.17):
            B(s * (W / 2 + 0.04), y, 0.74, 0.08, 0.34, 1.32, woods[2], 0.015)
    steel = (62, 64, 68)
    for sx in (-1, 1):  # coins en acier
        for sy in (-1, 1):
            for z in (0.24, 1.78):
                B(sx * (W / 2 - 0.2), sy * (D / 2 + 0.095), z, 0.42, 0.03, 0.42, steel, 0.01)
                B(sx * (W / 2 + 0.095), sy * (D / 2 - 0.2), z, 0.03, 0.42, 0.42, steel, 0.01)
            B(sx * (W / 2 - 0.2), sy * (D / 2 - 0.2), 2.01, 0.42, 0.42, 0.03, steel, 0.01)
    for x in (-1.0, 1.0):  # moraillons
        B(x, -D / 2 - 0.1, 1.44, 0.2, 0.04, 0.4, steel, 0.01)
        C(x, -D / 2 - 0.13, 1.33, 0.05, 0.05, (90, 92, 96), "y")
    B(-0.65, -D / 2 - 0.004, 1.675, 1.9, 0.01, 0.3, RED, 0)  # bande peinte de la collection
    TXT("S1-0332", 1.0, -D / 2 - 0.006, 1.675, 0.26, (24, 22, 20))
    B(0, 0, 2.005, 0.7, D - 0.2, 0.01, RED, 0)  # bande sur le dessus
    for sx in (-1, 1):  # poignées en corde
        T(sx * (W / 2 + 0.09), 0, 1.0, 0.3, 0.05, (176, 156, 116), (0, 90, 0))
        for y in (-0.3, 0.3):
            B(sx * (W / 2 + 0.1), y, 1.18, 0.05, 0.14, 0.12, steel, 0.01)
    TXT("SÉRIE 1", -1.2, -0.5, 2.03, 0.3, INK, "top")


# Cette méthode permet de construire la variante C, coffre à munitions en acier (tôle nervurée comme les murs de Dizzy,
# couvercle à rebord, leviers de serrage, poignée rabattue, ceinture peinte aux couleurs de la collection).
def ammo():
    body, lidc = (52, 58, 64), (60, 66, 72)
    B(0, 0, 0.72, W - 0.14, D - 0.24, 1.36, body, 0.06, 2)
    for s in (-1, 1):  # nervures embouties avant et arrière
        for i in range(9):
            B(-1.6 + i * 0.4, s * ((D - 0.24) / 2 + 0.02), 0.52, 0.16, 0.06, 0.72, (46, 51, 57), 0.025)
        for i in range(5):
            B(s * ((W - 0.14) / 2 + 0.02), -0.8 + i * 0.4, 0.52, 0.06, 0.16, 0.72, (46, 51, 57), 0.025)
    B(0, 0, 1.12, W - 0.08, D - 0.18, 0.2, RED, 0.02)  # ceinture de collection
    B(0, 0, 1.405, W - 0.16, D - 0.26, 0.04, INK, 0)  # joint
    B(0, 0, 1.62, W, D - 0.06, 0.42, lidc, 0.08, 3)  # couvercle à rebord
    B(0, 0, 1.86, W - 0.6, D - 0.6, 0.08, (66, 72, 78), 0.05, 2)  # panneau embouti
    lite = (128, 132, 138)
    for x in (-0.75, 0.75):  # poignée rabattue
        B(x, 0.1, 1.94, 0.2, 0.26, 0.1, (40, 42, 46), 0.02)
        B(x, -0.12, 1.96, 0.07, 0.42, 0.06, lite, 0.015)
    C(0, -0.34, 1.97, 0.06, 1.56, lite, "x")
    for sx in (-1, 1):  # leviers de serrage latéraux
        C(sx * (W / 2 + 0.0), 0, 0.98, 0.08, 0.6, (40, 42, 46), "y")
        B(sx * (W / 2 + 0.05), 0, 1.3, 0.08, 0.46, 0.7, lite, 0.02, rot=(0, -6 * sx, 0))
        B(sx * (W / 2 + 0.08), 0, 1.62, 0.06, 0.3, 0.12, AMBER, 0.02)
    TXT("SÉRIE 1  ·  S1-0332", 0, -(D - 0.06) / 2 - 0.01, 1.6, 0.2, BONE)
    TXT("CAL. 338 · 10 CPS", -1.0, -(D - 0.24) / 2 - 0.06, 0.52, 0.16, BONE)
    for y in (-0.8, 0.8):  # patins
        B(0, y, 0.03, W - 0.5, 0.22, 0.06, (22, 22, 24), 0.02)


# Cette méthode permet de construire la variante D, flight case (panneaux noirs, cornières et coins boule en alu,
# fermoirs papillon encastrés, étiquette os, panneau de couvercle aux couleurs de la collection).
def flight():
    pan, alu, chrome = (26, 28, 32), (168, 172, 178), (205, 208, 212)
    B(0, 0, 0.66, W - 0.06, D - 0.06, 1.24, pan, 0.01)
    B(0, 0, 1.65, W - 0.06, D - 0.06, 0.66, pan, 0.01)
    B(0, 0, 1.3, W - 0.1, D - 0.1, 0.06, INK, 0)  # fente du joint
    for z in (1.265, 1.335):  # profilés de fermeture
        B(0, 0, z, W + 0.02, D + 0.02, 0.035, alu, 0.008)
    for z0, z1 in ((0.04, 1.28), (1.32, 1.98)):  # cornières
        for sx in (-1, 1):
            for sy in (-1, 1):
                B(sx * W / 2, sy * D / 2, (z0 + z1) / 2, 0.12, 0.12, z1 - z0, alu, 0.02)
        for z in (z0, z1):
            for sy in (-1, 1):
                B(0, sy * D / 2, z, W, 0.12, 0.12, alu, 0.02)
            for sx in (-1, 1):
                B(sx * W / 2, 0, z, 0.12, D, 0.12, alu, 0.02)
    for sx in (-1, 1):  # coins boule
        for sy in (-1, 1):
            for z in (0.04, 1.98):
                S(sx * W / 2, sy * D / 2, z, 0.15, chrome)
            B(sx * W / 2, sy * D / 2, 1.3, 0.22, 0.22, 0.2, chrome, 0.03)
    for x in (-1.25, 1.25):  # fermoirs papillon encastrés
        B(x, -D / 2 - 0.01, 1.3, 0.52, 0.04, 0.52, (120, 124, 130), 0.02)
        C(x, -D / 2 - 0.04, 1.3, 0.11, 0.05, chrome, "y")
        B(x, -D / 2 - 0.05, 1.3, 0.38, 0.03, 0.09, chrome, 0.01)
    for sx in (-1, 1):  # poignées encastrées
        B(sx * (W / 2 + 0.01), 0, 0.85, 0.04, 0.84, 0.46, (120, 124, 130), 0.02)
        B(sx * (W / 2 + 0.05), 0, 0.97, 0.05, 0.62, 0.08, (22, 22, 24), 0.02)
    B(0, -D / 2 - 0.035, 1.66, 1.8, 0.01, 0.4, RED, 0)  # panneau de collection
    B(0, -D / 2 - 0.035, 0.68, 1.5, 0.01, 0.42, BONE, 0)  # étiquette
    TXT("SÉRIE 1 · S1-0332", 0, -D / 2 - 0.042, 0.68, 0.22, INK)
    B(0, 0, 1.985, 0.55, D - 0.3, 0.012, RED, 0)


DESIGNS = [("actuelle", current), ("A_polymere", polymer), ("B_bois", wood), ("C_munitions", ammo), ("D_flightcase", flight)]
SPACING = 10.0
for i, (_, fn) in enumerate(DESIGNS):
    OX = i * SPACING
    fn()

# sol
bpy.ops.mesh.primitive_plane_add(size=200, location=(20, 0, 0))
bpy.context.active_object.data.materials.append(mat((48, 47, 45)))

sc = bpy.context.scene
try:
    sc.render.engine = "BLENDER_WORKBENCH"
except TypeError as e:
    print(e)
sh = sc.display.shading
sh.light = "STUDIO"
sh.color_type = "MATERIAL"
sh.show_shadows = True
sh.shadow_intensity = 0.55
sh.show_cavity = True
sh.cavity_type = "BOTH"
sh.cavity_ridge_factor = 1.0
sh.cavity_valley_factor = 1.0
sh.curvature_ridge_factor = 1.0
sh.curvature_valley_factor = 1.0
sh.show_specular_highlight = True
sc.display.light_direction = (0.45, -0.35, 0.82)
sc.display_settings.display_device = "sRGB"
try:
    sc.view_settings.view_transform = "Standard"
except TypeError:
    pass
sc.render.resolution_x, sc.render.resolution_y = 900, 700
sc.render.film_transparent = False
w = bpy.data.worlds.new("w")
w.color = lin((14, 15, 20))[:3]
sc.world = w
sc.render.image_settings.file_format = "PNG"
try:
    sc.display.render_aa = "16"
except TypeError:
    pass

cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
sc.collection.objects.link(cam)
sc.camera = cam


# Cette méthode permet de viser un point depuis une position et de rendre la vue dans un fichier.
def shot(name, pos, target, lens=50):
    from mathutils import Vector

    cam.location = pos
    d = Vector(target) - Vector(pos)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = lens
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)


for i, (name, _) in enumerate(DESIGNS):
    x = i * SPACING
    shot(name, (x - 4.6, -6.8, 4.0), (x, 0, 0.95), 45)
    shot(name + "_dos", (x + 5.2, 5.8, 3.4), (x, 0, 0.95), 45)
print("OK")
