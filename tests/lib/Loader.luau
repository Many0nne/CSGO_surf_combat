-- Charge les modules de src/ sous Lune en simulant l'arborescence Rojo (game:GetService + require d'Instance).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

-- Racines Rojo : service -> enfant -> dossier source (cf. default.project.json)
local ROOTS = {
	ReplicatedStorage = { Shared = "src/shared" },
	ServerScriptService = { Server = "src/server" },
	StarterPlayer = { StarterPlayerScripts = { Client = "src/client" } },
}

local Loader = {}
Loader.__index = Loader

-- Cette méthode permet de représenter un chemin de fichier comme une pseudo-Instance indexable lorsque
-- un module fait `ReplicatedStorage.Shared.X` ; `require` résout ensuite le nœud vers X.luau ou X/init.luau.
local function pathNode(path: string)
	return setmetatable({ __path = path }, {
		__index = function(_, name)
			-- `X:WaitForChild("Y")` se résout comme `X.Y` : les modules sont là dès le chargement
			if name == "WaitForChild" then
				return function(_, child: string)
					return pathNode(path .. "/" .. child)
				end
			end
			return pathNode(path .. "/" .. name)
		end,
	})
end

-- Cette méthode permet de convertir une table de racines en pseudo-Instances lorsque le service est demandé.
local function rootNode(spec)
	if type(spec) == "string" then
		return pathNode(spec)
	end
	local node = {}
	for name, child in spec do
		node[name] = rootNode(child)
	end
	function node.WaitForChild(_, name: string)
		return node[name]
	end
	return node
end

-- Cette méthode permet de créer un contexte de chargement isolé lorsqu'un test démarre ;
-- `services` remplace des services Roblox par des mocks (ex. Players), `globals` ajoute des globales Roblox simulées
-- (ex. un faux `task` dont le test déclenche lui-même les délais).
function Loader.new(services: { [string]: any }?, globals: { [string]: any }?)
	local self = setmetatable({ cache = {}, services = services or {}, globals = globals or {} }, Loader)
	self.game = {
		GetService = function(_, name: string)
			if self.services[name] then
				return self.services[name]
			end
			if ROOTS[name] then
				return rootNode(ROOTS[name])
			end
			error("Service non simulé dans les tests : " .. name, 2)
		end,
	}
	return self
end

-- Cette méthode permet de trouver le fichier source d'un nœud lorsque require reçoit une pseudo-Instance.
local function resolveFile(path: string): string
	for _, candidate in { path .. ".luau", path .. "/init.luau" } do
		if fs.isFile(candidate) then
			return candidate
		end
	end
	error("Module introuvable : " .. path, 3)
end

-- Cette méthode permet d'exécuter un module de src/ avec un environnement Roblox simulé lorsqu'il est requis ;
-- le résultat est mis en cache par contexte, comme le require de Roblox.
function Loader:require(target: any)
	if type(target) == "string" then
		target = pathNode(target)
	end
	local file = resolveFile(target.__path)
	if self.cache[file] == nil then
		local env = {
			game = self.game,
			require = function(t)
				return self:require(t)
			end,
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
			Instance = roblox.Instance,
			Color3 = roblox.Color3,
			Enum = roblox.Enum,
		}
		for name, value in self.globals do
			env[name] = value
		end
		local chunk = luau.load(fs.readFile(file), { debugName = file, environment = env })
		self.cache[file] = chunk()
	end
	return self.cache[file]
end

return Loader
