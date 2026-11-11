-- Règles pures de la synchro de position des personnages (#75) : le mouvement est fait par le client sur une racine
-- ancrée, il envoie sa position au serveur (CharacterSync), qui la valide, la pose sur la racine et la relaie aux
-- autres clients ; ceux-ci l'affichent avec un léger retard, interpolée entre deux paquets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MathRules = require(ReplicatedStorage.Shared.MathRules)
local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)

local CharacterSyncRules = {}

-- Intervalle entre deux envois du client (s).
CharacterSyncRules.SEND_INTERVAL = 1 / MovementConfig.NET_SYNC_RATE
-- Retard d'affichage des autres joueurs (s) : deux paquets d'avance pour interpoler malgré la gigue.
CharacterSyncRules.INTERP_DELAY = 2 * CharacterSyncRules.SEND_INTERVAL
-- Paquets gardés par joueur pour l'interpolation (une demi-seconde à 20 Hz).
CharacterSyncRules.BUFFER_SIZE = 10
-- Au-delà de cette coordonnée (studs), une position est rejetée (valeur absurde ou forgée).
CharacterSyncRules.MAX_COORD = 1e5
-- Seau de distance (#172) : true = un déplacement refusé est corrigé (client renvoyé à sa dernière position acceptée) ;
-- false = journal seul (violation comptée, déplacement appliqué), à remettre si des joueurs honnêtes sont corrigés.
CharacterSyncRules.ENFORCE_MOVEMENT = true

export type Snapshot = { t: number, pos: Vector3, yaw: number }

-- Cette méthode permet de vérifier la forme d'un paquet client lorsqu'il arrive : un Vector3 et un angle finis, de
-- valeur absolue au plus MAX_COORD.
function CharacterSyncRules.isWellFormed(pos: any, yaw: any): boolean
	return MathRules.isBoundedVector3(pos, CharacterSyncRules.MAX_COORD)
		and MathRules.isBounded(yaw, CharacterSyncRules.MAX_COORD)
end

-- Seau de distance d'un joueur (#172, docs/anticheat.md « D1 ») : `stored` = studs mis de côté (au plus MAX_DELTA_POS),
-- `lastAt` = heure serveur du dernier paquet jugé (accepté ou refusé).
export type MoveBudget = { stored: number, lastAt: number }

-- Cette méthode permet de créer le seau de distance d'un personnage lorsque le serveur commence à suivre sa position
-- (apparition) : plein, pour qu'un premier paquet tardif ne soit pas refusé.
function CharacterSyncRules.newBudget(now: number): MoveBudget
	return { stored = MovementConfig.MAX_DELTA_POS, lastAt = now }
end

-- Cette méthode permet de décider si un déplacement annoncé est possible lorsque le serveur reçoit une position : le
-- budget du paquet est le seau plus MAX_SPEED_SERVER × durée depuis le paquet précédent, durée plafonnée à
-- MAX_SILENCE ; un déplacement accepté le consomme, le reste (au plus MAX_DELTA_POS) est gardé pour les paquets
-- suivants. Un refus ne consomme rien, mais le temps écoulé est compté : se taire ou se faire refuser n'accumule pas.
function CharacterSyncRules.tryMove(budget: MoveBudget, lastPos: Vector3, newPos: Vector3, now: number): boolean
	local elapsed = math.clamp(now - budget.lastAt, 0, MovementConfig.MAX_SILENCE)
	local allowance = budget.stored + MovementConfig.MAX_SPEED_SERVER * elapsed
	budget.lastAt = math.max(budget.lastAt, now)
	local distance = (newPos - lastPos).Magnitude
	local accepted = distance <= allowance
	if accepted then
		allowance -= distance
	end
	budget.stored = math.min(allowance, MovementConfig.MAX_DELTA_POS)
	return accepted
end

-- Cette méthode permet de savoir si un paquet a été envoyé avant que le client n'applique la dernière correction
-- lorsqu'il arrive (ack = numéro de la dernière correction appliquée, joint à chaque paquet) : un tel paquet part
-- d'une position que le serveur a déjà refusée, il est ignoré sans être jugé, ce qui évite une boucle de corrections.
-- requiredAck reste en place après l'accusé : un paquet plus ancien arrivé en retard (non fiable) est aussi ignoré.
function CharacterSyncRules.awaitsAck(requiredAck: number, ack: number): boolean
	return ack < requiredAck
end

-- Cette méthode permet au client de décider s'il applique une correction du serveur lorsqu'elle arrive : position
-- valide, numéro plus récent que la dernière correction appliquée (ack), et pour le personnage local actuel (target).
function CharacterSyncRules.acceptsCorrection(char: any, pos: any, seq: any, target: Model?, ack: number): boolean
	return typeof(pos) == "Vector3" and type(seq) == "number" and seq > ack and target ~= nil and char == target
end

-- Cette méthode permet de lire le cap horizontal (rad, autour de Y) d'une orientation lorsque le client l'envoie.
function CharacterSyncRules.yawOf(look: Vector3): number
	return math.atan2(-look.X, -look.Z)
end

-- Cette méthode permet de ranger un paquet dans le tampon d'un joueur lorsqu'il arrive : les paquets en retard
-- (horodatage antérieur au dernier, possible en non fiable) sont ignorés, et le tampon garde les BUFFER_SIZE derniers.
function CharacterSyncRules.push(buffer: { Snapshot }, snap: Snapshot)
	local last = buffer[#buffer]
	if last and snap.t <= last.t then
		return
	end
	table.insert(buffer, snap)
	while #buffer > CharacterSyncRules.BUFFER_SIZE do
		table.remove(buffer, 1)
	end
end

-- Cette méthode permet de calculer la position et le cap affichés d'un autre joueur à l'instant renderTime lorsque le
-- client dessine une frame : interpolation entre les deux paquets qui l'encadrent, le plus ancien avant le tampon,
-- le dernier reçu après (sans extrapoler). nil si le tampon est vide.
function CharacterSyncRules.sample(buffer: { Snapshot }, renderTime: number): (Vector3?, number?)
	local count = #buffer
	if count == 0 then
		return nil, nil
	end
	if renderTime <= buffer[1].t then
		return buffer[1].pos, buffer[1].yaw
	end
	for i = 1, count - 1 do
		local a, b = buffer[i], buffer[i + 1]
		if renderTime <= b.t then
			local alpha = (renderTime - a.t) / (b.t - a.t)
			return a.pos + (b.pos - a.pos) * alpha, a.yaw + MathRules.angleDelta(a.yaw, b.yaw) * alpha
		end
	end
	return buffer[count].pos, buffer[count].yaw
end

return CharacterSyncRules
