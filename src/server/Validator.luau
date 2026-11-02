local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local HitZones = require(ReplicatedStorage.Shared.HitZones)

local MAX_HITSCAN_RANGE = 250 -- studs
local MAX_MELEE_RANGE = 10 -- studs
-- Secondes tolérées sur la cadence : latence réseau et écart entre les instants d'impact des attaques
-- (marqueur « Stab Sound » à 0,12-0,16 s selon l'animation ; le serveur ne voit que l'impact, pas le clic).
local CADENCE_TOLERANCE = 0.15

type LastAttack = { at: number, delay: number }

local Validator = {}

-- Attribut serveur de la cible immobile du helper de playtest ; les attributs posés par un client ne répliquent pas.
Validator.DEBUG_TARGET_ATTRIBUTE = "DebugTarget"

-- Dernière attaque acceptée, par joueur et par arme (entrée de WeaponConfig), comme `nextFireTime` côté client.
local lastAttacks: { [Player]: { [any]: LastAttack } } = {}

local function getRoot(char: Model): BasePart?
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Valid targets are real players (other than the attacker) or the playtest helper's target.
local function isValidTarget(attacker: Player, targetCharacter: Instance): boolean
	if typeof(targetCharacter) ~= "Instance" then
		return false
	end

	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	if targetPlayer then
		if targetPlayer == attacker then
			return false
		end
	elseif targetCharacter:GetAttribute(Validator.DEBUG_TARGET_ATTRIBUTE) ~= true then
		return false
	end

	local humanoid = targetCharacter:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
	return humanoid ~= nil and humanoid.Health > 0
end

-- Cette méthode permet de vérifier ce qui est commun à toutes les attaques (cible, arme réellement en main, portée)
-- lorsqu'une touche arrive ; elle renvoie la config de l'arme et les deux roots, ou nil si la touche est invalide.
local function resolveAttack(attacker: Player, targetCharacter: Instance, maxRange: number): (any, BasePart?, BasePart?)
	if not isValidTarget(attacker, targetCharacter) then
		return nil
	end
	local aChar = attacker.Character
	local tool = aChar and aChar:FindFirstChildOfClass("Tool")
	local cfg = tool and WeaponConfig.Weapons[tool:GetAttribute("WeaponName") or tool.Name]
	if not cfg then
		return nil
	end
	local aRoot = getRoot(aChar :: Model)
	local tRoot = getRoot(targetCharacter :: Model)
	if not aRoot or not tRoot or (aRoot.Position - tRoot.Position).Magnitude > maxRange then
		return nil
	end
	return cfg, aRoot, tRoot
end

-- Cette méthode permet de vérifier que la partie annoncée par le client appartient à la cible lorsqu'un tir arrive.
local function isPartOfTarget(hitPart: any, targetCharacter: Instance): boolean
	return typeof(hitPart) == "Instance" and hitPart:IsA("BasePart") and hitPart:IsDescendantOf(targetCharacter)
end

-- Cette méthode permet de savoir si l'arme a fini sa cadence lorsqu'une touche arrive, à la tolérance près.
local function isCadenceReady(attacker: Player, cfg: any, now: number): boolean
	local playerAttacks = lastAttacks[attacker]
	local last = playerAttacks and playerAttacks[cfg]
	return last == nil or now - last.at >= last.delay - CADENCE_TOLERANCE
end

-- Cette méthode permet de démarrer la cadence de l'arme lorsqu'une attaque vient d'être acceptée.
local function recordAttack(attacker: Player, cfg: any, delay: number, now: number)
	local playerAttacks = lastAttacks[attacker]
	if not playerAttacks then
		playerAttacks = {}
		lastAttacks[attacker] = playerAttacks
	end
	playerAttacks[cfg] = { at = now, delay = delay }
end

-- Cette méthode permet de décider un tir d'arme à distance lorsque le remote arrive : elle renvoie les dégâts de l'arme
-- réellement en main selon la zone touchée et si c'est un tir à la tête, et démarre sa cadence ; nil si le tir est refusé.
function Validator.authorizeHitscan(
	attacker: Player,
	targetCharacter: Instance,
	hitPart: Instance,
	now: number
): (number?, boolean)
	local cfg = resolveAttack(attacker, targetCharacter, MAX_HITSCAN_RANGE)
	if not cfg or cfg.IsMelee or not isPartOfTarget(hitPart, targetCharacter) then
		return nil, false
	end
	if not isCadenceReady(attacker, cfg, now) then
		return nil, false
	end
	recordAttack(attacker, cfg, cfg.FireDelay, now)

	-- Seul un enfant direct est une partie du corps : un accessoire ou l'arme 3P peut contenir une pièce nommée "Head".
	local zone = if hitPart.Parent == targetCharacter then HitZones.zoneOf(hitPart.Name) else nil
	return HitZones.damageFor(cfg.Damage, zone), zone == HitZones.Zone.HEAD
end

-- Cette méthode permet de décider un coup de mêlée lorsque le remote arrive : elle renvoie les dégâts calculés depuis
-- WeaponConfig (backstab recalculé d'après les positions serveur) et démarre la cadence, ou nil si le coup est refusé.
function Validator.authorizeMelee(attacker: Player, targetCharacter: Instance, attackKind: string, now: number): number?
	local cfg, aRoot, tRoot = resolveAttack(attacker, targetCharacter, MAX_MELEE_RANGE)
	if not cfg or not aRoot or not tRoot then
		return nil
	end
	local damage, fireDelay = WeaponConfig.getMeleeAttack(cfg, attackKind)
	if not damage or not fireDelay or not isCadenceReady(attacker, cfg, now) then
		return nil
	end
	recordAttack(attacker, cfg, fireDelay, now)

	local isBackstab = (aRoot.Position - tRoot.Position):Dot(tRoot.CFrame.LookVector) < 0
	return if isBackstab then damage * cfg.BackstabMultiplier else damage
end

-- Cette méthode permet d'oublier les cadences d'un joueur lorsqu'il réapparaît (armes neuves, comme côté client) ou s'en va.
function Validator.forgetPlayer(player: Player)
	lastAttacks[player] = nil
end

-- Cette méthode permet de qualifier le résultat de dégâts appliqués lorsque le tireur doit en être informé :
-- nil si les PV n'ont pas baissé (ForceField de spawn, par exemple), sinon "hit", ou "kill" si la cible n'a plus de PV.
function Validator.hitOutcome(healthBefore: number, healthAfter: number): ("hit" | "kill")?
	if healthAfter >= healthBefore then
		return nil
	end
	return if healthAfter <= 0 then "kill" else "hit"
end

-- Position plausibility (for future use with position-based anti-cheat)
function Validator.isPositionPlausible(player: Player, claimedPos: Vector3): boolean
	local char = player.Character
	if not char then
		return false
	end
	local root = getRoot(char)
	if not root then
		return false
	end
	return (root.Position - claimedPos).Magnitude <= MovementConfig.MAX_DELTA_POS * 5
end

return Validator
