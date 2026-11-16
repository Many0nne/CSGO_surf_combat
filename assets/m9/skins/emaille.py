"""ÉMAIL (#420) : émail cloisonné. Le plat de la lame est un champ de vagues en écailles (seigaiha : rangées d'arcs
concentriques qui se recouvrent), chaque anneau d'un émail différent (bleu clair au cœur, cobalt, bleu nuit, crête blanche), séparés par
des cloisons d'or en relief ; un filet d'or encadre le champ en suivant le contour de la lame et le tour du trou. L'émail
est vitreux (brillant, non métallique), un peu plus clair vers la pointe. Fil et dos en acier poli, garde et pommeau en
or, manche bleu nuit.
"""

import numpy as np
from common import fbm, mix, smooth

R = 0.095  # rayon d'une écaille (unités) : cinq à six rangées à la hauteur du talon
BOUNDS = np.array([0.32, 0.55, 0.85, 1.0])  # bords extérieurs des anneaux (fraction de R) : crête fine
WIRE = 0.0055  # largeur d'une cloison d'or
FRAME = (0.016, 0.031)  # filet d'or : distances au bord de la lame (dedans de l'un, dehors de l'autre)
# Émaux du cœur de l'écaille vers sa crête, au talon et à la pointe
ENAMEL_HEEL = np.array([[70, 140, 210], [22, 70, 160], [12, 28, 80], [226, 236, 242]]) / 255
ENAMEL_TIP = np.array([[110, 180, 228], [36, 104, 190], [20, 50, 118], [236, 242, 246]]) / 255
GOLD = np.array([0.92, 0.72, 0.36])
NAVY = np.array([0.06, 0.09, 0.2])


def seigaiha(t, h):
	"""Cette méthode permet de calculer, en chaque point de toile (t, h), l'anneau d'écaille visible (0 cœur à 3
	crête), la distance à la cloison la plus proche (unités) et un identifiant d'écaille."""
	ring = np.zeros(t.shape, np.int32)
	wire = np.full(t.shape, 1.0, np.float32)
	ident = np.zeros(t.shape, np.int32)
	dy = R * 0.5
	rows = np.arange(np.floor(h.min() / dy) - 2, np.ceil(h.max() / dy) + 3)
	# Rangées du haut (dos) vers le bas : une écaille plus basse recouvre le bas de celles du dessus
	for j in rows[::-1]:
		cy = j * dy
		off = R if int(j) % 2 else 0.0
		i = np.round((t - off) / (2 * R))
		cx = i * 2 * R + off
		d = np.hypot(t - cx, h - cy)
		cover = d < R
		k = np.minimum(np.searchsorted(BOUNDS, d / R), len(BOUNDS) - 1)
		# Distance à la frontière d'anneau la plus proche
		edge = np.min(np.abs(d[..., None] - BOUNDS[:-1] * R), -1)
		ring = np.where(cover, k, ring)
		wire = np.where(cover, np.minimum(edge, np.where(d > R - WIRE, R - d, 1.0)), wire)
		ident = np.where(cover, (i.astype(np.int64) * 7919 + int(j) * 104729) % 9973, ident)
	return ring, wire, ident


def paint(kn):
	"""Cette méthode permet d'émailler le plat de la lame en seigaiha cloisonné d'or, de dorer filet, garde et pommeau,
	et de teinter le manche en bleu nuit."""
	m = kn.m
	t, h = kn.grid()
	ring, wire, ident = seigaiha(t, h)
	inner = kn.dist > FRAME[1]
	frame = (kn.dist > FRAME[0]) & ~inner
	gold_wire = inner & (wire < WIRE / 2)
	kn.put("cloison", gold_wire | frame)
	kn.put("émail", inner & ~gold_wire)
	# Couleur d'émail par anneau, plus claire vers la pointe, légèrement variée d'une écaille à l'autre
	g = np.clip((t - (-2.1)) / 2.4, 0, 1)[..., None]  # 0 pointe, 1 talon
	pal = ENAMEL_TIP[ring] * (1 - g) + ENAMEL_HEEL[ring] * g
	jit = ((ident * 0.618) % 1.0)[..., None] * 0.12 - 0.06
	pal = np.clip(pal * (1 + jit), 0, 1)
	for c in range(3):
		kn.put(f"émail{c}", pal[..., c])
	enamel = kn.sample("émail", blur=0.6) * kn.blade
	cloison = kn.sample("cloison", blur=0.6) * kn.blade
	col = np.stack([kn.sample(f"émail{c}", blur=0.0) for c in range(3)], -1)
	# Émail vitreux : nuages de cuisson et fines bulles
	cloud = m.field(lambda p: fbm(p * 7, 3, 51)) * 0.5 + 0.5
	bubbles = smooth(0.55, 0.7, m.field(lambda p: fbm(p * 90, 1, 53)))
	col = col * (0.92 + 0.12 * cloud)[..., None]
	col = mix(col, col * 1.25, bubbles * 0.35)
	kn.paint(enamel, col, 0.2 + 0.06 * bubbles, 0.0, detail=0.05, ao=0.3)
	kn.paint(cloison, GOLD, 0.24, 1.0, detail=0.3, ao=0.4)
	kn.height = kn.height + cloison * 0.6 - enamel * 0.1 * cloud
	kn.edge(0.08)
	hw = kn.guard | kn.pommel
	kn.paint(hw, GOLD * (0.85 + 0.25 * smooth(0.2, 0.8, m.edges))[..., None], 0.28, 1.0, detail=0.6)
	kn.tint_grip(NAVY)
