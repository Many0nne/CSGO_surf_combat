-- Règles de réapparition d'un joueur (#171, docs/anticheat.md « R1 »), pures et testées par
-- tests/specs/SpawnRules.spec.luau ; SpawnManager les applique.
local SpawnRules = {}

-- Motif d'un refus de RequestSpawn :
-- - "spawning" : un LoadCharacterAsync est déjà en vol pour ce joueur ;
-- - "alive" : il a déjà un personnage en place (vivant, ou corps pas encore détruit) ;
-- - "result" : bannière de fin de round ;
-- - "early" : round actif et mort depuis moins de RESPAWN_DELAY (la réapparition programmée s'en charge).
export type Refusal = "spawning" | "alive" | "result" | "early"

export type Request = {
	spawning: boolean,
	hasCharacter: boolean,
	roundState: string,
	diedAt: number?,
	now: number,
	respawnDelay: number,
}

-- Cette méthode permet de décider si une demande d'apparition du client est acceptée lorsqu'elle arrive ;
-- renvoie le motif du refus, ou nil si elle peut partir.
function SpawnRules.request(r: Request): Refusal?
	if r.spawning then
		return "spawning"
	end
	-- Avant "alive" : pendant CORPSE_HANDOFF_DELAY le corps est encore en place, la demande reste une demande précoce
	if r.roundState == "active" and r.diedAt and r.now - r.diedAt < r.respawnDelay then
		return "early"
	end
	-- Avant "alive" : un personnage arrivé pendant la bannière (réapparition en vol à la fin de manche) n'est repris
	-- qu'en idle, où beforeSpawn démarre la manche suivante (#300) ; repris en "result", aucune manche ne démarrerait
	if r.roundState == "result" then
		return "result"
	end
	if r.hasCharacter then
		return "alive"
	end
	return nil
end

-- Réponse du serveur à chaque RequestSpawn (#219), renvoyée au client par le même remote : "accepted" (chargement
-- lancé ou servi à la fin d'un chargement en vol), "failed" (LoadCharacterAsync en échec), ou le motif du refus ;
-- retryIn = délai restant avant qu'une demande "early" soit acceptée ; live = personnage en place vivant ("alive"),
-- que le client peut reprendre.
export type ReplyStatus = "accepted" | "failed" | Refusal
export type Reply = { status: ReplyStatus, retryIn: number?, live: boolean? }

-- Tous les statuts de réponse, chacun traité par le client (SpawnRequestRules.onReply, test croisé)
SpawnRules.REPLY_STATUSES = { "accepted", "failed", "spawning", "alive", "result", "early" } :: { ReplyStatus }

-- Contexte de la réponse en plus de la demande : joueur revenu du menu, personnage en place vivant
export type ReplyContext = { away: boolean?, live: boolean? }

-- Cette méthode permet de construire la réponse au client lorsqu'une demande vient d'être jugée (refusal nil : acceptée) ;
-- "spawning" non servie (joueur revenu du menu ou bannière de fin) : "result", ce chargement ne lui servira pas.
function SpawnRules.reply(refusal: Refusal?, r: Request, context: ReplyContext?): Reply
	if not refusal then
		return { status = "accepted" }
	end
	if refusal == "spawning" and ((context and context.away) or r.roundState == "result") then
		return { status = "result" }
	end
	if refusal == "early" and r.diedAt then
		return { status = "early", retryIn = math.clamp(r.respawnDelay - (r.now - r.diedAt), 0, r.respawnDelay) }
	end
	if refusal == "alive" then
		return { status = "alive", live = context ~= nil and context.live == true }
	end
	return { status = refusal }
end

-- Cette méthode permet de décider si une demande refusée vient d'un joueur revenu du menu pendant que sa réapparition
-- programmée charge encore (#157) : elle est alors servie à la fin de ce chargement, sauf pendant la bannière de fin.
function SpawnRules.rejoinsInFlight(refusal: Refusal?, away: boolean, roundState: string): boolean
	return refusal == "spawning" and away and roundState ~= "result"
end

-- Cette méthode permet de décider si la réapparition programmée après une mort part lorsqu'elle échoit : jamais
-- par-dessus un personnage vivant ni un autre LoadCharacterAsync en vol.
function SpawnRules.scheduled(spawning: boolean, alive: boolean): boolean
	return not spawning and not alive
end

-- Cette méthode permet de décider si un personnage chargé est gardé lorsqu'il arrive : pas pour un joueur revenu au
-- menu (#157), ni pendant la bannière de fin (#300 : protection d'apparition écoulée avant la manche suivante).
function SpawnRules.keepsArrival(away: boolean, roundState: string): boolean
	return not away and roundState ~= "result"
end

-- Cette méthode permet de savoir si un joueur a un personnage en place dans le jeu (vivant ou corps pas encore
-- détruit) lorsqu'une demande d'apparition arrive.
function SpawnRules.inPlace(character: any): boolean
	return character ~= nil and character.Parent ~= nil
end

-- Cette méthode permet de savoir si un personnage est vivant lorsqu'une réapparition est envisagée : en place dans
-- le jeu, avec un Humanoid à plus de 0 PV (un corps en attente de destruction ne compte pas).
function SpawnRules.isAlive(character: any): boolean
	if not SpawnRules.inPlace(character) then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

return SpawnRules
