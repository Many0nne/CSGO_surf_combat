-- Registre des participants au round (#137) : un joueur (id = UserId) ou un bot (id négatif, sans Player).
-- RoundManager, Validator et init.server ne raisonnent qu'en participants ; un joueur y entre par fromPlayer.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ParticipantRules = require(ReplicatedStorage.Shared.ParticipantRules)

export type Participant = {
	id: number,
	name: string,
	isBot: boolean,
	player: Player?, -- nil pour un bot
	character: Model?, -- personnage d'un bot ; celui d'un joueur se lit sur player.Character
}

local Participants = {}

local byId: { [number]: Participant } = {}
local byPlayer: { [Player]: Participant } = {}

-- Cette méthode permet de retrouver (ou d'inscrire) le participant d'un joueur lorsqu'il arrive ou agit.
function Participants.fromPlayer(player: Player): Participant
	local existing = byPlayer[player]
	if existing then
		return existing
	end
	local participant: Participant = { id = player.UserId, name = player.Name, isBot = false, player = player }
	byPlayer[player] = participant
	byId[participant.id] = participant
	return participant
end

-- Cette méthode permet d'inscrire un bot sous le premier id négatif libre lorsqu'il entre dans le round.
function Participants.addBot(name: string): Participant
	local participant: Participant = { id = ParticipantRules.nextBotId(byId), name = name, isBot = true }
	byId[participant.id] = participant
	return participant
end

-- Cette méthode permet de désinscrire un participant lorsqu'il quitte le jeu (joueur parti, bot retiré).
function Participants.remove(participant: Participant)
	if byId[participant.id] == participant then
		byId[participant.id] = nil
	end
	if participant.player and byPlayer[participant.player] == participant then
		byPlayer[participant.player] = nil
	end
end

-- Cette méthode permet de savoir si un participant est encore inscrit lorsqu'une action différée le concerne (respawn).
function Participants.isRegistered(participant: Participant): boolean
	return byId[participant.id] == participant
end

-- Cette méthode permet de retrouver un participant inscrit par son id lorsqu'un coup mémorisé désigne son auteur.
function Participants.get(id: number): Participant?
	return byId[id]
end

-- Cette méthode permet de lire le personnage actuel d'un participant lorsqu'on a besoin de sa position ou de son arme.
function Participants.characterOf(participant: Participant): Model?
	if participant.player then
		return participant.player.Character
	end
	return participant.character
end

-- Cette méthode permet d'associer son personnage à un bot lorsqu'il apparaît (nil à sa disparition).
function Participants.setCharacter(participant: Participant, character: Model?)
	assert(participant.isBot, "le personnage d'un joueur se lit sur player.Character")
	participant.character = character
end

-- Cette méthode permet de retrouver le participant inscrit qui possède un personnage lorsqu'une touche le vise ; nil
-- pour un personnage sans participant (cible du helper de playtest, joueur déjà parti dont le corps reste en place).
function Participants.fromCharacter(character: Instance): Participant?
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		return byPlayer[player]
	end
	for _, participant in byId do
		if participant.isBot and participant.character == character then
			return participant
		end
	end
	return nil
end

-- Cette méthode permet de parcourir tous les participants inscrits lorsqu'on agit sur chacun (fin de round).
function Participants.all(): { Participant }
	local list = {}
	for _, participant in byId do
		table.insert(list, participant)
	end
	return list
end

return Participants
