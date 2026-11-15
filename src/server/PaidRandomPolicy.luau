-- Objets aléatoires payants (#395) : un joueur est-il restreint (`PolicyService:GetPolicyInfoForPlayerAsync`, champ
-- `ArePaidRandomItemsRestricted`) ? Les caisses du shop en sont : elles se paient en crédits, achetables en Robux. Règles
-- et choix (caisses bloquées, packs masqués) : docs/economie.md.
--
-- Réponse mise en cache par joueur, demandée à son arrivée. Appel en échec ou réponse illisible = **restreint** ; un
-- échec est redemandé au plus toutes les RETRY_AFTER s (panne passagère), une réponse lue est gardée pour la session.
-- L'attribut informatif `PaidRandomRestricted` du Player (CreditPacks.RESTRICTED_ATTRIBUTE) en est la copie pour le
-- client, jamais relu par le serveur. Studio seulement : attribut Player `DebugPaidRandomRestricted` (true/false, en
-- contexte serveur) remplace la réponse de PolicyService, pour voir les deux cas.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CreditPacks = require(ReplicatedStorage.Shared.CreditPacks)

local DEBUG_ATTRIBUTE = "DebugPaidRandomRestricted"
local RETRY_AFTER = 30 -- s avant de redemander une réponse en échec

type Entry = { restricted: boolean, known: boolean, at: number }

local cache: { [Player]: Entry } = {}

local PaidRandomPolicy = {}

-- Cette méthode permet de lire la restriction dans la réponse de PolicyService lorsqu'elle arrive : seule une réponse
-- lue qui dit `false` ouvre les objets aléatoires payants ; échec ou champ absent = restreint.
function PaidRandomPolicy.fromResponse(ok: boolean, info: any): (boolean, boolean)
	if ok and type(info) == "table" and type(info.ArePaidRandomItemsRestricted) == "boolean" then
		return info.ArePaidRandomItemsRestricted, true
	end
	return true, false
end

-- Cette méthode permet de publier la restriction connue d'un joueur pour le client lorsqu'elle change.
local function publish(player: Player, restricted: boolean)
	if player.Parent then
		player:SetAttribute(CreditPacks.RESTRICTED_ATTRIBUTE, restricted)
	end
end

-- Cette méthode permet de lire la valeur de debug de Studio lorsqu'elle est posée ; nil sinon (et hors Studio).
local function debugValue(player: Player): boolean?
	if not RunService:IsStudio() then
		return nil
	end
	local value = player:GetAttribute(DEBUG_ATTRIBUTE)
	return if type(value) == "boolean" then value else nil
end

-- Cette méthode permet de savoir si un joueur est restreint lorsqu'un achat de caisse, un prompt de pack ou un reçu le
-- demande ; bloquante au premier appel (PolicyService), puis lue dans le cache.
function PaidRandomPolicy.isRestricted(player: Player): boolean
	local forced = debugValue(player)
	if forced ~= nil then
		publish(player, forced)
		return forced
	end
	local entry = cache[player]
	if entry and (entry.known or os.clock() - entry.at < RETRY_AFTER) then
		return entry.restricted
	end
	local ok, info = pcall(function()
		return game:GetService("PolicyService"):GetPolicyInfoForPlayerAsync(player)
	end)
	local restricted, known = PaidRandomPolicy.fromResponse(ok, info)
	if not known then
		warn(
			"[PaidRandomPolicy] réponse de PolicyService illisible pour",
			player.Name,
			"— traité comme restreint :",
			info
		)
	end
	if player.Parent then
		cache[player] = { restricted = restricted, known = known, at = os.clock() }
	end
	publish(player, restricted)
	return restricted
end

-- Cette méthode permet de demander la restriction des joueurs à leur arrivée et d'oublier ceux qui partent lorsque le
-- serveur démarre ; Studio : la valeur de debug est republiée à chaque changement.
function PaidRandomPolicy.init()
	local function onPlayer(player: Player)
		task.spawn(PaidRandomPolicy.isRestricted, player)
		if RunService:IsStudio() then
			player:GetAttributeChangedSignal(DEBUG_ATTRIBUTE):Connect(function()
				cache[player] = nil
				PaidRandomPolicy.isRestricted(player)
			end)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		cache[player] = nil
	end)
end

return PaidRandomPolicy
