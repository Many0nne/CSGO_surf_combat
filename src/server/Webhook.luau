-- Envoi d'un message à un webhook (Discord) depuis le serveur, partagé par FeedbackService et CheatLog (#170).
-- L'URL n'est jamais versionnée : c'est un StringValue posé à la main dans ServerScriptService de la place publiée
-- (ex. FeedbackWebhookUrl). HttpService.HttpEnabled doit être activé dans les réglages du jeu.
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local Webhook = {}

-- Cette méthode permet de lire l'URL d'un webhook lorsqu'un envoi se prépare : premier StringValue non vide parmi les
-- noms donnés (dans l'ordre), nil si aucun n'est configuré.
function Webhook.url(...: string): string?
	for _, name in { ... } do
		local v = ServerScriptService:FindFirstChild(name)
		if v and v:IsA("StringValue") and v.Value ~= "" then
			return v.Value
		end
	end
	return nil
end

-- Cette méthode permet de poster un embed (titre, description, couleur, pied, champs) lorsqu'un module a un message
-- à transmettre ; horodaté à l'envoi. Bloquant (requête HTTP) : renvoie la réussite et l'erreur éventuelle.
function Webhook.post(url: string, embed: { [string]: any }): (boolean, any)
	-- Copie : l'embed de l'appelant n'est pas modifié
	embed = table.clone(embed)
	embed.timestamp = embed.timestamp or os.date("!%Y-%m-%dT%H:%M:%S.000Z")
	return pcall(function()
		-- Aucune mention : le texte peut venir d'un joueur. Encodage dans le pcall : il échoue sur un texte non UTF-8
		local body = HttpService:JSONEncode({ embeds = { embed }, allowed_mentions = { parse = {} } })
		HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
	end)
end

-- Cette méthode permet de savoir si un envoi en échec vaut un nouvel essai lorsque PostAsync a levé une erreur : oui,
-- sauf une réponse HTTP 4xx autre que 429 (message refusé tel quel : le renvoyer échouerait pareil).
function Webhook.isRetryable(err: any): boolean
	local code = tonumber(string.match(tostring(err), "HTTP (%d%d%d)"))
	return not (code and code >= 400 and code < 500 and code ~= 429)
end

-- Cette méthode permet de poster un embed en réessayant lorsqu'un envoi échoue (réseau, limite de débit du webhook) :
-- jusqu'à `attempts` essais, attente de delay × n° d'essai entre deux, arrêt sur une erreur définitive (isRetryable).
-- Bloquant : renvoie la réussite, la dernière erreur et le nombre d'essais faits.
function Webhook.postWithRetry(
	url: string,
	embed: { [string]: any },
	attempts: number,
	delay: number
): (boolean, any, number)
	local total = math.max(1, attempts)
	local err = nil
	for attempt = 1, total do
		local ok, attemptErr = Webhook.post(url, embed)
		if ok then
			return true, nil, attempt
		end
		err = attemptErr
		if not Webhook.isRetryable(attemptErr) then
			return false, err, attempt
		end
		if attempt < total then
			task.wait(delay * attempt)
		end
	end
	return false, err, total
end

return Webhook
