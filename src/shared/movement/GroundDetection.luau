-- Détection du sol sous un personnage. Une instance par personnage (#139) : filtre de rayons et dimensions propres.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CollisionGroups = require(ReplicatedStorage.Shared.CollisionGroups)
local Config = require(ReplicatedStorage.Shared.MovementConfig)
local PhysicsUtils = require(ReplicatedStorage.Shared.PhysicsUtils)
local CharacterDimensions = require(script.Parent.CharacterDimensions)

local CAST_SKIN = 0.5 -- augmenté de 0.15 : détection jusqu'à ~1.45 studs sous les pieds

export type GroundInfo = {
	onGround: boolean,
	normal: Vector3,
	slopeAngle: number,
	distance: number,
	material: Enum.Material,
	hitPosition: Vector3,
}

local GROUND_MISS: GroundInfo = {
	onGround = false,
	normal = Vector3.yAxis,
	slopeAngle = 0,
	distance = math.huge,
	material = Enum.Material.Air,
	hitPosition = Vector3.zero,
}

local GroundDetection = {}
GroundDetection.__index = GroundDetection

export type GroundDetection = typeof(setmetatable(
	{} :: {
		params: RaycastParams,
		castRadius: number,
		halfHeight: number,
		centerOffset: number,
		castDist: number,
		castDir: Vector3,
	},
	GroundDetection
))

-- Cette méthode permet de préparer la détection du sol d'un personnage lorsqu'il apparaît (ses pièces sont exclues
-- des rayons, dimensions debout mesurées sur son rig).
function GroundDetection.new(character: Model, dims: CharacterDimensions.CharacterDimensions): GroundDetection
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, workspace.CurrentCamera }
	CollisionGroups.ignoreCharacters(params)
	local stand = dims:getStand()
	local castDist = stand.halfHeight + CAST_SKIN
	return setmetatable({
		params = params,
		castRadius = stand.radius - 0.05,
		halfHeight = stand.halfHeight,
		centerOffset = stand.centerOffset,
		castDist = castDist,
		castDir = Vector3.new(0, -castDist, 0),
	}, GroundDetection)
end

-- Retourne l'état du sol sous la racine placée en rootPosition.
-- velocityY  : vitesse verticale courante (garde "bMovingUpRapidly" Source)
-- wasGrounded: était-on au sol la frame précédente (hystérésis anti-flicker)
function GroundDetection.getGroundInfo(
	self: GroundDetection,
	rootPosition: Vector3,
	velocityY: number?,
	wasGrounded: boolean?
): GroundInfo
	local params = self.params
	local castRadius, halfHeight, castDist, castDir = self.castRadius, self.halfHeight, self.castDist, self.castDir
	local origin = rootPosition + Vector3.new(0, self.centerOffset, 0)

	-- Détection par spherecast (capsule tolérante), avec repli sur 4 quadrants
	-- pour ne pas rater le sol au bord d'une marche (≈ TryTouchGroundInQuadrants).
	local result = workspace:Spherecast(origin, castRadius, castDir, params)
	if not result then
		local q = castRadius * 0.6
		for _, off in ipairs({
			Vector3.new(q, 0, 0),
			Vector3.new(-q, 0, 0),
			Vector3.new(0, 0, q),
			Vector3.new(0, 0, -q),
		}) do
			result = workspace:Spherecast(origin + off, castRadius, castDir, params)
			if result then
				break
			end
		end
	end
	if not result then
		return GROUND_MISS
	end

	-- Muret plus bas que le centre du corps : la sphère accroche son arête, au-dessus de la hauteur de marche, alors que
	-- le sol est plus bas. Ce contact n'est pas le sol (sinon : normale d'arête non marchable, joueur passé en l'air à
	-- chaque frame, collé au muret au lieu de le longer). On relance la sonde depuis la hauteur de marche.
	local travel = result.Distance
	local feetY = origin.Y - halfHeight
	local lowOrigin = Vector3.new(origin.X, feetY + Config.STEPUP_HEIGHT + castRadius, origin.Z)
	local drop = origin.Y - lowOrigin.Y
	if drop > 0 and PhysicsUtils.isSideContact(result.Position.Y, feetY, Config.STEPUP_HEIGHT) then
		local low = workspace:Spherecast(lowOrigin, castRadius, Vector3.new(0, -(castDist - drop), 0), params)
		if not low or PhysicsUtils.isSideContact(low.Position.Y, feetY, Config.STEPUP_HEIGHT) then
			return GROUND_MISS
		end
		result = low
		travel = low.Distance + drop
		origin = lowOrigin
	end

	-- NORMALE DE CLASSIFICATION : le spherecast renvoie une normale d'ARÊTE sur les
	-- jointures entre rampes. On relance un raycast fin droit sous le centre pour
	-- récupérer la vraie normale de FACE (stable d'un segment à l'autre).
	-- Longueur bornée au contact réel : sinon sur rampe courbe le rayon file plus bas
	-- et lit une face plus plate (ou le sol SOUS la rampe) → faux "marchable".
	local normal = result.Normal
	local probeLen = result.Distance + castRadius + 0.1 -- depuis `origin` (relevée si la sonde a été relancée)
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

	local cosAngle = math.clamp(normal:Dot(Vector3.yAxis), -1, 1)
	local slopeAngle = math.deg(math.acos(cosAngle))

	-- Hystérésis : marge supplémentaire pour RESTER au sol (évite l'oscillation au seuil).
	local maxAngle = Config.SLOPE_ANGLE_MAX + (wasGrounded and 3 or 0)
	local onGround = slopeAngle <= maxAngle

	return {
		onGround = onGround,
		normal = normal,
		slopeAngle = slopeAngle,
		distance = travel - halfHeight,
		material = result.Material,
		hitPosition = result.Position,
	}
end

return GroundDetection
