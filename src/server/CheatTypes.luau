-- Gravités et catégories du journal anti-triche (#170, #226), seule source des noms : CheatLog les ré-exporte
-- (CheatLog.Severity, CheatLog.Category) et les règles pures (ShotRules) les lisent ici. Ce module n'a aucune
-- dépendance : les règles testables sous Lune n'ont pas besoin de CheatLog, qui demande des services Roblox.
-- Une nouvelle parade ajoute sa catégorie ici et dans docs/anticheat.md.

local CheatTypes = {}

export type Severity = "low" | "medium" | "high"

-- Gravités (docs/anticheat.md « Classer les violations ») :
-- - LOW : comptée seulement, l'action est déjà ignorée (débit dépassé, tir un peu tôt) ; faux positifs fréquents ;
-- - MEDIUM : suspecte mais explicable par le réseau (tir sans ligne de vue, téléport refusé) ; entre dans le score ;
-- - HIGH : impossible pour notre client (type d'argument, remote de debug en jeu) ; kick à KICK_HIGH_COUNT.
CheatTypes.Severity = {
	LOW = "low" :: Severity,
	MEDIUM = "medium" :: Severity,
	HIGH = "high" :: Severity,
}

-- Catégories : une par parade. Les suivantes sont réservées aux issues du plan (#160) pour garder des noms stables
-- dans le journal.
CheatTypes.Category = {
	REMOTE_RATE = "RemoteRate", -- débit d'un remote dépassé (RemoteGuard)
	REMOTE_ARGS = "RemoteArgs", -- argument d'un type impossible (RemoteGuard)
	SPAWN = "Spawn", -- réapparition (#171)
	MOVEMENT = "Movement", -- vitesse, téléport, noclip, vol (#172)
	HITSCAN = "Hitscan", -- tir : origine, direction, ligne de vue, equip, chargeur (#174, #175)
	MELEE = "Melee", -- mêlée : equip (#175), orientation, ligne de vue (#176)
	-- statistiques de visée signalées (#178, AimStats) : toujours faible, chiffres bruts pour revue humaine, jamais de
	-- sanction ; un seul signalement suffit au résumé de fin de session (worthSummary)
	AIM = "Aim",
	-- outil non possédé arrivé en main d'un joueur (#267) : retiré ; impossible pour notre client (le serveur seul
	-- distribue les Tools), signe d'un écart côté serveur plus que d'une triche, d'où une gravité faible
	INVENTORY = "Inventory",
}

return CheatTypes
