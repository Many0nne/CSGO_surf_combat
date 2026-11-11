-- Règles pures de la demande d'apparition du client (#219), testées par tests/specs/SpawnRequestRules.spec.luau ;
-- GameStateController les applique. Le serveur répond à chaque RequestSpawn par le même remote (SpawnRules.reply) :
-- accepté, refusé avec son motif, ou chargement échoué. Sans réponse, le client renvoie sa demande (le serveur la refuse
-- sans créer de second personnage) ; dans tous les cas il quitte SPAWNING en un temps borné, au pire vers le menu.
local SpawnRequestRules = {}

-- Délais (s), à régler ici
SpawnRequestRules.TICK = 0.25 -- cadence de la surveillance d'une demande
SpawnRequestRules.REPLY_TIMEOUT = 3 -- sans réponse depuis l'envoi : renvoi
SpawnRequestRules.MAX_UNANSWERED = 3 -- envois sans réponse avant l'abandon
SpawnRequestRules.LOAD_TIMEOUT = 15 -- demande acceptée, personnage pas arrivé : abandon
SpawnRequestRules.GIVE_UP_AFTER = 30 -- borne des envois (+ LOAD_TIMEOUT si acceptée juste avant)
-- Écart minimal entre deux envois : la garde du serveur (RemoteGuard.RULES.RequestSpawn) en admet 1 par seconde
SpawnRequestRules.MIN_RESEND = 1.2
SpawnRequestRules.RESULT_RETRY = 1.5 -- bannière de fin (6 s) : renvoi à ce rythme jusqu'au round suivant
SpawnRequestRules.ALIVE_RETRY = 1.2 -- personnage encore en place côté serveur (corps) : renvoi
SpawnRequestRules.FAILED_RETRY = 1.5 -- LoadCharacterAsync échoué côté serveur : renvoi
SpawnRequestRules.EARLY_MARGIN = 0.1 -- marge ajoutée au délai restant annoncé par le serveur
-- Redemande en DEAD (#245) : borne stricte, chargement accepté compris (le round tourne, le joueur regarde l'écran
-- de mort) ; un personnage arrivé après l'abandon est détruit par le serveur (LeaveRound)
SpawnRequestRules.DEAD_GIVE_UP_AFTER = 6

export type Attempt = {
	startedAt: number,
	lastSendAt: number?,
	unanswered: number,
	acceptedAt: number?,
	retryAt: number?,
	giveUpAfter: number,
	strict: boolean,
}

-- Attente de la réapparition programmée en DEAD (#245) : redemande (attempt) seulement après le délai de réapparition
-- et sa marge sans nouveau personnage
export type DeadWatch = {
	diedAt: number,
	attempt: Attempt?,
}

export type TickAction = "wait" | "send" | "giveUp"
export type ReplyAction = "wait" | "adopt"

-- Cette méthode permet de créer le suivi d'une demande d'apparition lorsque le joueur clique JOUER, ou que la
-- réapparition programmée tarde (#245 : strictBound, borne totale qui ne laisse pas LOAD_TIMEOUT au chargement).
function SpawnRequestRules.new(now: number, strictBound: number?): Attempt
	return {
		startedAt = now,
		lastSendAt = nil,
		unanswered = 0,
		acceptedAt = nil,
		retryAt = nil,
		giveUpAfter = strictBound or SpawnRequestRules.GIVE_UP_AFTER,
		strict = strictBound ~= nil,
	}
end

-- Cette méthode permet de noter qu'une demande vient de partir au serveur lorsque le client l'envoie (premier envoi
-- ou renvoi) : une nouvelle réponse est attendue.
function SpawnRequestRules.noteSent(attempt: Attempt, now: number)
	attempt.lastSendAt = now
	attempt.unanswered += 1
	attempt.retryAt = nil
end

-- Cette méthode permet de traiter une réponse du serveur (SpawnRules.Reply) arrivée en SPAWNING : attendre le
-- personnage, reprendre celui déjà en jeu ("alive" et personnage local vivant), ou programmer un renvoi.
function SpawnRequestRules.onReply(attempt: Attempt, reply: any, now: number, hasLiveCharacter: boolean): ReplyAction
	if type(reply) ~= "table" or type(reply.status) ~= "string" then
		return "wait"
	end
	attempt.unanswered = 0
	local status = reply.status
	if status == "accepted" or status == "spawning" then
		attempt.acceptedAt = attempt.acceptedAt or now
		attempt.retryAt = nil
		return "wait"
	end
	-- Vivant pour le serveur (live) et pour le client : jamais un corps dont la mort n'est pas encore répliquée
	if status == "alive" and reply.live == true and hasLiveCharacter then
		return "adopt"
	end
	local delay
	if status == "alive" then
		delay = SpawnRequestRules.ALIVE_RETRY
	elseif status == "result" then
		delay = SpawnRequestRules.RESULT_RETRY
	elseif status == "early" then
		local retryIn = if type(reply.retryIn) == "number" then reply.retryIn else 0
		delay = math.clamp(retryIn, 0, SpawnRequestRules.GIVE_UP_AFTER) + SpawnRequestRules.EARLY_MARGIN
	elseif status == "failed" then
		delay = SpawnRequestRules.FAILED_RETRY
	else
		-- Motif inconnu : rien à faire de plus, les délais bornent l'attente
		return "wait"
	end
	attempt.acceptedAt = nil
	attempt.retryAt = math.max(now + delay, (attempt.lastSendAt or now) + SpawnRequestRules.MIN_RESEND)
	return "wait"
end

-- Cette méthode permet de décider, à chaque pas de la surveillance d'une demande en SPAWNING, s'il faut attendre,
-- (r)envoyer la demande ou abandonner (retour au menu) ; borné par giveUpAfter + LOAD_TIMEOUT (giveUpAfter si strict).
function SpawnRequestRules.onTick(attempt: Attempt, now: number): TickAction
	if attempt.strict and now - attempt.startedAt >= attempt.giveUpAfter then
		return "giveUp"
	end
	-- Acceptée : le chargement a toujours LOAD_TIMEOUT, même accepté juste avant GIVE_UP_AFTER
	if attempt.acceptedAt then
		return if now - attempt.acceptedAt >= SpawnRequestRules.LOAD_TIMEOUT then "giveUp" else "wait"
	end
	if now - attempt.startedAt >= attempt.giveUpAfter then
		return "giveUp"
	end
	if attempt.retryAt then
		return if now >= attempt.retryAt then "send" else "wait"
	end
	local lastSendAt = attempt.lastSendAt
	if not lastSendAt then
		-- Remote pas encore résolu : envoi dès qu'il l'est, abandon s'il ne vient pas
		local bound = SpawnRequestRules.REPLY_TIMEOUT * SpawnRequestRules.MAX_UNANSWERED
		return if now - attempt.startedAt >= bound then "giveUp" else "send"
	end
	if now - lastSendAt >= SpawnRequestRules.REPLY_TIMEOUT then
		return if attempt.unanswered >= SpawnRequestRules.MAX_UNANSWERED then "giveUp" else "send"
	end
	return "wait"
end

-- Cette méthode permet de savoir si l'attente de la réapparition continue lorsque l'état client change : seulement en
-- DEAD (personnage revenu → IN_ROUND, round idle ou départ → MENU, fin de round → RESULT l'annulent).
function SpawnRequestRules.keepsDeadWatch(state: string): boolean
	return state == "DEAD"
end

-- Cette méthode permet de commencer l'attente de la réapparition programmée lorsque le joueur local passe en DEAD.
function SpawnRequestRules.newDeadWatch(now: number): DeadWatch
	return { diedAt = now, attempt = nil }
end

-- Cette méthode permet de décider, à chaque pas en DEAD, s'il faut attendre la réapparition du serveur, redemander
-- l'apparition (passé waitFor = RESPAWN_DELAY + marge, puis comme une demande, borne DEAD_GIVE_UP_AFTER) ou abandonner.
function SpawnRequestRules.onDeadTick(watch: DeadWatch, now: number, waitFor: number): TickAction
	if not watch.attempt then
		if now - watch.diedAt < waitFor then
			return "wait"
		end
		watch.attempt = SpawnRequestRules.new(now, SpawnRequestRules.DEAD_GIVE_UP_AFTER)
	end
	return SpawnRequestRules.onTick(watch.attempt :: Attempt, now)
end

return SpawnRequestRules
