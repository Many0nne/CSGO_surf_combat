-- Règles pures des statistiques persistantes (#296) : champs comptés, format sauvegardé (DataStore `PlayerStats_v1`),
-- chargement tolérant et fusion des écarts d'une session dans le profil stocké. Utilisées par le serveur (StatsStore),
-- testées (tests/specs/StatsRules.spec.luau). En fin de fichier : l'attribut lu par la fiche de l'accueil (#301).
--
-- Une session ne réécrit pas le profil entier : elle envoie ses écarts (kills, morts, manches jouées et gagnées depuis
-- la dernière écriture) par lots, et `mergeForSave`, appelée par UpdateAsync, les ajoute à ce qui est stocké. Deux
-- serveurs qui écrivent le même joueur (reconnexion rapide, écriture en retard) additionnent donc leurs écarts au lieu de
-- s'écraser. Chaque lot porte l'id de sa session et un numéro croissant, retenus dans l'enregistrement (`writes`) : un lot
-- renvoyé après une écriture passée mais signalée en échec n'est pas compté deux fois. Un format que cette version ne
-- sait pas réécrire (inconnu, sans `stats`, ou schéma plus récent) n'est jamais touché.
local StatsRules = {}

export type Stats = { kills: number, deaths: number, roundsPlayed: number, roundsWon: number }
export type Field = "kills" | "deaths" | "roundsPlayed" | "roundsWon"
-- Lot d'écarts envoyé par une session : id de session, numéro croissant dans la session, écarts
export type Batch = { session: string, seq: number, delta: Stats }
-- Dernier lot appliqué d'une session
export type WriteMark = { session: string, seq: number }
export type Payload = { schemaVersion: number, stats: { [string]: any }, writes: { WriteMark } }
-- Issue d'une fusion : écarts ajoutés, lot déjà appliqué (rien à écrire), ou format refusé (rien à écrire)
export type MergeStatus = "merged" | "applied" | "refused"

StatsRules.SCHEMA_VERSION = 1
-- Champs comptés, dans l'ordre d'affichage
StatsRules.FIELDS = { "kills", "deaths", "roundsPlayed", "roundsWon" } :: { Field }
-- Sessions dont le dernier lot appliqué est retenu (les plus récentes) : de quoi reconnaître un lot renvoyé
StatsRules.MAX_WRITE_MARKS = 10

-- Cette méthode permet de créer des statistiques à zéro lorsqu'un profil ou un écart de session démarre.
function StatsRules.zero(): Stats
	return { kills = 0, deaths = 0, roundsPlayed = 0, roundsWon = 0 }
end

-- Cette méthode permet de savoir si une valeur relue est un compteur valide (nombre entier positif ou nul, fini).
local function isCount(value: any): boolean
	return type(value) == "number" and value >= 0 and value == math.floor(value) and value < math.huge
end

-- Cette méthode permet de savoir si une valeur relue est d'un format que cette version sait réécrire : absente (nouveau
-- joueur), ou de schéma connu avec une table `stats` de compteurs (un enregistrement sans `stats` n'est pas du jeu).
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
	if type(data.stats) ~= "table" or (data.writes ~= nil and type(data.writes) ~= "table") then
		return false
	end
	for _, field in StatsRules.FIELDS do
		local value = data.stats[field]
		if value ~= nil and not isCount(value) then
			return false
		end
	end
	return true
end

-- Cette méthode permet de lire les compteurs d'un enregistrement lorsqu'il est chargé, fusionné ou vient d'être écrit :
-- champ absent ou invalide → 0.
function StatsRules.read(data: any): Stats
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

-- Cette méthode permet de décider des statistiques stockées et du droit d'écrire lorsque le chargement DataStore se
-- termine : échec, format inconnu ou plus récent → zéros et sauvegarde coupée ; aucune donnée → zéros, écriture permise.
function StatsRules.loadOutcome(ok: boolean, data: any): (Stats, boolean)
	if not (ok and isWritable(data)) then
		return StatsRules.zero(), false
	end
	return StatsRules.read(data), true
end

-- Cette méthode permet d'ajouter 1 à un champ d'écart lorsqu'un kill, une mort ou une fin de manche est enregistré.
function StatsRules.add(delta: Stats, field: Field)
	delta[field] += 1
end

-- Cette méthode permet de savoir si un écart ne contient rien lorsqu'une sauvegarde est envisagée (joueur resté au menu).
function StatsRules.isEmpty(delta: Stats): boolean
	for _, field in StatsRules.FIELDS do
		if delta[field] ~= 0 then
			return false
		end
	end
	return true
end

-- Cette méthode permet d'additionner deux statistiques champ par champ (nouvelle table) lorsqu'on affiche le profil
-- stocké plus les écarts pas encore écrits.
function StatsRules.sum(a: Stats, b: Stats): Stats
	local total = StatsRules.zero()
	for _, field in StatsRules.FIELDS do
		total[field] = a[field] + b[field]
	end
	return total
end

-- Cette méthode permet de relire les marques de lots appliqués d'un enregistrement lorsqu'il est fusionné : seules les
-- entrées bien formées, dans l'ordre (la plus récente en dernier).
local function readMarks(data: any): { WriteMark }
	local marks: { WriteMark } = {}
	if type(data) == "table" and type(data.writes) == "table" then
		for _, mark in ipairs(data.writes) do
			if type(mark) == "table" and type(mark.session) == "string" and isCount(mark.seq) then
				table.insert(marks, { session = mark.session, seq = mark.seq })
			end
		end
	end
	return marks
end

-- Cette méthode permet de calculer la valeur écrite par UpdateAsync lorsqu'une session envoie un lot : stocké plus
-- écarts (champs inconnus recopiés), ou nil si le lot est déjà appliqué ou le format refusé. Pure : rejouable.
function StatsRules.mergeForSave(old: any, batch: Batch): (Payload?, MergeStatus)
	if not isWritable(old) then
		return nil, "refused"
	end
	local marks = readMarks(old)
	for i, mark in marks do
		if mark.session == batch.session then
			if mark.seq >= batch.seq then
				return nil, "applied"
			end
			table.remove(marks, i)
			break
		end
	end
	table.insert(marks, { session = batch.session, seq = batch.seq })
	while #marks > StatsRules.MAX_WRITE_MARKS do
		table.remove(marks, 1)
	end
	-- Champs inconnus de cette version (enregistrement ou stats) recopiés tels quels
	local payload: { [string]: any } = {}
	local stats: { [string]: any } = {}
	if type(old) == "table" then
		for key, value in old do
			payload[key] = value
		end
		for key, value in old.stats do
			stats[key] = value
		end
	end
	local stored = StatsRules.read(old)
	for _, field in StatsRules.FIELDS do
		stats[field] = stored[field] + batch.delta[field]
	end
	payload.schemaVersion = StatsRules.SCHEMA_VERSION
	payload.stats = stats
	payload.writes = marks
	return payload :: Payload, "merged"
end

-- Lecture côté client (#301) : attribut informatif du Player, posé par le serveur (StatsStore) une fois le profil stocké
-- lu, puis à chaque kill, mort ou fin de manche ; jamais relu par le serveur. Absent : pas (encore) chargé. Mise en
-- forme de la fiche : HUDRules.statsView (client).
StatsRules.ATTRIBUTE = "PlayerStats"
-- Cette méthode permet d'écrire les compteurs dans l'attribut du Player lorsque le serveur les publie : entiers séparés
-- par des virgules, dans l'ordre de FIELDS (« 12,3,5,1 ») ; « %.0f » et non « %d », qui rendrait négatif un compteur
-- de 2^63 ou plus (relu alors comme non chargé).
function StatsRules.encode(stats: Stats): string
	local parts = table.create(#StatsRules.FIELDS)
	for i, field in StatsRules.FIELDS do
		parts[i] = string.format("%.0f", stats[field])
	end
	return table.concat(parts, ",")
end

-- Cette méthode permet de relire l'attribut du Player lorsque la fiche se remplit ; nil (non chargé) si l'attribut est
-- absent ou mal formé, jamais des zéros par défaut.
function StatsRules.decode(value: any): Stats?
	if type(value) ~= "string" then
		return nil
	end
	local parts = string.split(value, ",")
	if #parts ~= #StatsRules.FIELDS then
		return nil
	end
	local stats = StatsRules.zero()
	for i, field in StatsRules.FIELDS do
		local count = if string.match(parts[i], "^%d+$") then tonumber(parts[i]) else nil
		if not (count and isCount(count)) then
			return nil
		end
		stats[field] = count
	end
	return stats
end

return StatsRules
