-- studio_export.luau
-- À exécuter DANS Roblox Studio (mode Edit), pendant que `lune run tools/rbxm/receive.luau` tourne :
-- via le MCP Studio (`execute_luau`, contexte plugin) ou la barre de commande. Sérialise chaque viewmodel
-- (ReplicatedStorage.ViewModels.*) et chaque Tool (StarterPack.*) en .rbxm et les envoie au serveur local,
-- qui les écrit dans assets/rbx/ViewModels/<Nom>.rbxm et assets/rbx/Tools/<Nom>.rbxm.
-- Ne modifie rien dans la place.

local HttpService = game:GetService("HttpService")
local SerializationService = game:GetService("SerializationService")

local PORT = 34990
local BASE = "http://localhost:" .. PORT

-- Cette méthode permet d'encoder un buffer en hexadécimal lorsqu'il doit transiter dans un corps HTTP texte.
local function toHex(b: buffer): string
	local parts = table.create(buffer.len(b))
	for i = 0, buffer.len(b) - 1 do
		parts[i + 1] = string.format("%02x", buffer.readu8(b, i))
	end
	return table.concat(parts)
end

-- Cette méthode permet de sérialiser une instance et de l'envoyer au serveur lorsqu'on exporte un asset
-- vers assets/rbx/<dossier>/<Nom>.rbxm.
local function export(instance: Instance, folder: string)
	assert(string.match(instance.Name, "^[%w_%-]+$"), "nom non exportable : " .. instance:GetFullName())
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
local viewModels = game:GetService("ReplicatedStorage"):FindFirstChild("ViewModels")
assert(viewModels, "ReplicatedStorage.ViewModels introuvable")
for _, child in viewModels:GetChildren() do
	table.insert(exported, export(child, "ViewModels"))
	task.wait()
end
for _, child in game:GetService("StarterPack"):GetChildren() do
	if child:IsA("Tool") then
		table.insert(exported, export(child, "Tools"))
		task.wait()
	end
end
HttpService:PostAsync(BASE .. "/done", "", Enum.HttpContentType.TextPlain)
return table.concat(exported, "\n")
