--[[
	Serveur de commande du plugin Rojo modifie (CSGO autoconnect, voir tools/rojo-plugin/README.md).

	Sert sur http://localhost:34870 le contenu du fichier cible ecrit par scripts/csgo-worktree.ps1
	(worktrees/.run/studio.target, JSON { port, rev }). Le plugin l'interroge chaque seconde et se reconnecte
	quand `rev` change. Fichier absent : 404, le plugin ne fait rien. En retour, le plugin envoie l'etat de sa
	session (POST /status, JSON { rev, port, state }), ecrit dans worktrees/.run/studio.status.

	Usage : lune run tools/rojo-plugin/control-server.luau <fichier cible> <fichier etat>
	Lance et maintenu par scripts/csgo-worktree.ps1 (-AcquireStudio, -ReleaseStudio) : pas besoin de le lancer a la main.
]]

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")

local PORT = 34870
local targetFile = process.args[1]
local statusFile = process.args[2]
if not (targetFile and statusFile) then
	error("usage : lune run control-server.luau <fichier cible> <fichier etat>")
end

-- Cette methode permet de repondre a une requete du plugin lorsqu'il demande la cible courante (/target),
-- ou au script quand il verifie que le serveur tourne (/health).
local function handle(request)
	if request.path == "/health" then
		-- Version du protocole : csgo-worktree.ps1 redemarre un serveur qui en annonce une autre.
		return { status = 200, headers = { ["Content-Type"] = "text/plain" }, body = "csgo-control 2" }
	end
	if request.path == "/status" and request.method == "POST" then
		-- Etat reel de la session (rev, port, state) renvoye par le plugin : lu par csgo-worktree.ps1 -AcquireStudio.
		fs.writeFile(statusFile, request.body)
		return { status = 204, body = "" }
	end
	if request.path ~= "/target" then
		return { status = 404, body = "not found" }
	end
	if not fs.isFile(targetFile) then
		return { status = 404, body = "no target" }
	end
	local ok, content = pcall(fs.readFile, targetFile)
	if not ok then
		-- Ecriture en cours par le script : le plugin reessaiera a la seconde suivante.
		return { status = 503, body = "busy" }
	end
	return { status = 200, headers = { ["Content-Type"] = "application/json" }, body = content }
end

net.serve(PORT, { address = "http://127.0.0.1", handleRequest = handle })
print(`[rojo-control] http://localhost:{PORT}/target -> {targetFile}`)
