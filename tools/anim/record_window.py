# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow", "mss"]
# ///
"""Enregistre la fenêtre Studio en temps réel (playtest), pour une animation qu'on ne peut pas rendre image par image :
effets de particules, lumières, scène pilotée par le jeu (ouverture de caisse #332, docs/ui.md).

Usage : uv run tools/anim/record_window.py <dossier> <Nom> <duree_s> [i/s=30] [seuil=2.0]
  Capture la fenêtre en continu pendant `duree_s` (lancer l'enregistrement, puis déclencher l'animation en jeu), cherche
  le départ (première image qui diffère nettement de la première : la caméra se met à bouger), puis rééchantillonne à
  cadence fixe en <dossier>/<Nom>_0000.png, <Nom>_0001.png… : le format attendu par side_by_side.py. Captures à la
  moitié de la résolution de la fenêtre : relever le viewport de side_by_side.py sur ces images.
  Les captures brutes restent dans <dossier>/raw/ avec leurs instants (raw/times.txt).
  Studio doit rester au premier plan : la capture lit l'écran (mss, ~27 i/s). PrintWindow, qui capture une fenêtre
  couverte, plafonnait à 11 i/s ; la Windows Graphics Capture (paquet windows-capture) n'a reçu aucune image de Studio.
"""

import ctypes
import ctypes.wintypes as W
import os
import sys
import time

import mss
from PIL import Image, ImageChops, ImageStat

OUT, NAME, DURATION = sys.argv[1], sys.argv[2], float(sys.argv[3])
FPS = int(sys.argv[4]) if len(sys.argv) > 4 else 30
THRESHOLD = float(sys.argv[5]) if len(sys.argv) > 5 else 2.0
u32 = ctypes.windll.user32
u32.SetProcessDPIAware()



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
	return found[0] if found else None



# Cette méthode permet de mesurer l'écart moyen entre deux images réduites (0-255) lorsque le départ est recherché.
def difference(a, b):
	small = (160, 90)
	diff = ImageChops.difference(a.convert("L").resize(small), b.convert("L").resize(small))
	return ImageStat.Stat(diff).mean[0]


def main():
	handle = find_window()
	if not handle:
		sys.exit("fenêtre Studio introuvable")
	raw = os.path.join(OUT, "raw")
	os.makedirs(raw, exist_ok=True)
	rect = W.RECT()
	u32.GetWindowRect(handle, ctypes.byref(rect))
	box = {"left": rect.left, "top": rect.top, "width": rect.right - rect.left, "height": rect.bottom - rect.top}
	if u32.GetForegroundWindow() != handle:
		print("attention : Studio n'est pas au premier plan, la capture lira ce qui le couvre")
	frames = []
	with mss.MSS() as screen:
		begin = time.perf_counter()
		while time.perf_counter() - begin < DURATION:
			at = time.perf_counter() - begin
			shot = screen.grab(box)
			# moitié de la résolution : en pleine taille, 10 s de captures dépassent le giga-octet de mémoire
			image = Image.frombytes("RGB", shot.size, shot.bgra, "raw", "BGRX").reduce(2)
			frames.append((at, image))
	print(f"{len(frames)} captures en {DURATION:.1f} s ({len(frames) / DURATION:.1f} i/s)")
	first = frames[0][1]
	start = next((at for at, image in frames if difference(first, image) > THRESHOLD), None)
	if start is None:
		sys.exit("aucun départ détecté : l'animation a-t-elle été déclenchée ?")
	# le départ est entre la capture précédente et celle-ci : on prend la précédente
	index = next(i for i, (at, _) in enumerate(frames) if at == start)
	start = frames[max(index - 1, 0)][0]
	with open(os.path.join(raw, "times.txt"), "w") as fh:
		for i, (at, image) in enumerate(frames):
			image.save(os.path.join(raw, f"{i:04d}.png"))
			fh.write(f"{i:04d} {at - start:.4f}\n")
	k = 0
	while True:
		target = start + k / FPS
		if target > frames[-1][0]:
			break
		nearest = min(frames, key=lambda f: abs(f[0] - target))
		nearest[1].save(os.path.join(OUT, f"{NAME}_{k:04d}.png"))
		k += 1
	print(f"départ à {start:.3f} s, {k} images à {FPS} i/s dans {OUT}")


main()
