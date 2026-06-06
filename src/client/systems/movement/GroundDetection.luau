local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage.Shared.MovementConfig)
local CharacterDimensions = require(script.Parent.CharacterDimensions)

local CAST_RADIUS = Config.CHAR_RADIUS - 0.05
local HALF_HEIGHT = Config.CHAR_HEIGHT_STAND / 2
local CENTER_OFFSET = 0
local CAST_SKIN   = 0.5    -- augmenté de 0.15 : détection jusqu'à ~1.45 studs sous les pieds
local CAST_DIST   = HALF_HEIGHT + CAST_SKIN
local CAST_DIR    = Vector3.new(0, -CAST_DIST, 0)

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

export type GroundInfo = {
	onGround    : boolean,
	normal      : Vector3,
	slopeAngle  : number,
	distance    : number,
	material    : Enum.Material,
	hitPosition : Vector3,
}

local GROUND_MISS: GroundInfo = {
	onGround    = false,
	normal      = Vector3.yAxis,
	slopeAngle  = 0,
	distance    = math.huge,
	material    = Enum.Material.Air,
	hitPosition = Vector3.zero,
}

local GroundDetection = {}

local function refreshDims()
	local stand = CharacterDimensions.getStand()
	CAST_RADIUS = stand.radius - 0.05
	HALF_HEIGHT = stand.halfHeight
	CENTER_OFFSET = stand.centerOffset
	CAST_DIST = HALF_HEIGHT + CAST_SKIN
	CAST_DIR = Vector3.new(0, -CAST_DIST, 0)
end

-- Appeler à chaque CharacterAdded pour exclure les parts du character du cast.
function GroundDetection.init(character: Model)
	params.FilterDescendantsInstances = { character, workspace.CurrentCamera }
	refreshDims()
end

-- Retourne l'état du sol sous rootPart.
-- velocityY  : vitesse verticale courante (garde "bMovingUpRapidly" Source)
-- wasGrounded: était-on au sol la frame précédente (hystérésis anti-flicker)
function GroundDetection.getGroundInfo(rootPart: BasePart, velocityY: number?, wasGrounded: boolean?): GroundInfo
	local origin = rootPart.Position + Vector3.new(0, CENTER_OFFSET, 0)

	-- Détection par spherecast (capsule tolérante), avec repli sur 4 quadrants
	-- pour ne pas rater le sol au bord d'une marche (≈ TryTouchGroundInQuadrants).
	local result = workspace:Spherecast(origin, CAST_RADIUS, CAST_DIR, params)
	if not result then
		local q = CAST_RADIUS * 0.6
		for _, off in ipairs({
			Vector3.new(q,0,0), Vector3.new(-q,0,0),
			Vector3.new(0,0,q), Vector3.new(0,0,-q),
		}) do
			result = workspace:Spherecast(origin + off, CAST_RADIUS, CAST_DIR, params)
			if result then break end
		end
	end
	if not result then
		return GROUND_MISS
	end

	-- NORMALE DE CLASSIFICATION : le spherecast renvoie une normale d'ARÊTE sur les
	-- jointures entre rampes. On relance un raycast fin droit sous le centre pour
	-- récupérer la vraie normale de FACE (stable d'un segment à l'autre).
	-- Longueur bornée au contact réel : sinon sur rampe courbe le rayon file plus bas
	-- et lit une face plus plate (ou le sol SOUS la rampe) → faux "marchable".
	local normal = result.Normal
	local probeLen = result.Distance + CAST_RADIUS + 0.1
	local centerRay = workspace:Raycast(origin, Vector3.new(0, -probeLen, 0), params)
	if centerRay then
		normal = centerRay.Normal
	end

	-- Garde "montée rapide" : on ne grounde pas si on monte vite (départ de rampe surf).
	if velocityY and velocityY > Config.JUMP_VELOCITY * 0.5 then
		return GROUND_MISS
	end

	-- Séparateur dur surf/sol : une surface non-marchable ne grounde JAMAIS.
	-- On reste airborne et WallSlide gère le glissement.
	if normal.Y < Config.SURF_NORMAL_Y then
		return GROUND_MISS
	end

	local cosAngle   = math.clamp(normal:Dot(Vector3.yAxis), -1, 1)
	local slopeAngle = math.deg(math.acos(cosAngle))

	-- Hystérésis : marge supplémentaire pour RESTER au sol (évite l'oscillation au seuil).
	local maxAngle = Config.SLOPE_ANGLE_MAX + (wasGrounded and 3 or 0)
	local onGround = slopeAngle <= maxAngle

	return {
		onGround    = onGround,
		normal      = normal,
		slopeAngle  = slopeAngle,
		distance    = result.Distance - HALF_HEIGHT,
		material    = result.Material,
		hitPosition = result.Position,
	}
end

return GroundDetection
