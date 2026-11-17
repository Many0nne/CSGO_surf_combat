"""Illustration d'un skin de la M9 peinte hors du projet (modèle d'image) sur le gabarit de `gabarit.py` (#505).

Le recalage sur le masque du gabarit est commun aux armes (`tools/skins/art_fit.py`) ; ce module lit ensuite l'image
recalée sur chaque texel par sa place sur la toile de profil, sans distinction de face : le joueur la voit à l'endroit
sur la face droite en 1P (tranchant en haut), et en miroir, à l'endroit aussi, sur la face gauche.
"""

import os

import numpy as np
from scipy import ndimage

import art_fit  # tools/skins, mis dans le chemin par common
from gabarit import Gabarit


def load(kn, path):
	"""Cette méthode permet de charger une illustration et de la recaler sur le gabarit de la lame ; renvoie le gabarit,
	l'image recalée (H x W x 3, 0 à 1) et le recouvrement obtenu."""
	g = Gabarit(kn)
	rgb, score = art_fit.load(path, g.mask())
	return g, rgb, score


def sample(kn, g, rgb):
	"""Cette méthode permet de lire l'illustration recalée sur chaque texel de la M9 (H x W x 3)."""
	gx, gy = g.to_gab(kn.u, kn.v)
	coords = [gy.ravel(), gx.ravel()]
	return np.stack(
		[ndimage.map_coordinates(rgb[..., c], coords, order=1, mode="nearest").reshape(kn.u.shape) for c in range(3)],
		axis=-1,
	).astype(np.float32)


def source(name):
	"""Cette méthode permet d'obtenir le chemin de l'illustration source d'un skin (`art/<skin>.png`)."""
	return os.path.join(os.path.dirname(os.path.abspath(__file__)), "art", f"{name}.png")
