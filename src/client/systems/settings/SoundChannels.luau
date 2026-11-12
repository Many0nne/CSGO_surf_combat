-- Canaux de volume (#249) : un SoundGroup général (« Master », tous les sons du jeu) et un canal « Weapons » enfant du
-- général (tirs, rechargement, sons d'animation d'arme) : volume effectif d'une arme = général × armes. Les valeurs
-- viennent des réglages (LocalSettings) et s'appliquent en direct. Règle : tout nouveau son d'arme passe par
-- SoundChannels.weapon(sound) avant d'être joué ; les autres sons sont rattachés au général automatiquement.
local SoundService = game:GetService("SoundService")

local LocalSettings = require(script.Parent.LocalSettings)

local SoundChannels = {}

local master: SoundGroup
local weapons: SoundGroup
local started = false

-- Cette méthode permet de rattacher au canal général un son créé sans groupe lorsqu'il apparaît dans le jeu (filet de
-- sécurité : un son oublié suit au moins le volume général).
local function adopt(instance: Instance)
	if instance:IsA("Sound") and instance.SoundGroup == nil then
		instance.SoundGroup = master
	end
end

-- Cette méthode permet d'appliquer les volumes des réglages aux groupes lorsqu'ils changent ou sont chargés.
local function apply(settings)
	master.Volume = settings.volumeMaster / 100
	weapons.Volume = settings.volumeWeapons / 100
end

-- Cette méthode permet de rattacher un son d'arme au canal armes lorsqu'il va être joué (viewmodel, 3P, tirs des autres) ;
-- renvoie le son pour s'enchaîner.
function SoundChannels.weapon(sound: Sound): Sound
	if started then
		sound.SoundGroup = weapons
	end
	return sound
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
	started = true

	for _, instance in game:GetDescendants() do
		adopt(instance)
	end
	game.DescendantAdded:Connect(adopt)

	apply(LocalSettings.get())
	LocalSettings.onChanged(apply)
end

return SoundChannels
