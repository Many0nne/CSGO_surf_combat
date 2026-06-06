local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.MovementConfig)
local CharacterDimensions = require(script.Parent.CharacterDimensions)

local HALF_HEIGHT = Config.CHAR_HEIGHT_STAND / 2
local CENTER_OFFSET = 0
local RADIUS      = Config.CHAR_RADIUS - 0.05

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude

local StepupSystem = {}

function StepupSystem.init(character: Model)
	castParams.FilterDescendantsInstances = { character, workspace.CurrentCamera }
	local stand = CharacterDimensions.getStand()
	HALF_HEIGHT = stand.halfHeight
	CENTER_OFFSET = stand.centerOffset
	RADIUS = stand.radius - 0.05
end

-- Retourne (yOffset, wallNormal, slideNormal).
-- yOffset non-nil     → stepup réussi, ajouter au Y.
-- wallNormal non-nil  → vrai mur (raide), projeter la velocity dessus.
-- slideNormal non-nil → pente/jointure marchable, clipper la velocity 3D dessus (glisser).
-- les trois nil       → aucun obstacle, déplacement libre.
function StepupSystem.tryStepup(hrp: BasePart, moveVec: Vector3): (number?, Vector3?, Vector3?)
	if moveVec.Magnitude < 1e-4 then return nil, nil, nil end

	local origin = hrp.Position + Vector3.new(0, CENTER_OFFSET, 0)
	local upVec  = Vector3.new(0, Config.STEPUP_HEIGHT, 0)

	-- 1. Bloqué horizontalement ?
	local horizHit = workspace:Spherecast(origin, RADIUS, moveVec, castParams)
	if not horizHit then return nil, nil, nil end

	-- 1b. Surface MARCHABLE devant (pente douce / jointure d'arrondi multi-rampes) :
	-- ni un mur, ni une marche → on glisse dessus (ClipVelocity 3D), pas de blocage.
	if horizHit.Normal.Y >= Config.SURF_NORMAL_Y then
		return nil, nil, horizHit.Normal
	end

	-- À partir d'ici : surface raide → mur potentiel ou marche.
	local wallNormalXZ = Vector3.new(horizHit.Normal.X, 0, horizHit.Normal.Z)
	local wallNormal = wallNormalXZ.Magnitude > 1e-4
		and wallNormalXZ.Unit
		or Vector3.new(-moveVec.X, 0, -moveVec.Z).Unit

	-- 2. Plafond bloque la montée ?
	if workspace:Spherecast(origin, RADIUS, upVec, castParams) then
		return nil, wallNormal, nil
	end

	-- 3. Encore bloqué à la hauteur surélevée ?
	if workspace:Spherecast(origin + upVec, RADIUS, moveVec, castParams) then
		return nil, wallNormal, nil
	end

	-- 4. Trouver la surface exacte de la marche par cast descendant
	local downHit = workspace:Spherecast(
		origin + upVec + moveVec, RADIUS,
		Vector3.new(0, -(Config.STEPUP_HEIGHT + 0.5), 0),
		castParams
	)
	if not downHit then return nil, wallNormal, nil end

	local stepHeight = downHit.Position.Y - (origin.Y - HALF_HEIGHT)
	if stepHeight <= 0 or stepHeight > Config.STEPUP_HEIGHT then
		return nil, wallNormal, nil
	end

	return stepHeight + 0.01, nil, nil
end

return StepupSystem
