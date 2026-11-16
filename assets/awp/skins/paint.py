# /// script
# dependencies = ["numpy", "pillow", "scipy"]
# ///
"""Peint un skin dessiné de l'AWP (#417) : un module par skin dans ce dossier, avec une fonction paint(maps, cv).

`uv run assets/awp/skins/paint.py <cuisson> <skin> <sortie> [--canvas <apercu.png>]`
<cuisson> : `blender -b assets/awp/AWP.blend --factory-startup --python tools/skins/bake_maps.py -- <cuisson>`.
Sortie : <PREFIXE>_<Carte>.png pour WOOD, METAL_A, METAL_B, SCOPE (même format qu'assets/awp/textures).
"""

import importlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402


def main():
	"""Cette méthode permet de charger le module du skin demandé, de peindre ses cartes et d'écrire l'aperçu de sa toile."""
	bake_dir, name, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
	mod = importlib.import_module(name)
	cv = common.Canvas()
	common.build(bake_dir, out_dir, lambda maps: mod.paint(maps, cv))
	if "--canvas" in sys.argv:
		cv.preview(sys.argv[sys.argv.index("--canvas") + 1])


main()
