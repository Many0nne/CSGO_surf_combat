-- Lobby entre amis (#523), côté serveur : tient les groupes du serveur (règles pures `PartyRules`), publie le groupe de
-- chaque joueur dans des attributs informatifs du Player (hôte, rang, présence : lus par les clients pour dessiner le
-- lobby), traite les demandes du remote Party (lobby ouvert ou quitté, LANCER, QUITTER LE GROUPE, REJOINDRE un ami) et
-- relie un joueur qui arrive par une invitation ou REJOINDRE au groupe de son ami (`Player:GetJoinData`).
-- Le groupe ne donne aucun droit en jeu : entrer dans la manche passe toujours par RequestSpawn (mêmes règles pour tous).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local PartyRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PartyRules"))
local CheatLog = require(script.Parent.CheatLog)

local PartyService = {}

local registry = PartyRules.new()
local remote: RemoteEvent
-- REJOINDRE en cours (téléportation lancée), par joueur : la demande suivante est répondue « busy » jusqu'à son issue
local pending: { [Player]: { at: number } } = {}
-- Délai (s) au bout duquel une téléportation lancée sans suite ne bloque plus une nouvelle demande
local PENDING_TIMEOUT = 30

-- Cette méthode permet de republier les attributs de groupe (hôte, rang, présence) des joueurs `ids` lorsque leur groupe
-- ou leur présence change ; un id sans joueur sur le serveur est ignoré.
local function publish(ids: { number })
	for _, id in ids do
		local player = Players:GetPlayerByUserId(id)
		local host = PartyRules.hostOf(registry, id)
		if player and host then
			local members = PartyRules.membersOf(registry, id)
			player:SetAttribute(PartyRules.HOST_ATTRIBUTE, host)
			player:SetAttribute(PartyRules.ORDER_ATTRIBUTE, table.find(members, id) or 1)
			player:SetAttribute(PartyRules.PRESENCE_ATTRIBUTE, PartyRules.presenceOf(registry, id))
		end
	end
end

-- Cette méthode permet d'envoyer un message du lobby à un joueur lorsqu'une demande aboutit ou échoue.
local function reply(player: Player, message: string, value: number?)
	if player.Parent then
		remote:FireClient(player, message, value)
	end
end

-- Cette méthode permet de vérifier qu'un joueur est ami avec `otherId` lorsqu'il rejoint son groupe (hors Studio, où
-- les joueurs de test n'ont pas d'amis) ; un appel en échec vaut refus.
local function areFriends(player: Player, otherId: number): boolean
	if RunService:IsStudio() then
		return true
	end
	local ok, result = pcall(player.IsFriendsWithAsync, player, otherId)
	if not ok then
		warn("[PartyService] amitié de " .. player.Name .. " avec " .. otherId .. " illisible :", result)
		return false
	end
	return result == true
end

-- Cette méthode permet de faire entrer un joueur dans le groupe de l'ami `friendId` (présent sur le serveur) lorsqu'il
-- arrive par une invitation ou choisit REJOINDRE ; le client ouvre alors le lobby (JOINED). Renvoie le motif de
-- PartyRules.join.
local function joinFriend(player: Player, friendId: number): string
	local result, changed = PartyRules.join(registry, player.UserId, friendId)
	if result == "ok" then
		publish(changed)
		reply(player, PartyRules.JOINED, PartyRules.hostOf(registry, player.UserId))
	end
	return result
end

-- Cette méthode permet de téléporter un joueur vers le serveur de son ami (REJOINDRE, ami dans le jeu sur un autre
-- serveur) lorsqu'il le demande : serveur de l'ami trouvé par TeleportService, données de téléportation qui le relient
-- au groupe de l'ami à l'arrivée.
local function followElsewhere(player: Player, friendId: number)
	local ok, here, err, placeId, jobId = pcall(TeleportService.GetPlayerPlaceInstanceAsync, TeleportService, friendId)
	if not ok or not here or placeId ~= game.PlaceId or type(jobId) ~= "string" or jobId == "" then
		if not ok then
			warn("[PartyService] serveur de " .. friendId .. " introuvable :", here)
		elseif err and err ~= "" then
			warn("[PartyService] serveur de " .. friendId .. " introuvable :", err)
		end
		reply(player, "notFound")
		return
	end
	if jobId == game.JobId then
		-- Revenu sur ce serveur entre-temps
		if joinFriend(player, friendId) == "unknown" then
			reply(player, "notFound")
		end
		return
	end
	local entry = { at = os.clock() }
	pending[player] = entry
	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = jobId
	options:SetTeleportData({ partyHost = friendId })
	local sent, failure = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, options)
	if not sent then
		warn("[PartyService] téléportation de " .. player.Name .. " impossible :", failure)
		pending[player] = nil
		reply(player, "failed")
		return
	end
	reply(player, "teleporting")
	task.delay(PENDING_TIMEOUT, function()
		if pending[player] == entry then
			pending[player] = nil
		end
	end)
end

-- Cette méthode permet de traiter REJOINDRE lorsqu'il arrive : groupe de l'ami s'il est sur ce serveur, sinon son
-- serveur (refusé dans Studio, ou si ce n'est pas un ami).
local function follow(player: Player, friendId: number)
	if pending[player] then
		reply(player, "busy")
		return
	end
	if not areFriends(player, friendId) then
		reply(player, "notFriend")
		return
	end
	if Players:GetPlayerByUserId(friendId) then
		joinFriend(player, friendId)
		return
	end
	if RunService:IsStudio() then
		reply(player, "studio")
		return
	end
	followElsewhere(player, friendId)
end

-- Cette méthode permet de traiter une demande du remote Party lorsqu'elle arrive (garde commune d'abord).
local function onRequest(player: Player, rawAction: any, rawTarget: any)
	if not CheatLog.admit(player, remote.Name, rawAction, rawTarget) then
		return
	end
	local action, target = PartyRules.readRequest(rawAction, rawTarget)
	local id = player.UserId
	if action == PartyRules.OPEN then
		PartyRules.setPresence(registry, id, "lobby")
		publish({ id })
	elseif action == PartyRules.CLOSE then
		-- Seulement depuis le lobby : un « close » arrivé après LANCER ne remet pas au menu un joueur en partie
		if PartyRules.presenceOf(registry, id) == "lobby" then
			PartyRules.setPresence(registry, id, "menu")
			publish({ id })
		end
	elseif action == PartyRules.LAUNCH then
		-- Le client du lanceur entre de lui-même dans la manche (RequestSpawn) ; l'hôte y fait entrer les membres du lobby
		local pulled = PartyRules.launch(registry, id)
		publish({ id })
		publish(pulled)
		for _, memberId in pulled do
			local member = Players:GetPlayerByUserId(memberId)
			if member then
				reply(member, PartyRules.GO)
			end
		end
	elseif action == PartyRules.LEAVE then
		publish(PartyRules.leave(registry, id))
		publish({ id })
	elseif action == PartyRules.FOLLOW and target then
		follow(player, target)
	end
end

-- Cette méthode permet de relier un joueur qui arrive par une invitation ou REJOINDRE au groupe de son ami lorsqu'il
-- se connecte (données de lancement ou de téléportation) ; ami absent du serveur (plein, parti) : il reste seul, prévenu.
local function onArrival(player: Player)
	local ok, joinData = pcall(player.GetJoinData, player)
	local friendId = if ok then PartyRules.readJoinHost(joinData) else nil
	if not friendId or friendId == player.UserId then
		return
	end
	if not Players:GetPlayerByUserId(friendId) then
		reply(player, "hostMissing")
		return
	end
	if not areFriends(player, friendId) then
		warn("[PartyService] " .. player.Name .. " arrive pour " .. friendId .. " sans en être ami : groupe ignoré")
		return
	end
	if joinFriend(player, friendId) == "unknown" then
		reply(player, "hostMissing")
	end
end

-- Cette méthode permet d'inscrire un joueur lorsqu'il se connecte (seul dans son groupe, au menu), puis de le relier au
-- groupe de son ami s'il arrive par une invitation.
local function onPlayerAdded(player: Player)
	PartyRules.add(registry, player.UserId)
	publish({ player.UserId })
	-- À part : l'amitié se vérifie par un appel web
	task.spawn(onArrival, player)
end

-- Cette méthode permet de noter qu'un joueur entre en partie lorsque sa demande d'apparition est acceptée (JOUER seul,
-- manche suivante, LANCER d'un hôte) : ses amis ne l'attendent plus dans le lobby.
function PartyService.noteInGame(player: Player)
	if PartyRules.presenceOf(registry, player.UserId) ~= "game" then
		PartyRules.setPresence(registry, player.UserId, "game")
		publish({ player.UserId })
	end
end

-- Cette méthode permet de noter qu'un joueur revient au menu lorsqu'il quitte la partie (MENU PRINCIPAL, abandon d'une
-- apparition).
function PartyService.noteMenu(player: Player)
	if PartyRules.presenceOf(registry, player.UserId) == "game" then
		PartyRules.setPresence(registry, player.UserId, "menu")
		publish({ player.UserId })
	end
end

-- Cette méthode permet de brancher les demandes des joueurs, leurs arrivées et départs lorsque le serveur démarre.
function PartyService.init(partyRemote: RemoteEvent)
	remote = partyRemote
	remote.OnServerEvent:Connect(onRequest)
	TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
		if not pending[player] then
			return
		end
		pending[player] = nil
		warn(string.format("[PartyService] échec de REJOINDRE de %s : %s (%s)", player.Name, result.Name, message))
		reply(player, if result == Enum.TeleportResult.GameFull then "full" else "failed")
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		publish(PartyRules.remove(registry, player.UserId))
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return PartyService
