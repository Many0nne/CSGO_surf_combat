# Génère src/client/systems/game/MenuMirrorsData.luau depuis les sorties de mirrors.py --export (#112) :
# caméra, salle, lumières, et pour chaque éclat (AWP, M9, vides) son point d'attache, son retard de vague, sa teinte
# et son liseré. Positions en studs, relatives à l'origine de la scène du menu.
# Usage : python tools/menu/make_luau.py [dossier des exports]   (défaut : $MENU_OUT ou .maquettes/menu-miroirs)
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("MENU_OUT", os.path.join(ROOT, ".maquettes", "menu-miroirs"))
DEST = os.path.join(ROOT, "src", "client", "systems", "game", "MenuMirrorsData.luau")
WEAPONS = ["AWP", "M9"]


# Cette méthode permet d'écrire un vecteur JSON en Vector3 Luau.
def v3(p):
    return "Vector3.new(%s, %s, %s)" % tuple(("%.4f" % c).rstrip("0").rstrip(".") for c in p)


# Cette méthode permet d'écrire la table des éclats d'un jeu (nom -> attache, retard, teinte, liseré).
def shards(entries, indent="\t\t"):
    lines = []
    for s in entries:
        lines.append(
            '%s%s = { pivot = %s, delay = %s, tint = %s, irise = %s },'
            % (indent, s["name"], v3(s["pivot"]), s.get("delay", 0), s["tint"], "true" if s["irise"] else "false")
        )
    return "\n".join(lines)


def load(path):
    with open(os.path.join(SRC, path), encoding="utf-8") as f:
        return json.load(f)


layout = load("layout.json")
published = json.load(open(os.path.join(HERE, "published.json"), encoding="utf-8"))
cam = layout["camera"]
out = [
    "-- Généré par tools/menu/make_luau.py depuis tools/menu/mirrors.py --export : ne pas modifier à la main.",
    "-- Données de la salle des miroirs du menu (#112), en studs, relatives à l'origine de la scène.",
    "-- stylua: ignore",
    "return {",
    "\tcamera = { position = %s, target = %s, verticalFov = %s, aspectRef = 16 / 9 }," % (
        v3(cam["position"]), v3(cam["target"]), cam["verticalFov"]),
    "\troom = {",
]
for r in layout["room"]:
    out.append('\t\t{ name = "%s", size = %s, position = %s, yaw = %s },' % (r["name"], v3(r["size"]), v3(r["position"]), r["yaw"]))
out.append("\t},")
out.append("\tlights = {")
for l in layout["lights"]:
    out.append('\t\t{ name = "%s", position = %s, target = %s, color = Color3.fromHex("%s"), shadow = %s },' % (
        l["name"], v3(l["position"]), v3(l["target"]), l["color"], "true" if l["shadow"] else "false"))
out.append("\t},")
out.append('\tweapons = { "%s" },' % '", "'.join(WEAPONS))
out.append("\tassets = {")
for w in WEAPONS:
    p = published[w]
    out.append('\t\t%s = { model = %s, atlas = "rbxassetid://%s", mask = "rbxassetid://%s" },' % (
        w, p["model"], p["atlas"], p["mask"]))
out.append('\t\tVides = { model = %s, atlas = "rbxassetid://%s" },' % (published["Vides"]["model"], published["Vides"]["glass"]))
out.append("\t},")
out.append("\tsets = {")
for w in WEAPONS:
    out.append("\t\t%s = {" % w)
    out.append(shards(load(os.path.join(w, "eclats.json"))["shards"], "\t\t\t"))
    out.append("\t\t},")
out.append("\t\tVides = {")
out.append(shards(load("vides.json")["shards"], "\t\t\t"))
out.append("\t\t},")
out.append("\t},")
out.append("}")
with open(DEST, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(out) + "\n")
print("écrit", DEST)
