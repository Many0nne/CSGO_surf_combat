# Planches du portant des tenues (#543) : pose l'esquisse de l'interface du shop (colonne de gauche, palette du menu,
# étiquettes des tenues projetées par outfit_rack_board.py) sur les rendus et assemble une planche par question :
# présentation d'une tenue, emplacement du portant, vue détail d'une tenue.
# Usage : python -I tools/shop/outfit_sheet.py <rendus> <dossier des planches> [préfixe]
# Polices Windows (Arial Narrow à la place d'Oswald, comme tools/shop/sheet.py) : l'esquisse juge la place, pas la forme.
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

R, OUT = sys.argv[1], sys.argv[2]
PREFIX = sys.argv[3] if len(sys.argv) > 3 else "planche_"
FONT, FONT_R = "C:/Windows/Fonts/ARIALNB.TTF", "C:/Windows/Fonts/ARIALN.TTF"
BONE, AMBER, RED, MUTED, INK = (243, 233, 220), (242, 169, 0), (226, 58, 40), (150, 146, 140), (21, 24, 28)
SCRIM = (10, 12, 22)
# Couleurs des raretés (ShopCatalog.RARITIES)
RARITY = {"COMMUN": (150, 160, 172), "RARE": (70, 120, 230), "EXCEPTIONNEL": (170, 70, 220), "LÉGENDAIRE": (235, 75, 75)}
LABELS = json.load(open(os.path.join(R, "labels.json"), encoding="utf-8"))
os.makedirs(OUT, exist_ok=True)


# Cette méthode permet de charger la police de l'esquisse (gras ou normal) à une taille donnée.
def f(size, bold=True):
    return ImageFont.truetype(FONT if bold else FONT_R, size)


# Cette méthode permet d'écrire un prix à la française (espace tous les trois chiffres) lorsqu'une étiquette l'affiche.
def price(n):
    return f"{n:,}".replace(",", " ")


# Cette méthode permet de poser le fond de coin de la colonne (dégradé horizontal) sur un rendu.
def scrim(im, frac=0.45, alpha=210):
    W, H = im.size
    sc = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(sc)
    for x in range(int(W * frac)):
        d.line([(x, 0), (x, H)], fill=(*SCRIM, int(alpha * max(0.0, 1 - x / (W * frac)) ** 1.2)))
    return Image.alpha_composite(im, sc)


# Cette méthode permet de dessiner le jeton du crédit (disque ambré cerclé) devant un montant.
def coin(d, x, y, r):
    d.ellipse([x, y, x + 2 * r, y + 2 * r], fill=AMBER)
    d.ellipse([x + r * 0.35, y + r * 0.35, x + r * 1.65, y + r * 1.65], outline=(150, 100, 0), width=max(2, r // 6))


# Cette méthode permet de dessiner la vue d'ensemble du portant : titre, sous-onglets CAISSES / TENUES (ambre = où je
# suis), nom et prix sur l'étiquette de chaque tenue (survol en rouge d'impact), aide en bas à gauche.
def overview(name):
    im = scrim(Image.open(os.path.join(R, name + ".png")).convert("RGBA"), 0.42)
    W, H = im.size
    d = ImageDraw.Draw(im)
    x = 70
    d.text((x, 60), "SHOP", font=f(30), fill=MUTED)
    d.text((x + 3, 103), "TENUES", font=f(68), fill=(0, 0, 0))
    d.text((x, 100), "TENUES", font=f(68), fill=BONE)
    d.text((x, 185), "6 EN VENTE · ACHAT DIRECT, SANS TIRAGE", font=f(22), fill=AMBER)
    # sous-onglets du shop : boîte ambrée = vue ouverte
    tx, ty = x, 232
    for label, active in (("CAISSES", False), ("TENUES", True)):
        w = d.textlength(label, font=f(22)) + 28
        if active:
            d.rectangle([tx, ty, tx + w, ty + 36], fill=AMBER)
        d.text((tx + 14, ty + 5), label, font=f(22), fill=INK if active else MUTED)
        tx += w + 10
    for lab in LABELS.get(name, []):
        cx, cy = lab["xy"]
        half = max(lab["half"], 20)
        hover = lab["hover"]
        size = max(12, min(22, int(half / 3.6)))
        text = f"{lab['name']}  {price(lab['price'])}"
        fn = f(size)
        while d.textlength(text, font=fn) > 2 * half - 6 and size > 11:
            size -= 1
            fn = f(size)
        w = d.textlength(text, font=fn)
        d.text((cx - w / 2, cy - size * 0.62), text, font=fn, fill=BONE if hover else INK)
    hy = H - 80
    d.rectangle([x, hy, x + 58, hy + 30], fill=BONE)
    d.text((x + 9, hy + 2), "CLIC", font=f(22), fill=INK)
    d.text((x + 72, hy + 2), "VOIR LA TENUE ET ACHETER", font=f(22), fill=MUTED)
    return im.convert("RGB")


# Cette méthode permet de dessiner la vue détail d'une tenue : retour, nom, rareté, prix, ACHETER (ou POSSÉDÉE), tenue
# voisine, aide de rotation ; `owned` donne l'état d'une tenue déjà possédée.
def detail(name, owned):
    im = scrim(Image.open(os.path.join(R, name + ".png")).convert("RGBA"), 0.5, 200)
    W, H = im.size
    d = ImageDraw.Draw(im)
    x = 70
    d.text((x, 60), "‹  SHOP", font=f(30), fill=MUTED)
    d.text((x + 3, 103), "MERCURE", font=f(68), fill=(0, 0, 0))
    d.text((x, 100), "MERCURE", font=f(68), fill=BONE)
    rar, col = "EXCEPTIONNEL", RARITY["EXCEPTIONNEL"]
    d.text((x, 185), "TENUE DE PERSONNAGE", font=f(22), fill=AMBER)
    w = d.textlength(rar, font=f(20)) + 20
    rx = x + d.textlength("TENUE DE PERSONNAGE", font=f(22)) + 14
    d.rectangle([rx, 186, rx + w, 214], fill=col)
    d.text((rx + 10, 188), rar, font=f(20), fill=INK)
    y = 250
    for line in ("Chrome liquide sur tout le corps,", "reflet du ciel peint dans la matière."):
        d.text((x, y), line, font=f(24, False), fill=BONE)
        y += 34
    d.text((x, y + 8), "S'ÉQUIPE DANS ÉQUIPEMENT · TENUE", font=f(20), fill=MUTED)
    y += 56
    d.line([(x, y), (x + 520, y)], fill=(70, 70, 76), width=1)
    y += 26
    coin(d, x, y + 12, 17)
    d.text((x + 46, y), "2 500", font=f(54), fill=BONE)
    d.text((x + 46 + d.textlength("2 500", font=f(54)) + 14, y + 22), "CRÉDITS", font=f(22), fill=MUTED)
    by = y + 88
    if owned:
        # pas de bouton : étiquette pleine en rouge d'impact (rouge = « à moi », comme ÉQUIPÉ à l'écran d'équipement)
        d.rectangle([x, by, x + 220, by + 54], fill=RED)
        d.text((x + 38, by + 10), "POSSÉDÉE", font=f(30), fill=BONE)
    else:
        d.rectangle([x, by, x + 220, by + 54], fill=BONE)
        d.text((x + 52, by + 10), "ACHETER", font=f(30), fill=INK)
    d.text((x + 250, by + 14), "‹  TENUE 5 / 6  ›", font=f(24), fill=MUTED)
    for i, (key, text) in enumerate((("GLISSER", "LA TOURNER"),)):
        hx, hy = W - 330, H - 70
        d.rectangle([hx, hy, hx + 98, hy + 30], fill=BONE)
        d.text((hx + 10, hy + 2), key, font=f(22), fill=INK)
        d.text((hx + 112, hy + 2), text, font=f(22), fill=MUTED)
    return im.convert("RGB")


# Cette méthode permet d'annoter le plan vu de dessus (ortho 36 studs sur 1200 px, centré en x 0, z 7,6, -z en haut) :
# contour de la salle, emplacements, vitrine, socle et caméras.
def plan():
    im = Image.open(os.path.join(R, "q2_plan.png")).convert("RGB")
    d = ImageDraw.Draw(im)

    # Cette méthode permet de convertir une position de la salle (x, z en studs) en pixel du plan.
    def px(x, z):
        return (600 + x / 36 * 1200, 600 + (z - 7.6) / 36 * 1200)

    d.rectangle([*px(-15.75, -8.75), *px(15.75, 24.0)], outline=BONE, width=3)
    for txt, (x, z), col in (
        ("P1", (-9.0, 16.8), AMBER),
        ("P2", (-8.9, -1.2), AMBER),
        ("P3", (8.9, -1.2), AMBER),
        ("VITRINE DES CAISSES", (9.5, 7.3), BONE),
        ("SOCLE", (0, 4.6), BONE),
    ):
        fn = f(44 if txt.startswith("P") else 26)
        w = d.textlength(txt, font=fn)
        cx, cy = px(x, z)
        d.text((cx - w / 2, cy - 20), txt, font=fn, fill=col)
    # vitrine (masquée au plan par le cadre clair : contour seul) et caméras (triangle vers la visée)
    d.rectangle([*px(12.7, 0.7), *px(15.7, 13.9)], outline=BONE, width=3)
    cams = (
        ("détail des caisses", (4, 20), (-4.5, 0)),
        ("vitrine", (-2.8, 4.5), (14.2, 4.5)),
        ("P1", (9.15, 19.6), (-12.85, 19.6)),
    )
    for label, (x, z), (tx, tz) in cams:
        cx, cy = px(x, z)
        vx, vy = px(tx, tz)
        dx, dy = vx - cx, vy - cy
        n = (dx * dx + dy * dy) ** 0.5
        dx, dy = dx / n, dy / n
        # point de la caméra et trait dans la direction de visée
        d.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], fill=RED)
        d.line([(cx, cy), (cx + dx * 70, cy + dy * 70)], fill=RED, width=5)
        d.text((cx + 14, cy + 12), "caméra " + label, font=f(22, False), fill=RED)
    return im


# Cette méthode permet de centrer une image carrée (plan) dans une case 16:9 sur fond sombre.
def letterbox(img, w=1600, h=900):
    canvas = Image.new("RGB", (w, h), INK)
    canvas.paste(img.resize((h, h)), ((w - h) // 2, 0))
    return canvas


# Cette méthode permet de couper une légende en lignes de largeur `width` px lorsqu'elle ne tient pas sous sa case.
def wrap(d, text, font, width):
    lines, cur = [], ""
    for word in text.split(" "):
        test = f"{cur} {word}".strip()
        if d.textlength(test, font=font) > width and cur:
            lines.append(cur)
            cur = word
        else:
            cur = test
    return lines + [cur]


# Cette méthode permet d'assembler une planche : titre, puis des cases (image, titre, légende) sur `cols` colonnes.
def sheet(path, title, intro, cells, cols, w=960):
    h = int(w * 9 / 16)
    rows = (len(cells) + cols - 1) // cols
    top = 130
    cell_h = h + 110
    im = Image.new("RGB", (cols * w + (cols + 1) * 24, top + rows * cell_h + 20), INK)
    d = ImageDraw.Draw(im)
    d.text((24, 20), title, font=f(44), fill=BONE)
    d.text((24, 76), intro, font=f(22, False), fill=MUTED)
    for i, (img, label, legend) in enumerate(cells):
        x = 24 + (i % cols) * (w + 24)
        y = top + (i // cols) * cell_h
        ih = int(img.height * w / img.width)
        im.paste(img.resize((w, min(ih, h))), (x, y))
        d.text((x, y + h + 10), label, font=f(26), fill=BONE)
        ly = y + h + 46
        for line in wrap(d, legend, f(19, False), w):
            d.text((x, ly), line, font=f(19, False), fill=MUTED)
            ly += 24
    im.save(path)
    print(path)


P = lambda s: os.path.join(OUT, PREFIX + s + ".png")
sheet(
    P("presentation"),
    "TENUES · COMMENT UNE TENUE EST MONTRÉE SUR LE PORTANT",
    "Même emplacement (P1, face à la vitrine) et même cadrage. MERCURE : vraies cartes du jeu ; les cinq autres tenues prévues en couleurs unies. Survol : MERCURE (étiquette rouge).",
    [
        (overview("q1_cintre"), "A · SUR CINTRE", "Haut (torse et bras) sur la barre du haut, bas (bassin et jambes) sur celle du bas, de trois quarts. La tenue survolée sort du rang, de face. 8 à 10 tenues tiennent en serrant."),
        (overview("q1_buste"), "B · SUR BUSTE", "Torse et tête sur un pied, trois par étage comme la vitrine des caisses. Lisible de face, mais ni bras ni jambes (le chrome des bras de MERCURE ne se voit pas). 6 au plus."),
        (overview("q1_complet"), "C · PERSONNAGE COMPLET", "Six mannequins debout sur une estrade à deux marches. La tenue entière, mais ils se cachent les uns les autres (bras collés au corps : 6,4 studs de large chacun). 6 au plus."),
        (detail("q3_detail", False), "RAPPEL · VUE DÉTAIL (PLANCHE 3)", "Quelle que soit la présentation, le clic montre la tenue portée en entier sur le socle : le portant n'a pas à tout montrer."),
    ],
    2,
)
sheet(
    P("emplacement"),
    "TENUES · OÙ PLACER LE PORTANT DANS LA SALLE",
    "Portant sur cintre (A). En haut à gauche : plan vu de dessus. Puis, par emplacement : sa vue de face (la vue d'ensemble des tenues) et la vue détail des caisses actuelle, pour voir s'il la dérange.",
    [
        (letterbox(plan()), "PLAN", "P1 mur de gauche à l'avant, face à la vitrine ; P2 mur du fond à gauche du socle ; P3 mur du fond à droite du socle. Caméras en rouge."),
        (overview("q2_p1_face"), "P1 · FACE À LA VITRINE (VUE DE FACE)", "Le portant a son propre plan, comme la vitrine : CAISSES et TENUES sont deux vues du shop, la caméra se retourne (glissement)."),
        (Image.open(os.path.join(R, "q2_p1_detail.png")).convert("RGB"), "P1 · VUE DÉTAIL DES CAISSES", "Inchangée : le portant est derrière la caméra, la gauche reste sombre sous l'interface."),
        (overview("q2_p2_face"), "P2 · FOND, À GAUCHE DU SOCLE (VUE DE FACE)", "Remplace le rack de stock de gauche."),
        (Image.open(os.path.join(R, "q2_p2_detail.png")).convert("RGB"), "P2 · VUE DÉTAIL DES CAISSES", "Le portant blanc passe derrière la caisse et sous la colonne de texte : la gauche ne fait plus fond sombre (raison du refus de la vitrine à gauche)."),
        (overview("q2_p3_face"), "P3 · FOND, À DROITE DU SOCLE (VUE DE FACE)", "Remplace le rack de stock du fond ; la vitrine est juste à droite."),
        (Image.open(os.path.join(R, "q2_p3_detail.png")).convert("RGB"), "P3 · VUE DÉTAIL DES CAISSES", "Le portant entre dans l'image à droite, à côté de la caisse : deux sujets se disputent la vue."),
    ],
    2,
)
sheet(
    P("vue-detail"),
    "TENUES · VUE DÉTAIL D'UNE TENUE",
    "Même direction que la vue détail des caisses : colonne à gauche, sujet sur le socle sous la suspension (cloche remontée de 2 studs : la tête du personnage y touchait presque).",
    [
        (detail("q3_detail", False), "À ACHETER", "Nom, « TENUE DE PERSONNAGE » et rareté, deux lignes de description, où l'équiper, prix (jeton, montant, CRÉDITS), ACHETER, tenue voisine."),
        (detail("q3_detail", True), "DÉJÀ POSSÉDÉE", "ACHETER remplacé par l'étiquette POSSÉDÉE, pleine en rouge d'impact (rouge = à moi, comme ÉQUIPÉ), sans clic. On l'équipe dans l'onglet TENUE de l'équipement."),
        (Image.open(os.path.join(R, "q3_proche.png")).convert("RGB"), "GROS PLAN (COMME L'APERÇU D'UN SKIN)", "Variante : la caméra s'avance sur la tenue ; glisser la fait tourner, comme l'aperçu d'un skin."),
        (Image.open(os.path.join(R, "q2_p1_detail.png")).convert("RGB"), "RÉFÉRENCE · VUE DÉTAIL DES CAISSES", "Même salle, même caméra, rendu Workbench (sans les lampes) : la caisse sur son socle, d'où part la tenue."),
    ],
    2,
)
