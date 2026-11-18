# /// script
# requires-python = ">=3.11"
# dependencies = ["DracoPy", "numpy", "pillow"]
# ///
"""Planche de variantes d'une tenue de personnage (#521) : le rig R15 habillé de chaque variante, de face, de trois
quarts et de dos, au même cadrage, une rangée par variante (MERCURE à côté pour comparer).

Les couleurs viennent des cartes pré-éclairées de r15_bake.py (--preview : <dossier>/<Groupe>_Lit.png, relief ombré
dans la couleur), car le rendu Workbench (quelques secondes, cf. docs/assets.md) ignore les normal maps.

Usage (depuis la racine du worktree, ROBLOX_OPEN_CLOUD_KEY pour les meshs du rig) :
  uv run tools/outfits/board.py <sortie.png> --head-obj <coque.obj> --row "NOM=<dossier Lit>" [--row ...]
    [--title "Titre"]
Une rangée prend <dossier>/<Groupe>_Lit.png et <dossier>/Head_Lit.png ; sans Head_Lit.png, l'image donnée après une
virgule (« NOM=<dossier>,<image de tête> », couleur de la coque de MERCURE par exemple), sinon une tête grise.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import r15_bake  # noqa: E402

BLENDER = os.environ.get("BLENDER", r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
# Centre de chaque pièce, rig au repos (studs, repère du jeu) : hauteurs de r15_bake.OFFSETS, membres à côté du torse
ARM_X = (3.1764 + 1.5882) / 2
LEG_X = 1.5882 / 2
HEAD_Y = 0.3176 + 2.5412 / 2 + 0.85
VIEWS = {"face": 0, "trois_quarts": -35, "dos": 180}


# Cette méthode permet de donner le centre d'une pièce du rig au repos (repère du jeu) lorsqu'on monte le personnage
# de la planche.
def position(name):
	if name == "Head":
		return [0.0, HEAD_Y, 0.0]
	side = -1 if name.startswith("Left") else 1
	key = name.removeprefix("Left").removeprefix("Right")
	x = {"UpperArm": ARM_X, "LowerArm": ARM_X, "Hand": ARM_X, "UpperLeg": LEG_X, "LowerLeg": LEG_X, "Foot": LEG_X}.get(key, 0)
	return [side * x, r15_bake.OFFSETS[key], 0.0]


# Cette méthode permet d'écrire une pièce du rig en OBJ (studs, UV au format OBJ : V vers le haut) lorsque la planche
# la fait importer par Blender ; le fichier est gardé en cache.
def write_obj(name, cache, key):
	path = os.path.join(cache, "obj", name + ".obj")
	if os.path.exists(path):
		return path
	os.makedirs(os.path.dirname(path), exist_ok=True)
	pos, nrm, uv, tris = r15_bake.load_part(name, cache, key)
	with open(path, "w") as f:
		for p in pos:
			f.write(f"v {p[0]:.5f} {p[1]:.5f} {p[2]:.5f}\n")
		for t in uv:
			f.write(f"vt {t[0]:.5f} {1 - t[1]:.5f}\n")
		for n in nrm:
			f.write(f"vn {n[0]:.5f} {n[1]:.5f} {n[2]:.5f}\n")
		for a, b, c in tris + 1:
			f.write(f"f {a}/{a}/{a} {b}/{b}/{b} {c}/{c}/{c}\n")
	return path


# Cette méthode permet de donner l'image de couleur de chaque pièce pour une rangée (atlas de son groupe, coque de
# tête) lorsqu'on prépare le rendu.
def row_textures(lit_dir, head_img, grey):
	tex = {name: os.path.abspath(os.path.join(lit_dir, f"{g}_Lit.png")) for name, (_, _, g) in r15_bake.PARTS.items()}
	head = os.path.join(lit_dir, "Head_Lit.png")
	tex["Head"] = os.path.abspath(head if os.path.exists(head) else head_img or grey)
	return tex


# Cette méthode permet de monter la planche (meshs du rig en OBJ, rendu Blender de chaque rangée, assemblage) lorsqu'on
# lance le script en ligne de commande.
def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("out")
	ap.add_argument("--head-obj", required=True)
	ap.add_argument("--row", action="append", required=True)
	ap.add_argument("--title", default="")
	ap.add_argument("--cache", default=os.path.join(os.environ.get("TEMP", "/tmp"), "r15_meshes"))
	args = ap.parse_args()
	key = os.environ["ROBLOX_OPEN_CLOUD_KEY"]
	work = tempfile.mkdtemp(prefix="board_")
	grey = os.path.join(work, "grey.png")
	Image.new("RGB", (8, 8), (150, 150, 150)).save(grey)
	objs = {name: write_obj(name, args.cache, key) for name in r15_bake.PARTS}
	objs["Head"] = os.path.abspath(args.head_obj)
	rows = []
	for spec in args.row:
		name, rest = spec.split("=", 1)
		lit_dir, _, head_img = rest.partition(",")
		rows.append({"name": name, "textures": row_textures(lit_dir, head_img or None, grey)})
	res = [540, 640]
	cfg = {
		"objs": objs,
		"positions": {name: position(name) for name in objs},
		"rows": rows,
		"views": VIEWS,
		"res": res,
		"ortho": 9.4,
		"center": -0.75,
		"out": work,
	}
	cfg_path = os.path.join(work, "config.json")
	json.dump(cfg, open(cfg_path, "w"))
	script = os.path.join(HERE, "board_render.py")
	# --python-exit-code : sans lui, Blender sort en 0 même si le script de rendu lève une erreur
	run = subprocess.run(
		[BLENDER, "-b", "--factory-startup", "--python-exit-code", "1", "--python", script, "--", cfg_path],
		capture_output=True,
		text=True,
	)
	if run.returncode != 0:
		sys.stderr.write(run.stdout[-4000:] + run.stderr[-4000:])
		raise SystemExit(f"[board] rendu Blender en échec (code {run.returncode})")
	compose(args.out, rows, res, work, args.title)
	shutil.rmtree(work, ignore_errors=True)


# Cette méthode permet d'assembler les rendus en planche (une rangée par variante, une colonne par vue, fond gris
# moyen comme une scène du jeu) lorsqu'ils sont tous écrits.
def compose(out, rows, res, work, title):
	label_w, head_h = 210, 70 if title else 30
	w, h = res
	sheet = Image.new("RGB", (label_w + w * len(VIEWS), head_h + h * len(rows)), (118, 122, 128))
	draw = ImageDraw.Draw(sheet)
	try:
		font = ImageFont.truetype("arialbd.ttf", 26)
		small = ImageFont.truetype("arial.ttf", 18)
	except OSError:
		font = small = ImageFont.load_default()
	if title:
		draw.text((16, 18), title, fill=(245, 245, 245), font=font)
	for c, view in enumerate(VIEWS):
		draw.text((label_w + c * w + 12, head_h - 26), view.replace("_", " "), fill=(230, 230, 230), font=small)
	for r, row in enumerate(rows):
		y = head_h + r * h
		draw.text((16, y + h // 2 - 14), row["name"], fill=(250, 250, 250), font=font)
		for c, view in enumerate(VIEWS):
			img = Image.open(os.path.join(work, f"{row['name']}_{view}.png")).convert("RGBA")
			sheet.paste(img, (label_w + c * w, y), img)
	sheet.save(out)
	print(f"[board] -> {out} ({np.array(sheet).shape[1]} × {np.array(sheet).shape[0]})")


if __name__ == "__main__":
	main()
