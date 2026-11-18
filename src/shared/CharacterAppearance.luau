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
-- Attributs d'une pièce ajoutée par une tenue (MeshPart du dossier, #521) : pièce du rig qui la porte, place par
-- rapport à elle (CFrame, défaut : confondue), et tête du rig à cacher dessous (casque fermé)
local ATTACH_ATTRIBUTE = "OutfitAttach"
local OFFSET_ATTRIBUTE = "OutfitOffset"
local HIDES_HEAD_ATTRIBUTE = "OutfitHidesHead"
-- Amincissement (largeur et profondeur) des bras d'un viewmodel habillé, et attribut de leur taille d'origine
local UPPER_ARM_THIN = 0.96
local BASE_SIZE_ATTRIBUTE = "OutfitBaseSize"
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

-- Cette méthode permet de cacher la tête du rig (et d'en retirer le visage) lorsqu'une pièce de tenue la recouvre.
local function hideHead(head: BasePart)
	head.Transparency = 1
	head:SetAttribute(HIDDEN_ATTRIBUTE, true)
	-- Le visage est retiré, pas caché : le clip de fin remet la transparence des Decals à 0 (HighlightPlayer)
	for _, decal in head:GetChildren() do
		if decal:IsA("Decal") then
			decal:Destroy()
		end
	end
end

-- Cette méthode permet de souder au personnage une copie d'une pièce de tenue (casque, col, épaulière…) lorsqu'on
-- l'habille : posée sur la pièce du rig nommée par OutfitAttach (la coque `Head` de MERCURE : sur la tête), à
-- OutfitOffset près, sans collision, requête, contact ni masse.
local function attachPiece(model: Model, piece: BasePart, outfitId: string)
	local attachName = piece:GetAttribute(ATTACH_ATTRIBUTE)
	if type(attachName) ~= "string" then
		attachName = if piece.Name == "Head" then "Head" else nil
	end
	local target = attachName and model:FindFirstChild(attachName)
	if not (target and target:IsA("BasePart")) then
		return
	end
	local offset = piece:GetAttribute(OFFSET_ATTRIBUTE)
	local copy = piece:Clone()
	copy.Name = "Outfit" .. piece.Name
	copy.Anchored = false
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.Massless = true
	copy.CFrame = if typeof(offset) == "CFrame" then target.CFrame * offset else target.CFrame
	copy:SetAttribute(OUTFIT_ATTRIBUTE, outfitId)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = target
	weld.Part1 = copy
	weld.Parent = copy
	copy.Parent = model
	if attachName == "Head" and (piece.Name == "Head" or piece:GetAttribute(HIDES_HEAD_ATTRIBUTE) == true) then
		hideHead(target)
	end
end

-- Cette méthode permet d'habiller un personnage d'une tenue de personnage (#521) lorsqu'il apparaît, à l'accueil ou quand
-- l'écran d'équipement en montre une : SurfaceAppearance du dossier ReplicatedStorage.Outfits.<appearance> copiées sur
-- les pièces du même nom (une copie : un script de jeu ne peut pas écrire les cartes), et pièces ajoutées (MeshParts du
-- dossier : coque de la tête, casque, épaulières…) soudées au rig (`attachPiece`). Purement visuel : les pièces ajoutées
-- ne bloquent, ne pèsent et ne reçoivent rien, le rig reste la hitbox. nil, id inconnu ou dossier absent : tenue
-- d'origine. Idempotente.
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
	for _, child in source:GetChildren() do
		if child:IsA("BasePart") then
			attachPiece(model, child, outfitId :: string)
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
-- est équipée ; les pièces des bras portent les noms et les meshs du rig (LeftUpperArm…). Habillés, les bras (épaule au
-- coude) s'amincissent de UPPER_ARM_THIN : au coude du viewmodel, presque droit, leurs faces et celles de l'avant-bras
-- se superposaient presque et les deux dessins s'y disputaient l'affichage. nil : bras d'origine, taille rendue.
function CharacterAppearance.dressArms(viewmodel: Instance, outfitId: string?)
	local item = outfitId and InventoryRules.item(outfitId)
	local folder = ReplicatedStorage:FindFirstChild("Outfits")
	local source = item
		and item.type == InventoryRules.Type.OUTFIT
		and item.appearance
		and folder
		and folder:FindFirstChild(item.appearance)
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
			if string.find(part.Name, "UpperArm") then
				local base = part:GetAttribute(BASE_SIZE_ATTRIBUTE)
				if typeof(base) ~= "Vector3" then
					base = part.Size
					part:SetAttribute(BASE_SIZE_ATTRIBUTE, base)
				end
				local thin = if source then UPPER_ARM_THIN else 1
				part.Size = Vector3.new(base.X * thin, base.Y, base.Z * thin)
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
