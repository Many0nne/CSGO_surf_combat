# /// script
# dependencies = ["numpy", "pillow", "scipy"]
# ///
"""Peint un skin dessiné de la M9 Bayonet (#420) : un module par skin dans ce dossier, avec une fonction paint(kn).

`uv run assets/m9/skins/paint.py <cuisson> <cartes_origine> <skin> <sortie> [--canvas <apercu.png>] [--flat <profil.png>]`
<cuisson> : `blender -b --factory-startup --python tools/skins/bake_maps.py -- <cuisson>/m9 --glb <m9.glb>`.
<cartes_origine> : dossier de `fetch_viewmodel.py` (m9_Handle_*.png).
Sortie : Handle_<Carte>.png (Color, Rough, Metal, Normal), la SurfaceAppearance de la M9.
--flat : couleur peinte vue de profil (face gauche), pour régler un motif sans rendu.
"""

import importlib
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402


def flat_view(kn, path):
	"""Cette méthode permet d'écrire la couleur peinte projetée sur le profil gauche (texels les plus proches devant)."""
	m = kn.m
	sel = m.cov & ~kn.right
	img = np.zeros((kn.hpx // 2 + 1, kn.w // 2 + 1, 3), np.float32)
	f = (m.pos - kn.k.c) @ kn.k.flat
	order = np.argsort(-f[sel])  # faces du fond d'abord, celles du devant (f négatif) par-dessus
	x = (kn.u[sel][order] / 2).astype(int)
	y = (kn.v[sel][order] / 2).astype(int)
	img[y, x] = np.clip(kn.color[sel][order], 0, 1)
	Image.fromarray((img * 255).astype(np.uint8)).save(path)


def main():
	"""Cette méthode permet de charger le module du skin demandé, de peindre ses cartes et d'écrire les aperçus demandés."""
	bake_dir, orig_dir, name, out_dir = sys.argv[1:5]
	kn = common.Knife(bake_dir, orig_dir)
	importlib.import_module(name).paint(kn)
	kn.save(out_dir)
	print(f"[skin] {name} -> {out_dir}")
	if "--canvas" in sys.argv:
		kn.preview(sys.argv[sys.argv.index("--canvas") + 1])
	if "--flat" in sys.argv:
		flat_view(kn, sys.argv[sys.argv.index("--flat") + 1])


main()
