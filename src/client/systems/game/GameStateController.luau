local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local MapSelection = require(Shared:WaitForChild("MapSelection"))
local ParticipantRules = require(Shared:WaitForChild("ParticipantRules"))
local BotCharacters = require(Shared:WaitForChild("BotCharacters"))

local MainMenu = require(script.Parent.Parent.Parent.ui.MainMenu)
local InfosScreen = require(script.Parent.Parent.Parent.ui.InfosScreen)
local LearnScreen = require(script.Parent.Parent.Parent.ui.LearnScreen)
local ShopScreen = require(script.Parent.Parent.Parent.ui.ShopScreen)
local RoundHUD = require(script.Parent.Parent.Parent.ui.RoundHUD)
local FeedbackScreen = require(script.Parent.Parent.Parent.ui.FeedbackScreen)
local LobbyScreen = require(script.Parent.Parent.Parent.ui.LobbyScreen)
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
local KillAnnouncer = require(script.Parent.KillAnnouncer)
local SpawnRequestRules = require(script.Parent.SpawnRequestRules)
local BeginnerState = require(script.Parent.BeginnerState)
local BeginnerRules = require(script.Parent.BeginnerRules)
local InfosRules = require(script.Parent.Parent.Parent.ui.InfosRules)
local LocalSettings = require(script.Parent.Parent.settings.LocalSettings)
local TrainingClient = require(script.Parent.TrainingClient)
local PartyClient = require(script.Parent.PartyClient)
local HighlightPlayer = require(script.Parent.Parent.highlight.HighlightPlayer)
local HighlightClipRules = require(Shared:WaitForChild("HighlightClipRules"))

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
-- Conseils de l'écran de mort (#291) : morts du joueur local, et morts qui ont montré un conseil (les conseils tournent,
-- un par mort, en commençant au premier) ; `tipDeath` : dernière mort comptée, pour ne la compter qu'une fois
local deathCount = 0
-- Dernière map dont le nom a été affiché à l'arrivée dans une manche (#594) : nil avant la première manche
local lastMapTitle: string? = nil
local tipCount = 0
local tipDeath = 0

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
	-- Entraînement (#345) : pas de fil des kills (seulement des chutes), la démo prend sa place en haut à droite
	KillFeed.setVisible(HUDRules.killFeedVisible(state) and not TrainingClient.isTraining())
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

-- Cette méthode permet de poser le conseil de l'écran de mort (#291) lorsque le joueur meurt, ou que son état débutant
-- ou ses réglages (conseils, auto-bhop, touches) changent pendant qu'il est mort ; rien pour un non-débutant.
local function applyDeathTip()
	if state ~= "DEAD" then
		return
	end
	local settings = LocalSettings.get()
	local beginner = BeginnerState.isBeginner()
	if not (beginner and settings.deathTips) then
		RoundHUD.setTip(nil)
		return
	end
	-- Premier conseil de cette mort (à la mort, ou conseils activés pendant qu'il est mort) : conseil suivant
	if tipDeath ~= deathCount then
		tipDeath = deathCount
		tipCount += 1
	end
	local tips = InfosRules.deathTips({
		entries = HUDRules.keyDisplayEntries("full"),
		keyText = LocalSettings.keyText,
		autoBhop = settings.autoBhop,
	})
	RoundHUD.setTip(BeginnerRules.pickTip(tips, beginner, settings.deathTips, tipCount))
end

local startRespawnWatch: () -> ()

local function setState(newState: State)
	state = newState
	if newState ~= "IN_ROUND" then
		-- Mort, fin de manche ou retour au menu : la série de kills de l'annonceur repart à 0
		KillAnnouncer.reset()
	end
	if newState ~= "SPAWNING" then
		-- La surveillance de la demande s'arrête d'elle-même (GameStateController.requestPlay)
		spawnAttempt = nil
	end
	if not SpawnRequestRules.keepsDeadWatch(newState) then
		-- Personnage revenu, round idle, fin de round ou retour au menu : la surveillance s'arrête (watchRespawn)
		deadWatch = nil
	end
	-- Avant la fermeture du menu en partie : les abonnés de HUDState voient le nouvel état menu encore ouvert (tout masqué),
	-- jamais l'ancien état de partie menu fermé (crosshair ou touches réaffichés un instant)
	HUDState.setGameState(newState)
	-- Avant le reste : le menu en partie rend la souris au jeu avant que le menu principal la reprenne
	InGameMenu.onGameState(newState)
	applyGameHud()
	-- Démo dans un coin sur un serveur d'entraînement (#345), libérée au menu
	TrainingClient.onGameState(newState)
	if newState ~= "DEAD" then
		-- Réapparition, menu ou fin de round : la caméra revient à FPSCamera ou au menu
		DeathCamera.stop()
	end
	if newState ~= "RESULT" then
		-- Clip de la partie (#499) : ne survit pas à la phase de résultat (menu, manche suivante)
		HighlightPlayer.stop()
	end
	if newState == "MENU" or newState == "SPAWNING" then
		-- Corps de la manche finie retirés aussi quand elle s'enchaîne sans passer par le menu (#300)
		DeathRagdoll.clear()
	end
	if newState == "MENU" or newState == "RESULT" then
		-- Mouvement et caméra coupés au menu et à la fin de manche : un personnage repris ensuite (JOUER, enchaînement
		-- #300, "alive") doit être rebranché
		boundChar = nil
	end

	if newState == "MENU" then
		SettingsMenu.close()
		-- Retour de partie : le menu repart de l'accueil. Le serveur est prévenu que le joueur n'est plus en partie pour son
		-- groupe (#523) : LeaveRound ne part pas sur tous les chemins (manche finie pendant l'écran de mort)
		LobbyScreen.hide(true)
		PartyClient.close()
		MainMenu.show()
		InfosScreen.hide()
		RoundHUD.hide()
		-- La caméra et le curseur (souris système) sont pilotés par le menu
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	elseif newState == "INFOS" then
		SettingsMenu.close()
		InfosScreen.show()
		MainMenu.setPage("infos")
	elseif newState == "SPAWNING" then
		-- Le menu reste visible sous les volets qui se ferment ; il est masqué une fois l'écran couvert
		SettingsMenu.close()
		FeedbackScreen.hide()
		LearnScreen.hide()
		Transition.close(function()
			if state == "SPAWNING" then
				-- Le shop garde sa salle sous les volets : la caméra ne saute pas à l'accueil pendant qu'ils se ferment
				ShopScreen.hide()
				-- Entrée dans la manche (LANCER) : le serveur sait déjà que le joueur quitte le lobby
				LobbyScreen.hide(true)
				MainMenu.hide()
				InfosScreen.hide()
			end
		end)
	elseif newState == "IN_ROUND" then
		ShopScreen.hide()
		LobbyScreen.hide(true)
		MainMenu.hide()
		InfosScreen.hide()
		LearnScreen.hide()
		Transition.open()
		RoundHUD.show()
		RoundHUD.hideRespawning()
		deactivateMenuCamera()
		-- Arrivée sur une map pas encore annoncée (première manche, ou map changée par la rotation, #594) : son nom
		local title = HUDRules.mapTitle(MapSelection.currentName(), lastMapTitle)
		if title then
			lastMapTitle = MapSelection.currentName()
			RoundHUD.showMapTitle(title)
		end
	elseif newState == "DEAD" then
		RoundHUD.showRespawning(GameConfig.RESPAWN_DELAY)
		applyDeathInfo()
		deathCount += 1
		applyDeathTip()
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

-- Cette méthode permet de savoir si un personnage qui arrive est ignoré lorsqu'il apparaît : au menu, ou pendant la
-- bannière de fin de manche (#300), y compris après une attente.
local function ignoresCharacter(): boolean
	return atMenu() or state == "RESULT"
end

local function onCharacterAdded(char: Model)
	-- Au menu, un personnage n'est pas attendu (réapparition partie avant un retour au menu, détruite par le serveur, #157).
	-- Pendant la bannière non plus (réapparition en vol à la fin de manche) : la demande qui enchaîne le reprend ("alive",
	-- #300), d'où boundChar remis à nil en RESULT
	if ignoresCharacter() then
		return
	end
	-- Connecter la mort
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	-- Après l'attente : retour au menu entre-temps (abandon, #245), ou personnage déjà branché par l'autre voie
	if ignoresCharacter() or boundChar == char then
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

	local victimIsLocal = not death.victimIsBot and death.victimId == localPlayer.UserId
	if victimIsLocal then
		KillAnnouncer.reset()
	elseif state == "IN_ROUND" and not death.killerIsBot and death.killerId == localPlayer.UserId then
		-- Kill du joueur local vivant : annonce « Headshot » ou palier de série (KillStreakRules)
		KillAnnouncer.onKill(death.headshot)
	end

	if victimIsLocal then
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

-- Cette méthode permet de passer en SPAWNING et d'envoyer une demande d'apparition suivie (#219) lorsque le joueur
-- clique JOUER ou enchaîne la manche suivante après la bannière de fin (#300).
local function startSpawnRequest()
	setState("SPAWNING")
	-- Le serveur répond à chaque demande ; sans réponse ou après un refus temporaire, elle est renvoyée (#219)
	local attempt = SpawnRequestRules.new(os.clock())
	spawnAttempt = attempt
	task.spawn(watchSpawnRequest, attempt)
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

	-- RoundResult : { outcome, winnerId, scores, clip? } (#295, #499), lu par HUDRules.readRoundResult
	local roundResultRmt = NetworkProtocol.getRemote(N.ROUND_RESULT)
	roundResultRmt.OnClientEvent:Connect(function(data: any)
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
		RoundHUD.showResult(data)
		-- Fin de la bannière, puis clip de la partie s'il y en a un (#499), joué une fois sans pouvoir passer :
		-- enchaînement sur la manche suivante sans repasser par le menu (#300). Le serveur repasse idle après la même
		-- durée (HighlightClipRules.resultDuration), comptée avant la réception : une demande un peu en avance reçoit
		-- "result" et est renvoyée (SpawnRequestRules.RESULT_RETRY) ; la première acceptée démarre la manche (beforeSpawn).
		local clip = HighlightClipRules.readClip(data and data.clip)
		if data and data.clip ~= nil and not clip then
			warn("[Highlight] clip reçu illisible : ignoré")
		end
		-- Cette méthode permet d'enchaîner sur la manche suivante lorsque la bannière (et le clip) est finie.
		local function afterResult()
			if SpawnRequestRules.afterResult(state) == "SPAWNING" then
				startSpawnRequest()
			end
		end
		resultTimer = task.delay(GameConfig.RESULT_DURATION, function()
			resultTimer = nil
			RoundHUD.hideResult()
			RoundHUD.hide()
			if clip and state == "RESULT" then
				HighlightPlayer.play(clip, afterResult)
			else
				afterResult()
			end
		end)
	end)

	-- PlayerDied (#102), envoyé à tous : corps, kill feed, et pour le tué écran de mort et caméra vers le tueur.
	-- Le passage en DEAD reste déclenché par Humanoid.Died ; le respawn est géré côté serveur (redemande s'il tarde, #245).
	local playerDiedRmt = NetworkProtocol.getRemote(N.PLAYER_DIED)
	playerDiedRmt.OnClientEvent:Connect(onPlayerDied)
end

-- ── API ────────────────────────────────────────────────────────────────────

-- Cette méthode permet de lancer le spawn en round lorsqu'on est au menu ou sur Infos (LANCER du lobby, LANCER de l'hôte
-- reçu par un membre, arrivée sur l'entraînement) ; renvoie false si l'état ne le permet pas (aussi utilisée par le
-- helper de playtest Studio, #30, qui passe donc à côté du lobby).
function GameStateController.requestPlay(): boolean
	if state ~= "MENU" and state ~= "INFOS" then
		return false
	end
	startSpawnRequest()
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
	-- QUITTER L'ENTRAÎNEMENT (#345) : retour au menu comme MENU PRINCIPAL, puis téléportation vers un serveur public ;
	-- si elle échoue, le joueur reste au menu (message), d'où il peut réessayer (APPRENDRE) ou rejouer
	if TrainingClient.isTraining() then
		TrainingClient.request()
	end
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

-- Cette méthode permet de revenir à l'accueil du menu lorsque le joueur change d'onglet depuis un écran ouvert (onglet
-- ARMES, ou avant d'ouvrir un autre écran) : tout écran secondaire se ferme, le lobby prévient le serveur qu'il le quitte.
local function goHome()
	if state == "INFOS" then
		setState("MENU")
	end
	FeedbackScreen.hide()
	LearnScreen.hide()
	ShopScreen.hide()
	LobbyScreen.hide()
	SettingsMenu.close()
	MainMenu.setPage("home")
end

-- Cette méthode permet d'ouvrir le lobby (#523) lorsque le joueur clique JOUER, ou qu'il vient d'entrer dans le groupe
-- d'un ami ; sur un serveur d'entraînement (seul par serveur, #388), JOUER entre directement en partie.
local function openLobby()
	if TrainingClient.isTraining() then
		GameStateController.requestPlay()
		return
	end
	if state ~= "MENU" and state ~= "INFOS" then
		return
	end
	if MainMenu.getPage() ~= "home" then
		goHome()
	end
	MainMenu.setPage("lobby")
	LobbyScreen.show()
end

-- Cette méthode permet de faire entrer le joueur dans la manche lorsque son hôte lance (#523) : seulement s'il attend
-- dans le lobby ; ailleurs (autre page, déjà en partie), le serveur est prévenu qu'il n'y est plus.
local function onPartyGo()
	if state == "MENU" and LobbyScreen.isOpen() then
		if GameStateController.requestPlay() then
			LobbyScreen.lock()
		end
	elseif not LobbyScreen.isOpen() then
		PartyClient.close()
	end
end

-- Cette méthode permet de n'exécuter un choix du menu (onglet, RETOUR du lobby) que lorsque le client est au menu : les
-- volets de LANCER mettent un instant à couvrir l'écran, un onglet cliqué entre-temps écraserait SPAWNING (le
-- personnage serait ignoré, le joueur resterait derrière les volets).
local function fromMenu(action: () -> ()): () -> ()
	return function()
		if atMenu() then
			action()
		end
	end
end

-- ── Init ───────────────────────────────────────────────────────────────────

function GameStateController.init(player: Player, setupCharacter: (char: Model) -> (), stopCharacter: () -> ())
	localPlayer = player
	setupCharFn = setupCharacter
	stopCharFn = stopCharacter

	-- Connexions RemoteEvent (attend que le serveur les crée)
	task.spawn(listenToRemotes)
	-- Mode du serveur (#345) connu avant les écrans qui en dépendent (libellés, HUD)
	TrainingClient.waitForMode()
	local training = TrainingClient.isTraining()

	-- UI
	FeedbackScreen.init(function() -- fermer Feedback
		MainMenu.setPage("home")
	end)
	MainMenu.init(
		fromMenu(openLobby),
		fromMenu(function() -- Infos ; JOUER ouvre le lobby (#523)
			setState("INFOS")
		end),
		fromMenu(function() -- Feedback
			MainMenu.setPage("feedback")
			FeedbackScreen.show()
		end),
		fromMenu(openSettingsPage),
		fromMenu(goHome),
		fromMenu(function() -- Apprendre (#285)
			MainMenu.setPage("learn")
			LearnScreen.show()
		end),
		fromMenu(function() -- Shop (#347)
			MainMenu.setPage("shop")
			ShopScreen.show()
		end)
	)
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
		leaveLabel = if training then TrainingClient.actionLabel() else nil,
		-- Entraînement (#345) : la démo du coin se masque ou se réaffiche depuis le menu
		toggle = if training
			then { label = TrainingClient.demoToggleLabel, action = TrainingClient.toggleDemo }
			else nil,
	})
	SettingsMenu.setOnClosed(function()
		if state == "MENU" then
			MainMenu.setPage("home")
		end
	end)
	InfosScreen.init(function() -- fermer infos
		setState("MENU")
	end)
	ShopScreen.init()
	-- Lobby entre amis (#523) : LANCER entre dans la manche comme JOUER le faisait, mêmes règles d'apparition
	LobbyScreen.init({
		onBack = fromMenu(goHome),
		onLaunch = GameStateController.requestPlay,
		onNotice = MainMenu.showNotice,
	})
	PartyClient.init(onPartyGo, openLobby, MainMenu.showNotice)
	LearnScreen.init(function() -- fermer Apprendre
		LearnScreen.hide()
		MainMenu.setPage("home")
	end, { label = TrainingClient.actionLabel(), action = TrainingClient.request })
	RoundHUD.init()
	RoundHUD.setTraining(training)
	-- Série de kills montrée sous le timer (#364), comptée par l'annonceur
	KillAnnouncer.onStreak(RoundHUD.setStreak)
	LocalSettings.onChanged(applyDeathTip)
	BeginnerState.onChanged(applyDeathTip)
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
	-- Arrivée sur un serveur d'entraînement (#345) : en jeu tout de suite, comme JOUER (le joueur vient de le demander)
	if training then
		GameStateController.requestPlay()
	end
end

return GameStateController
