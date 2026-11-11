local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local HitZones = require(ReplicatedStorage.Shared.HitZones)
local MovementConfig = require(ReplicatedStorage.Shared.MovementConfig)
local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)
local CharacterSyncRules = require(ReplicatedStorage.Shared.CharacterSyncRules)
local MathRules = require(ReplicatedStorage.Shared.MathRules)
local PositionHistory = require(ReplicatedStorage.Shared.PositionHistory)
local Participants = require(ServerScriptService.Server.Participants)
local CheatTypes = require(ServerScriptService.Server.CheatTypes)
local ShotRules = require(ServerScriptService.Server.ShotRules)
local ShotLinkRules = require(ServerScriptService.Server.ShotLinkRules)

type Participant = Participants.Participant

-- Distance maximale (studs) entre les racines du tireur et de la cible : portée du client, plus le chemin qu'une cible
-- peut avoir parcouru pendant le rembobinage, la hauteur de la caméra et une marge (~2 256 studs).
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
local CADENCE_TOLERANCE = ShotRules.CADENCE_TOLERANCE

type LastAttack = { at: number, delay: number }

local Validator = {}

Validator.MAX_HITSCAN_RANGE = MAX_HITSCAN_RANGE

-- Accès au monde dont la validation d'un tir de joueur a besoin (#174), branchés par init.server (simulés en test) :
-- horloge serveur, position rembobinée d'un personnage, raycast de ligne de vue sur la map, journal des violations
-- (category : CheatTypes.Category, Hitscan si absente ; l'equip vaut aussi pour la mêlée, #175 ; orientation et
-- ligne de vue de la mêlée, #176). positionAt rend aussi la pose (#213) : cap (rad) et accroupi, nil si inconnus.
-- pingOf (#214) : aller-retour réseau du tireur (s), nil si inconnu ou absent (instant annoncé alors non borné).
export type ShotWorld = {
	serverNow: () -> number,
	positionAt: (char: Model, t: number) -> (Vector3?, number?, boolean?),
	isObstructed: (from: Vector3, delta: Vector3) -> boolean,
	pingOf: ((attacker: Participant) -> number?)?,
	report: (
		attacker: Participant,
		check: string,
		severity: ShotRules.Severity,
		detail: string,
		category: string?
	) -> (),
}

-- nil tant que setShotWorld n'a pas été appelé : les tirs et coups de mêlée de joueurs sont alors refusés (jamais
-- validés en silence).
local shotWorld: ShotWorld? = nil
local warnedNoWorld = false
local warnedNoWorldWeapon = false
local warnedNoWorldMelee = false

-- Attribut serveur de la cible immobile du helper de playtest ; les attributs posés par un client ne répliquent pas.
Validator.DEBUG_TARGET_ATTRIBUTE = "DebugTarget"

-- Dernière attaque acceptée, par participant et par arme (entrée de WeaponConfig), comme `nextFireTime` côté client.
local lastAttacks: { [Participant]: { [any]: LastAttack } } = {}
-- Dernier outil arrivé dans le personnage d'un participant et instant de son arrivée (#175), même horloge que `now`.
local equips: { [Participant]: { tool: Instance, at: number } } = {}
-- Chargeur de chaque arme à distance d'un participant (#175), par entrée de WeaponConfig comme les cadences.
local magazines: { [Participant]: { [any]: ShotRules.Magazine } } = {}
-- Tirs récents de chaque arme à distance d'un participant (#215, #216) : ShotFired acceptés et touches orphelines, pour
-- rattacher chaque touche à son tir par shotTime (ShotLinkRules). Joueurs seulement.
local shotLedgers: { [Participant]: { [any]: ShotLinkRules.Ledger } } = {}

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

-- Cette méthode permet de lire l'outil en main d'un participant et sa fiche WeaponConfig (attribut WeaponName, sinon
-- nom de l'outil) lorsqu'il attaque ou recharge ; nil sans outil ou sans fiche.
local function weaponInHand(participant: Participant): (Tool?, any)
	local char = Participants.characterOf(participant)
	local tool = char and char:FindFirstChildOfClass("Tool")
	if not tool then
		return nil, nil
	end
	return tool, WeaponConfig.Weapons[tool:GetAttribute("WeaponName") or tool.Name]
end

-- Cette méthode permet de vérifier ce qui est commun à toutes les attaques (cible, arme réellement en main, portée)
-- lorsqu'une touche arrive ; elle renvoie la config de l'arme, les deux roots, le personnage du tireur et l'outil en
-- main, ou nil si la touche est invalide.
local function resolveAttack(
	attacker: Participant,
	targetCharacter: Instance,
	maxRange: number
): (any, BasePart?, BasePart?, Model?, Tool?)
	if not isValidTarget(attacker, targetCharacter) then
		return nil
	end
	local aChar = Participants.characterOf(attacker)
	local tool, cfg = weaponInHand(attacker)
	if not cfg then
		return nil
	end
	local aRoot = getRoot(aChar :: Model)
	local tRoot = getRoot(targetCharacter :: Model)
	if not aRoot or not tRoot or (aRoot.Position - tRoot.Position).Magnitude > maxRange then
		return nil
	end
	return cfg, aRoot, tRoot, aChar, tool
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

-- Cette méthode permet de lire le chargeur d'une arme d'un participant lorsqu'il tire ou recharge ; il est créé plein.
local function magazineOf(participant: Participant, cfg: any): ShotRules.Magazine
	local perWeapon = magazines[participant]
	if not perWeapon then
		perWeapon = {}
		magazines[participant] = perWeapon
	end
	local mag = perWeapon[cfg]
	if not mag then
		mag = ShotRules.newMagazine()
		perWeapon[cfg] = mag
	end
	return mag
end

-- Cette méthode permet de lire le registre des tirs d'une arme d'un participant lorsqu'un ShotFired ou une touche
-- arrive ; il est créé vide.
local function ledgerOf(participant: Participant, cfg: any): ShotLinkRules.Ledger
	local perWeapon = shotLedgers[participant]
	if not perWeapon then
		perWeapon = {}
		shotLedgers[participant] = perWeapon
	end
	local ledger = perWeapon[cfg]
	if not ledger then
		ledger = ShotLinkRules.new()
		perWeapon[cfg] = ledger
	end
	return ledger
end

-- Cette méthode permet d'annuler les rechargements en cours d'un participant lorsqu'il range ou change d'arme (un
-- rechargement déjà fini reste acquis).
local function cancelReloads(participant: Participant, now: number)
	local perWeapon = magazines[participant]
	if not perWeapon then
		return
	end
	for cfg, mag in perWeapon do
		ShotRules.cancelReload(mag, cfg.ReloadTime or 0, now)
	end
end

-- Cette méthode permet de journaliser un contrôle en échec lorsqu'il est constaté (tir ou mêlée) : « contrôle : détail »,
-- suffixé « (journal seul) » en mode "log", ou de la raison du refus (LOG_ONLY_RANGE).
local function reportCheck(
	world: ShotWorld,
	attacker: Participant,
	check: string,
	detail: string,
	refuses: boolean,
	category: string?
)
	local suffix = if ShotRules.blocks(check)
		then ""
		elseif refuses then string.format(" (refusé : au-delà de %d studs)", ShotRules.LOG_ONLY_RANGE)
		else " (journal seul)"
	world.report(
		attacker,
		check,
		ShotRules.SEVERITY[check],
		string.format("%s : %s%s", check, detail, suffix),
		category
	)
end

-- Cette méthode permet de journaliser un contrôle d'equip ou de chargeur en échec lorsqu'il est constaté ; elle
-- renvoie true s'il refuse la touche (mode "block"). Sans monde branché, la décision s'applique sans journal.
local function failWeaponCheck(attacker: Participant, category: string, check: string, detail: string): boolean
	local blocks = ShotRules.blocks(check)
	local world = shotWorld
	if world then
		reportCheck(world, attacker, check, detail, blocks, category)
	elseif not warnedNoWorldWeapon then
		-- Comme validateShot : un refus de mêlée sans journal ne doit pas passer inaperçu
		warnedNoWorldWeapon = true
		warn("[Validator] setShotWorld non appelé : refus d'equip et de chargeur non journalisés")
	end
	return blocks
end

-- Cette méthode permet de vérifier qu'un joueur pouvait utiliser son arme lorsqu'une touche a passé cible, arme et
-- cadence (#175) : equip fini, et pour une arme à chargeur, chargeur non vide, sauf touche rattachée à un tir déjà
-- compté (linked, #215). Renvoie false si la touche est refusée.
local function isWeaponReady(
	attacker: Participant,
	category: string,
	tool: Instance,
	cfg: any,
	now: number,
	linked: boolean?
): boolean
	local blocked = false
	local record = equips[attacker]
	local equippedAt = if record and record.tool == tool then record.at else nil
	local ok, detail = ShotRules.checkEquip(equippedAt, cfg.EquipTime or 0, now)
	if not ok then
		blocked = failWeaponCheck(attacker, category, ShotRules.Check.EQUIP, detail or "?") or blocked
	end
	if not cfg.IsMelee and cfg.Magazine and not linked then
		ok, detail = ShotRules.checkMagazine(magazineOf(attacker, cfg), cfg.Magazine, cfg.ReloadTime or 0, now)
		if not ok then
			blocked = failWeaponCheck(attacker, category, ShotRules.Check.MAGAZINE, detail or "?") or blocked
		end
	end
	return not blocked
end

-- Cette méthode permet de savoir si l'arme à distance en main peut tirer lorsqu'un tir doit être relayé (#156) : equip
-- et chargeur (#175) selon leur mode, sans journal ni compte ; toujours vrai pour un bot armé (BotArsenal), et pour un
-- ShotFired dont la touche est arrivée avant lui (shotTime, #215 : tir déjà compté par cette touche).
function Validator.isReadyToFire(participant: Participant, now: number, shotTime: number?): boolean
	local tool, cfg = weaponInHand(participant)
	if not tool or not cfg or cfg.IsMelee then
		return false
	end
	if participant.isBot then
		return true
	end
	-- Sans créer de registre pour un tir qui sera peut-être refusé (find purge seulement les tirs trop anciens)
	local perWeapon = shotLedgers[participant]
	local ledger = perWeapon and perWeapon[cfg]
	if ledger and ShotLinkRules.find(ledger, shotTime, now, "fired") then
		return true
	end
	local record = equips[participant]
	local equippedAt = if record and record.tool == tool then record.at else nil
	-- Mêmes refus qu'une touche (isWeaponReady) : un contrôle en mode "log" ne rend pas muet un tir accepté
	if not ShotRules.checkEquip(equippedAt, cfg.EquipTime or 0, now) and ShotRules.blocks(ShotRules.Check.EQUIP) then
		return false
	end
	if cfg.Magazine then
		local ok = ShotRules.checkMagazine(magazineOf(participant, cfg), cfg.Magazine, cfg.ReloadTime or 0, now)
		if not ok and ShotRules.blocks(ShotRules.Check.MAGAZINE) then
			return false
		end
	end
	return true
end

-- Cette méthode permet de compter un tir dans le chargeur de l'arme en main lorsque son ShotFired est accepté par le
-- relais (#215) et de l'inscrire au registre pour sa touche (#216) ; un tir déjà compté par sa touche arrivée avant
-- lui y est seulement rattaché. Rien pour un bot (BotArsenal tient son chargeur).
function Validator.noteShotFired(participant: Participant, shotTime: number, now: number)
	local _, cfg = weaponInHand(participant)
	if participant.isBot or not cfg or cfg.IsMelee then
		return
	end
	local ledger = ledgerOf(participant, cfg)
	local early = ShotLinkRules.find(ledger, shotTime, now, "fired")
	if early then
		early.fired = true
		return
	end
	if cfg.Magazine then
		ShotRules.countShot(magazineOf(participant, cfg), now)
	end
	ShotLinkRules.record(ledger, shotTime, now, true, false)
end

-- Cette méthode permet de noter l'arrivée d'un outil dans le personnage d'un participant lorsque le serveur la voit
-- (equip, #175) : début de sa durée d'equip ; un rechargement en cours est annulé, comme côté client.
function Validator.noteEquip(participant: Participant, tool: Instance, now: number)
	cancelReloads(participant, now)
	equips[participant] = { tool = tool, at = now }
end

-- Cette méthode permet de noter qu'un outil quitte le personnage d'un participant lorsqu'il range son arme :
-- rechargement annulé ; l'equip suivant repartira de son arrivée.
function Validator.noteUnequip(participant: Participant, tool: Instance, now: number)
	cancelReloads(participant, now)
	local record = equips[participant]
	if record and record.tool == tool then
		equips[participant] = nil
	end
end

-- Cette méthode permet de démarrer le rechargement de l'arme en main lorsque l'action Reload arrive (#175), au plus tôt
-- à la fin de l'equip et de la cadence du dernier tir (le client ne peut pas recharger avant).
function Validator.noteReload(participant: Participant, now: number)
	local tool, cfg = weaponInHand(participant)
	if not cfg or cfg.IsMelee or not cfg.Magazine then
		return
	end
	local record = equips[participant]
	local start = now
	if record and record.tool == tool then
		start = math.max(start, record.at + (cfg.EquipTime or 0) - ShotRules.EQUIP_TOLERANCE)
	end
	local playerAttacks = lastAttacks[participant]
	local last = playerAttacks and playerAttacks[cfg]
	if last then
		start = math.max(start, last.at + last.delay - ShotRules.RELOAD_TOLERANCE)
	end
	local mag = magazineOf(participant, cfg)
	-- Dernier tir compté, touché ou manqué (#215) : sa cadence aussi précède le rechargement
	if mag.lastShotAt then
		start = math.max(start, mag.lastShotAt + (cfg.FireDelay or 0) - ShotRules.RELOAD_TOLERANCE)
	end
	ShotRules.startReload(mag, cfg.ReloadTime or 0, start)
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

-- Cette méthode permet de vérifier l'instant annoncé par un joueur (shotTime, hitTime) lorsqu'un tir ou un coup arrive
-- (#214) : borné par son ping (pingOf du monde) ; sans ping connu, accepté.
local function checkAnnouncedTime(world: ShotWorld, attacker: Participant, t: number, now: number): (boolean, string?)
	local pingOf = world.pingOf
	return ShotRules.checkShotDelay(t, now, if pingOf then pingOf(attacker) else nil)
end

-- Cette méthode permet de lire la pose rembobinée d'une cible à l'instant t lorsqu'un tir ou un coup est vérifié
-- (#213) : racine, cap et accroupi de son historique ; position actuelle de la racine (pose inconnue) sans historique.
local function rewoundPose(world: ShotWorld, targetCharacter: Model, tRoot: BasePart, t: number): ShotRules.Pose
	local pos, yaw, crouching = world.positionAt(targetCharacter, t)
	if not pos then
		return { pos = tRoot.Position }
	end
	return { pos = pos, yaw = yaw, crouching = crouching }
end

-- Cette méthode permet de replacer une partie de la cible dans sa pose rembobinée lorsqu'un tir ou un coup est vérifié
-- (#213) ; accroupi actuel lu dans l'historique seulement si CROUCH_DROP est non nul.
local function posedCenter(
	world: ShotWorld,
	targetCharacter: Model,
	tRoot: BasePart,
	partPos: Vector3,
	pose: ShotRules.Pose,
	now: number
): Vector3
	local crouchingNow = nil
	if ShotRules.CROUCH_DROP ~= 0 then
		crouchingNow = select(3, world.positionAt(targetCharacter, now))
	end
	return ShotRules.posedPartCenter(tRoot.CFrame, tRoot.Position, partPos, crouchingNow, pose)
end

-- Cette méthode permet de lire le bras d'un membre touché sur le rig serveur lorsqu'un tir le vise (#240) : épaule
-- (position monde) et articulations du côté de la partie ; nil hors des bras R15 ou si le rig est incomplet.
local function limbArm(targetCharacter: Model, hitPart: BasePart): (Vector3?, ShotRules.ArmRig?)
	local side = ShotRules.limbSide(hitPart.Name)
	if not side or hitPart.Parent ~= targetCharacter then
		return nil, nil
	end
	local torso = targetCharacter:FindFirstChild("UpperTorso")
	local upperArm = targetCharacter:FindFirstChild(side .. "UpperArm")
	local lowerArm = targetCharacter:FindFirstChild(side .. "LowerArm")
	local hand = targetCharacter:FindFirstChild(side .. "Hand")
	if
		not (torso and torso:IsA("BasePart"))
		or not (upperArm and upperArm:IsA("BasePart"))
		or not (lowerArm and lowerArm:IsA("BasePart"))
		or not (hand and hand:IsA("BasePart"))
	then
		return nil, nil
	end
	local shoulder = upperArm:FindFirstChild(side .. "Shoulder")
	local elbow = lowerArm:FindFirstChild(side .. "Elbow")
	local wrist = hand:FindFirstChild(side .. "Wrist")
	if
		not (shoulder and shoulder:IsA("Motor6D"))
		or not (elbow and elbow:IsA("Motor6D"))
		or not (wrist and wrist:IsA("Motor6D"))
	then
		return nil, nil
	end
	local waist = torso:FindFirstChild("Waist")
	local arm: ShotRules.ArmRig = {
		shoulderC1 = shoulder.C1.Position,
		elbowC0 = elbow.C0.Position,
		elbowC1 = elbow.C1.Position,
		wristC0 = wrist.C0.Position,
		wristC1 = wrist.C1.Position,
		upperArmSize = upperArm.Size,
		lowerArmSize = lowerArm.Size,
		handSize = hand.Size,
		shoulderC0 = shoulder.C0.Position,
		waistC1 = if waist and waist:IsA("Motor6D") then waist.C1 else nil,
		waistTransform = if waist and waist:IsA("Motor6D") then waist.Transform else nil,
	}
	-- Position et rotation lues à part (sous Lune, Position et CFrame sont posées séparément)
	local shoulderPos = torso.Position + torso.CFrame:VectorToWorldSpace(arm.shoulderC0)
	return shoulderPos, arm
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
		reportCheck(world, attacker, check, detail, refuses)
	end

	local wellFormed, reason = ShotRules.isWellFormed(shot)
	if not wellFormed then
		-- Sans forme valide, aucun autre contrôle n'a de sens
		fail(ShotRules.Check.SHAPE, reason or "?")
		return not blocked
	end
	local now = world.serverNow()

	-- Instant annoncé dans la borne du ping (#214) : sinon le client choisit l'instant de rembobinage (« backtrack »)
	local ok, detail = checkAnnouncedTime(world, attacker, shot.shotTime, now)
	if not ok then
		fail(ShotRules.Check.PING, detail or "?")
	end

	-- Origine : près de la position du tireur au moment du tir, ou de sa position actuelle
	local shooterT = ShotRules.shooterTime(shot.shotTime, now)
	local shooterPositions = { aRoot.Position }
	local past = world.positionAt(aChar, shooterT)
	if past then
		table.insert(shooterPositions, past)
	end
	local shooterSpeed = math.max(speedAround(world, aChar, shooterT, now), speedAround(world, aChar, now, now))
	ok, detail = ShotRules.checkOrigin(shot.origin, shooterPositions, shooterSpeed)
	if not ok then
		fail(ShotRules.Check.ORIGIN, detail or "?")
	end

	-- Visée : partie annoncée replacée là où le tireur voyait la cible, dans sa pose rembobinée (#213 : cap et accroupi ;
	-- décalage pris sur le rig serveur)
	local rewindT = ShotRules.rewindTime(shot.shotTime, now)
	local pose = rewoundPose(world, targetCharacter, tRoot, rewindT)
	local rewoundRoot = pose.pos
	local targetSpeed = speedAround(world, targetCharacter, rewindT, now)
	-- Membre (#240) : la tenue de l'arme n'existe que chez les clients, la partie est jugée dans la sphère d'allonge de
	-- son épaule rembobinée plutôt qu'à sa position serveur
	local shoulderPos, arm = limbArm(targetCharacter, hitPart)
	local partCenter, partLimit
	if shoulderPos and arm then
		partCenter = posedCenter(world, targetCharacter, tRoot, shoulderPos, pose, now)
		partLimit = ShotRules.directionLimit(ShotRules.limbRadius(arm), targetSpeed)
	else
		partCenter = posedCenter(world, targetCharacter, tRoot, hitPart.Position, pose, now)
		partLimit = ShotRules.directionLimit(hitPart.Size.Magnitude / 2, targetSpeed)
	end
	ok, detail = ShotRules.checkDirection(shot, partCenter, partLimit)
	if not ok then
		-- Contexte pour régler les tolérances pendant la phase de mesure (docs/anticheat.md, « T1 »)
		fail(
			ShotRules.Check.DIRECTION,
			string.format(
				"%s ; %s, cible à %.0f studs/s, rembobinée de %.2f s (%.1f studs)",
				detail or "?",
				if arm then hitPart.Name .. " jugé dans l'allonge de l'épaule" else hitPart.Name,
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

-- Hauteur de la caméra au-dessus de la racine, debout et accroupi : départ du segment « œil à tête » de la ligne de vue
-- d'un coup (#176 ; accroupi du tireur lu dans son historique, #213).
local EYE_OFFSET = Vector3.new(0, CameraConfig.CAM_HEIGHT_STAND, 0)
local EYE_OFFSET_CROUCH = Vector3.new(0, CameraConfig.CAM_HEIGHT_CROUCH, 0)
-- Durée (s) pour que la caméra qui s'accroupit (approche exponentielle à CAM_LERP_SPEED, CrouchSystem) arrive à
-- 0,1 stud de CAM_HEIGHT_CROUCH : avant, l'œil est encore plus haut, pris debout (comme avant #213 ; en se relevant,
-- l'œil debout est pris tout de suite, plus haut que la caméra qui remonte : un obstacle en surplomb peut alors
-- couper le segment œil à tête, il reste celui des racines).
local CROUCH_EYE_SETTLE = math.log((CameraConfig.CAM_HEIGHT_STAND - CameraConfig.CAM_HEIGHT_CROUCH) / 0.1)
	/ CameraConfig.CAM_LERP_SPEED

-- Cette méthode permet de savoir si l'œil d'un joueur est à la hauteur accroupie lorsqu'un coup est vérifié (#213) :
-- accroupi sur ses relevés de now - CROUCH_EYE_SETTLE à now (caméra descendue), sinon pris debout.
local function eyeSettledCrouched(world: ShotWorld, aChar: Model, now: number): boolean
	for _, back in { 0, CROUCH_EYE_SETTLE / 2, CROUCH_EYE_SETTLE } do
		local _, _, crouching = world.positionAt(aChar, now - back)
		if crouching ~= true then
			return false
		end
	end
	return true
end
-- Centre de la tête au-dessus de la racine, si le rig serveur de la cible n'a pas de Head (R6 : 1,5 stud).
local DEFAULT_HEAD_OFFSET = Vector3.new(0, 1.5, 0)

-- Cette méthode permet de vérifier un coup de mêlée de joueur lorsqu'il a passé cible, arme et cadence : instant du coup
-- dans la borne du ping (#214), cible rembobinée à cet instant (pose comprise, #213) devant le cap du tireur et sans
-- obstacle de la map (#176). Renvoie true s'il peut s'appliquer.
local function validateMelee(
	attacker: Participant,
	aChar: Model,
	aRoot: BasePart,
	tRoot: BasePart,
	targetCharacter: Model,
	hitTime: number?
): boolean
	local world = shotWorld
	if not world then
		if not warnedNoWorldMelee then
			warnedNoWorldMelee = true
			warn("[Validator] setShotWorld non appelé : coups de mêlée de joueurs refusés")
		end
		return false
	end
	local blocked = false
	-- Cette méthode permet de journaliser un contrôle de mêlée en échec lorsqu'il est constaté, et de retenir s'il
	-- refuse le coup (mode "block").
	local function fail(check: string, detail: string)
		local refuses = ShotRules.blocks(check)
		blocked = blocked or refuses
		reportCheck(world, attacker, check, detail, refuses, CheatTypes.Category.MELEE)
	end

	-- Instant du coup (#214) : notre client l'envoie toujours, et la garde (RemoteGuard) l'exige ; filet si un appel
	-- passe sans elle : rien ne dirait où le tireur voyait la cible
	if hitTime == nil or not MathRules.isFinite(hitTime) then
		fail(ShotRules.Check.SHAPE, "coup sans instant")
		return not blocked
	end
	local now = world.serverNow()
	local ok, detail = checkAnnouncedTime(world, attacker, hitTime, now)
	if not ok then
		fail(ShotRules.Check.PING, detail or "?")
	end

	-- Cible là où le tireur la voyait (hitTime - INTERP_DELAY, borné) ; hors de portée du tireur, position actuelle (déjà
	-- à portée, resolveAttack) : une position lointaine du sillage ne justifie pas un coup sur une cible proche
	local look = aRoot.CFrame.LookVector
	local attackerPos = aRoot.Position
	local rewindT = ShotRules.rewindTime(hitTime, now)
	local pose = rewoundPose(world, targetCharacter, tRoot, rewindT)
	local rewind = now - rewindT
	if (pose.pos - attackerPos).Magnitude > MAX_MELEE_RANGE then
		pose = { pos = tRoot.Position }
		rewind = 0
	end
	local targetPos = pose.pos

	-- Orientation : dernier cap reçu du tireur, ou l'un de ceux reçus juste avant (MELEE_YAW_PACKETS : un paquet parti
	-- après le coup a pu arriver avant lui). Son paquet de position (non fiable, 20 Hz) part au plus 50 ms avant le
	-- coup, ou plus tôt s'il s'est perdu : MELEE_MAX_ANGLE couvre ce retard
	local looks = { look }
	for k = 1, ShotRules.MELEE_YAW_PACKETS do
		local _, yaw = world.positionAt(aChar, now - k * CharacterSyncRules.SEND_INTERVAL)
		if yaw then
			table.insert(looks, CFrame.Angles(0, yaw, 0).LookVector)
		end
	end
	local facing, orientationDetail, closestExcess = false, nil, math.huge
	for _, candidate in looks do
		local inFront, excess, candidateDetail = ShotRules.checkMeleeOrientation(candidate, attackerPos, targetPos)
		if inFront then
			facing = true
			break
		elseif excess < closestExcess then
			orientationDetail, closestExcess = candidateDetail, excess
		end
	end
	if not facing then
		fail(ShotRules.Check.ORIENTATION, string.format("%s, rembobinée de %.2f s", orientationDetail or "?", rewind))
	end

	-- Ligne de vue : racine à racine, ou œil du tireur (accroupi, caméra descendue, ou debout) à tête de la cible dans
	-- sa pose rembobinée
	local eyeOffset = if eyeSettledCrouched(world, aChar, now) then EYE_OFFSET_CROUCH else EYE_OFFSET
	local head = targetCharacter:FindFirstChild("Head")
	local headOffset = if head and head:IsA("BasePart")
		then posedCenter(world, targetCharacter, tRoot, head.Position, pose, now) - targetPos
		else DEFAULT_HEAD_OFFSET
	local segments = ShotRules.meleeSightSegments(attackerPos, targetPos, eyeOffset, headOffset)
	local clear = #segments == 0
	for _, segment in segments do
		if not world.isObstructed(segment.from, segment.delta) then
			clear = true
			break
		end
	end
	if not clear then
		fail(
			ShotRules.Check.MELEE_LINE_OF_SIGHT,
			string.format(
				"obstacle de la map, cible à %.1f studs, rembobinée de %.2f s",
				(targetPos - attackerPos).Magnitude,
				rewind
			)
		)
	end
	return not blocked
end

-- Cette méthode permet de décider un tir d'arme à distance lorsque le remote arrive : elle renvoie les dégâts de l'arme
-- réellement en main selon la zone touchée, si c'est un tir à la tête, et l'instant du tir auquel la touche est
-- rattachée (#216, nil si orpheline), et démarre sa cadence ; nil si le tir est refusé.
-- shot (origine, direction, impact, instant) est exigé d'un joueur et vérifié (#174) ; un bot tire depuis le serveur,
-- par un vrai raycast : son tir garde le chemin sans shot.
function Validator.authorizeHitscan(
	attacker: Participant,
	targetCharacter: Instance,
	hitPart: Instance,
	now: number,
	shot: any?
): (number?, boolean, number?)
	local maxRange = if attacker.isBot then BOT_HITSCAN_RANGE else MAX_HITSCAN_RANGE
	local cfg, aRoot, tRoot, aChar, tool = resolveAttack(attacker, targetCharacter, maxRange)
	if
		not cfg
		or cfg.IsMelee
		or not aRoot
		or not tRoot
		or not aChar
		or not tool
		or not isPartOfTarget(hitPart, targetCharacter)
	then
		return nil, false
	end
	if not isCadenceReady(attacker, cfg, now) then
		return nil, false
	end
	local shotTime = if type(shot) == "table" then shot.shotTime else nil
	local link: ShotLinkRules.Entry? = nil
	if not attacker.isBot then
		-- Tir de cette touche (#216) : un ShotFired accepté du même instant, déjà compté dans le chargeur (#215)
		link = ShotLinkRules.find(ledgerOf(attacker, cfg), shotTime, now, "hit")
		-- Géométrie du tir (#174) d'abord, puis equip et chargeur (#175, joueurs seulement : BotArsenal les fait déjà
		-- respecter à ses bots) : tous sont évalués, pour que la phase de mesure de T1 voie aussi les tirs refusés ici
		local shotOk = validateShot(attacker, aChar, aRoot, tRoot, targetCharacter :: Model, hitPart :: BasePart, shot)
		local weaponOk = isWeaponReady(attacker, CheatTypes.Category.HITSCAN, tool, cfg, now, link ~= nil)
		if not shotOk or not weaponOk then
			-- Refusé : la cadence n'est pas relancée, comme pour toute touche refusée
			return nil, false
		end
		-- Touche orpheline : journalisée seulement si rien d'autre ne la refuse (un chargeur vide explique déjà le
		-- ShotFired écarté) ; mode "log" de shotLink jusqu'à mesure en jeu
		if not link then
			local detail = if type(shotTime) == "number"
				then string.format("touche sans ShotFired accepté du même instant (%.3f)", shotTime)
				else "touche sans instant de tir"
			if failWeaponCheck(attacker, CheatTypes.Category.HITSCAN, ShotRules.Check.SHOT_LINK, detail) then
				return nil, false
			end
		end
	end
	recordAttack(attacker, cfg, cfg.FireDelay, now)
	if link then
		link.hit = true
	elseif not attacker.isBot then
		-- Tir compté par sa touche (#215), inscrit au registre : son ShotFired, s'il arrive après, n'est pas recompté
		if cfg.Magazine then
			ShotRules.countShot(magazineOf(attacker, cfg), now)
		end
		if type(shotTime) == "number" then
			ShotLinkRules.record(ledgerOf(attacker, cfg), shotTime, now, false, true)
		end
	end

	-- Seul un enfant direct est une partie du corps : un accessoire ou l'arme 3P peut contenir une pièce nommée "Head".
	local zone = if hitPart.Parent == targetCharacter then HitZones.zoneOf(hitPart.Name) else nil
	return HitZones.damageFor(cfg.Damage, zone), zone == HitZones.Zone.HEAD, link and link.shotTime
end

-- Cette méthode permet de décider un coup de mêlée lorsque le remote arrive : elle renvoie les dégâts calculés depuis
-- WeaponConfig (backstab recalculé d'après les positions serveur) et démarre la cadence, ou nil si le coup est refusé.
-- Pour un joueur : instant du coup hitTime (horloge serveur, comme shotTime) borné par le ping (#214), orientation et
-- ligne de vue vers la cible rembobinée à cet instant (#176, #213), durée d'equip (#175). Un bot n'envoie pas d'instant.
function Validator.authorizeMelee(
	attacker: Participant,
	targetCharacter: Instance,
	attackKind: string,
	now: number,
	hitTime: number?
): number?
	local cfg, aRoot, tRoot, aChar, tool = resolveAttack(attacker, targetCharacter, MAX_MELEE_RANGE)
	if not cfg or not aRoot or not tRoot or not aChar or not tool then
		return nil
	end
	local damage, fireDelay = WeaponConfig.getMeleeAttack(cfg, attackKind)
	if not damage or not fireDelay or not isCadenceReady(attacker, cfg, now) then
		return nil
	end
	if not attacker.isBot then
		-- Orientation et ligne de vue (#176), puis equip (#175) : joueurs seulement (les bots frappent depuis le serveur,
		-- face à leur cible, BotMotion) ; tous sont évalués, comme pour le tir
		local geometryOk = validateMelee(attacker, aChar, aRoot, tRoot, targetCharacter :: Model, hitTime)
		local weaponOk = isWeaponReady(attacker, CheatTypes.Category.MELEE, tool, cfg, now)
		if not geometryOk or not weaponOk then
			-- Refusé : la cadence n'est pas relancée
			return nil
		end
	end
	recordAttack(attacker, cfg, fireDelay, now)

	local isBackstab = (aRoot.Position - tRoot.Position):Dot(tRoot.CFrame.LookVector) < 0
	return if isBackstab then damage * cfg.BackstabMultiplier else damage
end

-- Cette méthode permet d'oublier les cadences, l'equip, les chargeurs et les tirs récents d'un participant lorsqu'il
-- réapparaît (armes neuves, comme côté client) ou s'en va (joueur parti, bot retiré : sinon l'entrée reste, #218).
function Validator.forget(participant: Participant)
	lastAttacks[participant] = nil
	equips[participant] = nil
	magazines[participant] = nil
	shotLedgers[participant] = nil
end

-- Cette méthode permet de savoir si le Validator retient encore quelque chose d'un participant (cadence, equip ou
-- chargeur) lorsqu'on vérifie qu'un retrait l'a bien oublié (test, sonde de mémoire).
function Validator.hasEntries(participant: Participant): boolean
	return lastAttacks[participant] ~= nil
		or equips[participant] ~= nil
		or magazines[participant] ~= nil
		or shotLedgers[participant] ~= nil
end

-- Cette méthode permet de compter les participants dont le Validator retient encore l'état lorsque la sonde serveur
-- écrit son bilan : ce nombre doit retomber quand les bots sont retirés (fuite, #218).
function Validator.trackedCount(): number
	local seen: { [Participant]: boolean } = {}
	local count = 0
	for _, byParticipant in { lastAttacks, equips, magazines, shotLedgers } :: { { [Participant]: any } } do
		for participant in byParticipant do
			if not seen[participant] then
				seen[participant] = true
				count += 1
			end
		end
	end
	return count
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
