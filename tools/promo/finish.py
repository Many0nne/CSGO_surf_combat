# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Retouches des miniatures de la page du jeu (#524, docs/promo.md).

clean SRC DST             efface le cube de vue de Studio (coin haut droit du viewport) d'une capture de stage.luau
scope SRC DST             pose la lunette de l'AWP comme en jeu (ScopeOverlay : cercle de la hauteur de l'écran, masque
                          noir, réticule blanc de 1 px à contour noir, écart central de 6 px, point de 2 px), à l'échelle
                          de l'image (épaisseurs données pour un écran de 1080 px de haut)
export SRC DST            recadre au 16:9 (centre) et redimensionne en 1920x1080, PNG
small SRC... SHEET        planche des miniatures aux tailles d'affichage (320x180 et 160x90) pour juger la lisibilité
"""

import sys

from PIL import Image, ImageDraw, ImageFilter

W, H = 1920, 1080


def clean(src: str, dst: str) -> None:
    """Remplace la zone du cube de vue par la bande voisine étirée (ciel en dégradé vertical), lorsqu'une capture vient
    du viewport ; un fondu sur le bord gauche évite la couture."""
    im = Image.open(src).convert("RGB")
    w, h = im.size
    # Cube de vue : environ 100 px au coin haut droit d'un viewport de 1349x759 (mesuré sur les captures)
    x0, y1 = int(w * 0.89), int(h * 0.19)
    strip = im.crop((x0 - 12, 0, x0 - 4, y1)).resize((w - x0, y1), Image.BILINEAR)
    strip = strip.filter(ImageFilter.GaussianBlur(3))
    fade = Image.new("L", (w - x0, y1), 255)
    d = ImageDraw.Draw(fade)
    for i in range(20):
        d.line((i, 0, i, y1), fill=int(255 * i / 20))
    im.paste(strip, (x0, 0), fade)
    im.save(dst)


def scope(src: str, dst: str) -> None:
    """Dessine la lunette de ScopeOverlay sur une capture au FOV de la lunette."""
    im = Image.open(src).convert("RGB")
    w, h = im.size
    k = h / 1080
    cx, cy, r = w / 2, h / 2, h / 2
    mask = Image.new("L", (w, h), 255)
    ImageDraw.Draw(mask).ellipse((cx - r, cy - r, cx + r, cy + r), fill=0)
    im.paste((0, 0, 0), (0, 0), mask)
    d = ImageDraw.Draw(im)
    gap, line, outline = 6 * k, max(1, round(1 * k)), max(1, round(1 * k))
    for x0, y0, x1, y1 in (
        (cx - r, cy, cx - gap, cy),
        (cx + gap, cy, cx + r, cy),
        (cx, cy - r, cx, cy - gap),
        (cx, cy + gap, cx, cy + r),
    ):
        d.line((x0, y0, x1, y1), fill=(0, 0, 0), width=line + 2 * outline)
        d.line((x0, y0, x1, y1), fill=(255, 255, 255), width=line)
    dot = max(1, round(2 * k)) / 2
    d.rectangle((cx - dot, cy - dot, cx + dot, cy + dot), fill=(255, 255, 255))
    im.save(dst)


def export(src: str, dst: str) -> None:
    """Recadre au centre en 16:9 puis redimensionne en 1920x1080 (Lanczos)."""
    im = Image.open(src).convert("RGB")
    w, h = im.size
    if w / h > W / H:
        nw = round(h * W / H)
        im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    else:
        nh = round(w * H / W)
        im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
    im.resize((W, H), Image.LANCZOS).save(dst, optimize=True)


def small(paths: list[str], sheet: str) -> None:
    """Assemble chaque miniature à 320x180 et 160x90, sur fond gris de page, pour juger la lecture en petit."""
    rows = [Image.open(p).convert("RGB") for p in paths]
    pad = 12
    out = Image.new("RGB", (pad * 3 + 320 + 160, pad + len(rows) * (180 + pad)), (35, 37, 41))
    for i, im in enumerate(rows):
        y = pad + i * (180 + pad)
        out.paste(im.resize((320, 180), Image.LANCZOS), (pad, y))
        out.paste(im.resize((160, 90), Image.LANCZOS), (pad * 2 + 320, y))
    out.save(sheet)


if __name__ == "__main__":
    cmd, *args = sys.argv[1:]
    if cmd == "clean":
        clean(*args)
    elif cmd == "scope":
        scope(*args)
    elif cmd == "export":
        export(*args)
    elif cmd == "small":
        small(args[:-1], args[-1])
    else:
        sys.exit(__doc__)
