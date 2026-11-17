-- Écran courant du joueur signalé au serveur pour les analytics (#527, server/analytics/Analytics) : relevé toutes les
-- AnalyticsRules.POLL_INTERVAL s auprès de l'orchestrateur (init.client), envoyé seulement quand il change (remote
-- AnalyticsScreen, valeurs de AnalyticsRules.SCREENS). Le client ne fait que décrire où il est : funnels, temps passés
-- et événements sont décidés par le serveur. Un relevé plus court que la période peut ne pas être vu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnalyticsRules = require(Shared:WaitForChild("AnalyticsRules"))
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))

-- Attente (s) au plus du remote créé par le serveur
local REMOTE_WAIT = 30

local AnalyticsClient = {}

-- Cette méthode permet de démarrer le relevé de l'écran lorsque le client a tout initialisé ; `current` renvoie l'écran
-- courant (nil : rien à signaler). Une erreur du relevé est ignorée (relevé suivant).
function AnalyticsClient.init(current: () -> string?)
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild(NetworkProtocol.Names.ANALYTICS_SCREEN, REMOTE_WAIT)
		if not (remote and remote:IsA("RemoteEvent")) then
			return
		end
		local last: string? = nil
		while true do
			local ok, screen = pcall(current)
			if ok and type(screen) == "string" and screen ~= last then
				last = screen
				remote:FireServer(screen)
			end
			task.wait(AnalyticsRules.POLL_INTERVAL)
		end
	end)
end

return AnalyticsClient
