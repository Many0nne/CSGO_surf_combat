-- Règles pures du mode entraînement (#345), sans Instance ni service : reconnaître un serveur d'entraînement, partager un
-- même serveur réservé entre les joueurs (code d'accès commun, remplacé quand ce serveur est plein ou introuvable), et
-- message montré au joueur pour chaque réponse du serveur. Testées sous Lune (tests/specs/TrainingRules.spec.luau).
--
-- Un serveur d'entraînement est un serveur réservé de la même place (TeleportService:ReserveServer) : le jeu n'en
-- réserve pour rien d'autre. Il garde le moteur de jeu (mouvement, map, mort par chute) sans bots, sans armes ni
-- dégâts, sans stats, dans une manche sans fin ; le client y montre la démo dans un coin (TrainingClient).
local TrainingRules = {}

-- Attribut de ReplicatedStorage posé par le serveur au démarrage : true sur un serveur d'entraînement
TrainingRules.ATTRIBUTE = "TrainingServer"
-- Studio seulement (la téléportation n'y marche pas) : attribut Workspace à poser en mode Edit avant le playtest, pour
-- que le serveur du playtest se comporte en serveur d'entraînement
TrainingRules.DEBUG_ATTRIBUTE = "DebugTraining"

-- Clé du code d'accès partagé dans la MemoryStore (SortedMap TrainingRules.MAP), et durée de vie de l'entrée (s),
-- prolongée à chaque usage : un code reste valable tant qu'on l'utilise (un serveur réservé vide s'éteint, le même code
-- en relance un neuf)
TrainingRules.MAP = "TrainingServers"
TrainingRules.KEY = "shared"
TrainingRules.CODE_TTL = 24 * 3600

-- Demandes du client (remote Training, client → serveur)
TrainingRules.JOIN = "join"
TrainingRules.LEAVE = "leave"

-- Réponses du serveur (même remote, serveur → client)
export type Status = "teleporting" | "studio" | "failed" | "busy" | "unavailable"

-- Résultats de téléportation (noms de Enum.TeleportResult) pour lesquels le code partagé est remplacé par un neuf avant
-- un nouvel essai : serveur plein, ou introuvable
local ROTATE_ON = { GameFull = true, GameNotFound = true }
-- Essais d'une même demande (le premier, puis un avec un code neuf)
TrainingRules.MAX_TRIES = 2

local NOTICES: { [string]: string } = {
	teleporting = "EN ROUTE…",
	studio = "TÉLÉPORTATION IMPOSSIBLE DANS STUDIO",
	failed = "TÉLÉPORTATION IMPOSSIBLE, RÉESSAIE",
	busy = "TÉLÉPORTATION DÉJÀ EN COURS",
	unavailable = "ENTRAÎNEMENT INDISPONIBLE",
}

-- Cette méthode permet de savoir si le serveur courant est un serveur d'entraînement lorsqu'il démarre : serveur réservé
-- (identifiant privé non vide, sans propriétaire), ou playtest Studio avec l'attribut DebugTraining.
function TrainingRules.isTrainingServer(
	privateServerId: string,
	privateServerOwnerId: number,
	isStudio: boolean,
	debugFlag: any
): boolean
	if privateServerId ~= "" and privateServerOwnerId == 0 then
		return true
	end
	return isStudio and debugFlag == true
end

-- Cette méthode permet de garder le code partagé déjà en place lorsque deux serveurs en réservent un en même temps
-- (transformation d'UpdateAsync, pure) : le premier écrit l'emporte, `candidate` ne sert que s'il n'y en a pas.
function TrainingRules.keepCode(stored: any, candidate: string): string
	if type(stored) == "string" and stored ~= "" then
		return stored
	end
	return candidate
end

-- Cette méthode permet de remplacer le code partagé par `fresh` lorsqu'une téléportation vers `failed` a échoué
-- (serveur plein) ; un code déjà remplacé par un autre serveur entre-temps est gardé (transformation d'UpdateAsync).
function TrainingRules.rotateCode(stored: any, failed: string, fresh: string): string
	if type(stored) ~= "string" or stored == "" or stored == failed then
		return fresh
	end
	return stored
end

-- Cette méthode permet de décider si un échec de téléportation est retenté avec un code neuf lorsqu'il arrive : selon le
-- résultat (nom de Enum.TeleportResult) et le numéro de l'essai qui a échoué.
function TrainingRules.retriesWithFreshCode(resultName: string, try: number): boolean
	return ROTATE_ON[resultName] == true and try < TrainingRules.MAX_TRIES
end

-- Cette méthode permet de lire une demande du client lorsqu'elle arrive : "join", "leave", ou nil si elle est inconnue.
function TrainingRules.readRequest(request: any): string?
	if request == TrainingRules.JOIN or request == TrainingRules.LEAVE then
		return request
	end
	return nil
end

-- Cette méthode permet de décider ce que le serveur fait d'une demande lorsqu'elle arrive : "teleport" (vers le serveur
-- d'entraînement pour join, vers un serveur public pour leave), ou une réponse de refus.
function TrainingRules.decide(request: string, isTraining: boolean, isStudio: boolean, pending: boolean): string
	if pending then
		return "busy"
	end
	-- Rejoindre depuis l'entraînement, ou le quitter depuis la partie : rien à faire
	if (request == TrainingRules.JOIN) == isTraining then
		return "unavailable"
	end
	if isStudio then
		return "studio"
	end
	return "teleport"
end

-- Cette méthode permet de donner le message du menu pour une réponse du serveur lorsqu'elle arrive ; nil si elle est
-- inconnue.
function TrainingRules.notice(status: any): string?
	return if type(status) == "string" then NOTICES[status] else nil
end

return TrainingRules
