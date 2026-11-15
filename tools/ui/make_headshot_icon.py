# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Génère l'icône du tir à la tête du HUD (#365) : une tête de profil, tournée vers la gauche (vers le tueur dans le
kill feed), percée d'un impact à la tempe, des éclats projetés à l'arrière du crâne.

Blanc sur fond transparent, teinté en jeu par ImageColor3 (ambre comme le libellé de l'arme), comme le crâne de la série.
Dessiné 4 fois plus grand puis réduit, pour des bords lissés.
Usage : uv run tools/ui/make_headshot_icon.py <fichier .png de sortie>
Puis publier avec tools/publish_asset.sh (type Decal), voir docs/ui.md.
"""
import math
import sys

from PIL import Image, ImageDraw

SIZE = 128
SS = 4  # suréchantillonnage

# Impact : centre, rayon du trou, rayon atteint par les fissures (coordonnées de l'icône 0..128)
HOLE = (62, 46)
HOLE_RADIUS = 12
CRACK_REACH = 26


# Cette méthode permet de passer des coordonnées de l'icône (0..128) à celles du dessin suréchantillonné lorsque une
# forme est tracée.
def s(*values: float) -> list[float]:
    return [v * SS for v in values]


# Cette méthode permet de tracer un éclat (triangle effilé dans l'axe du tir) lorsque l'arrière du crâne est dessiné :
# base centrée en (x, y), pointe dans la direction angle (degrés), longueur et demi-largeur données.
def shard(d: ImageDraw.ImageDraw, x: float, y: float, angle: float, length: float, half: float, fill) -> None:
    a = math.radians(angle)
    ux, uy = math.cos(a), math.sin(a)
    px, py = -uy, ux
    d.polygon(s(x + px * half, y + py * half, x + ux * length, y + uy * length, x - px * half, y - py * half), fill=fill)


# Cette méthode permet d'écrire l'icône lorsque le script est lancé : silhouette pleine (crâne, visage, cou), puis trou
# et fissures effacés (alpha 0), puis éclats pleins sortant à l'arrière, dans l'axe du tir.
def main(out: str) -> None:
    big = SIZE * SS
    img = Image.new("RGBA", (big, big), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    white = (255, 255, 255, 255)
    clear = (255, 255, 255, 0)

    # Crâne
    d.ellipse(s(30, 10, 102, 82), fill=white)
    # Visage tourné vers la gauche : front, arcade, nez, lèvres, menton, puis mâchoire vers la nuque
    d.polygon(
        s(40, 24, 31, 46, 28, 52, 18, 66, 28, 70, 26, 76, 30, 80, 29, 86, 36, 94, 56, 98, 70, 90, 96, 70, 80, 40),
        fill=white,
    )
    # Cou, légèrement penché
    d.polygon(s(58, 84, 90, 70, 96, 120, 56, 120), fill=white)

    # Trou de l'impact à la tempe, et trois fissures brisées (deux segments chacune) qui en partent : régulières et
    # nombreuses, elles dessinaient un soleil
    cx, cy = HOLE
    d.ellipse(s(cx - HOLE_RADIUS, cy - HOLE_RADIUS, cx + HOLE_RADIUS, cy + HOLE_RADIUS), fill=clear)
    for angle, bend in ((-125, 30), (-35, -25), (95, 30)):
        a1, a2 = math.radians(angle), math.radians(angle + bend)
        mid = (cx + math.cos(a1) * CRACK_REACH * 0.6, cy + math.sin(a1) * CRACK_REACH * 0.6)
        end = (mid[0] + math.cos(a2) * CRACK_REACH * 0.5, mid[1] + math.sin(a2) * CRACK_REACH * 0.5)
        d.line(s(cx, cy, *mid, *end), fill=clear, width=4 * SS, joint="curve")

    # Éclats projetés à l'arrière du crâne, dans l'axe du tir (de gauche à droite) : peu et larges, pour rester lisibles
    # à 20 px
    for x, y, angle, length, half in (
        (102, 32, -28, 22, 7),
        (106, 50, 4, 20, 6.5),
        (118, 64, 28, 9, 4),
    ):
        shard(d, x, y, angle, length, half, white)

    img.resize((SIZE, SIZE), Image.LANCZOS).save(out)


if __name__ == "__main__":
    if len(sys.argv) != 2 or not sys.argv[1].lower().endswith(".png"):
        sys.exit("usage : uv run tools/ui/make_headshot_icon.py <fichier .png de sortie>")
    main(sys.argv[1])
