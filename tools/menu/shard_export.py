# Export des éclats du menu « salle des miroirs » pour Roblox (#112), appelé par mirrors.py --export.
# Un MeshPart ne porte qu'une SurfaceAppearance : face, dos et tranche d'un éclat partagent une seule texture. L'atlas
# contient donc les morceaux d'image de l'arme (composés sur le verre sombre) et, en haut, une bande de nuancier
# (dos, tranche claire, liseré irisé). Sorties dans <OUT>/<arme>/ : atlas.png, masque.png (émissif), eclats.fbx,
# eclats.json ; et dans <OUT>/ : verre.png, vides.fbx, vides.json (éclats vides, communs aux armes).
import json, math, os, random
import bpy
import numpy as np
from mathutils import Matrix

ATLAS = 1024
BAND = 32  # hauteur de la bande de nuancier, en haut de l'atlas
PAD = 3  # marge en pixels source autour de chaque morceau (filtrage)
GLASS_ALPHA = 0.55
SWATCH_W = 320  # largeur utile de la bande : dos 0-31, tranche claire 32-63, irisé 64-319


# Cette méthode permet de convertir une couleur hexadécimale en composantes sRGB 0-1 (valeurs stockées dans le PNG).
def srgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)], dtype=np.float32)


GLASS = srgb("#07080d")
BACK = srgb("#0b0d14")
NETTE = srgb("#b9bcc6")
IRIS = [srgb("#3fd6e8"), srgb("#8a5bd6"), srgb("#F2A900")]


# Cette méthode permet de peindre la bande de nuancier dans une image (H, L, 4) dont la bande occupe les BAND lignes
# du haut (convention Blender : ligne 0 en bas).
def paint_band(img):
    h = img.shape[0]
    band = img[h - BAND : h]
    band[:, 0:32] = [*BACK, GLASS_ALPHA]
    band[:, 32:64] = [*NETTE, 1.0]
    for x in range(64, SWATCH_W):
        t = (x - 64) / (SWATCH_W - 65)
        a, b, k = (IRIS[0], IRIS[1], t / 0.5) if t < 0.5 else (IRIS[1], IRIS[2], (t - 0.5) / 0.5)
        band[:, x] = [*(a + (b - a) * k), 1.0]


# Cette méthode permet de donner les UV d'un point du nuancier (x en pixels de la bande) pour une texture de taille
# (w, h) dont la bande occupe le haut.
def band_uv(x, w, h):
    return (x / w, (h - BAND / 2) / h)


# Cette méthode permet de rééchantillonner une image (H, L, 4) à une nouvelle taille (bilinéaire, bords répétés).
def resize(img, nw, nh):
    h, w = img.shape[:2]
    xs = (np.arange(nw) + 0.5) * w / nw - 0.5
    ys = (np.arange(nh) + 0.5) * h / nh - 0.5
    x0 = np.clip(np.floor(xs).astype(int), 0, w - 1)
    y0 = np.clip(np.floor(ys).astype(int), 0, h - 1)
    x1, y1 = np.clip(x0 + 1, 0, w - 1), np.clip(y0 + 1, 0, h - 1)
    fx = np.clip(xs - x0, 0, 1)[None, :, None]
    fy = np.clip(ys - y0, 0, 1)[:, None, None]
    top = img[y0][:, x0] * (1 - fx) + img[y0][:, x1] * fx
    bot = img[y1][:, x0] * (1 - fx) + img[y1][:, x1] * fx
    return top * (1 - fy) + bot * fy


# Cette méthode permet de ranger des rectangles (l, h) en étagères dans une zone (W, H) ; renvoie les positions ou
# None si tout ne tient pas.
def shelf_pack(sizes, W, H):
    order = sorted(range(len(sizes)), key=lambda i: -sizes[i][1])
    pos = [None] * len(sizes)
    x = y = shelf = 0
    for i in order:
        w, h = sizes[i]
        if x + w > W:
            x, y, shelf = 0, y + shelf, 0
        if y + h > H or w > W:
            return None
        pos[i] = (x, y)
        x += w
        shelf = max(shelf, h)
    return pos


# Cette méthode permet d'enregistrer un tableau (H, L, 4) en PNG par Blender (valeurs écrites telles quelles).
def save_png(arr, path, name):
    h, w = arr.shape[:2]
    im = bpy.data.images.new(name, w, h, alpha=True)
    im.pixels.foreach_set(np.ascontiguousarray(arr, dtype=np.float32).ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)


# Cette méthode permet de passer un point Blender en coordonnées Roblox (x, z, -y), 1 unité = 1 stud.
def rb(p):
    return [round(p[0], 4), round(p[2], 4), round(-p[1], 4)]


# Cette méthode permet de donner le centre de la boîte englobante (monde) d'un objet maillé : c'est la position
# du MeshPart que Roblox crée à l'import.
def bbox_center(o):
    pts = [o.matrix_world @ v.co for v in o.data.vertices]
    return [(min(p[i] for p in pts) + max(p[i] for p in pts)) / 2 for i in range(3)]


# Cette méthode permet de réécrire les UV d'un éclat vers l'atlas : face = morceau d'image, dos et tranche = nuancier.
# `face_uv` convertit une UV écran (projection caméra) en UV atlas ; None pour un éclat vide (face = dos).
def remap_uvs(o, face_uv, tex_w, tex_h):
    me = o.data
    uvl = me.uv_layers.active or me.uv_layers.new(name="Proj")
    irise = len(me.materials) > 2 and me.materials[2].name == "Tranche"
    sides = max(len(me.polygons) - 2, 1)
    for poly in me.polygons:
        slot = poly.material_index
        for k, li in enumerate(poly.loop_indices):
            if slot == 0 and face_uv:
                uvl.data[li].uv = face_uv(uvl.data[li].uv)
            elif slot == 2 and irise:
                # Liseré irisé : la face de tranche parcourt le dégradé selon sa position sur le pourtour.
                t = (poly.index - 2 + (k in (0, 3))) / sides
                uvl.data[li].uv = band_uv(64 + t * (SWATCH_W - 66), tex_w, tex_h)
            elif slot == 2:
                uvl.data[li].uv = band_uv(48, tex_w, tex_h)
            else:
                uvl.data[li].uv = band_uv(16, tex_w, tex_h)
    return irise


# Cette méthode permet de figer la position monde d'un objet dans son maillage (objet à l'identité, sans parent) :
# le MeshPart importé est alors placé au centre de sa boîte, sans rotation, quelle que soit la lecture du FBX.
def bake_world(o):
    mw = o.matrix_world.copy()
    o.parent = None
    o.data.transform(mw)
    o.matrix_world = Matrix.Identity(4)


# Cette méthode permet d'exporter des objets en FBX avec la correction d'axes du dépôt (cf. tools/export_mesh_fbx.py :
# l'importeur Roblox donne (-x, z, y), compensé par 180° autour de Z), noms d'objets conservés.
def export_fbx(objs, path):
    for o in bpy.context.scene.objects:
        o.select_set(o in objs)
    turn = Matrix.Rotation(math.pi, 4, "Z")
    saved = [o.matrix_world.copy() for o in objs]
    try:
        for o in objs:
            o.matrix_world = turn @ o.matrix_world
        bpy.context.view_layer.update()
        bpy.ops.export_scene.fbx(
            filepath=path, use_selection=True, object_types={"MESH"}, apply_scale_options="FBX_SCALE_ALL",
            use_mesh_modifiers=False, mesh_smooth_type="FACE",
        )
    finally:
        for o, m in zip(objs, saved):
            o.matrix_world = m


# Cette méthode permet de tout exporter pour une arme : atlas et masque depuis l'image source, UV des éclats, FBX et
# positions (centre du MeshPart, point d'attache du fil, retard de la vague, teinte, liseré).
def run(out_dir, weapon, src_px, shards, rigs):
    H, W = src_px.shape[:2]
    wdir = os.path.join(out_dir, weapon)
    os.makedirs(wdir, exist_ok=True)
    image = [(o, info, r) for (o, info), r in zip(shards, rigs) if info is not None]
    vides = [(o, r) for (o, info), r in zip(shards, rigs) if info is None]

    # 1. Rectangle source de chaque éclat (pixels, ligne 0 en bas), d'après les UV écran de sa face.
    rects = []
    for o, _, _ in image:
        uvl = o.data.uv_layers.active
        us = [uvl.data[li].uv for p in o.data.polygons if p.material_index == 0 for li in p.loop_indices]
        x0 = max(0, int(math.floor(min(u[0] for u in us) * W)) - PAD)
        x1 = min(W, int(math.ceil(max(u[0] for u in us) * W)) + PAD)
        y0 = max(0, int(math.floor(min(u[1] for u in us) * H)) - PAD)
        y1 = min(H, int(math.ceil(max(u[1] for u in us) * H)) + PAD)
        rects.append((x0, y0, x1, y1))

    # 2. Plus grande échelle (pleine résolution au mieux) à laquelle tous les morceaux tiennent sous la bande.
    scale = 1.0
    while True:
        sizes = [(max(2, math.ceil((x1 - x0) * scale)), max(2, math.ceil((y1 - y0) * scale))) for x0, y0, x1, y1 in rects]
        pos = shelf_pack(sizes, ATLAS, ATLAS - BAND - 2)
        if pos:
            break
        scale *= 0.97
    print("atlas", weapon, "echelle", round(scale, 3), "morceaux", len(rects))

    # 3. Atlas : image de l'arme posée sur le verre sombre ; masque émissif = opacité de l'arme.
    atlas = np.zeros((ATLAS, ATLAS, 4), dtype=np.float32)
    atlas[:, :] = [*GLASS, GLASS_ALPHA]
    mask = np.zeros((ATLAS, ATLAS, 4), dtype=np.float32)
    mask[:, :, 3] = 1.0
    for (x0, y0, x1, y1), (sw, sh), (px, py) in zip(rects, sizes, pos):
        crop = resize(src_px[y0:y1, x0:x1], sw, sh)
        a = crop[:, :, 3:4]
        atlas[py : py + sh, px : px + sw, :3] = crop[:, :, :3] * a + GLASS * (1 - a)
        atlas[py : py + sh, px : px + sw, 3:4] = a + GLASS_ALPHA * (1 - a)
        mask[py : py + sh, px : px + sw, :3] = a
    paint_band(atlas)
    save_png(atlas, os.path.join(wdir, "atlas.png"), "Atlas")
    save_png(mask, os.path.join(wdir, "masque.png"), "Masque")

    # 4. UV vers l'atlas, noms, puis FBX et positions des éclats porteurs d'image.
    tint_rng = random.Random(23)
    entries = []
    objs = []
    for i, ((o, info, r), (x0, y0, x1, y1), (sw, sh), (px, py)) in enumerate(zip(image, rects, sizes, pos)):
        sx, sy = sw / (x1 - x0), sh / (y1 - y0)

        def face_uv(uv, x0=x0, y0=y0, px=px, py=py, sx=sx, sy=sy):
            return ((px + (uv[0] * W - x0) * sx) / ATLAS, (py + (uv[1] * H - y0) * sy) / ATLAS)

        irise = remap_uvs(o, face_uv, ATLAS, ATLAS)
        o.name = o.data.name = "Eclat_%02d" % (i + 1)
        bake_world(o)
        objs.append(o)
        entries.append({
            "name": o.name, "center": rb(bbox_center(o)), "pivot": rb(r["piv"].location), "delay": round(r["delay"], 3),
            "screen": [round(info[0], 4), round(info[1], 4)], "irise": irise,
            "tint": round(tint_rng.uniform(0.72, 1.0), 3),
        })
    export_fbx(objs, os.path.join(wdir, "eclats.fbx"))
    with open(os.path.join(wdir, "eclats.json"), "w") as f:
        json.dump({"weapon": weapon, "atlasScale": round(scale, 3), "shards": entries}, f, indent=1)

    # 5. Éclats vides (communs aux armes) : petite texture de verre (la bande seule), FBX et positions.
    verre = np.zeros((BAND, SWATCH_W, 4), dtype=np.float32)
    paint_band(verre)
    save_png(verre, os.path.join(out_dir, "verre.png"), "Verre")
    vent, vobjs = [], []
    tint_rng = random.Random(29)  # tirage propre aux vides : identiques quelle que soit l'arme exportée
    for i, (o, r) in enumerate(vides):
        irise = remap_uvs(o, None, SWATCH_W, BAND)
        o.name = o.data.name = "Vide_%02d" % (i + 1)
        bake_world(o)
        vobjs.append(o)
        vent.append({"name": o.name, "center": rb(bbox_center(o)), "pivot": rb(r["piv"].location), "irise": irise,
                     "tint": round(tint_rng.uniform(0.72, 1.0), 3)})
    export_fbx(vobjs, os.path.join(out_dir, "vides.fbx"))
    with open(os.path.join(out_dir, "vides.json"), "w") as f:
        json.dump({"shards": vent}, f, indent=1)
    print("export", weapon, len(entries), "eclats,", len(vent), "vides ->", wdir)
