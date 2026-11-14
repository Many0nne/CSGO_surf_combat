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
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local InventoryRules = require(Shared:WaitForChild("InventoryRules"))
local WeaponSkins = require(Shared:WaitForChild("WeaponSkins"))
local LocalInventory = require(script.Parent.LocalInventory)
local SkinPreloadRules = require(script.Parent.SkinPreloadRules)

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

-- Cette méthode permet de lister les cartes pas encore demandées des skins d'un joueur lorsque ses attributs sont lus
-- (au plus un skin par emplacement, cf. SkinPreloadRules).
local function pendingUris(player: Player): { string }
	local uris: { string } = {}
	local skins = SkinPreloadRules.skinsOf(
		player:GetAttribute(InventoryRules.ATTRIBUTE),
		player:GetAttribute(InventoryRules.EQUIPPED_ATTRIBUTE),
		viewmodelOf
	)
	for _, request in skins do
		local folder = WeaponSkins.folder(request.viewmodel, request.skin)
		if folder then
			for _, uri in SkinPreloadRules.fresh(WeaponSkins.mapUris(folder), requested) do
				table.insert(uris, uri)
			end
		end
	end
	return uris
end

-- Cette méthode permet de lancer en tâche de fond le chargement des cartes des skins d'un joueur lorsque son équipement
-- est connu ou change ; une carte en échec sera redemandée au prochain changement.
local function preloadPlayer(player: Player)
	local uris = pendingUris(player)
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

-- Cette méthode permet de suivre un autre joueur lorsqu'il est présent ou arrive : ses skins sont demandés tout de suite,
-- puis à chaque changement de ses attributs (un seul appel différé quand les deux changent ensemble). Les connexions
-- d'un Player parti sont libérées avec lui.
local function watchOther(player: Player)
	local pending = false
	-- Cette méthode permet de programmer un seul préchargement lorsque l'un des deux attributs change.
	local function schedule()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			if player.Parent then
				preloadPlayer(player)
			end
		end)
	end
	player:GetAttributeChangedSignal(InventoryRules.ATTRIBUTE):Connect(schedule)
	player:GetAttributeChangedSignal(InventoryRules.EQUIPPED_ATTRIBUTE):Connect(schedule)
	preloadPlayer(player)
end

-- Cette méthode permet de démarrer le préchargement lorsque le client démarre : équipement du joueur local (celui par
-- défaut tant que l'attribut n'est pas arrivé) puis chaque changement, et skins équipés des autres joueurs (#342),
-- déjà présents ou à leur arrivée.
function SkinPreloader.init()
	if started then
		return
	end
	started = true
	LocalInventory.onChanged(function()
		preloadPlayer(Players.LocalPlayer)
	end)
	preloadPlayer(Players.LocalPlayer)
	Players.PlayerAdded:Connect(function(player)
		if player ~= Players.LocalPlayer then
			watchOther(player)
		end
	end)
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer then
			watchOther(player)
		end
	end
end

return SkinPreloader
