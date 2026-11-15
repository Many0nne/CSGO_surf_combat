# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Génère l'icône du crédit, la monnaie du jeu (#391) : un jeton en laiton (le métal des douilles), frappé d'un
réticule en creux, vu de face.

Image en couleur (pas teintée en jeu : le laiton fait la monnaie), sur fond transparent, détourée d'un liseré sombre
pour rester lisible sur l'os des étiquettes du shop comme sur le fond sombre du menu. Peu de détails : elle s'affiche
de 18 à 40 px. Dessinée 4 fois plus grande puis réduite, pour des bords lissés.
Usage : uv run tools/ui/make_credit_icon.py <fichier .png de sortie> [--preview <planche .png>]
Puis publier avec tools/publish_asset.sh (type Decal), voir docs/ui.md.
"""
import math
import sys

from PIL import Image, ImageDraw

SIZE = 128
SS = 4  # suréchantillonnage
C = SIZE / 2

OUTLINE = (34, 22, 8, 255)  # liseré sombre autour du jeton
RIM_DARK = (120, 80, 26, 255)  # tranche, côté ombre
RIM_LIGHT = (246, 210, 120, 255)  # tranche, côté lumière
GROOVE = (92, 60, 18, 255)  # sillon entre la tranche et la face (gris si on le fait d'un liseré translucide)
FACE_LIGHT = (240, 196, 98)  # face, en haut à gauche
FACE_DARK = (184, 132, 48)  # face, en bas à droite
STAMP = (112, 74, 22, 255)  # creux du réticule
STAMP_EDGE = (255, 230, 160, 255)  # arête éclairée du creux (bas droit)

R_OUTER = 62  # rayon du jeton, liseré compris
R_RIM = 58  # rayon de la tranche
R_FACE = 49  # rayon de la face, dans la tranche
R_RING = 29  # cercle du réticule
RING_W = 9  # épaisseur du cercle et des branches (à 7, le réticule s'empâtait à 18 px)
TICK_IN = 14  # début des branches, depuis le centre (le vide du milieu)
TICK_OUT = 42  # fin des branches, au-delà du cercle


# Cette méthode permet de passer des coordonnées de l'icône (0..128) à celles du dessin suréchantillonné lorsqu'une
# forme est tracée.
def s(*values: float) -> list[float]:
    return [v * SS for v in values]


# Cette méthode permet de calculer la boîte d'un disque centré lorsque le jeton est dessiné couche par couche.
def disc(r: float) -> list[float]:
    return s(C - r, C - r, C + r, C + r)


# Cette méthode permet de remplir un disque d'un dégradé diagonal (clair en haut à gauche, sombre en bas à droite)
# lorsque la tranche ou la face est dessinée.
def gradient_disc(img: Image.Image, r: float, light: tuple, dark: tuple) -> None:
    big = img.size[0]
    grad = Image.new("RGBA", (big, big))
    px = grad.load()
    for y in range(big):
        for x in range(big):
            t = min(1.0, max(0.0, (x + y) / (2 * big) * 1.5 - 0.25))
            px[x, y] = tuple(int(light[i] + (dark[i] - light[i]) * t) for i in range(3)) + (255,)
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).ellipse(disc(r), fill=255)
    img.paste(grad, (0, 0), mask)


# Cette méthode permet de tracer le réticule (cercle et quatre branches, vide au centre) dans un masque lorsque le
# creux et son arête éclairée sont dessinés ; décalage (dx, dy) en px de l'icône.
def reticle_mask(big: int, dx: float = 0, dy: float = 0) -> Image.Image:
    mask = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(mask)
    cx, cy = C + dx, C + dy
    d.ellipse(s(cx - R_RING, cy - R_RING, cx + R_RING, cy + R_RING), outline=255, width=RING_W * SS)
    half = RING_W / 2
    for angle in (0, 90, 180, 270):
        a = math.radians(angle)
        ux, uy = math.cos(a), math.sin(a)
        px, py = -uy * half, ux * half
        x1, y1 = cx + ux * TICK_IN, cy + uy * TICK_IN
        x2, y2 = cx + ux * TICK_OUT, cy + uy * TICK_OUT
        d.polygon(s(x1 + px, y1 + py, x2 + px, y2 + py, x2 - px, y2 - py, x1 - px, y1 - py), fill=255)
    return mask


# Cette méthode permet de dessiner le jeton lorsque le script est lancé : liseré, tranche, face, puis réticule frappé
# (arête claire décalée en bas à droite, creux sombre par-dessus), coupé au bord de la face.
def draw() -> Image.Image:
    big = SIZE * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse(disc(R_OUTER), fill=OUTLINE)
    gradient_disc(img, R_RIM, RIM_LIGHT[:3], RIM_DARK[:3])
    # Sillon entre la tranche et la face
    d.ellipse(disc(R_FACE + 2), fill=GROOVE)
    gradient_disc(img, R_FACE, FACE_LIGHT, FACE_DARK)

    face = Image.new("L", (big, big), 0)
    ImageDraw.Draw(face).ellipse(disc(R_FACE - 1), fill=255)
    edge = reticle_mask(big, 2.2, 2.2)
    stamp = reticle_mask(big)
    for mask, color in ((edge, STAMP_EDGE), (stamp, STAMP)):
        clipped = Image.new("L", (big, big), 0)
        clipped.paste(mask, (0, 0), face)
        img.paste(Image.new("RGBA", (big, big), color), (0, 0), clipped)
    # Point central
    d.ellipse(disc(4.5), fill=STAMP)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


# Cette méthode permet de composer une planche de contrôle lorsque --preview est demandé : l'icône aux tailles du jeu,
# sur le fond sombre du menu et sur l'os des étiquettes du shop.
def preview(icon: Image.Image, out: str) -> None:
    sizes = (18, 24, 32, 44, 128)
    width = sum(sizes) + 30 * (len(sizes) + 1)
    sheet = Image.new("RGBA", (width, 2 * 160), (0, 0, 0, 255))
    for row, bg in enumerate(((22, 24, 28), (243, 233, 220))):
        band = Image.new("RGBA", (width, 160), bg + (255,))
        x = 30
        for size in sizes:
            small = icon.resize((size, size), Image.LANCZOS)
            band.paste(small, (x, 80 - size // 2), small)
            x += size + 30
        sheet.paste(band, (0, row * 160))
    sheet.save(out)


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or not args[0].lower().endswith(".png"):
        sys.exit("usage : uv run tools/ui/make_credit_icon.py <fichier .png de sortie> [--preview <planche .png>]")
    icon = draw()
    icon.save(args[0])
    if len(args) == 3 and args[1] == "--preview":
        preview(icon, args[2])
