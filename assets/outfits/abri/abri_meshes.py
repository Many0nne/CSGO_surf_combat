"""ABRI (#521) : volumes ajoutés au rig (cagoule, masque à gaz et ses filtres, visière, sac du dos), d'après la planche
de concept validée (assets/outfits/concepts/abri.png). Une MeshPart par couleur et par pièce du rig qui la porte ;
couleur et matière posées dans Studio d'après pieces.json (pas de texture).

Usage (Blender sans interface, depuis la racine du worktree) :
  blender -b --factory-startup --python assets/outfits/abri/abri_meshes.py -- <dossier des OBJ du rig>
    [--fbx <sortie.fbx>] [--preview <dossier>]
Écrit toujours assets/outfits/abri/pieces.json. Les OBJ du rig viennent de tools/outfits/rig_obj.py ; l'aperçu pose
sur eux les cartes cuites (maps/base/R15).
"""

import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "..", "..", "tools", "outfits")))

import mesh_kit as kit  # noqa: E402

# Couleurs (sRGB 0-255, relevées sur la planche) et matières Roblox
YELLOW = (224, 168, 20)
BLACK = (32, 32, 31)
GREY = (150, 150, 146)
GLASS = (64, 78, 70)
LOOK = {
	"yellow": {"color": YELLOW, "material": "SmoothPlastic"},
	"black": {"color": BLACK, "material": "Plastic"},
	"grey": {"color": GREY, "material": "Metal"},
	"glass": {"color": GLASS, "material": "SmoothPlastic", "reflectance": 0.2},
}

# Cagoule : la tête classique (1,98 × 1,99 × 1,98) agrandie, un peu plus haute (capuche ample)
HOOD_SCALE = (1.12, 1.12, 1.14)
R = 0.99 * 1.12


# Cette méthode permet de créer un cylindre (rayon, épaisseur) centré en `at` et orienté selon `axis` lorsqu'on modèle
# un filtre du masque ou son cerclage.
def disc(name, radius, depth, at, axis, bev=0.03):
	bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=32, location=(0, 0, 0))
	ob = bpy.context.object
	ob.name = name
	ob.rotation_euler = Vector(axis).to_track_quat("Z", "Y").to_euler()
	ob.location = at
	bpy.ops.object.transform_apply(location=True, rotation=True)
	return kit.bevel(ob, bev) if bev > 0 else ob


# Cette méthode permet de créer un contour arrondi vu de face (demi-largeur, bas, haut, rayon des coins), profond vers
# l'avant, lorsqu'on découpe une coque de la tête à la forme d'une visière ou d'un masque.
def outline(half_w, z0, z1, radius, depth=2.0):
	return kit.rounded_box("outline", (-half_w, 0.0, z0), (half_w, depth, z1), radius, 6)


# Cette méthode permet de créer la cagoule, le masque (cadre, groin, filtres), le cerclage gris des filtres et la
# visière, dans l'espace de la tête.
def head():
	hood = kit.head_shell("Hood", HOOD_SCALE, lift=0.05)
	# masque : cadre de lunettes aux coins arrondis autour de la visière, et partie basse (bouche, menton)
	frame = kit.intersect(kit.arc_shell("Mask", R - 0.1, R + 0.1, 66, -0.2, 1.0), outline(0.92, -0.06, 0.9, 0.28))
	kit.cut(frame, outline(0.76, 0.06, 0.78, 0.22))
	chin = kit.intersect(kit.arc_shell("chin", R - 0.12, R + 0.07, 50, -0.9, 0.1), outline(0.56, -0.82, -0.02, 0.26))
	bpy.ops.mesh.primitive_uv_sphere_add(radius=0.3, location=(0, R + 0.1, -0.38))
	snout = bpy.context.object
	snout.scale = (1.0, 0.8, 1.0)
	bpy.ops.object.transform_apply(scale=True)
	filters, rims = [], []
	for sx in (-1, 1):
		a = math.radians(40 * sx)
		radial = Vector((math.sin(a), math.cos(a), 0))
		axis = (radial + Vector((0, 0, -0.35))).normalized()
		base = Vector((math.sin(a) * (R + 0.05), math.cos(a) * (R + 0.05), -0.36))
		filters.append(disc("filter", 0.31, 0.26, base + axis * 0.13, axis))
		rim = disc("rim", 0.335, 0.08, base + axis * 0.27, axis, 0.02)
		kit.cut(rim, disc("rim_hole", 0.24, 0.3, base + axis * 0.27, axis, 0))
		rims.append(rim)
	mask = kit.join([frame, chin, snout] + filters)
	rim = kit.join(rims)
	rim.name = "MaskRims"
	visor = kit.intersect(kit.arc_shell("Visor", R - 0.06, R + 0.05, 62, -0.1, 0.9), outline(0.8, 0.02, 0.82, 0.24))
	return [
		(hood, "Head", "yellow", True),
		(mask, "Head", "black", False),
		(rim, "Head", "grey", False),
		(visor, "Head", "glass", False),
	]


# Cette méthode permet de créer le sac plat du dos (petite bouteille d'air dans son harnais) dans l'espace de
# l'UpperTorso ; les sangles sont dessinées sur les cartes.
def pack():
	back = -kit.LIMB / 2
	ob = kit.rounded_box("Pack", (-0.85, back - 0.42, -1.12), (0.85, back + 0.02, 0.66), 0.18)
	return [(ob, "UpperTorso", "black", False)]


def main():
	# lire la ligne de commande d'abord : l'export FBX la réécrit
	rig_dir, fbx, preview = os.path.abspath(kit.args()[0]), kit.arg("--fbx"), kit.arg("--preview")
	bpy.ops.wm.read_factory_settings(use_empty=True)
	pieces = head() + pack()
	kit.report(pieces, LOOK, os.path.join(HERE, "pieces.json"))
	if fbx:
		kit.export_fbx(fbx)
	if preview:
		kit.import_rig(rig_dir, os.path.join(HERE, "maps", "base", "R15"))
		kit.render_preview(preview, "abri")


main()
