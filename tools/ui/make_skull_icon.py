# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Génère les icônes de la série de kills du HUD depuis le crâne vectorisé fourni par l'utilisateur
(assets/ui/hud/crane_serie.svg : un seul chemin de polygones M/L/Z, remplissage pair-impair ; le fond est ignoré).

Deux images carrées, blanc sur fond transparent, teintées en jeu par ImageColor3 (os, puis rouge d'impact dès 10 kills) :
- crane_serie.png : os plein (2 à 4 kills) ;
- crane_serie_hachures.png : même crâne barré de hachures diagonales grises (5 kills et plus), qui foncent avec la teinte.
Dessiné 4 fois plus grand puis réduit, pour des bords lissés.
Usage : uv run tools/ui/make_skull_icon.py <dossier de sortie> [--preview <planche .png>]
Puis publier chaque image avec tools/publish_asset.sh (type Decal), voir docs/ui.md.
"""
import re
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SOURCE = Path(__file__).resolve().parents[2] / "assets" / "ui" / "hud" / "crane_serie.svg"
SIZE = 256
SS = 4  # suréchantillonnage
MARGIN = 0.03  # marge autour du crâne, en fraction du côté
HATCH_PERIOD = 0.032  # écart entre deux hachures, en fraction du côté
HATCH_WIDTH = 0.42  # part de la période couverte par une hachure
HATCH_GRAY = 140  # gris des hachures : multiplié par la teinte en jeu
# Les hachures de la référence sont découpées dans le SVG : une fermeture en travers des bandes, de cette portée (en
# fraction du côté, de part et d'autre), les rebouche sans fermer les orbites ni la bouche.
CLOSE_SIZE = 0.006
SMOOTH = 0.0025  # rayon du flou de lissage, en fraction du côté

Point = tuple[float, float]


# Cette méthode permet de lire les polygones du chemin du SVG lorsque l'icône est générée ; seules les commandes
# absolues M, L et Z sont acceptées (celles du fichier vectorisé).
def polygons(svg: str) -> list[list[Point]]:
    match = re.search(r'<path[^>]*\sd="([^"]+)"', svg)
    if not match:
        sys.exit(f"aucun <path d=...> dans {SOURCE}")
    tokens = re.findall(r"[MLZ]|-?\d+(?:\.\d+)?", match.group(1))
    out: list[list[Point]] = []
    current: list[Point] = []
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        if tok == "M":
            if current:
                out.append(current)
            current = [(float(tokens[i + 1]), float(tokens[i + 2]))]
            i += 3
        elif tok == "L":
            current.append((float(tokens[i + 1]), float(tokens[i + 2])))
            i += 3
        elif tok == "Z":
            out.append(current)
            current = []
            i += 1
        else:
            sys.exit(f"commande SVG non gérée : {tok}")
    if current:
        out.append(current)
    return out


# Cette méthode permet de rastériser le crâne en masque carré centré lorsque l'icône est générée : chaque polygone
# inverse le masque (règle pair-impair du SVG), à l'échelle qui fait tenir le crâne dans le carré.
def skull_mask() -> Image.Image:
    polys = polygons(SOURCE.read_text(encoding="utf-8"))
    xs = [x for p in polys for x, _ in p]
    ys = [y for p in polys for _, y in p]
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    big = SIZE * SS
    scale = big * (1 - 2 * MARGIN) / max(x1 - x0, y1 - y0)
    ox = (big - (x1 - x0) * scale) / 2 - x0 * scale
    oy = (big - (y1 - y0) * scale) / 2 - y0 * scale
    mask = Image.new("1", (big, big), 0)
    for poly in polys:
        if len(poly) < 3:
            continue
        layer = Image.new("1", (big, big), 0)
        ImageDraw.Draw(layer).polygon([(x * scale + ox, y * scale + oy) for x, y in poly], fill=1)
        mask = ImageChops.logical_xor(mask, layer)
    gray = close_across_hatches(mask.convert("L"), int(CLOSE_SIZE * big))
    # le SVG est tracé sur une grille de pixels : un flou suivi d'un seuil arrondit les marches d'escalier
    blur = gray.filter(ImageFilter.GaussianBlur(SMOOTH * big))
    return blur.point(lambda v: 255 if v >= 128 else 0)


# Cette méthode permet de reboucher les hachures découpées dans le SVG lorsque le masque est construit : dilatation
# puis érosion le long de la seule diagonale « \ », en travers des bandes « / », pour ne pas épaissir le reste.
def close_across_hatches(mask: Image.Image, reach: int) -> Image.Image:
    shifts = range(-reach, reach + 1)
    grown = mask
    for i in shifts:
        grown = ImageChops.lighter(grown, ImageChops.offset(mask, i, i))
    closed = grown
    for i in shifts:
        closed = ImageChops.darker(closed, ImageChops.offset(grown, i, i))
    return closed


# Cette méthode permet de composer l'icône blanche sur fond transparent lorsque une image est écrite ; avec hachures,
# des bandes diagonales grises recouvrent l'os sans toucher au canal alpha.
def icon(mask: Image.Image, hatched: bool) -> Image.Image:
    big = mask.width
    img = Image.new("RGBA", (big, big), (255, 255, 255, 255))
    if hatched:
        stripes = Image.new("L", (big, big), 0)
        d = ImageDraw.Draw(stripes)
        period = int(HATCH_PERIOD * big)
        for offset in range(-big, big * 2, period):
            d.line([(offset, big), (offset + big, 0)], fill=255, width=int(period * HATCH_WIDTH))
        img.paste((HATCH_GRAY, HATCH_GRAY, HATCH_GRAY, 255), (0, 0), stripes)
    img.putalpha(mask)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


# Cette méthode permet de teinter une icône comme ImageColor3 en jeu lorsque la planche d'aperçu est composée.
def tint(img: Image.Image, color: tuple[int, int, int]) -> Image.Image:
    r, g, b, a = img.split()
    channels = [ch.point(lambda v, c=c: v * c // 255) for ch, c in zip((r, g, b), color)]
    return Image.merge("RGBA", (*channels, a))


# Cette méthode permet de composer une planche des trois états (os, os hachuré, rouge hachuré) en grand et à la taille
# du HUD (40 px) lorsque l'option --preview est passée.
def preview(plain: Image.Image, stripes: Image.Image, out: str) -> None:
    bone, red = (232, 224, 208), (230, 57, 70)
    states = [tint(plain, bone), tint(stripes, bone), tint(stripes, red)]
    sheet = Image.new("RGBA", (3 * 276 + 16, 276 + 16 + 60), (16, 16, 16, 255))
    for i, state in enumerate(states):
        sheet.alpha_composite(state.resize((256, 256), Image.LANCZOS), (16 + i * 276, 16))
        sheet.alpha_composite(state.resize((40, 40), Image.LANCZOS), (16 + i * 276, 292))
    sheet.save(out)


# Cette méthode permet d'écrire les deux icônes (et la planche demandée) lorsque le script est lancé.
def main(out_dir: str, preview_path: str | None) -> None:
    mask = skull_mask()
    plain, stripes = icon(mask, False), icon(mask, True)
    folder = Path(out_dir)
    plain.save(folder / "crane_serie.png")
    stripes.save(folder / "crane_serie_hachures.png")
    if preview_path:
        preview(plain, stripes, preview_path)


if __name__ == "__main__":
    args = sys.argv[1:]
    preview_out = None
    if "--preview" in args:
        i = args.index("--preview")
        preview_out = args[i + 1]
        del args[i : i + 2]
    if len(args) != 1:
        sys.exit("usage : uv run tools/ui/make_skull_icon.py <dossier de sortie> [--preview <planche .png>]")
    main(args[0], preview_out)
