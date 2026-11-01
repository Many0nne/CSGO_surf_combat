# build_viewmodel.py
# Construit le rig du viewmodel M9 Bayonet dans Blender (bras droit + volume du couteau), génère ses
# animations (Idle, Equip, Shoot, Shoot2, Stab, Inspect) et les exporte pour Roblox. Le modèle du couteau vit dans
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

# Rendu du jeu (CameraConfig.DEFAULT_FOV = 90, vertical) et cadre de référence : sert à retrouver une pose 3D depuis une
# position à l'écran, mesurée sur la vidéo CS:GO de référence (0,0 = haut gauche de l'écran, 1,1 = bas droite).
SCREEN_ASPECT = 16 / 9
GAME_FOV = 90
GUARD_Z = 0.72  # garde dans le repère de prise
TIP_Z = 3.07  # pointe dans le repère de prise
FACE = (0.25, 0.55, -0.8)  # tranchant de la tenue : lame vue de plat
HIDDEN_LEFT = Vector((-0.3, -2.6, 0.4))  # décalage qui sort la main gauche de l'écran


# Cette méthode permet de convertir une position écran normalisée en rayon caméra (FOV vertical du jeu).
def screen_ray(uv):
	k = math.tan(math.radians(GAME_FOV) / 2)
	return Vector(((2 * uv[0] - 1) * SCREEN_ASPECT * k, (1 - 2 * uv[1]) * k, -1))


# Cette méthode permet de retrouver le repère 3D du couteau depuis la garde et la pointe à l'écran : la profondeur de
# la garde est donnée, la longueur réelle de la lame fixe le raccourci de perspective. edge="cam" montre la tranche.
def knife_from_screen(guard, tip, depth, edge, far=True):
	g = screen_ray(guard) * depth
	rt = screen_ray(tip)
	length = TIP_Z - GUARD_Z
	a, b, c = rt.dot(rt), -2 * rt.dot(g), g.dot(g) - length * length
	disc = b * b - 4 * a * c
	s = (-b + (1 if far else -1) * math.sqrt(disc)) / (2 * a) if disc > 0 else -b / (2 * a)
	axis = (rt * s - g).normalized()
	hint = -rt if edge == "cam" else Vector(edge)
	return frame(g - axis * GUARD_Z, basis_zx(axis, hint))


# Pose idle mesurée sur la référence : lame vers le haut-gauche de l'écran, vue de plat, main en bas à droite.
IDLE_KNIFE = knife_from_screen((0.67, 0.80), (0.445, 0.59), 2.8, FACE)
IDLE_POS = IDLE_KNIFE.translation.copy()
SHOULDER = Vector((2.2, -2.68, -1.3)) + (IDLE_POS - Vector((1.6, -0.98, -2.7))) * 0.35
POLE = Vector((2.5, -3.53, -1.55)) + (IDLE_POS - Vector((1.6, -0.98, -2.7))) * 0.35

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


# Cette méthode permet de résoudre le bras droit pour une pose de couteau donnée et de renvoyer le CFrame (repère
# caméra) de chacune de ses pièces et de la Handle ; flip fait pivoter le couteau dans le poing autour de sa normale.
def solve_arm(knife, shoulder, pole, flip=0.0):
	spin = Matrix.Rotation(math.radians(flip), 4, "Y")
	upper, lower, hand = solve_limb(knife @ spin.inverted() @ GRIP.inverted(), shoulder, pole)
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
# caméra du jeu (FOV vertical du jeu, cf. GAME_FOV).
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
	cam_data.angle = math.radians(GAME_FOV)
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


# Cette méthode permet de construire la clé de repos à l'instant t (fin ou début d'une animation).
def P(t, e="io"):
	return (t, IDLE_POS.copy(), IDLE_KNIFE.to_3x3().to_quaternion(), e, 0.0)


# Cette méthode permet de construire une clé depuis les positions à l'écran de la garde et de la pointe (voir
# knife_from_screen), avec la courbe d'arrivée et le pivot éventuel du couteau dans le poing.
def S(t, guard, tip, depth, edge, flip=0.0, e="io", far=True):
	k = knife_from_screen(guard, tip, depth, edge, far)
	return (t, k.translation.copy(), k.to_3x3().to_quaternion(), e, flip)


# Cette méthode permet d'évaluer une liste de clés à l'instant t (position, rotation slerp et pivot interpolés).
def eval_keys(keys, t):
	if t <= keys[0][0]:
		return keys[0][1].copy(), keys[0][2].copy(), keys[0][4]
	for (t0, p0, q0, _, f0), (t1, p1, q1, e1, f1) in zip(keys, keys[1:], strict=False):
		if t <= t1:
			s = ease(e1, (t - t0) / (t1 - t0)) if t1 > t0 else 1.0
			return p0.lerp(p1, s), q0.slerp(q1, s), f0 + (f1 - f0) * s
	return keys[-1][1].copy(), keys[-1][2].copy(), keys[-1][4]


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


# Les clés ci-dessous sont mesurées sur la vidéo CS:GO de référence (ralentie d'environ 1,25 fois : les temps sont ceux
# du jeu), puis validées à côté de leur image de référence. Les ids en commentaire renvoient aux images de cette vidéo.


# Cette méthode permet de décrire l'Equip : la trajectoire de l'arme suit la référence image par image (voir
# EQUIP_TRACK) ; le couteau fait son demi-tour devant le poing, puis la lame oscille, roule et descend sur la tenue.
def spec_equip():
	return dict(
		length=1.0,
		track=True,
		settle=0.06,
		left=[(0.0, 1.0), (0.70, 1.0), (0.92, 0.0)],
		markers=[("Equip Sound", 0.3)],
		step=1,
	)


# Cette méthode permet de décrire le premier coup du clic gauche : le bras jaillit en haut à gauche en quelques images,
# balaie vers la droite et sort en bas à droite, puis remonte du bas de l'écran. Le coup suivant coupe ce retour.
def spec_shoot():
	return dict(
		length=0.7,
		keys=[
			P(0.0),
			S(0.03, (0.37, 0.71), (0.18, 0.55), 3.2, FACE, e="o"),  # A2
			S(0.10, (0.57, 0.63), (0.40, 0.52), 3.2, FACE, e="l"),  # A4
			S(0.18, (0.79, 0.77), (0.65, 0.61), 3.2, FACE, e="l"),  # A6
			S(0.27, (1.0, 0.95), (0.84, 0.75), 3.2, FACE, e="l"),  # A8
			S(0.33, (1.08, 1.12), (0.95, 0.92), 3.2, FACE, e="l"),
			S(0.42, (1.08, 1.12), (0.95, 0.92), 3.2, FACE, e="l"),
			S(0.56, (0.72, 0.93), (0.52, 0.72), 3.0, FACE, e="o"),
			P(0.7),
		],
		left=[(0.0, 0.0), (0.05, 1.0), (0.55, 1.0), (0.7, 0.0)],
		markers=[("Stab Sound", 0.14)],
		step=1,
	)


# Cette méthode permet de décrire le second coup du clic gauche : diagonale descendante de droite à gauche, sortie en
# bas à gauche, puis remontée du bas de l'écran. Le coup suivant coupe ce retour.
def spec_shoot2():
	edge = (-1, 0.2, 0.2)
	return dict(
		length=0.7,
		keys=[
			P(0.0),
			S(0.04, (0.645, 0.63), (0.70, 0.47), 3.0, edge, e="o"),  # B3
			S(0.12, (0.435, 0.72), (0.48, 0.56), 3.0, edge, e="l"),  # B5
			S(0.20, (0.25, 0.85), (0.31, 0.66), 3.0, edge, e="l"),  # B7
			S(0.24, (0.08, 0.95), (0.16, 0.75), 3.0, edge, e="l"),  # B8
			S(0.31, (-0.12, 1.15), (-0.02, 0.92), 3.0, edge, e="l"),
			S(0.42, (-0.12, 1.15), (-0.02, 0.92), 3.0, edge, e="l"),
			S(0.56, (0.66, 0.96), (0.46, 0.74), 3.0, FACE, e="o"),
			P(0.7),
		],
		left=[(0.0, 0.0), (0.05, 1.0), (0.55, 1.0), (0.7, 0.0)],
		markers=[("Stab Sound", 0.12)],
		step=1,
	)


# Cette méthode permet de décrire le coup d'estoc du clic droit : la main recule, le bras se tend au centre de l'écran,
# tient le coup, tombe hors du cadre puis remonte du bas de l'écran.
def spec_stab():
	edge = (-0.7, 0.7, 0.2)
	return dict(
		length=1.0,
		keys=[
			P(0.0),
			S(0.04, (0.92, 1.05), (1.0, 0.92), 2.6, (0, 1, 0), e="o"),  # C2
			S(0.10, (0.50, 0.62), (0.63, 0.64), 3.0, (0, 1, 0), e="o"),  # C3
			S(0.23, (0.40, 0.60), (0.46, 0.49), 3.2, edge, e="o"),  # C5
			S(0.44, (0.39, 0.62), (0.45, 0.50), 3.2, edge, e="l"),
			S(0.57, (0.27, 0.85), (0.34, 0.61), 3.0, edge, e="i"),  # C10
			S(0.64, (0.20, 1.25), (0.30, 1.0), 3.0, edge, e="l"),
			S(0.78, (0.20, 1.25), (0.30, 1.0), 3.0, edge, e="l"),
			S(0.90, (0.68, 0.93), (0.48, 0.71), 3.0, FACE, e="o"),
			P(1.0),
		],
		left=[(0.0, 0.0), (0.03, 1.0), (0.82, 1.0), (1.0, 0.0)],
		markers=[("Stab Sound", 0.16)],
		step=1,
	)


# Cette méthode permet de décrire l'inspection : la lame se redresse à droite vue par la tranche puis de plat, le
# poignet roule jusqu'à la tranche et revient sur la même face, avec un temps de regard entre chaque geste.
def spec_inspect():
	return dict(
		length=9.2,
		freq=8.0,
		zeta=0.85,
		settle=0.2,
		keys=[
			P(0.0),
			S(0.24, (0.66, 0.80), (0.49, 0.52), 2.9, FACE),  # I2
			S(0.48, (0.67, 0.75), (0.60, 0.35), 3.0, "cam"),  # I3
			S(0.72, (0.71, 0.72), (0.70, 0.25), 3.0, "cam"),  # I4
			S(1.28, (0.72, 0.63), (0.75, 0.28), 3.0, (-1, 0, 0.2)),  # I6
			S(3.2, (0.72, 0.60), (0.75, 0.22), 3.0, (-1, 0, 0.2), e="l"),
			S(3.72, (0.68, 0.59), (0.64, 0.13), 3.0, "cam"),  # I9
			S(6.08, (0.68, 0.60), (0.65, 0.14), 3.0, "cam", e="l"),
			S(6.64, (0.75, 0.60), (0.78, 0.17), 3.0, (-1, 0, 0.2)),  # I12
			S(8.08, (0.73, 0.61), (0.75, 0.24), 3.0, (-1, 0, 0.2), e="l"),
			S(8.56, (0.71, 0.72), (0.70, 0.25), 3.0, "cam"),
			S(8.68, (0.68, 0.76), (0.55, 0.38), 3.0, "cam"),
			S(8.8, (0.66, 0.80), (0.41, 0.55), 2.9, FACE),  # I16
			P(9.2),
		],
		left=[(0.0, 0.0), (0.35, 1.0), (8.55, 1.0), (8.9, 0.0)],
		markers=[("Equip Sound", 1.1)],
		step=3,
	)


SPECS = {
	"Idle": spec_idle,
	"Equip": spec_equip,
	"Shoot": spec_shoot,
	"Shoot2": spec_shoot2,
	"Stab": spec_stab,
	"Inspect": spec_inspect,
}




# Cette méthode permet de calculer le décalage de la main gauche à l'instant t : elle respire avec la droite pendant
# l'Idle ; sinon elle suit le planning « left » de l'animation (0 = à sa place, 1 = sortie de l'écran).
def left_offset(spec, t, right_delta):
	if spec.get("loop"):
		return right_delta * 0.8
	schedule = spec.get("left")
	if not schedule:
		return Vector((0, 0, 0))
	for (t0, h0), (t1, h1) in zip(schedule, schedule[1:], strict=False):
		if t <= t1:
			return HIDDEN_LEFT * (h0 + (h1 - h0) * ease("io", (t - t0) / (t1 - t0)))
	return HIDDEN_LEFT * schedule[-1][1]


# Trajectoire de l'Equip mesurée sur la vidéo de référence, toutes les 0,05 s de vidéo (ralentie 1,25 fois) :
# temps vidéo, garde et pointe à l'écran, roulis de la lame (0 = de plat, tranchant à gauche d'une lame dressée ;
# 90 = dos vers la caméra), profondeur de la garde (None = déduite de la longueur à l'écran, lame vue de plat),
# centre de la main à l'écran tant que le couteau tourne dans le poing (None = la main tient le couteau).
EQUIP_VIDEO_START = 0.42
EQUIP_VIDEO_SCALE = 1.25
EQUIP_TRACK = (
	(0.40, (0.646, 1.20), (0.63, 1.55), 0, 2.5, (0.62, 1.15)),
	(0.45, (0.643, 1.08), (0.625, 1.46), 0, 2.5, (0.62, 1.08)),
	(0.50, (0.639, 1.02), (0.62, 1.40), 0, 2.5, (0.62, 0.98)),
	(0.55, (0.633, 0.95), (0.61, 1.32), 0, 2.5, (0.63, 0.90)),
	(0.60, (0.630, 0.89), (0.60, 1.25), 0, 2.5, (0.63, 0.84)),
	(0.65, (0.620, 0.81), (0.58, 1.12), 0, 2.5, (0.62, 0.76)),
	(0.70, (0.625, 0.76), (0.575, 1.10), 0, 2.5, (0.63, 0.72)),
	(0.75, (0.623, 0.71), (0.54, 1.05), 0, 2.5, (0.66, 0.72)),
	(0.80, (0.647, 0.68), (0.529, 0.899), 0, 2.5, (0.66, 0.70)),
	(0.85, (0.672, 0.652), (0.529, 0.701), 0, 2.5, (0.665, 0.69)),
	(0.90, (0.677, 0.684), (0.569, 0.464), 0, 2.5, (0.67, 0.70)),
	(0.95, (0.659, 0.674), (0.618, 0.313), 0, 2.5, (0.665, 0.71)),
	(1.00, (0.654, 0.645), (0.659, 0.209), 0, None, None),
	(1.05, (0.656, 0.623), (0.694, 0.145), 0, None, None),
	(1.10, (0.670, 0.598), (0.76, 0.107), 0, None, None),
	(1.15, (0.696, 0.580), (0.829, 0.107), 0, None, None),
	(1.20, (0.721, 0.558), (0.87, 0.122), 5, None, None),
	(1.25, (0.727, 0.590), (0.854, 0.136), 15, None, None),
	(1.30, (0.703, 0.603), (0.764, 0.145), 40, None, None),
	(1.35, (0.691, 0.640), (0.656, 0.203), 80, None, None),
	(1.40, (0.691, 0.754), (0.556, 0.296), 100, None, None),
	(1.45, (0.659, 0.759), (0.485, 0.412), 115, None, None),
	(1.50, (0.659, 0.710), (0.456, 0.516), 125, None, None),
	(1.55, (0.667, 0.754), (0.439, 0.58), 130, None, None),
	(1.60, (0.667, 0.806), (0.439, 0.632), 130, None, None),
	(1.67, (0.67, 0.80), (0.445, 0.59), 130, 2.8, None),
)


# Cette méthode permet de lisser une colonne de mesures (filtre 1-2-1, extrémités fixes) lorsque le relevé à l'œil
# contient un léger bruit qui ferait trembler la lame ; passes règle la force du lissage.
def smooth_column(values, passes=2):
	out = list(values)
	for _ in range(passes):
		out = [out[0]] + [(out[i - 1] + 2 * out[i] + out[i + 1]) / 4 for i in range(1, len(out) - 1)] + [out[-1]]
	return out


# Cette méthode permet d'interpoler une colonne de mesures à l'indice flottant u (spline de Catmull-Rom), pour que
# la vitesse reste continue d'une mesure à l'autre, sans ralentir sur chaque point comme une clé avec courbe.
def spline(values, u):
	i = min(max(int(u), 0), len(values) - 2)
	s = u - i
	a, b, c, d = values[max(i - 1, 0)], values[i], values[i + 1], values[min(i + 2, len(values) - 1)]
	return 0.5 * (2 * b + (c - a) * s + (2 * a - 5 * b + 4 * c - d) * s * s + (3 * b - a - 3 * c + d) * s * s * s)


# Cette méthode permet de construire le repère du couteau depuis la garde et la pointe à l'écran et son roulis,
# lorsque le tranchant se décrit par rapport au regard plutôt que par une direction fixe (qui tournerait avec la lame).
def knife_from_roll(guard, tip, depth, roll):
	k = knife_from_screen(guard, tip, depth, (0, 0, 1))
	axis = k.to_3x3().col[2]
	to_cam = -screen_ray(tip).normalized()
	left = to_cam.cross(axis).normalized()
	a = math.radians(roll)
	return frame(k.translation, basis_zx(axis, left * math.cos(a) - to_cam * math.sin(a)))


# Cette méthode permet de résoudre le bras gauche et le bras droit pour une frame de la trajectoire de l'Equip :
# tant que le couteau tourne, la main reste orientée comme à la fin du demi-tour et le couteau passe devant elle.
def equip_track_frame(track, t, hand_rot):
	vt = EQUIP_VIDEO_START + t * EQUIP_VIDEO_SCALE
	times = track["times"]
	if vt >= times[-1]:
		u = len(times) - 1.0
	else:
		j = next(i for i in range(len(times) - 1) if vt < times[i + 1])
		u = j + (vt - times[j]) / (times[j + 1] - times[j])
	guard = (spline(track["gu"], u), spline(track["gv"], u))
	tip = (spline(track["tu"], u), spline(track["tv"], u))
	depth = spline(track["depth"], u)
	knife = knife_from_roll(guard, tip, depth, spline(track["roll"], u))
	grip_hand = knife @ GRIP.inverted()
	weight = min(max((vt - 0.95) / 0.05, 0.0), 1.0)  # la main reprend le couteau à la fin du demi-tour
	free = frame(screen_ray((spline(track["hu"], u), spline(track["hv"], u))) * (depth + 0.55), hand_rot)
	hand = free.lerp(grip_hand, ease("io", weight))
	return knife, hand


# Cette méthode permet d'échantillonner l'Equip depuis sa trajectoire mesurée et de renvoyer les CFrames de chaque frame.
def sample_track(spec):
	rows = EQUIP_TRACK
	depths = []
	for _, g, tp, _, d, _ in rows:
		if d is not None:
			depths.append(d)
			continue
		length = math.hypot((tp[0] - g[0]) * SCREEN_ASPECT, tp[1] - g[1])
		depths.append(min(max((TIP_Z - GUARD_Z) / (2 * length), 2.1), 3.0))
	end = len(rows) - 1
	hands = [r[5] or rows[11][5] for r in rows]
	track = {
		"times": [r[0] for r in rows],
		"gu": smooth_column([r[1][0] for r in rows]),
		"gv": smooth_column([r[1][1] for r in rows]),
		"tu": smooth_column([r[2][0] for r in rows]),
		"tv": smooth_column([r[2][1] for r in rows]),
		"roll": smooth_column([r[3] for r in rows]),
		"depth": smooth_column(depths),
		"hu": smooth_column([h[0] for h in hands]),
		"hv": smooth_column([h[1] for h in hands]),
	}
	u_end = 12  # fin du demi-tour : ligne 1,00 s de la trajectoire
	end_knife = knife_from_roll(
		(track["gu"][u_end], track["gv"][u_end]),
		(track["tu"][u_end], track["tv"][u_end]),
		track["depth"][u_end],
		track["roll"][u_end],
	)
	hand_rot = (end_knife @ GRIP.inverted()).to_3x3()
	n = int(round(spec["length"] * FPS)) + 1
	ts = [i / FPS for i in range(n)]
	idle_hand = IDLE_KNIFE @ GRIP.inverted()
	frames = []
	for t in ts:
		knife, hand = equip_track_frame(track, t, hand_rot)
		blend = ease("io", (t - spec["length"] + spec["settle"]) / spec["settle"])  # finit pile sur la tenue
		if blend > 0:
			knife = knife.lerp(IDLE_KNIFE, blend)
			hand = hand.lerp(idle_hand, blend)
		pos = knife.translation
		delta = (pos - IDLE_POS) * 0.35
		upper, lower, solved = solve_limb(hand, SHOULDER + delta, POLE + delta)
		arm = {"RightUpperArm": upper, "RightLowerArm": lower, "RightHand": solved, "Handle": knife}
		arm.update(solve_left(left_offset(spec, t, pos - IDLE_POS)))
		frames.append(arm)
	return ts, frames


# Cette méthode permet d'échantillonner une animation (clés, ressort optionnel, pivot dans le poing) et de renvoyer,
# pour chaque frame, les CFrames (repère caméra) des pièces du bras et de la Handle.
def sample(spec):
	if spec.get("track"):
		return sample_track(spec)
	n = int(round(spec["length"] * FPS)) + 1
	ts = [i / FPS for i in range(n)]
	idle_q = IDLE_KNIFE.to_3x3().to_quaternion()
	flips = [0.0] * n
	if "offset" in spec:
		poses = []
		for t in ts:
			dp, dq = spec["offset"](t)
			poses.append((IDLE_POS + dp, idle_q @ dq))
	else:
		evaluated = [eval_keys(spec["keys"], t) for t in ts]
		flips = [e[2] for e in evaluated]
		poses = [(e[0], e[1]) for e in evaluated]
		if spec.get("freq"):
			poses = settle_tail(spring_pose(poses, spec["freq"], spec["zeta"]), spec["settle"], (IDLE_POS, idle_q))
	frames = []
	for i, t in enumerate(ts):
		pos, q = poses[i]
		# l'épaule (hors champ) accompagne la main, moins vite qu'elle
		delta = (pos - IDLE_POS) * 0.35
		arm = solve_arm(frame(pos, q.to_matrix()), SHOULDER + delta, POLE + delta, flips[i])
		arm.update(solve_left(left_offset(spec, t, pos - IDLE_POS)))
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
