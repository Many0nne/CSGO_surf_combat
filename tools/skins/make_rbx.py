"""Écrit les SurfaceAppearance d'un skin pour Rojo (#268), à partir de son ids.json (publish_skin.py).

Un fichier par arme et par skin : assets/rbx/Skins/<Viewmodel>/<skin>.model.json, un Folder qui contient une
SurfaceAppearance par pièce du viewmodel, nommée comme la pièce (Rojo : ReplicatedStorage.Skins.<Viewmodel>.<skin>).
Le jeu clone ces SurfaceAppearance sur les pièces de l'arme (WeaponSkins) : un script de jeu ne peut pas écrire les
cartes d'une SurfaceAppearance, il ne peut que les copier.

Usage (depuis la racine du worktree) : uv run tools/skins/make_rbx.py assets/skins/<skin>
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# Pièces de chaque matériau de l'AWP (même table que les cartes d'origine) ; la M9 n'a qu'une pièce, Handle
AWP_PARTS = json.load(open(os.path.join(ROOT, "assets", "sniper", "texture_ids.json")))["_parts"]
PROPS = {"Color": "ColorMapContent", "Rough": "RoughnessMapContent", "Metal": "MetalnessMapContent", "Normal": "NormalMapContent"}


# Cette méthode permet de lister les pièces d'un viewmodel qui portent les cartes d'un préfixe de texture.
def parts_of(viewmodel, prefix):
	return AWP_PARTS.get(prefix, []) if viewmodel == "AWP" else [prefix]


if __name__ == "__main__":
	skin_dir = sys.argv[1].rstrip("/\\")
	skin = os.path.basename(skin_dir)
	ids = json.load(open(os.path.join(skin_dir, "ids.json")))
	for viewmodel, prefixes in ids.items():
		children = []
		for prefix, maps in sorted(prefixes.items()):
			props = {PROPS[k]: v for k, v in maps.items() if k in PROPS}
			missing = set(PROPS) - set(maps)
			if missing:
				raise SystemExit(f"[make_rbx] {skin} {viewmodel} {prefix} : cartes manquantes {sorted(missing)}")
			for part in parts_of(viewmodel, prefix):
				children.append({"name": part, "className": "SurfaceAppearance", "properties": props})
		children.sort(key=lambda c: c["name"])
		out_dir = os.path.join(ROOT, "assets", "rbx", "Skins", viewmodel)
		os.makedirs(out_dir, exist_ok=True)
		out = os.path.join(out_dir, f"{skin}.model.json")
		with open(out, "w", newline="\n") as f:
			json.dump({"className": "Folder", "children": children}, f, indent=2)
			f.write("\n")
		print(f"[make_rbx] {out} : {len(children)} pièces")
