# Modèle de la caisse d'armes en bois (#332, piste B de la planche validée le 14/11/2026, cf. docs/ui.md « Shop ») :
# planches, cadre et écharpe, coins en acier, poignées en corde, bande peinte de la collection. Encombrement de la
# caisse en pièces qu'il remplace (4 x 2 x 2,4 studs, origine au centre du dessous, avant vers -Y Blender = +Z Roblox).
# Une pièce par matière, le couvercle à part (noms en « Lid ») pour l'ouverture ; couleurs et matières posées par le jeu
# (ShopScene), la bande « LidStripe » prend la couleur de la collection.
#   blender -b --factory-startup --python tools/shop/crate_model.py -- <sortie.fbx> [rendu.png]
# Puis : bash tools/publish_asset.sh <sortie.fbx> Model Crate, insert_asset dans Studio (docs/assets.md, « Caisse »).
import bmesh, bpy, math, os, re, runpy, sys
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
if not ARGS:
    sys.exit("usage : blender -b --factory-startup --python tools/shop/crate_model.py -- <sortie.fbx> [rendu.png]")
W, H, D = 4.0, 2.0, 2.4
UV_TILE = 4.0  # studs par unité d'UV (projection cubique)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

PIECES = {}  # groupe -> objets de travail, fusionnés à la fin en une pièce par groupe


# Cette méthode permet de ranger un objet de travail dans le groupe (future MeshPart) donné.
def keep(group, ob):
    PIECES.setdefault(group, []).append(ob)
    return ob


# Cette méthode permet de poser une boîte biseautée (centre, taille, rotation en degrés) dans un groupe.
def box(group, x, y, z, sx, sy, sz, bev=0.015, rot=(0, 0, 0)):
    me = bpy.data.meshes.new("b")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("b", me)
    bpy.context.collection.objects.link(ob)
    ob.location = (x, y, z)
    ob.rotation_euler = tuple(math.radians(a) for a in rot)
    if bev > 0:
        m = ob.modifiers.new("bev", "BEVEL")
        m.width = min(bev, min(sx, sy, sz) * 0.45)
        m.segments = 2
        m.limit_method = "ANGLE"
    return keep(group, ob)


# Cette méthode permet de poser un cylindre d'axe y (tête de moraillon) dans un groupe.
def cyl_y(group, x, y, z, r, depth):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, vertices=12, location=(x, y, z), rotation=(math.pi / 2, 0, 0))
    return keep(group, bpy.context.active_object)


# Cette méthode permet de poser un anneau de corde (tore dans le plan yz) dans un groupe.
def ring(group, x, y, z, R, r):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=R, minor_radius=r, major_segments=24, minor_segments=8, location=(x, y, z), rotation=(0, math.pi / 2, 0)
    )
    return keep(group, bpy.context.active_object)


# ---- corps : intérieur sombre, trois rangées de planches, cadre, patins -------------------------------------------
box("Interior", 0, 0, 1.0, W - 0.16, D - 0.16, 1.9, 0)
ROWS = [(0.08, 0.5), (0.53, 0.95), (0.98, 1.4), (1.47, 1.88)]  # trois rangées de corps, une de couvercle
for i, (z0, z1) in enumerate(ROWS):
    group = "LidPlanks" if i == 3 else "BodyPlanks"
    zc, h = (z0 + z1) / 2, z1 - z0
    for s in (-1, 1):
        box(group, 0, s * (D / 2 - 0.04), zc, W, 0.08, h)
        box(group, s * (W / 2 - 0.04), 0, zc, 0.08, D - 0.16, h)
for j in range(5):  # planches du couvercle
    box("LidPlanks", 0, -D / 2 + 0.24 + j * 0.48, 1.94, W, 0.45, 0.12)
for s in (-1, 1):  # cadre de l'avant et de l'arrière : montants, traverses, écharpe
    yf = s * (D / 2 + 0.04)
    for x in (-(W / 2 - 0.17), W / 2 - 0.17):
        box("BodyFrame", x, yf, 0.74, 0.34, 0.08, 1.32)
        box("LidFrame", x, yf, 1.675, 0.34, 0.08, 0.41)
    box("BodyFrame", 0, yf, 0.23, W - 0.68, 0.08, 0.3)
    box("BodyFrame", 0, yf, 1.25, W - 0.68, 0.08, 0.3)
    ang = math.degrees(math.atan2(0.72, W - 0.68))
    box("BodyFrame", 0, yf, 0.74, math.hypot(W - 0.68, 0.72), 0.07, 0.28, rot=(0, -ang * s, 0))
for s in (-1, 1):  # montants des côtés
    for y in (-(D / 2 - 0.17), D / 2 - 0.17):
        box("BodyFrame", s * (W / 2 + 0.04), y, 0.74, 0.08, 0.34, 1.32)
for y in (-0.8, 0.8):  # patins sous la caisse
    box("BodyFrame", 0, y, 0.04, W - 0.3, 0.3, 0.08)

# ---- ferrures : coins, moraillons, attaches des cordes ------------------------------------------------------------
for sx in (-1, 1):
    for sy in (-1, 1):
        for z, group in ((0.24, "BodySteel"), (1.78, "LidSteel")):
            box(group, sx * (W / 2 - 0.2), sy * (D / 2 + 0.095), z, 0.42, 0.03, 0.42, 0.01)
            box(group, sx * (W / 2 + 0.095), sy * (D / 2 - 0.2), z, 0.03, 0.42, 0.42, 0.01)
        box("LidSteel", sx * (W / 2 - 0.2), sy * (D / 2 - 0.2), 2.01, 0.42, 0.42, 0.03, 0.01)
for x in (-1.0, 1.0):  # moraillons : patte sur le couvercle, tête sur le corps
    box("LidSteel", x, -D / 2 - 0.1, 1.44, 0.2, 0.04, 0.4, 0.01)
    cyl_y("BodySteel", x, -D / 2 - 0.13, 1.33, 0.05, 0.05)
for sx in (-1, 1):  # poignées en corde et leurs attaches
    ring("Rope", sx * (W / 2 + 0.09), 0, 1.0, 0.3, 0.05)
    for y in (-0.3, 0.3):
        box("BodySteel", sx * (W / 2 + 0.1), y, 1.18, 0.05, 0.14, 0.12, 0.01)

# ---- marquage : bande de la collection (avant et dessus du couvercle) ---------------------------------------------
# Le pochoir (« S1-AWP », à droite de la bande sur la face avant) n'est plus modelé ici : le jeu le pose, propre à chaque
# caisse (#434, ShopCatalog.stencil), à la place donnée par src/shared/CrateStencil.luau, contrôlée plus bas (#456).
box("LidStripe", -0.65, -D / 2 - 0.004, 1.675, 1.9, 0.01, 0.3, 0)
box("LidStripe", 0, 0, 2.005, 0.7, D - 0.2, 0.01, 0)


# Cette méthode permet de lire un tableau de nombres (`AT = { 1.0, 1.72, 1.208 }`) de src/shared/CrateStencil.luau
# lorsque le générateur contrôle la place du pochoir ; arrêt si la ligne a changé de forme.
def stencil_const(source, name):
    m = re.search(r"^CrateStencil\." + name + r" = (\{[^}\n]*\}|[-\d.]+)", source, re.M)
    if not m:
        sys.exit(f"CrateStencil.{name} introuvable dans src/shared/CrateStencil.luau (format attendu : `= {{ a, b, c }}`)")
    values = [float(v) for v in m.group(1).strip("{} ").split(",")]
    return values if m.group(1).startswith("{") else values[0]


# Cette méthode permet de vérifier, avant l'export, que le pochoir posé par le jeu (CrateStencil) repose sur la face
# avant des planches du couvercle sans qu'une pièce (bande, cornière, moraillon, cadre) passe devant ses lettres.
def check_stencil():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "src", "shared", "CrateStencil.luau")
    source = open(path, encoding="utf-8").read()
    at, size = stencil_const(source, "AT"), stencil_const(source, "SIZE")
    ink, max_gap = stencil_const(source, "INK_HEIGHT"), stencil_const(source, "MAX_GAP")
    x0, x1 = at[0] - size[0] / 2, at[0] + size[0] / 2
    y0, y1 = at[1] - ink / 2, at[1] + ink / 2
    back = at[2] - size[2] / 2
    errors, support = [], None
    for group, objects in PIECES.items():
        for ob in objects:
            # boîte englobante dans le repère Roblox (x, z Blender, -y Blender), modificateurs non comptés (biseaux)
            pts = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
            lo = Vector((min(p.x for p in pts), min(p.z for p in pts), min(-p.y for p in pts)))
            hi = Vector((max(p.x for p in pts), max(p.z for p in pts), max(-p.y for p in pts)))
            covers = lo.x < x1 and hi.x > x0 and lo.y < y1 and hi.y > y0
            if not covers:
                continue
            if hi.z > back + 1e-4:
                errors.append(f"{group} passe devant les lettres (x {lo.x:.3f}..{hi.x:.3f}, y {lo.y:.3f}..{hi.y:.3f}, "
                              f"avant à {hi.z:.3f}, dos du pochoir à {back:.3f})")
            elif group == "LidPlanks" and lo.x <= x0 and hi.x >= x1 and lo.y <= y0 and hi.y >= y1:
                support = max(support or -1e9, hi.z)
    if support is None:
        errors.append("aucune planche du couvercle (LidPlanks) derrière tout le pochoir")
    elif back - support > max_gap:
        errors.append(f"pochoir flottant : {back - support:.3f} stud devant les planches (max {max_gap})")
    if errors:
        sys.exit("Pochoir (src/shared/CrateStencil.luau) incompatible avec la caisse :\n  " + "\n  ".join(errors))
    print(f"pochoir : x {x0:.3f}..{x1:.3f}, lettres y {y0:.3f}..{y1:.3f}, {back - support:.3f} stud devant les planches")


check_stencil()


# Cette méthode permet de fusionner les objets d'un groupe en un seul mesh (modificateurs appliqués) et de lui donner
# des UV en projection cubique (UV_TILE studs par unité), pour que la matière Roblox s'y répète à l'échelle.
def merge(group, objects):
    dg = bpy.context.evaluated_depsgraph_get()
    bm = bmesh.new()
    for ob in objects:
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        me.transform(ob.matrix_world)
        bm.from_mesh(me)
        ev.to_mesh_clear()
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        a = max(range(3), key=lambda k: abs(n[k]))
        u_axis, v_axis = [(1, 2), (0, 2), (0, 1)][a]
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = (co[u_axis] / UV_TILE, co[v_axis] / UV_TILE)
    me = bpy.data.meshes.new(group)
    bm.to_mesh(me)
    bm.free()
    for ob in objects:
        bpy.data.objects.remove(ob, do_unlink=True)
    final = bpy.data.objects.new(group, me)
    bpy.context.collection.objects.link(final)
    # origine de chaque pièce au centre de sa boîte (comme l'importeur Roblox), position conservée
    lo = Vector([min(v.co[k] for v in me.vertices) for k in range(3)])
    hi = Vector([max(v.co[k] for v in me.vertices) for k in range(3)])
    center = (lo + hi) / 2
    me.transform(Matrix.Translation(-center))
    final.location = center
    return final


# Couleurs d'aperçu (le jeu pose les siennes, cf. ShopScene)
PREVIEW = {
    "Interior": (34, 26, 18),
    "BodyPlanks": (150, 104, 62),
    "LidPlanks": (150, 104, 62),
    "BodyFrame": (128, 90, 56),
    "LidFrame": (128, 90, 56),
    "BodySteel": (62, 64, 68),
    "LidSteel": (62, 64, 68),
    "Rope": (176, 156, 116),
    "LidStripe": (226, 58, 40),
}


# Cette méthode permet de rendre un aperçu Workbench 3/4 avant de la caisse lorsque le 2e argument est donné.
def preview(path):
    for ob in bpy.data.objects:
        m = bpy.data.materials.new(ob.name)
        m.diffuse_color = tuple((c / 255) ** 2.2 for c in PREVIEW[ob.name]) + (1.0,)
        ob.data.materials.append(m)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light, sh.color_type, sh.show_shadows, sh.show_cavity = "STUDIO", "MATERIAL", True, True
    sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x, sc.render.resolution_y = 900, 700
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.location = (-4.6, -6.8, 4.0)
    cam.rotation_euler = (Vector((0, 0, 0.95)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 45
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    for ob in bpy.data.objects:
        ob.data.materials.clear()


for group, objects in list(PIECES.items()):
    merged = merge(group, objects)
    print(f"{group}: {len(merged.data.polygons)} faces")
if len(ARGS) > 1:
    preview(ARGS[1])
sys.argv = [sys.argv[0], "--", ARGS[0]]
runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "export_mesh_fbx.py"))
print("FBX", ARGS[0])
