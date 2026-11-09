-- Repérage des personnages de bots (#139) : un bot n'a pas de Player, son personnage porte le tag TAG et l'id de
-- participant (négatif) en attribut. Le serveur les marque à l'apparition, les clients les retrouvent ainsi (corps,
-- caméra de mort vers un bot tueur).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local BotCharacters = {}

BotCharacters.TAG = "BotCharacter"
BotCharacters.ID_ATTRIBUTE = "ParticipantId"

-- Cette méthode permet de marquer le personnage d'un bot lorsqu'il apparaît (serveur).
function BotCharacters.mark(character: Model, participantId: number)
	character:SetAttribute(BotCharacters.ID_ATTRIBUTE, participantId)
	CollectionService:AddTag(character, BotCharacters.TAG)
end

-- Cette méthode permet de retrouver le personnage en jeu d'un bot par son id de participant lorsqu'une mort le
-- désigne ; nil s'il n'est pas (ou plus) en jeu.
function BotCharacters.find(participantId: number): Model?
	for _, inst in CollectionService:GetTagged(BotCharacters.TAG) do
		if inst:IsA("Model") and inst.Parent and inst:GetAttribute(BotCharacters.ID_ATTRIBUTE) == participantId then
			return inst
		end
	end
	return nil
end

-- Cette méthode permet de retrouver le personnage d'un participant (joueur ou bot) par son id lorsqu'une mort le
-- désigne côté client.
function BotCharacters.characterOf(participantId: number, isBot: boolean): Model?
	if isBot then
		return BotCharacters.find(participantId)
	end
	local player = Players:GetPlayerByUserId(participantId)
	return player and player.Character
end

-- Cette méthode permet de lister tous les personnages en jeu (joueurs et bots) lorsqu'un rayon doit les ignorer.
function BotCharacters.allCharacters(): { Model }
	local list: { Model } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for _, inst in CollectionService:GetTagged(BotCharacters.TAG) do
		if inst:IsA("Model") then
			table.insert(list, inst)
		end
	end
	return list
end

return BotCharacters
