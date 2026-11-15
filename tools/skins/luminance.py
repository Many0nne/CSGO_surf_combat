"""Mesure la luminance des skins (#366) : moyenne de la luminance relative (sRGB linéarisé, Rec. 709) de toutes les
cartes de couleur d'une arme (`<PREFIXE>_Color.png`), à recopier dans le champ `luminance` du skin dans
src/shared/InventoryRules.luau.

Le shop s'en sert pour placer les skins les plus sombres au centre du tableau, sous la suspension (ShopCatalog.columns).
Pour un métal, la carte de couleur est la teinte du reflet : un métal sombre ne renvoie presque rien de la pièce, et
compte donc comme sombre ; pas besoin de pondérer par la carte de métal (même classement, vérifié sur les séries 1 et 2).

Usage (depuis la racine du worktree) :
  uv run --with numpy --with pillow tools/skins/luminance.py [assets/skins]
"""

import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WEAPON_IDS = {"AWP": "awp", "M9Bayonet": "m9bayonet"}


# Cette méthode permet de calculer la luminance moyenne des cartes de couleur d'un dossier d'arme lorsqu'un skin est
# mesuré ; chaque texel compte pour un, toutes cartes confondues. None si le dossier n'a aucune carte de couleur.
def mean_luminance(folder: str) -> float | None:
    total, count = 0.0, 0
    for name in sorted(os.listdir(folder)):
        if not name.endswith("_Color.png"):
            continue
        srgb = np.asarray(Image.open(os.path.join(folder, name)).convert("RGB"), dtype=np.float64) / 255
        linear = np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4)
        luminance = linear @ np.array([0.2126, 0.7152, 0.0722])
        total += luminance.sum()
        count += luminance.size
    return total / count if count else None


# Cette méthode permet d'afficher la luminance de chaque skin (une ligne par id d'item) lorsque le script est lancé.
def main() -> None:
    skins_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets", "skins")
    for skin in sorted(os.listdir(skins_dir)):
        for viewmodel, weapon in WEAPON_IDS.items():
            folder = os.path.join(skins_dir, skin, viewmodel)
            if not os.path.isdir(folder):
                continue
            value = mean_luminance(folder)
            if value is not None:
                print(f"skin.{weapon}.{skin}  luminance = {value:.3f}")


if __name__ == "__main__":
    main()
