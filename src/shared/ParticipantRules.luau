-- Règles pures de l'identité d'un participant au round, joueur ou bot (#137) : préfixe affiché, ids des bots,
-- comptage dans les stats persistantes. Partagées client/serveur, testées (tests/specs/ParticipantRules.spec.luau).
local ParticipantRules = {}

-- Préfixe affiché devant le nom d'un bot dans le kill feed, le classement et l'écran de mort (décision 5 de #133)
ParticipantRules.BOT_PREFIX = "BOT"

-- Cette méthode permet de savoir si un id de participant désigne un bot lorsqu'il arrive sans autre information :
-- les joueurs ont un UserId positif, les bots un id négatif.
function ParticipantRules.isBotId(id: number): boolean
	return id < 0
end

-- Cette méthode permet de choisir l'id d'un nouveau bot lorsqu'il entre dans le round : le premier id négatif libre
-- (-1, -2…), pour que les ids restent petits et ne croisent jamais un UserId.
function ParticipantRules.nextBotId(used: { [number]: any }): number
	local id = -1
	while used[id] ~= nil do
		id -= 1
	end
	return id
end

-- Cette méthode permet de composer le nom affiché d'un participant lorsqu'il est écrit en texte brut (« BOT Marcel »).
function ParticipantRules.displayName(name: string, isBot: boolean?): string
	return if isBot then ParticipantRules.BOT_PREFIX .. " " .. name else name
end

-- Cette méthode permet de savoir si une mort compte dans les stats persistantes lorsqu'elle arrive (décision 6 de #133) :
-- seulement pour un joueur, et pas si un bot l'a tué ; une mort sans tueur (chute) compte.
function ParticipantRules.countsInStats(victimIsBot: boolean, killerIsBot: boolean?): boolean
	return not victimIsBot and killerIsBot ~= true
end

-- Cette méthode permet de savoir si un kill compte dans les stats persistantes du tueur lorsqu'une mort est attribuée :
-- même règle que la mort (countsInStats), et il faut un tueur joueur (sans tueur ou tueur bot : rien).
function ParticipantRules.killCountsInStats(victimIsBot: boolean, killerIsBot: boolean?): boolean
	return killerIsBot == false and ParticipantRules.countsInStats(victimIsBot, killerIsBot)
end

return ParticipantRules
