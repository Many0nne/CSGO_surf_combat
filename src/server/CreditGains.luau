-- Gains de crédits en jouant (#394), branchés par init.server : kill crédité tout de suite (`onKill`, appelé par
-- `onDeathCounted`, seul point commun de la mort normale et du départ par MENU PRINCIPAL), manche jouée et victoire en
-- fin de manche (`onRoundEnd`). Barème et plafonds dans EconomyRules ; plafond de la manche tenu ici, plafond du jour
-- par le portefeuille (WalletStore.addPlayGain, réappliqué à l'écriture).
-- Pas de gain : serveur d'entraînement, kill hors manche active, solde qui ne peut pas changer (pas chargé, sauvegarde
-- coupée : Studio sans accès aux API). Temps en vie : compté de l'apparition dans une manche active jusqu'à la mort,
-- au retour au menu ou à la fin de la manche (`onSpawn`, `onDespawn`). Activité réelle (#401, manche sans kill) :
-- distance horizontale sur les positions acceptées par CharacterSync (`onMove`) et actions de combat acceptées par le
-- serveur (`onAction`), comptées seulement pendant une vie de la manche.
-- Attribut informatif `RoundCredits` du Player (gains de la manche, posé en fin de manche, effacé à chaque apparition),
-- lu par le bandeau de fin de manche (RoundHUD) avec `DailyCredits` (InventoryStore). Aucun remote.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyRules = require(ReplicatedStorage.Shared.EconomyRules)

-- Participant vu par ce module (Participants.Participant) : seuls ces champs sont lus
type Participant = { id: number, isBot: boolean, player: Player? }
-- Dépendances, injectées par init (testables sans DataStore) : mode entraînement, manche active, crédit d'un gain en
-- jouant (montant crédité, nil si le solde ne peut pas changer), horloges (os.time, os.clock), journal de Studio
export type Deps = {
	training: boolean,
	roundActive: () -> boolean,
	credit: (player: Player, amount: number, day: number) -> number?,
	now: () -> number,
	clock: () -> number,
	log: ((string) -> ())?,
}
-- Manche d'un joueur : kills (comptés même au plafond, pour « manche jouée »), crédits gagnés, secondes en vie
-- cumulées, début de la vie en cours (nil : pas en vie dans la manche) et son personnage, activité réelle (#401 :
-- distance horizontale en studs, actions de combat acceptées)
type RoundState = {
	kills: number,
	earned: number,
	alive: number,
	aliveSince: number?,
	character: Instance?,
	distance: number,
	actions: number,
}

local CreditGains = {}

local deps: Deps? = nil
local rounds: { [Player]: RoundState } = {}

-- Cette méthode permet de brancher les dépendances lorsque le serveur démarre (ou qu'un test monte le module) ; les
-- manches en cours sont oubliées.
function CreditGains.init(dependencies: Deps)
	deps = dependencies
	rounds = {}
end

-- Cette méthode permet de créer une manche vide lorsqu'un joueur y gagne ou y apparaît pour la première fois.
local function newRound(): RoundState
	return { kills = 0, earned = 0, alive = 0, aliveSince = nil, character = nil, distance = 0, actions = 0 }
end

-- Cette méthode permet de lire (ou créer) la manche d'un joueur lorsqu'un gain ou une apparition la touche.
local function roundOf(player: Player): RoundState
	local state = rounds[player]
	if not state then
		state = newRound()
		rounds[player] = state
	end
	return state
end

-- Cette méthode permet de créditer un gain sous le plafond de la manche puis celui du jour (portefeuille) lorsqu'un kill
-- ou une fin de manche rapporte ; renvoie le montant crédité, nil si le solde ne peut pas changer.
local function credit(d: Deps, player: Player, state: RoundState, amount: number): number?
	-- Au plafond de la manche, montant 0 : le portefeuille répond quand même 0 ou nil (solde qui ne peut pas changer)
	local credited = d.credit(player, EconomyRules.capRound(amount, state.earned), EconomyRules.day(d.now()))
	if credited then
		state.earned += credited
	end
	return credited
end

-- Cette méthode permet de créditer le kill d'un joueur (joueur tué : PLAYER_KILL, bot : BOT_KILL) lorsque
-- `onDeathCounted` compte une mort avec un tueur ; rien en entraînement, hors manche active ou pour un bot tueur.
function CreditGains.onKill(killer: Participant?, victim: Participant)
	local d = deps
	if not d or not killer or killer.isBot or not killer.player or killer.id == victim.id then
		return
	end
	if not EconomyRules.canEarn(d.training, d.roundActive()) then
		return
	end
	local player = killer.player :: Player
	local state = roundOf(player)
	state.kills += 1
	local credited = credit(d, player, state, EconomyRules.killGain(victim.isBot))
	if d.log then
		d.log(string.format("kill %s : +%s (manche %d)", player.Name, tostring(credited), state.earned))
	end
end

-- Cette méthode permet d'arrêter le compte du temps en vie d'une manche lorsque la vie en cours se termine.
local function endLife(d: Deps, state: RoundState)
	if state.aliveSince ~= nil then
		state.alive += math.max(d.clock() - state.aliveSince, 0)
		state.aliveSince = nil
	end
	state.character = nil
end

-- Cette méthode permet de démarrer le temps en vie d'un joueur et d'effacer les gains de sa manche précédente lorsque
-- son personnage apparaît dans une manche active.
function CreditGains.onSpawn(player: Player, character: Instance?)
	local d = deps
	-- Hors manche active (personnage arrivé pendant la bannière de fin, détruit aussitôt) : le bandeau garde ses gains
	if not d or not EconomyRules.canEarn(d.training, d.roundActive()) then
		return
	end
	player:SetAttribute(EconomyRules.ROUND_ATTRIBUTE, nil)
	local state = roundOf(player)
	-- Vie précédente pas encore close (mort manquée) : comptée jusqu'ici, pas en double
	endLife(d, state)
	state.aliveSince = d.clock()
	state.character = character
end

-- Cette méthode permet d'arrêter le temps en vie d'un joueur lorsque son personnage meurt ou disparaît ; un autre
-- personnage que celui de la vie en cours (corps détruit en retard) est ignoré.
function CreditGains.onDespawn(player: Player, character: Instance?)
	local d = deps
	local state = rounds[player]
	if not d or not state or (character ~= nil and state.character ~= nil and character ~= state.character) then
		return
	end
	endLife(d, state)
end

-- Cette méthode permet de lire la manche d'un joueur lorsque son activité est comptée : nil s'il n'est pas en vie dans
-- une manche active avec ce personnage (bannière de fin, corps d'une vie passée, personnage d'avant un retour au menu).
local function livingRound(d: Deps, player: Player, character: Instance?): RoundState?
	local state = rounds[player]
	if not state or state.aliveSince == nil or not d.roundActive() then
		return nil
	end
	if character ~= nil and state.character ~= nil and character ~= state.character then
		return nil
	end
	return state
end

-- Cette méthode permet d'ajouter la distance horizontale d'un pas à l'activité de la manche lorsque CharacterSync
-- accepte une position du joueur ; `from` = position acceptée précédente du même personnage (nil : premier paquet,
-- ignoré). Une position refusée n'arrive jamais ici, et une téléportation du serveur repart de son point d'arrivée.
function CreditGains.onMove(player: Player, character: Instance?, from: Vector3?, to: Vector3)
	local d = deps
	if not d or not from then
		return
	end
	local state = livingRound(d, player, character)
	if state then
		state.distance += EconomyRules.horizontalStep(from, to)
	end
end

-- Cette méthode permet de compter une action de combat à l'activité de la manche lorsque le serveur l'accepte (tir
-- relayé, touche ou coup de mêlée validés par le Validator).
function CreditGains.onAction(player: Player)
	local d = deps
	if not d then
		return
	end
	local state = livingRound(d, player, nil)
	if state then
		state.actions += 1
	end
end

-- Cette méthode permet de créditer manche jouée et victoire des joueurs en jeu et de publier leurs gains (`RoundCredits`)
-- lorsque RoundManager termine une manche, avant la destruction des personnages ; toutes les manches repartent de zéro.
function CreditGains.onRoundEnd(participants: { Participant }, winner: Participant?)
	local d = deps
	if not d then
		return
	end
	local finished = rounds
	rounds = {}
	if d.training then
		return
	end
	for _, participant in participants do
		local player = participant.player
		if player and not participant.isBot then
			local state = finished[player] or newRound()
			local alive = state.alive + (if state.aliveSince then math.max(d.clock() - state.aliveSince, 0) else 0)
			local won = winner ~= nil and winner.id == participant.id
			-- Même pour 0 : le portefeuille répond nil si le solde ne peut pas changer
			local activity = { distance = state.distance, actions = state.actions }
			local credited = credit(d, player, state, EconomyRules.roundGain(state.kills, alive, activity, won))
			-- Solde qui ne peut pas changer : rien à montrer (pas de « +0 » trompeur)
			if credited ~= nil then
				player:SetAttribute(EconomyRules.ROUND_ATTRIBUTE, state.earned)
			end
			if d.log then
				d.log(
					string.format(
						"fin de manche %s : kills %d, en vie %.0f s, distance %.0f studs, actions %d, victoire %s, +%s, manche %d, jour %s",
						player.Name,
						state.kills,
						alive,
						state.distance,
						state.actions,
						tostring(won),
						tostring(credited),
						state.earned,
						tostring(player:GetAttribute(EconomyRules.DAILY_ATTRIBUTE))
					)
				)
			end
		end
	end
end

-- Cette méthode permet d'oublier la manche d'un joueur lorsqu'il quitte le serveur.
function CreditGains.forget(player: Player)
	rounds[player] = nil
end

return CreditGains
