-- Statistiques persistantes des joueurs (kills, morts, manches jouées et gagnées), DataStore `PlayerStats_v1` (#296).
-- Règles pures dans `StatsRules`. La session ne réécrit pas le profil : elle tient ses écarts depuis la dernière écriture
-- et UpdateAsync les ajoute à ce qui est stocké, par lots numérotés (StatsRules.mergeForSave) : une écriture en retard ou
-- d'un autre serveur n'efface rien, un lot renvoyé après un échec douteux n'est pas compté deux fois. Un kill ou une mort
-- enregistré avant la fin du chargement va dans les écarts, il n'est pas perdu.
-- Écritures : seulement s'il y a des écarts (aucune pour un joueur resté au menu), toutes les
-- `GameConfig.AUTO_SAVE_INTERVAL` s, au départ du joueur et à l'arrêt du serveur (en parallèle). Une écriture en échec
-- est signalée (warn) et son lot gardé pour la suivante. Lecture en échec, format stocké inconnu ou plus récent :
-- sauvegarde coupée pour la session, l'enregistrement n'est pas touché.
-- Le client lit ces statistiques dans l'attribut informatif `PlayerStats` du Player (#301, fiche de l'accueil), posé une
-- fois le stocké connu puis à chaque kill, mort ou fin de manche ; jamais relu par le serveur.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local StatsRules = require(ReplicatedStorage.Shared.StatsRules)

local STORE_NAME = "PlayerStats_v1"
local CLOSE_WAIT = 25 -- s d'attente maximale des sauvegardes en vol à l'arrêt du serveur (budget Roblox : 30 s)
-- Échecs d'affilée (de 3 essais chacun) avant d'abandonner les écarts d'un joueur parti
local MAX_SAVE_FAILURES = 5

type Stats = StatsRules.Stats
-- session/seq : id de cette session du joueur et numéro du dernier lot ; stored : stocké connu (chargement, puis chaque
-- écriture) ; pending : lot en cours d'écriture ou en échec, renvoyé tel quel ; delta : écarts arrivés depuis ;
-- known : stored a été lu ; canSave : faux si la lecture a échoué ou si le format stocké n'est pas réécrivable.
type Profile = {
	player: Player,
	session: string,
	seq: number,
	stored: Stats,
	pending: StatsRules.Batch?,
	delta: Stats,
	known: boolean,
	canSave: boolean,
	saving: boolean,
	failures: number,
}

local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}
-- Profils des joueurs partis qui ont encore des écarts à écrire : retentés par l'auto-sauvegarde et l'arrêt du serveur
local departed: { [Profile]: boolean } = {}
-- Écritures en cours, attendues par BindToClose
local savesInFlight = 0
-- Arrêt du serveur en cours : une écriture en échec est retentée tout de suite, tant que closeDeadline le permet
local closing = false
local closeDeadline = math.huge

local StatsStore = {}

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

-- Cette méthode permet de savoir si un profil a encore quelque chose à écrire (lot en échec ou écarts nouveaux).
local function hasWork(profile: Profile): boolean
	return profile.pending ~= nil or not StatsRules.isEmpty(profile.delta)
end

-- Cette méthode permet de calculer les statistiques d'un profil (stockées, plus lot en écriture et écarts pas encore
-- écrits) lorsqu'un système serveur ou l'attribut du Player les lit.
local function totalOf(profile: Profile): Stats
	local total = StatsRules.sum(profile.stored, profile.delta)
	return if profile.pending then StatsRules.sum(total, profile.pending.delta) else total
end

-- Cette méthode permet de poser l'attribut informatif `PlayerStats` du Player (#301, lu par la fiche de l'accueil)
-- lorsque ses statistiques changent ou sont lues ; rien tant que le stocké n'est pas connu : le client affiche « — »
-- plutôt que des zéros (chargement en cours ou en échec).
local function publish(profile: Profile)
	if profile.known and profiles[profile.player] == profile then
		profile.player:SetAttribute(StatsRules.ATTRIBUTE, StatsRules.encode(totalOf(profile)))
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

-- Cette méthode permet d'écrire un lot d'écarts d'un profil lorsqu'il en a (auto-sauvegarde, départ, arrêt), une écriture
-- à la fois : le lot en échec repart tel quel, les écarts arrivés pendant l'écriture forment le lot suivant.
local function saveProfile(profile: Profile)
	local ds = getStore()
	if not (ds and profile.canSave) or profile.saving or not hasWork(profile) then
		return
	end
	local player = profile.player
	if not profile.pending then
		profile.seq += 1
		profile.pending = { session = profile.session, seq = profile.seq, delta = profile.delta }
		profile.delta = StatsRules.zero()
	end
	local batch = profile.pending :: StatsRules.Batch
	profile.saving = true
	savesInFlight += 1
	local status: StatsRules.MergeStatus = "refused"
	local seen: any = nil
	local startedAt = os.clock()
	local ok, written = withRetry(function()
		return ds:UpdateAsync(tostring(player.UserId), function(old)
			local merged
			merged, status = StatsRules.mergeForSave(old, batch)
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
		profile.stored = StatsRules.read(if status == "merged" then written else seen)
		profile.known = true
		profile.failures = 0
		-- Écriture faite pendant le chargement : c'est elle qui rend le stocké connu
		publish(profile)
	elseif ok then
		-- Un autre serveur (version plus récente) a écrit un format que celle-ci ne sait pas réécrire
		profile.canSave = false
		warn("[StatsStore] format enregistré inconnu pour", player.Name, "— statistiques non sauvegardées")
	else
		profile.failures += 1
		-- À l'arrêt, un nouvel essai n'est lancé que s'il peut durer autant que celui-ci avant la fin de CLOSE_WAIT
		local outOfTime = closing and 2 * os.clock() - startedAt >= closeDeadline
		if outOfTime or (gone and profile.failures >= MAX_SAVE_FAILURES) then
			profile.canSave = false
			warn("[StatsStore] sauvegarde abandonnée pour", player.Name, "après", profile.failures, "échecs")
		else
			warn("[StatsStore] sauvegarde impossible pour", player.Name, "— écarts gardés pour la suivante")
		end
	end
	track(profile)
	-- Écarts arrivés pendant l'écriture d'un joueur parti : écrits tout de suite ; à l'arrêt, un échec est aussi retenté
	if (closing or (ok and gone)) and profile.canSave and hasWork(profile) then
		saveProfile(profile)
	end
end

-- Cette méthode permet de lancer en parallèle l'écriture de tous les profils qui ont des écarts (joueurs connectés et
-- partis) lorsque l'auto-sauvegarde passe ou que le serveur s'arrête.
local function saveAll()
	for _, profile in profiles do
		task.spawn(saveProfile, profile)
	end
	for profile in departed do
		task.spawn(saveProfile, profile)
	end
end

-- Cette méthode permet d'inscrire un joueur puis de charger ses statistiques lorsqu'il arrive ; le profil existe avant la
-- lecture DataStore, pour que les kills et morts qui précèdent sa fin soient gardés en écarts.
function StatsStore.load(player: Player)
	local profile: Profile = {
		player = player,
		session = HttpService:GenerateGUID(false),
		seq = 0,
		stored = StatsRules.zero(),
		pending = nil,
		delta = StatsRules.zero(),
		known = false,
		canSave = true,
		saving = false,
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
		return -- parti pendant le chargement : ses écarts sont partis avec PlayerRemoving
	end
	local stored, canSave = StatsRules.loadOutcome(ok, data)
	if profile.known then
		return -- une écriture faite pendant le chargement a déjà relu le stocké (plus récent) et prouvé son format
	elseif not canSave then
		-- Lecture en échec (services d'API coupés en Studio compris) ou format inconnu : rien n'est écrit, et pas
		-- d'attribut (la fiche reste sur « — »)
		profile.canSave = false
		warn("[StatsStore] chargement impossible pour", player.Name, "— statistiques non sauvegardées")
	else
		profile.stored = stored
		profile.known = true
		publish(profile)
	end
end

-- Cette méthode permet de lire les statistiques d'un joueur (stockées plus écarts pas encore écrits) lorsqu'un système
-- serveur les affiche ; joueur inconnu : zéros.
function StatsStore.getStats(player: Player): Stats
	local profile = profiles[player]
	if not profile then
		return StatsRules.zero()
	end
	return totalOf(profile)
end

-- Cette méthode permet d'ajouter un écart au profil d'un joueur inscrit lorsqu'un événement compté arrive, et de
-- republier son attribut (une fin de manche met donc la fiche à jour avant le retour au menu).
local function record(player: Player, field: StatsRules.Field)
	local profile = profiles[player]
	if profile then
		StatsRules.add(profile.delta, field)
		publish(profile)
	end
end

-- Cette méthode permet de compter un kill pour un joueur lorsqu'il compte dans les stats (ParticipantRules).
function StatsStore.recordKill(player: Player)
	record(player, "kills")
end

-- Cette méthode permet de compter une mort pour un joueur lorsqu'elle compte dans les stats (ParticipantRules).
function StatsStore.recordDeath(player: Player)
	record(player, "deaths")
end

-- Cette méthode permet de compter une manche jouée (et gagnée si `won`) lorsqu'une manche se termine avec ce joueur en
-- jeu (RoundManager, vainqueur désigné par id).
function StatsStore.recordRoundEnd(player: Player, won: boolean)
	record(player, "roundsPlayed")
	if won then
		record(player, "roundsWon")
	end
end

-- Cette méthode permet de brancher l'auto-sauvegarde, le départ des joueurs et l'arrêt du serveur lorsque le serveur
-- démarre ; à l'arrêt, les écritures partent en parallèle et sont attendues CLOSE_WAIT s au plus.
function StatsStore.init()
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
			-- Les échecs d'un joueur connecté ne comptent pas dans l'abandon de ses écarts une fois parti
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
		-- Les départs (PlayerRemoving) ont souvent déjà écrit leurs écarts : rien n'est écrit deux fois
		saveAll()
		while savesInFlight > 0 and os.clock() < closeDeadline do
			task.wait(0.1)
		end
	end)
end

return StatsStore
