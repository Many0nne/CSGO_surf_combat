# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Génère l'icône de la série de kills du HUD (#364) : un crâne blanc de face, orbites, nez et dents ajourés.

Blanc sur fond transparent, teinté en jeu par ImageColor3 (os au repos, rouge d'impact au palier), comme les fonds du HUD.
Dessiné 4 fois plus grand puis réduit, pour des bords lissés.
Usage : uv run tools/ui/make_skull_icon.py <fichier .png de sortie>
Puis publier avec tools/publish_asset.sh (type Decal), voir docs/ui.md.
"""
import sys

from PIL import Image, ImageDraw

SIZE = 128
SS = 4  # suréchantillonnage


# Cette méthode permet de passer des coordonnées de l'icône (0..128) à celles du dessin suréchantillonné lorsque une
# forme est tracée.
def s(*values: float) -> list[float]:
    return [v * SS for v in values]


# Cette méthode permet d'écrire l'icône lorsque le script est lancé : crâne et mâchoire pleins, puis orbites, nez et
# interstices des dents effacés (alpha 0) pour laisser voir la scène.
def main(out: str) -> None:
    big = SIZE * SS
    img = Image.new("RGBA", (big, big), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    white = (255, 255, 255, 255)
    clear = (255, 255, 255, 0)

    # Crâne : grand ovale, pommettes, mâchoire arrondie
    d.ellipse(s(14, 4, 114, 96), fill=white)
    d.rounded_rectangle(s(30, 64, 98, 104), radius=10 * SS, fill=white)
    d.rounded_rectangle(s(38, 96, 90, 124), radius=8 * SS, fill=white)

    # Orbites : deux ovales penchés vers le nez
    d.ellipse(s(27, 44, 59, 76), fill=clear)
    d.ellipse(s(69, 44, 101, 76), fill=clear)
    # Nez : triangle pointe en haut
    d.polygon(s(64, 78, 56, 94, 72, 94), fill=clear)
    # Dents : trois interstices verticaux dans la mâchoire, et le trait entre les deux rangées
    for x in (50, 64, 78):
        d.rectangle(s(x - 2, 104, x + 2, 124), fill=clear)
    d.rectangle(s(38, 102, 90, 105), fill=clear)

    img.resize((SIZE, SIZE), Image.LANCZOS).save(out)


if __name__ == "__main__":
    if len(sys.argv) != 2 or not sys.argv[1].lower().endswith(".png"):
        sys.exit("usage : uv run tools/ui/make_skull_icon.py <fichier .png de sortie>")
    main(sys.argv[1])
