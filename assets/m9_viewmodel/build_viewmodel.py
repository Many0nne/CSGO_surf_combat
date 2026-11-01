# build_viewmodel.py
# Construit le rig du viewmodel M9 Bayonet dans Blender (bras droit + volume du couteau), génère ses
# animations (Equip, Shoot) et les exporte pour Roblox. Le modèle du couteau vit dans
# assets/rbx/ViewModels/M9Bayonet.rbxm : ce script ne le construit pas.
# À lancer dans Blender :
#   exec(open(f"{D}/build_viewmodel.py").read(), {"__name__": "__main__", "ASSET_DIR": D})
#
# Toute la cinématique est calculée dans le repère Roblox de la HumanoidRootPart du viewmodel
# (= caméra : X droite, Y haut, -Z avant ; unités = studs), puis affichée dans Blender via
# C (Roblox → Blender : X droite, Y avant, Z haut). Le script est la source de vérité : les clés
# Blender servent à prévisualiser, l'export JSON est calculé directement depuis les mêmes poses.

import json
import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

ASSET_DIR = globals().get("ASSET_DIR") or os.path.dirname(os.path.abspath(__file__))

FPS = 60
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
RIG_JSON = json.load(open(os.path.join(ASSET_DIR, "rig.json"), encoding="utf-8"))
ARM_PARTS = ("RightUpperArm", "RightLowerArm", "RightHand")
BONES = ("FakeCamera",) + ARM_PARTS + ("Handle",)

# Volume du couteau dans le repère de prise (origine = centre du manche, +Z = pointe, +X = tranchant)
KNIFE_SIZE = (0.926, 0.373, 3.72)
KNIFE_CENTER = Vector((-0.05, 0, 1.21))

# Géométrie du bras R15 (repères locaux des pièces, cf. Motor6D du rig Studio)
SHOULDER_IN_UA = Vector((0, 0.699, 0))  # haut du bras = « épaule » visuelle (racine IK)
ELBOW_IN_UA = Vector((0, -0.39966, 0))
ELBOW_IN_LA = Vector((0, 0.30926, 0))
WRIST_IN_LA = Vector((0, -0.59911, 0))
WRIST_IN_HAND = Vector((0, 0.14955, 0))
L_UPPER = (SHOULDER_IN_UA - ELBOW_IN_UA).length
L_LOWER = (ELBOW_IN_LA - WRIST_IN_LA).length


# Cette méthode permet de convertir des composantes de CFrame Roblox en matrice 4x4.
def cf(c):
	x, y, z, a, b, cc, d, e, f, g, h, i = c
	return Matrix(((a, b, cc, x), (d, e, f, y), (g, h, i, z), (0, 0, 0, 1)))


# Cette méthode permet de convertir une matrice 4x4 (orthonormalisée) en composantes de CFrame.
def to_cf(m):
	r = m.to_3x3().normalized()
	t = m.translation
	return [t.x, t.y, t.z, r[0][0], r[0][1], r[0][2], r[1][0], r[1][1], r[1][2], r[2][0], r[2][1], r[2][2]]


# Cette méthode permet de construire une matrice depuis une position et une rotation 3x3.
def frame(pos, rot3):
	m = rot3.to_4x4()
	m.translation = pos
	return m


# Cette méthode permet de construire une rotation (degrés) appliquée dans l'ordre roulis Z, lacet Y,
# tangage X, autour des axes du repère caméra Roblox.
def rot_deg(rx, ry, rz):
	return Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "ZYX").to_matrix()


# Cette méthode permet de calculer la plus petite rotation qui amène le vecteur a sur le vecteur b.
def swing(a, b):
	return a.normalized().rotation_difference(b.normalized()).to_matrix()


# Cette méthode permet de construire un repère orthonormé à partir d'un axe principal (Z) et d'une
# direction secondaire approchée (X) ; renvoie la rotation dont les colonnes sont X, Y, Z.
def basis_zx(z_dir, x_hint):
	z = z_dir.normalized()
	x = (x_hint - z * x_hint.dot(z)).normalized()
	y = z.cross(x)
	return Matrix((x, y, z)).transposed()


# ------------------------------------------------------------------------------------------------
# Tenue du couteau et pose idle (= pose de repos du rig dans Studio)
# ------------------------------------------------------------------------------------------------
# Prise : repère de la Handle dans le repère de la main. Prise marteau (axe du couteau en travers du
# poing, tranchant vers l'avant de l'avant-bras) inclinée de GRIP_TILT autour de la normale paume.
GRIP_TILT = 35


# Cette méthode permet de calculer le CFrame de la Handle dans le repère de la main (prise).
def grip_matrix():
	a = math.radians(GRIP_TILT)
	z = Vector((-math.cos(a), -math.sin(a), 0))  # axe couteau
	x = Vector((math.sin(a), -math.cos(a), 0))  # tranchant
	return frame(Vector((0, 0, 0)), Matrix((x, z.cross(x), z)).transposed())


GRIP = grip_matrix()

# Pose idle : centre de poignée, axe du couteau, direction approchée du tranchant (repère caméra)
IDLE_POS = Vector((1.7, -1.5, -2.7))
IDLE_AXIS = Vector((-0.78, 0.42, -0.46))
IDLE_EDGE = Vector((-0.2, -1, -0.3))
SHOULDER = Vector((2.6, -2.7, -1.0))
POLE = Vector((3.8, -3.0, -1.5))
IDLE_KNIFE = frame(IDLE_POS, basis_zx(IDLE_AXIS, IDLE_EDGE))


# Cette méthode permet de résoudre le bras (épaule, coude, poignet) pour une pose de couteau donnée
# et de renvoyer le CFrame (repère caméra) de chaque pièce du bras et de la Handle.
def solve_arm(knife, shoulder, pole):
	hand = knife @ GRIP.inverted()
	hr = hand.to_3x3().normalized()
	wrist = hand @ WRIST_IN_HAND
	d_vec = wrist - shoulder
	dirn = d_vec.normalized()
	reach = (L_UPPER + L_LOWER) * 0.985
	if d_vec.length > reach:
		# cible hors de portée : l'épaule (hors champ) suit la main plutôt que de la décrocher du bras
		shoulder = wrist - dirn * reach
	d = min(d_vec.length, reach)
	a = (L_UPPER**2 - L_LOWER**2 + d * d) / (2 * d)
	h = math.sqrt(max(0.0, L_UPPER**2 - a * a))
	p = pole - shoulder
	bend = (p - dirn * p.dot(dirn)).normalized()
	elbow = shoulder + dirn * a + bend * h
	wrist = shoulder + dirn * d
	# avant-bras : orientation de la main, ramenée sur l'axe coude→poignet (+Y local = vers le coude)
	lr = swing(hr.col[1], elbow - wrist) @ hr
	lower = frame(wrist - lr @ WRIST_IN_LA, lr)
	ur = swing(lr.col[1], shoulder - elbow) @ lr
	upper = frame(elbow - ur @ ELBOW_IN_UA, ur)
	return {"RightUpperArm": upper, "RightLowerArm": lower, "RightHand": frame(hand.translation, hr), "Handle": knife}


# ------------------------------------------------------------------------------------------------
# Rig Roblox : C0 d'origine, C1 recalculés pour que la pose de repos soit l'idle
# ------------------------------------------------------------------------------------------------


# Cette méthode permet de calculer les Motor6D du viewmodel M9 (C0 conservés, C1 recalculés) pour
# que Part1 = Part0 · C0 · C1⁻¹ redonne exactement la pose idle quand aucune animation ne joue.
def build_motors(idle):
	rest = dict(idle)
	rest["HumanoidRootPart"] = cf(RIG_JSON["parts"]["HumanoidRootPart"]["cf"])
	rest["FakeCamera"] = cf(RIG_JSON["parts"]["FakeCamera"]["cf"])
	src = {m["name"]: m for m in RIG_JSON["motors"]}
	motors = []
	for name, p0, p1 in (
		("FakeCamera", "HumanoidRootPart", "FakeCamera"),
		("RightShoulder", "FakeCamera", "RightUpperArm"),
		("RightElbow", "RightUpperArm", "RightLowerArm"),
		("RightWrist", "RightLowerArm", "RightHand"),
	):
		c0 = cf(src[name]["c0"])
		c1 = rest[p1].inverted() @ rest[p0] @ c0
		motors.append({"name": name, "p0": p0, "p1": p1, "c0": c0, "c1": c1})
	motors.append({"name": "Handle", "p0": "RightHand", "p1": "Handle", "c0": Matrix.Identity(4), "c1": GRIP.inverted()})
	return rest, motors


# ------------------------------------------------------------------------------------------------
# Scène Blender (prévisualisation)
# ------------------------------------------------------------------------------------------------


# Cette méthode permet de créer (ou remplacer) un objet maillé à partir d'un bmesh.
def mesh_object(name, bm, mat):
	old = bpy.data.objects.get(name)
	if old:
		bpy.data.objects.remove(old, do_unlink=True)
	me = bpy.data.meshes.new(name)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bm.to_mesh(me)
	bm.free()
	ob = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(ob)
	me.materials.append(mat)
	return ob


# Cette méthode permet de créer un matériau Principled de prévisualisation (le rendu final vient des
# MeshParts dans Studio).
def material(name, color, metallic, roughness):
	mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
	mat.use_nodes = True
	bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
	bsdf.inputs["Base Color"].default_value = (*color, 1)
	bsdf.inputs["Metallic"].default_value = metallic
	bsdf.inputs["Roughness"].default_value = roughness
	mat.diffuse_color = (*color, 1)
	return mat


# Cette méthode permet de créer une boîte de la taille d'une pièce Roblox, décalée de `center` par
# rapport à son origine.
def box_object(name, size, mat, center=Vector((0, 0, 0))):
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1)
	for v in bm.verts:
		v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + center
	return mesh_object(name, bm, mat)


# Cette méthode permet de construire l'armature (un os par pièce animée, sans hiérarchie : les poses
# sont écrites directement dans le repère armature), d'y attacher bras et couteau et de placer la
# caméra du jeu (FOV vertical 70°).
def build_scene(rest):
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	for coll in (bpy.data.armatures, bpy.data.cameras, bpy.data.lights):
		for block in list(coll):
			coll.remove(block)
	knife = {"Handle": box_object("Handle", KNIFE_SIZE, material("Knife_Proxy", (0.05, 0.05, 0.06), 0.8, 0.4), KNIFE_CENTER)}
	skin = material("Arm_Skin", (0.64, 0.635, 0.647), 0.0, 0.7)
	arms = {n: box_object(n, RIG_JSON["parts"][n]["size"], skin) for n in ARM_PARTS}

	arm_data = bpy.data.armatures.new("Rig")
	rig = bpy.data.objects.new("Rig", arm_data)
	bpy.context.scene.collection.objects.link(rig)
	bpy.context.view_layer.objects.active = rig
	bpy.ops.object.mode_set(mode="EDIT")
	for n in BONES:
		eb = arm_data.edit_bones.new(n)
		eb.head, eb.tail = (0, 0, 0), (0, 0.3, 0)
		eb.matrix = C @ rest[n]
	bpy.ops.object.mode_set(mode="OBJECT")
	bpy.context.view_layer.update()

	children = dict(arms)
	children.update({k: v for k, v in knife.items()})
	for name, ob in children.items():
		bone = name if name in BONES else "Handle"
		ob.parent = rig
		ob.parent_type = "BONE"
		ob.parent_bone = bone
		bpy.context.view_layer.update()
		ob.matrix_world = C @ (rest[bone] if name in BONES and name != "Handle" else rest["Handle"])

	cam_data = bpy.data.cameras.new("GameCam")
	cam_data.sensor_fit = "VERTICAL"
	cam_data.angle = math.radians(70)
	cam_data.clip_start = 0.05
	cam = bpy.data.objects.new("GameCam", cam_data)
	cam.rotation_euler = (math.radians(90), 0, 0)
	bpy.context.scene.collection.objects.link(cam)
	scene = bpy.context.scene
	scene.camera = cam
	scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
	scene.render.fps = FPS
	sun = bpy.data.lights.new("Sun", "SUN")
	sun.energy = 3
	sun_ob = bpy.data.objects.new("Sun", sun)
	sun_ob.rotation_euler = (math.radians(50), math.radians(10), math.radians(-30))
	scene.collection.objects.link(sun_ob)
	return rig


# ------------------------------------------------------------------------------------------------
# Courbes d'animation
# ------------------------------------------------------------------------------------------------


# Cette méthode permet d'appliquer une courbe d'accélération à une progression s ∈ [0, 1].
def ease(kind, s):
	s = min(max(s, 0.0), 1.0)
	if kind == "l":
		return s
	if kind == "i":
		return s * s * s
	if kind == "o":
		return 1 - (1 - s) ** 3
	if kind == "o5":
		return 1 - (1 - s) ** 5
	if kind == "io":
		return s * s * (3 - 2 * s)
	raise ValueError(kind)


# Cette méthode permet d'évaluer une piste de clés [(t, (x, y, z), easing d'arrivée)] à l'instant t.
def track(keys, t):
	if t <= keys[0][0]:
		return Vector(keys[0][1])
	for (t0, v0, _), (t1, v1, e1) in zip(keys, keys[1:], strict=False):
		if t <= t1:
			s = ease(e1, (t - t0) / (t1 - t0)) if t1 > t0 else 1.0
			return Vector(v0).lerp(Vector(v1), s)
	return Vector(keys[-1][1])


# Cette méthode permet de faire suivre une série de cibles par un ressort amorti (inertie de la main)
# lorsque l'animation doit garder un peu de dépassement sans clés supplémentaires.
def spring(targets, freq, zeta, substeps=8):
	w = 2 * math.pi * freq
	dt = 1.0 / FPS / substeps
	pos = targets[0].copy()
	vel = Vector((0, 0, 0))
	out = []
	for tgt in targets:
		for _ in range(substeps):
			acc = (tgt - pos) * (w * w) - vel * (2 * zeta * w)
			vel += acc * dt
			pos += vel * dt
		out.append(pos.copy())
	return out


# Cette méthode permet de ramener exactement une série à zéro sur ses dernières frames, pour que
# l'animation se termine pile sur la pose de repos (pas de saut quand la piste s'arrête).
def settle_tail(series, seconds):
	n = len(series)
	k = max(2, int(seconds * FPS))
	for i in range(max(0, n - k), n):
		s = (i - (n - k)) / (k - 1)
		series[i] = series[i] * (1 - ease("io", s))
	return series


Z = (0, 0, 0)


# Cette méthode permet de construire une fonction de piste à partir d'une liste de clés.
def K(keys):
	return lambda t: track(keys, t)


# Cette méthode permet de décrire l'Equip : la main remonte du bas-droite, couteau pointé vers le
# bas, le redresse en pivotant le poignet, présente le plat de la lame puis se cale sur l'idle.
def spec_equip():
	return dict(
		length=1.0,
		freq=7.0,
		zeta=0.65,
		settle=0.2,
		pos=K([(0.0, (0.75, -1.9, 0.5), "l"), (0.08, (0.62, -1.45, 0.38), "i"), (0.42, (-0.06, 0.1, -0.06), "o"), (0.56, Z, "io")]),
		# rotation caméra (tangage X : + vers le haut, lacet Y : + vers la gauche, roulis Z), puis
		# roulis autour de l'axe du couteau
		rot=K([(0.0, (60, -40, 35), "l"), (0.08, (55, -36, 32), "i"), (0.44, (-5, 4, -3), "o"), (0.58, Z, "io")]),
		roll=K([(0.0, (-110, 0, 0), "l"), (0.44, (8, 0, 0), "o"), (0.56, Z, "io"), (0.7, (28, 0, 0), "io"), (0.86, Z, "io")]),
		shoulder=K([(0.0, (0.3, -0.7, 0.5), "l"), (0.45, Z, "o")]),
		markers=[("Equip Sound", 0.02)],
	)


# Cette méthode permet de décrire le Shoot (slash) : armé vers le haut-droite en tournant le
# tranchant vers la gauche, balayage rapide en diagonale vers le bas-gauche, accompagnement, retour.
def spec_shoot():
	t_wind, t_hit, t_end = 0.1, 0.19, 0.29
	return dict(
		length=0.7,
		freq=11.0,
		zeta=0.72,
		settle=0.25,
		pos=K([(0.0, Z, "l"), (t_wind, (0.4, 0.45, 0.3), "o"), (t_hit, (-1.3, 0.6, -0.45), "io"), (t_end, (-1.95, 0.25, -0.25), "o"), (0.58, Z, "io")]),
		# armé : lame dressée vers le haut, plat face caméra ; la pointe décrit ensuite un arc vers la
		# gauche, tranchant devant (vers le bas-gauche), et finit un peu plongée en accompagnement
		rot=K([(0.0, Z, "l"), (t_wind, (0, -35, -60), "o"), (t_hit, (-5, -5, 0), "io"), (t_end, (-25, 0, 0), "o"), (0.58, Z, "io")]),
		roll=K([(0.0, Z, "l"), (t_wind, (10, 0, 0), "o"), (t_hit, (30, 0, 0), "io"), (t_end, (0, 0, 0), "o"), (0.58, Z, "io")]),
		shoulder=K([(0.0, Z, "l"), (t_wind, (0.15, 0.15, 0.25), "o"), (t_end, (-0.7, 0.1, -0.35), "o"), (0.58, Z, "io")]),
		markers=[("Stab Sound", (t_wind + t_hit) / 2)],
	)


SPECS = {"Equip": spec_equip, "Shoot": spec_shoot}


# Cette méthode permet d'échantillonner une animation (pistes + ressort) et de renvoyer, pour chaque
# frame, les CFrames (repère caméra) des pièces du bras et de la Handle.
def sample(spec):
	n = int(round(spec["length"] * FPS)) + 1
	ts = [i / FPS for i in range(n)]
	chans = {k: [spec[k](t) for t in ts] for k in ("pos", "rot", "roll", "shoulder")}
	for k in ("pos", "rot", "shoulder"):
		chans[k] = settle_tail(spring(chans[k], spec["freq"], spec["zeta"]), spec["settle"])
	chans["roll"] = settle_tail(chans["roll"], spec["settle"])
	idle_r = IDLE_KNIFE.to_3x3()
	frames = []
	for i in range(n):
		r = rot_deg(*chans["rot"][i]) @ idle_r @ Matrix.Rotation(math.radians(chans["roll"][i].x), 3, "Z")
		knife = frame(IDLE_POS + chans["pos"][i], r)
		frames.append(solve_arm(knife, SHOULDER + chans["shoulder"][i], POLE + chans["shoulder"][i]))
	return ts, frames


# ------------------------------------------------------------------------------------------------
# Clés Blender et export Roblox
# ------------------------------------------------------------------------------------------------


# Cette méthode permet d'écrire les clés d'une animation sur l'armature (prévisualisation Blender).
def key_action(rig, name, frames, markers):
	act = bpy.data.actions.get("M9_" + name)
	if act:
		bpy.data.actions.remove(act)
	act = bpy.data.actions.new("M9_" + name)
	act.use_fake_user = True
	rig.animation_data_create()
	rig.animation_data.action = act
	for f, poses in enumerate(frames):
		for n in ARM_PARTS + ("Handle",):
			pb = rig.pose.bones[n]
			pb.rotation_mode = "QUATERNION"
			basis = rig.data.bones[n].matrix_local.inverted() @ (C @ poses[n])
			loc, rot, _ = basis.decompose()
			pb.location, pb.rotation_quaternion = loc, rot
			pb.keyframe_insert("location", frame=f, group=n)
			pb.keyframe_insert("rotation_quaternion", frame=f, group=n)
	for m in list(act.pose_markers):
		act.pose_markers.remove(m)
	for mname, mt in markers:
		act.pose_markers.new(mname).frame = int(round(mt * FPS))
	act.frame_range = (0, len(frames) - 1)
	act.use_frame_range = True
	return act


# Cette méthode permet de convertir les poses d'une animation en Transform de chaque Motor6D
# (Part1 = Part0 · C0 · Transform · C1⁻¹  ⇒  Transform = C0⁻¹ · Part0⁻¹ · Part1 · C1) et de les
# écrire en JSON pour make_rbxm.luau (une keyframe toutes les `step` frames, plus la dernière).
def export_json(name, ts, frames, markers, rest, motors, out_dir, step=2):
	animated = [m for m in motors if m["p1"] in ARM_PARTS or m["p1"] == "FakeCamera"]
	out = []
	keep = sorted(set(range(0, len(ts), step)) | {len(ts) - 1})
	for i in keep:
		t, poses = ts[i], frames[i]
		world = dict(rest)
		world.update(poses)
		entry = {}
		for m in animated:
			tr = m["c0"].inverted() @ world[m["p0"]].inverted() @ world[m["p1"]] @ m["c1"]
			entry[m["p1"]] = [round(v, 4) for v in to_cf(tr)]
		out.append({"t": round(t, 4), "poses": entry})
	data = {
		"name": name,
		"loop": False,
		"frames": out,
		"markers": [{"name": n, "t": round(t, 4)} for n, t in markers],
		"parents": {m["p1"]: m["p0"] for m in animated},
	}
	with open(os.path.join(out_dir, "anim_%s.json" % name), "w", encoding="utf-8") as fh:
		json.dump(data, fh)


# Cette méthode permet d'exporter le rig Studio cible (C0/C1 des Motor6D, CFrames de repos) pour que
# le viewmodel ViewModels.M9Bayonet soit monté à l'identique dans Studio.
def export_rig(rest, motors, out_dir):
	data = {
		"motors": [{"name": m["name"], "p0": m["p0"], "p1": m["p1"], "c0": to_cf(m["c0"]), "c1": to_cf(m["c1"])} for m in motors],
		"rest": {n: to_cf(rest[n]) for n in ("FakeCamera",) + ARM_PARTS + ("Handle",)},
	}
	with open(os.path.join(out_dir, "m9_rig.json"), "w", encoding="utf-8") as fh:
		json.dump(data, fh, indent=1)


# Cette méthode permet de tout reconstruire : scène, animations, exports (JSON, rig).
def build(export=True):
	idle = solve_arm(IDLE_KNIFE, SHOULDER, POLE)
	rest, motors = build_motors(idle)
	rig = build_scene(rest)
	out_dir = os.path.join(ASSET_DIR, "export")
	os.makedirs(out_dir, exist_ok=True)
	results = {}
	for name, fn in SPECS.items():
		spec = fn()
		ts, frames = sample(spec)
		key_action(rig, name, frames, spec["markers"])
		if export:
			export_json(name, ts, frames, spec["markers"], rest, motors, out_dir)
		results[name] = len(frames)
	rig.animation_data.action = None
	if export:
		export_rig(rest, motors, out_dir)
	return results


if __name__ == "__main__":
	print(build(export=globals().get("EXPORT", True)))
