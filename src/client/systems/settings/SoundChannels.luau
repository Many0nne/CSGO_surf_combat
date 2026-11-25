-- Canaux de volume (#249) : un SoundGroup général (« Master », tous les sons du jeu) et quatre canaux enfants du général,
-- « Weapons » (tirs, rechargement, sons d'animation d'arme : volume effectif d'une arme = général × armes), « Music »
-- (musique de fond, #286 : suit le général ; ses volumes menu et partie sont appliqués par MusicPlayer) et « Announcer »
-- (voix des annonces de kills, #405 : volume effectif = général × annonces × volume de base) et « Footsteps » (bruits de
-- pas, #146 : les siens et ceux des autres, volume effectif = général × pas × volume de base). Les valeurs
-- viennent des réglages (LocalSettings) et s'appliquent en direct. Règle : tout nouveau son d'arme passe par
-- SoundChannels.weapon(sound) avant d'être joué ; les autres sons sont rattachés au général automatiquement, dans les
-- conteneurs où un son peut apparaître (#606 : plus d'écoute de tout le jeu, qui appelait du Lua pour chaque Instance
-- créée, maps comprises).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local MapSelection = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MapSelection"))
local LocalSettings = require(script.Parent.LocalSettings)

local SoundChannels = {}

local master: SoundGroup
local weapons: SoundGroup
local music: SoundGroup
local announcer: SoundGroup
local footsteps: SoundGroup
local started = false
-- Arbres déjà suivis : un enfant retiré puis remis n'est pas branché deux fois (oublié à sa destruction)
local watched: { [Instance]: boolean } = {}

-- Conteneurs suivis en entier : sons du jeu (SoundService), de l'interface et des Tools du sac (Players)
local WATCHED_SERVICES = { "SoundService", "Players", "ReplicatedFirst", "Lighting" }
-- Conteneurs suivis enfant par enfant, sans les dossiers des maps (milliers de pièces à chaque échange, aucun son)
local SPLIT_SERVICES: { [string]: { [string]: boolean } } = {
	Workspace = { Maps = true },
	ReplicatedStorage = { [MapSelection.STORE_NAME] = true },
}

-- Cette méthode permet de rattacher au canal général un son créé sans groupe lorsqu'il apparaît dans le jeu (filet de
-- sécurité : un son oublié suit au moins le volume général).
local function adopt(instance: Instance)
	if instance:IsA("Sound") and instance.SoundGroup == nil then
		-- Dossier « Sounds » d'un viewmodel : sons d'arme (cf. docs/assets.md), les copies jouées en héritent
		local parent = instance.Parent
		instance.SoundGroup = if parent and parent.Name == "Sounds" then weapons else master
	end
end

-- Cette méthode permet de rattacher les sons d'un arbre (existants et futurs) lorsqu'un conteneur suivi le reçoit.
local function watchTree(root: Instance)
	if watched[root] then
		return
	end
	watched[root] = true
	root.Destroying:Once(function()
		watched[root] = nil
	end)
	adopt(root)
	for _, instance in root:GetDescendants() do
		adopt(instance)
	end
	root.DescendantAdded:Connect(adopt)
end

-- Cette méthode permet de suivre un service enfant par enfant lorsque le client démarre, sauf les enfants nommés dans
-- `skip` (dossiers des maps).
local function watchChildren(service: Instance, skip: { [string]: boolean })
	-- Cette méthode permet de suivre un enfant du service lorsqu'il est présent ou arrive.
	local function onChild(child: Instance)
		if not skip[child.Name] then
			watchTree(child)
		end
	end
	for _, child in service:GetChildren() do
		onChild(child)
	end
	service.ChildAdded:Connect(onChild)
end

-- Cette méthode permet d'appliquer les volumes des réglages aux groupes lorsqu'ils changent ou sont chargés.
local function apply(settings)
	master.Volume = settings.volumeMaster / 100
	weapons.Volume = settings.volumeWeapons / 100
	announcer.Volume = settings.volumeAnnouncer / 100
	footsteps.Volume = settings.volumeFootsteps / 100
end

-- Cette méthode permet de rattacher un son d'arme au canal armes lorsqu'il va être joué (viewmodel, 3P, tirs des autres) ;
-- renvoie le son pour s'enchaîner.
function SoundChannels.weapon(sound: Sound): Sound
	if started then
		sound.SoundGroup = weapons
	end
	return sound
end

-- Cette méthode permet de rattacher la musique de fond au canal musique lorsqu'elle est créée (#286) ; renvoie le son.
function SoundChannels.music(sound: Sound): Sound
	if started then
		sound.SoundGroup = music
	end
	return sound
end

-- Cette méthode permet de rattacher la voix de l'annonceur de kills au canal annonces lorsqu'une annonce va être jouée ;
-- renvoie le son.
function SoundChannels.announcer(sound: Sound): Sound
	if started then
		sound.SoundGroup = announcer
	end
	return sound
end

-- Cette méthode permet de rattacher un bruit de pas au canal pas lorsqu'il va être joué (#146) ; renvoie le son.
function SoundChannels.footstep(sound: Sound): Sound
	if started then
		sound.SoundGroup = footsteps
	end
	return sound
end

-- Cette méthode permet de couper la musique de fond (canal « Music ») lorsque le rejeu d'une partie démarre (#586 : le
-- son des rushes n'a que les sons de jeu, la musique se choisit au montage), puis de la rendre à sa fin.
function SoundChannels.setMusicMuted(muted: boolean)
	if started then
		music.Volume = if muted then 0 else 1
	end
end

-- Cette méthode permet de créer les groupes, d'y rattacher les sons existants et futurs, et de suivre les réglages
-- lorsque le client démarre.
function SoundChannels.init()
	if started then
		return
	end
	master = Instance.new("SoundGroup")
	master.Name = "Master"
	master.Parent = SoundService
	weapons = Instance.new("SoundGroup")
	weapons.Name = "Weapons"
	weapons.Parent = master
	music = Instance.new("SoundGroup")
	music.Name = "Music"
	music.Parent = master
	announcer = Instance.new("SoundGroup")
	announcer.Name = "Announcer"
	announcer.Parent = master
	footsteps = Instance.new("SoundGroup")
	footsteps.Name = "Footsteps"
	footsteps.Parent = master
	started = true

	for _, name in WATCHED_SERVICES do
		watchTree(game:GetService(name))
	end
	for name, skip in SPLIT_SERVICES do
		watchChildren(game:GetService(name), skip)
	end

	apply(LocalSettings.get())
	LocalSettings.onChanged(apply)
end

return SoundChannels
