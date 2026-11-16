# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Génère l'éclat du hitmarker (#467) : un fragment effilé, pointe à gauche (vers le centre de l'écran en jeu), base
cassée à droite. Quatre copies tournées sur les diagonales forment le marqueur.

Blanc sur fond transparent, teinté en jeu par ImageColor3 (os, rouge d'impact sur un tir à la tête).
Dessiné 4 fois plus grand puis réduit, pour des bords lissés.
Usage : uv run tools/ui/make_hit_shard.py <fichier .png de sortie>
Puis publier avec tools/publish_asset.sh (type Decal), voir docs/ui.md.
"""
import sys

from PIL import Image, ImageDraw

WIDTH, HEIGHT = 128, 48
SS = 4  # suréchantillonnage

# Contour de l'éclat (coordonnées de l'image 0..128 x 0..48), dans le sens horaire depuis la pointe : bord haut presque
# droit, bord bas qui s'évase plus vite, base cassée en trois pans. Asymétrique, pour lire un fragment et pas une flèche.
OUTLINE = (
    (3, 25),  # pointe
    (70, 12),
    (112, 6),
    (124, 10),  # base cassée
    (118, 22),
    (125, 33),
    (102, 41),
    (60, 36),
)


# Cette méthode permet d'écrire l'image de l'éclat lorsque le script est lancé.
def main(out: str) -> None:
    img = Image.new("RGBA", (WIDTH * SS, HEIGHT * SS), (255, 255, 255, 0))
    ImageDraw.Draw(img).polygon([(x * SS, y * SS) for x, y in OUTLINE], fill=(255, 255, 255, 255))
    img.resize((WIDTH, HEIGHT), Image.LANCZOS).save(out)


if __name__ == "__main__":
    if len(sys.argv) != 2 or not sys.argv[1].lower().endswith(".png"):
        sys.exit("usage : uv run tools/ui/make_hit_shard.py <fichier .png de sortie>")
    main(sys.argv[1])
