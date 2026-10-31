--!nolint
-- Génère les KeyframeSequences du viewmodel sniper (Equip / Shoot / Reload).
-- À exécuter dans Studio (barre de commande ou MCP execute_luau), pas par Rojo.
-- Rig attendu : ReplicatedStorage.ViewModels.AWP_New (HumanoidRootPart > FakeCamera > Joint > Handle > Bolt/Magazine/Trigger,
-- bras R15 sur FakeCamera). Sortie : ServerStorage.RBX_ANIMSAVES.AWP_New.{Equip,Shoot,Reload}.

local RIG_NAME = "AWP_New"
local vm = game.ReplicatedStorage.ViewModels[RIG_NAME]
local fc = vm.FakeCamera
local jointM = fc.Joint
local lsM = vm.LeftArm.LeftUpperArm.LeftShoulder
local rsM = vm.RightArm.RightUpperArm.RightShoulder
local H = vm.Handle
local boltM, magM, trigM = H.Bolt, H.Magazine, H.Trigger

local GCAM = jointM.C0 -- repère de l'arme dans l'espace caméra
local BOLT_PIV = GCAM * CFrame.new(0, 0, 0.95)
local KNOB = GCAM * CFrame.new(0.32, -0.31, 1.0)
local MAG = GCAM * CFrame.new(0, -0.52, 0.29)

-- Cette méthode permet de calculer la position de repos d'une main lorsqu'on suit la chaîne de Motor6D du bras.
local function restHand(armModel, side)
	local up = armModel[side .. "UpperArm"]
	local lo = armModel[side .. "LowerArm"]
	local ha = armModel[side .. "Hand"]
	local s, e, w = up[side .. "Shoulder"], lo[side .. "Elbow"], ha[side .. "Wrist"]
	local upper = s.C0 * s.C1:Inverse()
	local lower = upper * e.C0 * e.C1:Inverse()
	return lower * w.C0 * w.C1:Inverse()
end
local R_HAND = restHand(vm.RightArm, "Right")
local L_HAND = restHand(vm.LeftArm, "Left")

local V = Vector3.new
local function rot(p, y, r) return CFrame.Angles(math.rad(p), math.rad(y), math.rad(r)) end
-- Cette méthode permet d'appliquer une transformation rigide autour d'un pivot lorsqu'on anime un bloc (arme, bras).
local function about(pivot, t) return pivot * t * pivot:Inverse() end
-- Cette méthode permet d'amener la main au point visé lorsqu'un bras doit saisir une pièce (translation pure).
local function reach(hand, target, extra)
	return CFrame.new(target.Position - hand.Position + (extra or Vector3.zero))
end

-- Mouvement global de l'arme (et des deux bras), pivot sous la poignée.
local GUN_PIV = GCAM * CFrame.new(0, -0.3, 0.6)
local function gun(pos, p, y, r) return CFrame.new(pos or Vector3.zero) * about(GUN_PIV, rot(p or 0, y or 0, r or 0)) end

-- Cette méthode permet de convertir un mouvement exprimé dans l'espace caméra en Transform de Motor6D lorsqu'on
-- écrit une pose (Transform = C0^-1 * M * C0).
local function tr(motor, m) return motor.C0:Inverse() * m * motor.C0 end

-- État d'une frame : G = mouvement de l'arme, L/R = mouvement additionnel des bras (espace caméra),
-- bolt = {angle, recul}, mag = décalage local, trig = angle.
-- Cette méthode permet de construire une Keyframe complète lorsqu'on lui donne l'état de la frame.
local function keyframe(t, st, ease)
	local G = st.G or CFrame.new()
	local boltT = CFrame.new(0, 0, (st.bolt and st.bolt[2]) or 0) * CFrame.Angles(0, 0, math.rad((st.bolt and st.bolt[1]) or 0))
	local boltCam = about(BOLT_PIV, boltT)
	-- la main suit la position de la boule du levier (pas sa rotation, sinon le bras entier pivote)
	local knobMove = CFrame.new((boltCam * KNOB).Position - KNOB.Position)
	local R = st.Rbolt and (G * knobMove * st.R) or (G * (st.R or CFrame.new()))
	local L = st.Lmag and (G * about(GCAM, CFrame.new(st.mag or Vector3.zero)) * st.L) or (st.Lfree and st.L or G * (st.L or CFrame.new()))
	local style = ease or Enum.PoseEasingStyle.Cubic
	local kf = Instance.new("Keyframe")
	kf.Time = t
	local function pose(name, cf, parent)
		local p = Instance.new("Pose")
		p.Name = name
		p.CFrame = cf or CFrame.new()
		p.EasingStyle = style
		p.EasingDirection = Enum.PoseEasingDirection.InOut
		p.Parent = parent
		return p
	end
	local hrp = pose("HumanoidRootPart", nil, kf)
	local fcp = pose("FakeCamera", nil, hrp)
	local j = pose("Joint", tr(jointM, G), fcp)
	local h = pose("Handle", nil, j)
	pose("Bolt", boltT, h)
	pose("Magazine", st.magFree or CFrame.new(st.mag or Vector3.zero), h)
	pose("Trigger", CFrame.Angles(math.rad(st.trig or 0), 0, 0), h)
	for _, n in { "Stock", "Handguard", "Barrel", "Fittings", "Scope", "ScopeLens" } do
		pose(n, nil, h)
	end
	local lu = pose("LeftUpperArm", tr(lsM, L), fcp)
	pose("LeftHand", nil, pose("LeftLowerArm", nil, lu))
	local ru = pose("RightUpperArm", tr(rsM, R), fcp)
	pose("RightHand", nil, pose("RightLowerArm", nil, ru))
	return kf
end

local function marker(kf, name)
	local m = Instance.new("KeyframeMarker")
	m.Name = name
	kf:AddMarker(m)
end

-- Cette méthode permet d'assembler une séquence lorsqu'on lui passe la liste {temps, état, marqueurs, easing}.
local function sequence(name, frames)
	local ks = Instance.new("KeyframeSequence")
	ks.Name = name
	ks.Loop = false
	ks.Priority = Enum.AnimationPriority.Action
	for _, f in frames do
		local kf = keyframe(f[1], f[2], f[4])
		for _, m in f[3] or {} do
			marker(kf, m)
		end
		kf.Parent = ks
	end
	return ks
end

-- Prises de main
local R_GRAB = reach(R_HAND, KNOB, V(0.12, -0.12, 0.08)) -- main droite sur la boule du levier
local L_MAG = reach(L_HAND, MAG, V(0.05, -0.55, 0)) -- main gauche sous le chargeur

-- Cycle de culasse (main droite) réutilisé par Shoot / Reload / Equip.
-- Cette méthode permet de générer les frames d'un réarmement lorsqu'on donne l'instant de départ et l'amplitude.
local function boltCycle(t0, Gtilt, pull, withSound)
	return {
		{ t0, { G = Gtilt, R = R_GRAB, Rbolt = true, bolt = { 0, 0 } } },
		{ t0 + 0.1, { G = Gtilt, R = R_GRAB, Rbolt = true, bolt = { 72, 0 } } },
		{ t0 + 0.22, { G = Gtilt, R = R_GRAB, Rbolt = true, bolt = { 72, pull } }, withSound and { "Bolt Sound" } or nil },
		{ t0 + 0.36, { G = Gtilt, R = R_GRAB, Rbolt = true, bolt = { 72, 0 } } },
		{ t0 + 0.45, { G = Gtilt, R = R_GRAB, Rbolt = true, bolt = { 0, 0 } } },
	}
end

local function concat(...)
	local out = {}
	for _, list in { ... } do
		for _, v in list do
			table.insert(out, v)
		end
	end
	return out
end

local REST = {}
local TILT = gun(V(-0.15, 0.12, 0.1), 4, 6, 14) -- arme penchée vers la gauche pendant le réarmement

-- SHOOT (1.6 s, < ShootAnimTime 1.63)
local KICK = gun(V(0, 0.06, 0.28), 6, -1.5, -2)
local shoot = sequence("Shoot", concat({
	{ 0, { trig = 0 }, { "Shoot Sound" }, Enum.PoseEasingStyle.Linear },
	{ 0.04, { G = KICK, trig = -14 }, nil, Enum.PoseEasingStyle.Linear },
	{ 0.2, { G = gun(V(0, 0.03, 0.15), 3, -0.5, -1), trig = -14 } },
	{ 0.38, { trig = 0 } },
}, boltCycle(0.55, TILT, 0.75, true), {
	{ 1.28, { G = gun(V(-0.05, 0.04, 0.05), 1, 2, 5) } },
	{ 1.6, REST },
}))

-- EQUIP (1.55 s)
local equip = sequence("Equip", concat({
	{ 0, { G = gun(V(0.6, -1.6, 0.6), -55, 20, 40) }, { "Draw Sound" } },
	{ 0.42, { G = gun(V(0, 0.06, -0.05), 3, -2, -4) } },
	{ 0.6, REST },
}, boltCycle(0.72, TILT, 0.35, true), {
	{ 1.35, { G = gun(V(-0.03, 0.02, 0), 0.5, 1, 3) } },
	{ 1.55, REST },
}))

-- RELOAD (3.65 s, < ReloadTime 3.7)
local RTILT = gun(V(-0.25, 0.2, 0.25), 8, 10, -18) -- arme basculée pour présenter le puits de chargeur
local reload = sequence("Reload", concat({
	{ 0, REST },
	{ 0.3, { G = RTILT } },
	{ 0.5, { G = RTILT, L = L_MAG, Lmag = true } },
	{ 0.62, { G = RTILT, L = L_MAG, Lmag = true }, { "ClipOut Sound" } },
	{ 0.85, { G = RTILT, L = L_MAG, Lmag = true, mag = V(0, -0.45, 0) } },
	{ 1.2, { G = RTILT, L = L_MAG, Lmag = true, mag = V(0, -2.6, 0.4) } },
	{ 1.55, { G = RTILT, L = L_MAG, Lmag = true, mag = V(0, -2.6, 0.4) } },
	{ 1.95, { G = RTILT, L = L_MAG, Lmag = true, mag = V(0, -0.35, 0) } },
	{ 2.08, { G = RTILT, L = L_MAG, Lmag = true }, { "ClipIn Sound" } },
	{ 2.16, { G = gun(V(-0.25, 0.26, 0.25), 9, 10, -18), L = L_MAG, Lmag = true }, { "ClipHit Sound" } },
	{ 2.4, { G = TILT } },
}, boltCycle(2.5, TILT, 0.75, true), {
	{ 3.2, { G = gun(V(-0.05, 0.04, 0.05), 1, 2, 5) } },
	{ 3.65, REST },
}))

local saves = game.ServerStorage:FindFirstChild("RBX_ANIMSAVES") or Instance.new("Folder")
saves.Name = "RBX_ANIMSAVES"
saves.Parent = game.ServerStorage
local folder = saves:FindFirstChild(RIG_NAME) or Instance.new("ObjectValue")
folder.Name = RIG_NAME
folder.Value = vm
folder.Parent = saves
for _, ks in { equip, shoot, reload } do
	local old = folder:FindFirstChild(ks.Name)
	if old then
		old:Destroy()
	end
	ks.Parent = folder
end
return "ok"
