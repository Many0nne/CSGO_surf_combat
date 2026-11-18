-- PanBurst.luau
-- Effet de tir PAN ! (#566) : l'explosion de BD du skin PAN ! jaillit devant le canon, toujours tournée vers la caméra
-- (BillboardGui), grossit d'un coup, se pose, puis s'efface. Réglages et courbe dans ShotEffectRules (PAN_*, panFrame).
-- Réserve de PAN_MAX_ACTIVE explosions (Attachment du Terrain + BillboardGui + ImageLabel, nommés PanBurst) créée au
-- premier tir puis réutilisée : un tir ne crée aucune Instance. Réserve pleine : le tir n'a pas d'explosion.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local ShotEffectRules = require(ReplicatedStorage.Shared.ShotEffectRules)

local PanBurst = {}

PanBurst.INSTANCE_NAME = "PanBurst"

-- Explosion de la réserve : son point d'accroche, son panneau, son image, sa largeur (studs), son instant de départ
-- (nil : libre)
type Burst = {
	anchor: Attachment,
	gui: BillboardGui,
	image: ImageLabel,
	width: number,
	born: number?,
}

local pool: { Burst } = {}
local stepConn: RBXScriptConnection? = nil
local terrain = workspace:WaitForChild("Terrain")

-- Cette méthode permet de créer une explosion de la réserve, cachée, lorsque la réserve se remplit.
local function make(): Burst
	local anchor = Instance.new("Attachment")
	anchor.Name = PanBurst.INSTANCE_NAME
	local gui = Instance.new("BillboardGui")
	gui.Name = PanBurst.INSTANCE_NAME
	gui.Adornee = anchor
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false -- un mur devant le canon la cache
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local image = Instance.new("ImageLabel")
	image.Name = PanBurst.INSTANCE_NAME
	image.BackgroundTransparency = 1
	image.Image = ShotEffectRules.PAN_IMAGE
	image.ScaleType = Enum.ScaleType.Fit
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(0, 0)
	image.Parent = gui
	gui.Parent = anchor
	anchor.Parent = terrain
	return { anchor = anchor, gui = gui, image = image, width = ShotEffectRules.PAN_WIDTH, born = nil }
end

-- Cette méthode permet de remplir la réserve lorsque le premier tir PAN ! part (ou que l'aperçu le demande).
function PanBurst.prewarm()
	while #pool < ShotEffectRules.PAN_MAX_ACTIVE do
		table.insert(pool, make())
	end
end

-- Cette méthode permet d'animer les explosions en cours lorsqu'une frame passe (échelle et transparence de
-- ShotEffectRules.panFrame), de rendre à la réserve celles dont la vie est finie, et d'arrêter la boucle sans explosion.
local function step()
	local now = os.clock()
	local active = 0
	for _, burst in pool do
		local born = burst.born
		if born then
			local elapsed = now - born
			if elapsed >= ShotEffectRules.PAN_LIFETIME or not burst.anchor.Parent then
				burst.born = nil
				burst.gui.Enabled = false
			else
				active += 1
				local scale, transparency = ShotEffectRules.panFrame(elapsed)
				burst.image.Size = UDim2.fromScale(scale, scale)
				burst.image.ImageTransparency = transparency
			end
		end
	end
	if active == 0 and stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

local timedStep = PerfMarkers.wrap("effets de tir", step)

-- Cette méthode permet de faire jaillir une explosion PAN ! lorsqu'un tir part avec cet effet : devant la bouche du
-- canon (`start`) vers l'impact (`finish`), plus petite et plus près chez le tireur (`isLocal`), ou à `ahead` studs et
-- `width` studs de large (démonstrations). Renvoie le centre de l'explosion et sa largeur, ou nil si la réserve est pleine.
function PanBurst.spawn(
	start: Vector3,
	finish: Vector3,
	isLocal: boolean,
	ahead: number?,
	width: number?
): (Vector3?, number)
	PanBurst.prewarm()
	local free: Burst? = nil
	for _, burst in pool do
		if not burst.born then
			free = burst
			break
		end
	end
	if not free then
		return nil, 0
	end
	if not free.anchor.Parent then -- détruite par un tiers (rechargement de la map) : la recréer
		local index = table.find(pool, free)
		free = make()
		pool[index :: number] = free
	end
	local burst = free :: Burst
	local position, size = ShotEffectRules.panPlacement(start, finish, isLocal, ahead, width)
	burst.anchor.WorldPosition = position
	burst.width = size
	burst.gui.Size = UDim2.fromScale(size, size * ShotEffectRules.PAN_ASPECT)
	burst.image.Rotation = (math.random() * 2 - 1) * ShotEffectRules.PAN_TILT
	burst.image.Size = UDim2.fromScale(0, 0)
	burst.image.ImageTransparency = 0
	burst.gui.Enabled = true
	burst.born = os.clock()
	if not stepConn then
		stepConn = RunService.Heartbeat:Connect(timedStep)
	end
	return position, size
end

return PanBurst
