-- ViewmodelAnimator.luau
-- Moteur d'animation du viewmodel FPS écrit en code (#19) : clips à keyframes par articulation (position + angles
-- d'Euler en degrés), easing par segment, fondus entre clips et marqueurs (sons, coup de couteau).
-- Module pur (aucune Instance) : ViewmodelSystem applique les poses aux Motor6D, les tests le vérifient sous Lune.
--
-- Une articulation est désignée par le nom de la pièce qu'elle anime (Part1 du Motor6D). Une keyframe décrit un
-- décalage K exprimé dans le repère du Part0, autour du pivot de l'articulation (Rig.Pivots) :
--   delta = T(pivot) * K * T(-pivot), puis Motor6D.Transform = C0⁻¹ * delta * C0.
-- Rig.Follow fait suivre une articulation par une autre (ex. bras collés à l'arme) : delta = delta(parent) * delta.

local DEFAULT_BLEND_IN = 0.08
local DEFAULT_BLEND_OUT = 0.25

local IDENTITY = CFrame.new()

local ViewmodelAnimator = {}
ViewmodelAnimator.__index = ViewmodelAnimator

export type KeyDef = { t: number, p: { number }?, r: { number }?, e: string? }
export type MarkerDef = { t: number, name: string }
export type ClipDef = {
	Length: number,
	Looped: boolean?,
	BlendIn: number?,
	BlendOut: number?,
	Tracks: { [string]: { KeyDef } },
	Markers: { MarkerDef }?,
}
export type RigDef = {
	Pivots: { [string]: Vector3 }?,
	Follow: { [string]: string }?,
	Base: { [string]: KeyDef }?,
}
type Key = { t: number, p: Vector3, r: Vector3, e: string }
export type Clip = {
	name: string,
	length: number,
	looped: boolean,
	blendIn: number?,
	blendOut: number?,
	tracks: { [string]: { Key } },
	markers: { MarkerDef },
}
export type Rig = { pivots: { [string]: Vector3 }, follow: { [string]: string }, base: { [string]: CFrame } }
export type Pose = { [string]: CFrame }

local EASINGS: { [string]: (number) -> number } = {
	linear = function(a)
		return a
	end,
	sine = function(a)
		return -(math.cos(math.pi * a) - 1) / 2
	end,
	["in"] = function(a)
		return a * a
	end,
	out = function(a)
		return 1 - (1 - a) * (1 - a)
	end,
	inCubic = function(a)
		return a * a * a
	end,
	outCubic = function(a)
		return 1 - (1 - a) ^ 3
	end,
	inOut = function(a)
		if a < 0.5 then
			return 4 * a * a * a
		end
		return 1 - (-2 * a + 2) ^ 3 / 2
	end,
	outBack = function(a)
		local c1 = 1.70158
		return 1 + (c1 + 1) * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
	end,
	step = function(a)
		return a >= 1 and 1 or 0
	end,
}
ViewmodelAnimator.EASINGS = EASINGS

-- Cette méthode permet de convertir un triplet {x, y, z} en Vector3 lorsqu'une keyframe est compilée (nil → zéro).
local function vec(t: { number }?, scale: number): Vector3
	if not t then
		return Vector3.zero
	end
	return Vector3.new((t[1] or 0) * scale, (t[2] or 0) * scale, (t[3] or 0) * scale)
end

-- Cette méthode permet de construire le décalage K d'une keyframe lorsqu'on a sa position et ses angles (radians).
local function toCFrame(p: Vector3, r: Vector3): CFrame
	return CFrame.new(p) * CFrame.Angles(r.X, r.Y, r.Z)
end

-- Cette méthode permet de compiler la définition d'un clip lorsqu'un set d'armes est chargé : tri des keyframes,
-- ajout implicite de la pose de repos en début et fin de piste, validation des noms d'easing.
function ViewmodelAnimator.compileClip(name: string, def: ClipDef): Clip
	assert(def.Length and def.Length > 0, "clip " .. name .. " : Length invalide")
	local tracks = {}
	for joint, keyDefs in def.Tracks do
		local keys: { Key } = {}
		for _, k in keyDefs do
			local ease = k.e or "sine"
			assert(EASINGS[ease], "clip " .. name .. " : easing inconnu " .. tostring(ease))
			assert(k.t >= 0 and k.t <= def.Length, "clip " .. name .. " : keyframe hors du clip sur " .. joint)
			table.insert(keys, { t = k.t, p = vec(k.p, 1), r = vec(k.r, math.pi / 180), e = ease })
		end
		table.sort(keys, function(a, b)
			return a.t < b.t
		end)
		if #keys == 0 or keys[1].t > 0 then
			table.insert(keys, 1, { t = 0, p = Vector3.zero, r = Vector3.zero, e = "sine" })
		end
		if keys[#keys].t < def.Length then
			table.insert(keys, { t = def.Length, p = Vector3.zero, r = Vector3.zero, e = "sine" })
		end
		tracks[joint] = keys
	end
	local markers = {}
	local markerDefs: { MarkerDef } = def.Markers or {}
	for _, m in markerDefs do
		assert(m.t >= 0 and m.t <= def.Length, "clip " .. name .. " : marqueur hors du clip " .. m.name)
		table.insert(markers, { t = m.t, name = m.name })
	end
	table.sort(markers, function(a, b)
		return a.t < b.t
	end)
	return {
		name = name,
		length = def.Length,
		looped = def.Looped == true,
		blendIn = def.BlendIn,
		blendOut = def.BlendOut,
		tracks = tracks,
		markers = markers,
	}
end

-- Cette méthode permet de compiler le rig d'une arme (pivots, suivis, pose de base) lorsqu'un set est chargé.
function ViewmodelAnimator.compileRig(def: RigDef?): Rig
	local base = {}
	local baseDefs: { [string]: KeyDef } = (def and def.Base) or {}
	for joint, k in baseDefs do
		base[joint] = toCFrame(vec(k.p, 1), vec(k.r, math.pi / 180))
	end
	return {
		pivots = (def and def.Pivots) or {},
		follow = (def and def.Follow) or {},
		base = base,
	}
end

-- Cette méthode permet de compiler tout le set d'une arme ({ Rig, Clips }) lorsqu'un viewmodel est préparé.
function ViewmodelAnimator.compileSet(def: { Rig: RigDef?, Clips: { [string]: ClipDef } })
	local clips = {}
	for name, clipDef in def.Clips do
		clips[name] = ViewmodelAnimator.compileClip(name, clipDef)
	end
	return { rig = ViewmodelAnimator.compileRig(def.Rig), clips = clips }
end

-- Cette méthode permet d'évaluer une piste à l'instant t lorsqu'un clip est échantillonné ;
-- les angles sont interpolés composante par composante, ce qui autorise les rotations de plus de 180°.
function ViewmodelAnimator.sampleTrack(keys: { Key }, t: number): CFrame
	if t <= keys[1].t then
		return toCFrame(keys[1].p, keys[1].r)
	end
	for i = 2, #keys do
		local k1 = keys[i]
		if t <= k1.t then
			local k0 = keys[i - 1]
			local span = k1.t - k0.t
			local a = span > 0 and (t - k0.t) / span or 1
			local w = EASINGS[k1.e](a)
			return toCFrame(k0.p:Lerp(k1.p, w), k0.r:Lerp(k1.r, w))
		end
	end
	local last = keys[#keys]
	return toCFrame(last.p, last.r)
end

-- Cette méthode permet d'évaluer toutes les pistes d'un clip à l'instant t lorsqu'une frame est calculée.
function ViewmodelAnimator.sampleClip(clip: Clip, t: number): Pose
	local pose = {}
	for joint, keys in clip.tracks do
		pose[joint] = ViewmodelAnimator.sampleTrack(keys, t)
	end
	return pose
end

-- Cette méthode permet de mélanger deux poses lorsqu'un fondu est en cours (articulation absente = repos).
function ViewmodelAnimator.blendPoses(from: Pose, to: Pose, w: number): Pose
	local out = {}
	for joint, cf in to do
		out[joint] = (from[joint] or IDENTITY):Lerp(cf, w)
	end
	for joint, cf in from do
		if not to[joint] then
			out[joint] = cf:Lerp(IDENTITY, w)
		end
	end
	return out
end

-- Cette méthode permet de convertir une pose en décalages dans le repère du Part0 de chaque articulation
-- lorsqu'elle va être appliquée : pose de base, pivot, puis suivi éventuel d'une autre articulation.
function ViewmodelAnimator.resolveDeltas(pose: Pose, rig: Rig): { [string]: CFrame }
	local deltas: { [string]: CFrame } = {}
	local function delta(joint: string, depth: number): CFrame
		local cached = deltas[joint]
		if cached then
			return cached
		end
		assert(depth < 8, "Rig.Follow cyclique sur " .. joint)
		local k = pose[joint] or IDENTITY
		local base = rig.base[joint]
		if base then
			k = k * base
		end
		local pivot = rig.pivots[joint]
		local d = pivot and (CFrame.new(pivot) * k * CFrame.new(-pivot)) or k
		local parent = rig.follow[joint]
		if parent then
			d = delta(parent, depth + 1) * d
		end
		deltas[joint] = d
		return d
	end
	for joint in pose do
		delta(joint, 0)
	end
	for joint in rig.base do
		delta(joint, 0)
	end
	for joint in rig.follow do
		delta(joint, 0)
	end
	return deltas
end

-- Cette méthode permet de calculer le Motor6D.Transform qui applique un décalage exprimé dans le repère du Part0.
function ViewmodelAnimator.toTransform(delta: CFrame, c0: CFrame): CFrame
	return c0:Inverse() * delta * c0
end

-- Cette méthode permet de créer le lecteur d'un set compilé lorsqu'un viewmodel est équipé ;
-- l'Idle (s'il existe) tourne en boucle sous les actions.
function ViewmodelAnimator.new(clips: { [string]: Clip })
	local self = setmetatable({}, ViewmodelAnimator)
	self.clips = clips
	self.idle = clips.Idle
	self.idleTime = 0
	self.action = nil :: Clip?
	self.time = 0
	self.speed = 1
	self.markerCursor = 0
	self.current = {} :: Pose
	self.from = nil :: Pose?
	self.blendT = 0
	self.blendDur = 0
	self.paused = false
	return self
end

-- Cette méthode permet de figer la pose courante comme point de départ d'un fondu lorsqu'une source change.
function ViewmodelAnimator:_beginBlend(duration: number)
	if duration <= 0 then
		self.from = nil
		return
	end
	self.from = table.clone(self.current)
	self.blendT = 0
	self.blendDur = duration
end

-- Cette méthode permet de lancer une action lorsque le joueur tire, recharge, équipe ou inspecte ;
-- duration (optionnelle) étire le clip pour qu'il dure exactement ce temps (ex. ReloadTime de WeaponConfig).
function ViewmodelAnimator:play(name: string, duration: number?): boolean
	local clip = self.clips[name]
	if not clip or clip == self.idle then
		return false
	end
	self:_beginBlend(clip.blendIn or DEFAULT_BLEND_IN)
	self.action = clip
	self.time = 0
	self.speed = (duration and duration > 0) and clip.length / duration or 1
	self.markerCursor = 0
	self.paused = false
	return true
end

-- Cette méthode permet d'interrompre l'action en cours avec un fondu vers l'idle lorsqu'une autre logique l'annule.
function ViewmodelAnimator:stop(blend: number?)
	if not self.action then
		return
	end
	self:_beginBlend(blend or self.action.blendOut or DEFAULT_BLEND_OUT)
	self.action = nil
end

-- Cette méthode permet de tout remettre au repos sans fondu lorsque l'arme est rangée ou changée.
function ViewmodelAnimator:reset()
	self.action = nil
	self.from = nil
	self.current = {}
	self.idleTime = 0
	self.paused = false
end

-- Cette méthode permet de savoir quelle action joue (nil si seulement l'idle).
function ViewmodelAnimator:getAction(): string?
	return self.action and self.action.name or nil
end

-- Cette méthode permet de figer un clip à un instant donné lorsqu'on règle une animation en Studio (debug).
function ViewmodelAnimator:seek(name: string, t: number): boolean
	local clip = self.clips[name]
	if not clip then
		return false
	end
	self.action = clip ~= self.idle and clip or nil
	self.time = math.clamp(t, 0, clip.length)
	self.idleTime = self.time
	self.markerCursor = #clip.markers
	self.from = nil
	self.paused = true
	return true
end

-- Cette méthode permet de relancer la lecture après un seek de debug.
function ViewmodelAnimator:resume()
	self.paused = false
end

-- Cette méthode permet d'avancer la lecture de dt secondes lorsqu'une frame est rendue ;
-- retourne la pose à appliquer et la liste des marqueurs franchis pendant la frame (dans l'ordre).
function ViewmodelAnimator:step(dt: number): (Pose, { string })
	local fired = {}
	if not self.paused then
		self.idleTime += dt
		local action = self.action
		if action then
			self.time += dt * self.speed
			local markers = action.markers
			while self.markerCursor < #markers and markers[self.markerCursor + 1].t <= self.time do
				self.markerCursor += 1
				table.insert(fired, markers[self.markerCursor].name)
			end
			if self.time >= action.length then
				self.time = action.length
				self.current = ViewmodelAnimator.sampleClip(action, action.length)
				self:stop()
			end
		end
	end

	local source: Pose
	if self.action then
		source = ViewmodelAnimator.sampleClip(self.action, self.time)
	elseif self.idle then
		source = ViewmodelAnimator.sampleClip(self.idle, self.idleTime % self.idle.length)
	else
		source = {}
	end

	if self.from then
		self.blendT += dt
		local a = math.clamp(self.blendT / self.blendDur, 0, 1)
		source = ViewmodelAnimator.blendPoses(self.from, source, EASINGS.sine(a))
		if a >= 1 then
			self.from = nil
		end
	end
	self.current = source
	return source, fired
end

return ViewmodelAnimator
