# build_viewmodel.py
# Construit le rig du viewmodel M9 Bayonet dans Blender (bras droit + volume du couteau), génère ses
# animations (Idle, Equip, Shoot, Shoot2, Inspect) et les exporte pour Roblox. Le modèle du couteau vit dans
# assets/rbx/ViewModels/M9Bayonet.rbxm : ce script ne le construit pas.
# À lancer dans Blender :
#   exec(open(f"{D}/build_viewmodel.py").read(), {"__name__": "__main__", "ASSET_DIR": D})
#
# Toute la cinématique est calculée dans le repère Roblox de la HumanoidRootPart du viewmodel
# (= caméra : X droite, Y haut, -Z avant ; unités = studs), puis affichée dans Blender via
# C (Roblox → Blender : X droite, Y avant, Z haut). Le script est la source de vérité : les clés
# Blender servent à prévisualiser, l'export JSON est calculé directement depuis les mêmes poses.
# Une pose se décrit par des directions (position du manche, axe manche → pointe, sens du tranchant), jamais
# par des angles d'Euler : l'orientation de la lame à l'écran se lit directement dans les clés.

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
LEFT_PARTS = ("LeftUpperArm", "LeftLowerArm", "LeftHand")
BONES = ("FakeCamera",) + ARM_PARTS + LEFT_PARTS + ("Handle",)

# Volume du couteau dans le repère de prise (origine = centre du manche, +Z = pointe, +X = tranchant)
# Mesure du mesh Studio : Z de -0,65 (pommeau) à 3,07 (pointe), garde vers Z = 0,72.
BLADE_OUTLINE = ((-0.3, 0.72), (0.3, 0.72), (0.34, 2.3), (0.05, 3.07), (-0.2, 2.5), (-0.3, 2.3))
HANDLE_OUTLINE = ((-0.17, -0.65), (0.17, -0.65), (0.17, 0.66), (-0.17, 0.66))
GUARD_OUTLINE = ((-0.5, 0.64), (0.42, 0.64), (0.42, 0.74), (-0.5, 0.74))

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
# Prise : repère de la Handle dans le repère de la main. Prise marteau inclinée de GRIP_TILT autour de la
# normale paume : le manche traverse le poing en biais par rapport à l'avant-bras, tranchant à l'opposé du joueur.
GRIP_TILT = 35


# Cette méthode permet de calculer le CFrame de la Handle dans le repère de la main (prise).
def grip_matrix():
	a = math.radians(GRIP_TILT)
	z = Vector((-math.cos(a), -math.sin(a), 0))  # axe couteau
	x = Vector((math.sin(a), -math.cos(a), 0))  # tranchant
	return frame(Vector((0, 0, 0)), Matrix((x, z.cross(x), z)).transposed())


GRIP = grip_matrix()

# Pose idle : centre de poignée, axe du couteau, direction approchée du tranchant (repère caméra).
# Référence CS:GO : lame vers le haut-gauche de l'écran, vue presque de profil, tranchant vers le haut et l'avant.
IDLE_POS = Vector((1.6, -0.98, -2.7))
IDLE_AXIS = Vector((-0.85, 0.38, -0.36))
IDLE_EDGE = Vector((0.25, 0.55, -0.8))
SHOULDER = Vector((2.2, -2.68, -1.3))
POLE = Vector((2.5, -3.53, -1.55))
IDLE_KNIFE = frame(IDLE_POS, basis_zx(IDLE_AXIS, IDLE_EDGE))

# Main gauche au repos : en bas à gauche de l'écran, l'avant-bras remonte vers le centre.
LEFT_HAND_POS = Vector((-2.0, -1.35, -3.0))
LEFT_FOREARM = Vector((0.42, 0.62, -0.66))  # direction coude → main
LEFT_SHOULDER = Vector((-2.75, -2.55, -1.75))
LEFT_POLE = Vector((-3.8, -3.4, -1.8))


# Cette méthode permet de résoudre un bras (épaule, coude, poignet) pour un repère de main donné et de renvoyer
# les CFrames (repère caméra) du haut du bras, de l'avant-bras et de la main.
def solve_limb(hand, shoulder, pole):
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
	return upper, lower, frame(hand.translation, hr)


# Cette méthode permet de résoudre le bras droit pour une pose de couteau donnée et de renvoyer le CFrame
# (repère caméra) de chacune de ses pièces et de la Handle.
def solve_arm(knife, shoulder, pole):
	upper, lower, hand = solve_limb(knife @ GRIP.inverted(), shoulder, pole)
	return {"RightUpperArm": upper, "RightLowerArm": lower, "RightHand": hand, "Handle": knife}


# Cette méthode permet de résoudre le bras gauche au repos (main décalée de `offset`) et de renvoyer le CFrame
# (repère caméra) de chacune de ses pièces.
def solve_left(offset=Vector((0, 0, 0))):
	# +Y local de la main = vers le coude ; le bloc de main est symétrique autour de cet axe
	y = -LEFT_FOREARM.normalized()
	x = (Vector((1, 0, 0)) - y * y.x).normalized()
	hand = frame(LEFT_HAND_POS + offset, Matrix((x, y, x.cross(y))).transposed())
	upper, lower, hand = solve_limb(hand, LEFT_SHOULDER + offset, LEFT_POLE + offset)
	return {"LeftUpperArm": upper, "LeftLowerArm": lower, "LeftHand": hand}


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
	for name, p0, p1 in (
		("LeftShoulder", "FakeCamera", "LeftUpperArm"),
		("LeftElbow", "LeftUpperArm", "LeftLowerArm"),
		("LeftWrist", "LeftLowerArm", "LeftHand"),
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


# Cette méthode permet de créer le volume du couteau (lame, manche, garde extrudés dans le plan X/Z du
# repère de prise) pour lire le sens de la lame et du tranchant dans la prévisualisation.
def knife_object(mat):
	bm = bmesh.new()
	for outline, half in ((BLADE_OUTLINE, 0.04), (HANDLE_OUTLINE, 0.13), (GUARD_OUTLINE, 0.1)):
		front = [bm.verts.new((x, -half, z)) for x, z in outline]
		back = [bm.verts.new((x, half, z)) for x, z in outline]
		bm.faces.new(front)
		bm.faces.new(back)
		n = len(outline)
		for i in range(n):
			j = (i + 1) % n
			bm.faces.new((front[i], front[j], back[j], back[i]))
	return mesh_object("Handle", bm, mat)


# Cette méthode permet de construire l'armature (un os par pièce animée, sans hiérarchie : les poses
# sont écrites directement dans le repère armature), d'y attacher bras et couteau et de placer la
# caméra du jeu (FOV vertical 70°).
def build_scene(rest):
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	for coll in (bpy.data.armatures, bpy.data.cameras, bpy.data.lights):
		for block in list(coll):
			coll.remove(block)
	knife = {"Handle": knife_object(material("Knife_Proxy", (0.05, 0.05, 0.06), 0.8, 0.4))}
	skin = material("Arm_Skin", (0.64, 0.635, 0.647), 0.0, 0.7)
	arms = {n: box_object(n, RIG_JSON["parts"][n]["size"], skin) for n in ARM_PARTS + LEFT_PARTS}

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


# Cette méthode permet de construire une clé de pose à l'instant t : position du manche, axe manche → pointe,
# sens approché du tranchant et courbe d'arrivée. Sans axe ni tranchant, la clé reprend l'orientation idle.
def P(t, pos=None, axis=None, edge=None, e="io"):
	rot = basis_zx(Vector(axis), Vector(edge)) if axis else IDLE_KNIFE.to_3x3()
	return (t, Vector(pos) if pos else IDLE_POS.copy(), rot.to_quaternion(), e)


# Cette méthode permet d'évaluer une liste de clés de pose à l'instant t (position interpolée, rotation slerp).
def eval_keys(keys, t):
	if t <= keys[0][0]:
		return keys[0][1].copy(), keys[0][2].copy()
	for (t0, p0, q0, _), (t1, p1, q1, e1) in zip(keys, keys[1:], strict=False):
		if t <= t1:
			s = ease(e1, (t - t0) / (t1 - t0)) if t1 > t0 else 1.0
			return p0.lerp(p1, s), q0.slerp(q1, s)
	return keys[-1][1].copy(), keys[-1][2].copy()


# Cette méthode permet de faire suivre les cibles (position et rotation) par un ressort amorti, pour donner de
# l'inertie à la main sans clés supplémentaires ; l'erreur de rotation passe par le chemin le plus court.
def spring_pose(targets, freq, zeta, substeps=8):
	w = 2 * math.pi * freq
	dt = 1.0 / FPS / substeps
	pos, q = targets[0][0].copy(), targets[0][1].copy()
	vel, ang = Vector((0, 0, 0)), Vector((0, 0, 0))
	out = []
	for tp, tq in targets:
		for _ in range(substeps):
			vel += ((tp - pos) * (w * w) - vel * (2 * zeta * w)) * dt
			pos += vel * dt
			d = q.inverted() @ tq
			if d.w < 0:
				d = Quaternion((-d.w, -d.x, -d.y, -d.z))
			axis, angle = d.to_axis_angle()
			ang += (axis * angle * (w * w) - ang * (2 * zeta * w)) * dt
			step = ang * dt
			if step.length > 1e-9:
				q = q @ Quaternion(step.normalized(), step.length)
		out.append((pos.copy(), q.copy()))
	return out


# Cette méthode permet de ramener une série de poses exactement sur sa dernière pose cible, pour que
# l'animation finisse pile sur la pose de repos (pas de saut quand la piste s'arrête).
def settle_tail(series, seconds, end):
	n = len(series)
	k = max(2, int(seconds * FPS))
	for i in range(max(0, n - k), n):
		s = ease("io", (i - (n - k)) / (k - 1))
		series[i] = (series[i][0].lerp(end[0], s), series[i][1].slerp(end[1], s))
	return series


# Cette méthode permet de décrire l'Idle : respiration lente et petite dérive du poignet, en boucle parfaite
# (période entière sur toute la piste) autour de la pose de repos.
def spec_idle():
	length = 4.0

	def offset(t):
		a = 2 * math.pi * t / length
		pos = Vector((0.012 * math.sin(a * 2), 0.03 * (1 - math.cos(a)) / 2 + 0.006 * math.sin(a * 3), 0.014 * math.sin(a)))
		rot = Euler((math.radians(0.9 * math.sin(a)), math.radians(0.6 * math.sin(a * 2)), math.radians(0.8 * math.sin(a))), "XYZ")
		return pos, rot.to_quaternion()

	return dict(length=length, offset=offset, loop=True, step=6, markers=[])


# Cette méthode permet de décrire l'Equip : le couteau jaillit du bas de l'écran en tournoyant, la main monte
# le chercher et le rattrape au vol, encaisse la réception puis se cale sur la tenue. La main gauche remonte aussi.
def spec_equip():
	catch = 0.56
	return dict(
		length=1.0,
		freq=9.0,
		zeta=0.62,
		settle=0.14,
		keys=[
			P(0.0, (2.4, -3.2, -2.4), (-0.75, 0.5, -0.43), (0.25, 0.6, -0.75)),
			P(0.26, (2.05, -2.2, -2.6), (-0.75, 0.5, -0.43), (0.25, 0.6, -0.75), "o"),
			P(catch, (1.5, -0.7, -2.85), (-0.75, 0.5, -0.43), (0.25, 0.6, -0.75), "io"),
			P(catch + 0.11, (1.7, -1.25, -2.6), (-0.85, 0.25, -0.45), (0.2, 0.65, -0.75), "o"),
			P(0.86, None, None, None, "io"),
		],
		flight=dict(t0=0.0, t1=catch, start=(1.2, -3.9, -3.4), height=2.1, turns=1.25, axis=(0, 1, 0), spin="o"),
		left_in=dict(offset=(-0.3, -2.4, 0.4), until=0.5),
		markers=[("Equip Sound", catch - 0.3)],
		step=1,
	)


# Cette méthode permet de décrire le slash droite → gauche : main armée en haut à droite, lame dressée, coup de
# poignet en diagonale tranchant devant, accompagnement bas-gauche, retour sur la tenue.
def spec_shoot():
	hit = 0.2
	return dict(
		length=0.7,
		freq=13.0,
		zeta=0.74,
		settle=0.16,
		keys=[
			P(0.0),
			P(0.09, (2.1, -0.55, -2.9), (0.25, 0.85, -0.45), (-0.85, 0.1, -0.5), "o"),
			P(hit, (0.85, -0.7, -3.2), (-0.75, 0.4, -0.5), (-0.5, -0.6, 0.25), "i"),
			P(0.3, (0.3, -1.05, -3.05), (-0.85, -0.05, -0.5), (-0.35, -0.85, 0.2), "o"),
			P(0.62),
		],
		markers=[("Stab Sound", hit)],
		step=2,
	)


# Cette méthode permet de décrire le slash de revers gauche → droite : la main passe devant le torse, le poignet
# retourne le tranchant vers la droite et la lame balaie l'écran, légèrement remontante, avant le retour.
def spec_shoot2():
	hit = 0.2
	return dict(
		length=0.7,
		freq=13.0,
		zeta=0.74,
		settle=0.16,
		keys=[
			P(0.0),
			P(0.1, (0.15, -1.2, -2.85), (-0.9, 0.25, -0.35), (-0.25, 0.2, -0.95), "o"),
			P(hit, (1.35, -1.1, -3.2), (0.3, 0.75, -0.6), (0.9, -0.25, 0.1), "i"),
			P(0.31, (1.8, -1.2, -3.05), (0.65, 0.6, -0.45), (0.65, -0.2, 0.7), "o"),
			P(0.62),
		],
		markers=[("Stab Sound", hit)],
		step=2,
	)


# Cette méthode permet de décrire l'inspection, sans lancer : la main présente une face de la lame, le poignet
# roule pour montrer l'autre face, puis revient sur la tenue.
def spec_inspect():
	return dict(
		length=2.9,
		freq=8.0,
		zeta=0.75,
		settle=0.2,
		keys=[
			P(0.0),
			P(0.4, (0.95, -0.7, -2.6), (-0.9, 0.35, -0.25), (0.3, 0.85, 0.35), "io"),
			P(0.95, (0.92, -0.67, -2.55), (-0.88, 0.42, -0.2), (0.3, 0.8, 0.45), "l"),
			P(1.15, (0.92, -0.72, -2.58), (-0.88, 0.42, -0.2), (0.1, 0.25, -0.95), "io"),
			P(1.35, (0.95, -0.78, -2.6), (-0.88, 0.38, -0.25), (-0.3, -0.85, -0.35), "io"),
			P(1.9, (0.98, -0.75, -2.55), (-0.86, 0.45, -0.2), (-0.3, -0.8, -0.45), "l"),
			P(2.1, (1.2, -0.85, -2.62), (-0.86, 0.42, -0.28), (0.1, 0.25, -0.95), "io"),
			P(2.65),
		],
		markers=[("Equip Sound", 1.1)],
		step=2,
	)


SPECS = {"Idle": spec_idle, "Equip": spec_equip, "Shoot": spec_shoot, "Shoot2": spec_shoot2, "Inspect": spec_inspect}


# Cette méthode permet de calculer la pose du couteau pendant son vol : trajet parabolique depuis un point hors
# champ jusqu'à la main au rattrapage, avec une rotation sur lui-même.
def flight_pose(fl, t, poses):
	q0 = poses[int(round(fl["t0"] * FPS))][1]
	p1, q1 = poses[int(round(fl["t1"] * FPS))]
	p0 = Vector(fl["start"])
	s = (t - fl["t0"]) / (fl["t1"] - fl["t0"])
	pos = p0.lerp(p1, s) + Vector((0, fl["height"] * 4 * s * (1 - s), 0))
	angle = (1 - ease(fl["spin"], s)) * fl["turns"] * 2 * math.pi
	rot = q0.slerp(q1, s).to_matrix() @ Matrix.Rotation(angle, 3, Vector(fl["axis"]))
	return frame(pos, rot)


# Cette méthode permet de calculer le décalage de la main gauche à l'instant t : elle respire avec la droite, part
# légèrement à l'opposé de ses gestes et, si l'animation le demande, remonte depuis le bas de l'écran.
def left_offset(spec, t, right_delta):
	if spec.get("loop"):
		return right_delta * 0.8
	off = right_delta * -0.08
	entry = spec.get("left_in")
	if entry:
		off += Vector(entry["offset"]) * (1 - ease("o", t / entry["until"]))
	return off


# Cette méthode permet d'échantillonner une animation (clés + ressort + vol éventuel) et de renvoyer, pour chaque
# frame, les CFrames (repère caméra) des pièces du bras et de la Handle.
def sample(spec):
	n = int(round(spec["length"] * FPS)) + 1
	ts = [i / FPS for i in range(n)]
	idle_q = IDLE_KNIFE.to_3x3().to_quaternion()
	if "offset" in spec:
		poses = []
		for t in ts:
			dp, dq = spec["offset"](t)
			poses.append((IDLE_POS + dp, idle_q @ dq))
	else:
		targets = [eval_keys(spec["keys"], t) for t in ts]
		poses = settle_tail(spring_pose(targets, spec["freq"], spec["zeta"]), spec["settle"], (IDLE_POS, idle_q))
	frames = []
	fl = spec.get("flight")
	for i, t in enumerate(ts):
		pos, q = poses[i]
		# l'épaule (hors champ) accompagne la main, moins vite qu'elle
		delta = (pos - IDLE_POS) * 0.35
		arm = solve_arm(frame(pos, q.to_matrix()), SHOULDER + delta, POLE + delta)
		arm.update(solve_left(left_offset(spec, t, pos - IDLE_POS)))
		if fl and fl["t0"] <= t < fl["t1"]:
			arm["Handle"] = flight_pose(fl, t, poses)
		frames.append(arm)
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
		for n in ARM_PARTS + LEFT_PARTS + ("Handle",):
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
def export_json(name, ts, frames, markers, rest, motors, out_dir, step=2, loop=False):
	animated = [m for m in motors if m["p1"] in BONES]
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
		"loop": loop,
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
		"rest": {n: to_cf(rest[n]) for n in BONES},
	}
	with open(os.path.join(out_dir, "m9_rig.json"), "w", encoding="utf-8") as fh:
		json.dump(data, fh, indent=1)


# Cette méthode permet de tout reconstruire : scène, animations, exports (JSON, rig).
def build(export=True):
	idle = {**solve_arm(IDLE_KNIFE, SHOULDER, POLE), **solve_left()}
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
			export_json(name, ts, frames, spec["markers"], rest, motors, out_dir, spec["step"], spec.get("loop", False))
		results[name] = len(frames)
	rig.animation_data.action = None
	if export:
		export_rig(rest, motors, out_dir)
	return results


if __name__ == "__main__":
	print(build(export=globals().get("EXPORT", True)))
