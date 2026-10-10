-- WeaponThirdPerson.luau
-- Arme en 3e personne commune joueurs/bots (#5).
--   • Modèle 3P : pièces de l'arme clonées depuis ReplicatedStorage.ViewModels.<nom> (sans bras,
--     caméra ni humanoid), réduites à l'échelle du personnage et soudées à la main par une Weld
--     "Grip3P" dont le C0 vaut le grip défini par arme (WeaponConfig.Weapons.<nom>.ThirdPerson).
--   • Tenue : pose procédurale des épaules (C0 des Motor6D, répliqué par le serveur), sans asset.
--   • Tir / recharge / switch : le serveur pose les attributs Weapon3PAction / Weapon3PActionAt sur
--     le personnage ; chaque client décale localement le C0 du grip via actionOffset (visuel seul).
--   • Visibilité : le joueur local ne voit pas son propre modèle 3P en 1re personne (isVisibleTo).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

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

-- Grip par défaut : canon (X local de la poignée) vers l'avant et dessus (Y local) vers le haut
-- quand le bras est levé à l'horizontale (main : -Y local = avant, -Z local = haut).
local DEFAULT = {
	Scale = 0.5,
	Grip = CFrame.fromMatrix(Vector3.new(0, -0.2, 0), Vector3.new(0, -1, 0), Vector3.new(0, 0, -1)),
	Pose = "Rifle",
}

-- Rotation ajoutée au C0 de chaque épaule (repère du torse) : X+90° lève le bras vers l'avant,
-- la rotation Y le ramène vers l'axe du corps.
WeaponThirdPerson.POSES = {
	Rifle = {
		Right = CFrame.Angles(0, math.rad(10), 0) * CFrame.Angles(math.rad(90), 0, 0),
		Left = CFrame.Angles(0, math.rad(-35), 0) * CFrame.Angles(math.rad(90), 0, 0),
	},
	Melee = {
		Right = CFrame.Angles(math.rad(60), 0, 0),
	},
}

local SHOULDERS = {
	Right = { "RightShoulder", "Right Shoulder" },
	Left = { "LeftShoulder", "Left Shoulder" },
}
local HANDS = { "RightHand", "Right Arm" }
local BASE_C0_ATTR = "Weapon3PBaseC0"

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
			return CFrame.new(0.6 * math.sin(math.pi * elapsed / STAB_TIME), 0, 0)
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
		return CFrame.Angles(0, 0, math.rad(-60) * k)
	end
	return CFrame.identity
end

-- Cette méthode permet de décider si un modèle 3P doit être rendu pour ce client lorsqu'on met à jour
-- la vue : caché seulement pour son propre personnage en 1re personne (le viewmodel le remplace).
function WeaponThirdPerson.isVisibleTo(isOwnCharacter: boolean, firstPerson: boolean): boolean
	return not (isOwnCharacter and firstPerson)
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

-- Cette méthode permet d'appliquer (ou retirer, pose=nil) la pose de tenue sur les épaules lorsqu'une
-- arme est équipée ou rangée ; le C0 d'origine est mémorisé en attribut pour être restauré.
local function applyPose(character: Model, poseName: string?)
	local pose = poseName and WeaponThirdPerson.POSES[poseName] or {}
	for side, names in SHOULDERS do
		local motor = findAny(character, names)
		if motor and motor:IsA("Motor6D") then
			local base = motor:GetAttribute(BASE_C0_ATTR)
			if typeof(base) ~= "CFrame" then
				base = motor.C0
				motor:SetAttribute(BASE_C0_ATTR, base)
			end
			local rotation = pose[side]
			motor.C0 = if rotation then base * rotation else base
		end
	end
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

	-- Sons de l'arme sur la poignée : audibles en 3D par tout le monde (tirs des bots).
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

-- Cette méthode permet de retirer le modèle 3P et la pose de tenue d'un personnage côté serveur lorsque
-- l'arme est rangée ou remplacée.
function WeaponThirdPerson.detach(character: Model)
	local existing = character:FindFirstChild(WeaponThirdPerson.MODEL_NAME)
	if existing then
		existing:Destroy()
	end
	applyPose(character, nil)
	character:SetAttribute(WeaponThirdPerson.ACTION_ATTR, nil)
	character:SetAttribute(WeaponThirdPerson.ACTION_AT_ATTR, nil)
end

-- Cette méthode permet d'attacher le modèle 3P d'une arme à la main d'un personnage (joueur ou bot) côté
-- serveur lorsqu'il l'équipe : grip de WeaponConfig, pose de tenue, action "Equip" ; renvoie le modèle.
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

	applyPose(character, settings.Pose)
	WeaponThirdPerson.setAction(character, "Equip")
	return gun
end

return WeaponThirdPerson
