-- CharacterAppearance.luau
-- Rig et skin communs (#1).
--   • Rig : StarterPlayer.StarterCharacter (template unique, chargé par Roblox pour les
--     joueurs, cloné pour la cible du helper de playtest). À défaut, rig R15 généré
--     depuis la même description.
--   • Skin : appliqué directement sur le modèle (BodyColors + Shirt/Pants/visage),
--     ce qui fonctionne quel que soit le rig, contrairement à une HumanoidDescription
--     que Roblox ignore dès qu'un StarterCharacter existe.
--   • Tenue de personnage (#521) : par-dessus, les cartes d'une tenue achetée (`dress`), sans toucher aux pièces du rig
--     (mêmes tailles, mêmes collisions, même hitbox).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local CharacterConfig = require(ReplicatedStorage.Shared.CharacterConfig)
local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)

local CharacterAppearance = {}

-- Attribut posé sur tout ce qu'ajoute une tenue (et sur le personnage : id de la tenue portée), pour la retirer
local OUTFIT_ATTRIBUTE = "Outfit"
-- Attribut de la tête du rig cachée sous la coque d'une tenue
local HIDDEN_ATTRIBUTE = "OutfitHidden"
-- Pièces des bras d'un viewmodel habillées par la tenue (mêmes noms et meshs que le rig)
local ARM_PARTS = {
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
}

-- Cette méthode permet de renvoyer le rig de référence lorsqu'un personnage doit être construit côté serveur ;
-- nil si la place n'a pas de StarterCharacter (un rig est alors généré depuis buildDescription).
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

-- Cette méthode permet de retirer d'un personnage la tenue posée par `dress` (cartes des pièces, coque de la tête) et
-- de lui rendre sa tête d'origine (visible, avec le visage du rig de référence) lorsqu'il change de tenue.
local function undress(model: Model)
	for _, item in model:GetDescendants() do
		if item:GetAttribute(OUTFIT_ATTRIBUTE) ~= nil then
			item:Destroy()
		end
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") and head:GetAttribute(HIDDEN_ATTRIBUTE) then
		head.Transparency = 0
		head:SetAttribute(HIDDEN_ATTRIBUTE, nil)
		local template = CharacterAppearance.getTemplate()
		local face = template and template:FindFirstChild("Head") and template.Head:FindFirstChild("face")
		if face and not head:FindFirstChild("face") then
			face:Clone().Parent = head
		end
	end
	model:SetAttribute(OUTFIT_ATTRIBUTE, nil)
end

-- Cette méthode permet d'habiller un personnage d'une tenue de personnage (#521) lorsqu'il apparaît, à l'accueil ou quand
-- l'écran d'équipement en montre une : SurfaceAppearance du dossier ReplicatedStorage.Outfits.<appearance> copiées sur
-- les pièces du même nom (une copie : un script de jeu ne peut pas écrire les cartes), et coque de la tête (MeshPart
-- `Head` du dossier) soudée à la tête du rig, cachée. Purement visuel : la coque ne bloque, ne pèse et ne reçoit rien, la
-- tête du rig reste la hitbox. nil, id inconnu ou dossier absent : tenue d'origine. Idempotente.
function CharacterAppearance.dress(model: Model, outfitId: string?)
	if model:GetAttribute(OUTFIT_ATTRIBUTE) == outfitId and outfitId ~= nil then
		return
	end
	undress(model)
	local item = outfitId and InventoryRules.item(outfitId)
	local folder = ReplicatedStorage:FindFirstChild("Outfits")
	local source = item
		and item.type == InventoryRules.Type.OUTFIT
		and item.appearance
		and folder
		and folder:FindFirstChild(item.appearance)
	if not source then
		return
	end
	for _, child in source:GetChildren() do
		local part = model:FindFirstChild(child.Name)
		if child:IsA("SurfaceAppearance") and part and part:IsA("BasePart") then
			for _, old in part:GetChildren() do
				if old:IsA("SurfaceAppearance") then
					old:Destroy()
				end
			end
			local copy = child:Clone()
			copy:SetAttribute(OUTFIT_ATTRIBUTE, outfitId)
			copy.Parent = part
		end
	end
	local shell = source:FindFirstChild("Head")
	local head = model:FindFirstChild("Head")
	if shell and shell:IsA("BasePart") and head and head:IsA("BasePart") then
		local copy = shell:Clone()
		copy.Name = "OutfitHead"
		copy.Anchored = false
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.Massless = true
		copy.CFrame = head.CFrame
		copy:SetAttribute(OUTFIT_ATTRIBUTE, outfitId)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = copy
		weld.Parent = copy
		copy.Parent = model
		head.Transparency = 1
		head:SetAttribute(HIDDEN_ATTRIBUTE, true)
		-- Le visage est retiré, pas caché : le clip de fin remet la transparence des Decals à 0 (HighlightPlayer)
		for _, decal in head:GetChildren() do
			if decal:IsA("Decal") then
				decal:Destroy()
			end
		end
	end
	model:SetAttribute(OUTFIT_ATTRIBUTE, outfitId)
end

-- Cette méthode permet de lire la tenue que porte un personnage (#521) lorsqu'un système la recopie ; nil : d'origine.
function CharacterAppearance.outfitOf(model: Instance): string?
	local id = model:GetAttribute(OUTFIT_ATTRIBUTE)
	return if type(id) == "string" then id else nil
end

-- Cette méthode permet de poser sur les bras d'un viewmodel (1re personne) les cartes de la tenue (#521) lorsque l'arme
-- est équipée ; les pièces des bras portent les noms et les meshs du rig (LeftUpperArm…). Une tenue peut leur donner
-- des cartes à part (sous-dossier `Viewmodel` : bras très pliés, où un dessin du corps se coupe au coude). nil : bras
-- d'origine.
function CharacterAppearance.dressArms(viewmodel: Instance, outfitId: string?)
	local item = outfitId and InventoryRules.item(outfitId)
	local folder = ReplicatedStorage:FindFirstChild("Outfits")
	local outfit = item
		and item.type == InventoryRules.Type.OUTFIT
		and item.appearance
		and folder
		and folder:FindFirstChild(item.appearance)
	local source = outfit and (outfit:FindFirstChild("Viewmodel") or outfit)
	for _, part in viewmodel:GetDescendants() do
		if part:IsA("BasePart") and ARM_PARTS[part.Name] then
			for _, old in part:GetChildren() do
				if old:IsA("SurfaceAppearance") and old:GetAttribute(OUTFIT_ATTRIBUTE) ~= nil then
					old:Destroy()
				end
			end
			local sa = source and source:FindFirstChild(part.Name)
			if sa and sa:IsA("SurfaceAppearance") then
				local copy = sa:Clone()
				copy:SetAttribute(OUTFIT_ATTRIBUTE, outfitId)
				copy.Parent = part
			end
		end
	end
end

-- Cette méthode permet d'appliquer le skin commun à un personnage lorsqu'il spawn, côté serveur :
-- couleurs du corps toujours, vêtements et visage seulement si un asset est configuré, puis la tenue `outfitId` (#521,
-- nil : d'origine).
function CharacterAppearance.apply(model: Model, outfitId: string?)
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
	CharacterAppearance.dress(model, outfitId)
end

-- Cette méthode permet de lister les pièces du corps d'un rig (ses enfants BasePart) lorsqu'on vérifie qu'un
-- personnage a reçu tout son corps.
function CharacterAppearance.partNames(rig: Instance): { string }
	local names = {}
	for _, child in rig:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(names, child.Name)
		end
	end
	return names
end

-- Cette méthode permet d'attendre côté client les pièces du rig de référence sur un personnage arrivé incomplet par la
-- réplication (#328), avant de mesurer son rig ; renvoie celles encore absentes au bout de `timeout` secondes.
function CharacterAppearance.waitForParts(char: Model, timeout: number): { string }
	local template = CharacterAppearance.getTemplate()
	if not template then
		warn("[CharacterAppearance] pas de StarterCharacter : corps du personnage non attendu (#328)")
		return {}
	end
	local deadline = os.clock() + timeout
	local missing = {}
	for _, name in CharacterAppearance.partNames(template) do
		if not char:FindFirstChild(name) then
			local left = deadline - os.clock()
			if left <= 0 or not char:WaitForChild(name, left) then
				table.insert(missing, name)
			end
		end
	end
	return missing
end

return CharacterAppearance
