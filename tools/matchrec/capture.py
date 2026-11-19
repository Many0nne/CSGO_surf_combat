# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow", "mss", "numpy", "imageio-ffmpeg", "soundcard"]
# ///
"""Filme un rejeu de partie (#582, debug/MatchReplay) dans Studio et en tire une vidéo fluide à vitesse normale, avec
le son de jeu (#586) (docs/promo.md, « Enregistreur de partie »).

Deux passes sur le même segment (MatchReplayFrom / MatchReplayTo inchangés) :

1. Son : uv run tools/matchrec/capture.py <son.wav>
   Rejeu à vitesse 1 avec l'attribut joueur MatchReplayAudio = true. Le son du poste (boucle WASAPI de la sortie par
   défaut) est enregistré ; le rejeu joue un bip BEEP_LEAD s avant sa lecture, pendant l'écran noir : le son est coupé
   à partir de ce bip + BEEP_LEAD, donc calé sur l'instant 0 du rejeu à la milliseconde près.
2. Image : uv run tools/matchrec/capture.py <sortie.mp4> [--speed 0.25] [--audio <son.wav>] [--fps 60] [--cut-top 80]
   Rejeu au ralenti (MatchReplaySpeed = la même vitesse, MatchReplayAudio = false). Le rejeu commence par un écran noir
   (repère) : l'outil y relève le cadre du viewport, prend le départ à la première image non noire, puis s'arrête à
   l'écran noir de fin. Chaque capture est placée à l'instant du rejeu qu'elle montre (temps réel × vitesse) ; la
   vidéo est écrite à `fps` images/s sur ce temps-là : au quart de la vitesse, une capture d'écran à ~25 i/s donne
   ~100 images par seconde de rejeu, assez pour 60 i/s nettes même si Studio rame. Avec --audio, le son de la passe 1
   est ajouté à la vidéo (AAC).

Lancer l'outil, puis le rejeu (attribut MatchReplay ou MatchReplayRun). Studio doit rester au premier plan (la capture
lit l'écran, cf. tools/anim/record_window.py) et le son du poste ne doit jouer que Studio pendant la passe 1.
"""

import argparse
import ctypes
import ctypes.wintypes as W
import os
import subprocess
import sys
import threading
import time
import warnings
import wave

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
# Passe du son : bip joué par le rejeu BEEP_LEAD s avant sa lecture (même valeur que BEEP_LEAD de MatchReplay.luau)
BEEP_LEAD = 0.5
SAMPLE_RATE = 48000
# Crête (0-1) sous laquelle aucun bip n'a été entendu (Studio muet, autre sortie audio)
BEEP_MIN_PEAK = 0.01
# Début du bip : premier échantillon au-dessus de cette part de sa crête
BEEP_ONSET_SHARE = 0.25
# Demi-largeur (s) de la fenêtre où le bip est cherché, autour de BEEP_LEAD s avant la première image vue à l'écran
BEEP_WINDOW = 0.35
# Son gardé après la fin de la lecture vue à l'écran (s) : la vidéo, plus courte, coupe le reste
AUDIO_MARGIN = 0.5
# Blocs lus dans la boucle (échantillons, ~10 ms) ; un bloc arrivé plus de GAP s après la fin du précédent suit un silence
# que Windows n'a pas transmis (la boucle WASAPI ne livre rien quand rien ne joue) : il est rendu en zéros
BLOCK = 480
GAP = 0.02


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


# Cette méthode permet de mettre Studio au premier plan et de lire le cadre de sa fenêtre lorsque la capture démarre.
def studio_window():
	handle = find_window()
	if not handle:
		sys.exit("fenêtre Studio introuvable")
	u32.ShowWindow(handle, 9)  # SW_RESTORE
	u32.SetForegroundWindow(handle)
	rect = W.RECT()
	u32.GetWindowRect(handle, ctypes.byref(rect))
	if u32.GetForegroundWindow() != handle:
		print("attention : Studio n'est pas au premier plan, la capture lira ce qui le couvre")
	return {"left": rect.left, "top": rect.top, "width": rect.right - rect.left, "height": rect.bottom - rect.top}


# Cette méthode permet de suivre le rejeu à l'écran lorsqu'une passe tourne : écran noir de départ (cadre du viewport),
# première image (départ), écran noir de fin ; `on_frame(image, instant)` reçoit chaque image de la lecture. Renvoie le
# départ et la fin (perf_counter), départ nil si aucune lecture n'a été vue.
def watch(window, timeout, cut_top, on_frame=None):
	print("en attente de l'écran noir du rejeu…", flush=True)
	begin = time.perf_counter()
	box = None
	start = None
	black_since = None
	with mss.MSS() as screen:
		while time.perf_counter() - begin < timeout:
			shot = screen.grab(window)
			at = time.perf_counter()
			rgb = to_rgb(shot)
			if box is None:
				box = black_box(rgb)
				if box and cut_top:
					top, bottom, left, right = box
					top += cut_top + (bottom - top - cut_top) % 2
					box = (top, bottom, left, right)
				if box:
					top, bottom, left, right = box
					print(f"écran noir vu : viewport {right - left}x{bottom - top}", flush=True)
				continue
			top, bottom, left, right = box
			frame = rgb[top:bottom, left:right]
			if start is None:
				if is_black(frame):
					continue
				start = at
				print("lecture : capture en cours", flush=True)
			if is_black(frame):
				black_since = black_since or at
				if at - black_since >= TAIL_HOLD:
					break
				continue
			black_since = None
			if on_frame:
				on_frame(frame, at - start)
	return start, (black_since or time.perf_counter())


# Cette méthode permet d'écrire un son stéréo flottant (-1 à 1) en WAV 16 bits lorsque la passe du son se termine.
def write_wav(path, data):
	pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
	with wave.open(path, "wb") as out:
		out.setnchannels(pcm.shape[1])
		out.setsampwidth(2)
		out.setframerate(SAMPLE_RATE)
		out.writeframes(pcm.tobytes())


# Cette méthode permet de recoller les blocs de la boucle sur l'horloge lorsqu'ils sont tous lus : chaque bloc est daté à
# son arrivée, les silences non transmis (écart de plus de GAP) redeviennent des zéros. Renvoie le son et l'instant
# (perf_counter) de son premier échantillon.
def timeline(blocks):
	if not blocks:
		return np.zeros((0, 2)), time.perf_counter()
	first_at, first = blocks[0]
	origin = first_at - len(first) / SAMPLE_RATE
	parts, pos = [], 0
	for arrived, block in blocks:
		expected = round((arrived - origin) * SAMPLE_RATE) - len(block)
		if expected - pos > GAP * SAMPLE_RATE:
			parts.append(np.zeros((expected - pos, block.shape[1]), dtype=block.dtype))
			pos = expected
		parts.append(block)
		pos += len(block)
	return np.concatenate(parts), origin


# Cette méthode permet d'enregistrer le son du poste pendant le rejeu à vitesse 1, puis de le couper à l'instant 0 du
# rejeu d'après le bip de synchro (passe du son).
def audio_pass(args):
	import soundcard as sc

	warnings.simplefilter("ignore", sc.SoundcardRuntimeWarning)
	window = studio_window()
	speaker = sc.default_speaker()
	print(f"son enregistré : {speaker.name} (boucle)", flush=True)
	blocks = []
	stop = threading.Event()
	ready = threading.Event()

	# Cette méthode permet de lire la boucle de la sortie audio par blocs datés lorsqu'elle tourne (fil à part).
	def record():
		mic = sc.get_microphone(id=str(speaker.name), include_loopback=True)
		with mic.recorder(samplerate=SAMPLE_RATE, channels=2, blocksize=BLOCK) as rec:
			ready.set()
			while not stop.is_set():
				block = rec.record(numframes=BLOCK)
				blocks.append((time.perf_counter(), block))

	thread = threading.Thread(target=record, daemon=True)
	thread.start()
	ready.wait(10)
	start, end = watch(window, args.timeout, 0)
	stop.set()
	thread.join(5)
	if start is None:
		sys.exit("aucune lecture vue : le rejeu a-t-il démarré (écran noir puis image) ?")
	data, origin = timeline(blocks)
	# Bip cherché pendant l'écran noir, autour de BEEP_LEAD s avant la lecture vue à l'écran : avant l'écran noir, le
	# menu peut jouer sa musique (coupée par le rejeu dès son départ)
	low = max(0, int((start - origin - BEEP_LEAD - BEEP_WINDOW) * SAMPLE_RATE))
	high = max(low + 1, int((start - origin - BEEP_LEAD + BEEP_WINDOW) * SAMPLE_RATE))
	level = np.abs(data[low:high]).max(axis=1)
	peak = float(level.max()) if len(level) else 0.0
	if peak < BEEP_MIN_PEAK:
		sys.exit(
			f"bip introuvable (crête {peak:.4f}) : MatchReplayAudio = true ? Studio muet ou sur une autre sortie que "
			f"{speaker.name} ?"
		)
	onset = low + int(np.argmax(level >= BEEP_ONSET_SHARE * peak))
	first = onset + int(BEEP_LEAD * SAMPLE_RATE)
	length = int((end - start + AUDIO_MARGIN) * SAMPLE_RATE)
	clip = data[first : first + length]
	write_wav(args.out, clip)
	# Écart entre l'instant 0 calé sur le bip et la première image vue à l'écran : retard de l'affichage et de la capture
	screen_lag = (start - origin) - first / SAMPLE_RATE
	print(
		f"{args.out} : {len(clip) / SAMPLE_RATE:.2f} s de son, bip à {onset / SAMPLE_RATE:.3f} s (crête {peak:.2f}), "
		f"crête du jeu {float(np.abs(clip).max()) if len(clip) else 0:.2f} ; première image vue à l'écran "
		f"{screen_lag * 1000:+.0f} ms après l'instant 0 du son"
	)


# Cette méthode permet d'ajouter le son de la passe 1 à la vidéo lorsqu'elle est écrite (--audio) : image copiée, son en
# AAC, coupé à la durée de la vidéo.
def mux(video, audio):
	muxed = video + ".son.mp4"
	result = subprocess.run(
		[
			imageio_ffmpeg.get_ffmpeg_exe(),
			"-y",
			"-loglevel",
			"error",
			"-i",
			video,
			"-i",
			audio,
			"-map",
			"0:v:0",
			"-map",
			"1:a:0",
			"-c:v",
			"copy",
			"-c:a",
			"aac",
			"-b:a",
			"192k",
			"-shortest",
			muxed,
		],
		capture_output=True,
		text=True,
	)
	if result.returncode != 0:
		sys.exit(f"ajout du son impossible : {result.stderr.strip()}")
	os.replace(muxed, video)
	print(f"{video} : son de {audio} ajouté")


# Cette méthode permet de filmer le rejeu au ralenti et d'écrire la vidéo à vitesse normale (passe de l'image).
def video_pass(args):
	window = studio_window()
	state = {"writer": None, "written": 0, "captures": 0}

	# Cette méthode permet de placer une capture à l'instant du rejeu qu'elle montre lorsqu'elle arrive.
	def on_frame(frame, elapsed):
		if state["writer"] is None:
			height, width = frame.shape[:2]
			writer = imageio_ffmpeg.write_frames(
				args.out,
				(width, height),
				fps=args.fps,
				codec="libx264",
				pix_fmt_out="yuv420p",
				output_params=["-crf", "16", "-preset", "medium"],
				macro_block_size=1,
			)
			writer.send(None)
			state["writer"] = writer
		state["captures"] += 1
		replay_time = elapsed * args.speed
		frame_bytes = np.ascontiguousarray(frame).tobytes()
		while state["written"] / args.fps <= replay_time:
			state["writer"].send(frame_bytes)
			state["written"] += 1

	start, end = watch(window, args.timeout, args.cut_top, on_frame)
	writer = state["writer"]
	if writer is None:
		sys.exit("aucune lecture vue : le rejeu a-t-il démarré (écran noir puis image) ?")
	writer.close()
	real = end - start
	written, captures = state["written"], state["captures"]
	print(
		f"{args.out} : {written} images ({written / args.fps:.2f} s de rejeu) à {args.fps} i/s, "
		f"{captures} captures en {real:.1f} s réelles ({captures / max(real, 1e-3):.1f} i/s, "
		f"{captures / max(written / args.fps, 1e-3):.0f} captures par seconde de rejeu)"
	)
	if args.audio:
		mux(args.out, args.audio)


def main():
	parser = argparse.ArgumentParser()
	parser.add_argument("out", help="vidéo .mp4 (passe de l'image) ou son .wav (passe du son, rejeu à vitesse 1)")
	parser.add_argument("--speed", type=float, default=0.25)
	parser.add_argument("--fps", type=int, default=60)
	parser.add_argument("--timeout", type=float, default=900)
	# Pixels retirés en haut du viewport : les boutons Roblox du coin (logo, menu, micro) restent affichés en playtest,
	# aucune API ne les cache ; ~80 px les retirent d'une fenêtre Studio en 1920x1080
	parser.add_argument("--cut-top", type=int, default=0)
	parser.add_argument("--audio", help="son de la passe du son (.wav) à ajouter à la vidéo")
	args = parser.parse_args()
	if args.out.lower().endswith(".wav"):
		audio_pass(args)
	else:
		video_pass(args)


main()
