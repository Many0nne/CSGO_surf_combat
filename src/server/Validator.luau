local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local HitZones = require(ReplicatedStorage.Shared.HitZones)
local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)
local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)
local PositionHistory = require(ReplicatedStorage.Shared.PositionHistory)
local Participants = require(ServerScriptService.Server.Participants)
local ShotRules = require(ServerScriptService.Server.ShotRules)

type Participant = Participants.Participant

-- Distance maximale (studs) entre les racines du tireur et de la cible : portée du client, plus le chemin qu'une cible
-- peut avoir parcouru pendant le rembobinage, la hauteur de la caméra et une marge (~2 196 studs).
local MAX_HITSCAN_RANGE = WeaponConfig.HITSCAN_RANGE
	+ MovementConfig.MAX_SPEED_SERVER * PositionHistory.MAX_REWIND
	+ CameraConfig.CAM_HEIGHT_STAND
	+ 25
-- Portée entre racines des tirs de bots, inchangée par #174 (ils visent à 240 studs au plus, BotConfig) : leur rayon
-- serveur porte à 2 048 studs et peut toucher un joueur lointain derrière une cible manquée.
local BOT_HITSCAN_RANGE = 250
local MAX_MELEE_RANGE = 10 -- studs
-- Secondes tolérées sur la cadence : latence réseau et écart entre les instants d'impact des attaques
-- (marqueur « Stab Sound » à 0,12-0,16 s selon l'animation ; le serveur ne voit que l'impact, pas le clic).
local CADENCE_TOLERANCE = 0.15

type LastAttack = { at: number, delay: number }

local Validator = {}

Validator.MAX_HITSCAN_RANGE = MAX_HITSCAN_RANGE

-- Accès au monde dont la validation d'un tir de joueur a besoin (#174), branchés par init.server (simulés en test) :
-- horloge serveur, position rembobinée d'un personnage, raycast de ligne de vue sur la map, journal des violations.
export type ShotWorld = {
	serverNow: () -> number,
	positionAt: (char: Model, t: number) -> Vector3?,
	isObstructed: (from: Vector3, delta: Vector3) -> boolean,
	report: (attacker: Participant, check: string, severity: ShotRules.Severity, detail: string) -> (),
}

-- nil tant que setShotWorld n'a pas été appelé : les tirs de joueurs sont alors refusés (jamais validés en silence).
local shotWorld: ShotWorld? = nil
local warnedNoWorld = false

-- Attribut serveur de la cible immobile du helper de playtest ; les attributs posés par un client ne répliquent pas.
Validator.DEBUG_TARGET_ATTRIBUTE = "DebugTarget"

-- Dernière attaque acceptée, par participant et par arme (entrée de WeaponConfig), comme `nextFireTime` côté client.
local lastAttacks: { [Participant]: { [any]: LastAttack } } = {}

local function getRoot(char: Model): BasePart?
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Cette méthode permet de vérifier la cible d'une touche lorsqu'elle arrive : le personnage d'un autre participant
-- (joueur ou bot) ou la cible du helper de playtest, encore en vie.
local function isValidTarget(attacker: Participant, targetCharacter: Instance): boolean
	if typeof(targetCharacter) ~= "Instance" then
		return false
	end

	local target = Participants.fromCharacter(targetCharacter)
	if target then
		if target == attacker then
			return false
		end
	elseif targetCharacter:GetAttribute(Validator.DEBUG_TARGET_ATTRIBUTE) ~= true then
		return false
	end

	local humanoid = targetCharacter:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
	return humanoid ~= nil and humanoid.Health > 0
end

-- Cette méthode permet de vérifier ce qui est commun à toutes les attaques (cible, arme réellement en main, portée)
-- lorsqu'une touche arrive ; elle renvoie la config de l'arme, les deux roots et le personnage du tireur, ou nil si la
-- touche est invalide.
local function resolveAttack(
	attacker: Participant,
	targetCharacter: Instance,
	maxRange: number
): (any, BasePart?, BasePart?, Model?)
	if not isValidTarget(attacker, targetCharacter) then
		return nil
	end
	local aChar = Participants.characterOf(attacker)
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
	return cfg, aRoot, tRoot, aChar
end

-- Cette méthode permet de vérifier que la partie annoncée par le client appartient à la cible lorsqu'un tir arrive.
local function isPartOfTarget(hitPart: any, targetCharacter: Instance): boolean
	return typeof(hitPart) == "Instance" and hitPart:IsA("BasePart") and hitPart:IsDescendantOf(targetCharacter)
end

-- Cette méthode permet de savoir si l'arme a fini sa cadence lorsqu'une touche arrive, à la tolérance près.
local function isCadenceReady(attacker: Participant, cfg: any, now: number): boolean
	local playerAttacks = lastAttacks[attacker]
	local last = playerAttacks and playerAttacks[cfg]
	return last == nil or now - last.at >= last.delay - CADENCE_TOLERANCE
end

-- Cette méthode permet de démarrer la cadence de l'arme lorsqu'une attaque vient d'être acceptée.
local function recordAttack(attacker: Participant, cfg: any, delay: number, now: number)
	local playerAttacks = lastAttacks[attacker]
	if not playerAttacks then
		playerAttacks = {}
		lastAttacks[attacker] = playerAttacks
	end
	playerAttacks[cfg] = { at = now, delay = delay }
end

-- Cette méthode permet de brancher les accès au monde de la validation des tirs lorsque le serveur démarre (ou qu'un
-- test la simule).
function Validator.setShotWorld(world: ShotWorld)
	shotWorld = world
end

-- Cette méthode permet d'estimer la vitesse d'un personnage autour de l'instant t lorsqu'on règle une tolérance : une
-- fenêtre de SPEED_WINDOW autour de t, ramenée dans la borne de rembobinage, divisée par sa vraie durée.
local function speedAround(world: ShotWorld, char: Model, t: number, now: number): number
	local from, to = ShotRules.speedWindow(t, now)
	if not from or not to then
		return 0
	end
	return ShotRules.speedBetween(world.positionAt(char, from), world.positionAt(char, to), to - from)
end

-- Cette méthode permet de vérifier un tir de joueur lorsqu'il a passé cible, arme et cadence : forme, origine, visée
-- sur la partie rembobinée, portée, ligne de vue (#174). Chaque échec est journalisé ; il ne refuse le tir que si son
-- contrôle est en mode "block" (ShotRules.MODES). Renvoie true si le tir peut être appliqué.
local function validateShot(
	attacker: Participant,
	aChar: Model,
	aRoot: BasePart,
	tRoot: BasePart,
	targetCharacter: Model,
	hitPart: BasePart,
	shot: any
): boolean
	local world = shotWorld
	if not world then
		if not warnedNoWorld then
			warnedNoWorld = true
			warn("[Validator] setShotWorld non appelé : tirs de joueurs refusés")
		end
		return false
	end
	local blocked = false
	local rootDistance = (aRoot.Position - tRoot.Position).Magnitude
	-- Cette méthode permet de journaliser un contrôle en échec lorsqu'il est constaté, et de retenir s'il refuse le tir
	-- (mode "block", ou tir lointain pour un contrôle couvert par LOG_ONLY_RANGE).
	local function fail(check: string, detail: string)
		local refuses = ShotRules.refuses(check, rootDistance)
		blocked = blocked or refuses
		local suffix = if ShotRules.blocks(check)
			then ""
			elseif refuses then string.format(" (refusé : au-delà de %d studs)", ShotRules.LOG_ONLY_RANGE)
			else " (journal seul)"
		world.report(attacker, check, ShotRules.SEVERITY[check], string.format("%s : %s%s", check, detail, suffix))
	end

	local wellFormed, reason = ShotRules.isWellFormed(shot)
	if not wellFormed then
		-- Sans forme valide, aucun autre contrôle n'a de sens
		fail(ShotRules.Check.SHAPE, reason or "?")
		return not blocked
	end
	local now = world.serverNow()

	-- Origine : près de la position du tireur au moment du tir, ou de sa position actuelle
	local shooterT = ShotRules.shooterTime(shot.shotTime, now)
	local shooterPositions = { aRoot.Position }
	local past = world.positionAt(aChar, shooterT)
	if past then
		table.insert(shooterPositions, past)
	end
	local shooterSpeed = math.max(speedAround(world, aChar, shooterT, now), speedAround(world, aChar, now, now))
	local ok, detail = ShotRules.checkOrigin(shot.origin, shooterPositions, shooterSpeed)
	if not ok then
		fail(ShotRules.Check.ORIGIN, detail or "?")
	end

	-- Visée : partie annoncée replacée là où le tireur voyait la cible (décalage pris sur le rig serveur)
	local rewindT = ShotRules.rewindTime(shot.shotTime, now)
	local rewoundRoot = world.positionAt(targetCharacter, rewindT) or tRoot.Position
	local partCenter = rewoundRoot + (hitPart.Position - tRoot.Position)
	local targetSpeed = speedAround(world, targetCharacter, rewindT, now)
	local partLimit = ShotRules.directionLimit(hitPart.Size.Magnitude / 2, targetSpeed)
	ok, detail = ShotRules.checkDirection(shot, partCenter, partLimit)
	if not ok then
		-- Contexte pour régler les tolérances pendant la phase de mesure (docs/anticheat.md, « T1 »)
		fail(
			ShotRules.Check.DIRECTION,
			string.format(
				"%s ; %s, cible à %.0f studs/s, rembobinée de %.2f s (%.1f studs)",
				detail or "?",
				hitPart.Name,
				targetSpeed,
				now - rewindT,
				(tRoot.Position - rewoundRoot).Magnitude
			)
		)
	end

	ok, detail = ShotRules.checkDistance(shot)
	if not ok then
		fail(ShotRules.Check.DISTANCE, detail or "?")
	end

	-- Ligne de vue jusqu'à l'impact annoncé s'il est sur la partie, sinon jusqu'à la partie rembobinée : un impact
	-- forgé près de l'origine ne doit pas raccourcir le segment testé
	local losEnd = if (shot.hitPos - partCenter).Magnitude <= partLimit then shot.hitPos else partCenter
	local from, delta = ShotRules.lineOfSightSegment(shot.origin, losEnd)
	if from and delta and world.isObstructed(from, delta) then
		fail(ShotRules.Check.LINE_OF_SIGHT, string.format("obstacle de la map sur %.0f studs de tir", delta.Magnitude))
	end
	return not blocked
end

-- Cette méthode permet de décider un tir d'arme à distance lorsque le remote arrive : elle renvoie les dégâts de l'arme
-- réellement en main selon la zone touchée et si c'est un tir à la tête, et démarre sa cadence ; nil si le tir est refusé.
-- shot (origine, direction, impact, instant) est exigé d'un joueur et vérifié (#174) ; un bot tire depuis le serveur,
-- par un vrai raycast : son tir garde le chemin sans shot.
function Validator.authorizeHitscan(
	attacker: Participant,
	targetCharacter: Instance,
	hitPart: Instance,
	now: number,
	shot: any?
): (number?, boolean)
	local maxRange = if attacker.isBot then BOT_HITSCAN_RANGE else MAX_HITSCAN_RANGE
	local cfg, aRoot, tRoot, aChar = resolveAttack(attacker, targetCharacter, maxRange)
	if
		not cfg
		or cfg.IsMelee
		or not aRoot
		or not tRoot
		or not aChar
		or not isPartOfTarget(hitPart, targetCharacter)
	then
		return nil, false
	end
	if not isCadenceReady(attacker, cfg, now) then
		return nil, false
	end
	if
		not attacker.isBot
		and not validateShot(attacker, aChar, aRoot, tRoot, targetCharacter :: Model, hitPart :: BasePart, shot)
	then
		-- Refusé : la cadence n'est pas relancée, comme pour toute touche refusée
		return nil, false
	end
	recordAttack(attacker, cfg, cfg.FireDelay, now)

	-- Seul un enfant direct est une partie du corps : un accessoire ou l'arme 3P peut contenir une pièce nommée "Head".
	local zone = if hitPart.Parent == targetCharacter then HitZones.zoneOf(hitPart.Name) else nil
	return HitZones.damageFor(cfg.Damage, zone), zone == HitZones.Zone.HEAD
end

-- Cette méthode permet de décider un coup de mêlée lorsque le remote arrive : elle renvoie les dégâts calculés depuis
-- WeaponConfig (backstab recalculé d'après les positions serveur) et démarre la cadence, ou nil si le coup est refusé.
function Validator.authorizeMelee(
	attacker: Participant,
	targetCharacter: Instance,
	attackKind: string,
	now: number
): number?
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

-- Cette méthode permet d'oublier les cadences d'un participant lorsqu'il réapparaît (armes neuves, comme côté client)
-- ou s'en va.
function Validator.forget(participant: Participant)
	lastAttacks[participant] = nil
end

-- Cette méthode permet de qualifier le résultat de dégâts appliqués lorsque le tireur doit en être informé :
-- nil si les PV n'ont pas baissé (ForceField de spawn, par exemple), sinon "hit", ou "kill" si la cible n'a plus de PV.
function Validator.hitOutcome(healthBefore: number, healthAfter: number): ("hit" | "kill")?
	if healthAfter >= healthBefore then
		return nil
	end
	return if healthAfter <= 0 then "kill" else "hit"
end

return Validator
