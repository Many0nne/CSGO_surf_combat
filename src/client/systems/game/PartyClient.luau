-- Lobby entre amis côté client (#523) : lit le groupe du joueur local dans les attributs des Players (posés par
-- PartyService : hôte, rang, présence), envoie les demandes du lobby (remote Party) et reçoit les messages du serveur
-- (LANCER de l'hôte, entrée dans le groupe d'un ami, réponses de REJOINDRE).
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local PartyRules = require(Shared:WaitForChild("PartyRules"))
local LoadingRules = require(ReplicatedFirst:WaitForChild("LoadingRules"))
local LoadingScreen = require(ReplicatedFirst:WaitForChild("LoadingScreen"))

local PartyClient = {}

export type Member = {
	id: number,
	name: string,
	isHost: boolean,
	isLocal: boolean,
	presence: PartyRules.Presence,
	order: number,
}

local remote: RemoteEvent? = nil
local listeners: { () -> () } = {}
local watched: { [Player]: { RBXScriptConnection } } = {}
local onGoFn: (() -> ())? = nil
local onJoinedFn: (() -> ())? = nil
local onNoticeFn: ((string) -> ())? = nil
-- Écran de chargement fermé par un départ vers le serveur d'un ami : rouvert si la téléportation échoue (pas celui du
-- lancement, que le client lève lui-même)
local followCovering = false

-- Cette méthode permet de prévenir les abonnés (écran du lobby) lorsque le groupe ou la présence d'un joueur change.
-- Un changement de groupe pose trois attributs sur chaque membre : une seule notification par image.
local notifyQueued = false
local function notify()
	if notifyQueued then
		return
	end
	notifyQueued = true
	task.defer(function()
		notifyQueued = false
		for _, listener in listeners do
			task.spawn(listener)
		end
	end)
end

-- Cette méthode permet de suivre les attributs de groupe d'un joueur du serveur lorsqu'il arrive.
local function watch(player: Player)
	if watched[player] then
		return
	end
	local connections = {}
	for _, attribute in { PartyRules.HOST_ATTRIBUTE, PartyRules.ORDER_ATTRIBUTE, PartyRules.PRESENCE_ATTRIBUTE } do
		table.insert(connections, player:GetAttributeChangedSignal(attribute):Connect(notify))
	end
	watched[player] = connections
	notify()
end

-- Cette méthode permet de lire la présence publiée d'un joueur lorsqu'on dessine le groupe ("menu" si absente).
local function presenceOf(player: Player): PartyRules.Presence
	local value = player:GetAttribute(PartyRules.PRESENCE_ATTRIBUTE)
	return if value == "lobby" or value == "game" then value else "menu"
end

-- Cette méthode permet de lire l'hôte du groupe du joueur local lorsqu'on dessine le lobby (lui-même tant que le
-- serveur n'a rien publié).
function PartyClient.hostId(): number
	local localPlayer = Players.LocalPlayer
	local host = localPlayer:GetAttribute(PartyRules.HOST_ATTRIBUTE)
	return if type(host) == "number" then host else localPlayer.UserId
end

-- Cette méthode permet de lister les membres du groupe du joueur local (hôte en premier, puis par rang) lorsque le
-- lobby se dessine.
function PartyClient.members(): { Member }
	local localPlayer = Players.LocalPlayer
	local host = PartyClient.hostId()
	local list: { Member } = {}
	for _, player in Players:GetPlayers() do
		local playerHost = player:GetAttribute(PartyRules.HOST_ATTRIBUTE)
		local inParty = playerHost == host or (player == localPlayer)
		if inParty then
			local order = player:GetAttribute(PartyRules.ORDER_ATTRIBUTE)
			table.insert(list, {
				id = player.UserId,
				name = player.DisplayName,
				isHost = player.UserId == host,
				isLocal = player == localPlayer,
				presence = presenceOf(player),
				order = if type(order) == "number" then order else math.huge,
			})
		end
	end
	table.sort(list, function(a, b)
		if a.isHost ~= b.isHost then
			return a.isHost
		end
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.id < b.id
	end)
	return list
end

-- Cette méthode permet de décider si le joueur local peut lancer ou attend son hôte lorsque le lobby se dessine
-- (PartyRules.launchState, même règle que le serveur).
function PartyClient.launchState(): PartyRules.LaunchState
	local host = PartyClient.hostId()
	local hostPlayer = Players:GetPlayerByUserId(host)
	return PartyRules.launchState(
		host == Players.LocalPlayer.UserId,
		if hostPlayer then presenceOf(hostPlayer) else nil
	)
end

-- Cette méthode permet de s'abonner aux changements du groupe (arrivées, départs, attributs) lorsque le lobby s'affiche.
function PartyClient.onChanged(listener: () -> ())
	table.insert(listeners, listener)
end

-- Cette méthode permet d'envoyer une demande au serveur lorsque le joueur agit dans le lobby ; rien tant que le remote
-- n'existe pas.
local function send(action: string, target: number?)
	if remote then
		remote:FireServer(action, target or 0)
	end
end

-- Cette méthode permet de signaler au serveur que le lobby est ouvert lorsque le joueur clique JOUER.
function PartyClient.open()
	send(PartyRules.OPEN)
end

-- Cette méthode permet de signaler au serveur que le joueur quitte le lobby pour une autre page du menu.
function PartyClient.close()
	send(PartyRules.CLOSE)
end

-- Cette méthode permet de lancer depuis le lobby lorsque le joueur clique LANCER : le serveur fait entrer les membres du
-- lobby si le joueur est l'hôte (le client du lanceur entre de lui-même dans la manche).
function PartyClient.launch()
	send(PartyRules.LAUNCH)
end

-- Cette méthode permet de quitter le groupe lorsque le joueur clique QUITTER LE GROUPE.
function PartyClient.leave()
	send(PartyRules.LEAVE)
end

-- Cette méthode permet de rejoindre un ami lorsque le joueur clique REJOINDRE : son groupe s'il est sur ce serveur,
-- sinon son serveur (écran de chargement confié à Roblox avant la demande, comme pour l'entraînement).
function PartyClient.follow(friendId: number, elsewhere: boolean)
	if elsewhere then
		LoadingScreen.setTeleportGui(LoadingRules.FOLLOW_LABEL)
	end
	send(PartyRules.FOLLOW, friendId)
end

-- Cette méthode permet de brancher les messages du serveur lorsque le client démarre : `onGo` (l'hôte a lancé), `onJoined`
-- (entré dans le groupe d'un ami), `onNotice` (message à montrer au menu).
function PartyClient.init(onGo: () -> (), onJoined: () -> (), onNotice: (string) -> ())
	onGoFn, onJoinedFn, onNoticeFn = onGo, onJoined, onNotice
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local connections = watched[player]
		watched[player] = nil
		if connections then
			for _, connection in connections do
				connection:Disconnect()
			end
		end
		notify()
	end)
	task.spawn(function()
		local found = NetworkProtocol.getRemote(NetworkProtocol.Names.PARTY)
		if not (found and found:IsA("RemoteEvent")) then
			warn("[PartyClient] remote Party introuvable : lobby sans groupe")
			return
		end
		remote = found
		found.OnClientEvent:Connect(function(message: any)
			if message == PartyRules.GO then
				if onGoFn then
					onGoFn()
				end
			elseif message == PartyRules.JOINED then
				if onJoinedFn then
					onJoinedFn()
				end
			else
				-- Réponse de REJOINDRE : écran de chargement fermé au départ, rouvert sur un échec (#480)
				if message == "teleporting" then
					followCovering = true
					LoadingScreen.cover(LoadingRules.FOLLOW_LABEL, LoadingRules.COVER_TIMEOUT)
				elseif followCovering then
					followCovering = false
					LoadingScreen.uncover()
				end
				local text = PartyRules.notice(message)
				if text and onNoticeFn then
					onNoticeFn(text)
				end
			end
		end)
	end)
end

return PartyClient
