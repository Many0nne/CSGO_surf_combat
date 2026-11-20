-- Rotation des maps entre les rounds (#594) : une map par round, dans l'ordre de GameConfig.MAP_ROTATION. Au démarrage,
-- seule la première reste dans Workspace.Maps (MapSelection.setup) ; la suivante est publiée dans l'attribut NextMap
-- (annoncée par le bandeau de fin) et l'échange se fait après le bandeau et le clip de la partie (rejoué dans la map de
-- la manche), juste avant le retour à idle qui autorise les apparitions.
-- Plans de navigation des bots : celui de la map jouée d'abord, puis ceux des autres maps, chacune prêtée à
-- Workspace.Maps le temps de sa construction (les rayons ne touchent que le Workspace), pour un échange sans attente.
-- Studio : l'attribut DebugMap de Workspace force une map (tout de suite hors round, sinon au round suivant).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MapSelection = require(ReplicatedStorage.Shared.MapSelection)
local NavPlan = require(ServerScriptService.Server.bots.NavPlan)

local MapRotation = {}

local maps: Instance? = nil
-- Maps prêtées à Workspace.Maps pour la construction de leur plan : l'échange ne les range pas pendant ce temps
local lent: { [string]: boolean } = {}
-- Le round est-il terminé (idle) ? Branché par init : DebugMap change la map tout de suite seulement hors round
local isIdle: () -> boolean = function()
	return false
end

-- Cette méthode permet de lire la map forcée dans Studio lorsque la rotation choisit la suivante (attribut DebugMap).
local function forced(): string?
	return MapSelection.forced(RunService:IsStudio(), workspace:GetAttribute(MapSelection.DEBUG_ATTRIBUTE))
end

-- Cette méthode permet de publier la map du round suivant (attribut NextMap) lorsque la map jouée change ou que
-- DebugMap est posé ou retiré.
local function publishNext()
	if not maps then
		return
	end
	local nextName =
		MapSelection.nextInRotation(GameConfig.MAP_ROTATION, MapSelection.names(), MapSelection.currentName(), forced())
	maps:SetAttribute(MapSelection.NEXT_ATTRIBUTE, nextName)
end

-- Cette méthode permet de passer à une map lorsque le round se termine ou que DebugMap la force hors round : échange
-- des maps (temps mesuré, sortie [MapRotation]), puis map suivante publiée.
local function switchTo(name: string)
	if not maps or name == MapSelection.currentName() then
		publishNext()
		return
	end
	local started = os.clock()
	MapSelection.switch(maps, name, lent)
	NavPlan.setActive(name)
	print(string.format("[MapRotation] map jouée : %s (échange %.0f ms)", name, (os.clock() - started) * 1000))
	publishNext()
end

-- Cette méthode permet de construire en tâche de fond les plans de navigation de toutes les maps lorsque le serveur
-- démarre : la map jouée d'abord, puis chaque autre map prêtée à Workspace.Maps le temps de sa construction.
local function buildPlans()
	local active = MapSelection.current()
	if active then
		NavPlan.build(active)
	end
	for _, name in GameConfig.MAP_ROTATION do
		local map = MapSelection.find(name)
		if map and maps and not NavPlan.isDone(name) then
			lent[name] = true
			map.Parent = maps
			NavPlan.build(map)
			lent[name] = nil
			-- Rangée de nouveau, sauf si elle est devenue la map jouée pendant la construction
			if MapSelection.currentName() ~= name then
				map.Parent = MapSelection.store(true)
			end
		end
	end
end

-- Cette méthode permet de démarrer la rotation lorsque le serveur démarre, avant les premières apparitions : map
-- d'ouverture (DebugMap dans Studio, sinon la première de la rotation), maps suivantes rangées, plans construits.
function MapRotation.init(deps: { isIdle: () -> boolean })
	isIdle = deps.isIdle
	maps = workspace:FindFirstChild("Maps")
	local first = MapSelection.setup(maps, forced() or GameConfig.MAP_ROTATION[1])
	if first then
		NavPlan.setActive(first.Name)
	end
	publishNext()
	task.spawn(buildPlans)
	-- Map forcée dans Studio : tout de suite si aucun round n'est en cours, sinon annoncée pour le round suivant
	workspace:GetAttributeChangedSignal(MapSelection.DEBUG_ATTRIBUTE):Connect(function()
		local name = forced()
		if name and isIdle() then
			switchTo(name)
		else
			publishNext()
		end
	end)
end

-- Cette méthode permet de passer à la map suivante lorsque le résultat de la manche est fini (bandeau, puis clip de la
-- partie rejoué dans l'ancienne map), juste avant le retour à idle : les apparitions suivantes se font sur la nouvelle.
function MapRotation.onRoundEnded()
	local nextName = MapSelection.nextName()
	if nextName then
		switchTo(nextName)
	end
end

return MapRotation
