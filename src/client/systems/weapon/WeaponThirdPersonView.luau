-- WeaponThirdPersonView.luau
-- Rendu client des armes 3e personne (#5) de tous les personnages.
-- Le serveur attache les modèles (WeaponThirdPerson.attach, tag "Weapon3P") et pose l'action
-- courante en attributs ; ici, chaque frame : décalage procédural du grip (tir/recharge/switch)
-- et visibilité (le joueur local ne voit jamais son propre modèle 3P : le jeu est toujours en 1re personne).
-- Tenue (#107) : après l'Animator, le haut du corps des personnages armés prend la tenue de l'arme
-- (WeaponThirdPerson.POSES), les jambes gardent les pistes de déplacement répliquées. La tenue n'existe que
-- côté client : le serveur voit les bras dans la pose des pistes (sans incidence tant que la validation des tirs
-- ne contrôle que la pièce touchée).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WeaponThirdPerson = require(ReplicatedStorage.Shared.WeaponThirdPerson)
local CharacterAnimator = require(ReplicatedStorage.Shared.CharacterAnimator)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)

local WeaponThirdPersonView = {}

local settingsCache: { [string]: any } = {}

local MOTOR_RETRY_INTERVAL = 0.5 -- délai entre deux recherches d'un Motor6D encore absent (s)

-- Tenue en cours par personnage : couches (pose, poids) pour fondre d'une arme à l'autre, part aérienne lissée,
-- Motor6D et Animator du rig, pistes aériennes en cours, articulations tenues à la frame précédente.
type HoldState = {
	char: Model,
	layers: { WeaponThirdPerson.HoldLayer },
	air: number,
	motors: { [string]: Motor6D },
	missing: boolean,
	nextResolve: number,
	animator: Animator?,
	airTracks: { [AnimationTrack]: boolean },
	playedConn: RBXScriptConnection?,
	held: { [string]: boolean },
}
local holds: { [Model]: HoldState } = {}
local posesThisFrame: { [Model]: string } = {}
-- Motor6D d'une tenue terminée, à remettre au repos avant la prochaine passe d'animation.
local pendingRelease: { Motor6D } = {}

-- Cette méthode permet de mémoriser les réglages 3P par arme lorsqu'on anime un modèle chaque frame.
local function getSettings(weaponName: string)
	local s = settingsCache[weaponName]
	if not s then
		s = WeaponThirdPerson.getSettings(weaponName)
		settingsCache[weaponName] = s
	end
	return s
end

-- Cette méthode permet de lire les réglages 3P d'un modèle (attribut WeaponName posé par le serveur) lorsqu'on
-- anime son grip ou choisit la tenue du haut du corps.
local function settingsOf(gun: Instance)
	local weaponName = gun:GetAttribute("WeaponName")
	return getSettings(if type(weaponName) == "string" then weaponName else "")
end

-- Cette méthode permet d'appliquer une transparence locale à toutes les pièces d'un modèle 3P
-- lorsque sa visibilité pour ce client est recalculée.
local function setLocalVisible(gun: Instance, visible: boolean)
	local modifier = if visible then 0 else 1
	for _, inst in gun:GetDescendants() do
		if inst:IsA("BasePart") and inst.LocalTransparencyModifier ~= modifier then
			inst.LocalTransparencyModifier = modifier
		end
	end
end

-- Cette méthode permet de mettre à jour un modèle 3P lorsqu'une frame est rendue : visibilité
-- puis C0 du grip = grip de base * décalage de l'action en cours.
local function updateGun(gun: Instance, localChar: Model?)
	local char = gun.Parent
	if not char or not char:IsA("Model") then
		return
	end

	setLocalVisible(gun, WeaponThirdPerson.isVisibleTo(char == localChar))

	local handle = gun:FindFirstChild("Handle")
	local weld = handle and handle:FindFirstChild(WeaponThirdPerson.WELD_NAME)
	local grip = gun:GetAttribute("GripC0")
	if not (weld and weld:IsA("Weld") and typeof(grip) == "CFrame") then
		return
	end
	local action = char:GetAttribute(WeaponThirdPerson.ACTION_ATTR)
	local at = char:GetAttribute(WeaponThirdPerson.ACTION_AT_ATTR)
	local offset = CFrame.identity
	if type(action) == "string" and type(at) == "number" then
		offset = WeaponThirdPerson.actionOffset(action, workspace:GetServerTimeNow() - at, settingsOf(gun))
	end
	weld.C0 = grip * offset
end

-- Cette méthode permet de (re)chercher les Motor6D du haut du corps lorsqu'une tenue commence ou qu'il en manque
-- encore un (réplication en cours) ; la recherche suivante attend MOTOR_RETRY_INTERVAL.
local function resolveMotors(state: HoldState)
	local missing = false
	for _, name in WeaponThirdPerson.HOLD_JOINTS do
		local motor = state.motors[name]
		if not (motor and motor.Parent) then
			local found = state.char:FindFirstChild(name, true)
			if found and found:IsA("Motor6D") then
				state.motors[name] = found
			else
				state.motors[name] = nil
				missing = true
			end
		end
	end
	state.missing = missing
	state.nextResolve = os.clock() + MOTOR_RETRY_INTERVAL
end

-- Cette méthode permet de suivre les pistes aériennes d'un personnage (saut, chute, surf) lorsqu'on trouve son
-- Animator : un relevé des pistes en cours, puis l'événement AnimationPlayed, sans allocation par frame.
local function watchAnimator(state: HoldState, animator: Animator)
	if state.playedConn then
		state.playedConn:Disconnect()
	end
	state.animator = animator
	table.clear(state.airTracks)
	-- Cette méthode permet de retenir une piste lorsqu'elle démarre et qu'elle est aérienne.
	local function onPlayed(track: AnimationTrack)
		local animation = track.Animation
		if animation and CharacterAnimator.isAirborneAnimationId(animation.AnimationId) then
			state.airTracks[track] = true
		end
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		onPlayed(track)
	end
	state.playedConn = animator.AnimationPlayed:Connect(onPlayed)
end

-- Cette méthode permet de savoir si un personnage distant joue une piste aérienne lorsqu'une tenue ne tient un bras
-- qu'en l'air ; l'état vient des pistes répliquées, seul signal disponible côté client.
local function isAirborne(state: HoldState): boolean
	local animator = state.animator
	if not (animator and animator.Parent) then
		local humanoid = state.char:FindFirstChildOfClass("Humanoid")
		local found = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if not found then
			return false
		end
		watchAnimator(state, found)
	end
	local airborne = false
	for track in state.airTracks do
		if not track.IsPlaying then
			state.airTracks[track] = nil
		elseif track.WeightTarget > 0.5 then
			airborne = true
		end
	end
	return airborne
end

-- Cette méthode permet de faire évoluer les couches de tenue d'un personnage lorsqu'une frame est simulée
-- (Motor6D recherchés à chaque nouvelle tenue) ; renvoie false s'il n'en reste aucune.
local function stepLayers(state: HoldState, pose: string?, dt: number): boolean
	if WeaponThirdPerson.stepLayers(state.layers, pose, dt) then
		resolveMotors(state)
	end
	return #state.layers > 0
end

-- Cette méthode permet d'imposer la tenue au haut du corps d'un personnage lorsque l'Animator a posé ses pistes :
-- chaque Motor6D tenu est fondu de la pose animée vers la pose de tenue, couche après couche.
local function applyHold(state: HoldState, dt: number)
	if state.missing and os.clock() >= state.nextResolve then
		resolveMotors(state)
	end
	local needsAir = false
	for _, layer in state.layers do
		local pose = WeaponThirdPerson.POSES[layer.pose]
		if pose and pose.AirJoints then
			needsAir = true
		end
	end
	if needsAir then
		state.air = WeaponThirdPerson.approach(state.air, if isAirborne(state) then 1 else 0, dt)
	else
		-- plus de couteau : on cesse de suivre les pistes aériennes (rien ne les purgerait)
		state.air = 0
		if state.playedConn then
			state.playedConn:Disconnect()
			state.playedConn = nil
			state.animator = nil
			table.clear(state.airTracks)
		end
	end
	for name, motor in state.motors do
		-- Transform vaut la pose des pistes, ou le repos si aucune ne pilote l'articulation (remise à zéro en
		-- PreAnimation) : le fondu part donc toujours de l'animation, jamais de notre résultat précédent.
		local result = WeaponThirdPerson.blendHold(motor.Transform, state.layers, name, state.air)
		if result then
			motor.Transform = result
			state.held[name] = true
		else
			state.held[name] = nil
		end
	end
end

-- Cette méthode permet de remettre au repos les articulations tenues avant la passe d'animation : celles que les
-- pistes pilotent sont réécrites par l'Animator, les autres ne gardent pas la tenue (taille, cou) une fois l'arme rangée.
local function resetHeldJoints()
	for _, state in holds do
		for name in state.held do
			local motor = state.motors[name]
			if motor then
				motor.Transform = CFrame.identity
			end
		end
	end
	for _, motor in pendingRelease do
		motor.Transform = CFrame.identity
	end
	table.clear(pendingRelease)
end

-- Cette méthode permet d'oublier la tenue d'un personnage lorsqu'il n'est plus armé ou quitte la scène :
-- ses articulations tenues seront remises au repos avant la prochaine passe d'animation.
local function dropHold(char: Model, state: HoldState)
	for name in state.held do
		local motor = state.motors[name]
		if motor and motor.Parent then
			table.insert(pendingRelease, motor)
		end
	end
	if state.playedConn then
		state.playedConn:Disconnect()
	end
	holds[char] = nil
end

-- Cette méthode permet de poser la tenue de tous les personnages armés visibles lorsqu'une frame est simulée
-- (après les animations) ; le personnage local est ignoré, son corps n'est jamais affiché.
local function updateHolds(dt: number)
	local localChar = Players.LocalPlayer and Players.LocalPlayer.Character
	table.clear(posesThisFrame)
	for _, gun in CollectionService:GetTagged(WeaponThirdPerson.TAG) do
		local char = gun.Parent
		if char and char:IsA("Model") and char ~= localChar then
			posesThisFrame[char] = settingsOf(gun).Pose
			if not holds[char] then
				holds[char] = {
					char = char,
					layers = {},
					air = 0,
					motors = {},
					missing = true,
					nextResolve = 0,
					animator = nil,
					airTracks = {},
					playedConn = nil,
					held = {},
				}
			end
		end
	end
	for char, state in holds do
		if not char.Parent or not stepLayers(state, posesThisFrame[char], dt) then
			dropHold(char, state)
		else
			applyHold(state, dt)
		end
	end
end

-- Cette méthode permet de démarrer la boucle de rendu des armes 3P et la tenue des personnages lorsque le client
-- s'initialise.
function WeaponThirdPersonView.init()
	RunService.RenderStepped:Connect(PerfMarkers.wrap("armes 3P", function()
		local localChar = Players.LocalPlayer and Players.LocalPlayer.Character
		for _, gun in CollectionService:GetTagged(WeaponThirdPerson.TAG) do
			updateGun(gun, localChar)
		end
	end))
	-- PreAnimation précède l'Animator, PreSimulation le suit : un Transform posé en PreSimulation remplace celui
	-- des pistes pour la frame.
	RunService.PreAnimation:Connect(PerfMarkers.wrap("tenue 3P", resetHeldJoints))
	RunService.PreSimulation:Connect(PerfMarkers.wrap("tenue 3P", updateHolds))
end

return WeaponThirdPersonView
