-- Règles pures du lobby entre amis (#523), sans Instance ni service : groupes d'un serveur, hôte, présence de chacun
-- (menu, lobby, partie), lancement, arrivée d'un invité et départs. Testées sous Lune (tests/specs/PartyRules.spec.luau).
--
-- Un serveur fait tourner une seule partie : le groupe ne crée pas de serveur, il synchronise l'entrée dans la manche.
-- - Chaque joueur est toujours dans un groupe, seul au départ (il en est l'hôte). L'hôte est le premier membre ; les
--   autres suivent dans l'ordre d'arrivée.
-- - Rejoindre (invitation acceptée, REJOINDRE un ami) : le joueur quitte son groupe et entre dans celui de l'ami, quel
--   que soit le rôle de l'ami dans ce groupe. L'hôte qui invite reste l'hôte.
-- - Quitter (QUITTER LE GROUPE, déconnexion) : le joueur retrouve un groupe à lui seul (ou disparaît) ; si c'était
--   l'hôte, le membre suivant devient l'hôte. Un groupe n'est jamais dissous tant qu'il a un membre.
-- - Lancer : l'hôte lance pour tous les membres présents dans le lobby. Un membre attend l'hôte tant que celui-ci est
--   dans le lobby ; si l'hôte est au menu ou déjà en partie, le membre lance pour lui seul (il rejoint la manche en cours) :
--   un hôte parti au menu ne bloque personne.
local PartyRules = {}

export type Presence = "menu" | "lobby" | "game"
export type Registry = {
	-- Membres de chaque groupe, l'hôte en premier, par id de l'hôte
	parties: { [number]: { number } },
	-- Hôte du groupe de chaque joueur
	hostOf: { [number]: number },
	presence: { [number]: Presence },
}
-- Ce que l'écran propose à un joueur du lobby : lancer (hôte, ou membre dont l'hôte n'est pas dans le lobby), ou attendre
export type LaunchState = "launch" | "waitHost"

-- Attributs informatifs du Player posés par le serveur (PartyService), lus par les clients pour dessiner le groupe
PartyRules.HOST_ATTRIBUTE = "PartyHost" -- id de l'hôte du groupe du joueur (le sien s'il est l'hôte)
PartyRules.ORDER_ATTRIBUTE = "PartyOrder" -- rang dans le groupe (1 = hôte)
PartyRules.PRESENCE_ATTRIBUTE = "PartyPresence" -- "menu" | "lobby" | "game"

-- Demandes du client (remote Party, client → serveur), toujours avec un nombre (id de l'ami pour FOLLOW, 0 sinon)
PartyRules.OPEN = "open" -- lobby ouvert (JOUER)
PartyRules.CLOSE = "close" -- lobby quitté pour une autre page du menu
PartyRules.LAUNCH = "launch" -- LANCER
PartyRules.LEAVE = "leave" -- QUITTER LE GROUPE
PartyRules.FOLLOW = "follow" -- REJOINDRE un ami (sur ce serveur : son groupe ; sur un autre : téléportation)
PartyRules.REQUESTS = { PartyRules.OPEN, PartyRules.CLOSE, PartyRules.LAUNCH, PartyRules.LEAVE, PartyRules.FOLLOW }

-- Messages du serveur (même remote, serveur → client) : GO (l'hôte a lancé : entrer dans la manche), JOINED (le joueur
-- vient d'entrer dans le groupe d'un ami : ouvrir le lobby), ou un statut de REJOINDRE (message du lobby)
PartyRules.GO = "go"
PartyRules.JOINED = "joined"
export type Status = "teleporting" | "studio" | "failed" | "full" | "notFound" | "notFriend" | "busy"

local NOTICES: { [string]: string } = {
	teleporting = "EN ROUTE VERS LE SERVEUR DE TON AMI…",
	studio = "TÉLÉPORTATION IMPOSSIBLE DANS STUDIO",
	failed = "IMPOSSIBLE DE REJOINDRE TON AMI, RÉESSAIE",
	full = "LE SERVEUR DE TON AMI EST PLEIN",
	notFound = "TON AMI N'EST PLUS DANS LE JEU",
	notFriend = "CE JOUEUR N'EST PAS DANS TES AMIS",
	busy = "TÉLÉPORTATION DÉJÀ EN COURS",
	-- Arrivée par une invitation ou REJOINDRE, mais l'ami n'est pas sur ce serveur (plein entre-temps, parti)
	hostMissing = "TON AMI N'EST PAS SUR CE SERVEUR",
}

-- Cette méthode permet de créer le registre vide des groupes lorsque le serveur démarre.
function PartyRules.new(): Registry
	return { parties = {}, hostOf = {}, presence = {} }
end

-- Cette méthode permet d'inscrire un joueur qui arrive sur le serveur lorsqu'il se connecte : seul dans son groupe, au
-- menu ; sans effet s'il est déjà inscrit.
function PartyRules.add(reg: Registry, id: number)
	if reg.hostOf[id] then
		return
	end
	reg.parties[id] = { id }
	reg.hostOf[id] = id
	reg.presence[id] = "menu"
end

-- Cette méthode permet de lire l'hôte du groupe d'un joueur lorsqu'un écran ou une décision en dépend ; nil s'il n'est
-- pas inscrit.
function PartyRules.hostOf(reg: Registry, id: number): number?
	return reg.hostOf[id]
end

-- Cette méthode permet de lire les membres du groupe d'un joueur (hôte en premier) lorsqu'on les parcourt ; liste vide
-- s'il n'est pas inscrit. La liste rendue est une copie.
function PartyRules.membersOf(reg: Registry, id: number): { number }
	local host = reg.hostOf[id]
	local members = host and reg.parties[host]
	return if members then table.clone(members) else {}
end

-- Cette méthode permet de retirer un joueur de son groupe lorsqu'il le quitte ou se déconnecte : le membre suivant
-- devient l'hôte si c'était lui. Renvoie les joueurs restés dans l'ancien groupe dont l'hôte a changé (attributs à
-- republier).
local function detach(reg: Registry, id: number): { number }
	local host = reg.hostOf[id]
	if not host then
		return {}
	end
	local members = reg.parties[host]
	reg.hostOf[id] = nil
	if not members then
		return {}
	end
	local index = table.find(members, id)
	if index then
		table.remove(members, index)
	end
	if host ~= id then
		-- Un membre part : l'hôte et les autres gardent leur groupe (seuls les rangs changent)
		return table.clone(members)
	end
	reg.parties[host] = nil
	local nextHost = members[1]
	if not nextHost then
		return {}
	end
	reg.parties[nextHost] = members
	for _, member in members do
		reg.hostOf[member] = nextHost
	end
	return table.clone(members)
end

-- Cette méthode permet d'oublier un joueur lorsqu'il se déconnecte ; renvoie les membres de son ancien groupe à
-- republier (hôte transmis au suivant si c'était l'hôte).
function PartyRules.remove(reg: Registry, id: number): { number }
	local changed = detach(reg, id)
	reg.presence[id] = nil
	return changed
end

-- Cette méthode permet de faire quitter son groupe à un joueur lorsqu'il choisit QUITTER LE GROUPE : il retrouve un
-- groupe à lui seul. Renvoie les membres de l'ancien groupe à republier ; vide s'il était déjà seul.
function PartyRules.leave(reg: Registry, id: number): { number }
	local host = reg.hostOf[id]
	if not host then
		return {}
	end
	local members = reg.parties[host]
	if not members or #members <= 1 then
		return {}
	end
	local changed = detach(reg, id)
	reg.parties[id] = { id }
	reg.hostOf[id] = id
	return changed
end

-- Cette méthode permet de faire entrer un joueur dans le groupe d'un ami lorsqu'il arrive par une invitation ou choisit
-- REJOINDRE : il quitte d'abord le sien. Renvoie ok (ou le motif du refus : "self", "unknown" si l'ami n'est pas sur le
-- serveur, "already" s'ils sont déjà ensemble) et les joueurs dont le groupe a changé (attributs à republier).
function PartyRules.join(reg: Registry, id: number, friendId: number): (string, { number })
	if id == friendId then
		return "self", {}
	end
	local host = reg.hostOf[friendId]
	if not host or not reg.hostOf[id] then
		return "unknown", {}
	end
	if reg.hostOf[id] == host then
		return "already", {}
	end
	local changed = detach(reg, id)
	-- L'ami a pu changer de groupe si le joueur en était l'hôte (hôte transmis) : relu après le départ
	host = reg.hostOf[friendId] :: number
	local members = reg.parties[host]
	table.insert(members, id)
	reg.hostOf[id] = host
	for _, member in members do
		if not table.find(changed, member) then
			table.insert(changed, member)
		end
	end
	return "ok", changed
end

-- Cette méthode permet de noter où se trouve un joueur (menu, lobby, partie) lorsqu'il change d'écran ou entre en jeu.
function PartyRules.setPresence(reg: Registry, id: number, presence: Presence)
	if reg.hostOf[id] then
		reg.presence[id] = presence
	end
end

-- Cette méthode permet de lire où se trouve un joueur lorsqu'une décision en dépend ; "menu" s'il n'est pas inscrit.
function PartyRules.presenceOf(reg: Registry, id: number): Presence
	return reg.presence[id] or "menu"
end

-- Cette méthode permet de décider ce que le lobby propose à un joueur lorsqu'il s'affiche ou que le groupe change :
-- l'hôte lance ; un membre attend l'hôte seulement si celui-ci est dans le lobby (sinon il lance pour lui seul).
-- Partagée par le serveur et l'écran du client (qui lit les attributs).
function PartyRules.launchState(isHost: boolean, hostPresence: Presence?): LaunchState
	if isHost or hostPresence ~= "lobby" then
		return "launch"
	end
	return "waitHost"
end

-- Cette méthode permet d'appliquer « lobby quitté » lorsque le client le signale (autre page du menu, retour au menu) :
-- au menu depuis le lobby, ou depuis la partie si le joueur n'y est plus (`playing` : personnage ou apparition en vol ;
-- LANCER de l'hôte reçu hors du lobby, manche finie pendant l'écran de mort). Un « close » arrivé après LANCER ne sort
-- pas de la partie un joueur qui y entre. Renvoie true si la présence a changé.
function PartyRules.close(reg: Registry, id: number, playing: boolean): boolean
	local presence = reg.presence[id]
	if presence == "lobby" or (presence == "game" and not playing) then
		reg.presence[id] = "menu"
		return true
	end
	return false
end

-- Cette méthode permet d'écrire la ligne « qui lance » du lobby lorsque le groupe change : seul, hôte, membre qui attend
-- l'hôte, ou membre dont l'hôte est en partie ou au menu (il lance seul). `hostName` : nom de l'hôte (nil s'il est
-- inconnu).
function PartyRules.statusLine(
	count: number,
	isHost: boolean,
	state: LaunchState,
	hostPresence: Presence?,
	hostName: string?
): string
	if count <= 1 then
		return "INVITE TES AMIS OU LANCE SEUL"
	end
	if isHost then
		return "TU ES L'HÔTE · LANCER FAIT ENTRER TOUT LE LOBBY"
	end
	local name = if hostName then string.upper(hostName) else "TON HÔTE"
	if state == "waitHost" then
		return "EN ATTENTE DE L'HÔTE · " .. name .. " LANCE LA PARTIE"
	end
	if hostPresence == "game" then
		return name .. " EST EN PARTIE · LANCE POUR LE REJOINDRE"
	end
	return name .. " EST AU MENU · TU PEUX LANCER SEUL"
end

-- Cette méthode permet d'appliquer LANCER lorsqu'un joueur du lobby le choisit : il passe en partie, et s'il est l'hôte
-- et lance depuis le lobby, les membres présents dans le lobby avec lui aussi. Renvoie les autres joueurs à faire
-- entrer dans la manche (vide pour un membre, qui lance pour lui seul, ou pour un hôte qui n'est pas dans le lobby).
function PartyRules.launch(reg: Registry, id: number): { number }
	local host = reg.hostOf[id]
	if not host then
		return {}
	end
	local fromLobby = reg.presence[id] == "lobby"
	reg.presence[id] = "game"
	local pulled = {}
	if host ~= id or not fromLobby then
		return pulled
	end
	for _, member in reg.parties[host] do
		if member ~= id and reg.presence[member] == "lobby" then
			reg.presence[member] = "game"
			table.insert(pulled, member)
		end
	end
	return pulled
end

-- Cette méthode permet de lire une demande du client lorsqu'elle arrive : l'action et l'id visé (FOLLOW seulement, entier
-- positif), ou nil si elle est invalide.
function PartyRules.readRequest(action: any, target: any): (string?, number?)
	if type(action) ~= "string" or not table.find(PartyRules.REQUESTS, action) then
		return nil, nil
	end
	if action ~= PartyRules.FOLLOW then
		return action, nil
	end
	if type(target) ~= "number" or target ~= math.floor(target) or target == 0 or math.abs(target) > 2 ^ 53 then
		return nil, nil
	end
	return action, target
end

-- Cette méthode permet de lire l'ami dont le joueur rejoint le groupe à son arrivée sur le serveur, d'après
-- `Player:GetJoinData()` : données de lancement d'une invitation (`LaunchData`, id en texte), ou données de téléportation
-- de REJOINDRE (`TeleportData.partyHost`). nil sans ami valide.
function PartyRules.readJoinHost(joinData: any): number?
	if type(joinData) ~= "table" then
		return nil
	end
	local teleport = joinData.TeleportData
	if type(teleport) == "table" then
		local host = teleport.partyHost
		if type(host) == "number" and host == math.floor(host) and host > 0 then
			return host
		end
	end
	local launch = joinData.LaunchData
	if type(launch) == "string" then
		local digits = string.match(launch, "^%s*(%d+)%s*$")
		local host = digits and tonumber(digits)
		if host and host > 0 and host < 2 ^ 53 then
			return host
		end
	end
	return nil
end

-- Cette méthode permet d'écrire les données de lancement d'une invitation lorsque le joueur invite un ami : son propre
-- id, relu à l'arrivée de l'ami par readJoinHost.
function PartyRules.launchData(hostId: number): string
	return tostring(hostId)
end

-- Cette méthode permet de donner le message du lobby pour une réponse du serveur lorsqu'elle arrive ; nil si elle est
-- inconnue.
function PartyRules.notice(status: any): string?
	return if type(status) == "string" then NOTICES[status] else nil
end

return PartyRules
