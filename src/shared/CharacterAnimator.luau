-- CharacterAnimator.luau
-- Pipeline d'animation 3e personne commun joueurs/bots (#1).
-- L'appelant fournit un état de mouvement abstrait (sol, accroupi, surf, vitesses) ;
-- le module choisit la piste, gère les fondus et cale la vitesse de lecture.
--   • Joueur : MovementController (client) l'alimente depuis la physique custom ;
--     les pistes jouées sur l'Animator du personnage local sont répliquées par Roblox.
--   • Bot : BotManager (serveur) l'alimente depuis son Humanoid actif.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterConfig = require(ReplicatedStorage.Shared.CharacterConfig)

export type AnimState = "IDLE" | "WALK" | "RUN" | "JUMP" | "FALL" | "CROUCH_IDLE" | "CROUCH_WALK" | "SURF"

export type AnimInput = {
	onGround: boolean,
	crouching: boolean,
	surfing: boolean,
	speed: number, -- vitesse horizontale (studs/s)
	verticalSpeed: number,
}

local AIR_STATES = {
	JUMP = true,
	FALL = true,
	SURF = true,
}

local IDLE_PRIORITY_STATES = {
	IDLE = true,
	CROUCH_IDLE = true,
}

local CharacterAnimator = {}
CharacterAnimator.__index = CharacterAnimator

-- Cette méthode permet de déduire l'état d'animation depuis l'état de mouvement lorsqu'on met à jour le rig ;
-- priorité : surf > air (saut/chute) > accroupi > idle/marche/course selon la vitesse horizontale.
function CharacterAnimator.resolveState(input: AnimInput): AnimState
	if input.surfing then
		return "SURF"
	end
	if not input.onGround then
		return if input.verticalSpeed > 0 then "JUMP" else "FALL"
	end
	local moving = input.speed > CharacterConfig.IDLE_SPEED_MAX
	if input.crouching then
		return if moving then "CROUCH_WALK" else "CROUCH_IDLE"
	end
	if not moving then
		return "IDLE"
	end
	return if input.speed <= CharacterConfig.WALK_SPEED_MAX then "WALK" else "RUN"
end

-- Cette méthode permet d'obtenir l'id d'animation d'un état lorsqu'il faut charger sa piste,
-- en suivant FALLBACK tant que l'entrée est vide (ex. CROUCH_WALK → WALK).
function CharacterAnimator.resolveAnimationId(state: string): string?
	local current: string? = state
	for _ = 1, 4 do
		if not current then
			return nil
		end
		local id = CharacterConfig.ANIMATIONS[current]
		if id and id ~= "" then
			return id
		end
		current = CharacterConfig.FALLBACK[current]
	end
	return nil
end

-- Cette méthode permet de calculer la vitesse de lecture d'une piste lorsque l'état est un cycle de pas,
-- proportionnelle à la vitesse réelle (bornée) ; 1 pour les états sans référence de vitesse.
function CharacterAnimator.playbackSpeed(state: string, speed: number): number
	local ref = CharacterConfig.REF_SPEED[state]
	if not ref then
		return 1
	end
	return math.clamp(speed / ref, CharacterConfig.PLAYBACK_MIN, CharacterConfig.PLAYBACK_MAX)
end

-- Cette méthode permet de créer l'animateur d'un personnage lorsqu'il spawn ; l'Animator est résolu
-- paresseusement (createAnimator=true côté serveur pour les rigs qui n'en ont pas).
function CharacterAnimator.new(humanoid: Humanoid, createAnimator: boolean?)
	local self = setmetatable({
		humanoid = humanoid,
		createAnimator = createAnimator == true,
		animator = nil :: Animator?,
		tracks = {} :: { [string]: AnimationTrack },
		animations = {} :: { Animation },
		currentId = nil :: string?,
		currentTrack = nil :: AnimationTrack?,
		state = nil :: AnimState?,
		groundedSince = nil :: number?,
		owned = {} :: { [AnimationTrack]: boolean },
		playedConn = nil :: RBXScriptConnection?,
	}, CharacterAnimator)
	return self
end

-- Cette méthode permet de récupérer (ou créer côté serveur) l'Animator du Humanoid lorsqu'une piste doit jouer.
function CharacterAnimator:_getAnimator(): Animator?
	if self.animator and self.animator.Parent then
		return self.animator
	end
	local humanoid = self.humanoid
	if not humanoid.Parent then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator and self.createAnimator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	self.animator = animator
	if animator then
		self:_claimLocomotion(animator)
	end
	return animator
end

-- Cette méthode permet de prendre la main sur la couche locomotion lorsqu'on acquiert l'Animator : les pistes
-- Core étrangères (script Animate par défaut, qui crée ses Animation hors arborescence) sont coupées, présentes
-- et à venir ; les pistes d'autres systèmes en priorité supérieure (arme 3P en Action, #5) ne sont pas touchées.
function CharacterAnimator:_claimLocomotion(animator: Animator)
	local function stopForeignCore(track: AnimationTrack)
		if not self.owned[track] and track.Priority == Enum.AnimationPriority.Core then
			track:Stop(0)
		end
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		stopForeignCore(track)
	end
	if self.playedConn then
		self.playedConn:Disconnect()
	end
	self.playedConn = animator.AnimationPlayed:Connect(stopForeignCore)
end

-- Cette méthode permet de charger une piste une seule fois par id lorsqu'un état la demande.
function CharacterAnimator:_getTrack(animator: Animator, id: string): AnimationTrack
	local track = self.tracks[id]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		table.insert(self.animations, animation)
		track = animator:LoadAnimation(animation)
		track.Looped = true
		self.tracks[id] = track
		self.owned[track] = true
	end
	return track
end

-- Cette méthode permet d'appliquer l'état de mouvement courant au rig lorsqu'une frame est simulée :
-- fondu vers la nouvelle piste si l'état change, sinon simple ajustement de la vitesse de lecture.
function CharacterAnimator:update(input: AnimInput)
	local animator = self:_getAnimator()
	if not animator then
		return
	end
	local state = CharacterAnimator.resolveState(input)
	-- Bhop : le contact sol ne dure qu'une frame entre deux sauts ; on garde la pose aérienne
	-- tant que le sol n'est pas tenu LAND_HOLD_TIME, pour éviter un flash de course à chaque saut.
	if input.onGround then
		self.groundedSince = self.groundedSince or os.clock()
		if
			self.state
			and AIR_STATES[self.state]
			and os.clock() - self.groundedSince < CharacterConfig.LAND_HOLD_TIME
		then
			state = self.state
		end
	else
		self.groundedSince = nil
	end
	local id = CharacterAnimator.resolveAnimationId(state)
	if not id then
		return
	end

	local track = self:_getTrack(animator, id)
	if track ~= self.currentTrack then
		if self.currentTrack then
			self.currentTrack:Stop(CharacterConfig.FADE_TIME)
		end
		track.Priority = if IDLE_PRIORITY_STATES[state]
			then Enum.AnimationPriority.Idle
			else Enum.AnimationPriority.Movement
		track:Play(CharacterConfig.FADE_TIME)
		self.currentTrack = track
		self.currentId = id
	end
	self.state = state
	track:AdjustSpeed(CharacterAnimator.playbackSpeed(state, input.speed))
end

-- Cette méthode permet de renvoyer l'état d'animation joué lorsqu'un autre système (ex. arme 3P, #5) en dépend.
function CharacterAnimator:getState(): AnimState?
	return self.state
end

-- Cette méthode permet d'arrêter et libérer les pistes lorsque le personnage disparaît.
function CharacterAnimator:destroy()
	if self.playedConn then
		self.playedConn:Disconnect()
		self.playedConn = nil
	end
	for _, track in self.tracks do
		track:Stop(0)
		track:Destroy()
	end
	for _, animation in self.animations do
		animation:Destroy()
	end
	table.clear(self.tracks)
	table.clear(self.owned)
	table.clear(self.animations)
	self.currentTrack = nil
	self.currentId = nil
	self.state = nil
end

return CharacterAnimator
