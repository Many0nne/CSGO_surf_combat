# build_anims.py
# Génère les animations viewmodel de l'AWP (Idle, Equip, Shoot, Reload) dans AWP_Viewmodel_Anims.blend.
# À lancer depuis Blender (Text Editor > Run, ou exec(open(path).read())) avec le rig "Rig" déjà construit.
#
# Principe : chaque animation est décrite par des canaux d'intention (pose de l'arme, culasse, chargeur,
# position des mains sur l'arme) ; l'arme passe ensuite dans un ressort amorti du second ordre pour lui
# donner de l'inertie (démarrages lents, dépassement puis stabilisation), et les mains suivent l'arme
# par IK. Le repère est celui de la caméra du viewmodel : X droite, Y avant, Z haut (unités = studs).

import math

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

FPS = 60
RIG = bpy.data.objects["Rig"]
ARM = RIG.data
REST = {b.name: b.matrix_local.copy() for b in ARM.bones}

# --- Réglages de « poids » de l'arme -------------------------------------------------------------
GUN_FREQ = 4.2  # Hz : fréquence propre du ressort de l'arme (plus bas = plus lourd)
GUN_ZETA = 0.62  # amortissement (< 1 : léger dépassement avant stabilisation)
CAM_FREQ = 5.5
CAM_ZETA = 0.7
RECOIL_PIVOT = Vector((1.09, -0.6, -1.0))  # creux de l'épaule : pivot du relevé au tir

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


# Cette méthode permet de faire suivre une cible par un ressort amorti du second ordre, avec des
# impulsions de vitesse (recul, chocs de culasse) ; renvoie la série filtrée échantillonnée à FPS.
def spring(targets, freq, zeta, impulses=(), substeps=8):
	w = 2 * math.pi * freq
	dt = 1.0 / FPS / substeps
	pos = targets[0].copy()
	vel = Vector((0, 0, 0))
	out = []
	imp = {round(t * FPS): Vector(v) for t, v in impulses}
	for i, tgt in enumerate(targets):
		if i in imp:
			vel += imp[i]
		for _ in range(substeps):
			acc = (tgt - pos) * (w * w) - vel * (2 * zeta * w)
			vel += acc * dt
			pos += vel * dt
		out.append(pos.copy())
	return out


# Cette méthode permet de ramener exactement une série à la pose de base sur les dernières frames
# lorsque l'animation doit se terminer pile sur l'Idle (pas de saut au changement de piste).
def settle_tail(series, seconds):
	n = len(series)
	k = max(1, int(seconds * FPS))
	for i in range(max(0, n - k), n):
		s = (i - (n - k)) / (k - 1) if k > 1 else 1
		series[i] = series[i] * (1 - ease("io", s))
	return series


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


# Cette méthode permet d'échantillonner une animation décrite par `spec`, d'appliquer le ressort à
# l'arme, de placer mains/chargeur et d'écrire toutes les clés dans une action dédiée.
def bake(name, spec):
	n = int(round(spec["length"] * FPS)) + 1
	ts = [i / FPS for i in range(n)]
	gun_loc = [spec["gun_loc"](t) for t in ts]
	gun_rot = [spec["gun_rot"](t) for t in ts]
	cam_loc = [spec["cam_loc"](t) for t in ts]
	cam_rot = [spec["cam_rot"](t) for t in ts]
	if spec.get("spring", True):
		gun_loc = spring(gun_loc, GUN_FREQ, GUN_ZETA, spec.get("imp_loc", ()))
		gun_rot = spring(gun_rot, GUN_FREQ, GUN_ZETA, spec.get("imp_rot", ()))
		cam_loc = spring(cam_loc, CAM_FREQ, CAM_ZETA, spec.get("cam_imp_loc", ()))
		cam_rot = spring(cam_rot, CAM_FREQ, CAM_ZETA, spec.get("cam_imp_rot", ()))
		for s in (gun_loc, gun_rot, cam_loc, cam_rot):
			settle_tail(s, spec.get("settle", 0.25))
	act = new_action("AWP_" + name)
	pbs = RIG.pose.bones
	for i, t in enumerate(ts):
		f = i
		ch = {
			"gun_loc": gun_loc[i],
			"gun_rot": gun_rot[i],
			"cam_loc": cam_loc[i],
			"cam_rot": cam_rot[i],
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


# Cette méthode permet de décrire le cycle de culasse (lever, tirer, pousser, rabattre) à partir de
# l'instant t0 où la main atteint le levier ; renvoie les clés culasse et les instants clés.
def bolt_cycle(t0, travel=0.75, lift=62):
	t_up, t_back, t_hold, t_fwd, t_down = t0 + 0.075, t0 + 0.19, t0 + 0.235, t0 + 0.345, t0 + 0.41
	lift_k = [(0, (0, 0, 0), "l"), (t0, (0, 0, 0), "l"), (t_up, (lift, 0, 0), "io"), (t_fwd, (lift, 0, 0), "l"), (t_down, (0, 0, 0), "o")]
	trav_k = [(0, (0, 0, 0), "l"), (t_up, (0, 0, 0), "l"), (t_back, (travel, 0, 0), "o"), (t_hold, (travel, 0, 0), "l"), (t_fwd, (0, 0, 0), "i")]
	return lift_k, trav_k, dict(up=t_up, back=t_back, hold=t_hold, fwd=t_fwd, down=t_down)


# Cette méthode permet d'avancer l'épaule droite pendant le réarmement (le tireur engage le bras
# pour aller chercher le levier), de t_grab jusqu'au retour de la main sur la poignée.
def shoulder_reach(t_grab, bt):
	reach = (0.05, 0.3, 0.2)
	return K([(0, Z, "l"), (t_grab, Z, "l"), (t_grab + 0.13, reach, "io"), (bt["down"] + 0.02, reach, "l"), (bt["down"] + 0.22, Z, "io")])


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

	def cl(t):
		return Vector((0, 0, 0.01 * math.sin(2 * math.pi * t / L - 0.4)))

	return dict(
		length=L,
		spring=False,
		gun_loc=gl,
		gun_rot=gr,
		cam_loc=cl,
		cam_rot=const(),
		bolt_lift=const(),
		bolt_travel=const(),
		hand_R=[(0, 0, GRIP_R, GRIP_R, Z, "l")],
		hand_L=[(0, 0, FOREND_L, FOREND_L, Z, "l")],
	)


# Cette méthode permet de décrire l'Equip : l'arme remonte depuis le bas-droite avec l'inertie
# d'une arme lourde, puis vérification de chambre (culasse) avant de revenir en position.
def spec_equip():
	L = 1.55
	t_bolt = 0.66
	lk, tk, bt = bolt_cycle(t_bolt + 0.06, travel=0.42, lift=58)
	return dict(
		length=L,
		settle=0.3,
		gun_loc=K([
			(0.0, (0.55, -1.0, -1.9), "l"),
			(0.12, (0.45, -0.75, -1.35), "i"),
			(0.42, (-0.05, 0.05, 0.06), "o"),
			(0.6, (0, 0, 0), "io"),
			(t_bolt, (-0.06, -0.1, -0.03), "io"),
			(bt["down"] + 0.05, (-0.08, -0.14, -0.05), "io"),
			(1.25, (0, 0, 0), "io"),
		]),
		gun_rot=K([
			(0.0, (-38, 28, -18), "l"),
			(0.12, (-30, 24, -14), "i"),
			(0.42, (2.5, -3, 1.5), "o"),
			(0.6, (0, 0, 0), "io"),
			(t_bolt, (1.5, 9, 1.5), "io"),
			(bt["down"] + 0.05, (2, 11, 2), "io"),
			(1.25, (0, 0, 0), "io"),
		]),
		imp_loc=[(bt["back"], (0, -0.9, 0)), (bt["fwd"], (0, 1.3, 0.2))],
		imp_rot=[(bt["back"], (0, 0, 0)), (bt["fwd"], (-8, 0, 0)), (bt["down"], (0, -40, 0))],
		cam_loc=K([(0, (0, 0, -0.08), "l"), (0.45, (0, 0, 0), "o")]),
		cam_rot=K([(0, (-3, 1.5, 0), "l"), (0.5, (0, 0, 0), "o")]),
		bolt_lift=K(lk),
		bolt_travel=K(tk),
		hand_R=[(t_bolt - 0.08, t_bolt + 0.06, GRIP_R, KNOB_R, (0.15, 0, 0.2), "io"), (bt["down"] + 0.02, bt["down"] + 0.2, KNOB_R, GRIP_R, (0.2, 0, 0.1), "io")],
		shoulder_R=lambda t: shoulder_reach(t_bolt - 0.08, bt)(t)
		+ track([(0, (0.25, -0.15, -0.45), "l"), (0.4, Z, "io")], t),
		# la main gauche vient « cueillir » le garde-main pendant que l'arme remonte
		hand_L=[(0.14, 0.46, ("FC", Vector((0.2, 2.2, -3.7))), FOREND_L, (-0.2, 0, 0.1), "o")],
		markers=[("Draw Sound", 0.0), ("Bolt Sound", bt["up"] - 0.07)],
	)


# Cette méthode permet de décrire le Shoot : recul franc relevé autour de l'épaule, retour lourd,
# puis réarmement complet (main droite au levier, culasse, retour à la poignée).
def spec_shoot():
	L = 1.6
	t_grab = 0.5
	lk, tk, bt = bolt_cycle(t_grab + 0.13, travel=0.75, lift=62)
	return dict(
		length=L,
		settle=0.3,
		gun_loc=K([
			(0.0, (0, 0, 0), "l"),
			(0.4, (0, 0, 0), "l"),
			(t_grab, (-0.05, -0.12, -0.04), "io"),
			(bt["back"], (-0.1, -0.24, -0.1), "io"),
			(bt["down"], (-0.08, -0.16, -0.08), "io"),
			(1.25, (0, 0, 0), "io"),
		]),
		gun_rot=K([
			(0.0, (0, 0, 0), "l"),
			(0.4, (0, 0, 0), "l"),
			(t_grab, (1.5, 7, 1), "io"),
			(bt["back"], (2.5, 12, 2), "io"),
			(bt["down"], (1.5, 9, 1), "io"),
			(1.25, (0, 0, 0), "io"),
		]),
		# recul : forte impulsion vers l'arrière et muzzle up, un peu de roulis
		imp_loc=[(0.0, (0.25, -11.0, 3.2)), (bt["back"], (0, -1.0, 0)), (bt["fwd"], (0, 1.5, 0.2))],
		imp_rot=[(0.0, (230, -30, 25)), (bt["fwd"], (-10, 0, 0)), (bt["down"], (0, -55, 0))],
		cam_loc=const(),
		cam_rot=const(),
		cam_imp_loc=[(0.0, (0, -1.6, 0.4))],
		cam_imp_rot=[(0.0, (60, 0, 0))],
		trigger=K([(0, (14, 0, 0), "l"), (0.12, (0, 0, 0), "o")]),
		bolt_lift=K(lk),
		bolt_travel=K(tk),
		hand_R=[(t_grab, t_grab + 0.13, GRIP_R, KNOB_R, (0.15, 0, 0.2), "io"), (bt["down"] + 0.02, bt["down"] + 0.2, KNOB_R, GRIP_R, (0.2, 0, 0.1), "io")],
		shoulder_R=shoulder_reach(t_grab, bt),
		hand_L=[(0, 0, FOREND_L, FOREND_L, Z, "l")],
		markers=[("Shoot Sound", 0.0), ("Bolt Sound", bt["up"] - 0.07)],
	)


# Cette méthode permet de décrire le Reload : l'arme bascule pour exposer le puits, main gauche
# sur le chargeur, extraction, chargeur neuf hors écran, insertion + claque, retour, réarmement.
def spec_reload():
	L = 3.65
	t_out, t_in, t_hit = 0.62, 2.08, 2.16
	t_grab_r = 2.52
	lk, tk, bt = bolt_cycle(t_grab_r + 0.13, travel=0.75, lift=62)
	tilt_loc = (-0.35, -0.35, 0.3)
	tilt_rot = (9, 24, 12)
	return dict(
		length=L,
		settle=0.35,
		gun_loc=K([
			(0.0, Z, "l"),
			(0.32, tilt_loc, "io"),
			(t_out, (-0.33, -0.32, 0.36), "io"),
			(1.3, (-0.3, -0.3, 0.34), "io"),
			(1.95, (-0.36, -0.36, 0.3), "io"),
			(t_in, (-0.36, -0.34, 0.33), "o"),
			(2.45, (-0.08, -0.15, -0.04), "io"),
			(bt["back"], (-0.1, -0.24, -0.1), "io"),
			(bt["down"], (-0.08, -0.16, -0.08), "io"),
			(3.3, Z, "io"),
		]),
		gun_rot=K([
			(0.0, Z, "l"),
			(0.32, tilt_rot, "io"),
			(t_out, (11, 25, 13), "io"),
			(1.3, (8, 23, 11), "io"),
			(1.95, (10, 26, 12), "io"),
			(t_in, (9, 25, 12), "o"),
			(2.45, (1.5, 8, 1), "io"),
			(bt["back"], (2.5, 12, 2), "io"),
			(bt["down"], (1.5, 9, 1), "io"),
			(3.3, Z, "io"),
		]),
		# chocs : extraction (le chargeur « lâche »), insertion, claque de paume, culasse
		imp_loc=[(t_out, (0, 0, 1.2)), (t_in, (0, 0, 2.2)), (t_hit, (0, 0.4, 3.5)), (bt["back"], (0, -1.0, 0)), (bt["fwd"], (0, 1.5, 0.2))],
		imp_rot=[(t_out, (-12, 0, 0)), (t_in, (25, -10, 0)), (t_hit, (40, -25, 0)), (bt["fwd"], (-10, 0, 0)), (bt["down"], (0, -55, 0))],
		cam_loc=const(),
		cam_rot=K([(0, Z, "l"), (0.4, (0, 1.2, 0), "io"), (2.3, (0, 1.2, 0), "l"), (2.7, Z, "io")]),
		cam_imp_rot=[(t_hit, (8, 0, 0))],
		bolt_lift=K(lk),
		bolt_travel=K(tk),
		# décalage du chargeur dans le repère de l'arme (vers le bas = sortie du puits)
		mag_off=K([
			(0, Z, "l"),
			(0.5, Z, "l"),
			(t_out, (0, 0, -0.08), "o"),
			(0.75, (0, 0, -0.32), "i"),
			(1.95, (0, 0, -0.32), "l"),
			(2.0, (0, 0, -0.06), "io"),
			(t_in, Z, "o"),
		]),
		mag_in_hand=K([(0, Z, "l"), (0.6, Z, "l"), (0.7, (1, 0, 0), "io"), (1.95, (1, 0, 0), "l"), (2.03, Z, "io")]),
		hand_R=[(t_grab_r, t_grab_r + 0.13, GRIP_R, KNOB_R, (0.15, 0, 0.2), "io"), (bt["down"] + 0.02, bt["down"] + 0.2, KNOB_R, GRIP_R, (0.2, 0, 0.1), "io")],
		shoulder_R=lambda t: shoulder_reach(t_grab_r, bt)(t)
		+ track([(0, Z, "l"), (0.32, (-0.05, 0.15, 0.12), "io"), (2.3, (-0.05, 0.15, 0.12), "l"), (2.5, Z, "io")], t),
		hand_L=[
			(0.12, 0.5, FOREND_L, MAG_L, (-0.25, 0, -0.15), "io"),
			(0.7, 1.2, MAG_L, ("FC", Vector((-0.3, 1.6, -3.6))), (-0.3, 0, 0), "i"),
			(1.45, 1.95, ("FC", Vector((-0.3, 1.6, -3.6))), MAG_L, (-0.35, 0, 0), "o"),
			(t_hit, t_hit + 0.02, MAG_L, ("Handle", local_to("Handle", (1.1, 2.6, -1.55))), Z, "o"),
			(t_hit + 0.06, 2.55, ("Handle", local_to("Handle", (1.1, 2.6, -1.55))), FOREND_L, (-0.2, 0, -0.1), "io"),
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
