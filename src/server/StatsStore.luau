-- Statistiques persistantes des joueurs (kills, morts, manches jouées et gagnées), DataStore `PlayerStats_v1` (#296).
-- Règles pures dans `StatsRules`. La session ne réécrit pas le profil : elle tient ses écarts depuis la dernière écriture
-- et UpdateAsync les ajoute à ce qui est stocké (StatsRules.mergeForSave), si bien qu'une écriture en retard ou d'un
-- autre serveur n'efface rien. Un kill ou une mort enregistré avant la fin du chargement va dans les écarts, il n'est
-- pas perdu.
-- Écritures : seulement s'il y a des écarts (aucune pour un joueur resté au menu), toutes les
-- `GameConfig.AUTO_SAVE_INTERVAL` s, au départ du joueur et à l'arrêt du serveur (en parallèle). Une écriture en échec
-- est signalée (warn) et ses écarts gardés pour la suivante. Format stocké inconnu ou plus récent : sauvegarde coupée
-- pour la session, l'enregistrement n'est pas touché.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local StatsRules = require(ReplicatedStorage.Shared.StatsRules)

local STORE_NAME = "PlayerStats_v1"
local CLOSE_WAIT = 25 -- s d'attente maximale des sauvegardes en vol à l'arrêt du serveur (budget Roblox : 30 s)
-- Échecs d'affilée (de 3 essais chacun) avant d'abandonner les écarts d'un joueur parti
local MAX_SAVE_FAILURES = 5

type Stats = StatsRules.Stats
-- stored : statistiques stockées connues (au chargement, puis après chaque écriture) ; delta : écarts pas encore écrits ;
-- known : stored a été lu (chargement réussi ou écriture faite) ; canSave : faux si le format stocké n'est pas
-- réécrivable ; saving : une écriture part, les écarts arrivés depuis attendent la suivante.
type Profile = {
	player: Player,
	stored: Stats,
	delta: Stats,
	known: boolean,
	canSave: boolean,
	saving: boolean,
	failures: number,
}

local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}
-- Profils des joueurs partis dont les écarts ne sont pas encore écrits (écriture en vol ou en échec) : retentés par
-- l'auto-sauvegarde et l'arrêt du serveur
local departed: { [Profile]: boolean } = {}
-- Écritures en cours, attendues par BindToClose
local savesInFlight = 0
-- Arrêt du serveur en cours : une écriture en échec est retentée tout de suite
local closing = false

local StatsStore = {}

-- Cette méthode permet d'ouvrir le DataStore une seule fois lorsqu'il sert pour la première fois ; nil si les services
-- d'API sont coupés (Studio sans « Enable Studio Access to API Services »).
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

-- Cette méthode permet d'oublier le profil d'un joueur parti lorsqu'il n'a plus rien à écrire (écarts écrits, ou
-- sauvegarde coupée).
local function settle(profile: Profile)
	if profiles[profile.player] ~= profile and (StatsRules.isEmpty(profile.delta) or not profile.canSave) then
		departed[profile] = nil
	end
end

-- Cette méthode permet d'écrire les écarts d'un profil lorsqu'il en a (auto-sauvegarde, départ, arrêt), une écriture à
-- la fois : les écarts partent, ceux qui arrivent pendant l'écriture attendent la suivante ; un échec les remet.
local function saveProfile(profile: Profile)
	local ds = getStore()
	if not (ds and profile.canSave) or profile.saving or StatsRules.isEmpty(profile.delta) then
		return
	end
	local player = profile.player
	local sent = profile.delta
	profile.delta = StatsRules.zero()
	profile.saving = true
	savesInFlight += 1
	local refused = false
	local ok, written = withRetry(function()
		return ds:UpdateAsync(tostring(player.UserId), function(old)
			local merged = StatsRules.mergeForSave(old, sent)
			refused = merged == nil
			return merged
		end)
	end)
	savesInFlight -= 1
	profile.saving = false
	if ok and not refused then
		profile.stored = StatsRules.storedStats(written)
		profile.known = true
		profile.failures = 0
	else
		profile.delta = StatsRules.sum(profile.delta, sent)
		if ok then
			-- Un autre serveur (version plus récente) a écrit un format que celle-ci ne sait pas réécrire
			profile.canSave = false
			warn("[StatsStore] format enregistré inconnu pour", player.Name, "— statistiques non sauvegardées")
		else
			profile.failures += 1
			if profiles[player] ~= profile and profile.failures >= MAX_SAVE_FAILURES then
				profile.canSave = false
				warn("[StatsStore] sauvegarde abandonnée pour", player.Name, "après", profile.failures, "échecs")
			else
				warn("[StatsStore] sauvegarde impossible pour", player.Name, "— écarts gardés pour la suivante")
			end
		end
	end
	-- Arrêt du serveur : les écarts arrivés pendant l'écriture, ou d'une écriture en échec, repartent tout de suite
	if
		closing
		and profile.canSave
		and not StatsRules.isEmpty(profile.delta)
		and profile.failures < MAX_SAVE_FAILURES
	then
		saveProfile(profile)
	end
	settle(profile)
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

-- Cette méthode permet d'inscrire un joueur et de charger ses statistiques stockées lorsqu'il arrive ; le profil existe
-- dès l'appel, avant la lecture DataStore, pour que les kills et morts qui précèdent sa fin soient gardés en écarts.
function StatsStore.load(player: Player)
	local profile: Profile = {
		player = player,
		stored = StatsRules.zero(),
		delta = StatsRules.zero(),
		known = false,
		canSave = true,
		saving = false,
		failures = 0,
	}
	profiles[player] = profile
	local ds = getStore()
	if not ds then
		-- Rien ne pourra être écrit : sans quoi les écarts d'un joueur parti resteraient en attente
		profile.canSave = false
		warn("[StatsStore] DataStore indisponible pour", player.Name, "— statistiques non sauvegardées")
		return
	end
	local ok, data = withRetry(function()
		return ds:GetAsync(tostring(player.UserId))
	end)
	if profiles[player] ~= profile then
		return -- parti pendant le chargement : ses écarts sont partis avec PlayerRemoving
	end
	local stored, canSave, known = StatsRules.loadOutcome(ok, data)
	if not canSave then
		profile.canSave = false
		warn("[StatsStore] format enregistré inconnu pour", player.Name, "— statistiques non sauvegardées")
	elseif not known then
		warn("[StatsStore] chargement impossible pour", player.Name, "— écarts ajoutés à la prochaine écriture")
	end
	-- Une écriture déjà faite pendant le chargement a relu des statistiques plus récentes que cette lecture
	if known and not profile.known then
		profile.stored = stored
		profile.known = true
	end
end

-- Cette méthode permet de lire les statistiques d'un joueur (stockées plus écarts pas encore écrits) lorsqu'un système
-- serveur les affiche ; joueur inconnu : zéros.
function StatsStore.getStats(player: Player): Stats
	local profile = profiles[player]
	return if profile then StatsRules.sum(profile.stored, profile.delta) else StatsRules.zero()
end

-- Cette méthode permet d'ajouter un écart au profil d'un joueur inscrit lorsqu'un événement compté arrive.
local function record(player: Player, field: StatsRules.Field)
	local profile = profiles[player]
	if profile then
		StatsRules.add(profile.delta, field)
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
			departed[profile] = true
			saveProfile(profile)
			settle(profile)
		end
	end)

	game:BindToClose(function()
		closing = true
		-- Les départs (PlayerRemoving) ont souvent déjà vidé les écarts : rien n'est écrit deux fois
		saveAll()
		local deadline = os.clock() + CLOSE_WAIT
		while savesInFlight > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return StatsStore
