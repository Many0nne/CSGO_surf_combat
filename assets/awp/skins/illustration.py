"""Illustration d'un skin de l'AWP peinte hors du projet (modèle d'image) sur le gabarit de `gabarit.py` (#492).

Le recalage sur le gabarit (échelle et décalage par axe, couleurs prolongées au-delà du bord) est commun aux armes
(`tools/skins/art_fit.py`) ; ce module lit ensuite l'image recalée en coordonnées de la photo de profil.
"""

import os
import sys

import numpy as np
from scipy import ndimage

from common import mt_px, mt_py
from gabarit import mapping, silhouette

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))), "tools", "skins"))
import art_fit  # noqa: E402

W, H = 2520, 1080  # taille du gabarit de référence


def load(path):
	"""Cette méthode permet de charger une illustration, de la recaler sur le gabarit et de prolonger ses couleurs
	hors de son bord ; renvoie l'image (H x W x 3, 0 à 1) et le recouvrement obtenu."""
	return art_fit.load(path, np.asarray(silhouette(W, H)) < 128)


def sample(rgb, m):
	"""Cette méthode permet de lire l'illustration recalée sur les texels d'un matériau, par leur position de profil
	(le flanc droit la reçoit en miroir, comme les autres toiles)."""
	scale, ox, oy = mapping(W, H)
	u = mt_px(m.p[:, 0]) * scale + ox
	v = mt_py(m.p[:, 2]) * scale + oy
	return np.stack([ndimage.map_coordinates(rgb[..., c], [v, u], order=1, mode="nearest") for c in range(3)], axis=1)


def source(name):
	"""Cette méthode permet d'obtenir le chemin de l'illustration source d'un skin (`art/<skin>.png`)."""
	return os.path.join(os.path.dirname(os.path.abspath(__file__)), "art", f"{name}.png")
