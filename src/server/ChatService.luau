-- Chat côté serveur (#541, docs/moderation.md). Le moteur reste TextChatService : filtrage, restrictions de compte,
-- signalement et sourdine natifs de Roblox ne sont pas recodés. Ce module ajoute :
-- - la limite de débit et de longueur (ChatRules) dans le ShouldDeliverCallback de chaque canal ; refus non journalisés ;
-- - la sourdine du serveur en cours (/mute, /unmute) et l'expulsion (/kick), réservées au rôle Admin (Roles), reçues
--   par le remote ChatCommand ; un texte qui ressemble à une commande n'est jamais diffusé comme message ;
-- - le journal par lots (ChatLogRules) vers un webhook Discord : StringValue `ChatLogWebhookUrl` de ServerScriptService,
--   jamais versionné. Sans URL : rien n'est envoyé ni filtré (dans Studio, le lot s'écrit dans la sortie).
-- Piège : dans ShouldDeliverCallback, `message.Text` est le texte BRUT (filtré ensuite, par destinataire). Le journal
-- n'en garde jamais que la version filtrée pour tous (TextService, GetNonChatStringForBroadcastAsync).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local ChatRules = require(ReplicatedStorage.Shared.ChatRules)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NetworkProtocol = require(ReplicatedStorage.Shared.NetworkProtocol)
local ChatLogRules = require(ServerScriptService.Server.ChatLogRules)
local CheatLog = require(ServerScriptService.Server.CheatLog)
local Roles = require(ServerScriptService.Server.Roles)
local Webhook = require(ServerScriptService.Server.Webhook)

local ChatService = {}

-- StringValue de ServerScriptService lu pour l'URL du journal
ChatService.WEBHOOK_NAMES = { "ChatLogWebhookUrl" }
-- Attribut de debug (Studio seulement, posé côté serveur) : donne les commandes admin à un joueur de test
ChatService.DEBUG_ADMIN_ATTRIBUTE = "DebugChatAdmin"
-- Texte journalisé quand le filtrage échoue (jamais le texte brut)
ChatService.UNFILTERED_PLACEHOLDER = "[texte non filtré : filtrage indisponible]"

local WEBHOOK_ATTEMPTS = 3
local WEBHOOK_RETRY_DELAY = 2
-- Pause entre deux envois d'un même passage (lot plus long qu'un embed), sous la limite de débit de Discord
local SPLIT_DELAY = 2
-- Décision gardée par message (s) : ShouldDeliverCallback est appelé une fois par destinataire
local DECISION_TTL = 30
-- Attente au plus (s) d'un envoi périodique en cours avant le dernier envoi à l'arrêt (BindToClose : 30 s en tout)
local CLOSE_WAIT = 12

local buckets: { [number]: ChatRules.Bucket } = {}
local muted: { [number]: boolean } = {}
local decisions: { [string]: boolean } = {}
local batch = ChatLogRules.newBatch()
local noticeRemote: RemoteEvent? = nil
local flushing = false

-- Cette méthode permet de savoir si le journal doit être tenu lorsqu'un message ou une commande arrive : webhook
-- configuré, ou Studio (lot écrit dans la sortie pour vérifier).
local function logging(): boolean
	return Webhook.url(table.unpack(ChatService.WEBHOOK_NAMES)) ~= nil or RunService:IsStudio()
end

-- Cette méthode permet de filtrer un texte pour tous les joueurs lorsqu'il va au journal ou dans un message
-- d'expulsion ; nil si le filtrage échoue (jamais le texte brut à la place).
local function filterForAll(text: string, fromUserId: number): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		warn("[ChatService] filtrage impossible :", result)
		return nil
	end
	return result
end

-- Cette méthode permet de journaliser un message accepté lorsqu'il vient d'être délivré : entrée posée tout de suite
-- (ordre et heure d'envoi), texte filtré pour tous écrit ensuite. Bloquant (filtrage) : lancé dans sa propre tâche.
local function logMessage(userId: number, name: string, raw: string)
	if not logging() then
		return
	end
	local entry: ChatLogRules.Entry =
		{ at = os.time(), kind = "message", userId = userId, name = name, text = nil, pending = true }
	ChatLogRules.push(batch, entry)
	entry.text = filterForAll(raw, userId) or ChatService.UNFILTERED_PLACEHOLDER
	entry.pending = nil
end

-- Cette méthode permet de décider si un message est diffusé lorsque TextChatService le présente à un destinataire :
-- décision prise au premier appel (sourdine, longueur, débit) puis gardée, message accepté journalisé une fois.
function ChatService.decide(message: TextChatMessage): boolean
	local id = message.MessageId
	local known = decisions[id]
	if known ~= nil then
		return known
	end
	local source = message.TextSource
	local sender = source and Players:GetPlayerByUserId(source.UserId)
	if not sender then
		return true
	end
	local userId = sender.UserId
	local now = os.clock()
	local bucket = buckets[userId]
	if not bucket then
		bucket = ChatRules.newBucket(now, ChatRules.SERVER_BURST)
		buckets[userId] = bucket
	end
	-- Texte compté et journalisé sans entités de texte riche (« &lt; » compte pour un caractère, comme chez le client)
	local text = ChatRules.clean(ChatRules.unescape(message.Text))
	local verdict = ChatRules.admit(bucket, text, now, muted[userId] == true, ChatRules.SERVER_BURST)
	local accepted = verdict == "ok"
	decisions[id] = accepted
	task.delay(DECISION_TTL, function()
		decisions[id] = nil
	end)
	if accepted then
		task.spawn(logMessage, userId, sender.Name, text)
	end
	return accepted
end

-- Cette méthode permet de brancher la décision sur un canal lorsqu'il existe ou qu'il est créé (RBXGeneral, et tout
-- canal ajouté plus tard).
local function guardChannel(channel: Instance)
	if channel:IsA("TextChannel") then
		channel.ShouldDeliverCallback = function(message: TextChatMessage, _target: TextSource)
			return ChatService.decide(message)
		end
	end
end

-- Cette méthode permet d'envoyer un retour à l'admin lorsqu'il a lancé une commande (gabarit traduit chez lui).
local function notify(player: Player, template: string, args: { [string]: any }?)
	if noticeRemote and player.Parent then
		noticeRemote:FireClient(player, template, args or {})
	end
end

-- Cette méthode permet de savoir si un joueur a droit aux commandes admin lorsqu'il en tape une.
local function canModerate(player: Player): boolean
	return ChatRules.canModerate(
		Roles.hasRole(player, Roles.ADMIN),
		RunService:IsStudio(),
		player:GetAttribute(ChatService.DEBUG_ADMIN_ATTRIBUTE) == true
	)
end

-- Cette méthode permet de lister les joueurs présents (UserId, noms) lorsqu'une commande cherche le joueur visé.
local function candidates(): { ChatRules.Candidate }
	local list = {}
	for _, player in Players:GetPlayers() do
		table.insert(list, { userId = player.UserId, name = player.Name, displayName = player.DisplayName })
	end
	return list
end

-- Cette méthode permet de donner le message d'expulsion dans la langue du compte du joueur expulsé lorsqu'il est
-- expulsé, avec le motif filtré s'il y en a un.
local function kickMessage(target: Player, reason: string?): string
	local language = Locale.fromLocaleId((target :: any).LocaleId)
	if reason and reason ~= "" then
		return Locale.translate(language, ChatRules.KICK_MESSAGE_REASON, { reason = reason })
	end
	return Locale.translate(language, ChatRules.KICK_MESSAGE)
end

-- Cette méthode permet d'appliquer une commande admin lorsqu'un joueur la tape : rien pour un non-admin, sinon
-- sourdine, levée ou expulsion du joueur visé (jamais un admin, soi compris), journalisée, et un retour à l'admin.
function ChatService.runCommand(player: Player, text: string)
	if not canModerate(player) then
		return
	end
	local command, query, reason = ChatRules.parseCommand(text)
	if not command then
		return
	end
	if not query then
		notify(player, ChatRules.Notice.USAGE, { usage = ChatRules.usage(command) })
		return
	end
	local targetId, problem = ChatRules.findTarget(query, candidates())
	local target = targetId and Players:GetPlayerByUserId(targetId)
	if not target then
		local template = if problem == "ambiguous" then ChatRules.Notice.AMBIGUOUS else ChatRules.Notice.NOT_FOUND
		notify(player, template, { query = query })
		return
	end
	-- Un admin (le propriétaire, un autre admin, soi-même) n'est ni mis en sourdine ni expulsé par une commande
	if canModerate(target) then
		notify(player, ChatRules.Notice.PROTECTED, { name = target.DisplayName })
		return
	end
	local entry: ChatLogRules.Entry = {
		at = os.time(),
		kind = command,
		userId = player.UserId,
		name = player.Name,
		targetId = target.UserId,
		targetName = target.Name,
	}
	if command == "mute" then
		muted[target.UserId] = true
		notify(player, ChatRules.Notice.MUTED, { name = target.DisplayName })
	elseif command == "unmute" then
		muted[target.UserId] = nil
		notify(player, ChatRules.Notice.UNMUTED, { name = target.DisplayName })
	else
		local filtered = if reason then filterForAll(reason, player.UserId) else nil
		entry.text = filtered
		notify(player, ChatRules.Notice.KICKED, { name = target.DisplayName })
		target:Kick(kickMessage(target, filtered))
	end
	warn(
		string.format(
			"[ChatService] %s (%d) : /%s %s (%d)",
			player.Name,
			player.UserId,
			command,
			target.Name,
			target.UserId
		)
	)
	if logging() then
		ChatLogRules.push(batch, entry)
	end
end

-- Cette méthode permet d'envoyer le lot en attente lorsque l'intervalle est écoulé ou que le serveur s'arrête (`force` :
-- entrées en filtrage comprises) ; un embed par envoi, un envoi en échec laisse ses entrées au passage suivant.
function ChatService.flush(force: boolean?)
	if flushing then
		return
	end
	flushing = true
	local url = Webhook.url(table.unpack(ChatService.WEBHOOK_NAMES))
	while true do
		local embed, receipt = ChatLogRules.peek(batch, game.JobId, os.time(), force)
		if not embed then
			break
		end
		if url then
			local ok, err = Webhook.postWithRetry(url, embed, WEBHOOK_ATTEMPTS, WEBHOOK_RETRY_DELAY)
			if not ok then
				warn("[ChatService] journal non envoyé, nouvel essai au prochain passage :", err)
				break
			end
			ChatLogRules.commit(batch, receipt)
			if #batch.entries > 0 then
				task.wait(SPLIT_DELAY)
			end
		else
			print("[ChatLog] " .. embed.footer.text .. "\n" .. embed.description)
			ChatLogRules.commit(batch, receipt)
		end
	end
	flushing = false
end

-- Cette méthode permet d'envoyer tout le lot lorsque le serveur s'arrête (BindToClose) : attend un envoi périodique en
-- cours (CLOSE_WAIT s au plus) puis envoie le reste, même si cet envoi n'a pas fini (un doublon plutôt qu'une perte).
local function flushOnClose()
	local deadline = os.clock() + CLOSE_WAIT
	while flushing and os.clock() < deadline do
		task.wait(0.2)
	end
	flushing = false
	ChatService.flush(true)
end

-- Cette méthode permet de couper les commandes par défaut de Roblox (/mute natif prendrait notre alias, /whisper ou
-- /team n'ont pas d'interface dans notre fil) lorsque le serveur démarre ou qu'elles apparaissent.
local function disableDefaultCommand(inst: Instance)
	if inst:IsA("TextChatCommand") and string.sub(inst.Name, 1, 3) == "RBX" then
		inst.Enabled = false
	end
end

-- Cette méthode permet de brancher le chat côté serveur lorsque le serveur démarre : contrôle de chaque canal,
-- commandes admin (remote ChatCommand), envoi périodique du journal et dernier envoi à l'arrêt.
function ChatService.init(notice: RemoteEvent, command: RemoteEvent)
	noticeRemote = notice
	for _, inst in TextChatService:GetDescendants() do
		disableDefaultCommand(inst)
	end
	TextChatService.DescendantAdded:Connect(disableDefaultCommand)

	-- Commandes par un remote et non par TextChatCommand : TextChannel:SendAsync ne déclenche pas toujours les alias
	-- (retours de développeurs), une commande serait alors partie comme message public
	command.OnServerEvent:Connect(function(player: Player, text: unknown)
		if not CheatLog.admit(player, NetworkProtocol.Names.CHAT_COMMAND, text) or type(text) ~= "string" then
			return
		end
		ChatService.runCommand(player, text)
	end)

	task.spawn(function()
		local channels = TextChatService:WaitForChild("TextChannels", 30)
		if not channels then
			warn("[ChatService] TextChannels absent : chat sans contrôle serveur (ChatVersion ?)")
			return
		end
		for _, channel in channels:GetChildren() do
			guardChannel(channel)
		end
		channels.ChildAdded:Connect(guardChannel)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		-- La sourdine reste pour le serveur en cours (reconnexion comprise) ; le débit repart à zéro
		buckets[player.UserId] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(ChatLogRules.FLUSH_INTERVAL)
			local ok, err = pcall(ChatService.flush)
			if not ok then
				flushing = false
				warn("[ChatService] envoi du journal en erreur :", err)
			end
		end
	end)
	game:BindToClose(flushOnClose)
end

return ChatService
