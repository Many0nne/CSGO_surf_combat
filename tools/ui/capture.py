# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Captures de référence de l'interface (Windows) : placement de la fenêtre Studio, détection du viewport, recadrage.

Les images brutes viennent de tools/anim/capture_server.py (GET /shot?name=X, fenêtre Studio entière). Ce script les
recadre sur le viewport du jeu. Procédure complète : docs/ui.md, section « Captures de référence ».

Dossier de travail (raw/, place.json, rect.json), hors du dépôt : variable d'environnement CAP_DIR.

place save            sauvegarde le placement de la fenêtre Studio (place.json)
place set X Y W H     place la fenêtre (1655x1080 donne un viewport 16:9 sur un écran 1920x1080 à 125 %)
place restore         remet le placement sauvegardé
focus                 dit quelle fenêtre a le focus (Studio en arrière-plan tourne à ~15 i/s)
rect NOM              détecte la zone magenta de raw/NOM.png (voile posé sur le viewport) et l'écrit dans rect.json
crop DEST NOM...      recadre raw/NOM.png sur rect.json vers DEST/NOM.png
sheet SORTIE NOM...   planche-contact légendée, pour choisir une image dans une rafale
"""

import ctypes
import ctypes.wintypes as W
import json
import os
import sys

from PIL import Image, ImageDraw

HERE = os.environ["CAP_DIR"]
u32 = ctypes.windll.user32
u32.SetProcessDPIAware()


class Placement(ctypes.Structure):
	_fields_ = [
		("length", W.UINT),
		("flags", W.UINT),
		("show", W.UINT),
		("min", W.POINT),
		("max", W.POINT),
		("normal", W.RECT),
	]


# Cette méthode permet de trouver la fenêtre principale de Studio d'après son titre.
def find_window():
	found = []

	def on_window(handle, _):
		size = u32.GetWindowTextLengthW(handle)
		title = ctypes.create_unicode_buffer(size + 1)
		u32.GetWindowTextW(handle, title, size + 1)
		if u32.IsWindowVisible(handle) and "Roblox Studio" in title.value:
			found.append(handle)
		return True

	u32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, W.HWND, W.LPARAM)(on_window), 0)
	return found[0]


# Cette méthode permet de lire le placement (agrandi ou non, rectangle normal) de la fenêtre Studio.
def get_placement(handle):
	placement = Placement()
	placement.length = ctypes.sizeof(Placement)
	u32.GetWindowPlacement(handle, ctypes.byref(placement))
	return placement


# Cette méthode permet de sauvegarder, changer ou restaurer le placement de la fenêtre Studio.
def place(args):
	handle = find_window()
	store = os.path.join(HERE, "place.json")
	if args[0] == "save":
		p = get_placement(handle)
		data = {"show": p.show, "flags": p.flags, "normal": [p.normal.left, p.normal.top, p.normal.right, p.normal.bottom]}
		with open(store, "w") as fh:
			json.dump(data, fh)
		print(data)
	elif args[0] == "set":
		x, y, w, h = (int(v) for v in args[1:5])
		u32.ShowWindow(handle, 9)  # SW_RESTORE
		u32.SetWindowPos(handle, 0, x, y, w, h, 0x0004 | 0x0010)  # NOZORDER | NOACTIVATE
		rect = W.RECT()
		u32.GetWindowRect(handle, ctypes.byref(rect))
		print([rect.left, rect.top, rect.right, rect.bottom])
	elif args[0] == "restore":
		with open(store) as fh:
			data = json.load(fh)
		p = get_placement(handle)
		p.show, p.flags = data["show"], data["flags"]
		p.normal.left, p.normal.top, p.normal.right, p.normal.bottom = data["normal"]
		u32.SetWindowPlacement(handle, ctypes.byref(p))
		print("restauré", data)


# Cette méthode permet de savoir quelle fenêtre a le focus et si Studio est réduit, sans rien changer.
def focus():
	handle = u32.GetForegroundWindow()
	size = u32.GetWindowTextLengthW(handle)
	title = ctypes.create_unicode_buffer(size + 1)
	u32.GetWindowTextW(handle, title, size + 1)
	studio = find_window()
	print("premier plan :", title.value, "| Studio au premier plan :", handle == studio, "| Studio réduit :", bool(u32.IsIconic(studio)))


# Cette méthode permet de lire le rectangle du viewport écrit par `rect`.
def load_box():
	with open(os.path.join(HERE, "rect.json")) as fh:
		return tuple(json.load(fh))


# Cette méthode permet de trouver le rectangle magenta (voile posé sur le viewport) dans une capture brute.
def rect(name):
	image = Image.open(os.path.join(HERE, "raw", name + ".png")).convert("RGB")
	r, g, b = image.split()
	mask = Image.eval(r, lambda v: 255 if v > 240 else 0)
	for band, test in ((g, lambda v: 255 if v < 15 else 0), (b, lambda v: 255 if v > 240 else 0)):
		mask = Image.composite(mask, Image.new("L", image.size, 0), Image.eval(band, test))
	box = mask.getbbox()
	with open(os.path.join(HERE, "rect.json"), "w") as fh:
		json.dump(box, fh)
	print(box, "taille", box[2] - box[0], box[3] - box[1], "ratio", round((box[2] - box[0]) / (box[3] - box[1]), 4))


# Cette méthode permet de recadrer des captures brutes sur le viewport détecté.
def crop(dest, names):
	box = load_box()
	os.makedirs(dest, exist_ok=True)
	for name in names:
		image = Image.open(os.path.join(HERE, "raw", name + ".png")).convert("RGB").crop(box)
		image.save(os.path.join(dest, name + ".png"), optimize=True)
		print(name, image.size)


# Cette méthode permet de composer une planche-contact légendée de captures brutes recadrées, pour en choisir une.
def sheet(dest, names, columns=4, width=480):
	box = load_box()
	height = round(width * (box[3] - box[1]) / (box[2] - box[0]))
	rows = (len(names) + columns - 1) // columns
	board = Image.new("RGB", (columns * width, rows * (height + 18)), "black")
	draw = ImageDraw.Draw(board)
	for index, name in enumerate(names):
		image = Image.open(os.path.join(HERE, "raw", name + ".png")).convert("RGB").crop(box).resize((width, height))
		x, y = (index % columns) * width, (index // columns) * (height + 18)
		board.paste(image, (x, y + 18))
		draw.text((x + 4, y + 3), name, fill="white")
	board.save(dest, quality=85)
	print(dest, board.size)


if sys.argv[1] == "place":
	place(sys.argv[2:])
elif sys.argv[1] == "focus":
	focus()
elif sys.argv[1] == "rect":
	rect(sys.argv[2])
elif sys.argv[1] == "crop":
	crop(sys.argv[2], sys.argv[3:])
elif sys.argv[1] == "sheet":
	sheet(sys.argv[2], sys.argv[3:])
