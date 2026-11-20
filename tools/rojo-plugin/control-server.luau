--[[
	Serveur de commande du plugin Rojo modifie (CSGO autoconnect, voir tools/rojo-plugin/README.md).

	Un seul serveur pour tous les projets du poste, sur http://localhost:34870, demarre par le premier script qui
	reserve Studio. Chaque projet s'inscrit dans le registre (<registre>/projects/<nom>.json :
	{ name, placeIds, mainPort, target, status }) ; le serveur y cherche, a chaque requete, le projet de la place demandee.

	- GET /target?placeId=<id> : contenu du fichier cible du projet de cette place (JSON { port, rev }). Le plugin
	  l'interroge chaque seconde et se reconnecte quand `rev` change. Place inconnue ou fichier absent : 404, le plugin
	  ne fait rien.
	- POST /status?placeId=<id> : etat de la session du plugin (JSON { rev, port, state }), ecrit dans le fichier
	  `status` du projet.
	- GET /projects : projets inscrits (diagnostic). GET /health : version du protocole.

	Usage : lune run control-server.luau <dossier du registre> [<port>]   (port 34870 par defaut, autre port : tests)
	Lance et maintenu par scripts/csgo-worktree.ps1 (-AcquireStudio, -ReleaseStudio) : pas besoin de le lancer a la main.
]]

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")

-- Version du protocole : un script qui en attend une autre arrete ce serveur et lance le sien.
local VERSION = "rojo-control 3"
local registryDir = process.args[1]
if not registryDir then
	error("usage : lune run control-server.luau <dossier du registre> [<port>]")
end
local PORT = tonumber(process.args[2]) or 34870
local projectsDir = `{registryDir}/projects`

-- Cette methode permet de lire les projets inscrits lorsqu'une requete arrive ; une inscription illisible (ecriture en
-- cours, JSON invalide) est ignoree jusqu'a la requete suivante.
local function readProjects(): { any }
	local projects = {}
	if not fs.isDir(projectsDir) then
		return projects
	end
	for _, name in fs.readDir(projectsDir) do
		if string.sub(name, -5) == ".json" then
			local ok, project = pcall(function()
				return serde.decode("json", fs.readFile(`{projectsDir}/{name}`))
			end)
			if ok and type(project) == "table" and type(project.placeIds) == "table" then
				table.insert(projects, project)
			end
		end
	end
	return projects
end

-- Cette methode permet de trouver le projet qui a declare la place demandee par le plugin ; nil si aucun.
local function projectOf(placeId: string?): any
	if not placeId or placeId == "" then
		return nil
	end
	for _, project in readProjects() do
		for _, id in project.placeIds do
			-- Id ecrit en texte (recommande) ou en nombre JSON : les deux sont acceptes.
			if tostring(id) == placeId or (type(id) == "number" and id == tonumber(placeId)) then
				return project
			end
		end
	end
	return nil
end

-- Cette methode permet de repondre a une requete du plugin (/target, /status) ou d'un script (/health, /projects).
local function handle(request)
	if request.path == "/health" then
		return { status = 200, headers = { ["Content-Type"] = "text/plain" }, body = VERSION }
	end
	if request.path == "/projects" then
		return {
			status = 200,
			headers = { ["Content-Type"] = "application/json" },
			body = serde.encode("json", readProjects()),
		}
	end
	if request.path ~= "/target" and request.path ~= "/status" then
		return { status = 404, body = "not found" }
	end
	local placeId = request.query and request.query.placeId
	if not placeId then
		return { status = 400, body = "placeId required" }
	end
	local project = projectOf(placeId)
	if not project then
		return { status = 404, body = "unknown place" }
	end

	if request.path == "/status" then
		if request.method ~= "POST" or type(project.status) ~= "string" then
			return { status = 404, body = "no status file" }
		end
		-- Etat reel de la session (rev, port, state) : lu par le script du projet apres une reservation.
		local ok = pcall(fs.writeFile, project.status, request.body)
		return { status = if ok then 204 else 503, body = "" }
	end

	if type(project.target) ~= "string" or not fs.isFile(project.target) then
		return { status = 404, body = "no target" }
	end
	local ok, content = pcall(fs.readFile, project.target)
	if not ok then
		-- Ecriture en cours par le script : le plugin reessaiera a la seconde suivante.
		return { status = 503, body = "busy" }
	end
	return { status = 200, headers = { ["Content-Type"] = "application/json" }, body = content }
end

net.serve(PORT, { address = "http://127.0.0.1", handleRequest = handle })
print(`[rojo-control] {VERSION} : http://localhost:{PORT}/target?placeId=<id>, registre {projectsDir}`)
