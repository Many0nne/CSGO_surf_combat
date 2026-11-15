-- Solde de crédits des joueurs, la monnaie du jeu (#391), DataStore `PlayerWallet_v1`. Règles pures dans `WalletRules`.
-- Seul le serveur change un solde : `add` (gain) et `spend` (dépense) ; aucun remote n'en donne le droit au client, qui
-- lit l'attribut informatif `Credits` du Player (LocalWallet). Pas encore de gain ni d'achat : l'API attend l'obtention et
-- la boutique.
-- Comme StatsStore, la session ne réécrit pas le solde : elle tient son écart depuis la dernière écriture et UpdateAsync
-- l'ajoute au solde stocké, par lots numérotés (WalletRules.mergeForSave) : une écriture en retard ou d'un autre serveur
-- n'efface rien, un lot renvoyé après un échec douteux n'est pas compté deux fois. Un solde ne change qu'une fois le
-- stocké connu et sauvegardable (`canChange`) : avant, ou après une lecture en échec, un gain serait perdu et une
-- dépense pourrait passer sous le vrai solde.
-- Écritures : `CHANGE_SAVE_DELAY` s après un changement (changements rapprochés réunis), toutes les
-- `GameConfig.AUTO_SAVE_INTERVAL` s s'il reste un écart, au départ du joueur et à l'arrêt du serveur (en parallèle).
-- Une écriture en échec est signalée (warn) et son lot gardé pour la suivante.
-- Studio : attribut Player `DebugCredits` (nombre, posé en contexte serveur) ajouté au solde (négatif : retiré), puis
-- remis à nil ; sans accès aux API (chargement en échec), le solde devient un solde de session, jamais sauvegardé.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local WalletRules = require(ReplicatedStorage.Shared.WalletRules)

local STORE_NAME = "PlayerWallet_v1"
local CLOSE_WAIT = 25 -- s d'attente maximale des sauvegardes en vol à l'arrêt du serveur (budget Roblox : 30 s)
-- s entre un changement de solde et son écriture : les changements rapprochés partent ensemble
local CHANGE_SAVE_DELAY = 6
-- Échecs d'affilée (de 3 essais chacun) avant d'abandonner l'écart d'un joueur parti
local MAX_SAVE_FAILURES = 5
local DEBUG_ATTRIBUTE = "DebugCredits"

-- session/seq : id de cette session du joueur et numéro du dernier lot ; stored : solde stocké connu (chargement, puis
-- chaque écriture) ; pending : lot en cours d'écriture ou en échec, renvoyé tel quel ; delta : écart arrivé depuis ;
-- known : stored a été lu ; canSave : faux si la lecture a échoué ou si le format stocké n'est pas réécrivable ;
-- sessionOnly : solde de session de Studio (DebugCredits sans accès aux API), changeable mais jamais écrit.
type Profile = {
	player: Player,
	session: string,
	seq: number,
	stored: number,
	pending: WalletRules.Batch?,
	delta: number,
	known: boolean,
	canSave: boolean,
	sessionOnly: boolean,
	saving: boolean,
	saveScheduled: boolean,
	failures: number,
}

local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}
-- Profils des joueurs partis qui ont encore un écart à écrire : retentés par l'auto-sauvegarde et l'arrêt du serveur
local departed: { [Profile]: boolean } = {}
-- Écritures en cours, attendues par BindToClose
local savesInFlight = 0
-- Arrêt du serveur en cours : une écriture en échec est retentée tout de suite, tant que closeDeadline le permet
local closing = false
local closeDeadline = math.huge

local WalletStore = {}

-- Cette méthode permet d'ouvrir le DataStore une seule fois lorsqu'il sert pour la première fois ; nil si les services
-- d'API sont coupés.
local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
	if ok then
		store = result
	end
	return store
end

-- Cette méthode permet de lire ou d'écrire le DataStore avec trois essais espacés lorsque le réseau ou les quotas
-- refusent une requête ; renvoie la réussite et le résultat.
local function withRetry(fn: () -> any): (boolean, any)
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt < 3 then
			task.wait(2 ^ attempt)
		end
	end
	return false, nil
end

-- Cette méthode permet de savoir si un profil a encore quelque chose à écrire (lot en échec ou écart nouveau).
local function hasWork(profile: Profile): boolean
	return profile.pending ~= nil or profile.delta ~= 0
end

-- Cette méthode permet de calculer le solde d'un profil (stocké, plus lot en écriture et écart pas encore écrit) lorsqu'un
-- système serveur ou l'attribut du Player le lit.
local function totalOf(profile: Profile): number
	local pending = if profile.pending then profile.pending.delta else 0
	return WalletRules.clamp(profile.stored + pending + profile.delta)
end

-- Cette méthode permet de poser l'attribut informatif `Credits` lorsque le solde change ou est lu ; rien tant que le
-- stocké n'est pas connu, pour que le menu affiche « — » plutôt qu'un 0 trompeur.
local function publish(profile: Profile)
	if profile.known and profiles[profile.player] == profile then
		profile.player:SetAttribute(WalletRules.ATTRIBUTE, totalOf(profile))
	end
end

-- Cette méthode permet de tenir à jour la liste des joueurs partis à écrire lorsqu'un profil part ou finit une écriture.
local function track(profile: Profile)
	if profiles[profile.player] == profile then
		return
	end
	if profile.canSave and hasWork(profile) then
		departed[profile] = true
	else
		departed[profile] = nil
	end
end

-- Cette méthode permet d'écrire le lot d'un profil lorsqu'il a un écart (changement, auto-sauvegarde, départ, arrêt), une
-- écriture à la fois : le lot en échec repart tel quel, l'écart arrivé pendant l'écriture forme le lot suivant.
local function saveProfile(profile: Profile)
	local ds = getStore()
	if not (ds and profile.canSave) or profile.saving or not hasWork(profile) then
		return
	end
	local player = profile.player
	if not profile.pending then
		profile.seq += 1
		profile.pending = { session = profile.session, seq = profile.seq, delta = profile.delta }
		profile.delta = 0
	end
	local batch = profile.pending :: WalletRules.Batch
	profile.saving = true
	savesInFlight += 1
	local status: WalletRules.MergeStatus = "refused"
	local seen: any = nil
	local startedAt = os.clock()
	local ok, written = withRetry(function()
		return ds:UpdateAsync(tostring(player.UserId), function(old)
			local merged
			merged, status = WalletRules.mergeForSave(old, batch)
			seen = old
			return merged
		end)
	end)
	savesInFlight -= 1
	profile.saving = false
	local gone = profiles[player] ~= profile
	if ok and status ~= "refused" then
		-- "applied" : lot déjà écrit par un essai signalé en échec, l'enregistrement relu le contient
		profile.pending = nil
		profile.stored = WalletRules.read(if status == "merged" then written else seen)
		profile.failures = 0
		publish(profile)
	elseif ok then
		-- Un autre serveur (version plus récente) a écrit un format que celle-ci ne sait pas réécrire
		profile.canSave = false
		warn("[WalletStore] format enregistré inconnu pour", player.Name, "— crédits non sauvegardés")
	else
		profile.failures += 1
		-- À l'arrêt, un nouvel essai n'est lancé que s'il peut durer autant que celui-ci avant la fin de CLOSE_WAIT
		local outOfTime = closing and 2 * os.clock() - startedAt >= closeDeadline
		if outOfTime or (gone and profile.failures >= MAX_SAVE_FAILURES) then
			profile.canSave = false
			warn("[WalletStore] sauvegarde abandonnée pour", player.Name, "après", profile.failures, "échecs")
		else
			warn("[WalletStore] sauvegarde impossible pour", player.Name, "— écart gardé pour la suivante")
		end
	end
	track(profile)
	-- Écart arrivé pendant l'écriture d'un joueur parti : écrit tout de suite ; à l'arrêt, un échec est aussi retenté
	if (closing or (ok and gone)) and profile.canSave and hasWork(profile) then
		saveProfile(profile)
	end
end

-- Cette méthode permet de lancer en parallèle l'écriture de tous les profils qui ont un écart (joueurs connectés et
-- partis) lorsque l'auto-sauvegarde passe ou que le serveur s'arrête.
local function saveAll()
	for _, profile in profiles do
		task.spawn(saveProfile, profile)
	end
	for profile in departed do
		task.spawn(saveProfile, profile)
	end
end

-- Cette méthode permet de programmer l'écriture d'un profil CHANGE_SAVE_DELAY s après un changement de solde, une seule
-- fois pour des changements rapprochés.
local function scheduleSave(profile: Profile)
	if profile.saveScheduled or not profile.canSave then
		return
	end
	profile.saveScheduled = true
	task.spawn(function()
		task.wait(CHANGE_SAVE_DELAY)
		profile.saveScheduled = false
		saveProfile(profile)
	end)
end

-- Cette méthode permet de savoir si le solde d'un profil peut changer lorsqu'un gain ou une dépense arrive : stocké connu
-- et sauvegardable, ou solde de session de Studio.
local function changeable(profile: Profile?): boolean
	return profile ~= nil and profile.known and (profile.canSave or profile.sessionOnly)
end

-- Cette méthode permet d'appliquer un écart signé au solde d'un profil lorsqu'un gain ou une dépense est accepté, puis de
-- publier le solde et de programmer l'écriture.
local function apply(profile: Profile, delta: number)
	profile.delta += delta
	publish(profile)
	scheduleSave(profile)
end

-- Cette méthode permet d'inscrire un joueur puis de charger son solde lorsqu'il arrive ; le solde ne peut changer
-- qu'une fois la lecture DataStore terminée et réussie.
function WalletStore.load(player: Player)
	local profile: Profile = {
		player = player,
		session = HttpService:GenerateGUID(false),
		seq = 0,
		stored = WalletRules.STARTING_BALANCE,
		pending = nil,
		delta = 0,
		known = false,
		canSave = true,
		sessionOnly = false,
		saving = false,
		saveScheduled = false,
		failures = 0,
	}
	profiles[player] = profile
	local ds = getStore()
	local ok, data = false, nil
	if ds then
		ok, data = withRetry(function()
			return ds:GetAsync(tostring(player.UserId))
		end)
	end
	if profiles[player] ~= profile then
		return -- parti pendant le chargement : rien n'a pu changer
	end
	local stored, canSave = WalletRules.loadOutcome(ok, data)
	if not canSave then
		-- Lecture en échec (services d'API coupés en Studio compris) ou format inconnu : rien n'est écrit, et pas
		-- d'attribut (le menu reste sur « — »)
		profile.canSave = false
		warn("[WalletStore] chargement impossible pour", player.Name, "— crédits indisponibles")
		return
	end
	profile.stored = stored
	profile.known = true
	publish(profile)
end

-- Cette méthode permet de lire le solde d'un joueur (stocké plus écarts pas encore écrits) lorsqu'un système serveur le
-- consulte ; nil tant que le solde n'est pas chargé (ou si son chargement a échoué).
function WalletStore.balance(player: Player): number?
	local profile = profiles[player]
	if not (profile and profile.known) then
		return nil
	end
	return totalOf(profile)
end

-- Cette méthode permet de savoir si le solde d'un joueur peut changer lorsqu'un système serveur s'apprête à donner ou
-- faire payer (à vérifier avant un tirage ou un don, comme InventoryStore.canGrant).
function WalletStore.canChange(player: Player): boolean
	return changeable(profiles[player])
end

-- Cette méthode permet de créditer un joueur lorsqu'il gagne des crédits ; refus (false) si le montant est invalide ou si
-- le solde ne peut pas changer. Le solde est écrêté à WalletRules.MAX_BALANCE.
function WalletStore.add(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not (WalletRules.isAmount(amount) and changeable(profile)) then
		return false
	end
	local p = profile :: Profile
	local room = WalletRules.MAX_BALANCE - totalOf(p)
	if room > 0 then
		apply(p, math.min(amount, room))
	end
	return true
end

-- Cette méthode permet de débiter un joueur lorsqu'il paie ; refus (false, rien de débité) si le montant est invalide,
-- si le solde ne peut pas changer ou s'il ne suffit pas.
function WalletStore.spend(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not (WalletRules.isAmount(amount) and changeable(profile)) then
		return false
	end
	local p = profile :: Profile
	if totalOf(p) < amount then
		return false
	end
	apply(p, -amount)
	return true
end

-- Cette méthode permet, dans Studio, d'appliquer l'attribut `DebugCredits` d'un joueur lorsqu'il est posé (contexte
-- serveur) : nombre entier ajouté au solde (négatif : retiré, jusqu'à 0), puis attribut remis à nil. Sans accès aux
-- API, le solde devient un solde de session.
function WalletStore.applyDebug(player: Player)
	local value = player:GetAttribute(DEBUG_ATTRIBUTE)
	if value == nil then
		return
	end
	player:SetAttribute(DEBUG_ATTRIBUTE, nil)
	local profile = profiles[player]
	if type(value) ~= "number" or value ~= math.floor(value) or not profile then
		warn("[DebugCredits] valeur invalide ou joueur pas inscrit :", value)
		return
	end
	if not profile.known and not profile.canSave then
		-- Chargement en échec (Studio sans « Enable Studio Access to API Services ») : solde de session à 0
		profile.known = true
		profile.sessionOnly = true
	end
	local before = WalletStore.balance(player)
	local ok = if value >= 0
		then WalletStore.add(player, value)
		else WalletStore.spend(player, math.min(-value, before or 0))
	print("[DebugCredits]", player.Name, value, ok, before, "→", WalletStore.balance(player))
end

-- Cette méthode permet de brancher l'auto-sauvegarde, le départ des joueurs et l'arrêt du serveur lorsque le serveur
-- démarre ; à l'arrêt, les écritures partent en parallèle et sont attendues CLOSE_WAIT s au plus.
function WalletStore.init()
	task.spawn(function()
		while true do
			task.wait(GameConfig.AUTO_SAVE_INTERVAL)
			saveAll()
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		profiles[player] = nil
		if profile then
			profile.failures = 0
			track(profile)
			saveProfile(profile)
		end
	end)

	game:BindToClose(function()
		closing = true
		closeDeadline = os.clock() + CLOSE_WAIT
		for _, profile in profiles do
			profile.failures = 0
		end
		for profile in departed do
			profile.failures = 0
		end
		saveAll()
		while savesInFlight > 0 and os.clock() < closeDeadline do
			task.wait(0.1)
		end
	end)
end

return WalletStore
