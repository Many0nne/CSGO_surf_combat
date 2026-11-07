# Contrôle de l'export des éclats (#112) : réimporte eclats.fbx et vides.fbx avec leurs textures, sans éclairage
# (couleur de l'atlas telle quelle), et rend depuis la caméra du menu. L'arme doit se reconstituer à l'identique.
# Usage : blender -b --factory-startup --python tools/menu/check_export.py -- <arme>   (sortie : <OUT>/<arme>/controle.png)
import sys, os, math, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blend_common as C
import bpy
from mathutils import Matrix

weapon = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "AWP"
C.reset()
s = bpy.context.scene
C.setup_render(C.hexc("#2a2d36"), world_strength=1.0, res=(1920, 1080), samples=8)
s.view_settings.view_transform = "Standard"
lay = json.load(open(os.path.join(C.OUT, "layout.json")))


# Cette méthode permet de repasser un point Roblox (x, y, z) en Blender (x, -z, y).
def bl(p):
    return (p[0], -p[2], p[1])


cam = C.camera(bl(lay["camera"]["position"]), bl(lay["camera"]["target"]), lens=32)
cam.data.sensor_fit = "VERTICAL"
cam.data.sensor_height = 36 * 9 / 16


# Cette méthode permet de créer un matériau non éclairé qui affiche une texture avec sa transparence.
def unlit(name, path):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.remove(next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"))
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(path)
    tex.interpolation = "Closest"
    em = nt.nodes.new("ShaderNodeEmission")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    nt.links.new(tex.outputs["Color"], em.inputs["Color"])
    nt.links.new(tex.outputs["Alpha"], mix.inputs["Fac"])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    try:
        m.surface_render_method = "BLENDED"
    except Exception:
        pass
    return m


# L'export a tourné la scène de 180° autour de Z pour l'importeur Roblox : on annule ce demi-tour ici.
back = Matrix.Rotation(math.pi, 4, "Z")
for fbx, tex in ((os.path.join(C.OUT, weapon, "eclats.fbx"), os.path.join(C.OUT, weapon, "atlas.png")),
                 (os.path.join(C.OUT, "vides.fbx"), os.path.join(C.OUT, "verre.png"))):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=fbx)
    m = unlit(os.path.basename(tex), tex)
    for o in set(bpy.data.objects) - before:
        if o.type == "MESH":
            o.matrix_world = back @ o.matrix_world
            o.data.materials.clear()
            o.data.materials.append(m)
s.render.filepath = os.path.join(C.OUT, weapon, "controle.png")
bpy.ops.render.render(write_still=True)
