-- Plan de navigation de la map jouée (#140) : construit une fois au démarrage du serveur (NavBuilder), puis
-- interrogé par les bots (case la plus proche, chemin, destination, échelle). Tant qu'il n'est pas prêt, get()
-- renvoie nil et les bots attendent sur place.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local MapRules = require(ReplicatedStorage.Shared.MapRules)
local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)
local NavRules = require(ReplicatedStorage.Shared.NavRules)
local NavBuilder = require(script.Parent.NavBuilder)

export type Plan = NavBuilder.Plan

local NavPlan = {}

local current: Plan? = nil
local started = false

-- Cette méthode permet de lancer la construction du plan lorsque le serveur démarre et que la map est connue ; une
-- seule fois, en tâche de fond.
function NavPlan.start(map: Instance)
	if started then
		return
	end
	started = true
	task.spawn(function()
		local ok, result = pcall(NavBuilder.build, map)
		if not ok then
			warn("[Nav] construction du plan impossible : " .. tostring(result))
			return
		end
		local plan = result :: Plan
		local s = plan.stats
		print(
			string.format(
				"[Nav] %s : %d cases (%d gardées), %d points, arêtes marche %d / descente %d / saut %d / échelle %d, %d échelles, %.1f s (cases %.1f, marche %.1f, rebords %.1f, vue %.1f)",
				plan.mapName,
				s.cells,
				s.kept,
				s.waypoints,
				s.walk,
				s.drop,
				s.jump,
				s.ladder,
				#plan.ladders,
				s.seconds,
				s.secondsCells,
				s.secondsWalk,
				s.secondsLedges,
				s.secondsView
			)
		)
		current = plan
	end)
end

-- Cette méthode permet de lire le plan lorsqu'un bot en a besoin ; nil tant qu'il n'est pas construit.
function NavPlan.get(): Plan?
	return current
end

-- Cette méthode permet de trouver la case du plan sous un bot lorsqu'il a besoin d'un point de départ : la plus
-- proche des pieds dans radius studs, en préférant celles sous lui (il y tombe) à celles au-dessus ; keptOnly ne
-- garde que les cases d'où l'on va partout.
function NavPlan.nearestCell(plan: Plan, foot: Vector3, radius: number, keptOnly: boolean?): number?
	local G = plan.grid
	local cx, cz = math.floor((foot.X - plan.originX) / G), math.floor((foot.Z - plan.originZ) / G)
	local span = math.ceil(radius / G)
	local positions = plan.graph.positions
	local best, bestScore = nil, math.huge
	for dx = -span, span do
		for dz = -span, span do
			local list = plan.columns[NavBuilder.columnKey(cx + dx, cz + dz)]
			if list then
				for _, id in list do
					if not keptOnly or plan.keep[id] then
						local p = positions[id]
						local dy = p.Y - foot.Y
						local flat = Vector3.new(p.X - foot.X, 0, p.Z - foot.Z).Magnitude
						-- Au-dessus des pieds : il faudrait y monter, donc pénalisé ; loin dessous : coûte la chute
						local score = flat + (if dy > 0 then dy * 3 else -dy * 0.3)
						if
							flat <= radius
							and dy <= BotConfig.NAV_REACH_DY + MovementConfig.STEPUP_HEIGHT
							and score < bestScore
						then
							best, bestScore = id, score
						end
					end
				end
			end
		end
	end
	return best
end

-- Cette méthode permet de chercher un chemin de case à case lorsqu'un bot change de destination ou se replace ;
-- banned écarte les arêtes ratées par ce bot.
function NavPlan.findPath(plan: Plan, from: number, to: number, banned: { [number]: boolean }?): { number }?
	return NavRules.findPath(plan.graph, from, to, banned)
end

-- Cette méthode permet de tirer une destination lorsqu'un bot n'en a plus (#140 : au hasard, hors du point où il
-- se trouve ; la note dynamique viendra avec les états, #141). Renvoie l'index du point de passage.
function NavPlan.randomWaypoint(plan: Plan, rng: Random, avoid: number?): number?
	local count = #plan.waypoints
	if count == 0 then
		return nil
	end
	local pick = rng:NextInteger(1, count)
	if pick == avoid and count > 1 then
		pick = pick % count + 1
	end
	return pick
end

-- Cette méthode permet de trouver l'échelle dont le volume contient une position lorsqu'un bot grimpe : renvoie sa
-- normale sortante, ou nil.
function NavPlan.ladderAt(plan: Plan, pos: Vector3): Vector3?
	for _, ladder in plan.ladders do
		if MapRules.contains(ladder.cframe, ladder.size, pos, MovementConfig.CHAR_RADIUS) then
			return ladder.normal
		end
	end
	return nil
end

return NavPlan
