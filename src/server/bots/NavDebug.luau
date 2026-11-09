-- Affichage de debug du plan de navigation (#140), Studio uniquement : attribut Workspace DebugNav.
-- - true : points de passage (couleur et étiquette = note, type), arêtes entre points (gris marche, bleu descente,
--   orange saut, vert échelle), chemin restant de chaque bot (jaune) ;
-- - "cases" : en plus, chaque case du plan (vert : gardée, rouge : écartée, hors de la composante principale).
-- Tout est posé dans Workspace.NavDebug, créé par le serveur (visible par tous les clients du playtest). Bilan des
-- bots dans la console toutes les 30 s ([Nav] bilan), arêtes ratées en warn au fil de l'eau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local NavRules = require(ReplicatedStorage.Shared.NavRules)
local BotNavigator = require(script.Parent.BotNavigator)
local NavPlan = require(script.Parent.NavPlan)

local NavDebug = {}

local KIND_COLORS = {
	[NavRules.WALK] = Color3.fromRGB(200, 200, 200),
	[NavRules.DROP] = Color3.fromRGB(70, 140, 255),
	[NavRules.JUMP] = Color3.fromRGB(255, 150, 40),
	[NavRules.LADDER] = Color3.fromRGB(60, 220, 90),
}
local PATH_COLOR = Color3.fromRGB(255, 230, 40)
local LIFT = Vector3.new(0, 0.6, 0)

local root: Folder? = nil
local pathsFolder: Folder? = nil

-- Cette méthode permet de créer une pièce de debug sans collision ni requête lorsqu'on dessine le plan.
local function debugPart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Parent = parent
	return part
end

-- Cette méthode permet de tracer un segment entre deux points lorsqu'on dessine une arête ou un chemin.
local function segment(parent: Instance, a: Vector3, b: Vector3, color: Color3, width: number)
	local length = (b - a).Magnitude
	if length < 1e-3 then
		return
	end
	debugPart(parent, Vector3.new(width, width, length), CFrame.lookAt((a + b) / 2, b), color)
end

-- Cette méthode permet de dessiner le plan (points, arêtes, cases si demandé) lorsque l'attribut est activé.
local function drawPlan(plan: NavPlan.Plan, withCells: boolean)
	local folder = Instance.new("Folder")
	folder.Name = "NavDebug"
	folder.Archivable = false

	local maxScore = 1e-6
	for _, wp in plan.waypoints do
		maxScore = math.max(maxScore, wp.score)
	end
	local points = Instance.new("Folder")
	points.Name = "Points"
	points.Parent = folder
	for i, wp in plan.waypoints do
		local t = math.clamp(wp.score / maxScore, 0, 1)
		local color = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(60, 255, 60), t)
		local ball = debugPart(points, Vector3.one * 1.6, CFrame.new(wp.position + LIFT), color, Enum.PartType.Ball)
		ball.Name = "P" .. i
		ball:SetAttribute("Kind", wp.kind)
		ball:SetAttribute("Score", wp.score)
		ball:SetAttribute("View", wp.view)
		ball:SetAttribute("Cover", wp.cover)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(110, 22)
		gui.StudsOffset = Vector3.new(0, 1.6, 0)
		gui.MaxDistance = 140
		gui.AlwaysOnTop = true
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.3
		label.TextScaled = true
		label.Text = string.format("%d %s %.2f", i, wp.kind, wp.score)
		label.Parent = gui
		gui.Parent = ball
	end

	local edges = Instance.new("Folder")
	edges.Name = "Edges"
	edges.Parent = folder
	for a, targets in plan.waypointEdges do
		for b, kind in targets do
			local pa, pb = plan.waypoints[a].position + LIFT, plan.waypoints[b].position + LIFT
			-- Arête dans les deux sens : un seul trait ; à sens unique : trait plus fin, côté départ
			local back = plan.waypointEdges[b] and plan.waypointEdges[b][a]
			if not back or a < b then
				segment(edges, pa, if back then pb else pa:Lerp(pb, 0.85), KIND_COLORS[kind], if back then 0.3 else 0.2)
			end
		end
	end

	if withCells then
		local cells = Instance.new("Folder")
		cells.Name = "Cells"
		cells.Parent = folder
		for id, pos in plan.graph.positions do
			local color = if plan.keep[id] then Color3.fromRGB(60, 200, 90) else Color3.fromRGB(230, 50, 50)
			debugPart(cells, Vector3.new(0.6, 0.15, 0.6), CFrame.new(pos + Vector3.new(0, 0.1, 0)), color)
		end
	end

	local paths = Instance.new("Folder")
	paths.Name = "Paths"
	paths.Parent = folder
	pathsFolder = paths
	folder.Parent = workspace
	root = folder
end

-- Cette méthode permet de retirer l'affichage lorsque l'attribut est désactivé.
local function clear()
	if root then
		root:Destroy()
	end
	root, pathsFolder = nil, nil
end

-- Cette méthode permet de démarrer l'affichage de debug lorsque le serveur démarre en Studio ; navigators liste
-- le suivi de chemin des bots en jeu (chemins redessinés 4 fois par seconde).
function NavDebug.init(navigators: () -> { any })
	if not RunService:IsStudio() then
		return
	end
	local wanted: any = nil
	local function refresh()
		wanted = workspace:GetAttribute(BotConfig.DEBUG_NAV_ATTRIBUTE)
		clear()
	end
	workspace:GetAttributeChangedSignal(BotConfig.DEBUG_NAV_ATTRIBUTE):Connect(refresh)
	refresh()

	task.spawn(function()
		local nextReport = os.clock() + 30
		while true do
			task.wait(0.25)
			if os.clock() >= nextReport and #navigators() > 0 then
				nextReport = os.clock() + 30
				print(
					string.format(
						"[Nav] bilan : %d destinations atteintes, %d arêtes ratées ; franchies : %d descentes, %d sauts, %d échelles ; bhop : %d séries, %d sauts, %.0f studs/s au plus",
						BotNavigator.stats.reached,
						BotNavigator.stats.banned,
						BotNavigator.stats.passed[NavRules.DROP],
						BotNavigator.stats.passed[NavRules.JUMP],
						BotNavigator.stats.passed[NavRules.LADDER],
						BotNavigator.stats.bhopRuns,
						BotNavigator.stats.bhopJumps,
						BotNavigator.stats.bhopTopSpeed
					)
				)
			end
			local plan = NavPlan.get()
			if wanted and wanted ~= false and plan then
				if not root then
					drawPlan(plan, wanted == "cases")
				end
				local paths = pathsFolder :: Folder
				paths:ClearAllChildren()
				for _, navigator in navigators() do
					local path = navigator:remainingPath()
					if path then
						for i = 2, #path do
							segment(paths, path[i - 1] + LIFT * 2, path[i] + LIFT * 2, PATH_COLOR, 0.4)
						end
					end
				end
			end
		end
	end)
end

return NavDebug
