-- Son de hitmarker (#402) : tick court joué pour le seul tireur à chaque touche confirmée par le serveur (HIT_CONFIRM,
-- branché par Hitmarker), en 2D, kill et tête compris (l'annonce « Headshot » de KillAnnouncer s'y ajoute). Pas de
-- canal dédié : rattaché au volume général par SoundChannels. Son du Creator Store (« hitmarker_2 », NeoDoesStuff).
-- Mesuré au volume 1 : 66 ms, crête atteinte en moins de 15 ms, crête 1.0, RMS 0.46 (tir AWP joué à 0.5 : RMS ~0.10).
-- Quelques voix jouées à tour de rôle : deux touches rapprochées ne se coupent pas l'une l'autre.
local SoundService = game:GetService("SoundService")

local SOUND_ID = "rbxassetid://125235091454234"
local VOLUME = 0.2 -- RMS ~0.09 : au niveau d'un tir, crête deux fois plus basse
local VOICES = 3

local HitSound = {}

local voices: { Sound } = {}
local nextVoice = 1

-- Cette méthode permet de créer les voix du tick une seule fois lorsque le client démarre, pour que le son soit chargé
-- avant la première touche.
function HitSound.init()
	if #voices > 0 then
		return
	end
	for i = 1, VOICES do
		local sound = Instance.new("Sound")
		sound.Name = "HitSound" .. i
		sound.SoundId = SOUND_ID
		sound.Volume = VOLUME
		sound.Parent = SoundService
		table.insert(voices, sound)
	end
end

-- Cette méthode permet de jouer le tick lorsqu'une touche est confirmée ; prend la voix suivante du tour pour ne pas
-- couper un tick encore en cours.
function HitSound.play()
	HitSound.init()
	local sound = voices[nextVoice]
	nextVoice = nextVoice % VOICES + 1
	sound.TimePosition = 0
	sound:Play()
end

return HitSound
