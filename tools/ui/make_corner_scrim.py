# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow", "numpy"]
# ///
"""Génère le fond sombre du compteur de vitesse : blanc, opaque dans le coin bas gauche, transparent en haut et à droite.

Roblox ne sait pas fondre un cadre dans deux directions (un UIGradient sur un CanvasGroup est ignoré), d'où cette image,
teintée en jeu par ImageColor3 et posée dans le coin bas gauche de l'écran.
Usage : uv run tools/ui/make_corner_scrim.py <fichier .png de sortie>
Puis publier avec tools/publish_asset.sh (type Decal), voir docs/ui.md.
"""
import sys

import numpy as np
from PIL import Image

WIDTH, HEIGHT = 512, 256


# Cette méthode permet d'adoucir une rampe 0..1 (smoothstep) lorsque l'opacité est calculée, pour éviter une limite nette.
def smooth(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


# Cette méthode permet d'écrire l'image du fond lorsque le script est lancé : opacité = fondu horizontal x fondu vertical.
def main(out: str) -> None:
    x = np.linspace(0.0, 1.0, WIDTH)[None, :]
    y = np.linspace(0.0, 1.0, HEIGHT)[:, None]
    alpha = smooth(1.0 - x) * smooth(y)
    rgba = np.zeros((HEIGHT, WIDTH, 4), dtype=np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.round(alpha * 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(out)


if __name__ == "__main__":
    main(sys.argv[1])
