-- studio_build.luau
-- À exécuter DANS Roblox Studio (mode Edit, MCP `execute_luau`), plugin Rojo déconnecté : construit
-- ReplicatedStorage.MenuMirrors (un Model par jeu d'éclats : AWP, M9, Vides) depuis les modèles publiés, avec leur
-- SurfaceAppearance (atlas, masque émissif, teinte). Une SurfaceAppearance ne se règle pas en jeu par script : ces
-- jeux sont donc construits ici, puis exportés en .rbxm (tools/rbxm/studio_export.luau avec ONLY = "Menu").
-- Le code envoyé doit commencer par `local DATA = (function() <contenu de MenuMirrorsData.luau> end)()` :
--   bash tools/menu/studio_build.sh   (écrit .maquettes/studio_build_full.luau, à coller dans execute_luau)

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EMISSIVE = 1.5 -- intensité de l'image de l'arme (EmissiveStrength), cf. docs/ui.md

-- Cette méthode permet de régler un éclat importé (physique, ombre, apparence) lorsque son jeu est construit.
local function setupShard(part: MeshPart, info: any, asset: any)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true -- les tirs du menu touchent les éclats (#112, étape 4)
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	for _, old in part:GetChildren() do
		old:Destroy()
	end
	local look = Instance.new("SurfaceAppearance")
	look.ColorMap = asset.atlas
	look.AlphaMode = Enum.AlphaMode.Transparency
	-- Teinte propre à chaque éclat, comme des verres de lots différents (froide : bleu gardé à 1)
	look.Color = Color3.new(info.tint, info.tint, 1)
	if asset.mask then
		look.EmissiveMaskContent = Content.fromUri(asset.mask)
		look.EmissiveStrength = EMISSIVE
	end
	look.Parent = part
end

-- Cette méthode permet de construire un jeu d'éclats depuis son modèle publié lorsque MenuMirrors est (re)créé ;
-- vérifie que chaque éclat du modèle a ses données et inversement.
local function buildSet(name: string, folder: Folder)
	local asset = DATA.assets[name]
	local data = DATA.sets[name]
	local loaded = InsertService:LoadAsset(asset.model)
	local model = Instance.new("Model")
	model.Name = name
	local count = 0
	for _, part in loaded:GetDescendants() do
		if part:IsA("MeshPart") then
			local info = data[part.Name]
			assert(info, name .. " : pas de données pour " .. part.Name)
			setupShard(part, info, asset)
			part.Parent = model
			count += 1
		end
	end
	loaded:Destroy()
	for shardName in data do
		assert(model:FindFirstChild(shardName), name .. " : " .. shardName .. " absent du modèle publié")
	end
	model.Parent = folder
	return count
end

local old = ReplicatedStorage:FindFirstChild("MenuMirrors")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "MenuMirrors"
local report = {}
for _, name in { "AWP", "M9", "Vides" } do
	table.insert(report, name .. "=" .. buildSet(name, folder))
end
folder.Parent = ReplicatedStorage
return "MenuMirrors construit : " .. table.concat(report, ", ")
