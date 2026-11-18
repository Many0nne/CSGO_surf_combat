# /// script
# requires-python = ">=3.11"
# dependencies = ["DracoPy", "numpy", "pillow"]
# ///
"""Exporte les 14 pièces du rig R15 en blocs du jeu (StarterCharacter) en OBJ, pour la planche du portant des tenues
(#543, tools/shop/outfit_rack_board.py) : positions en studs dans l'espace de la pièce (Roblox : X droite du personnage,
Y haut, Z arrière ; l'avant est -Z), UV prêtes pour Blender (V retourné : les atlas de r15_bake ont l'origine en haut).
Écrit aussi rig.json : centre de chaque pièce dans le rig au repos (racine à l'origine) et son groupe d'atlas.

Meshs : ceux de r15_bake (cache Open Cloud, clé ROBLOX_OPEN_CLOUD_KEY seulement s'ils n'y sont pas).
Usage (depuis la racine du worktree) : uv run tools/shop/outfit_rig_obj.py <dossier> [--cache <dossier>]
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "outfits"))
import r15_bake as rb  # noqa: E402

# Écart latéral des membres (studs) : bras collés au torse (demi-torse + demi-bras), jambes sous chaque hanche
ARM_X = 3.1764 / 2 + 1.5882 / 2
LEG_X = 1.5882 / 2


# Cette méthode permet de donner le centre d'une pièce dans le rig au repos lorsque la planche assemble un personnage :
# hauteur lue dans r15_bake.OFFSETS, côté selon le nom (droite du personnage = +X).
def rest_center(name):
	for key, height in rb.OFFSETS.items():
		if name.endswith(key):
			side = 1 if name.startswith("Right") else -1 if name.startswith("Left") else 0
			lateral = ARM_X if ("Arm" in key or key == "Hand") else LEG_X if key in ("UpperLeg", "LowerLeg", "Foot") else 0
			return [side * lateral, height, 0.0]
	raise SystemExit(f"pièce sans hauteur : {name}")


# Cette méthode permet d'écrire une pièce en OBJ (positions, normales, UV retournées, triangles) lorsqu'on l'exporte.
def write_obj(path, pos, nrm, uv, tris):
	with open(path, "w", encoding="utf-8") as f:
		for p in pos:
			f.write(f"v {p[0]:.5f} {p[1]:.5f} {p[2]:.5f}\n")
		for n in nrm:
			f.write(f"vn {n[0]:.5f} {n[1]:.5f} {n[2]:.5f}\n")
		for t in uv:
			f.write(f"vt {t[0]:.6f} {1 - t[1]:.6f}\n")
		for a, b, c in tris:
			a, b, c = a + 1, b + 1, c + 1
			f.write(f"f {a}/{a}/{a} {b}/{b}/{b} {c}/{c}/{c}\n")


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("out")
	ap.add_argument("--cache", default=os.path.join(os.environ.get("TEMP", "/tmp"), "r15_meshes"))
	args = ap.parse_args()
	os.makedirs(args.out, exist_ok=True)
	key = os.environ.get("ROBLOX_OPEN_CLOUD_KEY", "")
	rig = {}
	for name, (_, size, group) in rb.PARTS.items():
		pos, nrm, uv, tris = rb.load_part(name, args.cache, key)
		write_obj(os.path.join(args.out, name + ".obj"), pos, nrm, uv, tris)
		rig[name] = {"center": rest_center(name), "size": list(size), "group": group}
	with open(os.path.join(args.out, "rig.json"), "w", encoding="utf-8") as f:
		json.dump(rig, f, indent=1)
	print(f"[outfit_rig_obj] {len(rig)} pièces dans {args.out}")


if __name__ == "__main__":
	main()
