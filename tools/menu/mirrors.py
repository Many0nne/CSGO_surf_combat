# Menu « salle des miroirs » : éclats de verre suspendus dans une salle de béton ; chacun porte un morceau de l'image
# de l'arme (projection depuis la caméra du menu), qui se reconstitue quand les éclats reviennent face à la caméra.
# Usage : blender -b --factory-startup --python tools/menu/mirrors.py -- [--full] [--state assembled|half|scattered] [--anim]
# Sortie : $MENU_OUT (défaut .maquettes/menu-miroirs/), rendus cibles versionnés dans docs/ui/menu-miroirs/.
import sys, os, math, random, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blend_common as C
import bpy, bmesh
import numpy as np
from mathutils import Vector, Matrix, Quaternion
from bpy_extras.object_utils import world_to_camera_view

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
FULL = "--full" in argv
STATE = argv[argv.index("--state") + 1] if "--state" in argv else "assembled"
ANIM = "--anim" in argv
# Format de l'écran du rendu final (la découpe est toujours faite en 16:9) : 16:9, 16:10, 4:3, 21:9...
ASPECT = argv[argv.index("--aspect") + 1] if "--aspect" in argv else "16:9"
# Export pour Roblox (atlas, masque émissif, FBX des éclats, positions) au lieu du rendu ; découpe en pleine résolution.
EXPORT = "--export" in argv
WEAPON = argv[argv.index("--weapon") + 1] if "--weapon" in argv else "AWP"
RES = (1920, 1080) if FULL or EXPORT else (960, 540)
random.seed(7)

C.reset()
s = bpy.context.scene
C.setup_render(C.hexc("#0A0C16"), world_strength=0.4, res=RES, samples=64 if FULL else (12 if ANIM else 24))
try:
    s.eevee.use_raytracing = True
except Exception:
    pass
# Caméra du menu, 1 unité = 1 stud. FOV vertical fixe comme Camera.FieldOfView de Roblox : capteur ajusté en hauteur
# (20,25 mm = 36 mm en 16:9), d'où 2·atan(10,125/32) ≈ 35,1° avec l'objectif de 32 mm.
CAM_LOC, CAM_TGT = Vector((0, -17.0, 3.4)), Vector((0.6, 0, 4.6))
CAM_LENS, SENSOR_H = 32, 36 * 9 / 16
VFOV = math.degrees(2 * math.atan(SENSOR_H / 2 / CAM_LENS))
cam = C.camera(tuple(CAM_LOC), tuple(CAM_TGT), lens=CAM_LENS, dof=17.0, fstop=6.0)
cam.data.sensor_fit = "VERTICAL"
cam.data.sensor_height = SENSOR_H

# --- 1. Image source : l'AWP seule, éclairée en studio, sur fond transparent, depuis la caméra du menu.
root, parts, size = C.import_awp()
if WEAPON == "M9":
    # L'arme remplit la vitrine quelle qu'elle soit (décision #112) : le M9 est agrandi à une longueur proche de celle
    # de l'AWP (M9_FILL), sa lame étant plus haute que le fusil à longueur égale.
    for o in list(parts.values()) + [root]:
        bpy.data.objects.remove(o, do_unlink=True)
    M9_FILL = float(argv[argv.index("--fill") + 1]) if "--fill" in argv else 0.85
    root, parts, size = C.import_m9(size.x * M9_FILL, flip_edge="--flip-edge" in argv)
else:
    C.awp_materials(parts)
root.scale = (1.4, 1.4, 1.4)
root.location = (1.5, 0.0, 3.0)
root.rotation_euler = (0, math.radians(-4), math.radians(-14))
src_lights = [
    C.light("AREA", (0, -8, 9), 1600, color=C.hexc("#F3E9DC"), target=(1.3, 0, 4), size=8),
    C.light("AREA", (4, 6, 6), 900, color=C.hexc("#F3E9DC"), target=(1.3, 0, 4), size=6),
    C.light("AREA", (-6, -6, 3), 200, color=C.hexc("#9aa3c4"), target=(1.3, 0, 4), size=6, shadow=False),
]
s.render.film_transparent = True
src_path = os.path.join(C.OUT, "c5_source_" + WEAPON + ".png")
s.render.filepath = src_path
bpy.ops.render.render(write_still=True)
s.render.film_transparent = False
bpy.context.view_layer.update()
gun_pts = [o.matrix_world @ v.co for o in parts.values() for v in list(o.data.vertices)[::7]]
for o in list(parts.values()) + [root] + src_lights:
    bpy.data.objects.remove(o, do_unlink=True)

img = bpy.data.images.load(src_path)
W, H = img.size
px = np.empty(W * H * 4, dtype=np.float32)
img.pixels.foreach_get(px)
alpha = px.reshape(H, W, 4)[:, :, 3]


def a_at(u, v):
    x, y = min(W - 1, max(0, int(u * W))), min(H - 1, max(0, int(v * H)))
    return alpha[y, x]


# --- 2. Découpe de Voronoï de la zone de l'arme, en coordonnées caméra normalisées (u, v).
uv = [world_to_camera_view(s, cam, p) for p in gun_pts]
u0, u1 = min(p.x for p in uv), max(p.x for p in uv)
v0, v1 = min(p.y for p in uv), max(p.y for p in uv)
pad_u, pad_v = (u1 - u0) * 0.08, (v1 - v0) * 0.18
u0, u1, v0, v1 = u0 - pad_u, u1 + pad_u, v0 - pad_v, v1 + pad_v
NX, NY = 13, 5
seeds = []
for i in range(NX):
    for j in range(NY):
        seeds.append(((u0 + (i + 0.5 + random.uniform(-0.4, 0.4)) * (u1 - u0) / NX), (v0 + (j + 0.5 + random.uniform(-0.4, 0.4)) * (v1 - v0) / NY)))


# Cette méthode permet de couper un polygone par un demi-plan (algorithme de Sutherland-Hodgman).
def clip(poly, m, n):
    out = []
    for k in range(len(poly)):
        p, q = poly[k], poly[(k + 1) % len(poly)]
        dp = (p[0] - m[0]) * n[0] + (p[1] - m[1]) * n[1]
        dq = (q[0] - m[0]) * n[0] + (q[1] - m[1]) * n[1]
        if dp <= 0:
            out.append(p)
        if (dp <= 0) != (dq <= 0):
            t = dp / (dp - dq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


# Cette méthode permet de mesurer la part de la cellule occupée par l'arme (grille de points dans le polygone).
def coverage(poly):
    xs, ys = [p[0] for p in poly], [p[1] for p in poly]
    hit = tot = 0
    for i in range(14):
        for j in range(14):
            x = min(xs) + (max(xs) - min(xs)) * (i + 0.5) / 14
            y = min(ys) + (max(ys) - min(ys)) * (j + 0.5) / 14
            inside = False
            for k in range(len(poly)):
                (x1, y1), (x2, y2) = poly[k], poly[(k + 1) % len(poly)]
                if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                    inside = not inside
            if inside:
                tot += 1
                hit += a_at(x, y) > 0.3
    return hit / max(tot, 1)


cells = []
aspect = RES[0] / RES[1]
for i, si in enumerate(seeds):
    poly = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
    for j, sj in enumerate(seeds):
        if i != j and poly:
            m = ((si[0] + sj[0]) / 2, (si[1] + sj[1]) / 2)
            # Distance mesurée en pixels (aspect) pour des cellules régulières à l'écran.
            n = ((sj[0] - si[0]) * aspect * aspect, sj[1] - si[1])
            poly = clip(poly, m, n)
    if len(poly) < 3:
        continue
    cx, cy = sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly)
    poly = [(cx + (p[0] - cx) * 0.95, cy + (p[1] - cy) * 0.95) for p in poly]
    cov = coverage(poly)
    if cov > 0.01 or random.random() < 0.06:
        cells.append((poly, (cx, cy)))
print("eclats", len(cells))

# --- 3. Matériaux : face = image projetée sur verre sombre ; dos = verre fumé ; tranche = liseré irisé.
face = bpy.data.materials.new("Face")
try:
    face.use_nodes = True
except Exception:
    pass
nt = face.node_tree
bs = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
bs.inputs["Base Color"].default_value = (*C.hexc("#07080d"), 1)
bs.inputs["Roughness"].default_value = 0.06
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = img
tex.extension = "CLIP"
em = nt.nodes.new("ShaderNodeEmission")
em.inputs["Strength"].default_value = 1.15
mix = nt.nodes.new("ShaderNodeMixShader")
out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
# Teinte propre à chaque éclat (comme des verres de lots différents) : Color3 par MeshPart en Roblox.
oi = nt.nodes.new("ShaderNodeObjectInfo")
mr = nt.nodes.new("ShaderNodeMapRange")
mr.inputs["To Min"].default_value, mr.inputs["To Max"].default_value = 0.72, 1.0
tint = nt.nodes.new("ShaderNodeMix")
tint.data_type = "RGBA"
tint.blend_type = "MULTIPLY"
tint.inputs["Factor"].default_value = 1.0
nt.links.new(oi.outputs["Random"], mr.inputs["Value"])
nt.links.new(tex.outputs["Color"], tint.inputs["A"])
cool = nt.nodes.new("ShaderNodeCombineColor")
nt.links.new(mr.outputs["Result"], cool.inputs[0])
nt.links.new(mr.outputs["Result"], cool.inputs[1])
cool.inputs[2].default_value = 1.0
nt.links.new(cool.outputs[0], tint.inputs["B"])
nt.links.new(tint.outputs["Result"], em.inputs["Color"])
nt.links.new(tex.outputs["Alpha"], mix.inputs["Fac"])
tr = nt.nodes.new("ShaderNodeBsdfTransparent")
glass = nt.nodes.new("ShaderNodeMixShader")
glass.inputs["Fac"].default_value = 0.45
nt.links.new(tr.outputs[0], glass.inputs[1])
nt.links.new(bs.outputs[0], glass.inputs[2])
nt.links.new(glass.outputs[0], mix.inputs[1])
nt.links.new(em.outputs[0], mix.inputs[2])
# Reflet du verre par-dessus l'image : les éclats légèrement désaxés accrochent la lumière différemment.
gl = nt.nodes.new("ShaderNodeBsdfGlossy")
gl.inputs["Roughness"].default_value = 0.05
addm = nt.nodes.new("ShaderNodeAddShader")
nt.links.new(mix.outputs[0], addm.inputs[0])
nt.links.new(gl.outputs[0], addm.inputs[1])
gl.inputs["Color"].default_value = (0.15, 0.155, 0.17, 1)
nt.links.new(addm.outputs[0], out.inputs["Surface"])
dos = C.mat("Dos", C.hexc("#0b0d14"), rough=0.08)
dn = dos.node_tree
db = next(n for n in dn.nodes if n.type == "BSDF_PRINCIPLED")
db.inputs["Alpha"].default_value = 0.55
edge = bpy.data.materials.new("Tranche")
try:
    edge.use_nodes = True
except Exception:
    pass
et = edge.node_tree
eb = next(n for n in et.nodes if n.type == "BSDF_PRINCIPLED")
eb.inputs["Base Color"].default_value = (0.02, 0.02, 0.03, 1)
eb.inputs["Roughness"].default_value = 0.1
lw = et.nodes.new("ShaderNodeLayerWeight")
lw.inputs["Blend"].default_value = 0.5
ramp = et.nodes.new("ShaderNodeValToRGB")
els = ramp.color_ramp.elements
els[0].color = (*C.hexc("#3fd6e8"), 1)
els[1].color = (*C.hexc("#F2A900"), 1)
mid = els.new(0.55)
mid.color = (*C.hexc("#8a5bd6"), 1)
els[0].position = 0.2
et.links.new(lw.outputs["Facing"], ramp.inputs["Fac"])
et.links.new(ramp.outputs["Color"], eb.inputs["Emission Color"])
eb.inputs["Emission Strength"].default_value = 0.6
# Tranche nette (la majorité) : verre clair qui accroche la lumière, sans irisé.
nette = C.mat("TrancheNette", C.hexc("#b9bcc6"), rough=0.12, metal=0.0)

# --- 4. Éclats : chaque cellule est reprojetée sur un plan à sa propre profondeur, face à la caméra.
frame = [cam.matrix_world @ v for v in cam.data.view_frame(scene=s)]  # haut-droit, bas-droit, bas-gauche, haut-gauche


# Cette méthode permet de donner la direction du rayon caméra qui passe par le point écran (u, v).
def ray(u, v):
    tr, br, bl, tl = frame
    p = bl + (br - bl) * u + (tl - bl) * v
    return (p - cam.location).normalized()


fwd = (CAM_TGT - CAM_LOC).normalized()
D0 = (Vector((1.3, 0, 4.3)) - CAM_LOC).length
THICK = 0.05
shards = []
for poly, (cx, cy) in cells:
    d = D0 * random.uniform(0.82, 1.12)
    n = (fwd + Vector((random.uniform(-0.12, 0.12), 0, random.uniform(-0.12, 0.12)))).normalized()
    p0 = CAM_LOC + ray(cx, cy) * d
    verts = []
    for (u, v) in poly:
        r = ray(u, v)
        t = (p0 - CAM_LOC).dot(n) / r.dot(n)
        verts.append(CAM_LOC + r * t)
    me = bpy.data.meshes.new("Eclat")
    bm = bmesh.new()
    fv = [bm.verts.new(p - p0) for p in verts]
    bv = [bm.verts.new(p - p0 + n * THICK) for p in verts]
    f_front = bm.faces.new(fv)
    f_back = bm.faces.new(list(reversed(bv)))
    f_front.material_index, f_back.material_index = 0, 1
    for k in range(len(fv)):
        sf = bm.faces.new([fv[(k + 1) % len(fv)], fv[k], bv[k], bv[(k + 1) % len(fv)]])
        sf.material_index = 2
    bm.normal_update()
    uvl = bm.loops.layers.uv.new("Proj")
    for f in bm.faces:
        for loop in f.loops:
            w = loop.vert.co + p0
            c = world_to_camera_view(s, cam, w)
            loop[uvl].uv = (c.x, c.y)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("Eclat", me)
    s.collection.objects.link(o)
    o.location = p0
    for m in (face, dos, edge if random.random() < 0.25 else nette):
        me.materials.append(m)
    # Pas de chanfrein à l'export : ses faces mélangeraient dans l'atlas l'image et le nuancier de la tranche.
    if not EXPORT:
        bev = o.modifiers.new("Chanfrein", "BEVEL")
        bev.width, bev.segments = 0.014, 2
    shards.append((o, (cx, cy)))

for m in (face, dos, edge, nette):
    try:
        m.surface_render_method = "BLENDED"
    except Exception as e:
        print("blend", e)

# Éclats vides plus loin dans la salle (même matière, sans image) : la profondeur du champ d'éclats.
# Tirage à part : les vides sont communs aux armes, ils ne doivent pas dépendre de la découpe de l'arme.
rv = random.Random(11)
for k in range(26):
    cxw, cyw, czw = rv.uniform(-14, 16), rv.uniform(3, 14), rv.uniform(1.5, 10)
    r = rv.uniform(0.4, 1.1)
    pts = sorted(rv.uniform(0, 2 * math.pi) for _ in range(rv.randint(4, 6)))
    me = bpy.data.meshes.new("Vide")
    bm = bmesh.new()
    fv = [bm.verts.new((math.cos(a) * r * rv.uniform(0.6, 1.2), 0, math.sin(a) * r * rv.uniform(0.6, 1.4))) for a in pts]
    bv = [bm.verts.new(v.co + Vector((0, THICK, 0))) for v in fv]
    f1 = bm.faces.new(fv)
    f1.material_index = 1
    f2 = bm.faces.new(list(reversed(bv)))
    f2.material_index = 1
    for i in range(len(fv)):
        sf = bm.faces.new([fv[(i + 1) % len(fv)], fv[i], bv[i], bv[(i + 1) % len(fv)]])
        sf.material_index = 2
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("Vide", me)
    s.collection.objects.link(o)
    for m in (face, dos, edge if rv.random() < 0.25 else nette):
        me.materials.append(m)
    if not EXPORT:
        o.modifiers.new("Chanfrein", "BEVEL").width = 0.014
    o.location = (cxw, cyw, czw)
    o.rotation_euler = (rv.uniform(-0.3, 0.3), 0, rv.uniform(-0.9, 0.9))
    shards.append((o, None))
bpy.context.view_layer.update()

# Pivots : chaque éclat pend à son fil et tourne autour de lui (axe vertical), avec un léger balancement.
# Les fils vont du point d'attache au plafond (hors champ) et ne bougent pas.
fil = C.mat("Fil", C.hexc("#8b8f9a"), rough=0.3, metal=0.6)
rigs = []
for o, info in shards:
    top = max((o.matrix_world @ v.co for v in o.data.vertices), key=lambda p: p.z)
    piv = bpy.data.objects.new("Pivot", None)
    s.collection.objects.link(piv)
    piv.location = top
    bpy.context.view_layer.update()
    mw = o.matrix_world.copy()
    o.parent = piv
    o.matrix_world = mw
    h = 30 - top.z
    C.cyl("Fil", 0.008, h, (top.x, top.y, top.z + h / 2), fil, verts=6)
    ang = random.choice((-1, 1)) * math.radians(random.uniform(70, 280))
    tilt = math.radians(random.uniform(-8, 8))
    delay = 0.3 + (info[0] - u0) / (u1 - u0) * 2.6 if info else 0.0
    rigs.append({"piv": piv, "ang": ang, "tilt": tilt, "delay": delay, "image": info is not None, "base": piv.rotation_euler.z})


# Cette méthode permet de poser un éclat à l'instant t (s) de la reconstitution :
# il tourne lentement tant qu'il n'est pas libéré, puis revient face caméra en oscillation amortie.
def pose(r, t):
    if not r["image"]:
        r["piv"].rotation_euler = (0, 0, r["base"] + 0.14 * t)
        return
    lt = t - r["delay"]
    if lt <= 0:
        a, tl = r["ang"] + 0.15 * lt, r["tilt"]
    else:
        k = math.exp(-1.6 * lt)
        a = r["ang"] * k * math.cos(2 * math.pi * 0.32 * lt)
        tl = r["tilt"] * k * math.cos(2 * math.pi * 0.6 * lt)
    r["piv"].rotation_euler = (tl, 0, a)


if not ANIM:
    amp = {"assembled": None, "half": 0.42, "scattered": 1.0}[STATE]
    for r in rigs:
        if amp is None:
            pose(r, 99)
        elif r["image"]:
            r["piv"].rotation_euler = (r["tilt"] * amp, 0, r["ang"] * amp)
bpy.context.view_layer.update()

# --- 5. Salle de béton : sol, mur du fond, mur de droite en biais (comme la réf).
beton = bpy.data.materials.new("Beton")
try:
    beton.use_nodes = True
except Exception:
    pass
bt = beton.node_tree
bb = next(n for n in bt.nodes if n.type == "BSDF_PRINCIPLED")
nz = bt.nodes.new("ShaderNodeTexNoise")
nz.inputs["Scale"].default_value = 2.5
nz.inputs["Detail"].default_value = 8
cr = bt.nodes.new("ShaderNodeValToRGB")
cr.color_ramp.elements[0].color = (*C.hexc("#1d2027"), 1)
cr.color_ramp.elements[1].color = (*C.hexc("#3a3e47"), 1)
bt.links.new(nz.outputs["Fac"], cr.inputs["Fac"])
bt.links.new(cr.outputs["Color"], bb.inputs["Base Color"])
bb.inputs["Roughness"].default_value = 0.85
sol = C.mat("Sol", C.hexc("#121419"), rough=0.32)
room = [
    ("Sol", (80, 60, 0.2), (0, 10, -0.1), 0, sol),
    ("Fond", (80, 0.5, 30), (0, 16, 15), 0, beton),
    ("MurDroit", (0.5, 40, 30), (17, 4, 15), -12, beton),
]
# Joints de banches sur le mur du fond (lignes horizontales du béton).
joint = C.mat("JointM", C.hexc("#15171c"), rough=0.9)
room += [("Joint", (80, 0.1, 0.03), (0, 15.74, z), 0, joint) for z in (3.2, 6.4, 9.6)]
for name, size, loc, yaw, m in room:
    C.box(name, size, loc, m, rot=(0, 0, math.radians(yaw)))

# Lumière : douche froide zénithale sur les éclats, rasante sur le mur du fond, reflets chauds au sol.
lights = [
    ("Douche", (1, 2, 16), 3000, "#b9c2dd", (1, 2, 0), 10, True),
    ("Rasante", (-10, 10, 14), 2500, "#9aa3c4", (-4, 16, 4), 6, False),
    ("Sol", (1.5, -2, 1.0), 35, "#F3E9DC", (1.5, 2, 0), 6, False),
]
for name, loc, energy, color, target, size, shadow in lights:
    lo = C.light("AREA", loc, energy, color=C.hexc(color), target=target, size=size, shadow=shadow)
    if name == "Sol":
        # Sans reflet : vue dans le verre vide, cette lumière donnait deux éclats gris clair sous le chargeur.
        lo.data.specular_factor = 0.0


# Cette méthode permet de convertir un point Blender en coordonnées Roblox (x, z, -y), 1 unité = 1 stud.
def rb(p):
    return [round(p[0], 3), round(p[2], 3), round(-p[1], 3)]


# Disposition du menu pour l'intégration Roblox (#112), relative à l'origine de la scène du menu.
layout = {
    "camera": {"position": rb(CAM_LOC), "target": rb(CAM_TGT), "verticalFov": round(VFOV, 2), "aspectRef": 16 / 9},
    "room": [{"name": n, "size": [sz[0], sz[2], sz[1]], "position": rb(lc), "yaw": yw} for n, sz, lc, yw, _ in room],
    "lights": [
        {"name": n, "position": rb(lc), "target": rb(tg), "color": col, "shadow": sh} for n, lc, _, col, tg, _, sh in lights
    ],
    "pivots": [
        {"position": rb(r["piv"].location), "image": r["image"], "delay": round(r["delay"], 3)} for r in rigs
    ],
}
with open(os.path.join(C.OUT, "layout.json"), "w") as f:
    json.dump(layout, f, indent=1)
print("layout", len(layout["pivots"]), "pivots, FOV vertical", round(VFOV, 2))

if EXPORT:
    import shard_export

    shard_export.run(C.OUT, WEAPON, px.reshape(H, W, 4), shards, rigs)
    sys.exit(0)

# Rendu à un autre format d'écran : même position et orientation de caméra (la reconstitution reste alignée), largeur
# du 16:9 gardée sur les écrans plus étroits en ouvrant le FOV vertical, comme le fera le script Roblox.
aw, ah = (float(x) for x in ASPECT.split(":"))
if ASPECT != "16:9":
    s.render.resolution_x = int(round(RES[1] * aw / ah))
    if aw / ah < 16 / 9:
        cam.data.lens = CAM_LENS * (aw / ah) / (16 / 9)
    print("format", ASPECT, "FOV vertical", round(math.degrees(2 * math.atan(SENSOR_H / 2 / cam.data.lens)), 2))
if ANIM:
    FPS, DUR = 24, 7.5
    s.render.fps = FPS
    s.frame_start, s.frame_end = 1, int(FPS * DUR)
    for f in range(s.frame_start, s.frame_end + 1):
        t = (f - 1) / FPS
        for r in rigs:
            pose(r, t)
            r["piv"].keyframe_insert("rotation_euler", frame=f)
    adir = os.path.join(C.OUT, "anim")
    os.makedirs(adir, exist_ok=True)
    s.render.filepath = os.path.join(adir, "f_")
    bpy.ops.render.render(animation=True)
else:
    C.render("c5_miroirs_" + STATE + ("" if ASPECT == "16:9" else "_" + ASPECT.replace(":", "x")) + ("" if FULL else "_low"))
