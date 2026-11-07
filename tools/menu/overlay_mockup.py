# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Pose une maquette de l'interface du menu (disposition retenue, style HUD) sur un rendu, pour juger une composition.

Usage : uv run tools/menu/overlay_mockup.py <Oswald .ttf> <rendu.png> <sortie.jpg> [dark|light] [annotations.json]
Police : Oswald (SIL Open Font License), https://github.com/google/fonts/tree/main/ofl/oswald (fichier Oswald[wght].ttf)
Maquette seulement : l'interface réelle est construite en Roblox (src/client/ui/).
"""
import json, sys, os
from PIL import Image, ImageDraw, ImageFont

FONT = sys.argv[1]
BONE, AMBER, RED, NIGHT = (243, 233, 220), (242, 169, 0), (226, 58, 40), (10, 12, 22)


# Cette méthode permet de charger Oswald à la graisse demandée.
def font(size, weight="SemiBold"):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


# Cette méthode permet d'écrire un texte avec l'ombre noire décalée du HUD lorsque le thème est sombre.
def text(d, xy, s, f, fill, shadow, anchor="la"):
    if shadow:
        d.text((xy[0] + 3, xy[1] + 3), s, font=f, fill=(0, 0, 0, 230), anchor=anchor)
    d.text(xy, s, font=f, fill=fill, anchor=anchor)


# Cette méthode permet de dessiner une barre segmentée (10 segments) comme les barres du HUD.
def bar(d, x, y, filled, red_last, fg, dim):
    w, g, h = 25, 6, 5
    for i in range(10):
        c = fg if i < filled else dim
        if red_last and i == 9:
            c = RED
        d.rectangle([x + i * (w + g), y, x + i * (w + g) + w, y + h], fill=c)


def main():
    src, dst = sys.argv[2], sys.argv[3]
    theme = sys.argv[4] if len(sys.argv) > 4 else "dark"
    dark = theme == "dark"
    fg = BONE if dark else NIGHT
    muted = (190, 182, 170) if dark else (60, 62, 72)
    dim = (70, 70, 78) if dark else (190, 184, 174)
    amber = AMBER if dark else (176, 112, 0)
    im = Image.open(src).convert("RGBA")
    W, H = im.size
    k = W / 1920
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    S = lambda v: int(v * k)

    # Haut gauche.
    text(d, (S(38), S(30)), "SURF FFA", font(S(38), "SemiBold"), fg, dark)
    text(d, (S(40), S(84)), "COMBAT DE SURF", font(S(14), "Medium"), amber, False)

    # Onglets.
    tabs = ["ARMES", "INFOS", "JOUER", "RÉGLAGES", "FEEDBACK"]
    fs = [font(S(20), "Medium") if t != "JOUER" else font(S(36), "SemiBold") for t in tabs]
    widths = [d.textlength(t, font=f) for t, f in zip(tabs, fs)]
    gap = S(66)
    total = sum(widths) + gap * (len(tabs) - 1)
    x = (W - total) / 2
    cy = S(62)
    for i, (t, f, w) in enumerate(zip(tabs, fs, widths)):
        active = t == "JOUER"
        text(d, (x, cy), t, f, fg if active else muted, dark and active, anchor="lm")
        if active:
            d.rectangle([x - S(4), cy + S(28), x + w + S(4), cy + S(31)], fill=RED)
        if i < len(tabs) - 1:
            sx = x + w + gap / 2
            d.line([sx, cy - S(12), sx, cy + S(12)], fill=muted + (110,), width=1)
        x += w + gap

    # Fiche de l'arme (bas gauche).
    text(d, (S(38), S(700)), "AWP", font(S(78), "SemiBold"), fg, dark)
    text(d, (S(41), S(806)), "FUSIL DE PRÉCISION  ·  1 / 5", font(S(14), "Medium"), amber, False)
    lab = font(S(13), "Medium")
    for i, (name, n, red) in enumerate([("DÉGÂTS", 9, True), ("CADENCE", 2, False), ("PRÉCISION", 9, False)]):
        y = S(842 + i * 27)
        text(d, (S(41), y), name, lab, amber, False, anchor="lm")
        bar(d, S(160), y - S(2), n, red, fg, dim)

    # Bas droite.
    text(d, (W - S(36), H - S(42)), "‹  MOLETTE  ·  1-9  ›", font(S(14), "Medium"), muted, False, anchor="rm")

    # Annotations (filets fins façon HUD) projetées depuis Blender.
    if len(sys.argv) > 5 and os.path.exists(sys.argv[5]):
        for a in json.load(open(sys.argv[5])):
            col = tuple(a.get("color", fg)) + (a.get("alpha", 200),)
            if a["type"] == "arc":
                x0, y0, r = a["c"][0], a["c"][1], a["r"]
                d.arc([x0 - r, y0 - a.get("ry", r), x0 + r, y0 + a.get("ry", r)], a["a0"], a["a1"], fill=col, width=a.get("w", 2))
            elif a["type"] == "line":
                d.line([tuple(p) for p in a["pts"]], fill=col, width=a.get("w", 2))
            elif a["type"] == "poly":
                d.polygon([tuple(p) for p in a["pts"]], fill=col)

    out = Image.alpha_composite(im, ov).convert("RGB")
    out.save(dst, quality=92)


if __name__ == "__main__":
    main()
