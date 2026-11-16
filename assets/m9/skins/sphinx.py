"""SPHINX (#436) : hommage au film de 1991 par son papillon, le sphinx tête-de-mort (Acherontia atropos), sans rien
reprendre de l'affiche. Le papillon est posé le long du couteau : sur la lame, l'aile antérieure (brun-noir poudré,
nervures crème qui fuient vers la pointe, deux lignes en zigzag en travers, taches rouille près de la pointe, point
discal crème) recouvre l'aile postérieure ocre à deux bandes noires festonnées, le long du tranchant ; le talon de
lame est le thorax, avec sa tache claire en forme de crâne ; le manche est l'abdomen, en anneaux ocre et noirs de plus
en plus serrés vers le pommeau. Fil poli, garde et pommeau brun-noir.
"""

import numpy as np
from common import S, fbm, mix, smooth
from scipy import ndimage

WING = np.array([0.21, 0.165, 0.13])  # brun-noir de l'aile (au moins ~0,2 : une base sombre tombe au noir en jeu)
CREAM = np.array([0.80, 0.70, 0.50])
RUST = np.array([0.50, 0.24, 0.09])
OCHRE = np.array([0.86, 0.58, 0.10])
BAND = np.array([0.05, 0.035, 0.025])
THORAX = np.array([0.12, 0.09, 0.07])
BONE = np.array([0.80, 0.64, 0.33])  # tache du thorax, ocre clair
MARGIN = 0.012
RICASSO = -0.16  # le thorax commence ici (t), l'aile s'arrête un peu avant


def profile(kn):
	"""Cette méthode permet d'obtenir, pour chaque colonne de la toile, la hauteur du tranchant et celle d'un dos lissé
	(les dents et le trou ne comptent pas), en unités : la hauteur relative 0 au tranchant, 1 au dos, en découle."""
	sil = kn.sil
	rows = np.arange(sil.shape[0])[:, None]
	has = sil.any(0)
	low = np.where(has, np.where(sil, rows, -1).max(0), 0)
	high = np.where(has, np.where(sil, rows, 10**6).min(0), 0)
	edge = 0.54 - low / S  # H1 - y / S (H1 = 0,54)
	back = 0.54 - high / S
	back = ndimage.maximum_filter1d(back, int(0.25 * S))  # dos sans les dents
	back = ndimage.gaussian_filter1d(back, 0.05 * S)
	edge = ndimage.gaussian_filter1d(edge, 0.01 * S)
	return edge, back


def wings(kn):
	"""Cette méthode permet de calculer les couches des deux ailes sur la toile : aile postérieure (ocre, bandes),
	aile antérieure (fond, nervures, zigzags, rouille, point discal)."""
	t, h = kn.grid()
	edge, back = profile(kn)
	rel = np.clip((h - edge[None, :]) / np.maximum(back - edge, 0.05)[None, :], 0, 1.2)
	inner = (kn.dist > MARGIN) & (t < thorax_front(h))
	along = np.clip((t - (-2.12)) / (RICASSO + 2.12), 0, 1)  # 0 à la pointe, 1 au talon
	# bord de l'aile antérieure : un peu au-dessus du tiers, festonné, il remonte vers la pointe
	hem0 = 0.36 + 0.06 * (1 - along)
	hem = hem0 + 0.012 * np.sin(t * 2 * np.pi / 0.07)  # seul le bord est festonné, pas les nervures
	hind = inner & (rel < hem)
	fore = inner & (rel >= hem)
	# deux bandes noires festonnées parallèles au tranchant (aile postérieure)
	sc = 0.015 * np.sin(t * 2 * np.pi / 0.26)  # festons larges : serrés, les bandes faisaient des vagues de zèbre
	b1 = np.abs(rel - (0.11 + sc)) < 0.04
	b2 = np.abs(rel - (0.25 + sc * 1.3)) < 0.022
	bands = hind & (b1 | b2)
	# nervures : lignes fines qui partent du talon et convergent vers la pointe
	veins = np.zeros(t.shape, bool)
	for r0 in (0.5, 0.64, 0.78, 0.91):
		rv = hem0 + (r0 - 0.36) * (0.45 + 0.55 * along)
		veins |= np.abs(rel - rv) < 0.012
	# deux lignes transverses en zigzag (antémédiane, postmédiane), penchées vers la pointe
	zig = np.zeros(t.shape, bool)
	for t0 in (-1.55, -0.72):
		tri = np.abs(((rel * 7) % 2) - 1)  # dent de scie en hauteur
		tz = t0 - 0.18 * rel + 0.06 * tri
		zig |= np.abs(t - tz) < 0.011
	# taches rouille entre la ligne postmédiane et la pointe, près du dos ; point discal crème
	rust = fore & (t < -1.2) & (t > -1.95) & (rel > 0.62) & (fbm_canvas(t, h, 0.1, 61) > -0.05)
	disc = np.hypot((t + 1.05) / 0.028, (rel - 0.66) / 0.06) < 1
	fore_lines = fore & zig
	# marbrure claire de l'aile : plages crème poudrées, plus denses entre les deux zigzags
	marble = fbm_canvas(t * np.array(1.0), h * 2.5, 0.12, 67)
	return {
		"veins": fore & veins & ~zig,
		"marble": fore & (marble > 0.18),
		"hind": hind & ~bands,
		"bands": bands,
		"fore": fore,
		"rust": rust & ~fore_lines,
		"lines": fore_lines,
		"disc": fore & disc,
		"hem": inner & (np.abs(rel - hem) < 0.012),
	}


def thorax_front(h):
	"""Cette méthode permet de donner l'abscisse t du bord avant du thorax à une hauteur h : un arc bombé vers la pointe,
	pour que l'aile s'y attache en arrondi et non par un trait droit."""
	return RICASSO + 0.1 * (np.asarray(h) / 0.22) ** 2


def fbm_canvas(t, h, cell, seed):
	"""Cette méthode permet d'évaluer le bruit fractal 3D sur la toile (z nul), pour un motif de taches sur la lame."""
	p = np.stack([t.ravel(), h.ravel(), np.zeros(t.size)], 1)
	return fbm(p / cell, 3, seed).reshape(t.shape)


def skull(kn):
	"""Cette méthode permet de dessiner sur le talon de lame la tache du thorax telle qu'elle est sur le papillon : une
	plage ocre clair arrondie en haut, rétrécie en bas, percée de deux grosses taches sombres (les orbites) ; ni nez ni
	dents (un crâne dessiné en entier faisait drapeau pirate). Les bords sont flous, comme un pelage."""
	c = (0.05, 0.0)
	kn.disc("skull", (c[0], c[1] + 0.025), 0.075)
	kn.poly("skull", [(c[0] - 0.068, c[1] + 0.01), (c[0] + 0.068, c[1] + 0.01), (c[0] + 0.035, c[1] - 0.09), (c[0] - 0.035, c[1] - 0.09)])
	for dx in (-0.032, 0.032):
		kn.disc("socket", (c[0] + dx, c[1] + 0.0), 0.026)
	kn.disc("socket", (c[0], c[1] - 0.05), 0.012)


def paint(kn):
	"""Cette méthode permet de peindre SPHINX : ailes sur la lame, thorax et crâne au talon, abdomen sur le manche."""
	m = kn.m
	t, h = kn.grid()
	for name, arr in wings(kn).items():
		kn.put(name, arr.astype(np.float32))
	thorax = (kn.dist > MARGIN) & (t >= thorax_front(h))
	kn.put("thorax", thorax.astype(np.float32))
	skull(kn)
	blade = kn.blade
	# écailles poudrées : un grain fin éclaircit l'aile par endroits (aspect velours, sans reflet)
	powder = m.field(lambda p: fbm(p * 40, 1, 71)) * 0.5 + 0.5
	mottle = m.field(lambda p: fbm(p * 6, 2, 73)) * 0.5 + 0.5
	fore = kn.sample("fore") * blade
	# brun sombre posé en métal (« candy ») : en non-métal, il prenait un voile gris et faisait acier terne
	kn.paint(fore, mix(WING, WING * 1.35, (powder * 0.6 + mottle * 0.4)[..., None]), 0.56, 1.0, detail=0.15)
	kn.paint(kn.sample("rust") * blade, RUST * (0.85 + 0.3 * powder)[..., None], 0.62, 0.0, detail=0.1)
	kn.paint(kn.sample("marble", blur=4) * blade * 0.35, CREAM * 0.7, 0.62, 0.0, detail=0.1)
	kn.paint(kn.sample("veins", blur=0.6) * blade * 0.2, CREAM, 0.6, 0.0, detail=0.1)  # nervures discrètes
	kn.paint(kn.sample("lines", blur=0.6) * blade * 0.85, CREAM, 0.6, 0.0, detail=0.1)
	kn.paint(kn.sample("disc") * blade, CREAM, 0.6, 0.0, detail=0.1)
	hind = kn.sample("hind") * blade
	kn.paint(hind, OCHRE * (0.92 + 0.12 * powder)[..., None], 0.55, 0.0, detail=0.15)
	kn.paint(kn.sample("bands") * blade, BAND, 0.6, 0.0, detail=0.1)
	kn.paint(kn.sample("hem") * blade * 0.7, CREAM * 0.8, 0.6, 0.0, detail=0.1)
	# thorax velu brun-noir au talon, crâne ocre clair en léger relief
	kn.paint(kn.sample("thorax") * blade, THORAX * 1.6 * (0.9 + 0.25 * powder)[..., None], 0.48, 1.0, detail=0.15)
	sk = kn.sample("skull", blur=2.5) * blade * (kn.sample("thorax") > 0.5)
	so = kn.sample("socket", blur=2) * sk
	kn.paint(sk, BONE * (0.9 + 0.15 * mottle)[..., None], 0.55, 0.0, detail=0.1)
	kn.paint(so, THORAX * 1.2, 0.5, 1.0, detail=0.05)
	kn.height = kn.height + sk * 0.5 - so * 0.4 + kn.sample("lines") * blade * 0.15
	kn.edge(0.1)
	# garde et pommeau brun-noir satiné
	hw = kn.guard | kn.pommel
	kn.paint(hw, THORAX * 1.6 * (0.85 + 0.25 * smooth(0.2, 0.8, m.edges))[..., None], 0.38, 1.0, detail=0.6)
	# abdomen : anneaux ocre et noirs, de plus en plus serrés vers le pommeau (une ligne gris-bleu sur le dessus, essayée,
	# se lisait comme du plastique non peint)
	g = np.clip((kn.t - 0.35) / 1.15, 0, 1)
	phase = (g * 7 + 0.9 * g * g) % 1.0  # 7 à 8 anneaux, plus serrés au bout
	ring_ochre = kn.grip & (phase < 0.6)
	kn.tint_grip(OCHRE * 0.8, ring_ochre)
	kn.tint_grip(BAND * 2.0, kn.grip & ~ring_ochre)
