-- receive.luau
-- Serveur local qui reçoit les .rbxm envoyés par tools/rbxm/studio_export.luau (exécuté dans Studio)
-- et les écrit sous assets/rbx/. S'arrête tout seul à la fin de l'export.
-- Usage (depuis la racine du dépôt) : lune run tools/rbxm/receive.luau [port]   (port par défaut : 34990)

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local task = require("@lune/task")

local PORT = tonumber(process.args[1]) or 34990
local ROOT = "assets/rbx/"

-- Cette méthode permet de décoder une chaîne hexadécimale en octets lorsque Studio envoie un .rbxm
-- (le corps HTTP reste ainsi en ASCII, sans risque de réencodage UTF-8 des octets binaires).
local function fromHex(hex: string): string
	assert(#hex % 2 == 0, "hex de longueur impaire")
	local out = table.create(#hex // 2)
	for i = 1, #hex, 2 do
		local byte = tonumber(string.sub(hex, i, i + 1), 16)
		assert(byte, "caractère non hexadécimal à la position " .. i)
		table.insert(out, string.char(byte))
	end
	return table.concat(out)
end

-- Cette méthode permet de valider un chemin cible lorsqu'il vient de la requête : il doit rester sous
-- assets/rbx/<Dossier>/<Nom>.rbxm, sans remontée de dossier.
local function isSafePath(path: string): boolean
	return string.match(path, "^assets/rbx/[%w_]+/[%w_%-]+%.rbxm$") ~= nil
end

local written = {}
local done = false

local handle = net.serve(PORT, function(request)
	if request.method ~= "POST" then
		return { status = 405, body = "POST uniquement" }
	end
	if request.path == "/done" then
		done = true
		return { status = 200, body = "ok" }
	end
	local path = request.query.path
	if type(path) ~= "string" or not isSafePath(path) then
		return { status = 400, body = "chemin refusé : " .. tostring(path) }
	end
	local ok, err = pcall(function()
		local bytes = fromHex(request.body)
		assert(string.sub(bytes, 1, 8) == "<roblox!", "pas un modèle Roblox binaire")
		local dir = string.match(path, "^(.*)/[^/]+$")
		if not fs.isDir(dir) then
			fs.writeDir(dir)
		end
		fs.writeFile(path, bytes)
		table.insert(written, path)
		print(string.format("%s (%d octets)", path, #bytes))
	end)
	if not ok then
		warn(path .. " : " .. tostring(err))
		return { status = 500, body = tostring(err) }
	end
	return { status = 200, body = "ok" }
end)

print(string.format("En attente de Studio sur http://localhost:%d (racine %s)...", PORT, ROOT))
while not done do
	task.wait(0.2)
end
handle.stop()
print(string.format("Export terminé : %d fichier(s) écrit(s).", #written))
