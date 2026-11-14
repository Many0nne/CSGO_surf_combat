-- État « débutant » du joueur local (#291) : relu dans l'attribut informatif `PlayerStats` (StatsStore, #296, celui de la
-- fiche de l'accueil) et, en Studio seulement, dans l'attribut de debug BeginnerRules.DEBUG_ATTRIBUTE ; décision par
-- BeginnerRules.isBeginner (statistiques absentes : pas débutant). Lu par KeyDisplay (touches en mode complet) et
-- GameStateController (conseil de l'écran de mort), prévenus à chaque changement (fin de la 3e manche, attribut posé).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StatsRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StatsRules"))
local BeginnerRules = require(script.Parent.BeginnerRules)

local BeginnerState = {}

local beginner = false
local started = false
local listeners: { (boolean) -> () } = {}

-- Cette méthode permet de relire l'état débutant lorsque les statistiques ou l'attribut de debug changent, et de prévenir
-- les abonnés s'il a changé.
local function refresh()
	local player = Players.LocalPlayer
	local stats = StatsRules.decode(player:GetAttribute(StatsRules.ATTRIBUTE))
	local debug = if RunService:IsStudio() then player:GetAttribute(BeginnerRules.DEBUG_ATTRIBUTE) else nil
	local value = BeginnerRules.isBeginner(stats, debug)
	if value == beginner then
		return
	end
	beginner = value
	for _, callback in listeners do
		task.spawn(callback, value)
	end
end

-- Cette méthode permet de suivre les attributs du joueur local lorsque le premier module lit l'état (idempotent).
local function start()
	if started then
		return
	end
	started = true
	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal(StatsRules.ATTRIBUTE):Connect(refresh)
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal(BeginnerRules.DEBUG_ATTRIBUTE):Connect(refresh)
	end
	refresh()
end

-- Cette méthode permet de savoir si le joueur local est débutant lorsqu'un module décide d'une aide.
function BeginnerState.isBeginner(): boolean
	start()
	return beginner
end

-- Cette méthode permet de s'abonner aux changements de l'état débutant lorsqu'un module affiche une aide.
function BeginnerState.onChanged(callback: (boolean) -> ())
	start()
	table.insert(listeners, callback)
end

return BeginnerState
