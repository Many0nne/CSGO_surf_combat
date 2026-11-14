# Planche du shop (#347) : pose sur chaque rendu une esquisse de l'interface (colonne de gauche, palette du menu) et
# assemble les trois variantes. Usage : python -I tools/shop/sheet.py <dossier de sortie> [rendu.png]
# Polices Windows (Arial Narrow à la place d'Oswald) : l'esquisse sert à juger la place du texte, pas sa forme.
import os, sys
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1]
FONT = "C:/Windows/Fonts/ARIALNB.TTF"  # à la place d'Oswald gras (même famille étroite)
FONT_R = "C:/Windows/Fonts/ARIALN.TTF"
BONE, AMBER, RED, MUTED = (243, 233, 220), (242, 169, 0), (226, 58, 40), (150, 146, 140)
SCRIM = (10, 12, 22)


# Cette méthode permet de dessiner la colonne d'interface du shop sur un rendu (fond de coin, titre, contenu, prix).
def overlay(path, title, sub):
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
    d.text((x, 60), "SHOP", font=f(30), fill=MUTED)
    d.text((x + 3, 103), title, font=f(68), fill=(0, 0, 0))
    d.text((x, 100), title, font=f(68), fill=BONE)
    d.text((x, 185), sub, font=f(22), fill=AMBER)
    y = 250
    for name, rar, col in (("AWP · M9  COUCHANT", "COMMUN 70 %", (150, 160, 172)), ("AWP · M9  IMPACT", "RARE 25 %", (70, 120, 230)), ("AWP · M9  RELEVÉ", "EXCEPTIONNEL 5 %", (170, 70, 220))):
        d.rectangle([x, y + 6, x + 6, y + 30], fill=col)
        d.text((x + 18, y), name, font=f(26, False), fill=BONE)
        d.text((x + 300, y + 3), rar, font=f(22), fill=col)
        y += 46
    d.line([(x, y + 10), (x + 520, y + 10)], fill=(*BONE, 30), width=1)
    d.text((x, y + 30), "500", font=f(54), fill=BONE)
    d.text((x + 100, y + 52), "CRÉDITS", font=f(22), fill=MUTED)
    bx, by = x, y + 110
    d.rectangle([bx, by, bx + 220, by + 54], fill=BONE)
    d.text((bx + 52, by + 10), "ACHETER", font=f(30), fill=(21, 24, 28))
    d.text((bx + 250, by + 14), "‹  CAISSE 1 / 2  ›", font=f(24), fill=MUTED)
    out = path.replace(".png", "_ui.png")
    im.convert("RGB").save(out)
    return out


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
