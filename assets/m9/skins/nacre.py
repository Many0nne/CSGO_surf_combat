"""NACRE (#495, rare de la série 2) : la lame marquetée de plaquettes de nacre en losanges réguliers, serties de filets
de laiton. Les plaquettes alternent le sens de leurs stries de croissance (en damier), ce qui fait jouer la lumière
d'une plaquette à l'autre, et leur irisation (rose, vert d'eau, bleu) varie doucement le long de la lame. Au talon, un
médaillon de laiton serti d'un cabochon d'haliotide bleu-vert ; un filet de laiton cerne le contour. Fil repoli, garde
et pommeau en laiton poli, manche d'origine noir.
"""

import numpy as np
from common import fbm, mix, smooth

DIAG = (0.15, 0.10)  # diagonales d'une plaquette le long de l'axe et en hauteur (unités) : quatre rangées au talon
ORIGIN = (0.25, 0.0)  # sommet commun de quatre plaquettes (t, h), sur le ricasso
WIRE = 0.010  # largeur d'un filet de laiton entre deux plaquettes
FRAME = (0.012, 0.026)  # filet de laiton du contour : distances au bord (dedans de l'un, dehors de l'autre)
STRIA = 0.022  # écart des stries de croissance (~4,5 texels) : contraste faible, sinon elles crénellent
MEDAL = (0.07, 0.0, 0.085, 0.064)  # médaillon du talon : centre (t, h), rayon du laiton, rayon du cabochon
NACRE = np.array([0.86, 0.85, 0.82])
# Teintes d'irisation (multiplient la nacre) : rose, vert d'eau, bleu
IRIS = np.array([[1.09, 0.88, 0.95], [0.87, 1.07, 0.98], [0.86, 0.95, 1.12]])
BRASS = np.array([0.86, 0.66, 0.32])
# Haliotide : bleu-vert profond et violet, posés en métal (« candy ») pour ne pas prendre de voile gris
PAUA = np.array([[0.08, 0.36, 0.42], [0.14, 0.18, 0.46], [0.10, 0.40, 0.26]])


def lattice(t, h):
	"""Cette méthode permet de donner, en chaque point (t, h), la distance au filet le plus proche (unités), la parité
	de sa plaquette (damier) et un identifiant de plaquette."""
	a, b = (t - ORIGIN[0]) / DIAG[0], (h - ORIGIN[1]) / DIAG[1]
	u, v = a + b, a - b
	grad = np.hypot(1 / DIAG[0], 1 / DIAG[1])  # |∇u| = |∇v| : convertit l'écart en unités
	du = np.minimum(u % 1, 1 - u % 1) / grad
	dv = np.minimum(v % 1, 1 - v % 1) / grad
	i, j = np.floor(u).astype(np.int64), np.floor(v).astype(np.int64)
	return np.minimum(du, dv), (i + j) % 2, (i * 7919 + j * 104729) % 9973


def paint(kn):
	"""Cette méthode permet de marqueter la lame de nacre irisée sertie de laiton, de poser le médaillon d'haliotide,
	de repolir le fil et de dorer garde et pommeau."""
	m = kn.m
	t, h = kn.grid()
	wire, parity, ident = lattice(t, h)
	ct, ch, r_brass, r_paua = MEDAL
	r = np.hypot((t - ct) / 1.15, h - ch)  # médaillon ovale, allongé le long de l'axe
	inner = kn.dist > FRAME[1]
	frame = kn.sil & (kn.dist > FRAME[0]) & ~inner
	medal = inner & (r < r_brass)
	paua = inner & (r < r_paua)
	brass = (inner & (wire < WIRE / 2) & ~medal) | frame | (medal & ~paua)
	plate = inner & ~brass & ~medal
	kn.put("laiton", brass)
	kn.put("nacre", plate)
	kn.put("haliotide", paua)
	# Stries de croissance : parallèles à une diagonale du losange, l'autre sur les plaquettes de l'autre parité
	along = np.where(parity == 0, t / DIAG[0] + (h - ORIGIN[1]) / DIAG[1], t / DIAG[0] - (h - ORIGIN[1]) / DIAG[1])
	# Stries ondulées comme les lignes de croissance d'une coquille (droites, elles faisaient des rayures de berlingot)
	wavy = along + 0.12 * np.sin(2 * np.pi * (t / 0.09 + h / 0.13))
	stria = 0.5 + 0.5 * np.cos(2 * np.pi * wavy * DIAG[0] / STRIA / np.sqrt(2))
	# Reflet propre à chaque plaquette : une large bande claire en travers des stries, placée selon la plaquette
	shift = (ident * 0.618) % 1.0
	flash = 0.5 + 0.5 * np.cos(2 * np.pi * (along * 0.5 + shift))
	sheen = np.where(parity == 0, 1.0, 0.93) * (0.84 + 0.22 * flash)
	n_brass = kn.sample("laiton", blur=0.6) * kn.blade
	n_plate = kn.sample("nacre", blur=0.6) * kn.blade
	n_paua = kn.sample("haliotide", blur=0.6) * kn.blade
	s_stria = kn.sample_array(stria.astype(np.float32))
	s_sheen = kn.sample_array(sheen.astype(np.float32))
	s_shift = kn.sample_array(shift.astype(np.float32), order=0)
	# Irisation : phase lente le long de la lame et en hauteur, décalée par plaquette et par les stries ; trois
	# teintes en boucle
	drift = m.field(lambda p: fbm(p * 2.5, 3, 401))
	phase = (kn.t * 0.9 + kn.h * 2.0 + drift * 0.8 + s_shift * 0.5 + s_stria * 0.06) % 1.0 * 3
	k = np.floor(phase).astype(int) % 3
	f = smooth(0.0, 1.0, phase % 1.0)[..., None]
	iris = mix(IRIS[k], IRIS[(k + 1) % 3], f)
	col = NACRE * iris * (s_sheen * (0.975 + 0.035 * s_stria))[..., None]
	kn.paint(n_plate, col, 0.14 + 0.05 * s_stria, 0.0, detail=0.05, ao=0.3)
	# Haliotide : bandes ondulées concentriques, trois teintes profondes
	wave = m.field(lambda p: fbm(p * 14, 3, 409)) * 0.5 + 0.5
	pk = np.floor(wave * 6).astype(int) % 3
	pf = smooth(0.0, 1.0, (wave * 6) % 1.0)[..., None]
	kn.paint(n_paua, mix(PAUA[pk], PAUA[(pk + 1) % 3], pf) * 1.3, 0.1, 1.0, detail=0.05, ao=0.3)
	kn.paint(n_brass, BRASS, 0.24, 1.0, detail=0.3, ao=0.4)
	kn.height = kn.height + n_brass * 0.5 + n_plate * s_stria * 0.05
	kn.edge(0.08)
	hw = kn.guard | kn.pommel
	kn.paint(hw, BRASS * (0.85 + 0.25 * smooth(0.2, 0.8, m.edges))[..., None], 0.22, 1.0, detail=0.5)
