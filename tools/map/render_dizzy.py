# Planche Blender d'un habillage de map (cf. docs/maps.md, « Planche Blender ») : reconstruit les pièces exportées par
# tools/map/dump_parts.luau (boîtes, coins, cylindres, boules, couleurs et matières Roblox approchées), éclaire comme le
# crépuscule du jeu (soleil rasant de build_dizzy.luau, ambiance de default.project.json, SpotLight des lampes) et rend
# une image par vue, au FOV vertical du jeu.
#   blender -b --factory-startup --python tools/map/render_dizzy.py -- <pièces.json> <vues.json> <dossier de sortie>
# Workbench par défaut (quelques secondes par vue) ; DIZZY_EEVEE=1 pour EEVEE (plusieurs minutes par vue).
# vues.json : [{ "name": "grue", "position": [x, y, z], "target": [x, y, z], "fov": 90, "res": [1613, 761] }, ...]
# (coordonnées du monde Roblox ; fov vertical en degrés, 90 par défaut comme CameraConfig.DEFAULT_FOV ; "radius" : les
# tuiles de la map à plus de radius studs de la caméra, en plan, ne sont pas rendues, 300 par défaut ; "percent").
import bpy, json, math, os, sys
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1 :]
PARTS, VIEWS, OUT = argv[0], argv[1], argv[2]
os.makedirs(OUT, exist_ok=True)

# direction vers le soleil (Roblox), SUN de build_dizzy.luau, valable pour l'heure et la latitude ci-dessous ; l'ambiance
# est lue dans default.project.json, qui doit garder cette heure (sinon relever SUN, comme pour build_dizzy.luau)
SUN = (-0.9167592525482178, 0.024006040766835213, -0.39871811866760254)
SUN_CLOCK, SUN_LATITUDE = 17.9, 0
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
_lighting = json.load(open(os.path.join(ROOT, "default.project.json"), encoding="utf-8"))["tree"]["Lighting"]["$properties"]
if _lighting["ClockTime"] != SUN_CLOCK or _lighting["GeographicLatitude"] != SUN_LATITUDE:
    raise SystemExit("Lighting de default.project.json ≠ SUN de render_dizzy.py : relever SUN (cf. build_dizzy.luau)")
AMBIENT = tuple(_lighting["OutdoorAmbient"])
CYL_SEGMENTS = 20


# Cette méthode permet de repasser un point ou un vecteur Roblox (x, y, z) en Blender (x, -z, y).
def bl(p):
    return Vector((p[0], -p[2], p[1]))


# Cette méthode permet de convertir une couleur sRGB 0-255 en couleur linéaire Blender.
def lin(c):
    out = []
    for v in c:
        v = v / 255
        out.append(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4)
    return out


# Cette méthode permet de donner les sommets locaux (unités de demi-taille) et les faces d'une forme Roblox.
def shape_geometry(shape):
    if shape in ("Block", "Part"):
        v = [(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
        f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        return v, f
    if shape == "WedgePart":
        # bas complet, dos (+Z) complet, pente du haut du dos vers le bas de l'avant (-Z)
        v = [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1), (-1, 1, 1), (1, 1, 1)]
        f = [(0, 3, 2, 1), (3, 4, 5, 2), (0, 1, 5, 4), (0, 4, 3), (1, 2, 5)]
        return v, f
    if shape == "Cylinder":
        n = CYL_SEGMENTS
        v = []
        for x in (-1, 1):
            for i in range(n):
                a = 2 * math.pi * i / n
                v.append((x, math.cos(a), math.sin(a)))
        f = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
        for i in range(n):
            j = (i + 1) % n
            f.append((i, j, n + j, n + i))
        return v, f
    if shape == "Ball":
        n, m = 16, 8
        v = [(0, -1, 0)]
        for k in range(1, m):
            t = math.pi * k / m - math.pi / 2
            for i in range(n):
                a = 2 * math.pi * i / n
                v.append((math.cos(t) * math.cos(a), math.sin(t), math.cos(t) * math.sin(a)))
        v.append((0, 1, 0))
        f = []
        for i in range(n):
            f.append((0, 1 + (i + 1) % n, 1 + i))
        for k in range(m - 2):
            for i in range(n):
                a, b = 1 + k * n + i, 1 + k * n + (i + 1) % n
                f.append((a, b, b + n, a + n))
        top = len(v) - 1
        for i in range(n):
            a, b = 1 + (m - 2) * n + i, 1 + (m - 2) * n + (i + 1) % n
            f.append((a, b, top))
        return v, f
    return None, None


GEOMS = {s: shape_geometry(s) for s in ("Block", "WedgePart", "Cylinder", "Ball")}


# Cette méthode permet de ranger une matière Roblox dans une famille de rendu (un matériau Blender par famille : un
# matériau par teinte ferait compiler des centaines de shaders).
def family(mat):
    if mat in ("Metal", "DiamondPlate", "CorrodedMetal"):
        return "metal"
    if mat in ("SmoothPlastic", "Plastic", "Glass", "Neon"):
        return mat.lower()
    return "rough"


# Cette méthode permet de créer le matériau Blender d'une famille de matières ; la teinte vient de l'attribut de
# couleur « Col » des faces.
def material(key):
    fam, transp = key
    m = bpy.data.materials.new(f"{fam}_{transp}")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    rough, metal = {"metal": (0.5, 0.55), "smoothplastic": (0.45, 0), "plastic": (0.6, 0), "glass": (0.1, 0)}.get(
        fam, (0.85, 0)
    )
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if fam == "neon":
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 6
    if transp > 0:
        bsdf.inputs["Alpha"].default_value = 1 - transp
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    return m


TILE = 100  # studs : côté des tuiles de la map (une tuile = un objet Blender, masqué loin de la vue)
MATS = {}


# Cette méthode permet de construire la map en tuiles de TILE studs (par centre de pièce) lorsque les pièces sont
# chargées : chaque vue ne rend que les tuiles proches, ce qui divise le temps de rendu (ombres du soleil surtout).
def build(parts):
    tiles = {}
    for p in parts:
        # une grande pièce (sol, mur, fût) déborde de sa tuile : toujours rendue
        key = "big" if max(p[13], p[15]) > TILE else (int(p[1] // TILE), int(p[3] // TILE))
        tiles.setdefault(key, []).append(p)
    out = []
    for key, group in tiles.items():
        if key == "big":
            out.append((build_tile(group, "Big"), None))
            continue
        i, j = key
        obj = build_tile(group, f"Tile_{i}_{j}")
        out.append((obj, Vector(((i + 0.5) * TILE, (j + 0.5) * TILE))))
    return out


# Cette méthode permet de construire un seul maillage pour un groupe de pièces (un matériau par famille de matières,
# partagé entre les tuiles).
def build_tile(parts, name):
    verts, faces, mats, cols = [], [], [], []
    keys = {}
    for p in parts:
        shape = p[0]
        geom = GEOMS.get("Block" if shape == "Block" else shape)
        if geom is None or geom[0] is None:
            continue
        gv, gf = geom
        pos = Vector(p[1:4])
        ax, ay, az = Vector(p[4:7]), Vector(p[7:10]), Vector(p[10:13])
        sx, sy, sz = p[13] / 2, p[14] / 2, p[15] / 2
        if shape == "Cylinder":
            d = min(sy, sz)
            sy = sz = d
        elif shape == "Ball":
            d = min(sx, sy, sz)
            sx = sy = sz = d
        key = (family(p[19]), round(p[20], 1))
        if key not in keys:
            keys[key] = len(keys)
        color = (*lin(p[16:19]), 1)
        base = len(verts)
        for lx, ly, lz in gv:
            w = pos + ax * (lx * sx) + ay * (ly * sy) + az * (lz * sz)
            verts.append(bl(w))
        for f in gf:
            faces.append(tuple(base + i for i in f))
            mats.append(keys[key])
            cols.extend([color] * len(f))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    for key in sorted(keys, key=lambda k: keys[k]):
        if key not in MATS:
            MATS[key] = material(key)
        mesh.materials.append(MATS[key])
    mesh.polygons.foreach_set("material_index", mats)
    col = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    col.data.foreach_set("color", [c for rgba in cols for c in rgba])
    mesh.color_attributes.active_color = col
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


# Cette méthode permet de poser le ciel (dégradé du crépuscule vu par la caméra) et l'ambiance (OutdoorAmbient) qui
# éclaire les faces à l'ombre.
def world():
    w = bpy.data.worlds.new("Crepuscule")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = next(n for n in nt.nodes if n.type == "BACKGROUND")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    nt.links.new(coord.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs[0])
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.0, (*lin((236, 150, 110)), 1)
    els[1].position, els[1].color = 0.35, (*lin((14, 22, 52)), 1)
    mid = els.new(0.08)
    mid.color = (*lin((120, 100, 140)), 1)
    path = nt.nodes.new("ShaderNodeLightPath")
    mix = nt.nodes.new("ShaderNodeMixRGB")
    mix.inputs["Color1"].default_value = (*AMBIENT, 1)
    nt.links.new(path.outputs["Is Camera Ray"], mix.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], mix.inputs["Color2"])
    nt.links.new(mix.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0


# Cette méthode permet d'ajouter le soleil rasant et les SpotLight des lampes exportées.
def lights(spots):
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 4.0
    sun.color = lin((255, 196, 150))
    sun.angle = math.radians(1.5)
    # soleil rasant : son ombre couvre toute la map ; une résolution basse évite le débordement du tampon d'ombres
    # d'EEVEE (« Shadow buffer full »), qui multipliait le temps de rendu
    try:
        sun.shadow_resolution_scale = 0.25
    except AttributeError:
        pass
    o = bpy.data.objects.new("Sun", sun)
    bpy.context.scene.collection.objects.link(o)
    d = bl(SUN).normalized()
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    for s in spots:
        l = bpy.data.lights.new("Spot", "SPOT")
        l.energy = s[8] * 900
        l.color = lin(s[9:12])
        l.spot_size = math.radians(min(s[6], 170))
        l.spot_blend = 0.6
        l.use_shadow = False  # comme dans le jeu (SpotLight.Shadows faux)
        l.use_custom_distance = True
        l.cutoff_distance = s[7]
        o = bpy.data.objects.new("Spot", l)
        o.location = bl(s[0:3])
        o.rotation_euler = (-bl(s[3:6])).normalized().to_track_quat("Z", "Y").to_euler()
        bpy.context.scene.collection.objects.link(o)


# Cette méthode permet de régler le moteur de rendu lorsque la scène est prête : Workbench par défaut (secondes par vue,
# ombres orientées comme le soleil du jeu), EEVEE avec DIZZY_EEVEE=1 (crépuscule, minutes par vue).
def setup():
    s = bpy.context.scene
    if not os.environ.get("DIZZY_EEVEE"):
        s.render.engine = "BLENDER_WORKBENCH"
        sh = s.display.shading
        sh.light = "STUDIO"
        sh.color_type = "VERTEX"
        sh.show_shadows = True
        sh.shadow_intensity = 0.55
        sh.show_cavity = True
        sh.cavity_type = "WORLD"
        sh.background_type = "VIEWPORT"
        sh.background_color = lin((40, 44, 72))
        # direction de l'ombre : vers le soleil, relevée un peu pour que l'ombre ne couvre pas tout
        d = bl(SUN)
        d.z = max(d.z, 0.25)
        s.display.light_direction = d.normalized()
        s.view_settings.view_transform = "Standard"
        return
    try:
        s.render.engine = "BLENDER_EEVEE"
    except TypeError as e:
        print(e)
    try:
        s.eevee.taa_render_samples = 16
        s.eevee.shadow_pool_size = "1024"
    except Exception:
        pass
    vt = [i.identifier for i in s.view_settings.bl_rna.properties["view_transform"].enum_items]
    s.view_settings.view_transform = "AgX" if "AgX" in vt else "Filmic"
    s.view_settings.exposure = 0.35


for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
data = json.load(open(PARTS, encoding="utf-8"))
tiles = build(data["parts"])
world()
lights(data.get("lights", []))
setup()
cam_data = bpy.data.cameras.new("Cam")
cam_data.sensor_fit = "VERTICAL"
cam_data.clip_start = 0.3
cam_data.clip_end = 5000
cam = bpy.data.objects.new("Cam", cam_data)
bpy.context.scene.collection.objects.link(cam)
bpy.context.scene.camera = cam
for v in json.load(open(VIEWS, encoding="utf-8")):
    s = bpy.context.scene
    s.render.resolution_x, s.render.resolution_y = v.get("res", [1613, 761])
    s.render.resolution_percentage = v.get("percent", 100)
    # tuiles à plus de `radius` studs (en plan) de la caméra : masquées
    eye = Vector((v["position"][0], v["position"][2]))
    for obj, c in tiles:
        obj.hide_render = c is not None and (c - eye).length > v.get("radius", 300) + TILE * 0.71
    cam_data.angle_y = math.radians(v.get("fov", 90))
    pos, target = bl(v["position"]), bl(v["target"])
    cam.location = pos
    cam.rotation_euler = (pos - target).normalized().to_track_quat("Z", "Y").to_euler()
    s.render.filepath = os.path.join(OUT, v["name"] + ".png")
    bpy.ops.render.render(write_still=True)
    print("vue", v["name"], "->", s.render.filepath)
