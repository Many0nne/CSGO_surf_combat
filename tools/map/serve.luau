-- serve.luau
-- Sert en local les scripts à exécuter dans Studio (générateur de map, export .rbxm) pour ne pas les recopier.
-- Usage (racine du worktree) : lune run tools/map/serve.luau   (port fixe 34992, Ctrl+C pour arrêter)
-- Puis dans Studio, mode Edit (MCP `execute_luau` ou barre de commande, avec Allow HTTP Requests) :
--   return loadstring(game:GetService("HttpService"):GetAsync("http://localhost:34992/build_arena.luau"))()
-- (build_city.luau : ancienne map « ville ensablée », gardée comme seconde map possible)
-- (ou /studio_export.luau, pendant que `lune run tools/rbxm/receive.luau` tourne)

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")

local PORT = 34992
local FILES = {
	["/build_arena.luau"] = "tools/map/build_arena.luau",
	["/build_city.luau"] = "tools/map/build_city.luau",
	["/studio_export.luau"] = "tools/rbxm/studio_export.luau",
}

if not fs.isFile(FILES["/build_arena.luau"]) then
	error("à lancer depuis la racine du dépôt (tools/map/build_arena.luau introuvable dans " .. process.cwd .. ")")
end

net.serve(PORT, function(request)
	local file = FILES[request.path]
	if request.method ~= "GET" or not file then
		return { status = 404, body = "GET /build_arena.luau, /build_city.luau ou /studio_export.luau uniquement" }
	end
	-- relu à chaque requête : la dernière version du fichier est toujours servie
	return { status = 200, body = fs.readFile(file) }
end)
print(
	string.format(
		"Scripts servis sur http://localhost:%d (build_arena.luau, build_city.luau, studio_export.luau)",
		PORT
	)
)
