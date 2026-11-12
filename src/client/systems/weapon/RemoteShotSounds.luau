-- RemoteShotSounds.luau
-- Tirs des autres entendus (#156) : le serveur relaie chaque tir à distance accepté, de joueur ou de bot, touché ou
-- manqué (remote ShotFired : personnage du tireur, nom de l'arme, origine, direction) à tous les clients sauf le
-- tireur. Ici, une copie du son de tir de l'arme (celui que le tireur entend chez lui, cloné sur la poignée du modèle
-- 3P par WeaponThirdPerson) est jouée en 3D à la position de l'arme 3P du tireur (repli : sa racine), avec
-- l'atténuation de l'arme (ShotSoundRules), puis détruite à la fin de sa lecture. Le son du tireur n'est pas touché.
-- Le son est porté par une Attachment du Terrain qui suit l'arme à chaque frame, pas par l'arme elle-même : le modèle
-- 3P est détruit quand le tireur change d'arme ou meurt, ce qui couperait le son en pleine lecture.
-- Origine et direction servent à la flamme de bouche et au rayon du tir chez les autres (ShotEffects, #54).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NetworkProtocol = require(ReplicatedStorage.Shared.NetworkProtocol)
local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local ShotSoundRules = require(ReplicatedStorage.Shared.ShotSoundRules)
local WeaponThirdPerson = require(ReplicatedStorage.Shared.WeaponThirdPerson)
local SoundChannels = require(script.Parent.Parent.settings.SoundChannels)

local RemoteShotSounds = {}

-- Son en cours : son ancrage (Attachment du Terrain, détruit avec le son) et la pièce qu'il suit.
type Entry = { anchor: Attachment, source: BasePart }

local entries: { Entry } = {}
local followConn: RBXScriptConnection? = nil
local connection: RBXScriptConnection? = nil
local getState: () -> string? = function()
	return nil
end
local terrain = workspace:WaitForChild("Terrain")

-- Cette méthode permet d'oublier les sons détruits (fin de lecture, durée de vie) lorsqu'on compte ou déplace les sons.
local function prune(): number
	for i = #entries, 1, -1 do
		if not entries[i].anchor.Parent then
			table.remove(entries, i)
		end
	end
	return #entries
end

-- Cette méthode permet de faire suivre l'arme du tireur aux sons en cours lorsqu'une frame passe ; un son dont l'arme a
-- disparu reste où elle était, et la boucle s'arrête quand il n'y a plus de son.
local function follow()
	prune()
	for _, entry in entries do
		if entry.source:IsDescendantOf(workspace) then
			entry.anchor.WorldPosition = entry.source.Position
		end
	end
	if #entries == 0 and followConn then
		followConn:Disconnect()
		followConn = nil
	end
end
local timedFollow = PerfMarkers.wrap("sons de tir", follow)

-- Cette méthode permet de trouver le son de tir modèle et la pièce à suivre lorsqu'un tir est entendu : poignée 3P du
-- tireur et son son cloné, sinon racine du personnage et son du viewmodel de l'outil en main.
local function resolve(shooter: Model, weaponName: string, soundName: string): (Sound?, BasePart?)
	local gun = shooter:FindFirstChild(WeaponThirdPerson.MODEL_NAME)
	local handle = gun and gun:FindFirstChild("Handle")
	local template = handle and handle:FindFirstChild(soundName)
	if not (template and template:IsA("Sound")) then
		local tool = shooter:FindFirstChildOfClass("Tool")
		local viewmodelName = tool and tool:GetAttribute("ViewmodelName")
		if type(viewmodelName) ~= "string" or viewmodelName == "" then
			viewmodelName = weaponName
		end
		local container = ReplicatedStorage:FindFirstChild("ViewModels")
		local viewmodel = container and container:FindFirstChild(viewmodelName)
		local sounds = viewmodel and viewmodel:FindFirstChild("Sounds")
		template = sounds and sounds:FindFirstChild(soundName)
	end
	local source = if handle and handle:IsA("BasePart") then handle else shooter:FindFirstChild("HumanoidRootPart")
	if not (template and template:IsA("Sound")) or not (source and source:IsA("BasePart")) then
		return nil, nil
	end
	return template, source
end

-- Cette méthode permet de jouer le son d'un tir relayé par le serveur lorsqu'il arrive : copie du son de l'arme en 3D
-- qui suit l'arme du tireur, détruite à la fin de sa lecture (ou au plus tard après sa durée de vie).
local function onShotFired(shooter: any, weaponName: any)
	if typeof(shooter) ~= "Instance" or not shooter:IsA("Model") then
		return
	end
	local localPlayer = Players.LocalPlayer
	if not ShotSoundRules.shouldPlay(shooter, localPlayer and localPlayer.Character, getState(), prune()) then
		return
	end
	local settings = ShotSoundRules.settingsFor(weaponName)
	if not settings then
		return
	end
	local template, source = resolve(shooter, weaponName, settings.Sound)
	if not template or not source then
		return
	end
	local anchor = Instance.new("Attachment")
	anchor.Name = ShotSoundRules.INSTANCE_NAME
	anchor.WorldPosition = source.Position
	local sound = template:Clone()
	sound.Name = ShotSoundRules.INSTANCE_NAME
	SoundChannels.weapon(sound)
	sound.Looped = false
	sound.PlayOnRemove = false
	sound.TimePosition = 0
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = settings.RollOffMinDistance
	sound.RollOffMaxDistance = settings.RollOffMaxDistance
	sound.Parent = anchor
	anchor.Parent = terrain
	table.insert(entries, { anchor = anchor, source = source })
	if not followConn then
		followConn = RunService.Heartbeat:Connect(timedFollow)
	end
	sound.Ended:Once(function()
		anchor:Destroy()
	end)
	sound:Play()
	Debris:AddItem(anchor, ShotSoundRules.lifetime(sound.TimeLength, sound.PlaybackSpeed))
end

-- Cette méthode permet d'écouter les tirs relayés par le serveur lorsque le client démarre ; stateOf lit l'état du
-- client (GameStateController.getState) : pas de tirs entendus dans les écrans du menu.
function RemoteShotSounds.init(stateOf: () -> string?)
	getState = stateOf
	if connection then
		return
	end
	-- Attente hors du fil de démarrage du client (init.client continue sans elle)
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild(NetworkProtocol.Names.SHOT_FIRED, 15)
		if not (remote and remote:IsA("RemoteEvent")) then
			warn(
				"[RemoteShotSounds] remote "
					.. NetworkProtocol.Names.SHOT_FIRED
					.. " introuvable : tirs des autres muets"
			)
			return
		end
		if not connection then
			connection = remote.OnClientEvent:Connect(onShotFired)
		end
	end)
end

return RemoteShotSounds
