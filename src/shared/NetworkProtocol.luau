local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = {}

Protocol.Names = {
	-- Combat (créés par init.server)
	MELEE_DAMAGE = "MeleeDamage",
	HITSCAN_DAMAGE = "HitscanDamage",
	-- Hitmarker (#44) : serveur → tireur, touche confirmée (arguments : cible morte, tir à la tête)
	HIT_CONFIRM = "HitConfirm",
	-- Tir entendu par les autres (#156) : client → serveur à chaque tir à distance, touché ou manqué (origine,
	-- direction, instant du tir : la touche s'y rattache, #216), compté dans le chargeur serveur (#215), puis serveur →
	-- autres clients (personnage du tireur, nom de l'arme, origine, direction), tirs de bots compris ; le client joue
	-- le son de l'arme en 3D sur l'arme 3P du tireur (RemoteShotSounds), le serveur pose le recul 3P
	SHOT_FIRED = "ShotFired",
	-- Jeu
	REQUEST_SPAWN = "RequestSpawn",
	ROUND_STATE = "RoundState",
	SCORE_UPDATE = "ScoreUpdate",
	-- Fin de manche (#295) : serveur → tous, { outcome = "winner" | "tie" | "none", winnerId, scores } ; `scores` liste les
	-- participants en jeu (pas ceux restés au menu), chacun avec son id ; le client y résout le nom du vainqueur
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
	-- Arme 3e personne (#5) : client → serveur, action visuelle ("Shoot" | "Reload") ; "Shoot" n'est plus suivi que
	-- pour le couteau (le tir d'une arme à distance passe par ShotFired, #215)
	WEAPON_ACTION = "WeaponAction",
	-- Feedback
	SEND_FEEDBACK = "SendFeedback",
	FEEDBACK_ACK = "FeedbackAck",
	-- Réglages du joueur (#100), cf. server/SettingsStore : RemoteFunction client → serveur (réglages sauvegardés),
	-- puis RemoteEvent client → serveur à chaque changement (réglages complets, validés par le serveur)
	GET_SETTINGS = "GetSettings",
	SAVE_SETTINGS = "SaveSettings",
	-- Équipement (#280), cf. server/InventoryStore : client → serveur depuis l'accueil (emplacement, id de l'arme, id du
	-- skin ou "" pour d'origine) ; le serveur valide, applique et publie l'attribut `EquippedItems` du Player
	EQUIP_ITEM = "EquipItem",
	-- Helper de playtest debug (#30) : créé uniquement dans Studio (RunService:IsStudio()), jamais en jeu publié
	DEBUG_PLAYTEST = "DebugPlaytest",
}

function Protocol.getRemote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild(name, 15) :: RemoteEvent
end

return Protocol
