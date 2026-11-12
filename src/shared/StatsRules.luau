-- Règles pures des statistiques persistantes (#296) : champs comptés, format sauvegardé (DataStore `PlayerStats_v1`),
-- chargement tolérant et fusion des écarts d'une session dans le profil stocké. Utilisées par le serveur (StatsStore),
-- testées (tests/specs/StatsRules.spec.luau).
--
-- Une session ne garde pas le profil entier à réécrire, mais ses écarts (kills, morts, manches jouées et gagnées depuis
-- la dernière écriture) : `mergeForSave`, appelée par UpdateAsync, les ajoute à ce qui est stocké au moment de
-- l'écriture. Deux serveurs qui écrivent le même joueur (reconnexion rapide, écriture en retard) additionnent donc
-- leurs écarts au lieu de s'écraser. Un format que cette version ne sait pas réécrire (inconnu, ou schéma plus récent)
-- n'est jamais touché.
local StatsRules = {}

export type Stats = { kills: number, deaths: number, roundsPlayed: number, roundsWon: number }
export type Field = "kills" | "deaths" | "roundsPlayed" | "roundsWon"
export type Payload = { schemaVersion: number, stats: { [string]: any } }

StatsRules.SCHEMA_VERSION = 1
-- Champs comptés, dans l'ordre d'affichage
StatsRules.FIELDS = { "kills", "deaths", "roundsPlayed", "roundsWon" } :: { Field }

-- Cette méthode permet de créer des statistiques à zéro lorsqu'un profil ou un écart de session démarre.
function StatsRules.zero(): Stats
	return { kills = 0, deaths = 0, roundsPlayed = 0, roundsWon = 0 }
end

-- Cette méthode permet de savoir si une valeur relue est un compteur valide (nombre entier positif ou nul, fini).
local function isCount(value: any): boolean
	return type(value) == "number" and value >= 0 and value == math.floor(value) and value < math.huge
end

-- Cette méthode permet de savoir si une valeur relue du DataStore est d'un format que cette version sait réécrire :
-- absente (nouveau joueur), ou table de schéma connu (pas plus récent) avec une table `stats` dont chaque champ connu est
-- un compteur ou absent. Un enregistrement sans `stats` n'a pas été écrit par ce jeu : on n'y touche pas.
local function isWritable(data: any): boolean
	if data == nil then
		return true
	end
	if type(data) ~= "table" then
		return false
	end
	local version = data.schemaVersion
	if version ~= nil and (type(version) ~= "number" or version > StatsRules.SCHEMA_VERSION) then
		return false
	end
	local stats = data.stats
	if type(stats) ~= "table" then
		return false
	end
	for _, field in StatsRules.FIELDS do
		local value = stats[field]
		if value ~= nil and not isCount(value) then
			return false
		end
	end
	return true
end
StatsRules.isWritable = isWritable

-- Cette méthode permet de lire les compteurs d'un enregistrement réécrivable lorsqu'il est chargé ou fusionné : champ
-- absent → 0 (champ ajouté depuis l'écriture).
local function readStats(data: any): Stats
	local stats = StatsRules.zero()
	if type(data) == "table" and type(data.stats) == "table" then
		for _, field in StatsRules.FIELDS do
			local value = data.stats[field]
			if isCount(value) then
				stats[field] = value
			end
		end
	end
	return stats
end

-- Cette méthode permet de décider des statistiques stockées, du droit d'écrire et de leur fiabilité lorsque le chargement
-- DataStore se termine : format inconnu ou plus récent → zéros et sauvegarde coupée ; aucune donnée → zéros, écriture
-- permise. Lecture en échec → zéros non fiables, écriture permise : la fusion relit ce qui est stocké et refuse elle-même
-- un format inconnu, une sauvegarde ne peut donc rien écraser.
function StatsRules.loadOutcome(ok: boolean, data: any): (Stats, boolean, boolean)
	if not ok then
		return StatsRules.zero(), true, false
	end
	if not isWritable(data) then
		return StatsRules.zero(), false, true
	end
	return readStats(data), true, true
end

-- Cette méthode permet d'ajouter `amount` (1 par défaut) à un champ d'écart lorsqu'un kill, une mort ou une fin de
-- manche est enregistré.
function StatsRules.add(delta: Stats, field: Field, amount: number?)
	delta[field] += amount or 1
end

-- Cette méthode permet de savoir si un écart de session ne contient rien lorsqu'une sauvegarde est envisagée : rien à
-- écrire (joueur resté au menu).
function StatsRules.isEmpty(delta: Stats): boolean
	for _, field in StatsRules.FIELDS do
		if delta[field] ~= 0 then
			return false
		end
	end
	return true
end

-- Cette méthode permet d'additionner deux statistiques champ par champ (nouvelle table) lorsqu'on affiche le profil
-- stocké plus les écarts pas encore écrits, ou qu'on remet un écart non écrit dans celui de la session.
function StatsRules.sum(a: Stats, b: Stats): Stats
	local total = StatsRules.zero()
	for _, field in StatsRules.FIELDS do
		total[field] = a[field] + b[field]
	end
	return total
end

-- Cette méthode permet de calculer la valeur écrite par UpdateAsync lorsqu'une session sauvegarde ses écarts : compteurs
-- stockés plus écarts, champs inconnus de cette version recopiés tels quels ; nil (écriture annulée) si le format stocké
-- n'est pas réécrivable. Pure : UpdateAsync peut l'appeler plusieurs fois.
function StatsRules.mergeForSave(old: any, delta: Stats): Payload?
	if not isWritable(old) then
		return nil
	end
	local stats: { [string]: any } = {}
	if type(old) == "table" then
		for key, value in old.stats do
			stats[key] = value
		end
	end
	local stored = readStats(old)
	for _, field in StatsRules.FIELDS do
		stats[field] = stored[field] + delta[field]
	end
	return { schemaVersion = StatsRules.SCHEMA_VERSION, stats = stats }
end

-- Cette méthode permet de relire les compteurs de la valeur que UpdateAsync vient d'écrire lorsqu'une sauvegarde
-- réussit : ce sont les nouvelles statistiques stockées du joueur.
function StatsRules.storedStats(data: any): Stats
	return readStats(data)
end

return StatsRules
