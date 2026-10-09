-- CharacterAppearance.luau
-- Rig et skin communs joueurs/bots (#1).
--   • Rig : StarterPlayer.StarterCharacter (template unique, chargé par Roblox pour les
--     joueurs, cloné par BotManager pour les bots). À défaut, rig R15 généré depuis
--     la même description.
--   • Skin : appliqué directement sur le modèle (BodyColors + Shirt/Pants/visage),
--     ce qui fonctionne quel que soit le rig, contrairement à une HumanoidDescription
--     que Roblox ignore dès qu'un StarterCharacter existe.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local CharacterConfig = require(ReplicatedStorage.Shared.CharacterConfig)

local CharacterAppearance = {}

-- Cette méthode permet de renvoyer le rig de référence lorsqu'un bot doit être construit ;
-- nil si la place n'a pas de StarterCharacter (BotManager génère alors un rig depuis buildDescription).
function CharacterAppearance.getTemplate(): Model?
	local template = StarterPlayer:FindFirstChild("StarterCharacter")
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

-- Cette méthode permet de créer une HumanoidDescription aux couleurs/échelles communes lorsqu'il faut
-- générer un rig sans StarterCharacter (une instance neuve par appel).
function CharacterAppearance.buildDescription(): HumanoidDescription
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = CharacterConfig.SKIN_COLOR
	desc.TorsoColor = CharacterConfig.TORSO_COLOR
	desc.LeftArmColor = CharacterConfig.ARM_COLOR
	desc.RightArmColor = CharacterConfig.ARM_COLOR
	desc.LeftLegColor = CharacterConfig.LEG_COLOR
	desc.RightLegColor = CharacterConfig.LEG_COLOR
	desc.BodyTypeScale = 0
	desc.ProportionScale = 0
	return desc
end

-- Cette méthode permet de remplacer (ou créer) l'enfant `className` nommé `name` d'un modèle lorsqu'on
-- applique le skin, pour qu'un respawn ou un second appel n'empile pas de doublons.
local function replaceChild(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChildOfClass(className)
	if existing then
		existing:Destroy()
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

-- Cette méthode permet d'appliquer le skin commun à un personnage (joueur ou bot) lorsqu'il spawn, côté serveur :
-- couleurs du corps toujours, vêtements et visage seulement si un asset est configuré.
function CharacterAppearance.apply(model: Model)
	local colors = replaceChild(model, "BodyColors", "Body Colors") :: BodyColors
	colors.HeadColor3 = CharacterConfig.SKIN_COLOR
	colors.TorsoColor3 = CharacterConfig.TORSO_COLOR
	colors.LeftArmColor3 = CharacterConfig.ARM_COLOR
	colors.RightArmColor3 = CharacterConfig.ARM_COLOR
	colors.LeftLegColor3 = CharacterConfig.LEG_COLOR
	colors.RightLegColor3 = CharacterConfig.LEG_COLOR

	if CharacterConfig.SHIRT_ID ~= 0 then
		local shirt = replaceChild(model, "Shirt", "Shirt") :: Shirt
		shirt.ShirtTemplate = "rbxassetid://" .. CharacterConfig.SHIRT_ID
	end
	if CharacterConfig.PANTS_ID ~= 0 then
		local pants = replaceChild(model, "Pants", "Pants") :: Pants
		pants.PantsTemplate = "rbxassetid://" .. CharacterConfig.PANTS_ID
	end
	local head = model:FindFirstChild("Head")
	if CharacterConfig.FACE_ID ~= 0 and head then
		local face = replaceChild(head, "Decal", "face") :: Decal
		face.Texture = "rbxassetid://" .. CharacterConfig.FACE_ID
	end
end

return CharacterAppearance
