"""PORCELAINE (#521, rare) : le corps devient une figurine de porcelaine. Mêmes muscles dessinés que MERCURE (anatomie
reprise de assets/outfits/mercure/mercure.py), blanc laiteux brillant, décor peint au bleu de cobalt **ordonné** :
filets qui suivent les blocs, frises de rinceaux aux articulations, chaînes de quatre-feuilles sur les jambes, anneaux sur la coque de tête.
Aucune craquelure ni motif tiré au hasard. Cuit par tools/outfits/r15_bake.py (avec --head pour la coque de tête).

Porcelaine = vernis non métallique : Roblox l'éclaire bien (reflet du soleil, relief par la normal map). La couleur
ne porte qu'un modelé léger (lumière douce au-dessus du regard, creux à peine bleutés) pour que le relief reste
lisible sous un ciel plat.

Variantes : filets (blanc pur à doubles filets bleus), dense (filets, frises de rinceaux, quatre-feuilles),
or (blanc et or : liserés dorés aux arêtes, bracelets dorés).

Coordonnées : espace de la pièce en studs, avant du personnage = -Z, sa gauche = -X (cf. r15_bake.face_coords).
"""

import numpy as np
from r15_bake import BOTTOM, OFFSETS, PARTS, TOP, cavity, face_coords, half_sizes, height_of, mercure, muscles, pillow, smoothstep


MERCURE = mercure()
RELIEF = MERCURE.RELIEF
BULGE = MERCURE.BULGE * 0.8
AA = 0.008  # demi-largeur de l'anticrénelage d'un trait (studs)

GLAZE = np.array([0.97, 0.975, 0.98])  # blanc laiteux
SHADOW = np.array([0.70, 0.74, 0.84])  # creux du vernis, bleutés
COBALT = np.array([0.03, 0.075, 0.42])
GOLD = np.array([0.92, 0.64, 0.22])

VARIANTS = {
	"filets": {"frame": True, "frieze": False, "chain": False, "gold": False},
	"dense": {"frame": True, "frieze": True, "chain": True, "gold": False},
	"or": {"frame": False, "frieze": False, "chain": False, "gold": True},
}


# Cette méthode permet de donner l'intensité d'un trait net (1 à moins de `half` du centre, anticrénelé) lorsqu'on
# peint un filet ou un motif à partir d'une distance.
def stroke(dist, half):
	return np.clip((half - np.abs(dist)) / AA + 0.5, 0, 1)


# Cette méthode permet de peindre une feuille (goutte elliptique de 0,021 × 0,039 stud, bord anticrénelé en studs)
# centrée en (du, dv) lorsqu'une frise de rinceaux pose ses feuilles aux crêtes.
def leaf(du, dv):
	e = np.hypot(du / 0.03, dv / 0.055)
	return np.clip((0.7 - e) * 0.03 / AA + 0.5, 0, 1)


# Cette méthode permet de peindre une frise de rinceaux (tige ondulée, volutes, feuilles) centrée sur `vc` lorsqu'une
# articulation reçoit sa frise ; un nombre pair d'ondes par face la raccorde d'une face à l'autre.
def rinceau(u, v, hu, vc, amp):
	waves = 2 * np.maximum(np.round(hu / 0.26), 1)
	period = 2 * hu / waves
	k = 2 * np.pi / period
	phase = np.cos(k * u)
	stem_v = vc + amp * phase
	slope = amp * k * np.sin(k * u)
	stem = stroke((v - stem_v) / np.sqrt(1 + slope**2), 0.02)
	# volutes : un cercle ouvert entre deux crêtes, au-dessus puis au-dessous de la tige
	local = np.mod(u, period)
	curls = np.zeros_like(u)
	for frac, sign in ((0.25, 1), (0.75, -1)):
		cu = frac * period
		cv = vc + sign * amp * 0.25
		r = amp * 0.62
		d = np.hypot(local - cu, v - cv)
		ring = stroke(d - r, 0.017)
		ang = np.arctan2((v - cv) * sign, local - cu)
		opening = (ang < -0.35) & (ang > -2.0)  # la volute s'ouvre vers la tige
		curls = np.maximum(curls, np.where(opening, 0, ring))
		curls = np.maximum(curls, stroke(d, r * 0.28))  # bouton au centre
	# feuilles : une goutte à chaque crête de la tige, tournée vers l'extérieur
	crest = np.mod(u + period / 2, period) - period / 2
	leaf_top = leaf(crest, v - (vc + amp + 0.05))
	crest2 = np.mod(u, period) - period / 2
	leaf_bot = leaf(crest2, v - (vc - amp - 0.05))
	return np.maximum.reduce([stem, curls, leaf_top, leaf_bot])


# Cette méthode permet de peindre un bracelet de frise à la hauteur `vc` (bande cobalt pleine, rinceaux réservés en
# blanc, un filet de part et d'autre) lorsqu'une pièce porte une frise ; `amp` règle la hauteur des ondes. Une bande
# pleine se lit encore de loin, là où des traits fins disparaîtraient.
def frieze(u, v, hu, vc, amp):
	border = amp + 0.12
	band = stroke(v - vc, border)
	lines = np.maximum(stroke(v - (vc + border + 0.05), 0.014), stroke(v - (vc - border - 0.05), 0.014))
	return np.maximum(lines, band * (1 - rinceau(u, v, hu, vc, amp)))


# Cette méthode permet de peindre une chaîne verticale de quatre-feuilles au milieu d'une face lorsqu'une jambe reçoit
# le décor dense : motifs entiers, au même pas, centrés entre les hauteurs `h0` et `h1` du membre, reliés par une tige.
def chain(u, height, h0, h1, pitch=0.65):
	size = 0.18  # demi-hauteur d'un quatre-feuilles
	count = np.floor((h1 - h0 - 2 * size) / pitch) + 1
	first = (h0 + h1) / 2 - (count - 1) * pitch / 2
	k = np.clip(np.round((height - first) / pitch), 0, count - 1)
	local = height - (first + k * pitch)
	lobes = np.zeros_like(u)
	r = 0.08
	for du, dv in ((0.09, 0), (-0.09, 0), (0, 0.09), (0, -0.09)):
		lobes = np.maximum(lobes, stroke(np.hypot(u - du, local - dv) - r, 0.018))
	motif = np.maximum(lobes, stroke(np.hypot(u, local), 0.04))
	between = (height > first) & (height < first + (count - 1) * pitch) & (np.abs(local) > 0.17)
	return np.maximum(motif, stroke(u, 0.014) * between)


# Cette méthode permet de donner le haut et le bas d'un membre (hauteurs au-dessus de la racine, rig au repos) lorsqu'on
# peint son décor d'un seul tenant ; None pour le torse.
def limb_span(part):
	if "Arm" in part or "Hand" in part:
		return OFFSETS["UpperArm"] + PARTS["LeftUpperArm"][1][1] / 2, OFFSETS["Hand"] - PARTS["LeftHand"][1][1] / 2
	if "Leg" in part or "Foot" in part:
		return OFFSETS["UpperLeg"] + PARTS["LeftUpperLeg"][1][1] / 2, OFFSETS["Foot"] - PARTS["LeftFoot"][1][1] / 2
	return None


# Cette méthode permet de donner les frises d'une pièce (hauteur du centre au-dessus de la racine, amplitude des ondes)
# lorsqu'on peint le décor dense : col et ceinture, haut des bras et poignets, haut des cuisses et chevilles.
def frieze_rows(part):
	if part == "UpperTorso":
		return [(OFFSETS["UpperTorso"] + PARTS["UpperTorso"][1][1] / 2 - 0.3, 0.07)]
	if part == "LowerTorso":
		return [(OFFSETS["LowerTorso"], 0.07)]
	span = limb_span(part)
	if span is None:
		return []
	top, bottom = span
	if "Arm" in part or "Hand" in part:
		return [(top - 0.3, 0.07), (-0.89, 0.07)]  # poignet : sur l'avant-bras seul, sous le recouvrement du coude
	return [(top - 0.3, 0.07), (bottom + 0.62, 0.07)]


# Cette méthode permet de peindre le décor d'une face (part de cobalt, part d'or) selon la variante lorsque r15_bake
# cuit une pièce du corps. Bras et jambes sont peints d'un seul tenant, selon la hauteur au-dessus de la racine : leurs
# pièces se recouvrent aux articulations (faces confondues, cf. docs/assets.md), et y peignent ainsi le même dessin.
def decor(part, face, u, v, height, cfg):
	hu, hv = half_sizes(part, face)
	sides = face < TOP
	span = limb_span(part)
	edge_local = np.minimum(hu - np.abs(u), hv - np.abs(v))
	if span is not None:
		top, bottom = span
		edge = np.where(sides, np.minimum.reduce([hu - np.abs(u), top - height, height - bottom]), edge_local)
	else:
		edge = edge_local
	edge = np.where(face == BOTTOM, 9.0, edge)  # dessous des blocs : rien
	blue = np.zeros_like(u)
	gold = np.zeros_like(u)
	if cfg["frame"]:
		blue = np.maximum.reduce([blue, stroke(edge - 0.07, 0.026), stroke(edge - 0.14, 0.011)])
	if cfg["frieze"]:
		for hc, amp in frieze_rows(part):
			blue = np.maximum(blue, np.where(sides, frieze(u, height, hu, hc, amp), 0))
	if cfg["chain"] and span is not None and "Leg" in part:
		top, bottom = span
		h0, h1 = bottom + 0.62 + 0.25, top - 0.3 - 0.25
		blue = np.maximum(blue, np.where(sides & (height > h0) & (height < h1), chain(u, height, h0, h1), 0))
	if cfg["gold"]:
		# liseré doré le long des arêtes, bracelets (bande et filet) aux poignets et chevilles, ceinture, col
		gold = np.maximum(gold, stroke(edge - 0.045, 0.035))
		bands = [(hc, 0.07) for hc, _ in frieze_rows(part)[1:]] if span is not None else []
		if part == "LowerTorso":
			bands = [(OFFSETS["LowerTorso"], 0.09)]
		if part == "UpperTorso":
			bands = [(OFFSETS["UpperTorso"] + PARTS["UpperTorso"][1][1] / 2 - 0.22, 0.05)]
		for hc, half in bands:
			ring = stroke(height - hc, half)
			if span is not None:
				ring = np.maximum(ring, stroke(height - hc - 0.16, 0.018))
			gold = np.maximum(gold, np.where(sides, ring, 0))
	return blue, gold


# Cette méthode permet de peindre le décor de la coque de tête lorsque r15_bake la cuit : des anneaux seulement,
# selon la hauteur (la bande du milieu du visage de la coque lit toute la largeur de la carte, cf. r15_bake.load_head).
def head_decor(p, cfg):
	y = p[:, 1]
	blue = np.zeros(len(p))
	gold = np.zeros(len(p))
	if cfg["frame"] and not cfg["frieze"]:
		blue = np.maximum.reduce([blue, stroke(y + 0.5, 0.026), stroke(y + 0.6, 0.011)])
	if cfg["frieze"]:
		# bandeau cobalt plein, deux filets réservés en blanc, un filet de part et d'autre
		band = stroke(y + 0.32, 0.15) * (1 - np.maximum(stroke(y + 0.25, 0.012), stroke(y + 0.39, 0.012)))
		blue = np.maximum.reduce([blue, band, stroke(y + 0.53, 0.014), stroke(y + 0.11, 0.014)])
	if cfg["gold"]:
		gold = np.maximum.reduce([gold, stroke(y + 0.5, 0.06), stroke(y + 0.64, 0.018)])
	return blue, gold


# Cette méthode permet de donner la surface de la porcelaine en chaque point d'une pièce (relief, couleur de base,
# métal, rugosité, parts de décor lues ensuite par shade) lorsque r15_bake cuit un atlas.
def surface(part, p, n, variant):
	cfg = VARIANTS[variant]
	if part == "Head":
		blue, gold = head_decor(p, cfg)
		h = np.zeros(len(p))
		cav = np.zeros(len(p))
	else:
		face, u, v = face_coords(p, n)
		legs = "Leg" in part or "Foot" in part
		h = muscles(part, face, u, v) + pillow(part, face, u, v, vertical=not legs) * BULGE
		cav = cavity(part, face, u, v)
		blue, gold = decor(part, face, u, v, height_of(part, p), cfg)
	gold = np.clip(gold, 0, 1)
	blue = np.clip(blue, 0, 1) * (1 - gold)
	return {
		"height": h,
		"color": np.zeros((len(p), 3)),
		"metal": gold * 0.6,
		"rough": 0.14 + gold * 0.16 + blue * 0.04,
		"blue": blue,
		"gold": gold,
		"cavity": smoothstep(0.04, 0.3, cav),
	}


# Cette méthode permet de peindre la couleur de la porcelaine (vernis blanc au modelé léger, creux bleutés, décor
# cobalt sous le vernis, or poli) lorsque r15_bake connaît la normale en relief.
def shade(part, p, bumped, s, variant):
	view = s["geo_normal"]
	light_dir = view * 0.75 + np.array([0.0, 0.66, 0.0])[None]
	light_dir /= np.linalg.norm(light_dir, axis=1, keepdims=True)
	diffuse = np.clip(np.sum(bumped * light_dir, axis=1), 0, 1)
	if part == "Head":
		diffuse = np.clip(0.75 + 0.25 * bumped[:, 1], 0, 1)
	model = (0.8 + 0.2 * diffuse)[:, None]
	shadow = s["cavity"][:, None] * 0.6
	glaze = GLAZE[None] * (1 - shadow) + SHADOW[None] * shadow
	white = glaze * model
	blue = COBALT[None] * (0.8 + 0.2 * diffuse)[:, None]
	gold = GOLD[None] * (0.45 + 0.75 * diffuse**2)[:, None]
	b = s["blue"][:, None]
	g = s["gold"][:, None]
	return white * (1 - b - g) + blue * b + gold * g
