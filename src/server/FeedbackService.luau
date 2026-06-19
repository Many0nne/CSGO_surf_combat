local HttpService         = game:GetService("HttpService")
local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService    = game:GetService("DataStoreService")

local FeedbackService = {}

local COOLDOWN     = 60       -- secondes entre deux envois (anti-spam immédiat)
local WEEKLY_LIMIT = 5        -- feedbacks max sur 7 jours glissants
local WEEK_SECS    = 7 * 24 * 3600
local MIN_LEN      = 10
local MAX_LEN      = 500

local rateStore = DataStoreService:GetDataStore("FeedbackRateV1")

local lastSent: {[number]: number} = {}

local function getWebhookUrl(): string?
	local v = ServerScriptService:FindFirstChild("FeedbackWebhookUrl")
	if v and v:IsA("StringValue") and v.Value ~= "" then
		return v.Value
	end
	return nil
end

local function buildPayload(player: Player, text: string): string
	local embed = {
		title       = "Feedback joueur",
		description = text,
		color       = 3626380,
		footer      = { text = player.Name .. "  |  UserId " .. player.UserId },
		timestamp   = os.date("!%Y-%m-%dT%H:%M:%S.000Z"),
	}
	return HttpService:JSONEncode({ embeds = { embed } })
end

-- Charge les timestamps de la semaine écoulée, ajoute now si fourni, sauvegarde.
-- Retourne (timestamps_filtrés, dépassé_limite)
local function updateRateStore(userId: number, now: number?): ({number}, boolean)
	local key = "uid_" .. userId
	local ok, data = pcall(function()
		return rateStore:GetAsync(key)
	end)

	local timestamps: {number} = {}
	if ok and type(data) == "table" then
		timestamps = data
	end

	-- Garder uniquement les 7 derniers jours
	local cutoff  = (now or os.time()) - WEEK_SECS
	local filtered: {number} = {}
	for _, t in timestamps do
		if t > cutoff then
			table.insert(filtered, t)
		end
	end

	if now == nil then
		return filtered, #filtered >= WEEKLY_LIMIT
	end

	if #filtered >= WEEKLY_LIMIT then
		return filtered, true
	end

	table.insert(filtered, now)
	pcall(function()
		rateStore:SetAsync(key, filtered)
	end)
	return filtered, false
end

function FeedbackService.init(sendFeedbackRmt: RemoteEvent, feedbackAckRmt: RemoteEvent)
	sendFeedbackRmt.OnServerEvent:Connect(function(player: Player, text: unknown)
		if type(text) ~= "string" then return end

		local trimmed = text:match("^%s*(.-)%s*$")
		if #trimmed < MIN_LEN or #trimmed > MAX_LEN then
			feedbackAckRmt:FireClient(player, false,
				"Message entre " .. MIN_LEN .. " et " .. MAX_LEN .. " caractères.")
			return
		end

		-- Anti-spam immédiat (en mémoire, pas de DataStore)
		local now  = os.time()
		local last = lastSent[player.UserId]
		if last and (now - last) < COOLDOWN then
			local remaining = COOLDOWN - (now - last)
			feedbackAckRmt:FireClient(player, false,
				"Réessaie dans " .. remaining .. "s.")
			return
		end

		-- Vérification + mise à jour du quota hebdomadaire
		local _, overLimit = updateRateStore(player.UserId, now)
		if overLimit then
			feedbackAckRmt:FireClient(player, false,
				"Limite de " .. WEEKLY_LIMIT .. " feedbacks par semaine atteinte.")
			return
		end

		local webhookUrl = getWebhookUrl()
		if not webhookUrl then
			feedbackAckRmt:FireClient(player, false, "Système indisponible.")
			return
		end

		local postOk, err = pcall(function()
			HttpService:PostAsync(webhookUrl, buildPayload(player, trimmed),
				Enum.HttpContentType.ApplicationJson)
		end)

		if postOk then
			lastSent[player.UserId] = now
			feedbackAckRmt:FireClient(player, true, "Merci pour ton feedback !")
		else
			warn("[FeedbackService] PostAsync failed:", err)
			feedbackAckRmt:FireClient(player, false, "Erreur lors de l'envoi.")
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		lastSent[player.UserId] = nil
	end)
end

return FeedbackService
