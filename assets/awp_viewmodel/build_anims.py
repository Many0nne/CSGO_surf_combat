# build_anims.py
# Génère les animations viewmodel de l'AWP (Idle, Equip, Shoot, Reload) dans AWP_Viewmodel_Anims.blend.
# À lancer depuis Blender (Text Editor > Run, ou exec(open(path).read())) avec le rig "Rig" déjà construit.
#
# Principe : la pose de l'arme vient d'une trajectoire mesurée sur la vidéo de référence (position à l'écran de l'œilleton
# et du canon, voir solve_gun) ; culasse, chargeur et mains sont décrits par canaux d'intention, et les mains suivent
# l'arme par IK. Le repère est celui de la caméra du viewmodel : X droite, Y avant, Z haut (unités = studs).
# FakeCamera étant recalé sur la caméra en jeu (PivotTo), tout le mouvement passe par l'arme, jamais par FakeCamera.

import math

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

FPS = 60
RIG = bpy.data.objects["Rig"]
ARM = RIG.data
REST = {b.name: b.matrix_local.copy() for b in ARM.bones}

RECOIL_PIVOT = Vector((1.09, -0.6, -1.0))  # creux de l'épaule : pivot des rotations de l'arme

# --- Roulis de l'arme (degrés autour de son axe), invisible sur les deux points mesurés : choisi à l'œil -----------
RELOAD_ROLL = 6.0  # arme levée pendant le changement de chargeur
BOLT_ROLL = 12.0  # arme penchée pour présenter la culasse à la main droite
EQUIP_ROLL_LOW = 0.0  # arme encore basse à la sortie

# --- Pose de base (tenue au repos) ------------------------------------------------------------------
SHOULDER = {"R": Vector((1.75, 0.25, -1.95)), "L": Vector((0.05, 2.1, -2.55))}
POLE = {"R": Vector((2.9, 0.4, -3.0)), "L": Vector((0.4, 2.2, -4.2))}
HAND_CENTER_TO_WRIST = 0.1496

# Points de prise : (repère parent, position locale du centre de la main dans ce repère au repos)
HANDLE_REST = REST["Handle"].translation
BOLT_REST = REST["Bolt"].translation
MAG_REST = REST["Magazine"].translation


# Cette méthode permet d'exprimer un point du repère caméra au repos dans le repère local d'un os.
def local_to(bone, world_point):
	return REST[bone].inverted() @ Vector(world_point)


GRIP_R = ("Handle", local_to("Handle", (1.17, 1.0, -1.18)))
FOREND_L = ("Handle", local_to("Handle", (1.0, 3.35, -1.5)))
KNOB_R = ("Bolt", local_to("Bolt", (1.72, 1.86, -1.22)))
MAG_L = ("Magazine", local_to("Magazine", (1.1, 2.6, -1.78)))


# ------------------------------------------------------------------------------------------------
# Outils de courbes
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
	if kind == "io":
		return s * s * (3 - 2 * s)
	if kind == "io5":
		return s * s * s * (s * (6 * s - 15) + 10)
	if kind == "step":
		return 1.0 if s >= 1 else 0.0
	raise ValueError(kind)


# Cette méthode permet d'évaluer une piste de clés [(t, valeur, easing d'arrivée)] à l'instant t
# lorsque les valeurs sont des vecteurs (position ou angles en degrés).
def track(keys, t):
	if t <= keys[0][0]:
		return Vector(keys[0][1])
	for (t0, v0, _), (t1, v1, e1) in zip(keys, keys[1:], strict=False):
		if t <= t1:
			s = ease(e1, (t - t0) / (t1 - t0)) if t1 > t0 else 1.0
			return Vector(v0).lerp(Vector(v1), s)
	return Vector(keys[-1][1])


# ------------------------------------------------------------------------------------------------
# Cinématique directe (hors bras) : même calcul que Blender, fait à la main pour pouvoir placer
# les cibles IK des mains sur l'arme avant d'écrire les clés.
# ------------------------------------------------------------------------------------------------


# Cette méthode permet de calculer la matrice de l'os parent⁻¹ × enfant au repos.
def rest_rel(name):
	b = ARM.bones[name]
	return REST[b.parent.name].inverted() @ REST[name] if b.parent else REST[name]


# Cette méthode permet de construire une matrice de rotation (angles en degrés : tangage X,
# roulis Y, lacet Z) autour d'un pivot, suivie d'une translation, dans le repère caméra.
def rot_about(pivot, loc_offset, rot_deg):
	r = Euler([math.radians(a) for a in rot_deg], "YXZ").to_matrix().to_4x4()
	return Matrix.Translation(pivot + loc_offset) @ r @ Matrix.Translation(-pivot)


# Cette méthode permet d'évaluer les poses (repère armature) de la caméra, de l'arme, de la culasse
# et du chargeur pour un jeu de canaux donné ; renvoie aussi les « basis » à keyer.
def eval_fk(ch):
	basis = {}
	cam = rot_about(Vector((0, 0, 0)), ch["cam_loc"], ch["cam_rot"])
	basis["FakeCamera"] = REST["FakeCamera"].inverted() @ cam @ REST["FakeCamera"]
	gun_g = rot_about(RECOIL_PIVOT, ch["gun_loc"], ch["gun_rot"])
	basis["Joint"] = REST["Joint"].inverted() @ gun_g @ REST["Joint"]
	pose = {}
	pose["FakeCamera"] = REST["FakeCamera"] @ basis["FakeCamera"]
	pose["Joint"] = pose["FakeCamera"] @ rest_rel("Joint") @ basis["Joint"]
	pose["Handle"] = pose["Joint"] @ rest_rel("Handle")
	lift = Matrix.Rotation(math.radians(-ch["bolt_lift"]), 4, "Y")
	basis["Bolt"] = Matrix.Translation((0, -ch["bolt_travel"], 0)) @ lift
	pose["Bolt"] = pose["Handle"] @ rest_rel("Bolt") @ basis["Bolt"]
	trig = Matrix.Rotation(math.radians(-ch.get("trigger", 0.0)), 4, "X")
	basis["Trigger"] = trig
	return basis, pose


# Cette méthode permet de convertir un point d'attache (repère, position locale) en position caméra
# lorsque les poses de l'arme sont connues ; le chargeur suit son propre repère posé.
def attach_world(att, pose):
	frame, local = att
	if frame == "FC":
		return pose["FakeCamera"] @ Vector(local)
	return pose[frame] @ Vector(local)


# Cette méthode permet de calculer le centre de la main à l'instant t à partir d'une liste de
# transitions [(t0, t1, attache_départ, attache_arrivée, arc, easing)] ; la main suit l'arme.
def hand_center(segments, t, pose):
	cur = segments[0][2]
	for t0, t1, a, b, arc, e in segments:
		if t < t0:
			break
		if t >= t1:
			cur = b
			continue
		s = ease(e, (t - t0) / (t1 - t0))
		pa, pb = attach_world(a, pose), attach_world(b, pose)
		lift = pose["FakeCamera"].to_3x3() @ Vector(arc) * math.sin(math.pi * s)
		return pa.lerp(pb, s) + lift
	return attach_world(cur, pose)


# ------------------------------------------------------------------------------------------------
# Écriture des clés
# ------------------------------------------------------------------------------------------------


# Cette méthode permet de créer (ou vider) l'action d'une animation et de l'assigner au rig.
def new_action(name):
	act = bpy.data.actions.get(name)
	if act:
		bpy.data.actions.remove(act)
	act = bpy.data.actions.new(name)
	act.use_fake_user = True
	RIG.animation_data_create()
	RIG.animation_data.action = act
	return act


# Cette méthode permet de keyer une matrice « basis » sur un os à la frame donnée.
def key_basis(pb, m, frame):
	loc, rot, _ = m.decompose()
	pb.location = loc
	pb.rotation_mode = "QUATERNION"
	pb.rotation_quaternion = rot
	pb.keyframe_insert("location", frame=frame, group=pb.name)
	pb.keyframe_insert("rotation_quaternion", frame=frame, group=pb.name)


# Cette méthode permet de calculer la basis d'un os parenté à FakeCamera pour qu'il ait la
# position voulue (repère armature) en conservant son orientation de repos.
def basis_for_position(bone, world_pos, pose):
	parent_pose = pose["FakeCamera"] @ rest_rel(bone)
	target = parent_pose.copy()
	target.translation = world_pos
	return parent_pose.inverted() @ target


# Cette méthode permet d'échantillonner une animation décrite par `spec`, de placer l'arme, les mains et
# le chargeur, et d'écrire toutes les clés dans une action dédiée.
def bake(name, spec):
	n = int(round(spec["length"] * FPS)) + 1
	ts = [i / FPS for i in range(n)]
	gun_loc = [spec["gun_loc"](t) for t in ts]
	gun_rot = [spec["gun_rot"](t) for t in ts]
	act = new_action("AWP_" + name)
	pbs = RIG.pose.bones
	for i, t in enumerate(ts):
		f = i
		ch = {
			"gun_loc": gun_loc[i],
			"gun_rot": gun_rot[i],
			"cam_loc": Vector(Z),
			"cam_rot": Vector(Z),
			"bolt_lift": spec["bolt_lift"](t)[0],
			"bolt_travel": spec["bolt_travel"](t)[0],
			"trigger": spec.get("trigger", lambda _t: Vector((0, 0, 0)))(t)[0],
		}
		basis, pose = eval_fk(ch)
		# chargeur : attaché à l'arme (+ décalage) ou à la main gauche
		mag_off = spec.get("mag_off", const())(t)
		mag_in_gun = pose["Handle"] @ Matrix.Translation(mag_off) @ rest_rel("Magazine")
		pose["Magazine"] = mag_in_gun
		for s in ("R", "L"):
			c = hand_center(spec["hand_" + s], t, pose)
			sh = pose["FakeCamera"] @ (SHOULDER[s] + spec.get("shoulder_" + s, lambda _t: Vector((0, 0, 0)))(t))
			d = (c - sh).normalized()
			wrist = c - d * HAND_CENTER_TO_WRIST
			key_basis(pbs["IK." + s], basis_for_position("IK." + s, wrist, pose), f)
			key_basis(pbs["UpperArm." + s], basis_for_position("UpperArm." + s, sh, pose), f)
			key_basis(pbs["Pole." + s], basis_for_position("Pole." + s, pose["FakeCamera"] @ POLE[s], pose), f)
			pose["Hand_" + s] = c
		w = spec.get("mag_in_hand", lambda _t: Vector((0, 0, 0)))(t)[0]
		if w > 0:
			# même orientation que dans l'arme, mais position imposée par la main gauche
			mag_hand = mag_in_gun.copy()
			mag_hand.translation = pose["Hand_L"] - mag_in_gun.to_3x3() @ MAG_L[1]
			mag_final = blend_matrix(mag_in_gun, mag_hand, w)
		else:
			mag_final = mag_in_gun
		basis["Magazine"] = (pose["Handle"] @ rest_rel("Magazine")).inverted() @ mag_final
		for b in ("FakeCamera", "Joint", "Bolt", "Trigger", "Magazine"):
			key_basis(pbs[b], basis[b], f)
	# pré-pliage des avant-bras : un bras tendu au repos bloque le solveur IK (singularité)
	for s in ("R", "L"):
		pb = pbs["LowerArm." + s]
		pb.rotation_mode = "QUATERNION"
		pb.rotation_quaternion = Quaternion((1, 0, 0), math.radians(40))
		pb.keyframe_insert("rotation_quaternion", frame=0, group=pb.name)
	for fc in act_fcurves(act):
		for kp in fc.keyframe_points:
			kp.interpolation = "LINEAR"
	markers = act.pose_markers
	for m in list(markers):
		markers.remove(m)
	for mname, mt in spec.get("markers", []):
		pm = markers.new(mname)
		pm.frame = int(round(mt * FPS))
	act.frame_range = (0, n - 1)
	act.use_frame_range = True
	return act


# Cette méthode permet d'interpoler deux matrices (position linéaire, rotation sphérique).
def blend_matrix(a, b, w):
	la, ra, _ = a.decompose()
	lb, rb, _ = b.decompose()
	return Matrix.Translation(la.lerp(lb, w)) @ ra.slerp(rb, w).to_matrix().to_4x4()


# Cette méthode permet de lister les F-curves d'une action, qu'elle soit « slotted » (Blender 4.4+)
# ou classique.
def act_fcurves(act):
	if hasattr(act, "layers") and len(act.layers):
		out = []
		for layer in act.layers:
			for strip in layer.strips:
				for cb in strip.channelbags:
					out.extend(cb.fcurves)
		return out
	return list(act.fcurves)


# ------------------------------------------------------------------------------------------------
# Animations
# ------------------------------------------------------------------------------------------------
Z = (0, 0, 0)


# Cette méthode permet de fabriquer une piste constante (canal non utilisé par une animation).
def const(v=Z):
	return lambda _t: Vector(v)


# Cette méthode permet de construire une fonction de piste à partir d'une liste de clés.
def K(keys):
	return lambda t: track(keys, t)


# ------------------------------------------------------------------------------------------------
# Trajectoires mesurées sur la vidéo de référence (AWP CS2, voir docs/animations.md)
# Chaque échantillon : (temps vidéo, E_x, E_y, M_x, M_y), positions à l'écran de l'œilleton (E) et du bout du canon (M)
# relevées sur les planches de tools/anim/grid.py recadrées sur x ∈ [0,4 ; 1], en pixels d'une case de 400 × 375.
# ------------------------------------------------------------------------------------------------
REF_IDLE = ((212, 238), (105, 222))  # œilleton et canon de la référence au repos
HEIGHT_OVER_WIDTH = 9 / 16  # le joueur voit du 16:9, au FOV vertical de 90° du jeu (tan 45° = 1)
EYE_REST = Vector((1.08, 1.59, -0.15))  # œilleton de notre arme, repère caméra au repos
MUZZLE_REST = Vector((1.074, 8.35, -0.587))  # bout du canon de notre arme, repère caméra au repos
GUN_AXIS_REST = (MUZZLE_REST - EYE_REST).normalized()
GUN_LENGTH = (MUZZLE_REST - EYE_REST).length

EQUIP_TRACK = [
	(1.80, 160, 425, 118, 412),
	(1.87, 170, 360, 118, 362),
	(1.94, 185, 295, 115, 312),
	(2.00, 215, 250, 115, 262),
	(2.07, 230, 222, 110, 240),
	(2.14, 245, 217, 112, 222),
	(2.20, 255, 230, 108, 200),
	(2.27, 265, 250, 110, 185),
	(2.34, 265, 265, 110, 185),
	(2.40, 255, 265, 110, 192),
	(2.47, 245, 257, 112, 197),
	(2.54, 235, 250, 110, 210),
	(2.60, 225, 235, 110, 220),
	(2.67, 220, 235, 110, 232),
	(2.74, 215, 232, 105, 238),
	(2.80, 210, 230, 105, 238),
	(2.87, 210, 235, 105, 230),
	(2.94, 210, 237, 105, 225),
	(3.00, 212, 238, 105, 222),
]
EQUIP_DEPTH = [(1.80, 0.9), (1.94, 0.9), (2.14, 1.0), (2.27, 1.1), (2.40, 1.05), (2.54, 1.0), (3.00, 1.0)]

SHOOT_TRACK = [
	(19.65, 212, 238, 105, 222),
	(19.67, 230, 240, 115, 225),
	(19.70, 232, 240, 110, 220),
	(19.73, 270, 243, 105, 210),
	(19.77, 275, 223, 105, 185),
	(19.80, 280, 223, 105, 183),
	(19.83, 265, 217, 105, 173),
	(19.87, 245, 212, 103, 173),
	(19.90, 235, 210, 103, 175),
	(19.93, 230, 208, 103, 180),
	(19.97, 230, 208, 103, 186),
	(20.00, 230, 210, 103, 192),
	(20.03, 225, 213, 103, 200),
	(20.07, 225, 215, 105, 205),
	(20.10, 220, 220, 105, 210),
	(20.13, 220, 225, 105, 215),
	(20.17, 215, 230, 105, 220),
	(20.20, 215, 235, 105, 228),
	(20.27, 210, 245, 105, 235),
	(20.33, 210, 250, 105, 228),
	(20.40, 215, 250, 105, 225),
	(20.47, 215, 240, 105, 200),
	(20.53, 215, 235, 105, 195),
	(20.60, 215, 235, 105, 210),
	(20.67, 205, 245, 110, 228),
	(20.73, 205, 245, 110, 233),
	(20.80, 205, 245, 105, 230),
	(20.87, 210, 245, 105, 230),
	(20.93, 210, 245, 105, 225),
	(21.00, 210, 245, 105, 225),
	(21.10, 212, 238, 105, 222),
]
SHOOT_DEPTH = [
	(19.65, 1.0), (19.70, 1.03), (19.73, 1.2), (19.77, 1.35), (19.80, 1.4), (19.83, 1.3), (19.87, 1.18), (19.90, 1.08),
	(19.97, 1.03), (20.20, 1.0), (20.40, 1.05), (20.60, 1.03), (20.80, 0.97), (21.10, 1.0),
]

RELOAD_TRACK = [
	(22.95, 212, 238, 105, 222),
	(23.05, 215, 235, 97, 205),
	(23.15, 220, 232, 90, 195),
	(23.25, 220, 235, 85, 195),
	(23.35, 210, 235, 85, 213),
	(23.45, 205, 237, 92, 220),
	(23.55, 225, 242, 97, 215),
	(23.65, 245, 237, 97, 180),
	(23.75, 275, 250, 85, 157),
	(23.85, 305, 260, 70, 135),
	(23.95, 320, 262, 58, 128),
	(24.05, 320, 262, 45, 128),
	(24.15, 315, 255, 35, 132),
	(24.25, 310, 255, 30, 135),
	(24.35, 305, 255, 30, 132),
	(24.45, 320, 240, 35, 120),
	(24.55, 340, 235, 45, 103),
	(24.60, 340, 232, 45, 100),
	(24.70, 337, 240, 42, 107),
	(24.80, 315, 240, 35, 122),
	(24.90, 298, 240, 33, 130),
	(25.00, 355, 240, 50, 70),
	(25.10, 350, 232, 50, 82),
	(25.20, 307, 230, 57, 132),
	(25.30, 250, 249, 70, 192),
	(25.40, 228, 252, 93, 232),
	(25.50, 210, 239, 100, 254),
	(25.60, 205, 229, 95, 254),
	(25.70, 202, 234, 107, 249),
	(25.80, 230, 249, 120, 239),
	(25.90, 233, 254, 123, 229),
	(26.00, 210, 241, 122, 219),
	(26.10, 205, 241, 112, 239),
	(26.20, 207, 241, 110, 231),
	(26.30, 215, 241, 110, 221),
	(26.40, 213, 236, 113, 218),
	(26.50, 215, 236, 115, 221),
	(26.60, 210, 233, 105, 220),
	(26.70, 212, 238, 105, 222),
]
RELOAD_DEPTH = [
	(22.95, 1.0), (23.55, 1.0), (23.85, 1.15), (24.05, 1.2), (24.35, 1.15), (24.55, 1.25), (24.90, 1.1), (25.00, 1.35),
	(25.10, 1.3), (25.20, 1.15), (25.30, 1.05), (25.40, 1.0), (25.80, 1.1), (25.90, 1.1), (26.20, 1.0), (26.70, 1.0),
]


# Cette méthode permet de convertir un relevé de planche en écart à l'écran par rapport à la référence au repos,
# en largeur et hauteur d'écran, lorsque le cadrage de repos de la référence et le nôtre diffèrent légèrement.
def ref_delta(point, rest):
	return Vector(((point[0] - rest[0]) / 400 * 0.6, (point[1] - rest[1]) / 375))


# Cette méthode permet de projeter un point du repère caméra à l'écran (0,0 = haut gauche, 1,1 = bas droite).
def project(p):
	return Vector((0.5 + p.x / p.y * HEIGHT_OVER_WIDTH * 0.5, 0.5 - p.z / p.y * 0.5))


# Cette méthode permet de retrouver le rayon caméra (profondeur y = 1) qui passe par un point de l'écran.
def screen_ray(uv):
	return Vector(((uv.x - 0.5) * 2 / HEIGHT_OVER_WIDTH, 1.0, (0.5 - uv.y) * 2))


# Cette méthode permet de retrouver la pose de l'arme (décalage, angles en degrés) qui place l'œilleton et le canon aux
# positions d'écran voulues ; la profondeur vient du grossissement mesuré et le roulis est un choix, invisible sur ces deux points.
def solve_gun(eye_uv, muzzle_uv, magnify, roll_deg):
	eye = screen_ray(eye_uv) * (EYE_REST.y / magnify)
	ray = screen_ray(muzzle_uv)
	a, b, c = ray.dot(ray), -2 * ray.dot(eye), eye.dot(eye) - GUN_LENGTH * GUN_LENGTH
	depth = (-b + math.sqrt(max(b * b - 4 * a * c, 0.0))) / (2 * a)
	axis = (ray * depth - eye).normalized()
	rotation = Quaternion(axis, math.radians(roll_deg)) @ GUN_AXIS_REST.rotation_difference(axis)
	loc = eye - RECOIL_PIVOT - rotation @ (EYE_REST - RECOIL_PIVOT)
	euler = rotation.to_euler("YXZ")
	return loc, Vector([math.degrees(v) for v in euler])


# Cette méthode permet d'interpoler une table [(t, v1, v2, ...)] par une spline qui passe par chaque échantillon, sans
# ramener la vitesse à zéro entre deux échantillons (voir « Ne pas poser une clé avec courbe » dans docs/animations.md).
def spline(table, t):
	if t <= table[0][0]:
		return list(table[0][1:])
	if t >= table[-1][0]:
		return list(table[-1][1:])
	i = next(k for k in range(len(table) - 1) if t < table[k + 1][0])
	p0, p1 = table[max(i - 1, 0)], table[i]
	p2, p3 = table[i + 1], table[min(i + 2, len(table) - 1)]
	h = p2[0] - p1[0]
	s = (t - p1[0]) / h
	out = []
	for c in range(1, len(p1)):
		m1 = (p2[c] - p0[c]) / (p2[0] - p0[0])
		m2 = (p3[c] - p1[c]) / (p3[0] - p1[0])
		out.append(
			(2 * s**3 - 3 * s**2 + 1) * p1[c]
			+ (s**3 - 2 * s**2 + s) * h * m1
			+ (-2 * s**3 + 3 * s**2) * p2[c]
			+ (s**3 - s**2) * h * m2
		)
	return out


# Cette méthode permet de construire les pistes de l'arme d'une animation depuis sa trajectoire mesurée : `t0` est l'instant
# vidéo de la frame 0, `stretch` le rapport durée en jeu / durée vidéo, et `roll` donne le roulis en fonction du temps vidéo.
def measured_gun(track, depth, roll, t0, stretch):
	cache = {}
	eye_rest_uv, muzzle_rest_uv = project(EYE_REST), project(MUZZLE_REST)

	def pose(t):
		key = round(t * FPS * 4)
		if key not in cache:
			video = t0 + t / stretch
			ex, ey, mx, my = spline(track, video)
			eye_uv = eye_rest_uv + ref_delta((ex, ey), REF_IDLE[0])
			muzzle_uv = muzzle_rest_uv + ref_delta((mx, my), REF_IDLE[1])
			cache[key] = solve_gun(eye_uv, muzzle_uv, spline(depth, video)[0], roll(video))
		return cache[key]

	return (lambda t: pose(t)[0]), (lambda t: pose(t)[1])


# Cette méthode permet de décrire le cycle de culasse par ses instants (lever, recul, tenue, retour, rabattre) ; renvoie les
# clés de la culasse et ces instants, pour y caler la main et les sons.
def bolt_keys(t_start, t_up, t_back, t_hold, t_fwd, t_down, travel=0.75, lift=62):
	lift_k = [(0, Z, "l"), (t_start, Z, "l"), (t_up, (lift, 0, 0), "io"), (t_fwd, (lift, 0, 0), "l"), (t_down, Z, "o")]
	trav_k = [(0, Z, "l"), (t_up, Z, "l"), (t_back, (travel, 0, 0), "o"), (t_hold, (travel, 0, 0), "l"), (t_fwd, Z, "i")]
	return lift_k, trav_k, dict(up=t_up, back=t_back, hold=t_hold, fwd=t_fwd, down=t_down)


# Cette méthode permet d'avancer l'épaule droite pendant le réarmement (le tireur engage le bras
# pour aller chercher le levier), de t_grab jusqu'au retour de la main sur la poignée.
def shoulder_reach(t_grab, t_back_on_grip):
	reach = (0.05, 0.3, 0.2)
	return K([(0, Z, "l"), (t_grab, Z, "l"), (t_grab + 0.13, reach, "io"), (t_back_on_grip - 0.18, reach, "l"), (t_back_on_grip, Z, "io")])


# Cette méthode permet de décrire l'Idle : respiration lente et micro-dérive de l'arme, en boucle
# parfaite sur 4 s (toutes les sinusoïdes ont une période qui divise 4 s).
def spec_idle():
	L = 4.0

	def gl(t):
		b = math.sin(2 * math.pi * t / L)
		return Vector((0.006 * math.sin(2 * math.pi * t / 2.0), 0.0, 0.018 * b))

	def gr(t):
		b = math.sin(2 * math.pi * t / L)
		return Vector((0.35 * b, 0.25 * math.sin(2 * math.pi * t / 2.0 + 0.6), 0.15 * math.sin(2 * math.pi * t / L + 1.3)))

	return dict(
		length=L,
		gun_loc=gl,
		gun_rot=gr,
		bolt_lift=const(),
		bolt_travel=const(),
		hand_R=[(0, 0, GRIP_R, GRIP_R, Z, "l")],
		hand_L=[(0, 0, FOREND_L, FOREND_L, Z, "l")],
	)


# Cette méthode permet de décrire l'Equip : l'arme monte du bas de l'écran, canon vers le bas, puis contrôle de culasse
# (référence 1,80 → 3,00 s, étirée sur les 1,58 s de sortie du jeu).
def spec_equip():
	L, t0 = 1.58, 1.80
	k = L / (3.00 - t0)
	A = lambda video: (video - t0) * k
	roll = lambda video: spline([(1.80, EQUIP_ROLL_LOW), (2.07, EQUIP_ROLL_LOW * 0.6), (2.27, BOLT_ROLL), (2.47, BOLT_ROLL), (2.74, 0.0), (3.00, 0.0)], video)[0]
	gun_loc, gun_rot = measured_gun(EQUIP_TRACK, EQUIP_DEPTH, roll, t0, k)
	lk, tk, bt = bolt_keys(A(2.14), A(2.20), A(2.30), A(2.40), A(2.47), A(2.54))
	t_home = A(2.76)
	return dict(
		length=L,
		gun_loc=gun_loc,
		gun_rot=gun_rot,
		bolt_lift=K(lk),
		bolt_travel=K(tk),
		hand_R=[(A(2.00), A(2.14), GRIP_R, KNOB_R, (0.15, 0, 0.2), "io"), (A(2.56), t_home, KNOB_R, GRIP_R, (0.2, 0, 0.1), "io")],
		shoulder_R=shoulder_reach(A(2.00), t_home),
		hand_L=[(0, 0, FOREND_L, FOREND_L, Z, "l")],
		markers=[("Draw Sound", 0.0), ("Bolt Sound", bt["up"] - 0.07)],
	)


# Cette méthode permet de décrire le Shoot : coup de recul vers l'œil (pic à 0,2 s) avec relevé du canon, retour rapide, puis
# réarmement (référence 19,65 → 21,10 s, à vitesse réelle : le cycle dure environ FireDelay).
def spec_shoot():
	L, t0 = 1.45, 19.65
	A = lambda video: video - t0
	roll = lambda video: spline([(19.65, 0.0), (20.20, 0.0), (20.40, BOLT_ROLL), (20.60, BOLT_ROLL), (20.87, 0.0), (21.10, 0.0)], video)[0]
	gun_loc, gun_rot = measured_gun(SHOOT_TRACK, SHOOT_DEPTH, roll, t0, 1.0)
	lk, tk, bt = bolt_keys(A(20.33), A(20.40), A(20.47), A(20.53), A(20.60), A(20.67))
	t_home = A(20.85)
	return dict(
		length=L,
		gun_loc=gun_loc,
		gun_rot=gun_rot,
		trigger=K([(0, (14, 0, 0), "l"), (0.12, Z, "o")]),
		bolt_lift=K(lk),
		bolt_travel=K(tk),
		hand_R=[(A(20.17), A(20.33), GRIP_R, KNOB_R, (0.15, 0, 0.2), "io"), (A(20.68), t_home, KNOB_R, GRIP_R, (0.2, 0, 0.1), "io")],
		shoulder_R=shoulder_reach(A(20.17), t_home),
		hand_L=[(0, 0, FOREND_L, FOREND_L, Z, "l")],
		# Eject : douille éjectée quand la culasse arrive en arrière (20,47 s de la référence, CasingRules.REMOTE_DELAY)
		markers=[("Shoot Sound", 0.0), ("Bolt Sound", bt["up"] - 0.07), ("Eject", bt["back"])],
	)


# Cette méthode permet de décrire le Reload : le canon monte et la crosse descend vers l'épaule, la main gauche quitte le
# garde-main, sort le chargeur et en ramène un neuf, la claque fait sauter l'arme, puis culasse (référence 22,95 → 26,70 s).
def spec_reload():
	L, t0 = 3.70, 22.95
	k = L / (26.70 - t0)
	A = lambda video: (video - t0) * k
	roll = lambda video: spline([(22.95, 0.0), (23.55, 0.0), (23.95, RELOAD_ROLL), (25.10, RELOAD_ROLL), (25.40, 4.0), (25.70, BOLT_ROLL), (25.95, BOLT_ROLL), (26.30, 0.0), (26.70, 0.0)], video)[0]
	gun_loc, gun_rot = measured_gun(RELOAD_TRACK, RELOAD_DEPTH, roll, t0, k)
	lk, tk, bt = bolt_keys(A(25.60), A(25.68), A(25.80), A(25.90), A(26.00), A(26.10))
	t_out, t_in, t_hit, t_home = A(23.45), A(24.85), A(25.00), A(26.22)
	away = ("FC", Vector((-0.2, 1.7, -3.9)))  # main gauche hors écran : elle lâche l'ancien chargeur et prend le neuf
	under_well = ("Handle", local_to("Handle", (1.1, 2.6, -1.55)))
	return dict(
		length=L,
		gun_loc=gun_loc,
		gun_rot=gun_rot,
		bolt_lift=K(lk),
		bolt_travel=K(tk),
		# décalage du chargeur dans le repère de l'arme (vers le bas = sortie du puits)
		mag_off=K([
			(0, Z, "l"),
			(t_out - 0.05, Z, "l"),
			(t_out + 0.05, (0, 0, -0.08), "o"),
			(t_out + 0.2, (0, 0, -0.32), "i"),
			(A(24.75), (0, 0, -0.32), "l"),
			(t_in, (0, 0, -0.06), "io"),
			(t_hit, Z, "o"),
		]),
		mag_in_hand=K([(0, Z, "l"), (t_out + 0.05, Z, "l"), (t_out + 0.15, (1, 0, 0), "io"), (A(24.80), (1, 0, 0), "l"), (t_in + 0.03, Z, "io")]),
		hand_R=[(A(25.42), A(25.60), GRIP_R, KNOB_R, (0.15, 0, 0.2), "io"), (A(26.08), t_home, KNOB_R, GRIP_R, (0.2, 0, 0.1), "io")],
		shoulder_R=shoulder_reach(A(25.42), t_home),
		hand_L=[
			(A(23.00), A(23.38), FOREND_L, MAG_L, (-0.25, 0, -0.15), "io"),
			(t_out + 0.12, A(24.02), MAG_L, away, (-0.3, 0, 0), "i"),
			(A(24.28), A(24.80), away, MAG_L, (-0.35, 0, 0), "o"),
			(t_hit - 0.03, t_hit + 0.02, MAG_L, under_well, Z, "o"),
			(A(25.12), A(25.40), under_well, FOREND_L, (-0.2, 0, -0.1), "io"),
		],
		markers=[("ClipOut Sound", t_out), ("ClipIn Sound", t_in), ("ClipHit Sound", t_hit), ("Bolt Sound", bt["up"] - 0.07)],
	)


SPECS = {"Idle": spec_idle, "Equip": spec_equip, "Shoot": spec_shoot, "Reload": spec_reload}

# ------------------------------------------------------------------------------------------------
# Export Roblox : Transform de chaque Motor6D, calculé depuis les matrices monde des pièces.
# Part1 = Part0 · C0 · Transform · C1⁻¹  ⇒  Transform = C0⁻¹ · Part0⁻¹ · Part1 · C1
# (le changement de repère Roblox → Blender s'annule dans Part0⁻¹ · Part1).
# ------------------------------------------------------------------------------------------------
STATIC_PARTS = {"Barrel", "Fittings", "Handguard", "Scope", "ScopeLens", "Stock"}
# Échelle du modèle ViewModels.AWP dans Studio (Model:GetScale()) : l'Animator multiplie les translations
# des poses par cette échelle, il faut donc les stocker divisées par elle (rotations inchangées).
MODEL_SCALE = 0.5169681310653687


# Cette méthode permet de convertir des composantes de CFrame Roblox en matrice 4x4.
def cframe_to_matrix(c):
	x, y, z, a, b, cc, d, e, f, g, h, i = c
	return Matrix(((a, b, cc, x), (d, e, f, y), (g, h, i, z), (0, 0, 0, 1)))


# Cette méthode permet de convertir une matrice 4x4 (orthonormalisée) en composantes de CFrame.
def matrix_to_cframe(m):
	r = m.to_3x3().normalized()
	t = m.translation
	return [t.x, t.y, t.z, r[0][0], r[0][1], r[0][2], r[1][0], r[1][1], r[1][2], r[2][0], r[2][1], r[2][2]]


# Cette méthode permet d'exporter une action en JSON (Transform par Motor6D et par frame, marqueurs)
# lorsque le rig Studio a été décrit dans rig.json (C0/C1 de chaque Motor6D).
def export(name, rig_json_path, out_path, step=1):
	import json

	rig = json.load(open(rig_json_path))
	act = bpy.data.actions["AWP_" + name]
	RIG.animation_data.action = act
	RIG.animation_data.action_slot = act.slots[0]
	f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
	motors = [m for m in rig["motors"] if m["p1"] not in STATIC_PARTS]
	frames = []
	scene = bpy.context.scene
	for f in list(range(f0, f1 + 1, step)) + ([f1] if (f1 - f0) % step else []):
		scene.frame_set(f)
		poses = {}
		for m in motors:
			a0 = bpy.data.objects[m["p0"]].matrix_world
			a1 = bpy.data.objects[m["p1"]].matrix_world
			t = cframe_to_matrix(m["c0"]).inverted() @ a0.inverted() @ a1 @ cframe_to_matrix(m["c1"])
			t.translation = t.translation / MODEL_SCALE
			poses[m["p1"]] = [round(v, 5) for v in matrix_to_cframe(t)]
		frames.append({"t": round((f - f0) / FPS, 4), "poses": poses})
	markers = [{"name": pm.name, "t": round(pm.frame / FPS, 4)} for pm in act.pose_markers]
	parents = {m["p1"]: m["p0"] for m in motors}
	data = {"name": name, "loop": name == "Idle", "frames": frames, "markers": markers, "parents": parents}
	with open(out_path, "w") as fh:
		json.dump(data, fh)
	return len(frames)


# Cette méthode permet de (re)générer toutes les animations ou une seule par son nom.
def build(only=None):
	acts = {}
	for name, fn in SPECS.items():
		if only and name != only:
			continue
		acts[name] = bake(name, fn())
	return acts


if __name__ == "__main__":
	build()
