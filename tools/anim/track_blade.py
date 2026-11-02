# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "opencv-python-headless"]
# ///
"""Mesure automatique d'une lame sur une vidéo à caméra fixe : garde, pointe, profondeur et roulis à chaque image.

Remplace le relevé à l'œil quand le geste est long ou rapide : le rythme vient directement de la vidéo.

Usage : uv run tools/anim/track_blade.py <video> <debut> <fin> <garde_x,garde_y> <pointe_x,pointe_y> <roulis_debut> <sortie.json> [controle.jpg]
  garde, pointe  positions normalisées à la première image (amorce du suivi d'une image à l'autre)
  roulis_debut   roulis de la lame à la première image, en degrés (voir knife_from_roll de build_viewmodel.py)

Le roulis se déduit de la largeur apparente : il passe par 90 à chaque minimum de largeur (lame vue par la tranche).
La pointe sortie de l'écran est reconstruite depuis la garde, l'axe et la longueur des images voisines.
"""

import json
import math
import sys

import cv2
import numpy as np

SKY_ROWS = 250  # lignes de ciel pur : seuil strict pour ignorer les nuages qui dérivent
SKY_THRESHOLD = 55
THRESHOLD = 24
EDGE_WIDTH = 16  # largeur en pixels de la lame vue par la tranche
BLADE_LENGTH_STUDS = 2.35  # TIP_Z - GUARD_Z de build_viewmodel.py
DEPTH_RANGE = (2.1, 3.0)  # bornes de profondeur déjà utilisées pour l'Equip
SCREEN_ASPECT = 16 / 9
HUD_BOX = (450, 160)  # texte incrusté en haut à gauche de la vidéo
RELOCK_AFTER = 8  # après ce nombre d'images sans mesure crédible, le suivi accepte la mesure et se recale
MAX_JUMP = 60  # déplacement maximal crédible de la garde ou de la pointe en une image, en pixels
CROSSING_WIDTH = 40  # sous cette largeur, un minimum compte comme un passage par la tranche

video, start, end, guard_seed, tip_seed, first_roll, out_path = sys.argv[1:8]
sheet_path = sys.argv[8] if len(sys.argv) > 8 else None
start, end, first_roll = float(start), float(end), float(first_roll)


# Cette méthode permet de construire l'image de fond lorsque l'arme sombre traverse l'écran (percentile haut par pixel).
def background(capture, count):
	frames = []
	for i in range(0, count, 20):
		capture.set(cv2.CAP_PROP_POS_FRAMES, i)
		ok, image = capture.read()
		if ok:
			frames.append(image)
	return cv2.GaussianBlur(np.percentile(np.array(frames), 85, axis=0).astype(np.uint8), (3, 3), 0).astype(np.int16)


# Cette méthode permet d'isoler l'arme d'une image par différence avec le fond.
def foreground(image, bg):
	diff = np.abs(cv2.GaussianBlur(image, (3, 3), 0).astype(np.int16) - bg).max(axis=2)
	mask = (diff > THRESHOLD).astype(np.uint8)
	mask[:SKY_ROWS, :] = (diff[:SKY_ROWS, :] > SKY_THRESHOLD).astype(np.uint8)
	mask[: HUD_BOX[1], : HUD_BOX[0]] = 0
	return cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))


# Cette méthode permet de mesurer la lame dans une image en partant de la ligne garde-pointe de l'image précédente :
# ajuste l'axe, cherche la garde (saut de largeur) et renvoie aussi la largeur apparente.
def measure(mask, guard, tip):
	ys, xs = np.nonzero(mask)
	points = np.stack([xs, ys], 1).astype(float)
	axis = (guard - tip) / np.linalg.norm(guard - tip)
	for _ in range(3):
		normal = np.array([-axis[1], axis[0]])
		along, side = (points - guard) @ axis, (points - guard) @ normal
		band = points[(along < -40) & (along > -470) & (np.abs(side) < 55)]
		if len(band) < 30:
			return None
		mean = band.mean(0)
		fit = np.linalg.svd(band - mean, full_matrices=False)[2][0]
		axis = fit if fit @ axis > 0 else -fit
		guard = mean + axis * ((guard - mean) @ axis)
	normal = np.array([-axis[1], axis[0]])
	along, side = (points - guard) @ axis, (points - mean) @ normal
	inline = points[(along < 40) & (along > -520) & (np.abs(side) < 45)]
	top = inline[np.argmin(inline @ axis)]
	found_tip = mean + axis * ((top - mean) @ axis)
	clipped = top[1] <= 2
	bins = np.floor((points - found_tip) @ axis).astype(int)
	inside = (bins >= 0) & (bins < 520) & (np.abs(side) < 110)
	low, high = np.full(520, np.inf), np.full(520, -np.inf)
	np.minimum.at(low, bins[inside], side[inside])
	np.maximum.at(high, bins[inside], side[inside])
	profile = np.where(high >= low, high - low + 1, 0.0)
	candidates = []
	for a in range(200, 510):
		ref = np.median(profile[a - 30 : a - 5])
		if profile[a] > max(ref * 1.5, ref + 14) and profile[a + 2] > max(ref * 1.4, ref + 10):
			candidates.append(found_tip + axis * a)
	if candidates:
		best = min(candidates, key=lambda c: np.linalg.norm(c - guard))
	else:
		best = None
	stop = int((guard - found_tip) @ axis)
	width = float(np.percentile(profile[60 : max(stop - 15, 70)], 70))
	return best, found_tip, axis, width, clipped


# Cette méthode permet de remplacer les trous d'une colonne par interpolation, puis de retirer les valeurs aberrantes
# (médiane glissante) et le bruit de mesure (gaussienne) sans émousser les gestes rapides.
def clean(values, median=7, sigma=1.6):
	values = np.array([np.nan if v is None else v for v in values], float)
	index = np.arange(len(values))
	known = ~np.isnan(values)
	values = np.interp(index, index[known], values[known])
	half = median // 2
	padded = np.pad(values, half, mode="edge")
	values = np.array([np.median(padded[i : i + median]) for i in range(len(values))])
	radius = int(sigma * 3)
	kernel = np.exp(-0.5 * (np.arange(-radius, radius + 1) / sigma) ** 2)
	padded = np.pad(values, radius, mode="edge")
	return np.convolve(padded, kernel / kernel.sum(), mode="valid")


# Cette méthode permet de convertir la largeur apparente en roulis, en changeant de face à chaque passage par la
# tranche : de part et d'autre de 90, côté où se trouve le roulis de la première image au départ.
def rolls_from_width(widths, first):
	flat = np.percentile(widths, 90)
	minima = [
		i
		for i in range(8, len(widths) - 8)
		if widths[i] < CROSSING_WIDTH and widths[i] == widths[i - 8 : i + 9].min()
	]
	crossings = []
	for i in minima:
		if not crossings or i - crossings[-1] > 15:
			crossings.append(i)
	print("passages par la tranche (images) :", crossings)
	side = 1.0 if first > 90 else -1.0
	out = []
	for i, w in enumerate(widths):
		if crossings and i >= crossings[0]:
			side = -side
			crossings.pop(0)
		c = min(max((w - EDGE_WIDTH) / (flat - EDGE_WIDTH), 0.0), 1.0)
		out.append(90 + side * math.degrees(math.asin(c)))
	return out


# Cette méthode permet de déduire la profondeur de la garde depuis la longueur de lame à l'écran (lame de plat).
def depth_from_length(length):
	return min(max(BLADE_LENGTH_STUDS / (2 * max(length, 1e-3)), DEPTH_RANGE[0]), DEPTH_RANGE[1])


capture = cv2.VideoCapture(video)
fps = capture.get(cv2.CAP_PROP_FPS)
W, H = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH)), int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
bg = background(capture, int(capture.get(cv2.CAP_PROP_FRAME_COUNT)))
first, last = int(start * fps), int(end * fps)
capture.set(cv2.CAP_PROP_POS_FRAMES, first)
guard = np.array([float(v) for v in guard_seed.split(",")]) * (W, H)
tip = np.array([float(v) for v in tip_seed.split(",")]) * (W, H)

guard_misses = tip_misses = 0
raw = {k: [] for k in ("gx", "gy", "ax", "ay", "length", "width")}
sheet = []
for frame_index in range(first, last + 1):
	ok, image = capture.read()
	result = measure(foreground(image, bg), guard, tip) if ok else None
	if result is None:
		for column in raw.values():
			column.append(None)
		continue
	found_guard, found_tip, axis, width, clipped = result
	if found_guard is not None and np.linalg.norm(found_guard - guard) > MAX_JUMP and guard_misses < RELOCK_AFTER:
		found_guard = None
	guard_misses = 0 if found_guard is not None else guard_misses + 1
	if not clipped and np.linalg.norm(found_tip - tip) > MAX_JUMP and tip_misses < RELOCK_AFTER:
		clipped = True  # pointe aberrante (nuage, reflet) : traitée comme une pointe non mesurée
		tip_misses += 1
	elif not clipped:
		tip_misses = 0
	if found_guard is not None:
		guard = found_guard
	if not clipped:
		tip = found_tip
	else:
		tip = guard - axis * np.linalg.norm(guard - tip)
	raw["gx"].append(float(guard[0]) if found_guard is not None else None)
	raw["gy"].append(float(guard[1]) if found_guard is not None else None)
	raw["ax"].append(float(axis[0]))
	raw["ay"].append(float(axis[1]))
	raw["length"].append(float(np.linalg.norm(guard - tip)) if not clipped and found_guard is not None else None)
	raw["width"].append(width)
	if sheet_path and (frame_index - first) % 6 == 0:
		view = image.copy()
		cv2.line(view, tuple(int(v) for v in guard), tuple(int(v) for v in tip), (0, 255, 0), 1)
		cv2.circle(view, tuple(int(v) for v in guard), 5, (0, 255, 255), -1)
		cv2.circle(view, tuple(int(v) for v in tip), 4, (0, 0, 255), -1)
		cv2.putText(view, f"{frame_index / fps:.2f}", (W // 2 + 10, 40), 0, 1, (0, 0, 0), 2)
		sheet.append(cv2.resize(view[:, W // 2 :], (240, 270)))

gx, gy = clean(raw["gx"]), clean(raw["gy"])
ax, ay = clean(raw["ax"]), clean(raw["ay"])
lengths = clean(raw["length"])
widths = clean(raw["width"], median=5, sigma=1.0)
rolls = clean(rolls_from_width(widths, first_roll), median=9, sigma=3.0)  # le reflet qui balaie la lame gonfle la largeur
rows = []
for i in range(len(gx)):
	norm = math.hypot(ax[i], ay[i])
	tx, ty = gx[i] - ax[i] / norm * lengths[i], gy[i] - ay[i] / norm * lengths[i]
	rows.append(
		{
			"t": round(i / fps, 4),
			"guard": [round(gx[i] / W, 4), round(gy[i] / H, 4)],
			"tip": [round(tx / W, 4), round(ty / H, 4)],
			"roll": round(rolls[i], 1),
			"depth": round(depth_from_length(lengths[i] / H), 3),
		}
	)
with open(out_path, "w", encoding="utf-8") as fh:
	json.dump({"video_start": start, "video_fps": fps, "rows": rows}, fh, separators=(",", ":"))
print(f"OK {len(rows)} images -> {out_path}")

if sheet_path:
	cols = 20
	blank = np.zeros_like(sheet[0])
	lines = [np.hstack((sheet[i : i + cols] + [blank] * cols)[:cols]) for i in range(0, len(sheet), cols)]
	cv2.imwrite(sheet_path, np.vstack(lines), [cv2.IMWRITE_JPEG_QUALITY, 80])
