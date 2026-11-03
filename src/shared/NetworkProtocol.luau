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
	-- Chute hors de l'île : client → serveur, le joueur est passé sous Maps.Map.KillHeight (le serveur ne voit pas
	-- la position, le mouvement est fait par le client)
	FELL_OUT = "FellOut",
	-- Arme 3e personne (#5) : client → serveur, action visuelle ("Shoot" | "Reload")
	WEAPON_ACTION = "WeaponAction",
	-- Feedback
	SEND_FEEDBACK = "SendFeedback",
	FEEDBACK_ACK = "FeedbackAck",
	-- Helper de playtest debug (#30) : créé uniquement dans Studio (RunService:IsStudio()), jamais en jeu publié
	DEBUG_PLAYTEST = "DebugPlaytest",
}

function Protocol.getRemote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild(name, 15) :: RemoteEvent
end

return Protocol
