# /// script
# requires-python = ">=3.10"
# dependencies = ["resvg-py"]
# ///
"""Génère les taches de sang posées derrière le crâne de la série de kills (5, 10 et 15 kills), depuis les SVG fournis
par l'utilisateur (assets/ui/hud/sang_serie_<1|2|3>.svg : dégradés et filtres, d'où resvg plutôt que PIL).

Images en couleur, affichées telles quelles en jeu (ImageColor3 blanc). 256 px pour un affichage à 64 px.
Usage : uv run tools/ui/make_blood_splats.py <dossier de sortie>
Puis publier chaque image avec tools/publish_asset.sh (type Decal), voir docs/ui.md.
"""
import sys
from pathlib import Path

import resvg_py

HUD = Path(__file__).resolve().parents[2] / "assets" / "ui" / "hud"
SIZE = 256
TIERS = (1, 2, 3)


# Cette méthode permet d'écrire les trois taches de sang en PNG lorsque le script est lancé.
def main(out_dir: str) -> None:
    for tier in TIERS:
        data = resvg_py.svg_to_bytes(svg_path=str(HUD / f"sang_serie_{tier}.svg"), width=SIZE, height=SIZE)
        (Path(out_dir) / f"sang_serie_{tier}.png").write_bytes(bytes(data))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage : uv run tools/ui/make_blood_splats.py <dossier de sortie>")
    main(sys.argv[1])
