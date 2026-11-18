-- PanBurst.luau
-- Effet de tir PAN ! (#566) : l'explosion de BD du skin PAN !, en volume (ReplicatedStorage.Props.PanBurst, fabriqué
-- par assets/effects/pan_burst_3d.py), jaillit devant le canon : tournée de trois quarts au tir, elle pivote face à la
-- caméra en grossissant, se pose, puis s'efface. Réglages et courbes dans ShotEffectRules (PAN_*, panFrame, panTurn).
-- Réserve de PAN_MAX_ACTIVE copies du modèle (MeshParts ancrées, sans collision), créée au premier tir puis réutilisée :
-- un tir ne crée aucune Instance. Chaque frame, taille et place de chaque pièce sont recalculées (échelle du pop).
-- Réserve pleine ou modèle absent : le tir n'a pas d'explosion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local ShotEffectRules = require(ReplicatedStorage.Shared.ShotEffectRules)

local PanBurst = {}

PanBurst.INSTANCE_NAME = "PanBurst"

-- Pièce d'une copie : la MeshPart, sa place par rapport au pivot du modèle et sa taille à l'échelle 1, sa transparence
-- de repos (celle du modèle)
type Piece = { part: BasePart, offset: CFrame, size: Vector3, transparency: number }
-- Explosion de la réserve : ses pièces, sa position (centre), sa largeur (studs), son inclinaison (radians), le sens
-- de sa rotation de départ, son instant de départ (nil : libre)
type Burst = {
	pieces: { Piece },
	position: Vector3,
	width: number,
	tilt: number,
	side: number,
	born: number?,
}

local pool: { Burst } = {}
local folder: Folder? = nil
local stepConn: RBXScriptConnection? = nil
local warned = false
-- Rangée hors de vue des explosions au repos (studs) : pas de pièce qui traîne devant une caméra
local PARKED = CFrame.new(0, -10000, 0)

-- Cette méthode permet de trouver le modèle source de l'explosion lorsque la réserve se remplit ; nil (et un
-- avertissement, une fois) s'il n'est pas répliqué.
local function template(): Model?
	local props = ReplicatedStorage:FindFirstChild("Props")
	local model = props and props:FindFirstChild(ShotEffectRules.PAN_MODEL)
	if model and model:IsA("Model") then
		return model
	end
	if not warned then
		warned = true
		warn(
			"[PanBurst] ReplicatedStorage.Props." .. ShotEffectRules.PAN_MODEL .. " introuvable : PAN ! sans explosion"
		)
	end
	return nil
end

-- Cette méthode permet de cacher une explosion (rangée hors de vue, transparente) lorsqu'elle est créée ou que sa vie
-- est finie.
local function park(burst: Burst)
	burst.born = nil
	for _, piece in burst.pieces do
		piece.part.Transparency = 1
		piece.part.CFrame = PARKED
	end
end

-- Cette méthode permet de créer une explosion de la réserve (copie du modèle, pièces relevées à l'échelle 1 et cachées)
-- lorsque la réserve se remplit ; nil sans modèle source.
local function make(): Burst?
	local source = template()
	if not source then
		return nil
	end
	if not folder or not folder.Parent then
		local created = Instance.new("Folder")
		created.Name = PanBurst.INSTANCE_NAME
		created.Parent = workspace
		folder = created
	end
	local model = source:Clone()
	model.Name = PanBurst.INSTANCE_NAME
	local pivot = model:GetPivot()
	local pieces: { Piece } = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			table.insert(pieces, {
				part = part,
				offset = pivot:ToObjectSpace(part.CFrame),
				size = part.Size,
				transparency = part.Transparency,
			})
		end
	end
	model.Parent = folder
	local burst = { pieces = pieces, position = Vector3.zero, width = 0, tilt = 0, side = 1, born = nil }
	park(burst)
	return burst
end

-- Cette méthode permet de remplir la réserve lorsque le premier tir PAN ! part (ou que l'aperçu le demande).
function PanBurst.prewarm()
	while #pool < ShotEffectRules.PAN_MAX_ACTIVE do
		local burst = make()
		if not burst then
			return
		end
		table.insert(pool, burst)
	end
end

-- Cette méthode permet de poser une explosion à un instant de sa vie lorsqu'une frame passe : face à la caméra
-- (`eye`), encore tournée de panTurn degrés, inclinée, à l'échelle du pop, à la transparence du fondu.
local function pose(burst: Burst, elapsed: number, eye: Vector3)
	local scale, fade = ShotEffectRules.panFrame(elapsed)
	local turn = math.rad(ShotEffectRules.panTurn(elapsed)) * burst.side
	-- lookAt : -Z (face avant du modèle) vers la caméra
	local base = CFrame.lookAt(burst.position, eye) * CFrame.Angles(0, turn, burst.tilt)
	local s = math.max(scale, 0.02) * burst.width / ShotEffectRules.PAN_MODEL_WIDTH
	for _, piece in burst.pieces do
		local offset = piece.offset
		piece.part.Size = piece.size * s
		piece.part.CFrame = base * (offset - offset.Position + offset.Position * s)
		piece.part.Transparency = piece.transparency + (1 - piece.transparency) * fade
	end
end

-- Cette méthode permet d'animer les explosions en cours lorsqu'une frame passe, de ranger celles dont la vie est finie,
-- et d'arrêter la boucle sans explosion.
local function step()
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local active = 0
	for _, burst in pool do
		local born = burst.born
		if born then
			local elapsed = now - born
			local alive = burst.pieces[1] ~= nil and burst.pieces[1].part.Parent ~= nil
			if elapsed >= ShotEffectRules.PAN_LIFETIME or not alive then
				park(burst)
			else
				active += 1
				pose(burst, elapsed, eye)
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
-- `width` studs de large (démonstrations). Renvoie le centre de l'explosion et sa largeur, ou nil si la réserve est
-- pleine ou le modèle absent.
function PanBurst.spawn(
	start: Vector3,
	finish: Vector3,
	isLocal: boolean,
	ahead: number?,
	width: number?
): (Vector3?, number)
	PanBurst.prewarm()
	local index: number? = nil
	for i, burst in pool do
		if not burst.born then
			index = i
			break
		end
	end
	if not index then
		return nil, 0
	end
	local burst = pool[index]
	if not (burst.pieces[1] and burst.pieces[1].part.Parent) then -- détruite par un tiers : la recréer
		local fresh = make()
		if not fresh then
			return nil, 0
		end
		pool[index] = fresh
		burst = fresh
	end
	local position, size = ShotEffectRules.panPlacement(start, finish, isLocal, ahead, width)
	burst.position = position
	burst.width = size
	burst.tilt = math.rad((math.random() * 2 - 1) * ShotEffectRules.PAN_TILT)
	burst.side = if math.random() < 0.5 then -1 else 1
	burst.born = os.clock()
	local camera = workspace.CurrentCamera
	pose(burst, 0, if camera then camera.CFrame.Position else position + Vector3.zAxis)
	if not stepConn then
		stepConn = RunService.Heartbeat:Connect(timedStep)
	end
	return position, size
end

return PanBurst
