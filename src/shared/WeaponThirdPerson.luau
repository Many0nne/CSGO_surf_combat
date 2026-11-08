-- WeaponThirdPerson.luau
-- Arme en 3e personne des joueurs (#5).
--   • Modèle 3P : pièces de l'arme clonées depuis ReplicatedStorage.ViewModels.<nom> (sans bras,
--     caméra ni humanoid), réduites à l'échelle du personnage et soudées à la main par une Weld
--     "Grip3P" dont le C0 vaut le grip défini par arme (WeaponConfig.Weapons.<nom>.ThirdPerson).
--   • Tenue (#107) : couche haut du corps posée par chaque client (WeaponThirdPersonView) sur les Motor6D, après
--     l'Animator : les pistes de déplacement gardent les jambes, la tenue remplace bras et taille (POSES).
--   • Tir / recharge / switch : le serveur pose les attributs Weapon3PAction / Weapon3PActionAt sur
--     le personnage ; chaque client décale localement le C0 du grip via actionOffset (visuel seul).
--   • Visibilité : le joueur local ne voit jamais son propre modèle 3P, le viewmodel le remplace (isVisibleTo).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local CharacterConfig = require(ReplicatedStorage.Shared.CharacterConfig)

local WeaponThirdPerson = {}

WeaponThirdPerson.MODEL_NAME = "Weapon3P"
WeaponThirdPerson.TAG = "Weapon3P"
WeaponThirdPerson.WELD_NAME = "Grip3P"
WeaponThirdPerson.ACTION_ATTR = "Weapon3PAction"
WeaponThirdPerson.ACTION_AT_ATTR = "Weapon3PActionAt"
WeaponThirdPerson.ACTIONS = { Shoot = true, Reload = true, Equip = true }

local SHOOT_TIME = 0.25 -- recul d'un tir (s)
local STAB_TIME = 0.3 -- estoc melee (s)
local EQUIP_TIME_MAX = 0.6 -- montée de l'arme au switch (s)
-- Fondu d'entrée / sortie de la tenue et du passage sol / air : le même que celui des pistes de déplacement.
WeaponThirdPerson.HOLD_FADE_TIME = CharacterConfig.FADE_TIME

-- Couche de tenue : une pose et son poids courant (fondu entre deux armes).
export type HoldLayer = { pose: string, weight: number }

-- Réglages par défaut d'une arme sans ThirdPerson : tenue fusil F1 et grip de l'AWP (canon, X local de la poignée,
-- vers l'avant avec cette tenue). La position de la poignée dépend du modèle : à régler par arme.
local DEFAULT = {
	Scale = WeaponConfig.Weapons.AWP.ThirdPerson.Scale,
	Grip = WeaponConfig.Weapons.AWP.ThirdPerson.Grip,
	Pose = "Rifle",
}

-- Tenues validées sur la planche tools/anim/poses3p/planche.html : Transform imposé à chaque Motor6D (rig R15 du
-- StarterCharacter). Joints : tenus en permanence. AirJoints : tenus seulement en l'air (poids = part aérienne).
-- Généré par tools/anim/poses3p/export_pose.js : modifier poses.js puis régénérer, ne pas retoucher à la main.
WeaponThirdPerson.POSES = {
	-- F1 : épaulé, taille tournée de 40° vers la droite (tête compensée), main gauche sous le garde-main.
	Rifle = {
		Joints = {
			Waist = CFrame.new(0, 0, 0, 0.76604, 0, -0.64279, 0, 1, 0, 0.64279, 0, 0.76604),
			Neck = CFrame.new(0, 0, 0, 0.76604, 0, 0.64279, 0, 1, 0, -0.64279, 0, 0.76604),
			RightShoulder = CFrame.new(
				0,
				0,
				0,
				0.12312,
				0.98009,
				0.15574,
				-0.547,
				0.19797,
				-0.81339,
				-0.82803,
				0.01496,
				0.56049
			),
			RightElbow = CFrame.new(0, 0, 0, 1, 0, 0, 0, 0.59846, -0.80115, 0, 0.80115, 0.59846),
			RightWrist = CFrame.identity,
			LeftShoulder = CFrame.new(
				0,
				0,
				0,
				0.79535,
				-0.32194,
				0.51359,
				0.52136,
				-0.06888,
				-0.85055,
				0.3092,
				0.94425,
				0.11307
			),
			LeftElbow = CFrame.new(0, 0, 0, 1, 0, 0, 0, 0.96822, -0.25011, 0, 0.25011, 0.96822),
			LeftWrist = CFrame.identity,
		},
	},
	-- C1 : garde basse, lame en avant. Bras gauche libre au sol (piste de déplacement), baissé en l'air.
	Melee = {
		Joints = {
			RightShoulder = CFrame.new(
				0,
				0,
				0,
				0.99027,
				-0.13917,
				0,
				0.12613,
				0.89749,
				-0.42262,
				0.05882,
				0.41851,
				0.90631
			),
			RightElbow = CFrame.new(0, 0, 0, 1, 0, 0, 0, 0.34202, -0.93969, 0, 0.93969, 0.34202),
			RightWrist = CFrame.identity,
		},
		AirJoints = {
			LeftShoulder = CFrame.new(
				0,
				0,
				0,
				0.98481,
				0.17365,
				0,
				-0.16849,
				0.95555,
				-0.24192,
				-0.04201,
				0.23825,
				0.9703
			),
			LeftElbow = CFrame.new(0, 0, 0, 1, 0, 0, 0, 0.81915, -0.57358, 0, 0.57358, 0.81915),
			LeftWrist = CFrame.identity,
		},
	},
}

-- Articulations qu'une tenue peut piloter (noms des Motor6D du rig R15).
WeaponThirdPerson.HOLD_JOINTS =
	{ "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }

local HANDS = { "RightHand", "Right Arm" }

-- Pièces du viewmodel qui ne font pas partie de l'arme.
local VIEWMODEL_EXCLUDE = {
	LeftArm = true,
	RightArm = true,
	Humanoid = true,
	HumanoidRootPart = true,
	FakeCamera = true,
	Animations = true,
	AnimSaves = true,
	Sounds = true,
}

-- Cette méthode permet de lire les réglages 3P d'une arme lorsqu'on construit ou anime son modèle,
-- en complétant les champs absents par les valeurs par défaut.
function WeaponThirdPerson.getSettings(weaponName: string?)
	local cfg = weaponName and WeaponConfig.Weapons[weaponName]
	local tp = (cfg and cfg.ThirdPerson) or {}
	return {
		Scale = tp.Scale or DEFAULT.Scale,
		Grip = tp.Grip or DEFAULT.Grip,
		Pose = tp.Pose or DEFAULT.Pose,
		IsMelee = cfg ~= nil and cfg.IsMelee == true,
		ReloadTime = (cfg and cfg.ReloadTime) or 2,
		EquipTime = math.min((cfg and cfg.EquipTime) or EQUIP_TIME_MAX, EQUIP_TIME_MAX),
	}
end

-- Cette méthode permet de calculer le CFrame monde de la poignée lorsqu'on connaît celui de la main,
-- le grip de l'arme et le décalage d'action courant (même formule que la Weld : main * C0).
function WeaponThirdPerson.handleCFrame(handCFrame: CFrame, grip: CFrame, offset: CFrame?): CFrame
	return handCFrame * grip * (offset or CFrame.identity)
end

-- Cette méthode permet de calculer le décalage procédural de l'arme (repère poignée) lorsqu'une action
-- 3P est en cours depuis `elapsed` secondes ; identité hors action ou une fois l'action terminée.
function WeaponThirdPerson.actionOffset(action: string?, elapsed: number, settings): CFrame
	if not action or elapsed < 0 then
		return CFrame.identity
	end
	if action == "Shoot" then
		if settings.IsMelee then
			if elapsed >= STAB_TIME then
				return CFrame.identity
			end
			-- estoc le long de la lame (+Z local de la poignée du couteau, vers la pointe)
			return CFrame.new(0, 0, 0.6 * math.sin(math.pi * elapsed / STAB_TIME))
		end
		if elapsed >= SHOOT_TIME then
			return CFrame.identity
		end
		local k = 1 - elapsed / SHOOT_TIME
		return CFrame.new(-0.25 * k, 0, 0) * CFrame.Angles(0, 0, math.rad(12) * k)
	elseif action == "Reload" then
		local duration = settings.ReloadTime
		if elapsed >= duration then
			return CFrame.identity
		end
		local s = math.sin(math.pi * elapsed / duration)
		return CFrame.Angles(math.rad(35) * s, 0, math.rad(-25) * s)
	elseif action == "Equip" then
		local duration = settings.EquipTime
		if elapsed >= duration then
			return CFrame.identity
		end
		local p = elapsed / duration
		local k = (1 - p) * (1 - p)
		if settings.IsMelee then
			-- couteau : la pointe part basse (rotation autour de l'axe latéral Y de la poignée) puis remonte
			return CFrame.Angles(0, math.rad(60) * k, 0)
		end
		return CFrame.Angles(0, 0, math.rad(-60) * k)
	end
	return CFrame.identity
end

-- Cette méthode permet d'obtenir la cible d'une articulation pour une tenue lorsqu'on pose le haut du corps ;
-- renvoie (Transform, poids) : poids 1 si tenue en permanence, `air` (0 au sol, 1 en l'air) si tenue en l'air, 0 sinon.
function WeaponThirdPerson.holdTarget(poseName: string?, jointName: string, air: number): (CFrame?, number)
	local pose = poseName and WeaponThirdPerson.POSES[poseName]
	if not pose then
		return nil, 0
	end
	local cf = pose.Joints and pose.Joints[jointName]
	if cf then
		return cf, 1
	end
	cf = pose.AirJoints and pose.AirJoints[jointName]
	if cf then
		return cf, math.clamp(air, 0, 1)
	end
	return nil, 0
end

-- Cette méthode permet de rapprocher un poids de sa cible à vitesse constante lorsqu'une tenue entre, sort ou passe
-- du sol à l'air : le trajet complet dure HOLD_FADE_TIME.
function WeaponThirdPerson.approach(weight: number, target: number, dt: number): number
	local step = dt / WeaponThirdPerson.HOLD_FADE_TIME
	if weight < target then
		return math.min(target, weight + step)
	end
	return math.max(target, weight - step)
end

-- Cette méthode permet de faire évoluer les couches de tenue d'un personnage lorsqu'une frame est simulée : la pose
-- courante monte vers 1, les anciennes descendent vers 0 puis disparaissent ; renvoie true si une couche a été ajoutée.
function WeaponThirdPerson.stepLayers(layers: { HoldLayer }, pose: string?, dt: number): boolean
	local top = layers[#layers]
	local added = false
	if pose and (not top or top.pose ~= pose) then
		table.insert(layers, { pose = pose, weight = 0 })
		added = true
	end
	for i = #layers, 1, -1 do
		local layer = layers[i]
		local target = if layer.pose == pose and i == #layers then 1 else 0
		layer.weight = WeaponThirdPerson.approach(layer.weight, target, dt)
		if layer.weight <= 0 and target == 0 then
			table.remove(layers, i)
		end
	end
	return added
end

-- Cette méthode permet de calculer le Transform d'une articulation lorsque des tenues s'y appliquent : moyenne
-- pondérée des cibles des couches, puis un seul fondu depuis la pose animée ; nil si aucune couche ne la tient.
function WeaponThirdPerson.blendHold(animated: CFrame, layers: { HoldLayer }, jointName: string, air: number): CFrame?
	local mix: CFrame? = nil
	local total = 0
	for _, layer in layers do
		local target, weight = WeaponThirdPerson.holdTarget(layer.pose, jointName, air)
		local w = weight * layer.weight
		if target and w > 0 then
			total += w
			mix = if mix then mix:Lerp(target, w / total) else target
		end
	end
	if not mix then
		return nil
	end
	return animated:Lerp(mix, math.min(1, total))
end

-- Cette méthode permet de décider si un modèle 3P doit être rendu pour ce client lorsqu'on met à jour
-- la vue : caché pour son propre personnage, sans condition de caméra (le jeu est toujours en 1re personne,
-- comme le corps masqué par FPSCamera), et visible pour les autres joueurs.
function WeaponThirdPerson.isVisibleTo(isOwnCharacter: boolean): boolean
	return not isOwnCharacter
end

-- Cette méthode permet de trouver le premier enfant (récursif) portant l'un des noms donnés lorsque
-- le rig peut être R15 ou R6.
local function findAny(model: Instance, names: { string }): Instance?
	for _, name in names do
		local inst = model:FindFirstChild(name, true)
		if inst then
			return inst
		end
	end
	return nil
end

-- Cette méthode permet de construire le modèle 3P (pièces de l'arme soudées à la poignée, mises à l'échelle)
-- lorsqu'on l'attache à un personnage ; nil si le viewmodel ou sa Handle est introuvable.
local function buildModel(viewmodelName: string, scale: number): (Model?, BasePart?)
	local container = ReplicatedStorage:FindFirstChild("ViewModels")
	local template = container and container:FindFirstChild(viewmodelName)
	if not (template and template:IsA("Model")) then
		return nil, nil
	end
	local handleSrc = template:FindFirstChild("Handle")
	if not (handleSrc and handleSrc:IsA("BasePart")) then
		return nil, nil
	end

	local gun = Instance.new("Model")
	gun.Name = WeaponThirdPerson.MODEL_NAME
	local handle: BasePart? = nil
	for _, child in template:GetChildren() do
		if not VIEWMODEL_EXCLUDE[child.Name] and child:IsA("BasePart") then
			local clone = child:Clone()
			clone.Anchored = false
			clone.CanCollide = false
			clone.CanQuery = false
			clone.CanTouch = false
			clone.Massless = true
			-- ombre d'une arme tenue : quasi invisible, mais tout le maillage passe dans la passe d'ombres (#88)
			clone.CastShadow = false
			clone.Parent = gun
			if clone.Name == "Handle" then
				handle = clone
			end
		end
	end
	if not handle then
		gun:Destroy()
		return nil, nil
	end

	-- Disposition interne de l'arme relative à sa poignée (pleine échelle, avant ScaleTo).
	local toHandle = handleSrc.CFrame:Inverse()
	for _, part in gun:GetChildren() do
		local src = template:FindFirstChild(part.Name)
		if part:IsA("BasePart") and part ~= handle and src and src:IsA("BasePart") then
			local weld = Instance.new("Weld")
			weld.Part0 = handle
			weld.Part1 = part
			weld.C0 = toHandle * src.CFrame
			weld.Parent = handle
		end
	end

	-- Sons de l'arme sur la poignée : audibles en 3D par tout le monde.
	local sounds = template:FindFirstChild("Sounds")
	if sounds then
		for _, s in sounds:GetChildren() do
			if s:IsA("Sound") then
				s:Clone().Parent = handle
			end
		end
	end

	gun.PrimaryPart = handle
	gun:ScaleTo(scale)
	return gun, handle
end

-- Cette méthode permet de marquer le début d'une action 3P (tir, recharge, switch) côté serveur lorsqu'elle
-- se produit ; les attributs répliqués déclenchent l'animation procédurale sur tous les clients.
function WeaponThirdPerson.setAction(character: Model, action: string)
	if not WeaponThirdPerson.ACTIONS[action] then
		return
	end
	character:SetAttribute(WeaponThirdPerson.ACTION_ATTR, action)
	character:SetAttribute(WeaponThirdPerson.ACTION_AT_ATTR, workspace:GetServerTimeNow())
end

-- Cette méthode permet de retirer le modèle 3P d'un personnage côté serveur lorsque l'arme est rangée ou remplacée
-- (la tenue des bras s'arrête d'elle-même côté client avec le modèle).
function WeaponThirdPerson.detach(character: Model)
	local existing = character:FindFirstChild(WeaponThirdPerson.MODEL_NAME)
	if existing then
		existing:Destroy()
	end
	character:SetAttribute(WeaponThirdPerson.ACTION_ATTR, nil)
	character:SetAttribute(WeaponThirdPerson.ACTION_AT_ATTR, nil)
end

-- Cette méthode permet d'attacher le modèle 3P d'une arme à la main d'un personnage côté
-- serveur lorsqu'il l'équipe : grip de WeaponConfig, action "Equip" ; renvoie le modèle.
function WeaponThirdPerson.attach(character: Model, weaponName: string, viewmodelName: string?): Model?
	WeaponThirdPerson.detach(character)
	local hand = findAny(character, HANDS)
	if not (hand and hand:IsA("BasePart")) then
		return nil
	end
	local settings = WeaponThirdPerson.getSettings(weaponName)
	local gun, handle = buildModel(viewmodelName or weaponName, settings.Scale)
	if not gun or not handle then
		return nil
	end

	handle.CFrame = WeaponThirdPerson.handleCFrame(hand.CFrame, settings.Grip)
	local grip = Instance.new("Weld")
	grip.Name = WeaponThirdPerson.WELD_NAME
	grip.Part0 = hand
	grip.Part1 = handle
	grip.C0 = settings.Grip
	grip.Parent = handle

	gun:SetAttribute("WeaponName", weaponName)
	gun:SetAttribute("GripC0", settings.Grip)
	gun:AddTag(WeaponThirdPerson.TAG)
	gun.Parent = character

	WeaponThirdPerson.setAction(character, "Equip")
	return gun
end

return WeaponThirdPerson
