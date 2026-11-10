# Texture du grillage des clôtures de Dizzy (DizzyDressing.CHAINLINK, cf. docs/maps.md) : losanges raccordables, fil
# galvanisé sur fond transparent, 256 px RGBA (deux losanges par tuile et par axe).
#   python -I tools/map/chainlink.py tools/map/chainlink.png
# Puis publier en Decal (bash tools/publish_asset.sh tools/map/chainlink.png Decal Dizzy_chainlink) et reporter l'id de
# l'image contenue dans le Decal dans DizzyDressing.CHAINLINK.
import sys
from PIL import Image, ImageDraw

S, K = 1024, 4  # dessin suréchantillonné x4, puis réduit (fil antialiasé)
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)
step = S // 2
# fil en trois passes : bord sombre, corps, reflet
for width, color in ((40, (120, 124, 126, 255)), (22, (196, 200, 202, 255)), (8, (232, 234, 236, 255))):
    for k in range(-3, 6):
        o = k * step
        draw.line([(o - S, -S), (o + 2 * S, 2 * S)], fill=color, width=width)
        draw.line([(o + S, -S), (o - 2 * S, 2 * S)], fill=color, width=width)
img.resize((S // K, S // K), Image.LANCZOS).save(sys.argv[1])
