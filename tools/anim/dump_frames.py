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
HOLD = 1.0  # vitesse (studs/s) d'une pose tenue qui dérive lentement (le couteau CT monte encore pendant sa tenue)
HOLD_TIME = 0.15  # durée (s) sous HOLD qui marque une tenue : un creux d'une image au milieu d'un geste n'en est pas une
TWIST_MAX = 200  # amplitude (degrés) de la torsion de l'avant-bras : pronation et supination font ≈ 180° à elles deux

# Cibles par archétype, mesurées sur le couteau CT de CS:GO (docs/animations.md) : (minimum, maximum) en secondes,
# rapport pour la profondeur. La taille est coupée par la cadence en jeu (FireDelay), d'où sa durée minimale courte.
# Estoc du CT, mesuré par ce script sur ses trajectoires : le pic est le saut d'une image vers l'armé (≈ 68 studs/s,
# frappe 0,03 s), hors cadre 0,37 s, retour au repos 0,98 s après ce pic, profondeur ×2,0 (gant 1,5 fois plus petit).
# Inspect du CT : montée 0,55 s avant la tenue qui monte lentement, descente 0,5 s ; la durée couvre aussi la M9 (10,3 s).
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
		"frappe": (None, 0.10),
		"hors cadre": (0.20, None),
		"retour": (None, 1.00),
		"profondeur": (1.40, None),
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
	# tenues : images où la main reste sous HOLD pendant au moins HOLD_TIME (une pose qui dérive lentement en est une)
	span = max(1, round(HOLD_TIME * FPS))
	held = [i + span <= len(speed) and all(v < HOLD for v in speed[i : i + span]) for i in range(len(speed))]
	# fin de la montée : première tenue après le départ, loin du repos
	rise_end = None
	if start is not None:
		rise_end = next((i for i in range(start, len(speed)) if held[i] and dist[i] > MOVE), None)
	# début de la descente : fin de la dernière tenue avant le repos final
	last_hold = max((i for i in range(settle) if held[i] and dist_end[i] > MOVE), default=None)
	last_fast = last_hold + span if last_hold is not None else settle

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
		"descente": ts[settle] - ts[min(last_fast, settle)],
		"montée": (ts[rise_end] - ts[start]) if rise_end is not None else None,
		"profondeur": max(depth) / min(depth) if min(depth) > 0 else None,
		"durée": ts[-1],
		"sorties": exits,
		"arrêt": stop,
		"torsion": twist_range(),
	}


# Cette méthode permet de mesurer l'amplitude (degrés) de la torsion de l'avant-bras sur tout le geste, lorsqu'on vérifie
# qu'un roulis de la lame reste faisable par un poignet : rotation de la main autour de son axe +Y (vers le coude), cumulée
# d'une image à l'autre (une décomposition par rapport à la première image diverge quand la main pivote de plus de 90°).
def twist_range():
	total = low = high = 0.0
	for prev, cur in zip(frames, frames[1:]):
		q = prev["RightHand"].to_3x3().to_quaternion().inverted() @ cur["RightHand"].to_3x3().to_quaternion()
		sign = 1 if q.w >= 0 else -1  # q et -q sont la même rotation : prendre le plus court chemin
		total += math.degrees(2 * math.atan2(sign * q.y, sign * q.w))
		low, high = min(low, total), max(high, total)
	return high - low


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
		f"descente {fmt(m['descente'])}, profondeur ×{m['profondeur']:.2f}, torsion {m['torsion']:.0f}°, durée {fmt(m['durée'])}"
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
	if m["torsion"] > TWIST_MAX:
		print(f"GRAMMAIRE ÉCART torsion de l'avant-bras {m['torsion']:.0f}° > {TWIST_MAX}° (tour du couteau dans la main)")
		gaps += 1
	if archetype in ("taille", "estoc"):
		# le CT sort toujours par le bas (coin ou centre) ; il revient par le bas, au centre ou par le même coin
		if not m["sorties"].startswith("sortie bas"):
			print(f"GRAMMAIRE ÉCART la main ne sort pas du cadre par le bas ({m['sorties'] or 'reste dans le cadre'})")
			gaps += 1
		if m["arrêt"] is not None:
			print(f"GRAMMAIRE ÉCART arrêt avant la frappe à {m['arrêt']:.2f} s (clé à vitesse nulle au milieu du geste)")
			gaps += 1
	print(f"GRAMMAIRE {'OK' if gaps == 0 else str(gaps) + ' écart(s)'} ({archetype})")
