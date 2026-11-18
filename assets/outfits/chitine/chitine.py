"""CHITINE (#521, légendaire) : le corps devient une carapace biomécanique bleu-noir, humide et brillante (hommage à la
créature du film de 1979 et aux planches biomécaniques de son dessinateur, sans en reprendre le crâne, la mâchoire ni
la silhouette). Cuit par tools/outfits/r15_bake.py (avec --head pour la coque de tête).

Variante retenue (18/11/2026, à confirmer par l'utilisateur) : laque, reflets les plus larges, la plus lisible de
loin. Gardées : nervure (relief plus fort, reflet plus fin), irise (reflet cyan-violet).

Structure dessinée, ordonnée et symétrique (rien au hasard) :
- torse : sternum en vertèbres, côtes arquées qui font le tour du buste, clavicules, plaques ventrales en écailles ;
  dos : colonne de vertèbres à apophyses, côtes dorsales et deux tubes qui passent par-dessus les épaules ;
- bras et jambes : plaques à chevrons qui se recouvrent (pointe en bas, comme les côtes), deux câbles devant et un
  sur chaque côté ; mains lisses (pas de doigts dessinés) ;
- coque de tête : dôme lisse, petite crête au sommet et anneaux de nuque, symétrique d'avant en arrière.

Les membres sont dessinés selon la hauteur au-dessus de la racine (`height_of`), et non pièce par pièce : au genou et
au coude, les pièces du rig se recouvrent, et deux dessins différents s'y disputeraient l'affichage.

Brillance humide : Roblox ne reflète que le ciel (cf. MERCURE). `shade` peint donc dans la couleur le reflet d'un
décor fixe (sol noir, bande de lumière au-dessus de l'horizon, deux bandes latérales) sur les flancs des côtes, tubes
et plaques.

Le haut de la face avant et arrière du torse est à la hauteur 1,588 (UpperTorso : centre 0,3176, demi-hauteur
1,2706) : tout motif placé plus haut n'est pas dessiné.

Coordonnées : espace de la pièce en studs, avant du personnage = -Z, sa gauche = -X (cf. r15_bake.face_coords).
"""

import numpy as np
from r15_bake import BACK, FRONT, LEFT, RIGHT, TOP, dome, face_coords, height_of, pillow, smoothstep

# relief : multiplicateur de hauteur ; gain : amplification de la pente du reflet (grand = bande plus nette et plus
# fréquente) ; env : décor peint dans le reflet (cf. ENV_*)
VARIANTS = {
	"laque": {"relief": 0.6, "gain": 0.6, "env": "laque"},
	"nervure": {"relief": 1.25, "gain": 0.9, "env": "laque"},
	"irise": {"relief": 1.25, "gain": 0.9, "env": "irise"},
}

HEAD = True  # coque de tête : mesh de la coque de MERCURE, avec sa propre carte
RELIEF = 0.065  # hauteur d'une côte, d'un tube (studs)
GROOVE = 0.05  # profondeur d'un sillon entre deux plaques
BULGE = 0.10  # bombé de chaque face


# --- Primitives de dessin -------------------------------------------------------------------------------------------


# Cette méthode permet de donner la distance de chaque point à une ligne brisée (liste de points) lorsqu'on trace une
# côte ou un tube qui suit une courbe.
def polyline_distance(u, v, pts):
	best = np.full_like(u, 1e9)
	for (ax, ay), (bx, by) in zip(pts[:-1], pts[1:]):
		dx, dy = bx - ax, by - ay
		t = np.clip(((u - ax) * dx + (v - ay) * dy) / (dx * dx + dy * dy), 0, 1)
		best = np.minimum(best, np.hypot(u - (ax + t * dx), v - (ay + t * dy)))
	return best


# Cette méthode permet de donner le profil parabolique d'un tube (1 sur l'axe, 0 à `width`) lorsqu'on dessine une côte,
# un câble ou une crête : la pente croît régulièrement, le reflet peint forme une ligne nette sur le haut du tube.
def tube(d, width):
	return np.clip(1 - (d / width) ** 2, 0, 1)


# Cette méthode permet de donner le relief d'anneaux bombés réguliers (période `period`) selon une coordonnée `h`
# lorsqu'on segmente un membre ou le ventre ; renvoie (relief de 0 à 1, sillon de 0 à 1).
def plates(h, period, phase=0.0):
	s = np.mod((h - phase) / period, 1.0)
	body = np.sin(np.pi * s) ** 0.6
	edge = np.minimum(s, 1 - s) * period  # distance au sillon (studs)
	groove = 1 - smoothstep(0.0, 0.045, edge)
	return body, groove


# Cette méthode permet de donner les points d'une côte arquée (de `a` à `b`, flèche `arch`) lorsqu'on dessine la cage
# thoracique.
def arc(a, b, arch, n=12):
	t = np.linspace(0, 1, n)
	u = a[0] + (b[0] - a[0]) * t
	v = a[1] + (b[1] - a[1]) * t**1.4 + arch * np.sin(np.pi * t)
	return list(zip(u, v))


# Cette méthode permet de donner le relief d'une vertèbre (dôme elliptique de pente régulière, centré sur le point :
# le reflet peint en éclaire le haut, pas le contour) lorsqu'on dessine le sternum ou la colonne.
def bead(du, dv, ru, rv):
	return dome(du, dv, 0, 0, ru, rv)


# Cette méthode permet de réunir plusieurs reliefs (le plus haut l'emporte) lorsqu'une face en porte plusieurs.
def union(*hs):
	return np.maximum.reduce([np.asarray(h, dtype=np.float64) for h in hs])


# --- Torse ----------------------------------------------------------------------------------------------------------

# Côtes : hauteur au sternum (front), à l'arrière du flanc (back), en hauteur du personnage (height_of)
RIBS = [(1.30, 1.36), (0.92, 0.98), (0.54, 0.60), (0.16, 0.22)]
RIB_DROP_FRONT = 0.42  # descente d'une côte du sternum au bord du buste
RIB_DROP_BACK = 0.30  # descente d'une côte dorsale de la colonne au bord du dos
TUBE_U = 0.95  # écart des tubes dorsaux à l'axe
TUBE_W = 0.16  # demi-largeur des tubes dorsaux
TORSO_HALF = (1.5882, 0.7941)  # demi-largeur et demi-profondeur du torse


# Cette méthode permet de dessiner l'avant du buste (sternum, côtes, clavicules, plaques ventrales) lorsqu'on cuit le
# torse ; `h` est la hauteur du point au-dessus de la racine.
def torso_front(u, h):
	au = np.abs(u)
	ribs = 0 * u
	for front, _ in RIBS:
		pts = arc((0.22, front), (1.62, front - RIB_DROP_FRONT), 0.1)
		ribs = union(ribs, tube(polyline_distance(au, h, pts), 0.13))
	clav = tube(polyline_distance(au, h, [(0.2, 1.5), (0.9, 1.47), (1.62, 1.43)]), 0.1)
	# sternum : vertèbres de 0,3 stud, du col au bas des côtes
	k = np.round((h - 1.45) / 0.3)
	sc = 1.45 + k * 0.3
	stern = np.where((sc <= 1.45) & (sc >= -0.05), bead(u, h - sc, 0.24, 0.135), 0)
	# tubes des épaules : arrivent du dos par le dessus et s'enfoncent sous la clavicule
	shoulder = np.where(h > 1.47, tube(np.abs(au - TUBE_U), TUBE_W), 0)
	# ventre : écailles sous les côtes, deux colonnes séparées par un sillon
	belly_zone = smoothstep(-0.12, -0.32, h) * (1 - smoothstep(0.95, 1.1, au))
	scales, sgroove = plates(h, 0.32, phase=-1.588)
	belly = scales * belly_zone
	mid = 1 - smoothstep(0.0, 0.05, au)
	# flancs du ventre : un câble de chaque côté, jusqu'au bas du bassin
	cable = np.where(h < -0.1, tube(np.abs(au - 1.25), 0.13), 0)
	relief = union(ribs * 1.3, clav * 1.1, stern * 1.2, shoulder * 1.5, belly * 0.8, cable * 1.3)
	groove = union(sgroove * belly_zone, mid * smoothstep(-0.1, -0.3, h))
	return relief, groove


# Cette méthode permet de dessiner le dos (colonne, apophyses, côtes dorsales, tubes) lorsqu'on cuit le torse.
def torso_back(u, h):
	au = np.abs(u)
	k = np.round((h - 1.42) / 0.32)
	vc = 1.42 + k * 0.32
	spine = bead(u, h - vc, 0.3, 0.145)
	process = tube(polyline_distance(au, h - vc, [(0.26, 0.0), (0.56, -0.07)]), 0.075) * 0.9
	ribs = 0 * u
	for _, back in RIBS:
		pts = arc((0.48, back), (1.62, back - RIB_DROP_BACK), 0.08)
		ribs = union(ribs, tube(polyline_distance(au, h, pts), 0.12))
	ribs = ribs * smoothstep(-0.1, 0.1, h)
	tubes = tube(np.abs(au - TUBE_U), TUBE_W) * smoothstep(-1.62, -1.5, h)  # bout arrondi au bas du bassin
	lower = plates(h, 0.32, phase=-1.588)[0] * smoothstep(0.0, -0.2, h) * (1 - smoothstep(0.75, 0.8, au)) * 0.6
	relief = union(spine * 1.4, process, ribs * 1.2, tubes * 1.6, lower)
	return relief, 0 * u


# Cette méthode permet de dessiner un flanc du buste (côtes qui font le tour, de l'avant à l'arrière) lorsqu'on cuit
# le torse ; `w` est la profondeur du point (studs, de -depth à l'avant à +depth à l'arrière).
def torso_side(w, h, depth):
	ribs = 0 * w
	for front, back in RIBS:
		a = (-depth, front - RIB_DROP_FRONT)
		b = (depth, back - RIB_DROP_BACK)
		ribs = union(ribs, tube(polyline_distance(w, h, [a, b]), 0.13))
	scales, sgroove = plates(h, 0.32, phase=-1.588)
	zone = smoothstep(-0.25, -0.45, h)
	return union(ribs * 1.3, scales * zone * 0.7), sgroove * zone


# Cette méthode permet de dessiner le dessus des épaules (tubes dorsaux qui passent vers l'avant) lorsqu'on cuit le
# torse ; `w` est la profondeur du point (studs, négative à l'avant).
def torso_top(u, w):
	au = np.abs(u)
	tubes = tube(np.abs(au - TUBE_U), TUBE_W)
	spine = tube(np.abs(u), 0.18) * smoothstep(-0.2, 0.3, w)
	return union(tubes * 1.5, spine * 0.8), 0 * u


# --- Membres --------------------------------------------------------------------------------------------------------


# Cette méthode permet de dessiner un bras ou une jambe (plaques à chevrons, deux câbles devant, un par côté) lorsqu'on
# cuit un membre ; selon la seule hauteur et la position sur la face, pour continuer d'une pièce à l'autre.
def limb(part, face, u, h):
	leg = "Leg" in part or "Foot" in part
	phase = -4.77 if leg else -1.59
	period = 0.62 if leg else 0.55
	au = np.abs(u)
	frontback = (face == FRONT) | (face == BACK)
	sides = (face == LEFT) | (face == RIGHT)
	chevron = np.where(frontback, h - 0.2 * np.clip(au / 0.7941, 0, 1), h - 0.2)
	s = np.mod((chevron - phase) / period, 1.0)
	plate = smoothstep(0.0, 0.9, s) * (1 - smoothstep(0.93, 1.0, s))  # monte jusqu'à la lèvre, puis le sillon
	groove = 1 - smoothstep(0.0, 0.045, np.minimum(s, 1 - s) * period)
	cable = np.where(face == FRONT, union(tube(np.abs(u - 0.4), 0.12), tube(np.abs(u + 0.4), 0.12)), 0)
	cable = union(cable, tube(au, 0.13) * sides)
	return union(plate * 0.7, cable * 1.3), groove * (cable < 0.05)


# --- Surface --------------------------------------------------------------------------------------------------------


# Cette méthode permet de donner la surface de CHITINE en chaque point d'une pièce (relief, couleur, métal, rugosité)
# lorsque r15_bake cuit un atlas ; `relief` et `groove` servent ensuite à `shade` (creux assombris).
def surface(part, p, n, variant):
	if part == "Head":
		return head(p, variant)
	cfg = VARIANTS[variant]
	face, u, v = face_coords(p, n)
	sides = (face == FRONT) | (face == BACK) | (face == LEFT) | (face == RIGHT)
	if part in ("UpperTorso", "LowerTorso"):
		h = height_of(part, p)
		fr, fg = torso_front(u, h)
		br, bg = torso_back(u, h)
		sr, sg = torso_side(p[:, 2], h, TORSO_HALF[1])
		tr, tg = torso_top(u, p[:, 2])
		masks = [face == FRONT, face == BACK, (face == LEFT) | (face == RIGHT), face == TOP]
		relief = np.select(masks, [fr, br, sr, tr], 0)
		groove = np.select(masks, [fg, bg, sg, tg], 0)
		bulge = pillow(part, face, u, v, vertical=part == "UpperTorso")
	elif "Hand" in part:
		relief, groove = np.zeros_like(u), np.zeros_like(u)
		bulge = pillow(part, face, u, v)
	else:
		relief, groove = limb(part, face, u, height_of(part, p))
		relief = np.where(sides, relief, 0)
		groove = np.where(sides, groove, 0)
		bulge = pillow(part, face, u, v, vertical=False)
	return finish(relief, groove, bulge * BULGE, cfg)


# Cette méthode permet d'assembler relief, sillons et bombé en cartes (hauteur, métal, rugosité) lorsqu'une pièce ou
# la coque est dessinée ; la couleur est peinte ensuite par `shade`.
def finish(relief, groove, bulge, cfg, side_light=0.8):
	groove = np.clip(groove, 0, 1)
	height = (relief * RELIEF - groove * GROOVE) * cfg["relief"] + bulge
	return {
		"height": height,
		"color": np.zeros((len(height), 3)),
		"metal": 0.0 * height,
		"rough": 0.12 + 0.35 * groove,
		"relief": np.clip(relief, 0, 1),
		"groove": groove,
		"side_light": side_light,  # force des bandes latérales du reflet (cf. shade)
	}


# Cette méthode permet de donner la surface de la coque (crête au sommet, anneaux de nuque, symétrique d'avant en
# arrière : l'orientation du mesh n'est pas vérifiée) lorsque r15_bake cuit la coque dans l'espace de la tête.
def head(p, variant):
	x, y = p[:, 0], p[:, 1]
	crest = tube(np.abs(x), 0.13) * smoothstep(0.45, 0.7, y)
	rings, rgroove = plates(y, 0.2, phase=-1.0)
	neck = smoothstep(-0.3, -0.45, y)
	# pas de bandes latérales sur le dôme : ses flancs courbes en faisaient deux traits verticaux, comme un visage
	return finish(union(crest * 1.2, rings * neck * 0.7), rgroove * neck, 0 * x, VARIANTS[variant], side_light=0.0)


# Décor peint dans le reflet de la laque (hauteur de la direction réfléchie -> couleur) : sol noir, horizon bleu nuit,
# une bande de lumière nette au-dessus (la ligne humide qui court sur chaque côte, chaque tube, chaque anneau), puis
# un ciel bleu sombre. Variante irisée : la bande passe du cyan au violet, l'horizon tire sur le violet.
ENV_LAQUE = [
	(-1.0, (0.004, 0.006, 0.012)),
	(-0.1, (0.006, 0.010, 0.022)),
	(0.08, (0.020, 0.036, 0.075)),
	(0.18, (0.045, 0.080, 0.160)),
	(0.24, (0.80, 0.92, 1.00)),
	(0.44, (0.66, 0.82, 1.00)),
	(0.56, (0.060, 0.110, 0.220)),
	(1.0, (0.025, 0.045, 0.095)),
]
ENV_IRISE = [
	(-1.0, (0.006, 0.004, 0.014)),
	(-0.1, (0.016, 0.008, 0.032)),
	(0.08, (0.060, 0.025, 0.110)),
	(0.18, (0.110, 0.050, 0.220)),
	(0.24, (0.62, 0.42, 1.00)),
	(0.34, (0.55, 0.85, 1.00)),
	(0.44, (0.50, 0.95, 0.95)),
	(0.56, (0.040, 0.120, 0.200)),
	(1.0, (0.020, 0.040, 0.090)),
]
ENVS = {"laque": ENV_LAQUE, "irise": ENV_IRISE}


# Cette méthode permet de lire la couleur du décor peint dans une direction (sa hauteur y, de -1 à 1) lorsqu'on peint
# le reflet de la laque.
def environment(y, env):
	keys = np.array([k for k, _ in env])
	cols = np.array([c for _, c in env])
	return np.stack([np.interp(y, keys, cols[:, i]) for i in range(3)], axis=1)


# Cette méthode permet de peindre dans la couleur le reflet humide de la carapace (regard de face, comme MERCURE ; creux
# assombris) lorsque r15_bake connaît la normale en relief.
def shade(part, p, bumped, s, variant):
	cfg = VARIANTS[variant]
	view = s["geo_normal"]
	nv = np.sum(bumped * view, axis=1, keepdims=True)
	refl = 2 * nv * bumped - view
	color = environment(np.clip(refl[:, 1] / cfg["gain"], -1, 1), ENVS[cfg["env"]])
	# bandes latérales (deux lumières verticales de part et d'autre) : les câbles verticaux brillent aussi
	across = np.cross(np.array([0.0, 1.0, 0.0])[None], view)
	across = np.where(np.linalg.norm(across, axis=1, keepdims=True) < 0.5, np.array([1.0, 0.0, 0.0])[None], across)
	across /= np.linalg.norm(across, axis=1, keepdims=True)
	lat = np.abs(np.sum(refl * across, axis=1)) / cfg["gain"]
	# seuil au-dessus de la pente du bombé des faces (0,55 au bord d'un membre) : seuls les flancs raides s'allument
	side = smoothstep(0.62, 0.7, lat) * (1 - smoothstep(0.9, 1.0, lat)) * s["side_light"]
	band = environment(np.full_like(lat, 0.3), ENVS[cfg["env"]])
	color = np.maximum(color, band * side[:, None])
	occlusion = (0.55 + 0.45 * s["relief"]) * (1 - 0.9 * s["groove"])
	return np.clip(color * occlusion[:, None], 0, 1)
