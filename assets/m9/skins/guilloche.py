"""GUILLOCHÉ (rare) : acier guilloché comme un cadran de montre. Le plat de la lame est gravé de sillons en vagues
régulières qui filent le long de l'axe jusqu'à la pointe, sous un émail translucide grenat : le fond du sillon
reste sombre, ses flancs renvoient la lumière à travers l'émail. Au talon, un médaillon d'argent nu guilloché en rosace
(anneaux ondulés, douze ondes par tour, l'ondulation grandissant vers le bord) cerclé d'un filet d'argent ; un autre
filet d'argent suit le contour de la lame. Fil repoli, garde et pommeau en argent poli, manche d'origine noir.

`GUILLOCHE_ENAMEL=nuit` (variable d'environnement) peint la variante bleu nuit écartée, pour comparer sur une planche.
"""

import os

import numpy as np
from common import fbm, smooth

PITCH = 0.028  # écart entre deux sillons du champ (unités) : ~6 texels, plus serré le motif crénelle
WAVE = (0.11, 0.011)  # vagues du champ : longueur d'onde le long de l'axe, amplitude (unités)
# Médaillon du talon : centre (t, h) sur le ricasso, rayon. Centré à t 0,04 il mordait sur l'arête de fin de gouttière
# (t -0,16), visible comme une encoche dans son bord
MEDAL = (0.075, 0.0, 0.135)
MEDAL_PITCH = 0.021  # écart entre deux anneaux de la rosace
PETALS = 12  # ondes par tour de la rosace
PETAL_AMP = 0.007  # amplitude des ondes au bord du médaillon
HUB = 0.018  # rayon du moyeu poli au centre de la rosace
FRAME = (0.014, 0.026)  # filet d'argent de la lame : distances au bord (dedans de l'un, dehors de l'autre)
RING = 0.009  # largeur du filet d'argent autour du médaillon
SILVER = np.array([0.80, 0.80, 0.82])
# Émail translucide posé en métal (« candy ») : en non-métal un émail sombre prend un voile gris ; canal dominant
# au-dessus de ~0,3 pour ne pas tomber au noir en jeu (docs/assets.md)
ENAMELS = {
	"nuit": np.array([0.10, 0.20, 0.50]),
	"grenat": np.array([0.50, 0.07, 0.14]),
}
# Grenat retenu par l'utilisateur : le bleu nuit côtoyait ÉMAIL, bleu aussi, dans la même caisse
ENAMEL = ENAMELS[os.environ.get("GUILLOCHE_ENAMEL", "grenat")]


def groove(phase):
	"""Cette méthode permet de donner le profil d'un sillon (0 au fond, 1 sur la crête) pour une phase en sillons."""
	return 0.5 + 0.5 * np.cos(2 * np.pi * phase)


def compose(kn):
	"""Cette méthode permet de calculer sur la toile le champ en vagues, la rosace du médaillon et les filets d'argent ;
	renvoie le profil des sillons du champ et celui de la rosace (tableaux de toile)."""
	t, h = kn.grid()
	ct, ch, radius = MEDAL
	r = np.hypot(t - ct, h - ch)
	theta = np.arctan2(h - ch, t - ct)
	inner = kn.dist > FRAME[1]
	medal = r < radius
	ring = (r >= radius) & (r < radius + RING)
	kn.put("champ", inner & ~medal & ~ring)
	kn.put("médaillon", inner & medal & (r >= HUB))
	kn.put("argent", (kn.sil & (kn.dist > FRAME[0]) & ~inner) | (inner & ring) | (inner & (r < HUB)))
	field = groove((h + WAVE[1] * np.sin(2 * np.pi * t / WAVE[0])) / PITCH)
	rose = groove((r + PETAL_AMP * (r / radius) * np.sin(PETALS * theta)) / MEDAL_PITCH)
	return field, rose


def paint(kn):
	"""Cette méthode permet d'émailler le champ guilloché, de poser le médaillon d'argent en rosace et les filets, de
	repolir le fil et d'argenter garde et pommeau."""
	m = kn.m
	field, rose = compose(kn)
	champ = kn.sample("champ", blur=0.6) * kn.blade
	medal = kn.sample("médaillon", blur=0.6) * kn.blade
	silver = kn.sample("argent", blur=0.6) * kn.blade
	cut = kn.sample_array(field.astype(np.float32))
	turn = kn.sample_array(rose.astype(np.float32))
	cloud = m.field(lambda p: fbm(p * 6, 3, 71)) * 0.5 + 0.5
	# Émail : sombre au fond du sillon, éclairé sur les flancs et la crête ; un peu plus clair vers la pointe
	tip = np.clip((-0.15 - kn.t) / 1.9, 0, 1)
	glow = (0.5 + 0.75 * smooth(0.15, 0.95, cut)) * (0.94 + 0.1 * cloud) * (1 + 0.12 * tip)
	kn.paint(champ, ENAMEL * glow[..., None], 0.16 + 0.08 * (1 - cut), 1.0, detail=0.05, ao=0.3)
	# Argent satiné et sillons sombres : clair et brillant, le médaillon brûlait au blanc et la rosace disparaissait
	ring = smooth(0.1, 0.9, turn)
	kn.paint(medal, SILVER * (0.38 + 0.4 * ring)[..., None], 0.3 + 0.16 * (1 - ring), 1.0, detail=0.1, ao=0.3)
	kn.paint(silver, SILVER, 0.14, 1.0, detail=0.15, ao=0.3)
	kn.height = kn.height + cut * champ * 0.35 + ring * medal * 0.6 + silver * 0.5
	kn.edge(0.08)
	hw = kn.guard | kn.pommel
	kn.paint(hw, SILVER * (0.85 + 0.2 * smooth(0.2, 0.8, m.edges))[..., None], 0.2, 1.0, detail=0.5)
