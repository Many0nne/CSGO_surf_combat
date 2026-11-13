-- Montée de petits obstacles au sol. Une instance par personnage (#139) : filtre de rayons et dimensions propres.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollisionGroups = require(ReplicatedStorage.Shared.CollisionGroups)
local Config = require(ReplicatedStorage.Shared.MovementConfig)
local CharacterDimensions = require(script.Parent.CharacterDimensions)

local StepupSystem = {}
StepupSystem.__index = StepupSystem

export type StepupSystem = typeof(setmetatable(
	{} :: { castParams: RaycastParams, halfHeight: number, centerOffset: number, radius: number },
	StepupSystem
))

-- Cette méthode permet de préparer la montée de marches d'un personnage lorsqu'il apparaît (ses pièces exclues des
-- rayons, dimensions debout).
function StepupSystem.new(character: Model, dims: CharacterDimensions.CharacterDimensions): StepupSystem
	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.FilterDescendantsInstances = { character, workspace.CurrentCamera }
	CollisionGroups.ignoreCharacters(castParams)
	local stand = dims:getStand()
	return setmetatable({
		castParams = castParams,
		halfHeight = stand.halfHeight,
		centerOffset = stand.centerOffset,
		radius = stand.radius - 0.05,
	}, StepupSystem)
end

-- Retourne (yOffset, wallNormal, slideNormal) pour la racine placée en rootPosition.
-- yOffset non-nil     → stepup réussi, ajouter au Y.
-- wallNormal non-nil  → vrai mur (raide), projeter la velocity dessus.
-- slideNormal non-nil → pente/jointure marchable, clipper la velocity 3D dessus (glisser).
-- les trois nil       → aucun obstacle, déplacement libre.
function StepupSystem.tryStepup(
	self: StepupSystem,
	rootPosition: Vector3,
	moveVec: Vector3
): (number?, Vector3?, Vector3?)
	if moveVec.Magnitude < 1e-4 then
		return nil, nil, nil
	end
	local castParams, radius = self.castParams, self.radius

	local origin = rootPosition + Vector3.new(0, self.centerOffset, 0)
	local upVec = Vector3.new(0, Config.STEPUP_HEIGHT, 0)

	-- 1. Bloqué horizontalement ?
	local horizHit = workspace:Spherecast(origin, radius, moveVec, castParams)
	if not horizHit then
		return nil, nil, nil
	end

	-- 1b. Surface MARCHABLE devant (pente douce / jointure d'arrondi multi-rampes) :
	-- ni un mur, ni une marche → on glisse dessus (ClipVelocity 3D), pas de blocage.
	if horizHit.Normal.Y >= Config.SURF_NORMAL_Y then
		return nil, nil, horizHit.Normal
	end

	-- À partir d'ici : surface raide → mur potentiel ou marche.
	local wallNormalXZ = Vector3.new(horizHit.Normal.X, 0, horizHit.Normal.Z)
	local wallNormal = wallNormalXZ.Magnitude > 1e-4 and wallNormalXZ.Unit
		or Vector3.new(-moveVec.X, 0, -moveVec.Z).Unit

	-- 2. Plafond bloque la montée ?
	if workspace:Spherecast(origin, radius, upVec, castParams) then
		return nil, wallNormal, nil
	end

	-- 3. Encore bloqué à la hauteur surélevée ?
	if workspace:Spherecast(origin + upVec, radius, moveVec, castParams) then
		return nil, wallNormal, nil
	end

	-- 4. Trouver la surface exacte de la marche par cast descendant
	local downHit = workspace:Spherecast(
		origin + upVec + moveVec,
		radius,
		Vector3.new(0, -(Config.STEPUP_HEIGHT + 0.5), 0),
		castParams
	)
	if not downHit then
		return nil, wallNormal, nil
	end

	local stepHeight = downHit.Position.Y - (origin.Y - self.halfHeight)
	if stepHeight <= 0 or stepHeight > Config.STEPUP_HEIGHT then
		return nil, wallNormal, nil
	end

	return stepHeight + 0.01, nil, nil
end

return StepupSystem
