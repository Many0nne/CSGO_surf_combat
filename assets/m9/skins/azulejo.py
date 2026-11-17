"""AZULEJO (#495, rare de la série 2) : la lame carrelée de faïence émaillée blanche peinte au bleu de cobalt. Un carreau
géométrique répété (étoile à huit pointes au lavis bleu, cernée de cobalt, quarts de cercle aux coins qui forment un
anneau à chaque croisée de joints) couvre le plat ; le long du tranchant, une frise de bordure cobalt à chaîne d'anneaux
blancs suit la ligne de la lame jusqu'à la pointe, et un filet cobalt cerne le contour. Émail brillant, joints gris en
léger creux. Fil repoli ; garde et pommeau en argent satiné, manche d'origine noir.
"""

import numpy as np
from common import H1, S, fbm
from scipy import ndimage

TILE = 0.18  # côté d'un carreau (unités) : deux rangées au-dessus de la frise au talon
TILE_ORIGIN = (0.25, -0.092)  # coin d'un carreau (t, h) : le ricasso et le haut de la frise tombent sur des joints
JOINT = 0.006
FIL = 0.042  # hauteur du fil repoli vu de profil (`kn.edge`) : la frise commence au-dessus, sinon l'acier la couvre
FRIEZE = 0.07  # hauteur de la frise au-dessus du fil (le biseau incliné la tasse de profil)
FRIEZE_LINE = 0.007  # filet cobalt qui sépare la frise du champ
LINK = 0.06  # pas de la chaîne d'anneaux de la frise
FRAME = 0.016  # filet cobalt le long du contour
TEETH = 0.12  # fenêtre du maximum glissant qui comble les creux des dents (comme CÉRAMIQUE)
GLAZE = np.array([0.90, 0.89, 0.85])  # blanc stannifère, un peu chaud
COBALT = np.array([0.08, 0.20, 0.58])
WASH = np.array([0.42, 0.58, 0.84])  # lavis de cobalt dilué
JOINT_GREY = np.array([0.58, 0.58, 0.56])
SILVER = np.array([0.80, 0.80, 0.82])


def edge_line(kn):
	"""Cette méthode permet de donner, pour chaque colonne de toile, la hauteur h du tranchant (bas de la silhouette)."""
	has = kn.sil.any(0)
	rows = np.arange(kn.hpx)[:, None]
	bottom = np.where(has, H1 - np.max(np.where(kn.sil, rows, 0), axis=0) / S, -1.0)
	return ndimage.gaussian_filter1d(bottom, 6)


def star(u, v, radius):
	"""Cette méthode permet de donner la distance signée (unités de carreau, négative dedans) à une étoile à huit
	pointes de centre (0, 0) : deux carrés superposés, l'un tourné de 45°."""
	square = np.maximum(np.abs(u), np.abs(v)) - radius
	diamond = (np.abs(u) + np.abs(v)) / np.sqrt(2) - radius
	return np.minimum(square, diamond)


def tile_motif(t, h):
	"""Cette méthode permet de peindre un carreau répété : renvoie les masques du cobalt plein, du lavis et du joint."""
	x, y = (t - TILE_ORIGIN[0]) / TILE, (h - TILE_ORIGIN[1]) / TILE
	u, v = x % 1 - 0.5, y % 1 - 0.5
	jd = (0.5 - np.maximum(np.abs(u), np.abs(v))) * TILE
	joint = jd < JOINT / 2
	s = star(u, v, 0.22)
	cobalt = np.abs(s) < 0.025  # cerne de l'étoile
	wash = s < -0.025
	core = star(u, v, 0.07) < 0  # cœur de l'étoile : petite étoile blanche cernée
	core_ring = np.abs(star(u, v, 0.07)) < 0.018
	wash &= ~core
	cobalt |= core_ring
	# Quarts de cercle aux coins : un anneau complet à chaque croisée de joints, plein de cobalt au centre
	cu, cv = 0.5 - np.abs(u), 0.5 - np.abs(v)
	rc = np.hypot(cu, cv)
	cobalt |= (np.abs(rc - 0.2) < 0.03) | (rc < 0.07)
	wash |= (rc > 0.1) & (rc < 0.17)
	# Fins rayons du centre vers chaque milieu de côté, entre l'étoile et le bord
	ray = ((np.abs(u) < 0.012) | (np.abs(v) < 0.012)) & (np.maximum(np.abs(u), np.abs(v)) > 0.3)
	cobalt |= ray
	return cobalt & ~joint, wash & ~joint & ~cobalt, joint


def paint(kn):
	"""Cette méthode permet de carreler le plat en azulejos, de poser la frise et le filet cobalt, de creuser les joints,
	de repolir le fil et d'argenter garde et pommeau."""
	m = kn.m
	t, h = kn.grid()
	low = edge_line(kn)[None, :] + FIL
	frieze_top = low + FRIEZE
	in_frieze = kn.sil & (h < frieze_top) & (h >= low - FIL)
	field = kn.sil & (h >= frieze_top + FRIEZE_LINE) & (kn.dist > FRAME)
	cobalt, wash, joint = tile_motif(t, h)
	# Frise : fond cobalt, losanges blancs pleins alternés de points. Une chaîne d'anneaux, tassée par le biseau
	# incliné vu de profil, ne se lisait plus que comme des traits verticaux
	mid = low + FRIEZE * 0.5
	lt = (t % LINK) - LINK / 2
	lozenge = np.abs(lt) / (LINK * 0.32) + np.abs(h - mid) / (FRIEZE * 0.34) < 1
	dot = np.hypot(np.abs(lt) - LINK / 2, h - mid) < FRIEZE * 0.12
	frieze_white = in_frieze & (lozenge | dot) & (h >= low)
	frieze_cobalt = in_frieze & ~frieze_white
	line = kn.sil & (h >= frieze_top) & (h < frieze_top + FRIEZE_LINE)
	frame = kn.sil & (kn.dist <= FRAME) & ~in_frieze
	kn.put("cobalt", (field & cobalt) | frieze_cobalt | line | frame)
	kn.put("lavis", field & wash)
	kn.put("joint", field & joint)
	blue = kn.sample("cobalt", blur=0.6) * kn.blade
	lavis = kn.sample("lavis", blur=0.6) * kn.blade
	grout = kn.sample("joint", blur=0.6) * kn.blade
	# Émail : nuages de cuisson et bleu qui « coule » un peu plus dense au fond des traits
	cloud = m.field(lambda p: fbm(p * 9, 3, 307)) * 0.5 + 0.5
	glaze = GLAZE * (0.97 + 0.05 * cloud)[..., None]
	# Rugosité 0,3 : à 0,16 l'émail renvoyait le ciel du crépuscule et le blanc virait au gris bleuté en jeu
	kn.paint(kn.blade, glaze, 0.3, 0.0, detail=0.1, ao=0.4)
	kn.paint(lavis, WASH * (0.94 + 0.12 * cloud)[..., None], 0.3, 0.0, detail=0.1, ao=0.4)
	kn.paint(blue, COBALT * (0.9 + 0.2 * cloud)[..., None], 0.3, 0.0, detail=0.1, ao=0.4)
	kn.paint(grout, JOINT_GREY, 0.8, 0.0, detail=0.3, ao=0.6)
	kn.height = kn.height + (cloud * 0.03 + blue * 0.06 - grout * 0.5) * kn.blade
	kn.edge(0.08)
	kn.paint(kn.guard | kn.pommel, SILVER, 0.3, 1.0, detail=0.5)
