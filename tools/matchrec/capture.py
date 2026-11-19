# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow", "mss", "numpy", "imageio-ffmpeg"]
# ///
"""Filme un rejeu de partie (#582, debug/MatchReplay) dans Studio et en tire une vidéo fluide à vitesse normale
(docs/promo.md, « Enregistreur de partie »).

Usage : uv run tools/matchrec/capture.py <sortie.mp4> [--speed 0.25] [--fps 60] [--timeout 900] [--cut-top 80]
  Lancer l'outil, puis le rejeu (attribut joueur MatchReplay ou MatchReplayRun, avec MatchReplaySpeed = la même
  vitesse). Le rejeu commence par un écran noir (repère) : l'outil y relève le cadre du viewport, prend le départ à la
  première image non noire, puis s'arrête à l'écran noir de fin. Chaque capture est placée à l'instant du rejeu qu'elle
  montre (temps réel × vitesse) ; la vidéo est écrite à `fps` images/s sur ce temps-là : au quart de la vitesse, une
  capture d'écran à ~25 i/s donne ~100 images par seconde de rejeu, assez pour 60 i/s nettes même si Studio rame.
  Studio doit rester au premier plan (la capture lit l'écran, cf. tools/anim/record_window.py). Sans le son : les sons
  du rejeu sont joués en temps réel.
"""

import argparse
import ctypes
import ctypes.wintypes as W
import sys
import time

import imageio_ffmpeg
import mss
import numpy as np

u32 = ctypes.windll.user32
u32.SetProcessDPIAware()

# Luminance (0-255) sous laquelle un pixel est noir : le thème sombre de Studio reste au-dessus (~40)
BLACK = 8
# Part des pixels du cadre qui doivent être noirs pour qu'une image soit l'écran noir du rejeu
BLACK_SHARE = 0.98
# Durée (s réelles) d'écran noir après la lecture qui termine la capture
TAIL_HOLD = 0.4


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


# Cette méthode permet de convertir une capture mss en tableau RGB lorsqu'elle arrive.
def to_rgb(shot):
	return np.frombuffer(shot.rgb, dtype=np.uint8).reshape(shot.height, shot.width, 3)


# Cette méthode permet de trouver le cadre du viewport (rectangle noir) sur une capture de l'écran noir du rejeu ; nil
# si moins d'un dixième de la fenêtre est noir.
def black_box(rgb):
	mask = rgb.max(axis=2) < BLACK
	if mask.mean() < 0.1:
		return None
	# Lignes et colonnes au moins à moitié aussi noires que la plus noire : le viewport n'occupe qu'une partie de la
	# fenêtre (explorateur, barres d'outils autour)
	row_counts, col_counts = mask.sum(axis=1), mask.sum(axis=0)
	rows = np.where(row_counts > 0.5 * row_counts.max())[0]
	cols = np.where(col_counts > 0.5 * col_counts.max())[0]
	if len(rows) == 0 or len(cols) == 0:
		return None
	top, bottom, left, right = int(rows[0]), int(rows[-1]) + 1, int(cols[0]), int(cols[-1]) + 1
	# Dimensions paires (libx264, yuv420p)
	return top, top + (bottom - top) // 2 * 2, left, left + (right - left) // 2 * 2


# Cette méthode permet de dire si une image recadrée est l'écran noir du rejeu (sur une version réduite, rapide).
def is_black(frame):
	small = frame[::8, ::8]
	return (small.max(axis=2) < BLACK).mean() >= BLACK_SHARE


def main():
	parser = argparse.ArgumentParser()
	parser.add_argument("out")
	parser.add_argument("--speed", type=float, default=0.25)
	parser.add_argument("--fps", type=int, default=60)
	parser.add_argument("--timeout", type=float, default=900)
	# Pixels retirés en haut du viewport : les boutons Roblox du coin (logo, menu, micro) restent affichés en playtest,
	# aucune API ne les cache ; ~80 px les retirent d'une fenêtre Studio en 1920x1080
	parser.add_argument("--cut-top", type=int, default=0)
	args = parser.parse_args()

	handle = find_window()
	if not handle:
		sys.exit("fenêtre Studio introuvable")
	u32.ShowWindow(handle, 9)  # SW_RESTORE
	u32.SetForegroundWindow(handle)
	rect = W.RECT()
	u32.GetWindowRect(handle, ctypes.byref(rect))
	window = {"left": rect.left, "top": rect.top, "width": rect.right - rect.left, "height": rect.bottom - rect.top}
	if u32.GetForegroundWindow() != handle:
		print("attention : Studio n'est pas au premier plan, la capture lira ce qui le couvre")
	print("en attente de l'écran noir du rejeu…", flush=True)

	begin = time.perf_counter()
	box = None
	start = None
	black_since = None
	writer = None
	written = 0
	captures = 0
	with mss.MSS() as screen:
		while time.perf_counter() - begin < args.timeout:
			shot = screen.grab(window)
			at = time.perf_counter()
			rgb = to_rgb(shot)
			if box is None:
				box = black_box(rgb)
				if box and args.cut_top:
					top, bottom, left, right = box
					top += (args.cut_top + (bottom - top - args.cut_top) % 2)
					box = (top, bottom, left, right)
				if box:
					top, bottom, left, right = box
					print(f"écran noir vu : viewport {right - left}x{bottom - top}", flush=True)
				continue
			top, bottom, left, right = box
			frame = rgb[top:bottom, left:right]
			if start is None:
				if not is_black(frame):
					start = at
					writer = imageio_ffmpeg.write_frames(
						args.out,
						(right - left, bottom - top),
						fps=args.fps,
						codec="libx264",
						pix_fmt_out="yuv420p",
						output_params=["-crf", "16", "-preset", "medium"],
						macro_block_size=1,
					)
					writer.send(None)
					print("lecture : capture en cours", flush=True)
				else:
					continue
			if is_black(frame):
				black_since = black_since or at
				if at - black_since >= TAIL_HOLD:
					break
				continue
			black_since = None
			captures += 1
			replay_time = (at - start) * args.speed
			frame_bytes = np.ascontiguousarray(frame).tobytes()
			while written / args.fps <= replay_time:
				writer.send(frame_bytes)
				written += 1
	if writer is None:
		sys.exit("aucune lecture vue : le rejeu a-t-il démarré (écran noir puis image) ?")
	writer.close()
	real = (black_since or time.perf_counter()) - start
	print(
		f"{args.out} : {written} images ({written / args.fps:.2f} s de rejeu) à {args.fps} i/s, "
		f"{captures} captures en {real:.1f} s réelles ({captures / max(real, 1e-3):.1f} i/s, "
		f"{captures / max(written / args.fps, 1e-3):.0f} captures par seconde de rejeu)"
	)


main()
