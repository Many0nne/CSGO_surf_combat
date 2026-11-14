# Planche des propositions de caisses (#332) : grille des vues 3/4 avant de tools/shop/crate_designs.py, vue arrière en
# vignette, légende et case des points communs. python -I tools/shop/crate_sheet.py <dossier des rendus> <sortie.png>
import os, sys
from PIL import Image, ImageDraw, ImageFont

SRC, OUT = sys.argv[1], sys.argv[2]
F = lambda s: ImageFont.truetype("C:/Windows/Fonts/ARIALNB.TTF", s)
TILES = [
    ("actuelle", "ACTUELLE", "pièces simples, coins os"),
    ("A_polymere", "A · MALLETTE POLYMÈRE", "coque arrondie, fermoirs à levier"),
    ("B_bois", "B · CAISSE D'ARMES EN BOIS", "planches, écharpe, coins acier, corde"),
    ("C_munitions", "C · COFFRE À MUNITIONS", "tôle nervurée, ceinture peinte"),
    ("D_flightcase", "D · FLIGHT CASE", "cornières alu, coins boule, étiquette"),
]
TW, TH = 900, 700
sheet = Image.new("RGB", (TW * 3, TH * 2), (14, 15, 20))
d = ImageDraw.Draw(sheet)
for i, (name, title, sub) in enumerate(TILES):
    x, y = (i % 3) * TW, (i // 3) * TH
    sheet.paste(Image.open(os.path.join(SRC, name + ".png")).convert("RGB"), (x, y))
    back = os.path.join(SRC, name + "_dos.png")
    if os.path.exists(back):
        th = Image.open(back).convert("RGB").resize((270, 210))
        sheet.paste(th, (x + TW - 290, y + TH - 230))
        d.rectangle([x + TW - 290, y + TH - 230, x + TW - 21, y + TH - 21], outline=(80, 80, 86), width=2)
    d.text((x + 30, y + 24), title, font=F(40), fill=(243, 233, 220))
    d.text((x + 30, y + 72), sub, font=F(26), fill=(150, 146, 140))
NOTES = [
    "même encombrement que l'actuelle (4 × 2 × 2,4)",
    "couvercle séparé, joint sombre : la lueur",
    "de rareté filtrera par là à l'ouverture",
    "bande rouge = couleur de la collection,",
    "recolorable par série",
    "",
    "rendus Workbench (forme et proportions),",
    "pas la matière finale",
]
x, y = 2 * TW, TH
d.text((x + 30, y + 24), "COMMUN AUX 4", font=F(40), fill=(243, 233, 220))
for i, line in enumerate(NOTES):
    d.text((x + 30, y + 100 + i * 44), line, font=F(30), fill=(150, 146, 140))
for i in range(1, 3):
    d.line([(i * TW, 0), (i * TW, TH * 2)], fill=(40, 40, 46), width=3)
d.line([(0, TH), (TW * 3, TH)], fill=(40, 40, 46), width=3)
sheet.save(OUT)
print(OUT)
