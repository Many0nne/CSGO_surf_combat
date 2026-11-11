local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")

local CheatLog = require(ServerScriptService.Server.CheatLog)
local NetworkProtocol = require(ReplicatedStorage.Shared.NetworkProtocol)
local RemoteGuard = require(ServerScriptService.Server.RemoteGuard)
local Webhook = require(ServerScriptService.Server.Webhook)

local FeedbackService = {}

local COOLDOWN = 60 -- secondes entre deux demandes valides (posé avant le DataStore), quel qu'en soit le résultat (#171)
local WEEKLY_LIMIT = 5 -- feedbacks max sur 7 jours glissants
local WEEK_SECS = 7 * 24 * 3600
local MIN_LEN = 10
local MAX_LEN = 500

local rateStore = DataStoreService:GetDataStore("FeedbackRateV1")

-- Heure (os.time) de la dernière demande de chaque joueur qui a passé la limite en mémoire : posée avant tout accès
-- DataStore, pour qu'un spam (sans webhook, quota atteint, DataStore en panne) ne coûte qu'un accès par COOLDOWN.
local lastAttempt: { [number]: number } = {}

-- Cette méthode permet de mettre en forme un feedback pour le webhook lorsqu'il va être envoyé.
local function buildEmbed(player: Player, text: string): { [string]: any }
	return {
		title = "Feedback joueur",
		description = text,
		color = 3626380,
		footer = { text = player.Name .. "  |  UserId " .. player.UserId },
	}
end

-- Cette méthode permet de décider du quota hebdomadaire lorsque la valeur stockée est lue : "overLimit" à la limite,
-- sinon "ok" et la liste à écrire (envois des 7 derniers jours, valeurs forgées ignorées, plus now).
function FeedbackService.weeklyQuota(data: unknown, now: number): ("ok" | "overLimit", { number }?)
	local cutoff = now - WEEK_SECS
	local recent: { number } = {}
	if type(data) == "table" then
		for _, t in data :: { any } do
			if type(t) == "number" and t > cutoff then
				table.insert(recent, t)
			end
		end
	end
	if #recent >= WEEKLY_LIMIT then
		return "overLimit", nil
	end
	table.insert(recent, now)
	return "ok", recent
end

-- Cette méthode permet de compter un envoi dans le quota hebdomadaire lorsqu'il va être posté, en un seul UpdateAsync
-- atomique : lecture échouée = "failed" sans rien écrire (une liste vide écraserait le quota), limite = pas d'écriture.
local function consumeWeeklyQuota(userId: number, now: number): "ok" | "overLimit" | "failed"
	local verdict: "ok" | "overLimit" = "overLimit"
	local ok, err = pcall(function()
		rateStore:UpdateAsync("uid_" .. userId, function(data)
			local updated
			verdict, updated = FeedbackService.weeklyQuota(data, now)
			-- nil : écriture annulée
			return updated
		end)
	end)
	if not ok then
		warn("[FeedbackService] quota hebdomadaire illisible ou non écrit :", err)
		return "failed"
	end
	return verdict
end

-- Cette méthode permet de rendre au joueur l'envoi compté lorsque le webhook a échoué (au mieux : une erreur
-- DataStore laisse l'envoi compté, sans autre effet).
local function refundWeeklyQuota(userId: number, now: number)
	pcall(function()
		rateStore:UpdateAsync("uid_" .. userId, function(data)
			if type(data) ~= "table" then
				return nil
			end
			local index = table.find(data, now)
			if not index then
				return nil
			end
			table.remove(data, index)
			return data
		end)
	end)
end

function FeedbackService.init(sendFeedbackRmt: RemoteEvent, feedbackAckRmt: RemoteEvent)
	sendFeedbackRmt.OnServerEvent:Connect(function(player: Player, text: unknown)
		-- Garde commune (#170) : débit et type, avant tout accès DataStore
		if not CheatLog.admit(player, NetworkProtocol.Names.SEND_FEEDBACK, text) or type(text) ~= "string" then
			-- Texte refusé pour débit : l'écran attend un accusé pour permettre un nouvel envoi (rien pour un type forgé
			-- ni pour un joueur parti)
			if type(text) == "string" and #text <= RemoteGuard.FEEDBACK_MAX_BYTES and player.Parent then
				feedbackAckRmt:FireClient(player, false, "Trop d'envois, réessaie dans quelques secondes.")
			end
			return
		end

		local trimmed = text:match("^%s*(.-)%s*$")
		if #trimmed < MIN_LEN or #trimmed > MAX_LEN then
			feedbackAckRmt:FireClient(
				player,
				false,
				"Message entre " .. MIN_LEN .. " et " .. MAX_LEN .. " caractères."
			)
			return
		end

		-- Limite en mémoire (#171), posée avant tout accès DataStore et quel que soit le résultat de la demande
		local now = os.time()
		local last = lastAttempt[player.UserId]
		if last and (now - last) < COOLDOWN then
			local remaining = COOLDOWN - (now - last)
			feedbackAckRmt:FireClient(player, false, "Réessaie dans " .. remaining .. "s.")
			return
		end
		lastAttempt[player.UserId] = now

		-- Pas de webhook : rien à envoyer, ni quota à consommer
		local webhookUrl = Webhook.url("FeedbackWebhookUrl")
		if not webhookUrl then
			feedbackAckRmt:FireClient(player, false, "Système indisponible.")
			return
		end

		-- Vérification + mise à jour du quota hebdomadaire
		local quota = consumeWeeklyQuota(player.UserId, now)
		if quota == "overLimit" then
			feedbackAckRmt:FireClient(player, false, "Limite de " .. WEEKLY_LIMIT .. " feedbacks par semaine atteinte.")
			return
		elseif quota == "failed" then
			feedbackAckRmt:FireClient(player, false, "Système indisponible, réessaie plus tard.")
			return
		end

		local postOk, err = Webhook.post(webhookUrl, buildEmbed(player, trimmed))

		if postOk then
			feedbackAckRmt:FireClient(player, true, "Merci pour ton feedback !")
		else
			warn("[FeedbackService] PostAsync failed:", err)
			refundWeeklyQuota(player.UserId, now)
			feedbackAckRmt:FireClient(player, false, "Erreur lors de l'envoi.")
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		-- Délai encore en cours : gardé jusqu'à son terme, pour qu'une reconnexion rapide ne le remette pas à zéro
		local userId = player.UserId
		local last = lastAttempt[userId]
		if not last then
			return
		end
		task.delay(math.max(COOLDOWN - (os.time() - last), 0), function()
			if lastAttempt[userId] == last and not Players:GetPlayerByUserId(userId) then
				lastAttempt[userId] = nil
			end
		end)
	end)
end

return FeedbackService
