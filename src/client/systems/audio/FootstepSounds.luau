-- Bruits de pas (#146), moitié client. Pas des autres (joueurs et bots) : relayés par le serveur (remote Footstep,
-- cf. server/FootstepService), joués en 3D aux pieds de leur auteur, atténués jusqu'à FootstepRules.RANGE, hors écrans
-- du menu. Ses propres pas : décidés ici à chaque tick du mouvement (MovementController → onTick) avec les mêmes règles,
-- joués sans position et plus bas (FootstepRules.OWN_VOLUME), sans attendre le serveur.
-- Le son est porté par une Attachment du Terrain posée aux pieds, pas par le personnage (un pas s'entend jusqu'au
-- bout, même si son auteur meurt entre-temps). Volume réglable : canal « Footsteps » (SoundChannels, réglage volumeFootsteps).

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local FootstepRules = require(ReplicatedStorage.Shared.FootstepRules)
local NetworkProtocol = require(ReplicatedStorage.Shared.NetworkProtocol)
local SoundChannels = require(script.Parent.Parent.settings.SoundChannels)

local FootstepSounds = {}

-- Nom des Instances créées pour un pas (repérables en Studio).
local INSTANCE_NAME = "Footstep"

local active: { Attachment } = {}
local connection: RBXScriptConnection? = nil
local getState: () -> string? = function()
	return nil
end
local ownState: FootstepRules.State = FootstepRules.new()
local rng = Random.new()
local terrain = workspace:WaitForChild("Terrain")

-- Cette méthode permet de compter les pas des autres en cours de lecture lorsqu'un nouveau arrive (les sons finis sont
-- oubliés).
local function prune(): number
	for i = #active, 1, -1 do
		if not active[i].Parent then
			table.remove(active, i)
		end
	end
	return #active
end

-- Cette méthode permet de créer le son d'un pas lorsqu'il va être joué : son commun, hauteur tirée au hasard,
-- atterrissage plus grave et plus fort.
local function makeSound(kind: FootstepRules.Kind, volume: number): Sound
	local pitch, gain = FootstepRules.voice(kind, rng:NextNumber())
	local sound = Instance.new("Sound")
	sound.Name = INSTANCE_NAME
	sound.SoundId = FootstepRules.SOUND_ID
	sound.Volume = volume * gain
	sound.PlaybackSpeed = pitch
	return SoundChannels.footstep(sound)
end

-- Cette méthode permet de jouer le pas d'un autre en 3D aux pieds de son auteur lorsqu'il est entendu (relayé par le
-- serveur, ou rejoué par le rejeu d'une partie, #586) ; détruit à la fin de sa lecture.
function FootstepSounds.playAt(feetPos: Vector3, kind: FootstepRules.Kind)
	local anchor = Instance.new("Attachment")
	anchor.Name = INSTANCE_NAME
	anchor.WorldPosition = feetPos
	local sound = makeSound(kind, FootstepRules.VOLUME)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = FootstepRules.ROLLOFF_MIN
	sound.RollOffMaxDistance = FootstepRules.RANGE
	sound.Parent = anchor
	anchor.Parent = terrain
	table.insert(active, anchor)
	sound.Ended:Once(function()
		anchor:Destroy()
	end)
	sound:Play()
	Debris:AddItem(anchor, FootstepRules.LIFETIME)
end

-- Cette méthode permet de jouer le pas d'un autre relayé par le serveur lorsqu'il arrive, s'il doit être entendu
-- (FootstepRules.shouldPlay).
local function onFootstep(source: any, feetPos: any, kind: any)
	if typeof(feetPos) ~= "Vector3" or (kind ~= "step" and kind ~= "land") then
		return
	end
	local localPlayer = Players.LocalPlayer
	if not FootstepRules.shouldPlay(source, localPlayer and localPlayer.Character, getState(), prune()) then
		return
	end
	FootstepSounds.playAt(feetPos, kind)
end

-- Cette méthode permet de jouer ses propres pas lorsque le mouvement local avance d'un tick (dt) : au sol ou non,
-- vitesse horizontale.
function FootstepSounds.onTick(dt: number, grounded: boolean, speed: number)
	local kind = FootstepRules.update(ownState, dt, grounded, speed * dt)
	if kind then
		FootstepSounds.playOwn(kind)
	end
end

-- Cette méthode permet de jouer un de ses propres pas lorsqu'il est fait (ou rejoué en vue du joueur, #586) : son sans
-- position, plus bas que celui d'un autre.
function FootstepSounds.playOwn(kind: FootstepRules.Kind)
	local sound = makeSound(kind, FootstepRules.OWN_VOLUME)
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	Debris:AddItem(sound, FootstepRules.LIFETIME)
end

-- Cette méthode permet de repartir d'un état neuf lorsque le personnage local apparaît (pas d'atterrissage entendu au
-- spawn, foulée remise à zéro).
function FootstepSounds.reset()
	ownState = FootstepRules.new()
end

-- Cette méthode permet d'écouter les pas relayés par le serveur lorsque le client démarre ; stateOf lit l'état du
-- client (GameStateController.getState) : pas de pas entendus dans les écrans du menu.
function FootstepSounds.init(stateOf: () -> string?)
	getState = stateOf
	if connection then
		return
	end
	-- Attente hors du fil de démarrage du client (init.client continue sans elle)
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild(NetworkProtocol.Names.FOOTSTEP, 15)
		if not (remote and remote:IsA("UnreliableRemoteEvent")) then
			warn("[FootstepSounds] remote " .. NetworkProtocol.Names.FOOTSTEP .. " introuvable : pas des autres muets")
			return
		end
		if not connection then
			connection = remote.OnClientEvent:Connect(onFootstep)
		end
	end)
	-- Son chargé dès le démarrage : sinon le premier pas entendu reste muet le temps du téléchargement
	task.spawn(function()
		local sample = Instance.new("Sound")
		sample.SoundId = FootstepRules.SOUND_ID
		ContentProvider:PreloadAsync({ sample })
	end)
end

return FootstepSounds
