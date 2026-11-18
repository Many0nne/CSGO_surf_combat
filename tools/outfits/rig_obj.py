# /// script
# requires-python = ">=3.11"
# dependencies = ["DracoPy", "numpy", "pillow"]
# ///
"""Écrit les meshs du rig R15 en blocs (#521) en OBJ, une pièce par fichier, pour les aperçus Blender des tenues :
positions dans l'espace de la pièce (origine au centre, à la taille du rig) converties dans le repère Blender du dépôt
(Roblox (x, y, z) -> Blender (x, -z, y) : l'avant du personnage est +Y, le haut +Z), UV de l'atlas de r15_bake
(v retourné : l'origine des UV de Blender est en bas).

Usage (depuis la racine du worktree, clé ROBLOX_OPEN_CLOUD_KEY) :
  uv run tools/outfits/rig_obj.py <dossier> [--cache <dossier>]
"""

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r15_bake  # noqa: E402


# Cette méthode permet d'écrire une pièce du rig en OBJ (repère Blender, UV de l'atlas) lorsqu'on prépare un aperçu.
def write_part(name, out, cache, key):
	pos, _, uv, tris = r15_bake.load_part(name, cache, key)
	with open(os.path.join(out, name + ".obj"), "w", encoding="utf-8") as f:
		for x, y, z in pos:
			f.write(f"v {x:.5f} {-z:.5f} {y:.5f}\n")
		for u, v in uv:
			f.write(f"vt {u:.6f} {1 - v:.6f}\n")
		for a, b, c in tris + 1:
			f.write(f"f {a}/{a} {b}/{b} {c}/{c}\n")


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("out")
	ap.add_argument("--cache", default=os.path.join(os.environ.get("TEMP", "/tmp"), "r15_meshes"))
	args = ap.parse_args()
	os.makedirs(args.out, exist_ok=True)
	key = os.environ["ROBLOX_OPEN_CLOUD_KEY"]
	for name in r15_bake.PARTS:
		write_part(name, args.out, args.cache, key)
	print(f"{len(r15_bake.PARTS)} pièces -> {args.out}")


if __name__ == "__main__":
	np.seterr(all="ignore")
	main()
