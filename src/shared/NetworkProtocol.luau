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
	-- participants en jeu (pas ceux restés au menu), chacun avec son id ; le client y résout le nom du vainqueur ; `clip` :
	-- meilleure action de la partie (#499, HighlightClipRules.Clip), absente sans kill valide
	ROUND_RESULT = "RoundResult",
	-- Clip de la partie (#499), cf. server/HighlightService : serveur → tireur d'un kill record (numéro de la demande,
	-- début et fin de la fenêtre, horloge serveur), puis client → serveur (même numéro, tampon caméra de la fenêtre en
	-- série HighlightClipRules.CAMERA_SCALES) ; le clip retenu part ensuite à tous dans RoundResult (`clip`)
	HIGHLIGHT_POV = "HighlightPov",
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
	-- Bruits de pas (#146), UnreliableRemoteEvent serveur → clients sauf l'auteur (personnage, position des pieds,
	-- "step" | "land") : pas détectés sur les positions acceptées des joueurs et des bots, cf. server/FootstepService
	FOOTSTEP = "Footstep",
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
	-- Ouverture d'une caisse du shop (#332), cf. server/CrateService : RemoteFunction client → serveur (id de la caisse),
	-- réponse { ok, reason?, skinId?, rarity?, added? } ; ouverture de test gratuite, réservée à l'admin et à Studio
	OPEN_CRATE = "OpenCrate",
	-- Achat d'une caisse du shop (#393), cf. server/CrateService : RemoteFunction client → serveur (id de la caisse),
	-- réponse après l'écriture { ok, reason?, skinId?, rarity?, added?, refund? } ; prix et tirage décidés par le serveur
	BUY_CRATE = "BuyCrate",
	-- Achat d'un pack de crédits en Robux (#395), cf. server/ReceiptService : RemoteFunction client → serveur (id du pack),
	-- réponse { ok, reason? } ; le serveur ouvre le prompt Roblox (refusé à un joueur restreint), les crédits arrivent
	-- par ProcessReceipt (attribut `Credits`)
	BUY_CREDIT_PACK = "BuyCreditPack",
	-- Helper de playtest debug (#30) : créé uniquement dans Studio (RunService:IsStudio()), jamais en jeu publié
	DEBUG_PLAYTEST = "DebugPlaytest",
	-- Rejeu d'un parcours de mesure (#379) : client → serveur (position du point de contrôle) ; le serveur y replace le
	-- personnage par une correction (CharacterSync.teleport). Refusé sauf dans Studio ou pour le créateur du jeu publié
	PERF_ROUTE_TELEPORT = "PerfRouteTeleport",
	-- Mode entraînement (#345), cf. server/TrainingService : client → serveur ("join" depuis APPRENDRE, "leave" depuis le
	-- serveur d'entraînement), puis serveur → client (réponse, TrainingRules.Status) ; le serveur téléporte le joueur
	TRAINING = "Training",
	-- Analytics (#527), cf. server/analytics/Analytics : client → serveur, écran courant du joueur (une valeur de
	-- AnalyticsRules.SCREENS) envoyé à chaque changement ; le serveur en tire les funnels et l'endroit d'un départ
	ANALYTICS_SCREEN = "AnalyticsScreen",
}

function Protocol.getRemote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild(name, 15) :: RemoteEvent
end

return Protocol
