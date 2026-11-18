# /// script
# requires-python = ">=3.11"
# dependencies = ["DracoPy", "numpy", "pillow"]
# ///
"""Planche de comparaison des tenues de personnage (#521) : le rig R15 du jeu habillé de chaque tenue, de face, de
trois quarts et de dos, au même cadrage, rendu par Blender sans interface (Workbench, couleur des textures : quelques
secondes ; le relief des normal maps n'y apparaît pas, la couleur peinte si).

Usage (depuis la racine du worktree) :
  uv run tools/outfits/board.py <planche.png> \
    --outfit "MERCURE=assets/outfits/mercure/maps/lisse" --outfit "CHITINE laque=assets/outfits/chitine/maps/laque" \
    [--head <coque.obj>] [--cache <dossier>]

Chaque dossier de tenue contient R15/<Groupe>_Color.png et, s'il a une coque, Head/Head_Color.png (posée sur le mesh
--head, cf. head_obj.py ; sans coque, la tête est grise). Meshs du rig : téléchargés par r15_bake (Open Cloud).
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import r15_bake  # noqa: E402

BLENDER = os.environ.get("BLENDER", r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
# Position du centre de chaque pièce, rig au repos (studs, X vers la droite du personnage, Y en haut, Z en arrière)
ARM_X = 1.5882 + 0.7941
LEG_X = 0.7941
POSITIONS = {
	"UpperTorso": (0, 0.3176, 0),
	"LowerTorso": (0, -1.2706, 0),
	"Head": (0, 1.5882 + 0.7941, 0),
}
for _side, _sx in (("Left", -1), ("Right", 1)):
	for _piece in ("UpperArm", "LowerArm", "Hand"):
		POSITIONS[_side + _piece] = (_sx * ARM_X, r15_bake.OFFSETS[_piece], 0)
	for _piece in ("UpperLeg", "LowerLeg", "Foot"):
		POSITIONS[_side + _piece] = (_sx * LEG_X, r15_bake.OFFSETS[_piece], 0)
VIEWS = [("face", 0), ("trois quarts", 40), ("dos", 180)]


# Cette méthode permet d'écrire une pièce du rig en OBJ (espace de la pièce, UV en convention Roblox) lorsque la
# planche a besoin des meshs dans Blender.
def write_part(name, cache, key, path):
	pos, nrm, uv, tris = r15_bake.load_part(name, cache, key)
	with open(path, "w", encoding="utf-8") as f:
		for p in pos:
			f.write(f"v {p[0]:.6f} {p[1]:.6f} {p[2]:.6f}\n")
		for t in uv:
			f.write(f"vt {t[0]:.6f} {t[1]:.6f}\n")
		for n in nrm:
			f.write(f"vn {n[0]:.6f} {n[1]:.6f} {n[2]:.6f}\n")
		for a, b, c in tris + 1:
			f.write(f"f {a}/{a}/{a} {b}/{b}/{b} {c}/{c}/{c}\n")


# Cette méthode permet de rendre et d'assembler la planche lorsqu'on lance le script : OBJ du rig en cache, vues
# rendues par Blender dans un dossier propre à ce lancement (plusieurs worktrees peuvent rendre en même temps).
def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("out")
	ap.add_argument("--outfit", action="append", required=True, help="NOM=dossier de la variante")
	ap.add_argument("--head", help="OBJ de la coque de tête (head_obj.py)")
	ap.add_argument("--cache", default=os.path.join(os.environ.get("TEMP", "/tmp"), "r15_meshes"))
	ap.add_argument("--size", type=int, default=520, help="hauteur d'une vue (pixels)")
	args = ap.parse_args()
	rig_dir = os.path.join(args.cache, "board_rig")
	os.makedirs(rig_dir, exist_ok=True)
	work = tempfile.mkdtemp(prefix="board_", dir=args.cache)
	rig = {}
	for name, (mesh_id, size, _) in r15_bake.PARTS.items():
		# nom du cache : mesh et taille de la pièce, un changement de PARTS refait l'OBJ
		rig[name] = os.path.join(rig_dir, f"{name}_{mesh_id}_{'x'.join(f'{c:.4f}' for c in size)}.obj")
		if not os.path.exists(rig[name]):
			write_part(name, args.cache, os.environ["ROBLOX_OPEN_CLOUD_KEY"], rig[name])
	outfits = []
	for spec in args.outfit:
		label, folder = spec.split("=", 1)
		head = os.path.join(folder, "Head", "Head_Color.png")
		outfits.append({
			"label": label,
			"maps": os.path.abspath(os.path.join(folder, "R15")),
			"head": os.path.abspath(head) if os.path.exists(head) else None,
		})
	config = {
		"rig": rig,
		"head_mesh": os.path.abspath(args.head) if args.head else None,
		"positions": POSITIONS,
		"groups": {name: g for name, (_, _, g) in r15_bake.PARTS.items()},
		"outfits": outfits,
		"views": VIEWS,
		"size": args.size,
		"out_dir": work,
	}
	cfg_path = os.path.join(work, "board.json")
	json.dump(config, open(cfg_path, "w"), indent=1)
	script = os.path.join(HERE, "board_blender.py")
	# --python-exit-code : une erreur du script Blender fait échouer le rendu (sinon Blender sort en 0)
	subprocess.run(
		[BLENDER, "-b", "--factory-startup", "--python-exit-code", "1", "--python", script, "--", cfg_path], check=True
	)
	# Assemblage : une ligne par tenue, une colonne par vue, nom de la tenue à gauche
	tiles = [[Image.open(os.path.join(work, f"view_{i}_{j}.png")) for j in range(len(VIEWS))] for i in range(len(outfits))]
	tw, th = tiles[0][0].size
	margin = 30
	sheet = Image.new("RGB", (len(VIEWS) * tw, len(outfits) * (th + margin)), (24, 24, 28))
	draw = ImageDraw.Draw(sheet)
	try:
		font = ImageFont.truetype("arial.ttf", 20)
	except OSError:
		font = ImageFont.load_default()
	for i, row in enumerate(tiles):
		y = i * (th + margin)
		draw.text((10, y + 4), outfits[i]["label"], fill=(235, 235, 235), font=font)
		for j, tile in enumerate(row):
			sheet.paste(tile, (j * tw, y + margin))
			if i == 0:
				draw.text((j * tw + tw - 130, y + 4), VIEWS[j][0], fill=(150, 150, 150), font=font)
	sheet.save(args.out)
	shutil.rmtree(work, ignore_errors=True)
	print(f"[board] {args.out}")


if __name__ == "__main__":
	main()
