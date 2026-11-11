"""Exporte toutes les frames d'une animation pour studio_render.luau, affiche ses vitesses de rotation et contrôle le
profil du geste contre la grammaire mesurée sur CS:GO (docs/animations.md, « Grammaire des gestes de couteau »).

À lancer sans toucher au Blender ouvert :
  blender -b --factory-startup --python tools/anim/dump_frames.py -- <dossier_build_viewmodel> <Animation> <sortie.json> [archétype]

Le tableau de vitesses se lit avant tout rendu : une rotation propre monte puis redescend, sans creux ni pic isolé, et
une main qui tient un couteau en rotation doit rester à 0. Le bilan GRAMMAIRE qui suit compare le geste (départ, pic de
vitesse, durée de la frappe, temps hors cadre, retour au repos, profondeur) aux cibles de son archétype : `taille`,
`estoc`, `equip` ou `inspect`, déduit du nom de l'animation si l'argument est absent. Chaque ligne « ÉCART » est à
corriger avant tout rendu, ou à justifier dans la PR.
"""

import json
import math
import os
import sys

from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1 :]
asset_dir, anim, out_path = args[:3]
archetype_arg = args[3] if len(args) > 3 else None
ns = {"__name__": "lib", "ASSET_DIR": asset_dir}
with open(os.path.join(asset_dir, "build_viewmodel.py"), encoding="utf-8") as fh:
	exec(fh.read(), ns)
to_cf, GRIP, FPS = ns["to_cf"], ns["GRIP"], ns["FPS"]
spec = ns["SPECS"][anim]()
ts, frames = ns["sample"](spec)

# La Handle du script est le centre du manche ; studio_render.luau la recale sur le mesh réel via la main virtuelle.
data = {}
for i, f in enumerate(frames):
	data[f"{anim}_{i:03d}"] = {
		name: [round(v, 5) for v in to_cf(m @ GRIP.inverted() if name == "Handle" else m)] for name, m in f.items()
	}
with open(out_path, "w", encoding="utf-8") as fh:
	json.dump(data, fh)


# Cette méthode permet de projeter un point du repère caméra à l'écran, en unités de demi-hauteur d'écran (FOV 90°).
def project(point):
	return point.x / -point.z, point.y / -point.z


print(" temps  lame  d_lame  d_main   (degrés par 1/30 s)")
total = previous = last_blade = last_hand = None
for i, (t, f) in enumerate(zip(ts, frames, strict=True)):
	knife, hand = f["Handle"], f["RightHand"]
	a, b = project(knife @ Vector((0, 0, -0.65))), project(knife @ Vector((0, 0, 3.07)))
	angle = math.degrees(math.atan2(b[0] - a[0], b[1] - a[1]))
	total = angle if total is None else total + ((angle - previous + 180) % 360 - 180)
	previous = angle
	if i % 2 == 0:
		q = hand.to_3x3().to_quaternion()
		turn = math.degrees(last_hand.rotation_difference(q).angle) if last_hand else 0.0
		print(f"{t:6.2f} {total:5.0f} {total - (last_blade if last_blade is not None else total):7.1f} {min(turn, 360 - turn):7.1f}")
		last_blade, last_hand = total, q
print(f"OK {len(data)} frames -> {out_path}")


# ------------------------------------------------------------------------------------------------
# Bilan de grammaire
# ------------------------------------------------------------------------------------------------

ASPECT = 16 / 9
MOVE = 0.15  # écart au repos de la main (studs) en dessous duquel elle est considérée immobile
SLOW = 0.3  # vitesse de la main (studs/s) en dessous de laquelle elle est considérée à l'arrêt

# Cibles par archétype, mesurées sur le couteau CT de CS:GO (docs/animations.md) : (minimum, maximum) en secondes,
# rapport pour la profondeur. La taille est coupée par la cadence en jeu (FireDelay), d'où sa durée minimale courte.
RULES = {
	"taille": {
		"anticipation": (None, 0.25),
		"frappe": (None, 0.12),
		"hors cadre": (0.20, None),
		"retour": (None, 1.50),
		"profondeur": (1.20, None),
		"durée": (0.40, 1.70),
	},
	"estoc": {
		"anticipation": (None, 0.20),
		"frappe": (None, 0.20),
		"retour": (None, 0.90),
		"profondeur": (1.20, None),
		"durée": (0.70, 1.30),
	},
	"equip": {
		"retour": (None, 0.80),
		"durée": (0.40, 1.70),
	},
	"inspect": {
		"montée": (None, 0.70),
		"descente": (None, 0.70),
		"durée": (4.00, 11.00),
	},
}


# Cette méthode permet de déduire l'archétype d'un geste depuis le nom de l'animation lorsque l'argument n'est pas donné.
def guess_archetype(name):
	n = name.lower()
	for key, arch in (("shoot", "taille"), ("slash", "taille"), ("stab", "estoc"), ("equip", "equip"), ("draw", "equip"), ("inspect", "inspect")):
		if key in n:
			return arch
	return None


# Cette méthode permet de nommer le bord du cadre par lequel la main sort ou rentre (pour vérifier qu'on ne revient pas
# par où on est sorti), depuis sa position écran en demi-hauteurs.
def side(p):
	x, y = p
	v = "haut" if y > 1 else "bas" if y < -1 else ""
	h = "droite" if x > ASPECT else "gauche" if x < -ASPECT else ""
	return "-".join(s for s in (v, h) if s) or "?"


# Cette méthode permet de mesurer le profil d'un geste (départ, pic, frappe, hors cadre, retour, profondeur, pauses)
# à partir du mouvement 3D de la main (studs, insensible aux sorties de cadre) et de sa position à l'écran.
def profile():
	pos = [f["RightHand"].translation for f in frames]
	depth = [-p.z for p in pos]
	dist = [(p - pos[0]).length for p in pos]
	dist_end = [(p - pos[-1]).length for p in pos]
	visible = [d > 0 and abs(x) <= ASPECT and abs(y) <= 1 for (x, y), d in zip((project(p) for p in pos), depth, strict=True)]
	# vitesse vue par le joueur : un déplacement entièrement hors cadre, ou une rentrée dans le cadre, est une apparition
	# et pas un mouvement (le rig peut s'y téléporter sans que rien ne se voie)
	speed = [0.0] + [
		(pos[i] - pos[i - 1]).length * FPS if visible[i - 1] else 0.0 for i in range(1, len(pos))
	]

	start = next((i for i, d in enumerate(dist) if d > MOVE), None)
	peak = max(range(len(speed)), key=lambda i: speed[i])
	half = speed[peak] / 2
	lo = hi = peak
	while lo > 0 and speed[lo - 1] > half:
		lo -= 1
	while hi < len(speed) - 1 and speed[hi + 1] > half:
		hi += 1
	settle = max((i for i, d in enumerate(dist_end) if d > MOVE), default=peak)
	# dernier mouvement franc avant le repos final : ce qui reste est la descente
	last_fast = max((i for i in range(settle + 1) if speed[i] > max(SLOW, speed[peak] * 0.3)), default=settle)
	# fin de la montée : première accalmie après le départ
	rise_end = None
	if start is not None:
		rise_end = next((i for i in range(start, len(speed)) if speed[i] < SLOW and dist[i] > MOVE), None)

	out_frames = [i for i, v in enumerate(visible) if not v]
	exits = ""
	if out_frames:
		first, last = out_frames[0], out_frames[-1]
		exits = f"sortie {side(project(pos[first]))}"
		if last < len(pos) - 1:
			exits += f", retour {side(project(pos[last]))}"
			if side(project(pos[first])) == side(project(pos[last])):
				exits += " (même côté)"
		else:
			exits += ", finit hors cadre"

	# arrêt avant la frappe : la main retombe à l'arrêt entre le départ et le pic
	stop = None
	if start is not None:
		running = 0.0
		for i in range(start, peak):
			running = max(running, speed[i])
			if running > 2.0 and speed[i] < SLOW and visible[i] and visible[i - 1]:
				stop = ts[i]
				break

	return {
		"départ": ts[start] if start is not None else None,
		"pic": ts[peak],
		"vitesse": speed[peak],
		"anticipation": (ts[peak] - ts[start]) if start is not None else None,
		"frappe": (hi - lo + 1) / FPS,
		"hors cadre": len(out_frames) / FPS,
		"retour": ts[settle] - ts[peak],
		"descente": ts[settle] - ts[last_fast],
		"montée": (ts[rise_end] - ts[start]) if rise_end is not None else None,
		"profondeur": max(depth) / min(depth) if min(depth) > 0 else None,
		"durée": ts[-1],
		"sorties": exits,
		"arrêt": stop,
	}


archetype = archetype_arg or guess_archetype(anim)
if spec.get("loop") or archetype is None:
	print(f"GRAMMAIRE : pas de contrôle pour {anim} (boucle ou archétype inconnu ; archétypes : {', '.join(RULES)})")
else:
	m = profile()

	# Cette méthode permet d'afficher une durée du bilan, ou un tiret lorsqu'elle n'a pas pu être mesurée.
	def fmt(v):
		return "-" if v is None else f"{v:.2f} s"

	print(
		f"GRAMMAIRE {archetype} : départ {fmt(m['départ'])}, pic {fmt(m['pic'])} ({m['vitesse']:.1f} studs/s), "
		f"frappe {fmt(m['frappe'])}, montée {fmt(m['montée'])}, hors cadre {fmt(m['hors cadre'])}"
		f"{' (' + m['sorties'] + ')' if m['sorties'] else ''}, retour au repos {fmt(m['retour'])} après le pic, "
		f"descente {fmt(m['descente'])}, profondeur ×{m['profondeur']:.2f}, durée {fmt(m['durée'])}"
	)
	gaps = 0
	for key, (lo, hi) in RULES[archetype].items():
		v = m.get(key)
		if v is None:
			continue
		unit = "" if key == "profondeur" else " s"
		if lo is not None and v < lo:
			print(f"GRAMMAIRE ÉCART {key} {v:.2f}{unit} < {lo:.2f}{unit}")
			gaps += 1
		if hi is not None and v > hi:
			print(f"GRAMMAIRE ÉCART {key} {v:.2f}{unit} > {hi:.2f}{unit}")
			gaps += 1
	if archetype in ("taille", "estoc"):
		# l'estoc de référence plonge sous le cadre et en revient : seule la taille change de côté
		if archetype == "taille" and m["sorties"].endswith("(même côté)"):
			print("GRAMMAIRE ÉCART la main revient par le côté où elle est sortie")
			gaps += 1
		if m["arrêt"] is not None:
			print(f"GRAMMAIRE ÉCART arrêt avant la frappe à {m['arrêt']:.2f} s (clé à vitesse nulle au milieu du geste)")
			gaps += 1
	print(f"GRAMMAIRE {'OK' if gaps == 0 else str(gaps) + ' écart(s)'} ({archetype})")
