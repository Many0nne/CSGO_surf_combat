-- Règles pures de la liste d'amis du lobby (#523), sans Instance ni service : réunir la liste des amis
-- (`Players:GetFriendsAsync`) et celle des amis en ligne (`Player:GetFriendsOnline`) en un statut par ami, trier, et
-- choisir l'action proposée (INVITER, REJOINDRE) avec la raison quand elle est impossible. Testées sous Lune
-- (tests/specs/FriendRules.spec.luau).
local FriendRules = {}

-- Statut d'un ami, du plus proche au plus lointain : sur ce serveur, dans ce jeu sur un autre serveur, en ligne
-- ailleurs, hors ligne
export type Status = "here" | "game" | "online" | "offline"
export type Friend = {
	id: number,
	name: string, -- nom affiché (DisplayName), sinon nom d'utilisateur
	status: Status,
	jobId: string?, -- serveur du jeu où il joue (statut "game")
}
-- Action proposée : INVITER (sur ce serveur), REJOINDRE (son groupe ici, ou son serveur par téléportation)
export type Action = "invite" | "follow"
export type Context = {
	studio: boolean, -- Studio : ni invitation ni téléportation
	canInvite: boolean?, -- réponse de SocialService:CanSendGameInviteAsync (nil : pas encore connue)
	serverFull: boolean, -- ce serveur est plein : un invité ne pourrait pas y arriver
	partyIds: { [number]: boolean }, -- membres du groupe du joueur
}

-- Nombre d'amis au plus montrés (pages de GetFriendsAsync lues jusque-là)
FriendRules.MAX_FRIENDS = 100
-- LocationType de GetFriendsOnline d'un ami dans une expérience : sur ordinateur (4), sur mobile (1), sur Xbox (5) ; les
-- autres (site, Studio, Team Create) ne sont pas en jeu
FriendRules.IN_GAME_LOCATION = 4
local IN_GAME_LOCATIONS = { [1] = true, [4] = true, [5] = true }
-- Studio seulement : attribut du Player (posé en contexte serveur ou client) qui remplace la liste par de faux amis,
-- joueurs du serveur compris (les API d'amis ne marchent pas avec les joueurs de test)
FriendRules.DEBUG_ATTRIBUTE = "DebugFriends"

local ORDER: { [Status]: number } = { here = 1, game = 2, online = 3, offline = 4 }

FriendRules.STATUS_LABELS = {
	here = "SUR CE SERVEUR",
	game = "DANS LE JEU",
	online = "EN LIGNE",
	offline = "HORS LIGNE",
} :: { [Status]: string }
FriendRules.IN_PARTY_LABEL = "DANS TON GROUPE"

-- Raisons d'une action impossible, montrées sous la liste
FriendRules.REASONS = {
	studio = "INVITER ET REJOINDRE UN AUTRE SERVEUR SONT IMPOSSIBLES DANS STUDIO",
	refused = "ROBLOX REFUSE LES INVITATIONS DEPUIS CE COMPTE",
	full = "SERVEUR PLEIN : UN AMI INVITÉ NE POURRAIT PAS TE REJOINDRE",
}

-- Cette méthode permet de lire un nom d'ami lorsqu'une entrée de l'API arrive : nom affiché, sinon nom d'utilisateur,
-- sinon l'id.
local function nameOf(displayName: any, userName: any, id: number): string
	if type(displayName) == "string" and displayName ~= "" then
		return displayName
	end
	if type(userName) == "string" and userName ~= "" then
		return userName
	end
	return tostring(id)
end

-- Cette méthode permet de construire la liste des amis lorsque le lobby la (re)charge : `all` (entrées de
-- GetFriendsAsync : Id, Username, DisplayName), `online` (entrées de GetFriendsOnline : VisitorId, UserName,
-- DisplayName, LocationType, PlaceId, GameId), la place et le serveur courants, et les ids des joueurs présents sur ce
-- serveur. Un ami vu en ligne mais absent de `all` (au-delà de MAX_FRIENDS) est ajouté. Entrées illisibles ignorées.
function FriendRules.merge(
	all: { any },
	online: { any },
	placeId: number,
	jobId: string,
	onServer: { [number]: boolean }
): { Friend }
	local byId: { [number]: Friend } = {}
	local list: { Friend } = {}
	-- Cette méthode permet d'ajouter un ami à la liste lorsqu'il est lu pour la première fois.
	local function ensure(id: number, name: string): Friend
		local friend = byId[id]
		if not friend then
			friend = { id = id, name = name, status = "offline" }
			byId[id] = friend
			table.insert(list, friend)
		end
		return friend
	end
	for _, entry in all do
		local id = type(entry) == "table" and entry.Id
		if type(id) == "number" then
			ensure(id, nameOf(entry.DisplayName, entry.Username, id))
		end
	end
	for _, entry in online do
		local id = type(entry) == "table" and entry.VisitorId
		if type(id) == "number" then
			local friend = ensure(id, nameOf(entry.DisplayName, entry.UserName, id))
			friend.status = "online"
			if IN_GAME_LOCATIONS[entry.LocationType] and entry.PlaceId == placeId then
				local gameId = entry.GameId
				if type(gameId) == "string" and gameId ~= "" and gameId ~= jobId then
					friend.status = "game"
					friend.jobId = gameId
				end
			end
		end
	end
	-- Présent ici : connu sans dépendre de l'API (GameId parfois absent selon la confidentialité de l'ami)
	for _, friend in list do
		if onServer[friend.id] then
			friend.status = "here"
			friend.jobId = nil
		end
	end
	table.sort(list, function(a, b)
		if ORDER[a.status] ~= ORDER[b.status] then
			return ORDER[a.status] < ORDER[b.status]
		end
		local la, lb = string.lower(a.name), string.lower(b.name)
		if la ~= lb then
			return la < lb
		end
		return a.id < b.id
	end)
	return list
end

-- Cette méthode permet de choisir l'action d'une ligne d'ami lorsque la liste se dessine : REJOINDRE pour un ami dans le
-- jeu (sur ce serveur : son groupe ; ailleurs : son serveur), INVITER sinon ; rien pour un ami déjà dans le groupe.
-- Renvoie l'action (nil : aucune), si elle est possible, et la raison sinon (clé de REASONS).
function FriendRules.action(friend: Friend, ctx: Context): (Action?, boolean, string?)
	if ctx.partyIds[friend.id] then
		return nil, false, nil
	end
	if friend.status == "here" then
		-- Même serveur : rien à téléporter, possible aussi dans Studio
		return "follow", true, nil
	end
	if friend.status == "game" then
		if ctx.studio then
			return "follow", false, "studio"
		end
		return "follow", true, nil
	end
	if ctx.studio then
		return "invite", false, "studio"
	end
	if ctx.canInvite == false then
		return "invite", false, "refused"
	end
	if ctx.serverFull then
		return "invite", false, "full"
	end
	-- Réponse de Roblox pas encore arrivée : le clic la redemande (InviteFriends)
	return "invite", true, nil
end

-- Cette méthode permet de donner le libellé du statut d'une ligne d'ami lorsque la liste se dessine.
function FriendRules.statusLabel(friend: Friend, ctx: Context): string
	if ctx.partyIds[friend.id] then
		return FriendRules.IN_PARTY_LABEL
	end
	return FriendRules.STATUS_LABELS[friend.status]
end

-- Cette méthode permet de réunir les raisons des actions impossibles de la liste lorsqu'elle se dessine (une ligne
-- sous la liste par raison, dans l'ordre de REASONS : studio, refused, full).
function FriendRules.reasons(friends: { Friend }, ctx: Context): { string }
	local seen: { [string]: boolean } = {}
	for _, friend in friends do
		local _, enabled, reason = FriendRules.action(friend, ctx)
		if not enabled and reason then
			seen[reason] = true
		end
	end
	local lines = {}
	for _, key in { "studio", "refused", "full" } do
		if seen[key] then
			table.insert(lines, FriendRules.REASONS[key])
		end
	end
	return lines
end

-- Cette méthode permet de construire de faux amis lorsque le lobby tourne dans Studio avec DebugFriends : les autres
-- joueurs du serveur (`others` : { id, name }), puis un ami dans le jeu sur un autre serveur, un en ligne ailleurs et un
-- hors ligne (ids positifs fictifs, inconnus du serveur), dans la place `placeId`. Mêmes champs que les API de Roblox,
-- pour passer par merge.
function FriendRules.debugEntries(others: { { id: number, name: string } }, placeId: number): ({ any }, { any })
	local all, online = {}, {}
	for _, other in others do
		table.insert(all, { Id = other.id, Username = other.name, DisplayName = other.name })
	end
	table.insert(all, { Id = 9100000001, Username = "AmiDansLeJeu", DisplayName = "AmiDansLeJeu" })
	table.insert(all, { Id = 9100000002, Username = "AmiEnLigne", DisplayName = "AmiEnLigne" })
	table.insert(all, { Id = 9100000003, Username = "AmiHorsLigne", DisplayName = "AmiHorsLigne" })
	table.insert(online, {
		VisitorId = 9100000001,
		UserName = "AmiDansLeJeu",
		DisplayName = "AmiDansLeJeu",
		LocationType = FriendRules.IN_GAME_LOCATION,
		PlaceId = placeId,
		GameId = "debug-server",
	})
	table.insert(
		online,
		{ VisitorId = 9100000002, UserName = "AmiEnLigne", DisplayName = "AmiEnLigne", LocationType = 2 }
	)
	return all, online
end

return FriendRules
