local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = {}

Protocol.Names = {
	-- Combat (créés par init.server)
	MELEE_DAMAGE = "MeleeDamage",
	HITSCAN_DAMAGE = "HitscanDamage",
	-- Hitmarker (#44) : serveur → tireur, touche confirmée (arguments : cible morte, tir à la tête)
	HIT_CONFIRM = "HitConfirm",
	-- Jeu
	REQUEST_SPAWN = "RequestSpawn",
	ROUND_STATE = "RoundState",
	SCORE_UPDATE = "ScoreUpdate",
	ROUND_RESULT = "RoundResult",
	PLAYER_DIED = "PlayerDied",
	-- Retour au menu principal depuis le menu en partie (#157) : client → serveur, sans argument ; le serveur retire le
	-- joueur du round (score de la manche, personnage, réapparition), cf. server/init.server
	LEAVE_ROUND = "LeaveRound",
	-- Position des personnages (#75), UnreliableRemoteEvent : client → serveur (position, cap, numéro de la dernière
	-- correction appliquée) à NET_SYNC_RATE, puis serveur → autres clients (joueur, position, cap, horodatage
	-- serveur), cf. server/CharacterSync
	CHARACTER_SYNC = "CharacterSync",
	-- Correction de position (#172), RemoteEvent fiable serveur → client (personnage, dernière position acceptée,
	-- numéro) : le client s'y replace, vitesse nulle, et joint le numéro à ses paquets CharacterSync suivants
	MOVEMENT_CORRECTION = "MovementCorrection",
	-- Arme 3e personne (#5) : client → serveur, action visuelle ("Shoot" | "Reload")
	WEAPON_ACTION = "WeaponAction",
	-- Feedback
	SEND_FEEDBACK = "SendFeedback",
	FEEDBACK_ACK = "FeedbackAck",
	-- Réglages du joueur (#100), cf. server/SettingsStore : RemoteFunction client → serveur (réglages sauvegardés),
	-- puis RemoteEvent client → serveur à chaque changement (réglages complets, validés par le serveur)
	GET_SETTINGS = "GetSettings",
	SAVE_SETTINGS = "SaveSettings",
	-- Helper de playtest debug (#30) : créé uniquement dans Studio (RunService:IsStudio()), jamais en jeu publié
	DEBUG_PLAYTEST = "DebugPlaytest",
}

function Protocol.getRemote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild(name, 15) :: RemoteEvent
end

return Protocol
