-- Musique de fond (#286) : une piste en boucle (MusicRules.TRACK_ID) sur le canal « Music » (SoundChannels), si le
-- réglage `music` est activé (coupé par défaut). Volume propre aux écrans du menu (`volumeMusicMenu`) et à la partie
-- (`volumeMusicGame`), baissé pendant les annonces vocales (KillAnnouncer) mais jamais par les tirs. Les réglages
-- s'appliquent en direct : coupée, la musique s'éteint en fondu puis se met en pause.
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local MusicRules = require(script.Parent.MusicRules)
local LocalSettings = require(script.Parent.Parent.settings.LocalSettings)
local SoundChannels = require(script.Parent.Parent.settings.SoundChannels)

local MusicPlayer = {}

local sound: Sound
local volume = 0
local started = false

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

-- Cette méthode permet de rapprocher le volume de la musique du volume visé lorsqu'une frame passe.
local function update(dt: number, getState: () -> string?, isAnnouncing: () -> boolean)
	local settings = LocalSettings.get()
	local target = 0
	if sound.SoundId ~= "" then
		target = MusicRules.targetVolume(settings, getState(), MusicRules.isDucking(settings, isAnnouncing()))
	end
	volume = MusicRules.step(volume, target, dt)
	sound.Volume = MusicRules.BASE_VOLUME * volume
	setPlaying(volume > 0)
end

-- Cette méthode permet de créer la piste et de suivre l'écran, les annonces et les réglages lorsque le client démarre ;
-- getState lit l'état du client (GameStateController), isAnnouncing dit si une annonce vocale joue (KillAnnouncer).
function MusicPlayer.init(getState: () -> string?, isAnnouncing: () -> boolean)
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

	RunService.Heartbeat:Connect(PerfMarkers.wrap("musique", function(dt: number)
		update(dt, getState, isAnnouncing)
	end))
end

return MusicPlayer
