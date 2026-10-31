-- receive.luau
-- Serveur local qui reçoit les .rbxm envoyés par tools/rbxm/studio_export.luau (exécuté dans Studio)
-- et les écrit sous assets/rbx/{ViewModels,Tools}/. Un export complet réussi supprime aussi les .rbxm
-- qui n'existent plus dans la place (arme renommée ou retirée). S'arrête tout seul à la fin de l'export.
-- Usage (racine du dépôt) : lune run tools/rbxm/receive.luau   (port fixe 34990, cf. studio_export.luau)

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local task = require("@lune/task")

local PORT = 34990
local FOLDERS = { "ViewModels", "Tools" }

if not fs.isFile("default.project.json") then
	error("à lancer depuis la racine du dépôt (default.project.json introuvable dans " .. process.cwd .. ")")
end

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

-- Cette méthode permet de valider un chemin cible lorsqu'il vient de la requête : il doit être
-- assets/rbx/ViewModels/<Nom>.rbxm ou assets/rbx/Tools/<Nom>.rbxm, sans remontée de dossier.
local function isSafePath(path: string): boolean
	local folder = string.match(path, "^assets/rbx/(%w+)/[%w_%-]+%.rbxm$")
	return folder ~= nil and table.find(FOLDERS, folder) ~= nil
end

-- Cette méthode permet de supprimer les .rbxm qui n'ont pas été reçus lorsqu'un export complet a réussi
-- (sinon une arme renommée ou retirée dans Studio serait recréée par Rojo depuis l'ancien fichier).
local function removeStale(received: { [string]: boolean })
	for _, folder in FOLDERS do
		local dir = "assets/rbx/" .. folder
		if fs.isDir(dir) then
			for _, file in fs.readDir(dir) do
				local path = dir .. "/" .. file
				if string.match(file, "%.rbxm$") and not received[path] then
					fs.removeFile(path)
					print("supprimé (absent de la place) : " .. path)
				end
			end
		end
	end
end

local received = {}
local count = 0
local finished = nil -- nil tant que l'export tourne, puis "ok" ou le message d'erreur de Studio

local handle = net.serve(PORT, function(request)
	if request.method ~= "POST" then
		return { status = 405, body = "POST uniquement" }
	end
	if request.path == "/done" then
		-- Studio envoie "OK" si tout est parti, sinon le message d'erreur (un corps vide n'arrive pas vide)
		finished = if request.body == "OK" then "ok" else request.body
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
		received[path] = true
		count += 1
		print(string.format("%s (%d octets)", path, #bytes))
	end)
	if not ok then
		warn(path .. " : " .. tostring(err))
		return { status = 500, body = tostring(err) }
	end
	return { status = 200, body = "ok" }
end)

print(string.format("En attente de Studio sur http://localhost:%d ...", PORT))
while finished == nil do
	task.wait(0.2)
end
-- laisse partir la réponse au /done avant de fermer le serveur
task.wait(1)
handle.stop()

if finished ~= "ok" then
	print(
		string.format("Export interrompu dans Studio (%d fichier(s) écrit(s), aucun supprimé) : %s", count, finished)
	)
	process.exit(1)
end
removeStale(received)
print(string.format("Export terminé : %d fichier(s) écrit(s).", count))
