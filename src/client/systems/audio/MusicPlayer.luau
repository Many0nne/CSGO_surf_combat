-- Musique de fond (#286) : une piste en boucle (MusicRules.TRACK_ID) sur le canal « Music » (SoundChannels), si le
-- réglage `music` est activé (coupé par défaut). Pleine au menu, atténuée en partie et au plus bas pendant un combat
-- (MusicRules) : nos tirs et coups (WeaponSystem en état FIRING), un dégât reçu, ou un tir relayé d'un autre à moins
-- de COMBAT_RADIUS. Le réglage s'applique en direct : coupée, elle s'éteint en fondu puis se met en pause.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local NetworkProtocol = require(ReplicatedStorage.Shared.NetworkProtocol)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local MusicRules = require(script.Parent.MusicRules)
local LocalSettings = require(script.Parent.Parent.settings.LocalSettings)
local SoundChannels = require(script.Parent.Parent.settings.SoundChannels)

local MusicPlayer = {}

local sound: Sound
local level = 0
local lastCombat: number? = nil
local started = false

-- Cette méthode permet de noter le début ou la suite d'un combat lorsque le joueur tire, est touché ou entend un tir
-- proche.
local function noteCombat()
	lastCombat = os.clock()
end

-- Cette méthode permet de suivre les dégâts reçus par un personnage du joueur lorsqu'il apparaît.
local function watchCharacter(char: Model)
	local humanoid = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	local health = humanoid.Health
	humanoid.HealthChanged:Connect(function(newHealth)
		if newHealth < health then
			noteCombat()
		end
		health = newHealth
	end)
end

-- Cette méthode permet de compter comme un combat un tir relayé d'un autre lorsqu'il part près de la caméra.
local function onShotFired(_shooter: any, _weaponName: any, origin: any)
	local camera = workspace.CurrentCamera
	if MusicRules.isNearShot(camera and camera.CFrame.Position, origin) then
		noteCombat()
	end
end

-- Cette méthode permet de lancer la piste lorsqu'elle doit être entendue et de la mettre en pause une fois éteinte.
local function setPlaying(playing: boolean)
	if playing and not sound.IsPlaying then
		if sound.TimePosition > 0 then
			sound:Resume()
		else
			sound:Play()
		end
	elseif not playing and sound.IsPlaying then
		sound:Pause()
	end
end

-- Cette méthode permet de rapprocher le volume de la musique du niveau visé lorsqu'une frame passe.
local function update(dt: number, getState: () -> string?, getWeaponState: () -> string)
	if getWeaponState() == "FIRING" then
		noteCombat()
	end
	local enabled = LocalSettings.get().music and sound.SoundId ~= ""
	local sinceCombat = if lastCombat then os.clock() - lastCombat else nil
	local target = MusicRules.targetLevel(enabled, getState(), sinceCombat)
	level = MusicRules.step(level, target, dt)
	sound.Volume = MusicRules.BASE_VOLUME * level
	setPlaying(level > 0)
end

-- Cette méthode permet de créer la piste et de suivre l'écran, le combat et le réglage lorsque le client démarre ;
-- getState lit l'état du client (GameStateController), getWeaponState celui de l'arme (WeaponSystem).
function MusicPlayer.init(getState: () -> string?, getWeaponState: () -> string)
	if started then
		return
	end
	started = true

	sound = Instance.new("Sound")
	sound.Name = "BackgroundMusic"
	sound.SoundId = MusicRules.TRACK_ID
	sound.Looped = true
	sound.Volume = 0
	SoundChannels.music(sound)
	sound.Parent = SoundService

	local player = Players.LocalPlayer
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)

	-- Attente hors du fil de démarrage du client (init.client continue sans elle)
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild(NetworkProtocol.Names.SHOT_FIRED, 15)
		if remote and remote:IsA("RemoteEvent") then
			remote.OnClientEvent:Connect(onShotFired)
		end
	end)

	RunService.Heartbeat:Connect(PerfMarkers.wrap("musique", function(dt: number)
		update(dt, getState, getWeaponState)
	end))
end

return MusicPlayer
