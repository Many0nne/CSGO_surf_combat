-- studio_save_viewmodel.luau
-- À coller dans `execute_luau` (mode Edit, contexte Edit), pendant que tools/anim/capture_server.py tourne.
-- Exporte UN viewmodel vers assets/rbx/ViewModels/ : contrairement à tools/rbxm/studio_export.luau, les autres armes
-- ne sont pas réécrites (leur .rbxm peut changer de quelques octets à chaque export, voir CLAUDE.md).

local VIEWMODEL = "M9Bayonet"

local Http = game:GetService("HttpService")
local Serialization = game:GetService("SerializationService")

local model = game:GetService("ReplicatedStorage").ViewModels[VIEWMODEL]
local bytes = Serialization:SerializeInstancesAsync({ model })
local parts = table.create(buffer.len(bytes))
for i = 0, buffer.len(bytes) - 1 do
	parts[i + 1] = string.format("%02x", buffer.readu8(bytes, i))
end
local path = Http:UrlEncode("assets/rbx/ViewModels/" .. VIEWMODEL .. ".rbxm")
return Http:PostAsync("http://127.0.0.1:34991/save?path=" .. path, table.concat(parts), Enum.HttpContentType.TextPlain)
