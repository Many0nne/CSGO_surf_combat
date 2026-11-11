local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local BotCombatRules = require(ReplicatedStorage.Shared.BotCombatRules)
local CharacterAppearance = require(ReplicatedStorage.Shared.CharacterAppearance)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MapSelection = require(ReplicatedStorage.Shared.MapSelection)
local SpawnLaunch = require(ReplicatedStorage.Shared.SpawnLaunch)
local CheatLog = require(ServerScriptService.Server.CheatLog)
local Participants = require(ServerScriptService.Server.Participants)
local SpawnRules = require(ServerScriptService.Server.SpawnRules)

local SpawnManager = {}

local mapModel: Instance?
-- Remote RequestSpawn, aussi la voie de la réponse au client (#219, SpawnRules.reply)
local replyRemote: RemoteEvent?
-- Joueurs dont un LoadCharacterAsync est en vol, et heure (os.clock) de leur dernière mort (#171)
local spawning: { [Player]: boolean } = {}
local diedAt: { [Player]: number } = {}
-- Joueurs revenus au menu (#157) : aucune réapparition programmée, aucun personnage en vol gardé, jusqu'à leur demande
local away: { [Player]: boolean } = {}
-- Joueurs revenus du menu pendant une réapparition encore en vol : leur demande est servie à la fin de ce chargement
local rejoin: { [Player]: boolean } = {}
-- Gravité d'un refus de RequestSpawn au journal ; "result" n'y va pas (Play cliqué pendant la bannière de fin).
-- "early" est moyen : notre client n'envoie RequestSpawn que depuis le menu, où un joueur mort en round ne revient pas,
-- ou en DEAD passé RESPAWN_DELAY + RESPAWN_MARGIN (#245), jamais pendant RESPAWN_DELAY.
local REFUSAL_SEVERITY: { [string]: CheatLog.Severity } = {
	spawning = CheatLog.Severity.LOW,
	alive = CheatLog.Severity.LOW,
	early = CheatLog.Severity.MEDIUM,
}

-- Cette méthode permet de trouver la map jouée (GameConfig.ACTIVE_MAP dans Workspace.Maps) lorsqu'un joueur demande à
-- apparaître.
local function getMap(): Instance?
	if mapModel and mapModel.Parent then
		return mapModel
	end
	mapModel = MapSelection.waitForActive(10)
	return mapModel
end

-- Cette méthode permet de tirer un enfant au hasard d'un dossier de la map lorsqu'on choisit un point d'apparition.
local function pickPoint(folderName: string): BasePart?
	local map = getMap()
	local folder = map and map:FindFirstChild(folderName)
	local points = folder and folder:GetChildren() or {}
	if #points == 0 then
		return nil
	end
	return points[math.random(1, #points)] :: BasePart
end

-- Cette méthode permet de rendre le joueur invulnérable pendant le lancement lorsqu'il sort du soleil
-- (ForceField invisible : Humanoid:TakeDamage l'ignore, cf. Validator.hitOutcome).
local function protect(char: Model)
	local field = Instance.new("ForceField")
	field.Visible = false
	field.Parent = char
	Debris:AddItem(field, GameConfig.SPAWN_PROTECTION)
end

-- Cette méthode permet de placer un personnage qui vient d'apparaître (joueur ou bot, #139) : lancé depuis le soleil
-- (#69) si la map a des points Maps.Map.SunLaunch, sinon posé sur un point au sol. Lancement : ForceField de protection,
-- origine puis vitesse posées en attributs (lues par MovementController, ou BotMotion pour un bot) ; renvoie la vitesse
-- du lancement (nil pour une apparition au sol).
function SpawnManager.place(char: Model): Vector3?
	local launch = pickPoint("SunLaunch")
	local ground = if launch then nil else pickPoint("GroundSpawns")
	if not launch and not ground then
		warn("[SpawnManager] aucun point dans Maps.Map.SunLaunch ni Maps.Map.GroundSpawns")
	end
	local root = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	-- Délai de grâce : un bot ne tire pas sur un participant qui vient d'apparaître (#143)
	char:SetAttribute(BotCombatRules.SPAWNED_AT_ATTRIBUTE, os.clock())
	if launch then
		local origin = launch.Position
		local speed = launch:GetAttribute("Speed")
		local velocity = SpawnLaunch.velocity(launch.CFrame.LookVector, if type(speed) == "number" then speed else 0)
		protect(char)
		if root then
			root.CFrame = CFrame.new(origin)
		end
		-- Origine d'abord : le client applique le lancement quand la vitesse arrive (MovementController)
		char:SetAttribute(SpawnLaunch.ORIGIN_ATTRIBUTE, origin)
		char:SetAttribute(SpawnLaunch.VELOCITY_ATTRIBUTE, velocity)
		return velocity
	elseif root then
		root.CFrame = CFrame.new((if ground then ground.Position else Vector3.new(0, 5, 0)) + Vector3.new(0, 5, 0))
	end
	return nil
end

-- Cette méthode permet de répondre au client lorsque sa demande d'apparition est jugée ou que son chargement échoue
-- (#219) : le client ne reste jamais sans nouvelles en SPAWNING.
local function reply(player: Player, answer: SpawnRules.Reply)
	if replyRemote and player.Parent then
		replyRemote:FireClient(player, answer)
	end
end

-- Cette méthode permet de faire apparaître un joueur lorsqu'une demande ou une réapparition programmée est acceptée ;
-- un seul LoadCharacterAsync en vol par joueur : rien si un autre est déjà en cours. Renvoie false si ce chargement
-- a échoué (true si un autre, en vol, servira la demande).
function SpawnManager.spawnPlayer(player: Player): boolean
	if spawning[player] then
		return true
	end
	-- Studio seulement (#245) : attribut Workspace DebugSpawnFail = true, chaque chargement échoue (réapparition
	-- programmée et demandes), pour vérifier que le client ne reste pas bloqué
	if RunService:IsStudio() and workspace:GetAttribute("DebugSpawnFail") == true then
		warn("[SpawnManager] DebugSpawnFail : chargement refusé pour " .. player.Name)
		return false
	end
	spawning[player] = true
	-- Connexion avant LoadCharacter pour ne pas manquer CharacterAdded
	local conn: RBXScriptConnection
	conn = player.CharacterAdded:Connect(function(char)
		conn:Disconnect()
		-- Réapparition partie avant le retour au menu : le joueur n'a plus de personnage dans le round
		if away[player] then
			char:Destroy()
			return
		end
		CharacterAppearance.apply(char)
		SpawnManager.place(char)
	end)
	-- Rig = StarterCharacter, skin appliqué dans CharacterAdded (#1).
	local ok, err = pcall(player.LoadCharacterAsync, player)
	spawning[player] = nil
	if not ok then
		conn:Disconnect()
		warn("[SpawnManager] LoadCharacterAsync a échoué pour " .. player.Name .. " :", err)
	end
	-- Demande arrivée pendant ce chargement (#157, #219) : le personnage gardé la sert, sinon un nouveau ; un échec est
	-- répondu ici, la demande compte alors comme traitée (true : pas de seconde réponse « failed »)
	if rejoin[player] then
		rejoin[player] = nil
		if not SpawnRules.isAlive(player.Character) and not SpawnManager.spawnPlayer(player) then
			reply(player, { status = "failed" })
		end
		return true
	end
	return ok
end

-- Cette méthode permet de faire réapparaître un joueur lorsque sa réapparition programmée échoit (RoundManager) :
-- rien s'il a déjà un personnage vivant (demande arrivée entre-temps) ou un LoadCharacterAsync en vol.
function SpawnManager.respawn(player: Player)
	if away[player] then
		return
	end
	if SpawnRules.scheduled(spawning[player] == true, SpawnRules.isAlive(player.Character)) then
		SpawnManager.spawnPlayer(player)
	end
end

-- Cette méthode permet de retenir l'heure de la mort d'un joueur lorsque son Humanoid meurt : une demande
-- d'apparition est refusée pendant RESPAWN_DELAY dans un round actif.
function SpawnManager.noteDeath(player: Player)
	-- Joueur déjà parti (forget passé) ou revenu au menu : rien à retenir
	if player.Parent and not away[player] then
		diedAt[player] = os.clock()
	end
end

-- Cette méthode permet d'oublier un joueur lorsqu'il quitte le jeu.
function SpawnManager.forget(player: Player)
	spawning[player] = nil
	diedAt[player] = nil
	away[player] = nil
	rejoin[player] = nil
end

-- Cette méthode permet de sortir du round un joueur revenu au menu (#157, après RoundManager.withdraw) : personnage
-- détruit, plus de réapparition, prochaine demande acceptée sans RESPAWN_DELAY (son score de la manche est perdu).
function SpawnManager.withdraw(player: Player)
	away[player] = true
	rejoin[player] = nil
	local char = player.Character
	if char then
		char:Destroy()
	end
	-- Après la destruction : une mort que Roblox annoncerait en détruisant le personnage n'est pas retenue
	diedAt[player] = nil
end

-- Cette méthode permet de brancher RequestSpawn lorsque le serveur démarre : garde commune, règles de réapparition
-- (SpawnRules.request, refus au journal), réponse au client (#219), puis beforeSpawn (démarrage du round) et apparition.
-- Une demande écartée par la garde commune (débit) reste sans réponse : le client la renvoie après un délai.
function SpawnManager.init(
	requestSpawnRemote: RemoteEvent,
	hooks: { roundState: () -> string, beforeSpawn: (Player) -> () }
)
	replyRemote = requestSpawnRemote
	requestSpawnRemote.OnServerEvent:Connect(function(player)
		-- Garde commune (#170) : débit
		if not CheatLog.admit(player, requestSpawnRemote.Name) then
			return
		end
		local now = os.clock()
		local request: SpawnRules.Request = {
			spawning = spawning[player] == true,
			hasCharacter = SpawnRules.inPlace(player.Character),
			roundState = hooks.roundState(),
			diedAt = diedAt[player],
			now = now,
			respawnDelay = GameConfig.RESPAWN_DELAY,
		}
		local refusal = SpawnRules.request(request)
		-- Retour du menu pendant une réapparition partie avant le départ : servie à la fin de son chargement (#157)
		if SpawnRules.rejoinsInFlight(refusal, away[player] == true, hooks.roundState()) then
			away[player] = nil
			rejoin[player] = true
			reply(player, SpawnRules.reply(nil, request))
			hooks.beforeSpawn(player)
			return
		end
		-- Avant le journal et le chargement : le client est fixé tout de suite, même si la suite échoue
		local live = refusal == "alive" and SpawnRules.isAlive(player.Character)
		local answer = SpawnRules.reply(refusal, request, { away = away[player] == true, live = live })
		reply(player, answer)
		-- Personnage vivant que le client reprend (il l'avait ignoré au menu) : remis au round comme une apparition,
		-- sans refus au journal
		if live then
			away[player] = nil
			hooks.beforeSpawn(player)
			return
		end
		-- Le client attend le chargement en vol : s'il échoue, la demande est servie à sa fin (nouveau chargement)
		if answer.status == "spawning" then
			rejoin[player] = true
		end
		if refusal then
			local severity = REFUSAL_SEVERITY[refusal]
			if severity then
				local detail = refusal
				if refusal == "early" then
					detail = string.format("early : %.2f s après la mort", now - (diedAt[player] :: number))
				end
				CheatLog.report(Participants.fromPlayer(player), CheatLog.Category.SPAWN, severity, detail)
			end
			return
		end
		away[player] = nil
		hooks.beforeSpawn(player)
		if not SpawnManager.spawnPlayer(player) then
			reply(player, { status = "failed" })
		end
	end)
end

return SpawnManager
