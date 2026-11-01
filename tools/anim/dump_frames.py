"""Exporte toutes les frames d'une animation pour studio_render.luau et affiche ses vitesses de rotation.

À lancer sans toucher au Blender ouvert :
  blender -b --factory-startup --python tools/anim/dump_frames.py -- <dossier_build_viewmodel> <Animation> <sortie.json>

Le tableau de vitesses se lit avant tout rendu : une rotation propre monte puis redescend, sans creux ni pic isolé, et
une main qui tient un couteau en rotation doit rester à 0.
"""

import json
import math
import os
import sys

from mathutils import Vector

asset_dir, anim, out_path = sys.argv[sys.argv.index("--") + 1 :]
ns = {"__name__": "lib", "ASSET_DIR": asset_dir}
with open(os.path.join(asset_dir, "build_viewmodel.py"), encoding="utf-8") as fh:
	exec(fh.read(), ns)
to_cf, GRIP = ns["to_cf"], ns["GRIP"]
ts, frames = ns["sample"](ns["SPECS"][anim]())

# La Handle du script est le centre du manche ; studio_render.luau la recale sur le mesh réel via la main virtuelle.
data = {}
for i, f in enumerate(frames):
	data[f"{anim}_{i:03d}"] = {
		name: [round(v, 5) for v in to_cf(m @ GRIP.inverted() if name == "Handle" else m)] for name, m in f.items()
	}
with open(out_path, "w", encoding="utf-8") as fh:
	json.dump(data, fh)


# Cette méthode permet de projeter un point du repère caméra à l'écran, en unités de hauteur d'écran.
def project(point):
	return point.x / -point.z, point.y / -point.z


print(" temps  lame  d_lame  d_main   (degrés par 1/30 s)")
total = previous = last_blade = last_hand = None
for i, (t, f) in enumerate(zip(ts, frames, strict=True)):
	knife, hand = f["Handle"], f["RightHand"]
	a, b = project(knife @ Vector((0, 0, -0.65))), project(knife @ Vector((0, 0, 3.07)))
	angle = math.degrees(math.atan2(b[0] - a[0], b[1] - a[1]))
	total = angle if total is None else total + ((angle - previous + 180) % 360 - 180)
	previous = angle
	if i % 2 == 0:
		q = hand.to_3x3().to_quaternion()
		turn = math.degrees(last_hand.rotation_difference(q).angle) if last_hand else 0.0
		print(f"{t:6.2f} {total:5.0f} {total - (last_blade if last_blade is not None else total):7.1f} {min(turn, 360 - turn):7.1f}")
		last_blade, last_hand = total, q
print(f"OK {len(data)} frames -> {out_path}")
