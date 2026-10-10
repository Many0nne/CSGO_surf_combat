local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = {}

Protocol.Names = {
	-- Combat (créés par init.server)
	MELEE_DAMAGE = "MeleeDamage",
	HITSCAN_DAMAGE = "HitscanDamage",
	-- Jeu
	REQUEST_SPAWN = "RequestSpawn",
	ROUND_STATE = "RoundState",
	SCORE_UPDATE = "ScoreUpdate",
	ROUND_RESULT = "RoundResult",
	PLAYER_DIED = "PlayerDied",
	-- Arme 3e personne (#5) : client → serveur, action visuelle ("Shoot" | "Reload")
	WEAPON_ACTION = "WeaponAction",
	-- Feedback
	SEND_FEEDBACK = "SendFeedback",
	FEEDBACK_ACK = "FeedbackAck",
}

function Protocol.getRemote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild(name, 15) :: RemoteEvent
end

return Protocol
