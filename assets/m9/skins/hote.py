"""HÔTE (#433) : hommage à la biomécanique de H.R. Giger (film de science-fiction de 1979), sans rien en reprendre tel
quel. Sur une lame noir bleuté, une colonne vertébrale couleur os court du talon vers la pointe ; ses vertèbres
rapetissent régulièrement et chacune porte deux côtes qui partent l'une vers le dos, l'autre vers le tranchant, en se
rabattant vers le manche. Entre les os, la lame est striée de fins tubes parallèles (parois de l'épave). Les os sont
ombrés vers leurs bords (sépia) et cernés d'une ombre noire en creux. Fil poli, garde et pommeau acier sombre, manche
noir.
"""

import numpy as np
from common import S, mix, smooth
from PIL import ImageDraw
from scipy import ndimage

BASE = np.array([0.17, 0.19, 0.23])  # laque métallique noir bleuté (au moins ~0,2 sur le canal dominant en jeu)
BONE = np.array([0.72, 0.66, 0.52])
SEPIA = np.array([0.26, 0.19, 0.12])  # bord des os (ombre propre : volume)
SHADOW = np.array([0.04, 0.045, 0.055])
DARK_STEEL = np.array([0.36, 0.38, 0.42])
GRIP = np.array([0.09, 0.10, 0.12])
MARGIN = 0.024  # distance au bord de la lame (et du trou) en deçà de laquelle rien n'est dessiné
# Axe de la colonne (t, h) : sous le trou et sous le bord bas de la gouttière (h 0,02, arête du mesh qui coupait les
# vertèbres en deux quand la colonne passait dessus)
PATH = ((0.17, -0.062), (-0.55, -0.066), (-1.2, -0.07), (-1.65, -0.045), (-1.95, -0.005))
TUBE = 0.017  # écart des tubes parallèles


def axis_h(t):
	"""Cette méthode permet de donner la hauteur de l'axe de la colonne à une abscisse t (passe sous le trou)."""
	ts, hs = zip(*PATH[::-1])
	return float(np.interp(t, ts, hs))


def bezier(p0, p1, p2, n=14):
	"""Cette méthode permet d'échantillonner une courbe de Bézier quadratique (points (t, h)) en n + 1 points."""
	s = np.linspace(0, 1, n + 1)[:, None]
	pts = (1 - s) ** 2 * np.array(p0) + 2 * (1 - s) * s * np.array(p1) + s**2 * np.array(p2)
	return [tuple(p) for p in pts]


def tapered(kn, name, pts, w0, w1):
	"""Cette méthode permet de tracer une ligne qui s'affine de w0 à w1 (unités), segment par segment, bouts arrondis."""
	n = len(pts) - 1
	for i in range(n):
		w = w0 + (w1 - w0) * i / n
		kn.line(name, [pts[i], pts[i + 1]], w)
		kn.disc(name, pts[i + 1], (w0 + (w1 - w0) * (i + 1) / n) / 2)


def skeleton(kn):
	"""Cette méthode permet de dessiner la colonne : moelle, vertèbres de plus en plus petites vers la pointe et leurs
	deux côtes rabattues vers le manche ; renvoie le masque des os sur la toile."""
	t = PATH[0][0]
	pts = [(tt, axis_h(tt)) for tt in np.linspace(PATH[0][0], PATH[-1][0], 60)]
	tapered(kn, "bone", pts, 0.022, 0.008)  # moelle continue sous les vertèbres
	while t > -1.9:
		g = np.clip((t - PATH[-1][0]) / (PATH[0][0] - PATH[-1][0]), 0, 1)  # 1 au talon, 0 vers la pointe
		step = 0.045 + 0.065 * g
		h = axis_h(t)
		bw, bh = step * 0.4, 0.028 + 0.03 * g
		(cx, cy), = kn.xy([(t, h)])
		for img in kn.layer("bone"):  # corps de la vertèbre
			ImageDraw.Draw(img).ellipse((cx - bw * S, cy - bh * S, cx + bw * S, cy + bh * S), fill=255)
		tj = t + step * 0.5  # entre cette vertèbre et la précédente : coupure creuse en travers de la moelle
		kn.line("slit", [(tj, axis_h(tj) - 0.02), (tj, axis_h(tj) + 0.02)], 0.007)
		edge, back = kn.edges_at(t)
		for end in (back - MARGIN - 0.02, edge + MARGIN + 0.02):  # côte vers le dos, puis vers le tranchant
			if abs(end - h) < bh + 0.02:
				continue
			sgn = np.sign(end - h)
			start = (t, h + sgn * bh * 0.6)
			kn.disc("bone", (t, h + sgn * bh * 1.05), step * 0.26)  # articulation de la côte
			tip = (t + step * 1.1, end)
			tapered(kn, "bone", bezier(start, (t, end), tip), step * 0.42, step * 0.08)
		t -= step
	return np.asarray(kn.layer("bone")[0]) > 127


def paint(kn):
	"""Cette méthode permet de peindre la lame (laque, tubes, os ombrés et cernés), le fil, la garde, le pommeau et le
	manche de HÔTE."""
	m = kn.m
	t, h = kn.grid()
	inner = kn.dist > MARGIN
	bone = skeleton(kn) & inner
	# os : clairs au cœur, sépia vers le bord ; ombre en creux autour
	d_in = ndimage.distance_transform_edt(bone) / S
	shade = smooth(0.0, 0.016, d_in) ** 0.7
	halo = ndimage.binary_dilation(bone, iterations=int(0.007 * S)) & ~bone & inner
	halo |= (np.asarray(kn.layer("slit")[0]) > 127) & bone
	# tubes parallèles le long de la lame, entre les os
	tube = np.abs(np.sin(np.pi * h / TUBE)).astype(np.float32)
	kn.put("bone", bone.astype(np.float32))
	kn.put("shade", shade)
	kn.put("halo", halo.astype(np.float32))
	kn.put("tube", tube * inner)
	kn.put("groove", (1 - smooth(0.0, 0.35, tube)) * inner)
	blade = kn.blade
	b = kn.sample("bone", blur=0.6) * blade
	sh = kn.sample("shade", blur=0.6)
	ha = kn.sample("halo", blur=0.8) * blade
	tu = kn.sample("tube", blur=0.6)
	gr = kn.sample("groove", blur=0.6) * blade
	# laque noir bleuté, tubes à peine plus clairs sur leur bombé
	kn.paint(blade, BASE[None, None, :] * (0.85 + 0.3 * tu)[..., None], 0.3, 1.0, detail=0.3)
	kn.paint(gr * 0.6, SHADOW, 0.4, 1.0, detail=0.1)
	kn.paint(ha, SHADOW, 0.45, 1.0, detail=0.1)
	col = mix(SEPIA[None, None, :], BONE[None, None, :], sh[..., None])
	kn.paint(b, col, 0.26, 0.0, detail=0.15, ao=0.3)  # os luisant (laqué, comme les sculptures de Giger)
	kn.paint(ha * b, SHADOW, 0.45, 1.0, detail=0.1)  # fentes des vertèbres, par-dessus l'os
	kn.height = kn.height + b * (0.5 + 1.0 * sh) - ha * 0.5 + tu * 0.15 * blade
	kn.edge(0.1)
	hw = kn.guard | kn.pommel
	kn.paint(hw, DARK_STEEL * (0.85 + 0.25 * smooth(0.2, 0.8, m.edges))[..., None], 0.32, 1.0, detail=0.6)
	kn.tint_grip(GRIP)
