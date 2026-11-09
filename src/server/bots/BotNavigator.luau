-- Suivi de chemin d'un bot (#140) : choisit une destination (au hasard parmi les points de passage, en attendant les
-- états de #141), cherche le chemin de case à case (NavPlan), puis donne à chaque tick l'intention de mouvement à
-- BotMotion : direction (raccourcie en ligne droite quand les cases sont alignées), saut devant un rebord à monter,
-- grimpe d'une échelle. Un bot qui ne se rapproche plus de sa cible recalcule son chemin ; après NAV_MAX_REPATH
-- essais, l'arête ratée est écartée NAV_BAN_TIME secondes et il change de destination.
-- Après une apparition (lancé depuis le soleil), il attend d'être au sol puis repart de la case la plus proche.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local NavRules = require(ReplicatedStorage.Shared.NavRules)
local NavPlan = require(script.Parent.NavPlan)

local BotNavigator = {}
BotNavigator.__index = BotNavigator

export type Intent = {
	wishdir: Vector3, -- direction horizontale voulue (zéro : rester sur place)
	jump: boolean,
	climb: boolean, -- grimper si le bot est dans le volume d'une échelle
	airControl: boolean, -- en l'air, viser la cible (saut sur un rebord)
}

export type BotNavigator = typeof(setmetatable(
	{} :: {
		rng: Random,
		destination: number?, -- point de passage visé
		lastWaypoint: number?,
		cells: { number }?,
		points: { Vector3 },
		kinds: { number },
		index: number,
		best: number,
		stalled: number,
		repaths: number,
		hold: number,
		banned: { [number]: number }, -- clé d'arête → fin de la mise à l'écart (os.clock)
	},
	BotNavigator
))

-- Bilan de tous les bots depuis le démarrage (debug Studio : NavDebug l'affiche dans la console)
BotNavigator.stats = { reached = 0, banned = 0, passed = { 0, 0, 0, 0 } } -- passed : arêtes franchies par type

local IDLE: Intent = { wishdir = Vector3.zero, jump = false, climb = false, airControl = false }

-- Cette méthode permet de créer le suivi de chemin d'un bot lorsqu'il apparaît.
function BotNavigator.new(rng: Random): BotNavigator
	return setmetatable({
		rng = rng,
		destination = nil,
		lastWaypoint = nil,
		cells = nil,
		points = {},
		kinds = {},
		index = 1,
		best = math.huge,
		stalled = 0,
		repaths = 0,
		hold = 0,
		banned = {},
	}, BotNavigator)
end

-- Cette méthode permet de lire le chemin restant lorsqu'un affichage de debug le dessine (nil sans chemin).
function BotNavigator.remainingPath(self: BotNavigator): { Vector3 }?
	if not self.cells then
		return nil
	end
	return table.move(self.points, math.max(self.index - 1, 1), #self.points, 1, {})
end

-- Cette méthode permet de lister les arêtes écartées encore actives lorsqu'un chemin est cherché.
function BotNavigator._activeBans(self: BotNavigator): { [number]: boolean }
	local now = os.clock()
	local active = {}
	for key, untilTime in self.banned do
		if untilTime > now then
			active[key] = true
		else
			self.banned[key] = nil
		end
	end
	return active
end

-- Cette méthode permet de calculer un chemin de la case sous les pieds vers la destination lorsque le bot n'en a pas
-- (nouvelle destination tirée si besoin) ; renvoie false si aucun chemin n'est possible pour l'instant.
function BotNavigator._plan(self: BotNavigator, plan: NavPlan.Plan, foot: Vector3): boolean
	local start = NavPlan.nearestCell(plan, foot, BotConfig.NAV_NEAREST_RADIUS)
	if not start then
		return false
	end
	local bans = self:_activeBans()
	for _ = 1, 4 do
		if not self.destination then
			self.destination = NavPlan.randomWaypoint(plan, self.rng, self.lastWaypoint)
		end
		local wp = self.destination and plan.waypoints[self.destination]
		if not wp then
			return false
		end
		local cells = NavPlan.findPath(plan, start, wp.cell, bans)
		if cells then
			local positions, out, outKind = plan.graph.positions, plan.graph.out, plan.graph.outKind
			local points, kinds = {}, {}
			for i, cell in cells do
				points[i] = positions[cell]
				kinds[i] = NavRules.WALK
				if i > 1 then
					local prev = cells[i - 1]
					local k = table.find(out[prev], cell)
					kinds[i] = if k then outKind[prev][k] else NavRules.WALK
				end
			end
			self.cells, self.points, self.kinds = cells, points, kinds
			self.index = math.min(2, #cells)
			self.best, self.stalled = math.huge, 0
			return true
		end
		self.destination = nil -- injoignable avec les arêtes écartées : autre tirage
	end
	return false
end

-- Cette méthode permet d'oublier le chemin courant lorsqu'il faut le recalculer (gêne, chute hors du trajet).
function BotNavigator._dropPath(self: BotNavigator)
	self.cells = nil
	self.best, self.stalled = math.huge, 0
end

-- Cette méthode permet de donner l'intention de mouvement du tick lorsque BotMotion joue un tick : foot = sous les
-- pieds, speed = vitesse horizontale. Sans plan (pas encore construit), le bot attend.
function BotNavigator.update(
	self: BotNavigator,
	plan: NavPlan.Plan?,
	foot: Vector3,
	grounded: boolean,
	speed: number,
	dt: number
): Intent
	if not plan then
		return IDLE
	end
	if self.hold > 0 then
		self.hold -= dt
		return IDLE
	end
	if not self.cells then
		-- En l'air (lancement, chute) : on attend l'atterrissage pour repartir de la case la plus proche
		if not grounded or not self:_plan(plan, foot) then
			return IDLE
		end
	end

	local points, kinds = self.points, self.kinds
	while self.index <= #points and NavRules.reached(foot, points[self.index]) do
		local passed = BotNavigator.stats.passed
		passed[kinds[self.index]] += 1
		self.index += 1
		self.best, self.stalled, self.repaths = math.huge, 0, 0
	end
	if self.index > #points then
		-- Arrivé : courte pause, puis destination suivante
		self.lastWaypoint = self.destination
		self.destination = nil
		BotNavigator.stats.reached += 1
		self:_dropPath()
		self.hold = BotConfig.NAV_HOLD_MIN + (BotConfig.NAV_HOLD_MAX - BotConfig.NAV_HOLD_MIN) * self.rng:NextNumber()
		return IDLE
	end

	local kind = kinds[self.index]
	local goal = points[self.index]
	-- Tombé sous le trajet (rebord raté) : chemin recalculé depuis là où il est
	if grounded and kind ~= NavRules.LADDER and goal.Y - foot.Y > BotConfig.NAV_JUMP_UP_MAX + 1 then
		self:_dropPath()
		return IDLE
	end

	local targetIndex = if kind == NavRules.WALK
		then NavRules.lookAhead(foot, points, kinds, self.index)
		else self.index
	local target = points[targetIndex]
	local flat = Vector3.new(target.X - foot.X, 0, target.Z - foot.Z)
	local wishdir = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero

	local jump = false
	if kind == NavRules.JUMP and grounded and self.index > 1 then
		local ledge = (points[self.index - 1] + goal) / 2
		local toLedge = Vector3.new(ledge.X - foot.X, 0, ledge.Z - foot.Z).Magnitude
		jump = NavRules.shouldJump(toLedge, speed)
	end

	local dist = (goal - foot).Magnitude
	self.best, self.stalled = NavRules.progress(self.best, self.stalled, dist, dt)
	if self.stalled >= BotConfig.NAV_STUCK_TIME then
		self.repaths += 1
		if self.repaths >= BotConfig.NAV_MAX_REPATH and self.cells and self.index > 1 then
			-- Arête ratée plusieurs fois : écartée un moment, et autre destination
			local cells = self.cells :: { number }
			local key = NavRules.edgeKey(cells[self.index - 1], cells[self.index])
			self.banned[key] = os.clock() + BotConfig.NAV_BAN_TIME
			BotNavigator.stats.banned += 1
			warn(
				string.format(
					"[Nav] arête %s ratée (%s → %s), écartée %d s",
					NavRules.KIND_NAMES[kind],
					tostring(points[self.index - 1]),
					tostring(goal),
					BotConfig.NAV_BAN_TIME
				)
			)
			self.repaths = 0
			self.destination = nil
		end
		self:_dropPath()
		return IDLE
	end

	return {
		wishdir = wishdir,
		jump = jump,
		climb = kind == NavRules.LADDER,
		airControl = kind == NavRules.JUMP or kind == NavRules.LADDER,
	}
end

return BotNavigator
