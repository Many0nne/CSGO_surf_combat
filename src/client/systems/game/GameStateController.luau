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
local Transition = require(script.Parent.Parent.Parent.ui.Transition)
local Speedometer = require(script.Parent.Parent.Parent.ui.Speedometer)
local WeaponBar = require(script.Parent.Parent.Parent.ui.WeaponBar)
local AmmoCounter = require(script.Parent.Parent.Parent.ui.AmmoCounter)
local Crosshair = require(script.Parent.Parent.Parent.ui.Crosshair)
local KeyDisplay = require(script.Parent.Parent.Parent.ui.KeyDisplay)
local ScopeSystem = require(script.Parent.Parent.weapon.ScopeSystem)
local HUDRules = require(script.Parent.Parent.Parent.ui.HUDRules)
local KillFeed = require(script.Parent.Parent.Parent.ui.KillFeed)
local DeathCamera = require(script.Parent.Parent.Parent.camera.DeathCamera)
local DeathRagdoll = require(script.Parent.DeathRagdoll)

-- PlayerDied et Humanoid.Died arrivent dans un ordre quelconque : l'info du tueur reste applicable ce temps-là (s)
local DEATH_INFO_TTL = 1

local GameStateController = {}

type State = "MENU" | "INFOS" | "SPAWNING" | "IN_ROUND" | "DEAD" | "RESULT"

local state: State = "MENU"
local localPlayer: Player
local setupCharFn: (char: Model) -> ()
local humDiedConn: RBXScriptConnection?
local resultTimer: thread?
-- Dernière mort du joueur local annoncée par le serveur (qui, avec quoi), pour l'écran de mort
local lastDeath: { killer: string?, weapon: string?, headshot: boolean, at: number }? = nil

-- Remotes (résolus une seule fois)
local spawnRemote: RemoteEvent?

-- ── Caméra ─────────────────────────────────────────────────────────────────

local function deactivateMenuCamera()
	-- FPSCamera prend la main lors du spawn ; on remet Scriptable
	-- pour ne pas combattre avec lui (il le positionne lui-même)
	workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
end

-- ── Transitions d'état ─────────────────────────────────────────────────────

-- Cette méthode permet d'appliquer la règle unique « HUD de jeu visible » (HUDRules.gameHudVisible) au compteur de vitesse
-- à la barre d'armes et à la lunette lorsque l'état client change ; RoundHUD suit déjà l'état. HUD masqué (mort, fin de
-- round, menu) : le zoom est remis à zéro tout de suite (FOV, viewmodel, lunette), sans attendre le prochain personnage.
local function applyGameHud()
	local show = HUDRules.gameHudVisible(state)
	Speedometer.setVisible(show)
	WeaponBar.setVisible(show)
	AmmoCounter.setVisible(show)
	Crosshair.setHudVisible(show)
	KeyDisplay.setHudVisible(show)
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

local function setState(newState: State)
	state = newState
	applyGameHud()
	if newState ~= "DEAD" then
		-- Réapparition, menu ou fin de round : la caméra revient à FPSCamera ou au menu
		DeathCamera.stop()
	end
	if newState == "MENU" then
		DeathRagdoll.clear()
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

local function onCharacterAdded(char: Model)
	-- Connecter la mort
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
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

local function listenToRemotes()
	local N = NetworkProtocol.Names

	spawnRemote = NetworkProtocol.getRemote(N.REQUEST_SPAWN)

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
	-- Le passage en DEAD reste déclenché par Humanoid.Died ; le respawn est géré côté serveur.
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
	if spawnRemote then
		spawnRemote:FireServer()
	end
	return true
end

-- Cette méthode permet de lire l'état client courant (MENU, IN_ROUND…) lorsqu'un module doit s'y adapter.
function GameStateController.getState(): State
	return state
end

-- Cette méthode permet d'ouvrir Réglages à même la scène lorsque le joueur le demande depuis l'accueil du menu ;
-- renvoie true tant que le menu gère la demande, même s'il l'ignore (autre écran ouvert, volets en cours).
local function openSettingsPage(): boolean
	if state == "SPAWNING" then
		return true
	end
	if state ~= "MENU" then
		return false
	end
	if MainMenu.getPage() == "home" then
		SettingsMenu.open("page")
		MainMenu.setPage("settings")
	end
	return true
end

-- ── Init ───────────────────────────────────────────────────────────────────

function GameStateController.init(player: Player, setupCharacter: (char: Model) -> ())
	localPlayer = player
	setupCharFn = setupCharacter

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
	SettingsMenu.setPageRequest(function()
		-- INFOS est un écran du menu : la touche P y reste sans effet
		return state == "INFOS" or openSettingsPage()
	end)
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
