-- Son des tirs des autres (#156) : règles pures du client (RemoteShotSounds), testées sous Lune
-- (tests/specs/ShotSoundRules.spec.luau). Le serveur relaie chaque tir à distance accepté (ShotFired) ; le client joue
-- une copie du son de tir de l'arme (celui que le tireur entend chez lui) en 3D sur l'arme 3P du tireur, avec une
-- atténuation propre à l'arme (WeaponConfig.Weapons.<nom>.RemoteShotSound).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

local ShotSoundRules = {}

-- Nom de l'Instance créée pour chaque tir entendu (repérable en Studio, et dans le dossier Sounds du viewmodel le nom
-- du son de tir, cf. WeaponConfig.AnimationSounds.Shoot).
ShotSoundRules.INSTANCE_NAME = "RemoteShot"
-- Atténuation par défaut d'une arme sans RemoteShotSound (studs) : volume plein jusqu'à RollOffMinDistance, puis en
-- 1/distance, ramené à zéro à RollOffMaxDistance (Enum.RollOffMode.InverseTapered).
ShotSoundRules.DEFAULT = {
	Sound = "Shoot",
	RollOffMinDistance = 20,
	RollOffMaxDistance = 600,
}
-- Sons de tir distants joués en même temps au plus : au-delà, un tir de plus n'est pas joué (beaucoup de bots).
ShotSoundRules.MAX_ACTIVE = 16
-- Durée de vie d'un son (s) : sa longueur + une marge, ou MAX_LIFETIME si elle n'est pas encore connue (son en
-- chargement, TimeLength = 0). Filet si Ended ne vient pas (son coupé) : le son est détruit quoi qu'il arrive.
ShotSoundRules.LIFETIME_MARGIN = 0.5
ShotSoundRules.MAX_LIFETIME = 5
-- États du client (GameStateController) où l'on entend les tirs : pas dans les écrans du menu, dont la salle flotte
-- au-dessus de la map (une AWP s'entend de loin).
ShotSoundRules.AUDIBLE_STATES = {
	SPAWNING = true,
	IN_ROUND = true,
	DEAD = true,
	RESULT = true,
} :: { [string]: boolean }

export type Settings = { Sound: string, RollOffMinDistance: number, RollOffMaxDistance: number }

-- Cette méthode permet de lire le son et l'atténuation d'un tir entendu lorsqu'il arrive (valeurs de l'arme,
-- complétées par DEFAULT) ; nil pour une arme inconnue ou de mêlée.
function ShotSoundRules.settingsFor(weaponName: any): Settings?
	local cfg = type(weaponName) == "string" and WeaponConfig.Weapons[weaponName]
	if not cfg or cfg.IsMelee then
		return nil
	end
	local own = cfg.RemoteShotSound or {}
	local minDistance = own.RollOffMinDistance or ShotSoundRules.DEFAULT.RollOffMinDistance
	return {
		Sound = own.Sound or ShotSoundRules.DEFAULT.Sound,
		RollOffMinDistance = minDistance,
		RollOffMaxDistance = math.max(own.RollOffMaxDistance or ShotSoundRules.DEFAULT.RollOffMaxDistance, minDistance),
	}
end

-- Cette méthode permet de décider si un tir relayé est joué lorsqu'il arrive : un personnage connu qui n'est pas le
-- nôtre (le tireur joue déjà son propre son), un état où l'on entend, et de la place parmi les sons en cours.
function ShotSoundRules.shouldPlay(shooter: any, localCharacter: any, state: string?, activeCount: number): boolean
	if shooter == nil or shooter == localCharacter then
		return false
	end
	if not (state and ShotSoundRules.AUDIBLE_STATES[state]) then
		return false
	end
	return activeCount < ShotSoundRules.MAX_ACTIVE
end

-- Cette méthode permet de fixer la durée de vie d'un son de tir lorsqu'il est lancé (longueur lue à la vitesse de
-- lecture, plus une marge ; MAX_LIFETIME si la longueur est inconnue), bornée à MAX_LIFETIME.
function ShotSoundRules.lifetime(timeLength: number, playbackSpeed: number): number
	if not (timeLength > 0) or not (playbackSpeed > 0) then
		return ShotSoundRules.MAX_LIFETIME
	end
	return math.min(timeLength / playbackSpeed + ShotSoundRules.LIFETIME_MARGIN, ShotSoundRules.MAX_LIFETIME)
end

return ShotSoundRules
