local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ParticipantRules = require(Shared:WaitForChild("ParticipantRules"))
local BotCharacters = require(Shared:WaitForChild("BotCharacters"))

local MainMenu = require(script.Parent.Parent.Parent.ui.MainMenu)
local InfosScreen = require(script.Parent.Parent.Parent.ui.InfosScreen)
local RoundHUD = require(script.Parent.Parent.Parent.ui.RoundHUD)
local FeedbackScreen = require(script.Parent.Parent.Parent.ui.FeedbackScreen)
local SettingsMenu = require(script.Parent.Parent.Parent.ui.SettingsMenu)
local InGameMenu = require(script.Parent.Parent.Parent.ui.InGameMenu)
local InGameMenuRules = require(script.Parent.Parent.Parent.ui.InGameMenuRules)
local Transition = require(script.Parent.Parent.Parent.ui.Transition)
local Speedometer = require(script.Parent.Parent.Parent.ui.Speedometer)
local WeaponBar = require(script.Parent.Parent.Parent.ui.WeaponBar)
local AmmoCounter = require(script.Parent.Parent.Parent.ui.AmmoCounter)
local HUDState = require(script.Parent.Parent.Parent.ui.HUDState)
local ScopeSystem = require(script.Parent.Parent.weapon.ScopeSystem)
local HUDRules = require(script.Parent.Parent.Parent.ui.HUDRules)
local KillFeed = require(script.Parent.Parent.Parent.ui.KillFeed)
local DeathCamera = require(script.Parent.Parent.Parent.camera.DeathCamera)
local DeathRagdoll = require(script.Parent.DeathRagdoll)
local SpawnRequestRules = require(script.Parent.SpawnRequestRules)

-- PlayerDied et Humanoid.Died arrivent dans un ordre quelconque : l'info du tueur reste applicable ce temps-là (s)
local DEATH_INFO_TTL = 1
-- Message du menu quand une demande d'apparition n'aboutit pas (#219, SpawnRequestRules)
local SPAWN_FAILED_NOTICE = "IMPOSSIBLE DE REJOINDRE LA PARTIE, RÉESSAIE"
-- Message du menu quand la réapparition après une mort n'aboutit pas, redemande comprise (#245)
local RESPAWN_FAILED_NOTICE = "RÉAPPARITION IMPOSSIBLE"

local GameStateController = {}

type State = "MENU" | "INFOS" | "SPAWNING" | "IN_ROUND" | "DEAD" | "RESULT"

local state: State = "MENU"
local localPlayer: Player
local setupCharFn: (char: Model) -> ()
local stopCharFn: () -> ()
local humDiedConn: RBXScriptConnection?
-- Personnage déjà branché (mort, setup) : CharacterAdded et une reprise "alive" ne le branchent pas deux fois (#245)
local boundChar: Model? = nil
local resultTimer: thread?
-- Dernière mort du joueur local annoncée par le serveur (qui, avec quoi), pour l'écran de mort
local lastDeath: { killer: string?, weapon: string?, headshot: boolean, at: number }? = nil

-- Remotes (résolus une seule fois)
local spawnRemote: RemoteEvent?
local leaveRemote: RemoteEvent?
-- Demande d'apparition en cours (#219) : suivie tant que l'état est SPAWNING, nil sinon
local spawnAttempt: SpawnRequestRules.Attempt? = nil
-- Attente de la réapparition programmée (#245) : suivie tant que l'état est DEAD, nil sinon
local deadWatch: SpawnRequestRules.DeadWatch? = nil

-- ── Caméra ─────────────────────────────────────────────────────────────────

local function deactivateMenuCamera()
	-- FPSCamera prend la main lors du spawn ; on remet Scriptable
	-- pour ne pas combattre avec lui (il le positionne lui-même)
	workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
end

-- ── Transitions d'état ─────────────────────────────────────────────────────

-- Cette méthode permet d'appliquer la règle unique « HUD de jeu visible » (HUDRules.gameHudVisible) au compteur de vitesse
-- à la barre d'armes et à la lunette lorsque l'état client change ; RoundHUD suit déjà l'état, crosshair et affichage
-- des touches suivent HUDState (posé par setState). HUD masqué (mort, fin de round, menu) : le zoom est remis à zéro
-- tout de suite (FOV, viewmodel, lunette), sans attendre le prochain personnage.
local function applyGameHud()
	local show = HUDRules.gameHudVisible(state)
	Speedometer.setVisible(show)
	WeaponBar.setVisible(show)
	AmmoCounter.setVisible(show)
	KillFeed.setVisible(HUDRules.killFeedVisible(state))
	if not show then
		ScopeSystem.reset()
	end
end

-- Cette méthode permet de renseigner l'écran de mort avec le tueur lorsque l'état passe à DEAD ou que PlayerDied
-- arrive, si l'annonce du serveur est assez récente pour concerner cette mort.
local function applyDeathInfo()
	if state == "DEAD" and lastDeath and os.clock() - lastDeath.at < DEATH_INFO_TTL then
		RoundHUD.setDeathInfo(lastDeath.killer, lastDeath.weapon, lastDeath.headshot)
	end
end

local startRespawnWatch: () -> ()

local function setState(newState: State)
	state = newState
	if newState ~= "SPAWNING" then
		-- La surveillance de la demande s'arrête d'elle-même (GameStateController.requestPlay)
		spawnAttempt = nil
	end
	if newState ~= "DEAD" then
		-- Personnage revenu, round idle, fin de round ou retour au menu : la surveillance s'arrête (watchRespawn)
		deadWatch = nil
	end
	-- Avant la fermeture du menu en partie : les abonnés de HUDState voient le nouvel état menu encore ouvert (tout masqué),
	-- jamais l'ancien état de partie menu fermé (crosshair ou touches réaffichés un instant)
	HUDState.setGameState(newState)
	-- Avant le reste : le menu en partie rend la souris au jeu avant que le menu principal la reprenne
	InGameMenu.onGameState(newState)
	applyGameHud()
	if newState ~= "DEAD" then
		-- Réapparition, menu ou fin de round : la caméra revient à FPSCamera ou au menu
		DeathCamera.stop()
	end
	if newState == "MENU" then
		DeathRagdoll.clear()
		-- Mouvement et caméra coupés au menu : un personnage repris ensuite (JOUER, "alive") doit être rebranché
		boundChar = nil
	end

	if newState == "MENU" then
		SettingsMenu.close()
		MainMenu.show()
		InfosScreen.hide()
		RoundHUD.hide()
		-- La caméra et le curseur (hitmarker) sont pilotés par le menu
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	elseif newState == "INFOS" then
		SettingsMenu.close()
		InfosScreen.show()
		MainMenu.setPage("infos")
	elseif newState == "SPAWNING" then
		-- Le menu reste visible sous les volets qui se ferment ; il est masqué une fois l'écran couvert
		SettingsMenu.close()
		FeedbackScreen.hide()
		Transition.close(function()
			if state == "SPAWNING" then
				MainMenu.hide()
				InfosScreen.hide()
			end
		end)
	elseif newState == "IN_ROUND" then
		MainMenu.hide()
		InfosScreen.hide()
		Transition.open()
		RoundHUD.show()
		RoundHUD.hideRespawning()
		deactivateMenuCamera()
	elseif newState == "DEAD" then
		RoundHUD.showRespawning(GameConfig.RESPAWN_DELAY)
		applyDeathInfo()
		startRespawnWatch()
	elseif newState == "RESULT" then
		RoundHUD.hide()
		-- Tuer le personnage local pour sortir du mode FPS et libérer la souris
		if localPlayer.Character then
			local hum = localPlayer.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				hum.Health = 0
			end
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

-- ── Liaison personnage ─────────────────────────────────────────────────────

-- Cette méthode permet de savoir si le client est au menu (principal ou Infos) lorsqu'un personnage arrive, y compris
-- après une attente (l'état a pu changer pendant le WaitForChild).
local function atMenu(): boolean
	return state == "MENU" or state == "INFOS"
end

local function onCharacterAdded(char: Model)
	-- Au menu, un personnage n'est pas attendu (réapparition partie avant un retour au menu, détruite par le serveur, #157)
	if atMenu() then
		return
	end
	-- Connecter la mort
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	-- Après l'attente : retour au menu entre-temps (abandon, #245), ou personnage déjà branché par l'autre voie
	if atMenu() or boundChar == char then
		return
	end
	boundChar = char
	if humDiedConn then
		humDiedConn:Disconnect()
	end
	humDiedConn = humanoid.Died:Connect(function()
		if state == "IN_ROUND" then
			setState("DEAD")
		end
	end)

	-- Lancer le setup physique/caméra
	task.spawn(setupCharFn, char)

	-- Transition vers IN_ROUND (depuis SPAWNING ou DEAD/respawn)
	if state == "SPAWNING" or state == "DEAD" then
		setState("IN_ROUND")
	end
end

local function onCharacterRemoving(_char: Model)
	if state == "IN_ROUND" then
		setState("DEAD")
	end
	-- En RESULT la destruction vient de endRound() côté serveur — pas de transition
end

-- ── Remotes serveur ────────────────────────────────────────────────────────

-- Cette méthode permet de montrer une mort lorsque le serveur l'annonce (HUDRules.readDeath) : ligne de kill feed et
-- ragdoll en partie, écran de mort et caméra si c'est le joueur local. Tueur ou victime bot : pas de Player, son
-- personnage est retrouvé par son tag (BotCharacters, #139).
local function onPlayerDied(data: any)
	local death = HUDRules.readDeath(data, localPlayer.UserId)
	-- Hors partie (menu, spawn), rien à montrer
	if not death or not HUDRules.killFeedVisible(state) then
		return
	end
	local victimChar = BotCharacters.characterOf(death.victimId, death.victimIsBot)
	local killerChar = if death.killerId then BotCharacters.characterOf(death.killerId, death.killerIsBot) else nil

	DeathRagdoll.spawn(victimChar, death.direction, death.weapon, death.headshot)
	KillFeed.add(death)

	if not death.victimIsBot and death.victimId == localPlayer.UserId then
		lastDeath = {
			killer = death.killer and ParticipantRules.displayName(death.killer, death.killerIsBot),
			weapon = death.weapon,
			headshot = death.headshot,
			at = os.clock(),
		}
		applyDeathInfo()
		DeathCamera.start(killerChar, death.killer and ParticipantRules.displayName(death.killer, death.killerIsBot))
	end
end

-- Cette méthode permet d'appliquer la réponse du serveur à la demande en cours (#219 en SPAWNING, redemande en DEAD
-- #245, rien ailleurs) ; "alive" avec un personnage local vivant : il est repris comme s'il venait d'apparaître.
local function onSpawnReply(answer: any)
	-- setState remet spawnAttempt à nil hors SPAWNING, deadWatch hors DEAD
	local attempt = spawnAttempt or (deadWatch and deadWatch.attempt)
	if not attempt then
		return
	end
	local char = localPlayer.Character
	local humanoid = char and char.Parent and char:FindFirstChildOfClass("Humanoid")
	local live = humanoid ~= nil and humanoid.Health > 0
	-- onCharacterAdded ne branche pas deux fois le même personnage (CharacterAdded encore en attente, boundChar)
	if SpawnRequestRules.onReply(attempt, answer, os.clock(), live) == "adopt" and char then
		onCharacterAdded(char)
	end
end

-- Cette méthode permet de retenir le remote RequestSpawn (trouvé par getRemote, ou cherché plus tard s'il manquait,
-- #219) et d'écouter ses réponses, une seule fois.
local function resolveSpawnRemote(found: Instance?): RemoteEvent?
	if spawnRemote then
		return spawnRemote
	end
	local remote = found or ReplicatedStorage:FindFirstChild(NetworkProtocol.Names.REQUEST_SPAWN)
	if remote and remote:IsA("RemoteEvent") then
		spawnRemote = remote
		remote.OnClientEvent:Connect(onSpawnReply)
	end
	return spawnRemote
end

-- Cette méthode permet d'envoyer (ou renvoyer) la demande d'apparition en cours lorsque SpawnRequestRules le décide ;
-- rien ne part tant que le remote n'existe pas (la surveillance réessaie, puis abandonne).
local function sendSpawnRequest(attempt: SpawnRequestRules.Attempt)
	local remote = resolveSpawnRemote()
	if remote then
		SpawnRequestRules.noteSent(attempt, os.clock())
		remote:FireServer()
	end
end

-- Cette méthode permet d'abandonner une demande restée sans suite après ses délais (#219, #245) : retour au menu avec
-- le message notice, et LeaveRound pour qu'un personnage arrivé trop tard ne reste pas dans le round.
local function giveUpSpawn(notice: string)
	warn("[GameState] apparition sans suite (" .. state .. ") : retour au menu")
	-- Cherché ici aussi : listenToRemotes peut encore l'attendre
	local leave = leaveRemote or ReplicatedStorage:FindFirstChild(NetworkProtocol.Names.LEAVE_ROUND)
	if leave and leave:IsA("RemoteEvent") then
		leave:FireServer()
	end
	setState("MENU")
	-- Les volets fermés par SPAWNING couvrent encore l'écran
	Transition.open()
	MainMenu.showNotice(notice)
end

-- Cette méthode permet de dérouler une surveillance d'apparition (JOUER #219, ou DEAD #245) tant que isCurrent() :
-- tick décide à chaque pas d'attendre, (r)envoyer la demande getAttempt() ou abandonner vers le menu avec notice.
local function runSpawnWatch(
	isCurrent: () -> boolean,
	tick: (now: number) -> SpawnRequestRules.TickAction,
	getAttempt: () -> SpawnRequestRules.Attempt?,
	notice: string
)
	while isCurrent() do
		local action = tick(os.clock())
		if action == "giveUp" then
			giveUpSpawn(notice)
			return
		elseif action == "send" then
			local attempt = getAttempt()
			if attempt then
				sendSpawnRequest(attempt)
			end
		end
		task.wait(SpawnRequestRules.TICK)
	end
end

-- Cette méthode permet de surveiller une demande d'apparition lorsqu'elle part (JOUER) : renvoi sans réponse, après un
-- refus temporaire ou un échec, abandon après un délai borné ; s'arrête dès que l'état quitte SPAWNING.
local function watchSpawnRequest(attempt: SpawnRequestRules.Attempt)
	runSpawnWatch(function()
		return spawnAttempt == attempt
	end, function(now)
		return SpawnRequestRules.onTick(attempt, now)
	end, function()
		return attempt
	end, SPAWN_FAILED_NOTICE)
end

-- Cette méthode permet de borner l'attente en DEAD (#245) lorsque la réapparition programmée par le serveur tarde :
-- redemande comme JOUER passé RESPAWN_DELAY + RESPAWN_MARGIN, puis retour au menu ; s'arrête dès que l'état quitte DEAD.
local function watchRespawn(watch: SpawnRequestRules.DeadWatch)
	local waitFor = GameConfig.RESPAWN_DELAY + GameConfig.RESPAWN_MARGIN
	runSpawnWatch(function()
		return deadWatch == watch
	end, function(now)
		return SpawnRequestRules.onDeadTick(watch, now, waitFor)
	end, function()
		return watch.attempt
	end, RESPAWN_FAILED_NOTICE)
end

-- Cette méthode permet de lancer la surveillance de la réapparition lorsque le joueur local passe en DEAD.
function startRespawnWatch()
	local watch = SpawnRequestRules.newDeadWatch(os.clock())
	deadWatch = watch
	task.spawn(watchRespawn, watch)
end

local function listenToRemotes()
	local N = NetworkProtocol.Names

	resolveSpawnRemote(NetworkProtocol.getRemote(N.REQUEST_SPAWN))
	leaveRemote = NetworkProtocol.getRemote(N.LEAVE_ROUND)

	-- RoundState : { state, timeLeft }
	local roundStateRmt = NetworkProtocol.getRemote(N.ROUND_STATE)
	roundStateRmt.OnClientEvent:Connect(function(data: { state: string, timeLeft: number })
		RoundHUD.updateTimer(data.timeLeft)
		-- Si round devient idle alors qu'on était DEAD, revenir au menu
		if data.state == "idle" and state == "DEAD" then
			setState("MENU")
		end
	end)

	-- ScoreUpdate
	local scoreUpdateRmt = NetworkProtocol.getRemote(N.SCORE_UPDATE)
	scoreUpdateRmt.OnClientEvent:Connect(function(scores)
		RoundHUD.updateScores(scores)
	end)

	-- RoundResult : { winnerName, scores }
	local roundResultRmt = NetworkProtocol.getRemote(N.ROUND_RESULT)
	roundResultRmt.OnClientEvent:Connect(function(data: { winnerName: string })
		-- Hors partie (menu, infos, spawn en cours), ignorer : RESULT bloquerait la promotion vers IN_ROUND (#110)
		if not HUDRules.acceptsRoundResult(state) then
			return
		end
		if resultTimer then
			task.cancel(resultTimer)
			resultTimer = nil
		end
		setState("RESULT")
		RoundHUD.show()
		RoundHUD.showResult(data.winnerName)
		resultTimer = task.delay(GameConfig.RESULT_DURATION, function()
			RoundHUD.hideResult()
			RoundHUD.hide()
			setState("MENU")
		end)
	end)

	-- PlayerDied (#102), envoyé à tous : corps, kill feed, et pour le tué écran de mort et caméra vers le tueur.
	-- Le passage en DEAD reste déclenché par Humanoid.Died ; le respawn est géré côté serveur (redemande s'il tarde, #245).
	local playerDiedRmt = NetworkProtocol.getRemote(N.PLAYER_DIED)
	playerDiedRmt.OnClientEvent:Connect(onPlayerDied)
end

-- ── API ────────────────────────────────────────────────────────────────────

-- Cette méthode permet de lancer le spawn en round comme le bouton Play lorsqu'on est au menu ou sur Infos ;
-- renvoie false si l'état ne le permet pas (aussi utilisée par le helper de playtest Studio, #30).
function GameStateController.requestPlay(): boolean
	if state ~= "MENU" and state ~= "INFOS" then
		return false
	end
	setState("SPAWNING")
	-- Le serveur répond à chaque demande ; sans réponse ou après un refus temporaire, elle est renvoyée (#219)
	local attempt = SpawnRequestRules.new(os.clock())
	spawnAttempt = attempt
	task.spawn(watchSpawnRequest, attempt)
	return true
end

-- Cette méthode permet de revenir au menu principal lorsque le joueur choisit MENU PRINCIPAL dans le menu en partie
-- (#157) : le serveur le retire du round (score, personnage), le client repasse au menu sans attendre sa réponse.
local function leaveRound()
	if not InGameMenuRules.available(state) then
		return
	end
	-- Mouvement et caméra FPS coupés dès le clic (#217) : plus aucune entrée de jeu jusqu'à la destruction du personnage
	stopCharFn()
	-- Arme rangée tout de suite (viewmodel, lunette, délais d'arme), sans attendre la destruction du personnage
	local char = localPlayer.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
	end
	if leaveRemote then
		leaveRemote:FireServer()
	end
	setState("MENU")
end

-- Cette méthode permet de lire l'état client courant (MENU, IN_ROUND…) lorsqu'un module doit s'y adapter.
function GameStateController.getState(): State
	return state
end

-- Cette méthode permet d'ouvrir Réglages à même la scène lorsque le joueur le demande depuis l'accueil du menu (rien
-- sur un autre écran du menu ni pendant les volets).
local function openSettingsPage()
	if state == "MENU" and MainMenu.getPage() == "home" then
		SettingsMenu.open("page")
		MainMenu.setPage("settings")
	end
end

-- ── Init ───────────────────────────────────────────────────────────────────

function GameStateController.init(player: Player, setupCharacter: (char: Model) -> (), stopCharacter: () -> ())
	localPlayer = player
	setupCharFn = setupCharacter
	stopCharFn = stopCharacter

	-- Connexions RemoteEvent (attend que le serveur les crée)
	task.spawn(listenToRemotes)

	-- UI
	FeedbackScreen.init(function() -- fermer Feedback
		MainMenu.setPage("home")
	end)
	MainMenu.init(function() -- Play
		GameStateController.requestPlay()
	end, function() -- Infos
		setState("INFOS")
	end, function() -- Feedback
		MainMenu.setPage("feedback")
		FeedbackScreen.show()
	end, function() -- Réglages
		openSettingsPage()
	end, function() -- Accueil (onglet ARMES, ou changement d'onglet depuis un écran ouvert)
		if state == "INFOS" then
			setState("MENU")
		end
		FeedbackScreen.hide()
		SettingsMenu.close()
		MainMenu.setPage("home")
	end)
	-- Menu en partie (#157) ; au menu principal, sa touche ouvre ou ferme les Réglages de l'accueil
	InGameMenu.init({
		getState = function()
			return state
		end,
		onLeave = leaveRound,
		onMainMenuKey = function()
			if SettingsMenu.isOpen() then
				SettingsMenu.close()
			else
				openSettingsPage()
			end
		end,
	})
	SettingsMenu.setOnClosed(function()
		if state == "MENU" then
			MainMenu.setPage("home")
		end
	end)
	InfosScreen.init(function() -- fermer infos
		setState("MENU")
	end)
	RoundHUD.init()
	KillFeed.init()
	Transition.init()

	-- Connexions personnage
	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(onCharacterRemoving)

	-- Si personnage déjà présent (cas edge)
	if player.Character then
		onCharacterAdded(player.Character)
	end

	-- Démarrer en MENU
	setState("MENU")
end

return GameStateController
