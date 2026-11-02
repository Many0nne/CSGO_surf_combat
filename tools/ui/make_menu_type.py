# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow", "numpy"]
# ///
"""Génère le titrage du menu principal : lettres arrachées par le vent, éclats et impacts de balles (PNG transparents).

Usage : uv run tools/ui/make_menu_type.py <police Anton .ttf> <dossier de sortie>
Police : Anton (SIL Open Font License), https://github.com/google/fonts/tree/main/ofl/anton
Mots en 1024 px maximum (limite d'affichage de Roblox), à publier ensuite avec tools/publish_asset.sh (type Decal).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = Path(sys.argv[1])
OUT = Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)
BONE = np.array([243, 233, 220], dtype=float)
EMBER = np.array([255, 150, 84], dtype=float)
RED = np.array([214, 44, 30], dtype=float)


def fractal(h, w, rng, scales=((4, 1.0), (10, 0.55), (28, 0.3), (70, 0.16))):
    """Bruit fractal 0-1 : superpose plusieurs grilles aléatoires agrandies."""
    total = np.zeros((h, w))
    for cells, amp in scales:
        small = Image.fromarray((rng.random((cells, cells * max(1, w // h))) * 255).astype("uint8"))
        total += amp * np.asarray(small.resize((w, h), Image.BICUBIC), dtype=float) / 255
    return (total - total.min()) / (total.max() - total.min())


def text_mask(text, size, pad_x, pad_y):
    """Trace le mot en masque, penché vers l'avant, avec de la marge pour les éclats."""
    font = ImageFont.truetype(str(FONT), size)
    left, top, right, bottom = font.getbbox(text)
    w, h = right - left + pad_x * 2, bottom - top + pad_y * 2
    img = Image.new("L", (w, h), 0)
    ImageDraw.Draw(img).text((pad_x - left, pad_y - top), text, fill=255, font=font)
    shear = 0.16
    img = img.transform((w, h), Image.AFFINE, (1, shear, -shear * h / 2, 0, 1, 0), Image.BICUBIC)
    return np.asarray(img, dtype=float) / 255


def wind(mask, rng, strength):
    """Décale chaque ligne vers l'arrière selon un bruit : les lettres se déchirent dans le sens de la vitesse."""
    h, w = mask.shape
    rows = fractal(h, 8, rng, ((6, 1.0), (24, 0.8), (90, 0.5)))[:, 0]
    rows = np.power(rows, 7) * strength
    out = np.zeros_like(mask)
    for y in range(h):
        out[y] = np.maximum(mask[y], np.roll(mask[y], -int(rows[y])) * 0.0)
        shift = int(rows[y])
        if shift:
            out[y] = np.roll(mask[y], -shift)
    return out


def erode(mask, rng, amount):
    """Ronge la matière : forte usure sur le bord arrière (gauche), rayures horizontales fines."""
    h, w = mask.shape
    noise = fractal(h, w, rng)
    streak = np.asarray(
        Image.fromarray((rng.random((h, max(8, w // 90))) * 255).astype("uint8")).resize((w, h), Image.BICUBIC),
        dtype=float,
    ) / 255
    col = mask.max(axis=0)
    xs = np.where(col > 0.1)[0]
    x0, x1 = (xs[0], xs[-1]) if len(xs) else (0, w)
    ramp = np.clip(1 - (np.arange(w) - x0) / max(1, x1 - x0), 0, 1)
    wear = (ramp[None, :] ** 2.2) * 0.55 + 0.12
    keep = (noise * 0.55 + streak * 0.45) > (wear * amount + 0.2)
    return mask * keep


def flecks(mask, rng, count, reach):
    """Ajoute des éclats arrachés qui partent vers l'arrière depuis les bords des lettres."""
    h, w = mask.shape
    layer = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(layer)
    ys, xs = np.where(mask > 0.5)
    if len(xs) == 0:
        return np.asarray(layer, dtype=float) / 255
    for _ in range(count):
        i = rng.integers(len(xs))
        dist = rng.exponential(reach)
        x = xs[i] - dist
        y = ys[i] + rng.normal(0, 4 + dist * 0.06)
        length = 1 + rng.exponential(10) * (1 + dist / reach)
        thick = max(1, int(rng.exponential(1.7)))
        draw.line([(x, y), (x + length, y + rng.normal(0, 0.6))], fill=int(rng.uniform(120, 255)), width=thick)
    return np.asarray(layer, dtype=float) / 255


def bullet_holes(alpha, rng, points, radius):
    """Perce de vrais trous : centre transparent, éclats rayonnants et couronne à vif (mêmes tirs que le jeu)."""
    h, w = alpha.shape
    rim = Image.new("L", (w, h), 0)
    cut = Image.new("L", (w, h), 0)
    d_rim, d_cut = ImageDraw.Draw(rim), ImageDraw.Draw(cut)
    for px, py in points:
        x, y = px * w, py * h
        d_rim.ellipse([x - radius * 1.5, y - radius * 1.5, x + radius * 1.5, y + radius * 1.5], fill=255)
        for _ in range(16):
            ang = rng.uniform(0, 2 * np.pi)
            length = radius * rng.uniform(1.6, 5.5)
            ex, ey = x + np.cos(ang) * length, y + np.sin(ang) * length
            d_cut.line([(x, y), (ex, ey)], fill=255, width=max(1, int(rng.uniform(1, radius * 0.32))))
        d_cut.ellipse([x - radius, y - radius, x + radius, y + radius], fill=255)
    return np.asarray(cut, dtype=float) / 255, np.asarray(rim.filter(ImageFilter.GaussianBlur(radius * 0.5)), dtype=float) / 255


def word(name, text, size, seed, wind_px, wear, fleck_count, reach, holes=(), hole_r=0):
    """Assemble un mot : déchirure, usure, éclats, impacts, puis lumière rasante chaude en bas des lettres."""
    rng = np.random.default_rng(seed)
    pad_x, pad_y = int(size * 0.9), int(size * 0.12)
    base = text_mask(text, size, pad_x, pad_y)
    torn = erode(wind(base, rng, wind_px), rng, wear)
    fl = flecks(base, rng, fleck_count, reach)
    alpha = np.maximum(torn, fl * 0.9)
    h, w = alpha.shape
    v = np.linspace(0, 1, h)[:, None]
    grain = fractal(h, w, rng, ((60, 1.0), (180, 0.7)))
    rgb = BONE[None, None, :] * (0.86 + grain[..., None] * 0.14)
    glow = np.clip((v - 0.55) / 0.45, 0, 1) ** 1.6
    rgb = rgb * (1 - glow[..., None] * 0.55) + EMBER[None, None, :] * glow[..., None] * 0.55
    fl_only = (fl > 0.05) & (torn < 0.2)
    rgb[fl_only] = EMBER * 0.5 + BONE * 0.5
    if holes:
        cut, rim = bullet_holes(alpha, rng, holes, hole_r)
        rgb = rgb * (1 - rim[..., None] * 0.75) + RED[None, None, :] * rim[..., None] * 0.75
        alpha = alpha * (1 - cut)
    arr = np.dstack([np.clip(rgb, 0, 255), alpha * 255]).astype("uint8")
    img = Image.fromarray(arr, "RGBA")
    img = img.crop(img.getbbox())
    img.thumbnail((1024, 1024), Image.LANCZOS)
    img.save(OUT / f"{name}.png")
    print(name, img.size)
    return img


word("surf", "SURF", 620, 7, 90, 0.42, 900, 120, ((0.57, 0.40), (0.70, 0.66)), 14)
word("jouer", "JOUER", 300, 11, 40, 0.3, 380, 60)
for i, (key, label) in enumerate((("infos", "INFOS"), ("reglages", "RÉGLAGES"), ("feedback", "FEEDBACK"))):
    word(key, label, 150, 20 + i, 0, 0.12, 70, 30)
# Onglets et actions de Réglages, Infos et Feedback (graines à part : les mots ci-dessus ne changent pas)
for i, (key, label) in enumerate(
    (
        ("surfer", "SURFER"),
        ("commandes", "COMMANDES"),
        ("credits", "CRÉDITS"),
        ("apropos", "À PROPOS"),
        ("retour", "RETOUR"),
        ("envoyer", "ENVOYER"),
        ("annuler", "ANNULER"),
    )
):
    word(key, label, 150, 40 + i, 0, 0.12, 70, 30)
