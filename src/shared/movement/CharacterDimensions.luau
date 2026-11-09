-- Dimensions d'un personnage (hitbox debout/accroupi), mesurées une fois sur son rig. Une instance par personnage
-- (#139) : le joueur local et chaque bot serveur ont la leur.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.MovementConfig)

export type Dims = {
	rootToTop: number,
	rootToBottom: number,
	height: number,
	halfHeight: number,
	centerOffset: number,
	radius: number,
}

local CharacterDimensions = {}
CharacterDimensions.__index = CharacterDimensions

export type CharacterDimensions = typeof(setmetatable(
	{} :: { standRootToTop: number, standRootToBottom: number, radius: number },
	CharacterDimensions
))

local function expandBounds(minVec: Vector3, maxVec: Vector3, point: Vector3): (Vector3, Vector3)
	local minX = math.min(minVec.X, point.X)
	local minY = math.min(minVec.Y, point.Y)
	local minZ = math.min(minVec.Z, point.Z)
	local maxX = math.max(maxVec.X, point.X)
	local maxY = math.max(maxVec.Y, point.Y)
	local maxZ = math.max(maxVec.Z, point.Z)
	return Vector3.new(minX, minY, minZ), Vector3.new(maxX, maxY, maxZ)
end

local function computeBodyBounds(character: Model): (Vector3?, Vector3?)
	local minVec = Vector3.new(math.huge, math.huge, math.huge)
	local maxVec = Vector3.new(-math.huge, -math.huge, -math.huge)
	local found = false

	for _, inst in character:GetDescendants() do
		if inst:IsA("BasePart") then
			if inst:FindFirstAncestorOfClass("Accessory") or inst:FindFirstAncestorOfClass("Tool") then
				continue
			end

			local size = inst.Size * 0.5
			local cf = inst.CFrame
			for dx = -1, 1, 2 do
				for dy = -1, 1, 2 do
					for dz = -1, 1, 2 do
						local corner = cf:PointToWorldSpace(Vector3.new(size.X * dx, size.Y * dy, size.Z * dz))
						minVec, maxVec = expandBounds(minVec, maxVec, corner)
						found = true
					end
				end
			end
		end
	end

	if not found then
		return nil, nil
	end

	return minVec, maxVec
end

-- Cette méthode permet de mesurer la hauteur racine→sommet et racine→pieds d'un rig lorsqu'on crée ses dimensions ;
-- nil si le rig ne donne pas de mesure exploitable (valeurs de MovementConfig gardées).
local function measure(character: Model, hrp: BasePart): (number?, number?)
	local minVec, maxVec = computeBodyBounds(character)
	if not minVec or not maxVec then
		local boxCFrame, boxSize = character:GetBoundingBox()
		minVec = boxCFrame.Position - (boxSize / 2)
		maxVec = boxCFrame.Position + (boxSize / 2)
	end

	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local headHeight = head.Size.Y
		if head:IsA("MeshPart") then
			local meshSizeY = (head :: MeshPart).MeshSize.Y
			headHeight = math.max(headHeight, meshSizeY)
		else
			local mesh = head:FindFirstChildOfClass("SpecialMesh")
			if mesh then
				headHeight = math.max(headHeight, head.Size.Y * mesh.Scale.Y)
			end
		end
		local headTopY = head.Position.Y + (headHeight / 2) + Config.HITBOX_HEAD_BUFFER
		if headTopY > (maxVec :: Vector3).Y then
			maxVec = Vector3.new((maxVec :: Vector3).X, headTopY, (maxVec :: Vector3).Z)
		end
	end

	local rootY = hrp.Position.Y
	local rootToTop = (maxVec :: Vector3).Y - rootY
	local rootToBottom = rootY - (minVec :: Vector3).Y
	if rootToTop > 0 and rootToBottom > 0 then
		return rootToTop, rootToBottom
	end
	return nil, nil
end

-- Cette méthode permet de mesurer les dimensions d'un personnage lorsqu'il apparaît (rig encore dans sa pose de repos).
function CharacterDimensions.new(character: Model, hrp: BasePart): CharacterDimensions
	local self = setmetatable({
		standRootToTop = Config.CHAR_HEIGHT_STAND / 2,
		standRootToBottom = Config.CHAR_HEIGHT_STAND / 2,
		radius = Config.CHAR_RADIUS,
	}, CharacterDimensions)
	if Config.HITBOX_USE_RIG_BOUNDS then
		local rootToTop, rootToBottom = measure(character, hrp)
		if rootToTop and rootToBottom then
			self.standRootToTop = rootToTop
			self.standRootToBottom = rootToBottom
		end
	end
	return self
end

local function build(rootToTop: number, rootToBottom: number, radius: number): Dims
	local height = rootToTop + rootToBottom
	return {
		rootToTop = rootToTop,
		rootToBottom = rootToBottom,
		height = height,
		halfHeight = height / 2,
		centerOffset = (rootToTop - rootToBottom) / 2,
		radius = radius,
	}
end

function CharacterDimensions.getStand(self: CharacterDimensions): Dims
	return build(self.standRootToTop, self.standRootToBottom, self.radius)
end

function CharacterDimensions.getCrouch(self: CharacterDimensions): Dims
	local rootToBottom = self.standRootToBottom
	local rootToTop = math.max(0.5, Config.CHAR_HEIGHT_CROUCH - rootToBottom)
	return build(rootToTop, rootToBottom, self.radius)
end

return CharacterDimensions
