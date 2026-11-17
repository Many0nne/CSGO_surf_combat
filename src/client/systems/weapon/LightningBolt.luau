-- LightningBolt.luau
-- Éclair de tir d'un skin (#520, AWP ORAGE), à la place du rayon de balle : dessiné par ShotEffects pour le tir local,
-- les tirs relayés des autres et les tirs rejoués. Forme, couleurs et déroulé dans LightningRules.
-- Rendu : par segment, une couche de Beams (voile, halo, cœur) entre des Attachment du Terrain, plus une PointLight
-- verte par éclair. Coût d'un tir : les Beams sont rangés en réserve par style (sorte de ligne et couche : largeur et
-- couleur posées une fois pour toutes), la réserve d'un éclair complet est remplie au démarrage par petits lots
-- (`prewarm`) ; un tir ne fait que poser les Attachment, relier les Beams et les allumer. À la fin de l'éclair, tout est
-- éteint et rendu à sa réserve.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LightningRules = require(ReplicatedStorage.Shared.LightningRules)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local ShotEffectRules = require(ReplicatedStorage.Shared.ShotEffectRules)

local LightningBolt = {}

-- Nom des Instances créées (repérables en Studio)
LightningBolt.INSTANCE_NAME = "ShotLightning"
-- Instances créées par frame pendant le remplissage de la réserve au démarrage
LightningBolt.PREWARM_CHUNK = 60

-- Trait en cours : son Beam, son style (clé de réserve), sa transparence de base, son palier courant
type Stroke = { beam: Beam, style: string, base: number, step: number }
-- Éclair en cours : ses traits, ses Attachment, sa lumière, ses extrémités et son instant de création (os.clock)
type Bolt = {
	strokes: { Stroke },
	attachments: { Attachment },
	light: Attachment,
	start: Vector3,
	finish: Vector3,
	born: number,
}

local terrain = workspace:WaitForChild("Terrain")
local rng = Random.new()
local bolts: { Bolt } = {}
local freeAttachments: { Attachment } = {}
local freeBeams: { [string]: { Beam } } = {}
local freeLights: { Attachment } = {}
local stepConn: RBXScriptConnection? = nil
local prewarmed = false

local COLORS = {
	core = ColorSequence.new(Color3.fromRGB(table.unpack(LightningRules.CORE_RGB))),
	glow = ColorSequence.new(Color3.fromRGB(table.unpack(LightningRules.GLOW_RGB))),
}
-- Transparence de chaque palier, précalculée : pas de NumberSequence créée à chaque frame
local FADE: { NumberSequence } = {}
for i = 0, LightningRules.FADE_STEPS do
	FADE[i + 1] = NumberSequence.new(i / LightningRules.FADE_STEPS)
end

-- Cette méthode permet de tirer un nombre au hasard dans [min, max] lorsque LightningRules dessine un éclair.
local function rand(min: number, max: number): number
	return rng:NextNumber(min, max)
end

-- Cette méthode permet de nommer le style d'une couche (clé de sa réserve) lorsqu'un Beam est pris ou rendu.
local function styleOf(kind: string, index: number): string
	return kind .. ":" .. index
end

-- Cette méthode permet de créer un Attachment éteint de la réserve lorsqu'il en manque.
local function newAttachment(): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = LightningBolt.INSTANCE_NAME
	attachment.Parent = terrain
	return attachment
end

-- Cette méthode permet de créer un Beam éteint d'un style (largeur, couleur de sa couche) lorsqu'il en manque.
local function newBeam(layer: LightningRules.Layer): Beam
	local beam = Instance.new("Beam")
	beam.Name = LightningBolt.INSTANCE_NAME
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Width0 = layer.width
	beam.Width1 = layer.width
	beam.Color = COLORS[layer.color] or COLORS.glow
	beam.Enabled = false
	beam.Parent = terrain
	return beam
end

-- Cette méthode permet de créer la lumière éteinte d'un éclair (PointLight dans un Attachment) lorsqu'il en manque.
local function newLight(): Attachment
	local holder = Instance.new("Attachment")
	holder.Name = LightningBolt.INSTANCE_NAME
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(table.unpack(LightningRules.GLOW_RGB))
	light.Range = LightningRules.LIGHT_RANGE
	light.Shadows = false
	light.Enabled = false
	light.Parent = holder
	holder.Parent = terrain
	return holder
end

-- Cette méthode permet de régler l'éclat de la lumière d'un éclair lorsqu'une frame passe (éteinte à 0).
local function setLight(holder: Attachment, intensity: number)
	local light = holder:FindFirstChildOfClass("PointLight")
	if light then
		light.Brightness = LightningRules.LIGHT_BRIGHTNESS * intensity
		light.Enabled = intensity > 0
	end
end

-- Cette méthode permet d'allumer un Beam d'un style entre deux points d'éclair lorsqu'un segment est tracé.
local function addStroke(bolt: Bolt, a0: Attachment, a1: Attachment, style: string, layer: LightningRules.Layer)
	local pool = freeBeams[style]
	local beam = pool and table.remove(pool) or newBeam(layer)
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	local step = LightningRules.fadeStep(layer.alpha, 1, false)
	beam.Transparency = FADE[step + 1]
	beam.Enabled = true
	table.insert(bolt.strokes, { beam = beam, style = style, base = layer.alpha, step = step })
end

-- Cette méthode permet de rendre à leurs réserves les Instances d'un éclair lorsque sa vie est finie.
local function release(bolt: Bolt)
	for _, stroke in bolt.strokes do
		stroke.beam.Enabled = false
		local pool = freeBeams[stroke.style]
		if not pool then
			pool = {}
			freeBeams[stroke.style] = pool
		end
		table.insert(pool, stroke.beam)
	end
	for _, attachment in bolt.attachments do
		table.insert(freeAttachments, attachment)
	end
	setLight(bolt.light, 0)
	table.insert(freeLights, bolt.light)
end

-- Cette méthode permet de faire scintiller puis s'éteindre les éclairs en cours lorsqu'une frame passe (masqués si
-- la caméra les traverse) ; la boucle s'arrête quand il n'en reste plus.
local function step()
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	for i = #bolts, 1, -1 do
		local bolt = bolts[i]
		local elapsed = now - bolt.born
		if elapsed >= LightningRules.LIFETIME then
			release(bolt)
			table.remove(bolts, i)
		else
			local hidden = eye ~= nil and ShotEffectRules.isTooClose(bolt.start, bolt.finish, eye)
			local intensity = LightningRules.intensity(elapsed)
			for _, stroke in bolt.strokes do
				local fade = LightningRules.fadeStep(stroke.base, intensity, hidden)
				if fade ~= stroke.step then
					stroke.step = fade
					stroke.beam.Transparency = FADE[fade + 1]
				end
			end
			setLight(bolt.light, if hidden then 0 else intensity)
		end
	end
	if #bolts == 0 and stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

local timedStep = PerfMarkers.wrap("effets de tir", step)

-- Cette méthode permet de remplir au démarrage du client la réserve d'un éclair complet, par lots de PREWARM_CHUNK
-- Instances par frame : le premier tir d'un skin à éclair ne crée rien (un seul remplissage).
function LightningBolt.prewarm()
	if prewarmed then
		return
	end
	prewarmed = true
	task.spawn(function()
		local made = 0
		-- Cette méthode permet de céder la frame lorsqu'un lot d'Instances vient d'être créé.
		local function tick()
			made += 1
			if made % LightningBolt.PREWARM_CHUNK == 0 then
				task.wait()
			end
		end
		local segments, points = LightningRules.maxCounts()
		for _ = 1, points do
			table.insert(freeAttachments, newAttachment())
			tick()
		end
		for kind, layers in LightningRules.KINDS do
			for index, layer in layers do
				local style = styleOf(kind, index)
				local pool = freeBeams[style] or {}
				freeBeams[style] = pool
				for _ = 1, segments[kind] or 0 do
					table.insert(pool, newBeam(layer))
					tick()
				end
			end
		end
		table.insert(freeLights, newLight())
	end)
end

-- Cette méthode permet de tirer un éclair du canon (start) au point d'impact (finish) lorsqu'un tir d'un skin à éclair
-- est montré ; false si trop d'éclairs sont déjà en cours (le tir garde alors son rayon ordinaire).
function LightningBolt.spawn(start: Vector3, finish: Vector3): boolean
	if not LightningRules.hasRoom(#bolts) then
		return false
	end
	local lines = LightningRules.build(start, finish, rand)
	if #lines == 0 then
		return false
	end
	local axis = (finish - start).Unit
	local light = table.remove(freeLights) or newLight()
	light.WorldPosition = start + axis * math.min(LightningRules.LIGHT_OFFSET, (finish - start).Magnitude / 2)
	local bolt: Bolt = {
		strokes = {},
		attachments = {},
		light = light,
		start = start,
		finish = finish,
		born = os.clock(),
	}
	for _, line in lines do
		local layers = LightningRules.KINDS[line.kind]
		local previous: Attachment? = nil
		for _, point in line.points do
			local attachment = table.remove(freeAttachments) or newAttachment()
			attachment.WorldPosition = point
			table.insert(bolt.attachments, attachment)
			if previous then
				for index, layer in layers do
					addStroke(bolt, previous, attachment, styleOf(line.kind, index), layer)
				end
			end
			previous = attachment
		end
	end
	setLight(bolt.light, 1)
	table.insert(bolts, bolt)
	if not stepConn then
		stepConn = RunService.Heartbeat:Connect(timedStep)
	end
	return true
end

return LightningBolt
