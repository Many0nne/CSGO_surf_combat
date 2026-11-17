"""Publie les cartes PBR d'un skin sur Roblox et note les ids d'image à poser sur les SurfaceAppearance (#268).

Chaque PNG de <dossier du skin>/<Viewmodel>/<PREFIXE>_<Carte>.png est publié en Decal (tools/publish_asset.sh), puis
l'id de l'image contenue dans le Decal est lu par Asset Delivery (l'id du Decal lui-même ne s'affiche pas sur une
SurfaceAppearance). Résultat dans <dossier du skin>/ids.json :
  { "<Viewmodel>": { "<PREFIXE>": { "Color": "rbxassetid://…", "Rough": …, "Metal": …, "Normal": … } } }
Reprise : une carte déjà présente dans ids.json n'est pas republiée. Deux fichiers identiques (cartes uniformes d'une
tenue, #521) ne sont publiés qu'une fois par lancement.

Clé : ROBLOX_OPEN_CLOUD_KEY (scopes asset:read, asset:write et legacy-asset:manage pour Asset Delivery).
Usage (depuis la racine du worktree) : uv run tools/skins/publish_skin.py <dossier du skin> <nom du skin>
"""

import gzip
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

API = "https://apis.roblox.com/asset-delivery-api/v1/assetId/"
KINDS = ("Color", "Rough", "Metal", "Normal")


# Cette méthode permet de lire l'id de l'image contenue dans un Decal publié, en réessayant tant que Roblox ne l'a pas
# encore traité.
def image_id(decal_id, key, attempts=20):
	last = ""
	for _ in range(attempts):
		try:
			req = urllib.request.Request(API + decal_id, headers={"x-api-key": key})
			with urllib.request.urlopen(req) as r:
				location = json.load(r)["location"]
			with urllib.request.urlopen(urllib.request.Request(location, headers={"Accept-Encoding": "gzip"})) as r:
				data = r.read()
			if data[:2] == b"\x1f\x8b":
				data = gzip.decompress(data)
			m = re.search(rb"id=(\d+)", data)
			if m:
				return m.group(1).decode()
			last = data[:200].decode("utf-8", "replace")
		except Exception as e:  # noqa: BLE001 - Decal pas encore disponible : on réessaie
			last = str(e)
		time.sleep(3)
	raise RuntimeError(f"id d'image introuvable pour le Decal {decal_id} : {last}")


if __name__ == "__main__":
	skin_dir, skin = sys.argv[1], sys.argv[2]
	key = os.environ.get("ROBLOX_OPEN_CLOUD_KEY")
	if not key:
		raise SystemExit("[publish_skin] variable d'environnement ROBLOX_OPEN_CLOUD_KEY absente")
	out_path = os.path.join(skin_dir, "ids.json")
	ids = json.load(open(out_path)) if os.path.exists(out_path) else {}
	published = {}  # empreinte d'un fichier publié pendant ce lancement -> id de son image
	for vm in sorted(os.listdir(skin_dir)):
		vdir = os.path.join(skin_dir, vm)
		if not os.path.isdir(vdir):
			continue
		for name in sorted(os.listdir(vdir)):
			m = re.match(r"(.+)_(Color|Rough|Metal|Normal|Emissive)\.png$", name)
			if not m:
				continue
			prefix, kind = m.groups()
			if ids.get(vm, {}).get(prefix, {}).get(kind):
				continue
			path = os.path.join(vdir, name)
			digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
			if digest in published:
				ids.setdefault(vm, {}).setdefault(prefix, {})[kind] = published[digest]
				json.dump(ids, open(out_path, "w"), indent=1, sort_keys=True)
				print(f"[publish_skin] {skin} {vm} {prefix} {kind} : même fichier, {published[digest]}", flush=True)
				continue
			res = subprocess.run(
				["bash", "tools/publish_asset.sh", path, "Decal", f"CSGO_skin_{skin}_{vm}_{prefix}_{kind}"],
				capture_output=True,
				text=True,
			)
			if res.returncode != 0:
				raise SystemExit(f"[publish_skin] {name} : {res.stderr.strip()}")
			decal = res.stdout.strip().splitlines()[-1]
			img = image_id(decal, key)
			ids.setdefault(vm, {}).setdefault(prefix, {})[kind] = f"rbxassetid://{img}"
			published[digest] = f"rbxassetid://{img}"
			json.dump(ids, open(out_path, "w"), indent=1, sort_keys=True)  # une carte republiée garde sa place
			print(f"[publish_skin] {skin} {vm} {prefix} {kind} : Decal {decal} -> image {img}", flush=True)
	print(f"[publish_skin] {out_path}")
