"""Écrit le code Luau qui pose un skin (ids.json de publish_skin.py) sur les viewmodels de la place ouverte dans Studio,
pour le juger en jeu avant d'écrire le vrai système de skins (#268). À exécuter en mode Edit (execute_luau du MCP) :
le client clone les viewmodels une fois par session, un changement en cours de partie ne se voit pas.

Usage : uv run tools/skins/apply_skin_lua.py <ids.json | origine>
  origine : remet les cartes d'origine (assets/sniper/texture_ids.json pour l'AWP, ids de la M9 publiée).
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AWP_IDS = json.load(open(os.path.join(ROOT, "assets", "sniper", "texture_ids.json")))
AWP_PARTS = AWP_IDS["_parts"]
M9_ORIG = {"Color": "rbxassetid://18775077937", "Rough": "rbxassetid://18775108675", "Metal": "rbxassetid://18775097265", "Normal": "rbxassetid://18775103691"}
PROPS = {"Color": "ColorMapContent", "Rough": "RoughnessMapContent", "Metal": "MetalnessMapContent", "Normal": "NormalMapContent"}


# Cette méthode permet de construire, pour un skin, la liste (viewmodel, pièce, cartes) à poser.
def entries(ids):
	out = []
	for prefix, maps in ids.get("AWP", {}).items():
		for part in AWP_PARTS.get(prefix, []):
			out.append(("AWP", part, maps))
	for prefix, maps in ids.get("M9Bayonet", {}).items():
		out.append(("M9Bayonet", prefix, maps))
	return out


if __name__ == "__main__":
	arg = sys.argv[1]
	if arg == "origine":
		awp = {k: {"Color": v["Color"], "Rough": v["Roughness"], "Metal": v.get("Metalness", ""), "Normal": v["Normal"]} for k, v in AWP_IDS.items() if k in AWP_PARTS and k != "GLASS"}
		ids = {"AWP": awp, "M9Bayonet": {"Handle": M9_ORIG}}
	else:
		ids = json.load(open(arg))
	lines = ["local VM = game:GetService(\"ReplicatedStorage\").ViewModels", "local n = 0"]
	for vm, part, maps in entries(ids):
		lines.append(f'do local sa = VM["{vm}"]["{part}"]:FindFirstChildOfClass("SurfaceAppearance")')
		for kind, prop in PROPS.items():
			uri = maps.get(kind, "")
			lines.append(f'\tsa.{prop} = Content.fromUri("{uri}")' if uri else f"\tsa.{prop} = Content.none")
		lines.append("\tn += 1 end")
	lines.append('return "pièces modifiées : " .. n')
	print("\n".join(lines))
