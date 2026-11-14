# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow", "numpy"]
# ///
"""Génère les deux dégradés de la suspension du shop (ShopScene, docs/ui.md « Shop ») : blancs, teintés en jeu
(Beam.Color, ImageColor3), opacité seule dans l'alpha.

- beam_profile.png : profil en travers du cône (Beam, texture étirée) : opaque au milieu, nul sur les bords, sans arête.
  Sur un Beam, la largeur de l'image suit la largeur du ruban et sa hauteur suit la longueur (haut = Attachment0) ;
  l'image ne varie qu'en largeur, l'effacement vers le bas vient de Beam.Transparency.
- wall_wash.png : trace de la suspension sur le tableau derrière elle (ImageLabel d'un SurfaceGui). Le haut de l'image
  est à hauteur de la cloche : rien au-dessus (une cloche tournée vers le bas n'éclaire pas plus haut qu'elle), bord
  haut en arc qui descend sur les côtés, trace étroite sous la cloche qui s'ouvre vers le bas et s'efface avec la
  distance. Une tache ronde centrée sur le tableau éclairait aussi au-dessus de la lampe (rejeté).
- weapon_shadow.png : ombre douce d'une arme sur le tableau (teintée en noir), pleine sur sa longueur. Le Voxel ne
  donne pas d'ombre aux lampes : sans elle, l'arme semblait collée devant le fond éclairé.
Des calques translucides empilés (rubans, disques) laissaient des traits visibles : il faut une image de dégradé.
Usage : uv run tools/shop/make_light_textures.py <dossier de sortie>
Puis publier chaque image avec tools/publish_asset.sh (type Decal), voir docs/ui.md.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

PROFILE_SIZE = (256, 16)
WASH_SIZE = 256
# trace sur le mur, en fraction de la demi-largeur de l'image : demi-largeur sous la cloche, puis pleine largeur dès
# WASH_OPEN de la hauteur (la trace s'ouvre vite, comme un cône proche du mur) ; trop étroite, seule l'arme du milieu
# était éclairée
WASH_TOP_HALF = 0.1
WASH_OPEN = 0.3
WASH_ARC = 0.2  # creux du bord haut sur les côtés, en fraction de la hauteur
WASH_FADE = 0.65  # part de l'intensité perdue en bas de l'image
SHADOW_SIZE = (256, 64)
SHADOW_END = 0.25  # part de la demi-longueur sur laquelle l'ombre s'efface à chaque bout

# Cette méthode permet d'adoucir une rampe 0..1 (smoothstep) lorsque l'opacité est calculée, pour éviter une limite nette.
def smooth(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


# Cette méthode permet d'écrire une image blanche dont l'alpha vaut `alpha` (0..1) lorsqu'une texture est générée.
def save(alpha: np.ndarray, path: Path) -> None:
    rgba = np.zeros((*alpha.shape, 4), dtype=np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.round(np.clip(alpha, 0.0, 1.0) * 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(path)


# Cette méthode permet de calculer la trace de la suspension sur le mur lorsque wall_wash.png est générée : masque du
# cône (bords doux), bord haut en arc, effacement avec la distance à la lampe.
def wall_wash() -> np.ndarray:
    u = np.linspace(-1.0, 1.0, WASH_SIZE)[None, :]
    v = np.linspace(0.0, 1.0, WASH_SIZE)[:, None]
    half = WASH_TOP_HALF + (1.0 - WASH_TOP_HALF) * np.minimum(v / WASH_OPEN, 1.0) ** 0.7
    cone = smooth((half - np.abs(u)) / (0.4 * half))
    top = smooth((v - WASH_ARC * u * u) / 0.15)
    fade = (1.0 - WASH_FADE * v) ** 1.5
    return cone * top * fade


# Cette méthode permet de calculer l'ombre douce d'une arme sur le tableau lorsque weapon_shadow.png est générée :
# pleine sur toute la longueur, effacée aux deux bouts et en travers (bords doux, pas de contour).
def weapon_shadow() -> np.ndarray:
    width, height = SHADOW_SIZE
    x = np.abs(np.linspace(-1.0, 1.0, width))[None, :]
    y = np.abs(np.linspace(-1.0, 1.0, height))[:, None]
    return smooth((1.0 - x) / SHADOW_END) * (1.0 - y * y) ** 2


# Cette méthode permet de générer les dégradés dans `out` lorsque le script est lancé ; profil du cône
# (1 - x²)^1.5, pente nulle au bord donc pas d'arête.
def main(out: str) -> None:
    folder = Path(out)
    folder.mkdir(parents=True, exist_ok=True)
    width, height = PROFILE_SIZE
    x = np.linspace(-1.0, 1.0, width)
    profile = (1.0 - x * x) ** 1.5
    save(np.tile(profile, (height, 1)), folder / "beam_profile.png")
    save(wall_wash(), folder / "wall_wash.png")
    save(weapon_shadow(), folder / "weapon_shadow.png")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage : uv run tools/shop/make_light_textures.py <dossier de sortie>")
    main(sys.argv[1])
