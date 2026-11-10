# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Génère une page three.js autonome qui montre des variantes numérotées d'un modèle (skins, matières).

Tout est dans le fichier HTML (modèle, textures réduites), seul three.js vient d'un CDN : la page s'ouvre telle quelle
ou s'affiche dans la conversation. L'utilisateur fait tourner le modèle et répond par numéro (« la 3 avec la lame de
la 5 »). Les variantes sont décrites par des PNG, comme la SurfaceAppearance de Roblox : la version retenue se publie
sans conversion.

Usage : uv run tools/preview/make_preview.py <spec.json> <sortie.html>

Spec (chemins relatifs au fichier spec) :
{
  "title": "M9 : pistes de skin",
  "model": "m9.glb",                     # sortie d'export_glb.py ou de fetch_roblox_mesh.py, manifeste .json à côté
  "maxSize": 1024,                       # côté max des textures dans la page (les PNG d'origine ne changent pas)
  "height": 640,                         # optionnel : hauteur fixe pour l'afficher dans la conversation (sinon plein écran)
  "variants": [
    { "label": "actuel" },               # textures du manifeste
    { "label": "lame noire", "maps": { "<MATERIAU>": {
        "Color": "skins/noir_Color.png",  # PNG, ou "#rrggbb" pour une teinte unie
        "Rough": 0.35,                    # PNG (gris), ou nombre 0..1
        "Metal": 1, "Normal": "..." } } }
  ]
}
Les cartes d'une variante remplacent celles du manifeste, canal par canal ; "Normal": null retire le relief.
"""

import base64
import io
import json
import os
import sys

from PIL import Image

CHANNELS = ("Color", "Rough", "Metal", "Normal")
TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview_template.html")


# Cette méthode permet de charger le manifeste écrit à côté du .glb lorsqu'il existe, pour en tirer les textures
# actuelles de chaque matériau (chemins absolus).
def base_maps(model_path):
	manifest_path = os.path.splitext(model_path)[0] + ".json"
	if not os.path.exists(manifest_path):
		return {}
	with open(manifest_path, encoding="utf-8") as f:
		manifest = json.load(f)
	tex_dir = manifest.get("textures") or os.path.dirname(manifest_path)
	if not os.path.isabs(tex_dir):
		tex_dir = os.path.join(os.path.dirname(manifest_path), tex_dir)
	out = {}
	for name, info in manifest.get("materials", {}).items():
		out[name] = {ch: os.path.join(tex_dir, file) for ch, file in info.get("maps", {}).items()}
	return out


# Cette méthode permet d'encoder une image réduite en data URI WebP lorsqu'elle est utilisée par au moins une variante
# (une seule fois par fichier, même si plusieurs variantes la partagent).
def encode_image(path, max_size, cache):
	if path in cache:
		return cache[path]
	if not os.path.exists(path):
		raise SystemExit(f"[make_preview] texture introuvable : {path}")
	img = Image.open(path)
	img = img.convert("RGBA" if img.mode in ("RGBA", "LA", "P") else "RGB")
	if max(img.size) > max_size:
		ratio = max_size / max(img.size)
		img = img.resize((max(1, round(img.width * ratio)), max(1, round(img.height * ratio))), Image.LANCZOS)
	buf = io.BytesIO()
	img.save(buf, "WEBP", quality=92, method=4)
	cache[path] = "data:image/webp;base64," + base64.b64encode(buf.getvalue()).decode("ascii")
	return cache[path]


# Cette méthode permet de convertir une valeur de carte de la spec (chemin, teinte, nombre, null) en valeur pour la
# page : data URI pour une image, sinon la valeur telle quelle.
def resolve(value, spec_dir, max_size, cache):
	if value is None or isinstance(value, (int, float)):
		return value
	if isinstance(value, str) and value.startswith("#"):
		return value
	path = value if os.path.isabs(value) else os.path.join(spec_dir, value)
	return {"img": encode_image(os.path.normpath(path), max_size, cache)}


def main():
	if len(sys.argv) != 3:
		raise SystemExit("usage : uv run tools/preview/make_preview.py <spec.json> <sortie.html>")
	spec_path, out_path = sys.argv[1], sys.argv[2]
	spec_dir = os.path.dirname(os.path.abspath(spec_path))
	with open(spec_path, encoding="utf-8") as f:
		spec = json.load(f)
	model = spec["model"] if os.path.isabs(spec["model"]) else os.path.join(spec_dir, spec["model"])
	max_size = int(spec.get("maxSize", 1024))
	base = base_maps(model)
	cache = {}

	variants = []
	for i, v in enumerate(spec.get("variants") or [{"label": "actuel"}], start=1):
		merged = {}
		for mat in set(base) | set(v.get("maps", {})):
			chans = dict(base.get(mat, {}))
			chans.update(v.get("maps", {}).get(mat, {}))
			merged[mat] = {ch: resolve(chans[ch], spec_dir, max_size, cache) for ch in CHANNELS if ch in chans}
		variants.append({"id": str(v.get("id", i)), "label": v.get("label", ""), "maps": merged})

	with open(model, "rb") as f:
		glb = base64.b64encode(f.read()).decode("ascii")
	data = {"title": spec.get("title", "Aperçu"), "variants": variants, "glb": glb, "height": spec.get("height")}
	with open(TEMPLATE, encoding="utf-8") as f:
		html = f.read()
	html = html.replace("__TITLE__", data["title"]).replace("__DATA__", json.dumps(data, ensure_ascii=False).replace("</", "<\\/"))
	os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
	with open(out_path, "w", encoding="utf-8") as f:
		f.write(html)
	size = os.path.getsize(out_path) / 1e6
	print(f"[make_preview] {out_path} : {len(variants)} variantes, {len(cache)} textures, {size:.1f} Mo")


sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")
main()
