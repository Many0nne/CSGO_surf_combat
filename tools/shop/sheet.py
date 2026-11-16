# Planche du shop (#347) : pose sur chaque rendu une esquisse de l'interface (colonne de gauche, palette du menu) et
# assemble les trois variantes. Usage : python -I tools/shop/sheet.py <dossier de sortie> [rendu.png]
# Vue d'ensemble (toutes les caisses, #347) : python -I tools/shop/sheet.py <dossier de sortie> ensemble <dossier des vues>
# (vues V2, V2n, V6 et B de board.py ; écrit planche_ensemble.png).
# Polices Windows (Arial Narrow à la place d'Oswald) : l'esquisse sert à juger la place du texte, pas sa forme.
import os, re, sys
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1]
FONT = "C:/Windows/Fonts/ARIALNB.TTF"  # à la place d'Oswald gras (même famille étroite)
FONT_R = "C:/Windows/Fonts/ARIALN.TTF"
BONE, AMBER, RED, MUTED = (243, 233, 220), (242, 169, 0), (226, 58, 40), (150, 146, 140)
SCRIM = (10, 12, 22)
CATALOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "src", "shared", "ShopCatalog.luau")
# Noms d'exemple de l'esquisse, un par rareté (de la plus courante à la plus rare) : seuls libellés, chances et couleurs
# viennent du catalogue.
SAMPLES = ("AWP · M9  COUCHANT", "AWP · M9  IMPACT", "AWP · M9  RELEVÉ", "AWP · M9  TREMPE")


# Cette méthode permet de lire les raretés (libellé, chance, couleur) dans ShopCatalog.RARITIES lorsque l'esquisse écrit
# les chances, pour qu'elle suive le catalogue sans copie en dur (#451).
def rarities():
    src = open(CATALOG, encoding="utf-8").read()
    block = src[src.index("ShopCatalog.RARITIES = {") :].split("} :: { Rarity }", 1)[0]
    pat = r'label = "([^"]+)", chance = ([\d.]+), color = \{ (\d+), (\d+), (\d+) \}'
    found = [(lab, float(c), (int(r), int(g), int(b))) for lab, c, r, g, b in re.findall(pat, block)]
    if not found:
        raise SystemExit(f"Aucune rareté lue dans {CATALOG}")
    return found


# Cette méthode permet de dessiner la colonne d'interface du shop sur un rendu (fond de coin, titre, contenu, prix).
def overlay(path, title, sub, buy=True):
    im = Image.open(path).convert("RGBA")
    W, H = im.size
    sc = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(sc)
    for x in range(int(W * 0.5)):
        a = int(200 * max(0.0, 1 - x / (W * 0.5)) ** 1.3)
        d.line([(x, 0), (x, H)], fill=(*SCRIM, a))
    im = Image.alpha_composite(im, sc)
    d = ImageDraw.Draw(im)
    f = lambda s, bold=True: ImageFont.truetype(FONT if bold else FONT_R, s)
    x = 70
    d.text((x, 60), "SHOP" if buy else "‹  SHOP", font=f(30), fill=MUTED)
    d.text((x + 3, 103), title, font=f(68), fill=(0, 0, 0))
    d.text((x, 100), title, font=f(68), fill=BONE)
    d.text((x, 185), sub, font=f(22), fill=AMBER)
    y = 250
    for name, (label, chance, col) in zip(SAMPLES, rarities()):
        rar = f"{label} {chance:g} %".replace(".", ",")
        d.rectangle([x, y + 6, x + 6, y + 30], fill=col)
        d.text((x + 18, y), name, font=f(26, False), fill=BONE)
        d.text((x + 300, y + 3), rar, font=f(22), fill=col)
        y += 46
    d.line([(x, y + 10), (x + 520, y + 10)], fill=(*BONE, 30), width=1)
    d.text((x, y + 30), "500", font=f(54), fill=BONE)
    d.text((x + 100, y + 52), "CRÉDITS", font=f(22), fill=MUTED)
    bx, by = x, y + 110
    if buy:
        d.rectangle([bx, by, bx + 220, by + 54], fill=BONE)
        d.text((bx + 52, by + 10), "ACHETER", font=f(30), fill=(21, 24, 28))
    else:  # achat pas encore branché : bouton atténué en contour, étiquette BIENTÔT
        d.rectangle([bx, by, bx + 220, by + 54], outline=(*MUTED, 255), width=2)
        d.text((bx + 52, by + 10), "ACHETER", font=f(30), fill=MUTED)
        d.rectangle([bx + 150, by - 14, bx + 236, by + 12], fill=MUTED)
        d.text((bx + 158, by - 13), "BIENTÔT", font=f(20), fill=(21, 24, 28))
    d.text((bx + 250, by + 14), "‹  CAISSE 1 / 2  ›", font=f(24), fill=MUTED)
    out = path.replace(".png", "_ui.png")
    im.convert("RGB").save(out)
    return out


# Cette méthode permet de dessiner l'interface de la vue d'ensemble sur un rendu : titre à gauche sur fond de coin, nom
# et prix écrits sur l'étiquette de chaque caisse (repères projetés par board.py), aide en bas à gauche.
def ensemble(path, view, total):
    im = Image.open(path).convert("RGBA")
    W, H = im.size
    sc = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(sc)
    for x in range(int(W * 0.42)):
        a = int(210 * max(0.0, 1 - x / (W * 0.42)) ** 1.2)
        d.line([(x, 0), (x, H)], fill=(*SCRIM, a))
    im = Image.alpha_composite(im, sc)
    d = ImageDraw.Draw(im)
    f = lambda s, bold=True: ImageFont.truetype(FONT if bold else FONT_R, s)
    x = 70
    d.text((x, 60), "SHOP", font=f(30), fill=MUTED)
    d.text((x + 3, 103), "CAISSES", font=f(68), fill=(0, 0, 0))
    d.text((x, 100), "CAISSES", font=f(68), fill=BONE)
    d.text((x, 185), f"{total} EN VENTE · UNE PAR SÉRIE DE SKINS", font=f(22), fill=AMBER)
    for lab in view["labels"]:
        cx, cy = lab["xy"]
        ink = BONE if lab["hover"] else (21, 24, 28)
        name, price = lab["name"], f"{lab['price']} CRÉDITS"
        fn, fp = f(22), f(20, False)
        wn = d.textlength(name, font=fn)
        wp = d.textlength(price, font=fp)
        gap = 14
        x0 = cx - (wn + gap + wp) / 2
        d.text((x0, cy - 14), name, font=fn, fill=ink)
        d.text((x0 + wn + gap, cy - 11), price, font=fp, fill=ink)
    hy = H - 80
    d.rectangle([x, hy, x + 58, hy + 30], fill=BONE)
    d.text((x + 9, hy + 2), "CLIC", font=f(22), fill=(21, 24, 28))
    d.text((x + 72, hy + 2), "VOIR LE CONTENU ET ACHETER", font=f(22), fill=MUTED)
    out = path.replace(".png", "_ui.png")
    im.convert("RGB").save(out)
    return out


if len(sys.argv) > 3 and sys.argv[2] == "ensemble":
    import json

    V = sys.argv[3]
    shots = [
        ("V2", 2, "VUE D'ENSEMBLE · 2 CAISSES (AUJOURD'HUI)", "Vitrine contre le mur de droite de la salle ; étage du bas vide ; étiquette survolée en rouge d'impact"),
        ("V2n", 2, "VUE D'ENSEMBLE · 2 CAISSES, ÉTAGE GARNI", "Variante : l'étage vide porte des caisses sans marque (stock, pas en vente, pas d'étiquette)"),
        ("V6", 6, "VUE D'ENSEMBLE · 6 CAISSES (FACTICES AU-DELÀ DE 2)", "Vitrine pleine : trois caisses par étage, l'étage à hauteur d'œil d'abord"),
    ]
    done = []
    for n, total, label, desc in shots:
        view = json.load(open(os.path.join(V, n + "_views.json"), encoding="utf-8"))[0]
        done.append((ensemble(os.path.join(OUT, n + ".png"), view, total), label, desc))
    detail = overlay(os.path.join(OUT, "B_salle.png"), "SÉRIE 1", "CAISSE · COUCHANT / IMPACT / RELEVÉ", buy=False)
    done.append((detail, "CLIC SUR UNE CAISSE · VUE DÉTAIL", "La caméra glisse de la vitrine au socle (planche validée) ; ACHETER inactif ; ‹ SHOP revient à la vitrine"))
    w, h = 960, 540
    sheet = Image.new("RGB", (w * 2 + 20, (h + 70) * 2 + 20), (21, 24, 28))
    d = ImageDraw.Draw(sheet)
    for i, (p, label, desc) in enumerate(done):
        x0, y = 20 + (i % 2) * w, 20 + (i // 2) * (h + 70)
        d.text((x0, y), label, font=ImageFont.truetype(FONT, 26), fill=BONE)
        d.text((x0, y + 32), desc, font=ImageFont.truetype(FONT_R, 18), fill=MUTED)
        sheet.paste(Image.open(p).resize((w - 40, int((w - 40) * 9 / 16))), (x0, y + 60))
    sheet.save(os.path.join(OUT, "planche_ensemble.png"))
    print("ok")
    sys.exit()
if len(sys.argv) > 2:  # un seul rendu : esquisse d'interface seulement
    print(overlay(os.path.join(OUT, sys.argv[2]), "SÉRIE 1", "CAISSE · COUCHANT / IMPACT / RELEVÉ"))
    sys.exit()
shots = [
    ("A_rack.png", "A · LE RACK DU STOCKAGE", "Caisses rangées contre le mur en tôle de Dizzy ; la caisse choisie sort sur une palette"),
    ("B_salle.png", "B · LA SALLE DE PRÉSENTATION", "Pièce dédiée (retenue) : caisse sur un socle sous une suspension, contenu au mur, racks de caisses"),
    ("C_accueil.png", "C · À CÔTÉ DU PERSONNAGE", "Accueil actuel (couloir du toit) : la caisse posée aux pieds du personnage"),
]
done = [overlay(os.path.join(OUT, n), "SÉRIE 1", "CAISSE · COUCHANT / IMPACT / RELEVÉ") for n, _, _ in shots]
w, h = 960, 540
sheet = Image.new("RGB", (w, (h + 70) * 3 + 20), (21, 24, 28))
d = ImageDraw.Draw(sheet)
for i, (p, (_, label, desc)) in enumerate(zip(done, shots)):
    y = 20 + i * (h + 70)
    d.text((20, y), label, font=ImageFont.truetype(FONT, 28), fill=BONE)
    d.text((20, y + 34), desc, font=ImageFont.truetype(FONT_R, 20), fill=MUTED)
    sheet.paste(Image.open(p).resize((w - 40, int((w - 40) * 9 / 16))), (20, y + 62))
sheet.save(os.path.join(OUT, "planche_shop.png"))
print("ok")
