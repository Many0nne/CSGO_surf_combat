local Players       = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)

local MAX_HITSCAN_RANGE = 250  -- studs
local MAX_MELEE_RANGE   = 10   -- studs

local Validator = {}

local function getRoot(char: Model): BasePart?
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Returns false if any basic type/ownership checks fail
local function commonChecks(attacker: Player, targetCharacter: Instance, damage: number, maxDamage: number): (boolean, Player?, Humanoid?)
	if typeof(targetCharacter) ~= "Instance" then return false, nil, nil end
	if typeof(damage) ~= "number" or damage <= 0 or damage > maxDamage then return false, nil, nil end

	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	if not targetPlayer or targetPlayer == attacker then return false, nil, nil end

	local humanoid = targetCharacter:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
	if not humanoid or humanoid.Health <= 0 then return false, nil, nil end

	return true, targetPlayer, humanoid
end

function Validator.validateHitscan(attacker: Player, targetCharacter: Instance, damage: number): boolean
	local ok, _, _ = commonChecks(attacker, targetCharacter, damage, 1000)
	if not ok then return false end

	local aChar = attacker.Character
	if not aChar then return false end
	local aRoot = getRoot(aChar)
	local tRoot = getRoot(targetCharacter :: Model)
	if not aRoot or not tRoot then return false end

	if (aRoot.Position - tRoot.Position).Magnitude > MAX_HITSCAN_RANGE then return false end

	return true
end

function Validator.validateMelee(attacker: Player, targetCharacter: Instance, damage: number): boolean
	local ok, _, _ = commonChecks(attacker, targetCharacter, damage, 500)
	if not ok then return false end

	local aChar = attacker.Character
	if not aChar then return false end
	local aRoot = getRoot(aChar)
	local tRoot = getRoot(targetCharacter :: Model)
	if not aRoot or not tRoot then return false end

	if (aRoot.Position - tRoot.Position).Magnitude > MAX_MELEE_RANGE then return false end

	return true
end

-- Position plausibility (for future use with position-based anti-cheat)
function Validator.isPositionPlausible(player: Player, claimedPos: Vector3): boolean
	local char = player.Character
	if not char then return false end
	local root = getRoot(char)
	if not root then return false end
	return (root.Position - claimedPos).Magnitude <= MovementConfig.MAX_DELTA_POS * 5
end

return Validator
