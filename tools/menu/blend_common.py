# Fonctions communes des rendus Blender du menu (blender -b --factory-startup), cf. docs/ui.md.
import bpy, json, math, os
from mathutils import Vector, Matrix
from bpy_extras.object_utils import world_to_camera_view

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BLEND = os.path.join(ROOT, "assets", "awp_viewmodel", "AWP_Viewmodel_Anims.blend")
PIECES = ["Magazine", "Trigger", "Handle", "Fittings", "Scope", "Bolt", "ScopeLens", "Handguard", "Barrel", "Stock"]
# Sortie hors dépôt par défaut (.maquettes/ n'est pas versionné) ; MENU_OUT pour la changer.
OUT = os.environ.get("MENU_OUT", os.path.join(ROOT, ".maquettes", "menu-miroirs"))
os.makedirs(OUT, exist_ok=True)


# Cette méthode permet de vider la scène de démarrage lorsque Blender est lancé en --factory-startup.
def reset():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


# Cette méthode permet d'importer les pièces de l'AWP (sans bras) lorsque la composition en a besoin ;
# les transformations sont figées, canon vers +X, haut +Z, origine au centre bas de l'arme.
def import_awp(name="AWP"):
    with bpy.data.libraries.load(BLEND, link=False) as (src, dst):
        dst.objects = [n for n in src.objects if n in PIECES or n == "Rig"]
    rig = None
    parts = {}
    for o in dst.objects:
        if o is None:
            continue
        bpy.context.scene.collection.objects.link(o)
        if o.type == "ARMATURE":
            rig = o
        elif o.type == "MESH":
            parts[o.name.split(".")[0]] = o
    bpy.context.view_layer.update()
    for o in parts.values():
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    if rig:
        bpy.data.objects.remove(rig, do_unlink=True)
    rot = Matrix.Rotation(-math.pi / 2, 4, "Z")
    for o in parts.values():
        o.matrix_world = rot @ o.matrix_world
    bpy.context.view_layer.update()
    pts = []
    for o in parts.values():
        pts += [o.matrix_world @ Vector(c) for c in o.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    off = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    for o in parts.values():
        o.matrix_world = Matrix.Translation(-off) @ o.matrix_world
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    for o in parts.values():
        o.parent = root
    bpy.context.view_layer.update()
    print("AWP bbox", tuple(round(v, 2) for v in (mx - mn)))
    return root, parts, (mx - mn)


# Export Studio du M9 (Explorer > M9Bayonet > Handle > Export Selection, non versionné).
M9_DIR = os.path.join(ROOT, ".maquettes", "m9")


# Cette méthode permet d'importer le M9 Bayonet exporté de Studio lorsque la vitrine doit le montrer : l'export est
# en coordonnées monde (couteau incliné dans la pose du viewmodel) et sa texture est réduite à 64 px, donc on le
# redresse sur ses axes principaux et on lui donne deux matières nettes (acier, manche noir) choisies face par face
# d'après la luminance de cette texture. Couteau couché le long de +X, pointe à droite, plat face à la caméra (-Y),
# longueur `length`, origine au centre bas comme l'AWP.
def import_m9(length, flip_edge=False):
    import numpy as np

    obj_path = os.path.join(M9_DIR, "m9.obj")
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=obj_path)
    o = next(x for x in set(bpy.data.objects) - before if x.type == "MESH")
    me = o.data
    me.transform(o.matrix_world)
    o.matrix_world = Matrix.Identity(4)
    # Axes principaux : le plus long = longueur (X), le moyen = largeur lame et garde (Z), le plus court = épaisseur (Y).
    co = np.array([v.co[:] for v in me.vertices])
    ctr = co.mean(0)
    _, vecs = np.linalg.eigh(np.cov((co - ctr).T))
    ax_len, ax_wid = Vector(vecs[:, 2]), Vector(vecs[:, 1])
    ax_thk = ax_len.cross(ax_wid)
    basis = Matrix((ax_len, ax_thk, ax_wid)).to_4x4()  # lignes : nouvelles coordonnées X, Y, Z
    me.transform(basis @ Matrix.Translation(-Vector(ctr)))

    # Matières d'après la texture réduite : sombre = manche, clair = acier.
    img = bpy.data.images.load(os.path.join(M9_DIR, "Handle1_diff.png"))
    w, h = img.size
    px = list(img.pixels)
    uvl = me.uv_layers.active
    steel = mat("M9_Acier", hexc("#6f757e"), rough=0.32, metal=1.0)
    grip = mat("M9_Manche", hexc("#141518"), rough=0.6, metal=0.0)
    me.materials.clear()
    me.materials.append(steel)
    me.materials.append(grip)
    for p in me.polygons:
        u = sum(uvl.data[li].uv[0] for li in p.loop_indices) / len(p.loop_indices)
        v = sum(uvl.data[li].uv[1] for li in p.loop_indices) / len(p.loop_indices)
        x, y = min(w - 1, max(0, int(u * w))), min(h - 1, max(0, int(v * h)))
        i = (y * w + x) * 4
        lum = 0.3 * px[i] + 0.59 * px[i + 1] + 0.11 * px[i + 2]
        p.material_index = 1 if lum < 0.16 else 0
        p.use_smooth = True

    # Pointe à droite : bout le plus fin en épaisseur (la lame est plate, le manche épais).
    pts = [v.co for v in me.vertices]
    xmin, xmax = min(p.x for p in pts), max(p.x for p in pts)
    span = xmax - xmin

    # Cette méthode permet de mesurer l'épaisseur (Y) des sommets situés dans une tranche de longueur.
    def thick(a, b):
        ys = [p.y for p in pts if a <= p.x <= b]
        return max(ys) - min(ys) if ys else 0

    if thick(xmax - span * 0.15, xmax) > thick(xmin, xmin + span * 0.15):
        me.transform(Matrix.Rotation(math.pi, 4, "Z"))
    # Scie sur le dos (en haut), tranchant en bas : l'export arrive dents en bas, d'où le retournement par défaut.
    if not flip_edge:
        me.transform(Matrix.Rotation(math.pi, 4, "X"))
    pts = [v.co for v in me.vertices]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    k = length / (mx.x - mn.x)
    me.transform(Matrix.Diagonal((k, k, k, 1)) @ Matrix.Translation(-Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))))
    root = bpy.data.objects.new("M9", None)
    bpy.context.scene.collection.objects.link(root)
    o.parent = root
    bpy.context.view_layer.update()
    print("M9 bbox", tuple(round(v * k, 2) for v in (mx - mn)))
    return root, {"Handle": o}, (mx - mn) * k


# Cette méthode permet de donner la position monde du centre de la boîte englobante d'une pièce.
def center(o):
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    return sum(pts, Vector()) / 8


def bounds(o):
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    return (
        Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))),
        Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))),
    )


def hexc(h):
    h = h.lstrip("#")
    srgb = [int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb)


# Cette méthode permet de créer un matériau PBR simple (équivalent Material/SurfaceAppearance Roblox).
def mat(name, color, rough=0.6, metal=0.0, emit=None, emit_strength=0.0):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = emit_strength
    return m


# Cette méthode permet d'ajouter un bloc (équivalent Part Roblox) de taille et position données.
def box(name, size, loc, material=None, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        m = o.modifiers.new("Bevel", "BEVEL")
        m.width = bevel
        m.segments = 3
    if material:
        o.data.materials.append(material)
    return o


# Cette méthode permet d'ajouter un cylindre (équivalent Part Cylinder Roblox).
def cyl(name, radius, depth, loc, material=None, rot=(0, 0, 0), verts=64):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=loc, rotation=rot, vertices=verts)
    o = bpy.context.object
    o.name = name
    if material:
        o.data.materials.append(material)
    return o


def aim(o, target):
    d = Vector(target) - o.location
    o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


# Cette méthode permet d'ajouter une lumière (point, spot, zone) orientée vers une cible.
def light(kind, loc, energy, color=(1, 1, 1), target=None, size=0.5, spot=45, blend=0.3, shadow=True):
    ld = bpy.data.lights.new(kind + "L", kind)
    ld.energy = energy
    ld.color = color
    ld.use_shadow = shadow
    if kind == "SPOT":
        ld.spot_size = math.radians(spot)
        ld.spot_blend = blend
    if kind in ("SPOT", "POINT"):
        ld.shadow_soft_size = size
    if kind == "AREA":
        ld.size = size
    o = bpy.data.objects.new(kind, ld)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    if target is not None:
        aim(o, target)
    return o


# Cette méthode permet de poser la caméra au cadrage final (16:9, focale, profondeur de champ optionnelle).
def camera(loc, target, lens=35, dof=None, fstop=2.8, shift=(0, 0)):
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lens
    cd.sensor_width = 36
    cd.shift_x, cd.shift_y = shift
    cd.clip_end = 1000
    if dof is not None:
        cd.dof.use_dof = True
        cd.dof.focus_distance = dof
        cd.dof.aperture_fstop = fstop
    c = bpy.data.objects.new("Cam", cd)
    bpy.context.scene.collection.objects.link(c)
    c.location = loc
    aim(c, target)
    bpy.context.scene.camera = c
    return c


# Cette méthode permet de régler le rendu (EEVEE, 16:9, fond uni) avant le rendu final.
def setup_render(world_color=(0, 0, 0), world_strength=1.0, res=(1920, 1080), samples=64):
    s = bpy.context.scene
    try:
        s.render.engine = "BLENDER_EEVEE"
    except TypeError as e:
        print(e)
    s.render.resolution_x, s.render.resolution_y = res
    s.render.resolution_percentage = 100
    try:
        s.eevee.taa_render_samples = samples
    except Exception:
        pass
    vt = [i.identifier for i in s.view_settings.bl_rna.properties["view_transform"].enum_items]
    s.view_settings.view_transform = "AgX" if "AgX" in vt else "Filmic"
    w = bpy.data.worlds.new("W")
    s.world = w
    try:
        w.use_nodes = True
    except Exception:
        pass
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (*world_color, 1)
    bg.inputs[1].default_value = world_strength


# Cette méthode permet de rendre l'image et d'exporter la position écran de points nommés (pour l'interface 2D).
def render(name, anchors=None):
    s = bpy.context.scene
    s.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    res = {}
    for k, p in (anchors or {}).items():
        v = world_to_camera_view(s, s.camera, Vector(p))
        res[k] = [v.x * s.render.resolution_x, (1 - v.y) * s.render.resolution_y]
    with open(os.path.join(OUT, name + ".json"), "w") as f:
        json.dump(res, f)


# Cette méthode permet de remplacer le vert du .blend par le bois de l'AWP du jeu (crosse, garde-main)
# et de régler le métal ; équivalent Roblox : Material Wood/WoodPlanks ou la texture du .rbxm existant.
def awp_materials(parts):
    wood = bpy.data.materials.new("Wood")
    try:
        wood.use_nodes = True
    except Exception:
        pass
    nt = wood.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (0.35, 9.0, 9.0)
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 3.0
    nz.inputs["Detail"].default_value = 6.0
    nz.inputs["Distortion"].default_value = 1.2
    cr = nt.nodes.new("ShaderNodeValToRGB")
    cr.color_ramp.elements[0].position = 0.35
    cr.color_ramp.elements[0].color = (*hexc("#3a1406"), 1)
    cr.color_ramp.elements[1].position = 0.7
    cr.color_ramp.elements[1].color = (*hexc("#8a3a12"), 1)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], cr.inputs["Fac"])
    nt.links.new(cr.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.42
    metal = mat("Gunmetal", hexc("#16171a"), rough=0.32, metal=0.9)
    lens = mat("Lens", hexc("#0c1420"), rough=0.05, metal=0.2)
    for n, o in parts.items():
        m = o.material_slots[0].material.name if o.material_slots and o.material_slots[0].material else ""
        o.data.materials.clear()
        o.data.materials.append(wood if m.startswith("M_Body") and n != "Fittings" else lens if n == "ScopeLens" else metal)
        for p in o.data.polygons:
            p.use_smooth = True
    return wood, metal
