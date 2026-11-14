-- Préchargement des textures des skins équipés (#333) : les cartes d'un skin (4 par pièce, 1024²) ne se chargent
-- qu'au premier affichage, et l'arme paraît grise le temps qu'elles arrivent (~2 à 3 s mesurées dans Studio pour un
-- skin jamais affiché). Dès le démarrage, puis à chaque changement d'équipement, le client demande les cartes des skins
-- équipés, pour que le premier équipement en partie les trouve déjà en cache.
--
-- ContentProvider:PreloadAsync ne lit pas les cartes d'une SurfaceAppearance (aucune requête) et échoue sur un id
-- brut (type d'asset deviné) : chaque carte passe par un ImageLabel hors de l'interface (cf. docs/assets.md).
-- Seuls les skins équipés sont préchargés : l'écran d'équipement charge déjà ceux de sa liste en les affichant, et tout
-- l'inventaire de l'admin (12 skins) pèserait des centaines de Mo de textures.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local InventoryRules = require(Shared:WaitForChild("InventoryRules"))
local WeaponSkins = require(Shared:WaitForChild("WeaponSkins"))
local LocalInventory = require(script.Parent.LocalInventory)

local SkinPreloader = {}

-- Ids des cartes déjà demandées (ou en cours) : un changement d'équipement ne redemande que les nouvelles
local requested: { [string]: boolean } = {}
local started = false

-- Cette méthode permet de donner le viewmodel d'un Tool (attribut ViewmodelName, sinon son nom) lorsqu'on cherche le
-- dossier de son skin.
local function viewmodelOf(toolName: string): string
	local folder = ReplicatedStorage:FindFirstChild("Tools")
	local tool = folder and folder:FindFirstChild(toolName)
	local viewmodel = tool and tool:GetAttribute("ViewmodelName")
	return if type(viewmodel) == "string" then viewmodel else toolName
end

-- Cette méthode permet de lister les cartes des skins équipés pas encore demandées lorsque l'équipement est lu.
local function pendingUris(): { string }
	local equipped = LocalInventory.equipped()
	local uris: { string } = {}
	for _, toolName in InventoryRules.equippedTools(equipped) do
		local folder = WeaponSkins.folder(viewmodelOf(toolName), InventoryRules.skinOfTool(equipped, toolName))
		if folder then
			for _, uri in WeaponSkins.mapUris(folder) do
				if not requested[uri] then
					requested[uri] = true
					table.insert(uris, uri)
				end
			end
		end
	end
	return uris
end

-- Cette méthode permet de lancer en tâche de fond le chargement des cartes des skins équipés lorsque l'équipement est
-- connu ou change ; une carte en échec sera redemandée au prochain changement.
local function preloadEquipped()
	local uris = pendingUris()
	if #uris == 0 then
		return
	end
	task.spawn(function()
		local images = table.create(#uris)
		for _, uri in uris do
			local image = Instance.new("ImageLabel")
			image.Image = uri
			table.insert(images, image)
		end
		ContentProvider:PreloadAsync(images, function(uri: string, status: Enum.AssetFetchStatus)
			if status ~= Enum.AssetFetchStatus.Success then
				requested[uri] = nil
			end
		end)
		for _, image in images do
			image:Destroy()
		end
	end)
end

-- Cette méthode permet de démarrer le préchargement lorsque le client démarre : équipement actuel (celui par défaut
-- tant que l'attribut n'est pas arrivé), puis chaque changement d'inventaire ou d'équipement.
function SkinPreloader.init()
	if started then
		return
	end
	started = true
	LocalInventory.onChanged(preloadEquipped)
	preloadEquipped()
end

return SkinPreloader
