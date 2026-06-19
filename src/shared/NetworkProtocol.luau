local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = {}

Protocol.Names = {
	-- Combat (créés par init.server)
	MELEE_DAMAGE   = "MeleeDamage",
	HITSCAN_DAMAGE = "HitscanDamage",
	-- Jeu
	REQUEST_SPAWN  = "RequestSpawn",
	ROUND_STATE    = "RoundState",
	SCORE_UPDATE   = "ScoreUpdate",
	ROUND_RESULT   = "RoundResult",
	PLAYER_DIED    = "PlayerDied",
}

function Protocol.getRemote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild(name, 15) :: RemoteEvent
end

return Protocol
