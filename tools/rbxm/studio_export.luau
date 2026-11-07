-- studio_export.luau
-- À exécuter DANS Roblox Studio (mode Edit), pendant que `lune run tools/rbxm/receive.luau` tourne :
-- via le MCP Studio (`execute_luau`, contexte plugin) ou la barre de commande (celle-ci exige
-- Game Settings > Security > Allow HTTP Requests). Sérialise chaque viewmodel (ReplicatedStorage.ViewModels.*),
-- chaque Tool (StarterPack.*), chaque map (Workspace.Maps.*) et chaque matière (MaterialService.*, MaterialVariant
-- des maps) en .rbxm et les envoie au serveur local, qui les écrit dans assets/rbx/ViewModels/<Nom>.rbxm,
-- assets/rbx/Tools/<Nom>.rbxm, assets/rbx/Maps/<Nom>.rbxm et assets/rbx/Materials/<Nom>.rbxm.
-- Ne modifie rien dans la place.

local HttpService = game:GetService("HttpService")
local SerializationService = game:GetService("SerializationService")

local BASE = "http://localhost:34990" -- port fixe, cf. receive.luau
-- Dossier à exporter seul (ex. "Menu"), à passer aussi à receive.luau ; nil = export complet.
local ONLY: string? = nil

-- Cette méthode permet d'encoder un buffer en hexadécimal lorsqu'il doit transiter dans un corps HTTP texte.
local function toHex(b: buffer): string
	local parts = table.create(buffer.len(b))
	for i = 0, buffer.len(b) - 1 do
		parts[i + 1] = string.format("%02x", buffer.readu8(b, i))
	end
	return table.concat(parts)
end

-- Cette méthode permet de vérifier les enfants d'un conteneur avant tout envoi lorsqu'un nom ne peut pas
-- devenir un fichier unique (caractère interdit, doublon même à la casse près) ou qu'une classe est inattendue.
local function checkChildren(container: Instance, className: string)
	local seen = {}
	for _, child in container:GetChildren() do
		assert(
			child:IsA(className),
			child:GetFullName() .. " n'est pas un " .. className .. " : il serait supprimé par Rojo"
		)
		assert(string.match(child.Name, "^[%w_%-]+$"), "nom non exportable : " .. child:GetFullName())
		local key = string.lower(child.Name)
		assert(not seen[key], "nom en double (casse comprise) : " .. child:GetFullName())
		seen[key] = true
	end
end

-- Cette méthode permet de sérialiser une instance et de l'envoyer au serveur lorsqu'on exporte un asset
-- vers assets/rbx/<dossier>/<Nom>.rbxm.
local function export(instance: Instance, folder: string): string
	local bytes = SerializationService:SerializeInstancesAsync({ instance })
	local path = "assets/rbx/" .. folder .. "/" .. instance.Name .. ".rbxm"
	HttpService:PostAsync(
		BASE .. "/rbxm?path=" .. HttpService:UrlEncode(path),
		toHex(bytes),
		Enum.HttpContentType.TextPlain
	)
	return path
end

local exported = {}
local ok, err = pcall(function()
	-- Conteneurs exportés : dossier cible, conteneur dans la place, classe attendue des enfants
	local sources = {
		{ "ViewModels", game:GetService("ReplicatedStorage"):FindFirstChild("ViewModels"), "Model" },
		{ "Tools", game:GetService("StarterPack"), "Tool" },
		{ "Maps", workspace:FindFirstChild("Maps"), "Model" },
		{ "Materials", game:GetService("MaterialService"), "MaterialVariant" },
		{ "Menu", game:GetService("ReplicatedStorage"):FindFirstChild("MenuMirrors"), "Model" },
	}
	for _, source in sources do
		if not ONLY or ONLY == source[1] then
			assert(source[2], "conteneur introuvable pour " .. source[1])
			checkChildren(source[2], source[3])
		end
	end
	for _, source in sources do
		if not ONLY or ONLY == source[1] then
			for _, child in source[2]:GetChildren() do
				table.insert(exported, export(child, source[1]))
				task.wait()
			end
		end
	end
end)
-- toujours prévenir le serveur, avec l'erreur éventuelle, pour qu'il s'arrête sans supprimer de fichier à tort
HttpService:PostAsync(BASE .. "/done", if ok then "OK" else tostring(err), Enum.HttpContentType.TextPlain)
if not ok then
	error(err)
end
return table.concat(exported, "\n")
