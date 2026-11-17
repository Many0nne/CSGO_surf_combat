-- Analytics du jeu (#527) : seul module qui appelle AnalyticsService, côté serveur. Il tient l'état de chaque joueur
-- (écran signalé par le client, phase en partie, manches jouées, série de morts, visites du shop) et en tire les
-- funnels (onboarding, session, shop, packs Robux), l'économie des crédits et les événements de départ et de blocage.
-- Étapes, noms et valeurs des champs : shared/AnalyticsRules. Points d'appel : server/init.server (branchement),
-- CrateService, ReceiptService, InventoryStore (rappels). Lecture des tableaux de bord : docs/analytics.md.
--
-- Rien n'est envoyé sans `service` (Studio : init.server ne le donne pas) ; `log` écrit alors chaque envoi, préfixé
-- [Analytics], pour vérifier en playtest. Un appel refusé par AnalyticsService (limite, argument) est signalé une
-- fois par méthode, sans effet sur le jeu ; une erreur de ce module ne remonte jamais dans le code de jeu.
-- Onboarding : seulement pour un nouveau joueur (aucune statistique enregistrée, StatsStore.isNewcomer), étapes
-- gardées en attente tant que son ancienneté n'est pas connue ; jamais sur un serveur d'entraînement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnalyticsRules = require(ReplicatedStorage.Shared.AnalyticsRules)

local R = AnalyticsRules
local S = R.Screen
local F = R.Field

export type Deps = {
	-- AnalyticsService (ou un faux dans les tests) ; nil : rien n'est envoyé
	service: any?,
	-- Enum.AnalyticsEconomyFlowType.Source et .Sink (passés pour garder le module testable sous Lune)
	flow: { source: any, sink: any },
	-- Écrit chaque envoi (Studio) ; nil : silencieux
	log: ((string) -> ())?,
	-- Horloge en secondes (os.clock)
	clock: () -> number,
	-- Identifiant unique d'un funnelSessionId (HttpService:GenerateGUID)
	guid: () -> string,
	-- Serveur d'entraînement (#345) : ni onboarding, ni morts comptées
	training: boolean,
}

type State = {
	name: string,
	sessionId: string,
	joinedAt: number,
	screen: string?,
	screenSince: number,
	screenEvents: number,
	phase: AnalyticsRules.Phase,
	rounds: number,
	-- Ancienneté : nil tant que les statistiques ne sont pas chargées
	newcomer: boolean?,
	-- Ancienneté décidée (chargement fini, réussi ou non) : l'onboarding n'attend plus
	newcomerKnown: boolean,
	onboardingDone: { [number]: boolean },
	onboardingPending: { AnalyticsRules.Step },
	sessionDone: { [number]: boolean },
	firstMenuAt: number?,
	playClicked: boolean,
	deathStreak: number,
	shopId: string?,
	shopDone: { [number]: boolean },
	-- Skins obtenus par une caisse achetée, avec la visite du shop de l'achat (étape Skin équipé)
	boughtSkins: { [string]: string },
	equippedShops: { [string]: boolean },
	packId: string?,
}

local Analytics = {}

local deps: Deps? = nil
local states: { [Player]: State } = {}
local warned: { [string]: boolean } = {}

-- Cette méthode permet de signaler une seule fois un problème d'analytics par clé lorsqu'il se répète (sans spam).
local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[Analytics] " .. message)
end

-- Cette méthode permet d'envelopper un point d'entrée lorsqu'il est appelé par le code de jeu : sans init, rien ; une
-- erreur est signalée une fois et ne remonte pas.
local function guarded<A...>(name: string, fn: (Deps, A...) -> ()): (A...) -> ()
	return function(...: A...)
		local d = deps
		if not d then
			return
		end
		local ok, err = pcall(fn, d, ...)
		if not ok then
			warnOnce("err:" .. name, name .. " en erreur : " .. tostring(err))
		end
	end
end

-- Cette méthode permet d'écrire des champs personnalisés lisiblement lorsqu'un envoi est journalisé.
local function describeFields(fields: { [string]: any }?): string
	if not fields then
		return ""
	end
	local parts = {}
	for _, key in { F.ONE, F.TWO, F.THREE } do
		if fields[key] ~= nil then
			table.insert(parts, tostring(fields[key]))
		end
	end
	return if #parts > 0 then " [" .. table.concat(parts, ", ") .. "]" else ""
end

-- Cette méthode permet d'envoyer un appel à AnalyticsService (et de le journaliser) lorsqu'un événement est retenu ;
-- un refus du service est signalé une fois par méthode.
local function emit(d: Deps, method: string, line: string, ...: any)
	if d.log then
		d.log(line)
	end
	local service = d.service
	if not service then
		return
	end
	local ok, err = pcall(function(...)
		service[method](service, ...)
	end, ...)
	if not ok then
		warnOnce("svc:" .. method, method .. " refusé : " .. tostring(err))
	end
end

-- Cette méthode permet d'envoyer une étape de funnel récurrent lorsqu'elle est atteinte.
local function funnelStep(
	d: Deps,
	player: Player,
	funnel: string,
	sessionId: string,
	step: AnalyticsRules.Step,
	fields: { [string]: any }?
)
	emit(
		d,
		"LogFunnelStepEvent",
		string.format("%s funnel %s %d %s%s", player.Name, funnel, step.step, step.name, describeFields(fields)),
		player,
		funnel,
		sessionId,
		step.step,
		step.name,
		fields
	)
end

-- Cette méthode permet d'envoyer un événement personnalisé lorsqu'il est retenu.
local function custom(d: Deps, player: Player, name: string, value: number, fields: { [string]: any }?)
	emit(
		d,
		"LogCustomEvent",
		string.format("%s événement %s = %s%s", player.Name, name, tostring(value), describeFields(fields)),
		player,
		name,
		value,
		fields
	)
end

-- Cette méthode permet d'envoyer un mouvement de crédits lorsqu'il est écrit (source : gagnés, sink : dépensés).
local function economy(
	d: Deps,
	player: Player,
	isSource: boolean,
	amount: number,
	endingBalance: number,
	transaction: string,
	sku: string
)
	if amount <= 0 then
		return
	end
	emit(
		d,
		"LogEconomyEvent",
		string.format(
			"%s économie %s %d %s (%s, %s), solde %d",
			player.Name,
			if isSource then "source" else "sink",
			amount,
			R.CURRENCY,
			transaction,
			sku,
			endingBalance
		),
		player,
		if isSource then d.flow.source else d.flow.sink,
		R.CURRENCY,
		amount,
		math.max(endingBalance, 0),
		transaction,
		sku
	)
end

-- Cette méthode permet d'envoyer une étape du funnel d'onboarding lorsqu'elle est retenue pour un nouveau joueur.
local function sendOnboarding(d: Deps, player: Player, step: AnalyticsRules.Step)
	emit(
		d,
		"LogOnboardingFunnelStepEvent",
		string.format("%s onboarding %d %s", player.Name, step.step, step.name),
		player,
		step.step,
		step.name
	)
end

-- Cette méthode permet de retenir une étape du funnel d'onboarding (une fois chacune) lorsqu'elle est atteinte : en
-- attente tant que l'ancienneté du joueur n'est pas connue, ignorée pour un habitué ou sur l'entraînement.
local function onboarding(d: Deps, player: Player, state: State, step: AnalyticsRules.Step)
	if d.training or state.onboardingDone[step.step] then
		return
	end
	state.onboardingDone[step.step] = true
	if not state.newcomerKnown then
		table.insert(state.onboardingPending, step)
	elseif state.newcomer then
		sendOnboarding(d, player, step)
	end
end

-- Cette méthode permet d'envoyer une étape du funnel de session (une fois chacune) lorsqu'elle est atteinte.
local function session(d: Deps, player: Player, state: State, step: AnalyticsRules.Step)
	if state.sessionDone[step.step] then
		return
	end
	state.sessionDone[step.step] = true
	funnelStep(d, player, R.SESSION_FUNNEL, state.sessionId, step)
end

-- Cette méthode permet d'envoyer une étape de la visite du shop en cours (une fois chacune) lorsqu'elle est atteinte ;
-- sans visite ouverte (achat sans passer par le shop), une visite est ouverte.
local function shop(d: Deps, player: Player, state: State, step: AnalyticsRules.Step)
	if not state.shopId then
		state.shopId = d.guid()
		state.shopDone = {}
	end
	if state.shopDone[step.step] then
		return
	end
	state.shopDone[step.step] = true
	funnelStep(d, player, R.SHOP_FUNNEL, state.shopId :: string, step)
end

-- Cette méthode permet d'envoyer une étape du funnel des packs Robux lorsqu'elle est atteinte, dans la dernière
-- ouverture de la fenêtre des packs (ouverte au besoin) ; `packId` part en champ (peu de packs).
local function packStep(d: Deps, player: Player, state: State, step: AnalyticsRules.Step, packId: string?)
	if not state.packId then
		state.packId = d.guid()
	end
	funnelStep(d, player, R.PACK_FUNNEL, state.packId :: string, step, if packId then { [F.ONE] = packId } else nil)
end

-- Cette méthode permet d'envoyer le temps passé sur l'écran quitté lorsqu'il change (ou au départ) : au-delà du
-- minimum, sous le plafond de la session.
local function closeScreen(d: Deps, player: Player, state: State, now: number)
	local screen = state.screen
	if not screen then
		return
	end
	local spent = now - state.screenSince
	if spent < R.SCREEN_TIME_MIN or state.screenEvents >= R.SCREEN_TIME_MAX_EVENTS then
		return
	end
	state.screenEvents += 1
	local where = R.location(screen, state.phase)
	custom(d, player, R.Event.SCREEN_TIME, math.floor(spent + 0.5), { [F.ONE] = where })
end

-- ── Points d'entrée (appelés par le code de jeu, jamais en erreur) ─────────────

-- Cette méthode permet de brancher le module lorsque le serveur démarre (service, horloge, mode du serveur).
function Analytics.init(dependencies: Deps)
	deps = dependencies
	states = {}
end

-- Cette méthode permet de démarrer le suivi d'un joueur lorsqu'il arrive : visite numérotée, étape Arrivée.
Analytics.playerAdded = guarded("playerAdded", function(d: Deps, player: Player)
	local now = d.clock()
	local state: State = {
		name = player.Name,
		sessionId = d.guid(),
		joinedAt = now,
		screen = nil,
		screenSince = now,
		screenEvents = 0,
		phase = "arrivee",
		rounds = 0,
		newcomer = nil,
		newcomerKnown = false,
		onboardingDone = {},
		onboardingPending = {},
		sessionDone = {},
		firstMenuAt = nil,
		playClicked = false,
		deathStreak = 0,
		shopId = nil,
		shopDone = {},
		boughtSkins = {},
		equippedShops = {},
		packId = nil,
	}
	states[player] = state
	session(d, player, state, R.Session.ARRIVAL)
end)

-- Cette méthode permet de fixer l'ancienneté d'un joueur lorsque ses statistiques sont chargées (nil : inconnue,
-- lecture en échec : pas d'onboarding, « inconnu » dans les champs) : étapes d'onboarding en attente envoyées pour un
-- nouveau joueur, oubliées sinon.
Analytics.setNewcomer = guarded("setNewcomer", function(d: Deps, player: Player, isNew: boolean?)
	local state = states[player]
	if not state or state.newcomerKnown then
		return
	end
	state.newcomerKnown = true
	state.newcomer = isNew
	local pending = state.onboardingPending
	state.onboardingPending = {}
	if isNew ~= true then
		return
	end
	for _, step in pending do
		sendOnboarding(d, player, step)
	end
end)

-- Cette méthode permet de suivre l'écran signalé par le client (remote AnalyticsScreen, valeur déjà validée par la
-- garde) lorsqu'il change : chargement terminé, arrivée au menu, clic sur JOUER, visites du shop et des packs, temps
-- passé sur l'écran quitté.
Analytics.screen = guarded("screen", function(d: Deps, player: Player, screen: string)
	local state = states[player]
	if not state or state.screen == screen or not table.find(R.SCREENS, screen) then
		return
	end
	local now = d.clock()
	local previous = state.screen
	closeScreen(d, player, state, now)
	state.screen = screen
	state.screenSince = now
	if screen ~= S.LOADING then
		onboarding(d, player, state, R.Onboarding.LOADED)
	end
	if R.isMenu(screen) then
		onboarding(d, player, state, R.Onboarding.MENU)
		session(d, player, state, R.Session.MENU)
		state.firstMenuAt = state.firstMenuAt or now
	end
	-- Clic sur JOUER : du menu à la partie (l'enchaînement des manches reste en partie)
	if screen == S.PLAYING and R.isMenu(previous) then
		onboarding(d, player, state, R.Onboarding.PLAY)
		if not state.playClicked then
			state.playClicked = true
			local waited = now - (state.firstMenuAt or now)
			custom(
				d,
				player,
				R.Event.MENU_BEFORE_PLAY,
				math.floor(waited + 0.5),
				{ [F.ONE] = R.newcomerLabel(state.newcomer) }
			)
		end
	end
	-- Nouvelle visite du shop en y entrant depuis un autre écran ; l'ouverture et les packs restent dans la visite
	if R.isShop(screen) and not R.isShop(previous) then
		state.shopId = d.guid()
		state.shopDone = {}
		shop(d, player, state, R.Shop.TAB)
	end
	if screen == S.SHOP_DETAIL then
		shop(d, player, state, R.Shop.DETAIL)
	end
	if screen == S.CREDIT_PACKS then
		state.packId = d.guid()
		packStep(d, player, state, R.Packs.SHOWN)
	end
end)

-- Cette méthode permet de compter l'apparition d'un joueur en partie lorsque son personnage arrive : premier spawn,
-- étape En partie, deuxième manche commencée après une manche finie.
Analytics.spawned = guarded("spawned", function(d: Deps, player: Player)
	local state = states[player]
	if not state then
		return
	end
	state.phase = "vivant"
	onboarding(d, player, state, R.Onboarding.SPAWN)
	session(d, player, state, R.Session.IN_GAME)
	if state.rounds >= 1 then
		onboarding(d, player, state, R.Onboarding.SECOND_ROUND)
	end
end)

-- Cette méthode permet de compter le premier tir accepté d'un joueur lorsqu'il part (arme à distance ou couteau).
Analytics.shot = guarded("shot", function(d: Deps, player: Player)
	local state = states[player]
	if state then
		onboarding(d, player, state, R.Onboarding.SHOT)
	end
end)

-- Cette méthode permet de compter le premier dégât infligé par un joueur lorsqu'une touche fait baisser des PV.
Analytics.damage = guarded("damage", function(d: Deps, player: Player)
	local state = states[player]
	if state then
		onboarding(d, player, state, R.Onboarding.DAMAGE)
	end
end)

-- Cette méthode permet de compter une mort lorsqu'elle est comptée par le round : pour la victime joueur, première
-- mort, série sans kill (paliers) et événement Mort (zone, cause) ; pour le tueur joueur, premier kill et série remise
-- à zéro. Rien sur un serveur d'entraînement.
Analytics.death = guarded("death", function(d: Deps, victim: Player?, killer: Player?, cause: string, zone: string)
	if d.training then
		return
	end
	local victimState = if victim then states[victim] else nil
	if victim and victimState then
		victimState.phase = "mort"
		onboarding(d, victim, victimState, R.Onboarding.DEATH)
		victimState.deathStreak += 1
		if R.isStreakMark(victimState.deathStreak) then
			custom(
				d,
				victim,
				R.Event.DEATH_STREAK,
				victimState.deathStreak,
				{ [F.ONE] = R.newcomerLabel(victimState.newcomer) }
			)
		end
		custom(d, victim, R.Event.DEATH, 1, { [F.ONE] = zone, [F.TWO] = cause })
	end
	local killerState = if killer then states[killer] else nil
	if killer and killerState and killer ~= victim then
		onboarding(d, killer, killerState, R.Onboarding.KILL)
		killerState.deathStreak = 0
	end
end)

-- Cette méthode permet de compter une manche finie pour un joueur en jeu lorsqu'elle se termine : première manche
-- finie, étapes 1 et 3 manches du funnel de session, bannière de fin.
Analytics.roundEnd = guarded("roundEnd", function(d: Deps, player: Player)
	local state = states[player]
	if not state then
		return
	end
	state.rounds += 1
	state.phase = "resultat"
	onboarding(d, player, state, R.Onboarding.ROUND_END)
	session(d, player, state, R.Session.ROUND_1)
	if state.rounds >= 3 then
		session(d, player, state, R.Session.ROUND_3)
	end
end)

-- Cette méthode permet de compter un retour au menu depuis la partie lorsque le joueur choisit MENU PRINCIPAL.
Analytics.leftRound = guarded("leftRound", function(d: Deps, player: Player)
	local state = states[player]
	if not state then
		return
	end
	state.phase = "arrivee"
	session(d, player, state, R.Session.BACK_TO_MENU)
end)

-- Cette méthode permet de suivre un achat de caisse lorsque le serveur a répondu : étape ACHETER (toute demande
-- traitée), puis pour un achat réussi étape Caisse ouverte, crédits dépensés (prix) et remboursés (doublon), skin
-- retenu pour l'étape Skin équipé. `balance` : solde après l'achat (nil s'il n'est pas connu).
Analytics.crateBought = guarded(
	"crateBought",
	function(d: Deps, player: Player, crateId: string, result: any, price: number?, balance: number?)
		local state = states[player]
		if not state then
			return
		end
		shop(d, player, state, R.Shop.BUY)
		if type(result) ~= "table" or result.ok ~= true then
			return
		end
		shop(d, player, state, R.Shop.OPENED)
		if type(result.skinId) == "string" then
			state.boughtSkins[result.skinId] = state.shopId :: string
		end
		local refund = if type(result.refund) == "number" then result.refund else 0
		local final = balance or 0
		if type(price) == "number" then
			economy(d, player, false, price, final - refund, R.Transaction.SHOP, crateId)
		end
		economy(d, player, true, refund, final, R.Transaction.SHOP, crateId)
	end
)

-- Cette méthode permet de compter l'étape Skin équipé lorsqu'un joueur équipe un skin obtenu par une caisse achetée
-- pendant la session (une fois par visite du shop).
Analytics.equipped = guarded("equipped", function(d: Deps, player: Player, skinId: string?)
	local state = states[player]
	if not (state and skinId) then
		return
	end
	local shopId = state.boughtSkins[skinId]
	if not shopId or state.equippedShops[shopId] then
		return
	end
	state.equippedShops[shopId] = true
	funnelStep(d, player, R.SHOP_FUNNEL, shopId, R.Shop.EQUIPPED)
end)

-- Cette méthode permet de compter l'ouverture du prompt Roblox d'un pack de crédits lorsque le serveur l'a demandée.
Analytics.packPrompted = guarded("packPrompted", function(d: Deps, player: Player, packId: string)
	local state = states[player]
	if state then
		packStep(d, player, state, R.Packs.PROMPT, packId)
	end
end)

-- Cette méthode permet de compter un reçu de pack traité lorsque ses crédits sont écrits : étape Reçu traité et
-- crédits achetés (IAP). `credits` : crédits réellement ajoutés ; `balance` : solde après le reçu.
Analytics.packCredited = guarded(
	"packCredited",
	function(d: Deps, player: Player, packId: string, credits: number, balance: number?)
		local state = states[player]
		if state then
			packStep(d, player, state, R.Packs.RECEIPT, packId)
		end
		economy(d, player, true, credits, balance or credits, R.Transaction.IAP, packId)
	end
)

-- Cette méthode permet de compter des crédits gagnés en jouant lorsqu'ils sont crédités (kill, manche, victoire).
Analytics.playGain = guarded("playGain", function(d: Deps, player: Player, amount: number, balance: number?)
	economy(d, player, true, amount, balance or amount, R.Transaction.GAMEPLAY, R.PLAY_GAIN_SKU)
end)

-- Cette méthode permet de clore le suivi d'un joueur lorsqu'il quitte le jeu : temps sur le dernier écran, étape
-- Départ, événement Depart (durée de la session, endroit, manches jouées, ancienneté).
Analytics.playerRemoving = guarded("playerRemoving", function(d: Deps, player: Player)
	local state = states[player]
	if not state then
		return
	end
	states[player] = nil
	local now = d.clock()
	closeScreen(d, player, state, now)
	session(d, player, state, R.Session.DEPARTURE)
	custom(d, player, R.Event.DEPARTURE, math.floor(now - state.joinedAt + 0.5), {
		[F.ONE] = R.location(state.screen, state.phase),
		[F.TWO] = R.roundsBucket(state.rounds),
		[F.THREE] = R.newcomerLabel(state.newcomer),
	})
end)

return Analytics
