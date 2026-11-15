-- Règles pures de la monnaie du jeu, les crédits (#391) : montants valides, solde de départ, format sauvegardé (DataStore
-- `PlayerWallet_v1`), chargement tolérant, fusion des écarts d'une session, attribut lu par le client et affichage.
-- Utilisées par le serveur (WalletStore) et le client (LocalWallet), testées (tests/specs/WalletRules.spec.luau).
--
-- Même principe que les statistiques (StatsRules) : une session ne réécrit pas le solde, elle envoie ses écarts (crédits
-- gagnés moins crédits dépensés depuis la dernière écriture) par lots numérotés, et `mergeForSave`, appelée par
-- UpdateAsync, les ajoute au solde stocké. Deux serveurs qui écrivent le même joueur additionnent leurs écarts ; un lot
-- renvoyé après une écriture passée mais signalée en échec n'est pas compté deux fois (`writes`). Un solde stocké ne
-- descend jamais sous 0 : deux serveurs qui dépensent en même temps le même solde (reconnexion rapide) le ramènent à 0.
local WalletRules = {}

-- Lot d'écarts envoyé par une session : id de session, numéro croissant dans la session, écart signé
export type Batch = { session: string, seq: number, delta: number }
export type WriteMark = { session: string, seq: number }
export type Payload = { schemaVersion: number, credits: number, writes: { WriteMark } }
-- Issue d'une fusion : écart ajouté, lot déjà appliqué (rien à écrire), ou format refusé (rien à écrire)
export type MergeStatus = "merged" | "applied" | "refused"

WalletRules.SCHEMA_VERSION = 1
-- Nom affiché de la monnaie (ShopCatalog.CURRENCY le reprend)
WalletRules.CURRENCY = "CRÉDITS"
-- Jeton du crédit (UIKit.creditIcon, étiquettes de la vitrine du shop) : jeton en laiton frappé d'un réticule, en
-- couleur (pas teinté). assets/ui/credits/jeton_credit.png (tools/ui/make_credit_icon.py, Decal 103980310535300 ;
-- ci-dessous l'id de l'image contenue dans le Decal)
WalletRules.ICON = "rbxassetid://133766247138455"
-- Solde d'un nouveau joueur
WalletRules.STARTING_BALANCE = 0
-- Plafond du solde : au-delà, un gain est écrêté (garde-fou contre un montant aberrant, loin de tout gain prévu)
WalletRules.MAX_BALANCE = 999_999_999
-- Sessions dont le dernier lot appliqué est retenu (les plus récentes) : de quoi reconnaître un lot renvoyé
WalletRules.MAX_WRITE_MARKS = 10

-- Cette méthode permet de savoir si une valeur est un solde valide (entier positif ou nul, fini, sous le plafond)
-- lorsqu'un enregistrement est relu ou un attribut décodé.
function WalletRules.isBalance(value: any): boolean
	return type(value) == "number" and value >= 0 and value <= WalletRules.MAX_BALANCE and value == math.floor(value)
end

-- Cette méthode permet de savoir si un montant à ajouter ou retirer est valide (entier strictement positif, fini, sous
-- le plafond) lorsqu'un système serveur demande un gain ou une dépense.
function WalletRules.isAmount(value: any): boolean
	return WalletRules.isBalance(value) and value > 0
end

-- Cette méthode permet de savoir si un numéro de lot relu est valide (entier positif ou nul, fini).
local function isSeq(value: any): boolean
	return type(value) == "number" and value >= 0 and value == math.floor(value) and value < math.huge
end

-- Cette méthode permet de ramener un solde dans [0, MAX_BALANCE] lorsqu'un écart est appliqué.
function WalletRules.clamp(balance: number): number
	return math.clamp(balance, 0, WalletRules.MAX_BALANCE)
end

-- Cette méthode permet de savoir si une valeur relue est d'un format que cette version sait réécrire : absente (nouveau
-- joueur), ou de schéma connu avec un solde valide (un enregistrement sans `credits` n'est pas du jeu).
local function isWritable(data: any): boolean
	if data == nil then
		return true
	end
	if type(data) ~= "table" then
		return false
	end
	local version = data.schemaVersion
	if version ~= nil and (type(version) ~= "number" or version > WalletRules.SCHEMA_VERSION) then
		return false
	end
	if data.writes ~= nil and type(data.writes) ~= "table" then
		return false
	end
	return WalletRules.isBalance(data.credits)
end

-- Cette méthode permet de lire le solde d'un enregistrement lorsqu'il est chargé, fusionné ou vient d'être écrit :
-- absent (nouveau joueur) ou invalide → solde de départ.
function WalletRules.read(data: any): number
	if type(data) == "table" and WalletRules.isBalance(data.credits) then
		return data.credits
	end
	return WalletRules.STARTING_BALANCE
end

-- Cette méthode permet de décider du solde stocké et du droit d'écrire lorsque le chargement DataStore se termine :
-- échec, format inconnu ou plus récent → solde de départ et sauvegarde coupée ; aucune donnée → départ, écriture permise.
function WalletRules.loadOutcome(ok: boolean, data: any): (number, boolean)
	if not (ok and isWritable(data)) then
		return WalletRules.STARTING_BALANCE, false
	end
	return WalletRules.read(data), true
end

-- Cette méthode permet de relire les marques de lots appliqués d'un enregistrement lorsqu'il est fusionné : seules les
-- entrées bien formées, dans l'ordre (la plus récente en dernier).
local function readMarks(data: any): { WriteMark }
	local marks: { WriteMark } = {}
	if type(data) == "table" and type(data.writes) == "table" then
		for _, mark in ipairs(data.writes) do
			if type(mark) == "table" and type(mark.session) == "string" and isSeq(mark.seq) then
				table.insert(marks, { session = mark.session, seq = mark.seq })
			end
		end
	end
	return marks
end

-- Cette méthode permet de calculer la valeur écrite par UpdateAsync lorsqu'une session envoie un lot : solde stocké plus
-- écart, ramené dans [0, MAX_BALANCE] (champs inconnus recopiés), ou nil si le lot est déjà appliqué ou le format
-- refusé. Pure : Roblox peut l'appeler plusieurs fois.
function WalletRules.mergeForSave(old: any, batch: Batch): (Payload?, MergeStatus)
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
	while #marks > WalletRules.MAX_WRITE_MARKS do
		table.remove(marks, 1)
	end
	local payload: { [string]: any } = {}
	if type(old) == "table" then
		for key, value in old do
			payload[key] = value
		end
	end
	payload.schemaVersion = WalletRules.SCHEMA_VERSION
	payload.credits = WalletRules.clamp(WalletRules.read(old) + batch.delta)
	payload.writes = marks
	return payload :: Payload, "merged"
end

-- Lecture côté client : attribut informatif du Player (nombre entier), posé par le serveur (WalletStore) une fois le
-- solde stocké lu, puis à chaque gain ou dépense ; jamais relu par le serveur. Absent : pas (encore) chargé.
WalletRules.ATTRIBUTE = "Credits"

-- Cette méthode permet de relire l'attribut du Player lorsque le menu ou le shop affichent le solde ; nil (non chargé)
-- si l'attribut est absent ou invalide, jamais 0 par défaut.
function WalletRules.decode(value: any): number?
	return if WalletRules.isBalance(value) then value else nil
end

-- Cette méthode permet d'écrire un montant avec une espace tous les trois chiffres (« 12 500 ») lorsqu'un solde ou un
-- prix est affiché ; nil (non chargé) → « — ».
function WalletRules.format(amount: number?): string
	if amount == nil then
		return "—"
	end
	local digits = string.format("%.0f", amount)
	local out = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1 ")))
	return (string.gsub(out, "^ ", ""))
end

return WalletRules
