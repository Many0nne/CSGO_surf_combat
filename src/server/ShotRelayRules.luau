-- Relais des tirs aux autres clients (#156, docs/anticheat.md « Remotes ») : règles pures, sans service ni workspace,
-- testées sous Lune (tests/specs/ShotRelayRules.spec.luau).
-- Chaque tir à distance (touché ou manqué) d'un joueur arrive par le remote ShotFired (origine, direction) ; un tir de
-- bot vient de BotArsenal. Le serveur le relaie à tous les autres clients, qui jouent le son de l'arme en 3D. Il ne
-- relaie qu'un tir plausible : arme à distance en main, forme, origine près du tireur, et cadence de l'arme (un client
-- modifié ne fait pas entendre 20 tirs par seconde chez tout le monde). Un tir écarté n'est pas journalisé : sans
-- dégâts, il ne gagne rien, et la garde commune (RemoteGuard) journalise déjà le débit et les types impossibles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)
local PositionHistory = require(ReplicatedStorage.Shared.PositionHistory)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local ShotRules = require(ServerScriptService.Server.ShotRules)

local ShotRelayRules = {}

-- Tolérance (s) sur la cadence de l'arme : la même que celle des touches (Validator), gigue entre deux paquets.
ShotRelayRules.CADENCE_TOLERANCE = ShotRules.CADENCE_TOLERANCE
-- Origine relayée : à moins de cette distance (studs) de la racine du tireur vue par le serveur. Le client est en
-- avance de sa latence : base de l'origine des tirs + MAX_SPEED_SERVER × rembobinage maximal (5 + 450 × 0,4 = 185).
-- Large exprès : un tir honnête n'est jamais écarté, une origine forgée à l'autre bout de la map l'est.
ShotRelayRules.ORIGIN_MAX = ShotRules.ORIGIN_BASE + MovementConfig.MAX_SPEED_SERVER * PositionHistory.MAX_REWIND

-- Dernier tir relayé par tireur (clé : participant, faible pour qu'un bot retiré ne reste pas en mémoire) et par arme.
export type State = { last: { [any]: { [string]: number } } }

-- Cette méthode permet de créer l'état du relais lorsque le serveur démarre (ou qu'un test commence).
function ShotRelayRules.new(): State
	return { last = setmetatable({}, { __mode = "k" }) :: any }
end

-- Cette méthode permet de décider si un tir est relayé lorsqu'il arrive (arme à distance, forme, origine, cadence) :
-- un tir relayé relance la cadence ; sinon false et la raison, rien n'est retenu.
function ShotRelayRules.admit(
	state: State,
	key: any,
	weaponName: string?,
	origin: any,
	direction: any,
	shooterPos: Vector3?,
	now: number
): (boolean, string?)
	local cfg = weaponName and WeaponConfig.Weapons[weaponName]
	if not cfg or cfg.IsMelee then
		return false, "pas d'arme à distance en main"
	end
	if not ShotRules.isBoundedVector(origin) or not ShotRules.isBoundedVector(direction) then
		return false, "origine ou direction invalide"
	end
	if math.abs(direction.Magnitude - 1) > ShotRules.UNIT_TOLERANCE then
		return false, "direction non unitaire"
	end
	if not shooterPos then
		return false, "tireur sans position"
	end
	local offset = (origin - shooterPos).Magnitude
	if offset > ShotRelayRules.ORIGIN_MAX then
		return false, string.format("origine à %.0f studs du tireur", offset)
	end
	local perWeapon = state.last[key]
	local last = perWeapon and perWeapon[weaponName :: string]
	local delay = cfg.FireDelay or 0
	if last and now - last < delay - ShotRelayRules.CADENCE_TOLERANCE then
		return false, string.format("cadence : %.2f s après le tir précédent", now - last)
	end
	if not perWeapon then
		perWeapon = {}
		state.last[key] = perWeapon
	end
	perWeapon[weaponName :: string] = now
	return true
end

-- Cette méthode permet d'oublier la cadence d'un tireur lorsqu'il réapparaît ou quitte le serveur.
function ShotRelayRules.forget(state: State, key: any)
	state.last[key] = nil
end

-- Cette méthode permet de choisir les clients qui entendent un tir lorsqu'il est relayé : tous sauf le tireur (qui
-- joue déjà son propre son) ; un bot n'a pas de joueur, tout le monde l'entend.
function ShotRelayRules.recipients<T>(players: { T }, shooter: T?): { T }
	local out = {}
	for _, p in players do
		if p ~= shooter then
			table.insert(out, p)
		end
	end
	return out
end

return ShotRelayRules
