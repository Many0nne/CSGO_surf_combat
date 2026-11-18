"""BRONZE (#521, rare) : le corps devient une statue de bronze. Mêmes muscles dessinés que MERCURE (son anatomie est
reprise telle quelle, assets/outfits/mercure/mercure.py), métal sombre et chaud, patine vert-de-gris dans les creux
du relief (calculée sur la forme, jamais en taches au hasard), arêtes et sommets des muscles polis plus clairs, comme
une statue que les passants touchent. Cuit par tools/outfits/r15_bake.py (avec --head pour la coque de tête).

Comme pour MERCURE, Roblox ne fait refléter au métal que le ciel : le reflet du bronze est peint dans la couleur
(décor imaginaire vu de face, comme MERCURE, plus doux et chaud), avec un tiers de métal seulement.

Variantes : poli (bronze neuf, doré, sans patine), patine (bronze brun, vert-de-gris dans les creux, saillies polies),
noirci (bronze presque noir, arêtes et sommets dorés).

Coordonnées : espace de la pièce en studs, avant du personnage = -Z, sa gauche = -X (cf. r15_bake.face_coords).
"""

import numpy as np
from r15_bake import TOP, cavity, face_coords, half_sizes, height_of, mercure, muscles, pillow, smoothstep


MERCURE = mercure()
RELIEF = MERCURE.RELIEF
BULGE = MERCURE.BULGE

# Décor imaginaire reflété par le métal, puis par les parties polies (hauteur de la direction réfléchie -> couleur :
# sol, bande sombre sous l'horizon, horizon, ciel, zénith), patine, part de patine et de poli
VARIANTS = {
	"poli": {
		"env": [
			(-1.0, (0.20, 0.09, 0.03)),
			(-0.35, (0.05, 0.022, 0.008)),
			(-0.06, (0.16, 0.075, 0.025)),
			(0.06, (1.0, 0.66, 0.30)),
			(0.4, (0.62, 0.33, 0.12)),
			(1.0, (0.36, 0.18, 0.06)),
		],
		"polish_env": [
			(-1.0, (0.40, 0.22, 0.08)),
			(-0.35, (0.16, 0.08, 0.03)),
			(-0.06, (0.45, 0.26, 0.10)),
			(0.06, (1.0, 0.82, 0.52)),
			(0.4, (0.95, 0.62, 0.28)),
			(1.0, (0.70, 0.42, 0.17)),
		],
		"patina": (0.14, 0.38, 0.29),
		"patina_amount": 0.0,
		"polish_amount": 0.5,
	},
	"patine": {
		"env": [
			(-1.0, (0.09, 0.045, 0.02)),
			(-0.35, (0.022, 0.011, 0.005)),
			(-0.06, (0.07, 0.036, 0.014)),
			(0.06, (0.60, 0.36, 0.15)),
			(0.4, (0.28, 0.15, 0.058)),
			(1.0, (0.16, 0.085, 0.034)),
		],
		"polish_env": [
			(-1.0, (0.30, 0.16, 0.06)),
			(-0.35, (0.10, 0.05, 0.02)),
			(-0.06, (0.30, 0.17, 0.065)),
			(0.06, (1.0, 0.76, 0.42)),
			(0.4, (0.85, 0.52, 0.22)),
			(1.0, (0.58, 0.33, 0.13)),
		],
		"patina": (0.11, 0.32, 0.24),
		"patina_amount": 1.0,
		"polish_amount": 0.9,
	},
	"noirci": {
		"env": [
			(-1.0, (0.03, 0.02, 0.013)),
			(-0.35, (0.006, 0.004, 0.003)),
			(-0.06, (0.02, 0.014, 0.009)),
			(0.06, (0.26, 0.17, 0.08)),
			(0.4, (0.085, 0.058, 0.034)),
			(1.0, (0.05, 0.035, 0.022)),
		],
		"polish_env": [
			(-1.0, (0.32, 0.18, 0.05)),
			(-0.35, (0.10, 0.055, 0.015)),
			(-0.06, (0.34, 0.20, 0.06)),
			(0.06, (1.0, 0.80, 0.40)),
			(0.4, (0.90, 0.56, 0.18)),
			(1.0, (0.60, 0.36, 0.10)),
		],
		"patina": (0.09, 0.22, 0.18),
		"patina_amount": 0.0,
		"polish_amount": 1.0,
	},
}


# Cette méthode permet de donner la part polie d'une arête de bloc (1 sur l'arête verticale, 0 à 0,14 stud) lorsqu'on
# éclaircit les angles que l'on touche : arêtes verticales des faces latérales, tour du dessus des blocs.
def edge_wear(part, face, u, v):
	hu, hv = half_sizes(part, face)
	dist = hu - np.abs(u)
	dist = np.where(face == TOP, np.minimum(dist, hv - np.abs(v)), dist)
	dist = np.where(face == TOP + 1, 1.0, dist)  # dessous : jamais touché
	return 1 - smoothstep(0.0, 0.14, dist)


# Cette méthode permet de donner la surface du bronze en chaque point d'une pièce (relief, métal, rugosité, et les parts
# de patine et de poli lues ensuite par shade) lorsque r15_bake cuit un atlas.
def surface(part, p, n, variant):
	cfg = VARIANTS[variant]
	if part == "Head":
		# coque lisse : poli sur le dessus du crâne, que l'on touche
		top = smoothstep(0.55, 0.95, p[:, 1])
		zeros = np.zeros(len(p))
		return {"height": zeros, "color": np.zeros((len(p), 3)), "metal": 0.35 + zeros, "rough": 0.35 + zeros,
			"patina": zeros, "polish": top * 0.6 * cfg["polish_amount"]}
	face, u, v = face_coords(p, n)
	h = muscles(part, face, u, v)
	legs = "Leg" in part or "Foot" in part
	h = h + pillow(part, face, u, v, vertical=not legs) * BULGE
	cav = cavity(part, face, u, v)
	patina = smoothstep(0.06, 0.3, cav) * cfg["patina_amount"]
	crest = smoothstep(0.55, 1.0, muscles(part, face, u, v) / RELIEF)  # sommet des muscles
	wear = np.maximum(crest, edge_wear(part, face, u, v) * 0.8)
	if "Hand" in part:
		wear = np.maximum(wear, 0.7)  # mains : polies par les poignées de main
	if "Foot" in part:
		wear = np.maximum(wear, smoothstep(0.0, -0.6, p[:, 2]) * 0.6)  # bout des pieds
	polish = wear * cfg["polish_amount"] * (1 - patina)
	metal = 0.35 * (1 - patina)
	rough = 0.35 + patina * 0.5 - polish * 0.1
	return {"height": h, "color": np.zeros((len(u), 3)), "metal": metal, "rough": rough, "patina": patina,
		"polish": polish}


# Cette méthode permet de lire la couleur d'un décor imaginaire dans une direction (sa hauteur y, de -1 à 1) lorsqu'on
# peint le reflet figé du bronze.
def environment(keys_cols, y):
	keys = np.array([k for k, _ in keys_cols])
	cols = np.array([c for _, c in keys_cols])
	return np.stack([np.interp(y, keys, cols[:, i]) for i in range(3)], axis=1)


# Cette méthode permet de peindre dans la couleur le reflet figé du bronze (même regard de face que MERCURE, reflet
# plus doux), puis le poli et la patine, lorsque r15_bake connaît la normale en relief.
def shade(part, p, bumped, s, variant):
	cfg = VARIANTS[variant]
	view = s["geo_normal"]
	nv = np.sum(bumped * view, axis=1, keepdims=True)
	refl = 2 * nv * bumped - view
	up = view[:, 1]
	y = refl[:, 1] * 2.2
	if part == "Head":
		# coque ronde : bandes selon la hauteur de la normale, sans couture (cf. coque de MERCURE)
		y = bumped[:, 1] * 1.3 - 0.1
	elif "Leg" in part or "Foot" in part:
		# jambes : ondulation d'horizon continue d'une pièce à l'autre, comme MERCURE (pas de coupure au genou)
		y = y + 0.16 * np.sin((height_of(part, p) + 2.3) * 2.0)
	if part != "Head":
		y = np.where(np.abs(up) > 0.7, np.sign(up) * (0.6 + 0.4 * np.abs(refl[:, 1])), y)
	y = np.clip(y, -1, 1)
	metal_col = environment(cfg["env"], y)
	polished = environment(cfg["polish_env"], y)
	light = 0.5 + 0.5 * np.clip(bumped[:, 1] * 0.5 + 0.6, 0, 1)
	patina_col = np.array(cfg["patina"])[None] * light[:, None]
	pol = s["polish"][:, None]
	pat = s["patina"][:, None]
	col = metal_col * (1 - pol) + polished * pol
	return col * (1 - pat) + patina_col * pat
