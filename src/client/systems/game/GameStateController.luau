local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local Shared          = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local GameConfig      = require(Shared:WaitForChild("GameConfig"))

local MainMenu      = require(script.Parent.Parent.Parent.ui.MainMenu)
local InfosScreen   = require(script.Parent.Parent.Parent.ui.InfosScreen)
local RoundHUD      = require(script.Parent.Parent.Parent.ui.RoundHUD)
local FeedbackModal = require(script.Parent.Parent.Parent.ui.FeedbackModal)

local GameStateController = {}

-- Caméra lobby : position fixe en attendant la map définitive
local LOBBY_CAM_CF = CFrame.new(0, 45, 75) * CFrame.Angles(math.rad(-22), 0, 0)

type State = "MENU" | "INFOS" | "SPAWNING" | "IN_ROUND" | "DEAD" | "RESULT"

local state: State = "MENU"
local localPlayer: Player
local setupCharFn: (char: Model) -> ()
local charAddedConn:    RBXScriptConnection?
local charRemovingConn: RBXScriptConnection?
local humDiedConn:      RBXScriptConnection?
local resultTimer:      thread?

-- Remotes (résolus une seule fois)
local spawnRemote: RemoteEvent?

-- ── Caméra lobby ───────────────────────────────────────────────────────────

local function activateLobbyCamera()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame     = LOBBY_CAM_CF
end

local function deactivateLobbyCamera()
	-- FPSCamera prend la main lors du spawn ; on remet Scriptable
	-- pour ne pas combattre avec lui (il le positionne lui-même)
	workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
end

-- ── Transitions d'état ─────────────────────────────────────────────────────

local function setState(newState: State)
	state = newState

	if newState == "MENU" then
		MainMenu.show()
		InfosScreen.hide()
		RoundHUD.hide()
		activateLobbyCamera()
		UserInputService.MouseBehavior  = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true

	elseif newState == "INFOS" then
		InfosScreen.show()

	elseif newState == "SPAWNING" then
		MainMenu.hide()
		InfosScreen.hide()
		FeedbackModal.hide()

	elseif newState == "IN_ROUND" then
		MainMenu.hide()
		InfosScreen.hide()
		RoundHUD.show()
		RoundHUD.hideRespawning()
		deactivateLobbyCamera()

	elseif newState == "DEAD" then
		RoundHUD.showRespawning(GameConfig.RESPAWN_DELAY)

	elseif newState == "RESULT" then
		RoundHUD.hide()
		-- Tuer le personnage local pour sortir du mode FPS et libérer la souris
		if localPlayer.Character then
			local hum = localPlayer.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then hum.Health = 0 end
		end
		UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

-- ── Liaison personnage ─────────────────────────────────────────────────────

local function onCharacterAdded(char: Model)
	-- Connecter la mort
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	if humDiedConn then humDiedConn:Disconnect() end
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
		if resultTimer then task.cancel(resultTimer); resultTimer = nil end
		setState("RESULT")
		RoundHUD.show()
		RoundHUD.showResult(data.winnerName)
		resultTimer = task.delay(GameConfig.RESULT_DURATION, function()
			RoundHUD.hideResult()
			RoundHUD.hide()
			setState("MENU")
		end)
	end)

	-- PlayerDied (feedback mort local, le respawn est géré côté serveur)
	local playerDiedRmt = NetworkProtocol.getRemote(N.PLAYER_DIED)
	playerDiedRmt.OnClientEvent:Connect(function(_data)
		-- Déjà géré via Humanoid.Died, mais peut servir pour affichage futur
	end)
end

-- ── Init ───────────────────────────────────────────────────────────────────

function GameStateController.init(player: Player, setupCharacter: (char: Model) -> ())
	localPlayer  = player
	setupCharFn  = setupCharacter

	-- Connexions RemoteEvent (attend que le serveur les crée)
	task.spawn(listenToRemotes)

	-- UI
	FeedbackModal.init()
	MainMenu.init(
		function()  -- Play
			if state ~= "MENU" then return end
			setState("SPAWNING")
			if spawnRemote then spawnRemote:FireServer() end
		end,
		function()  -- Infos
			setState("INFOS")
		end,
		function()  -- Feedback
			FeedbackModal.show()
		end
	)
	InfosScreen.init(function()  -- fermer infos
		setState("MENU")
	end)
	RoundHUD.init()

	-- Connexions personnage
	charAddedConn = player.CharacterAdded:Connect(onCharacterAdded)
	charRemovingConn = player.CharacterRemoving:Connect(onCharacterRemoving)

	-- Si personnage déjà présent (cas edge)
	if player.Character then
		onCharacterAdded(player.Character)
	end

	-- Démarrer en MENU
	setState("MENU")
end

return GameStateController
