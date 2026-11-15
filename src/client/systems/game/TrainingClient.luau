-- Mode entraînement côté client (#345) : lit le mode du serveur (attribut de ReplicatedStorage posé par TrainingService),
-- envoie les demandes du joueur (S'ENTRAÎNER sur APPRENDRE, QUITTER L'ENTRAÎNEMENT) et montre la réponse au menu.
-- Sur un serveur d'entraînement, la démo (DemoPlayer, la même qu'APPRENDRE, en petit et sans sa phrase) tourne en boucle
-- en haut à droite tant que le joueur est en partie (vivant ou en attente de réapparition), libérée au retour au menu.
-- Le joueur peut la masquer (menu en partie ou Réglages, réglage trainingDemo sauvegardé) : elle est alors libérée aussi.
-- Aucun jugement du geste : le joueur compare lui-même ses touches, sa souris et sa vitesse (HUD) à celles de la démo.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local PlayerSettings = require(Shared:WaitForChild("PlayerSettings"))
local TrainingRules = require(Shared:WaitForChild("TrainingRules"))

local LocalSettings = require(script.Parent.Parent.settings.LocalSettings)

local UI = script.Parent.Parent.Parent.ui
local DemoPlayer = require(UI.DemoPlayer)
local InfosContext = require(UI.InfosContext)
local InfosRules = require(UI.InfosRules)
local MainMenu = require(UI.MainMenu)
local UIKit = require(UI.UIKit)

local TrainingClient = {}

-- Coin de la démo (px à 720 de haut, à l'échelle du HUD) : en haut à droite, place du fil des kills, masqué à
-- l'entraînement ; le compteur de vitesse (bas à gauche) et les touches (bas au centre) du joueur restent dégagés
local CORNER_SCALE = 0.6
local CORNER_MARGIN = 24
-- Sous le menu en partie et son voile (DisplayOrder 2 et 3) : le menu couvre la démo
local CORNER_ORDER = 1
local HINT_GAP = 6 -- px entre le bas de la démo et le rappel de la touche du menu

local remote: RemoteEvent? = nil
local cornerGui: ScreenGui? = nil
local cornerHolder: Frame? = nil
local demo: DemoPlayer.Demo? = nil
local gameState = "MENU" -- dernier état du client (GameStateController)

-- Délai (s) d'attente du remote Training au démarrage du client, avant de composer les écrans selon le mode
local MODE_WAIT = 10

-- Cette méthode permet de savoir si le client est sur un serveur d'entraînement lorsqu'un écran ou le HUD s'y adapte.
function TrainingClient.isTraining(): boolean
	return ReplicatedStorage:GetAttribute(TrainingRules.ATTRIBUTE) == true
end

-- Cette méthode permet d'attendre que le mode du serveur soit connu lorsque le client démarre, avant de construire les
-- écrans qui en dépendent : le serveur publie l'attribut avant de créer le remote Training (au plus MODE_WAIT s).
function TrainingClient.waitForMode()
	ReplicatedStorage:WaitForChild(NetworkProtocol.Names.TRAINING, MODE_WAIT)
end

-- Cette méthode permet de donner le libellé de l'action qui rejoint ou quitte l'entraînement lorsqu'un écran la pose.
function TrainingClient.actionLabel(): string
	return if TrainingClient.isTraining() then "QUITTER L'ENTRAÎNEMENT" else "S'ENTRAÎNER"
end

-- Cette méthode permet de trouver le remote Training (créé par le serveur) lorsqu'une demande part, et d'écouter ses
-- réponses, une seule fois ; nil s'il n'existe pas encore.
local function resolveRemote(): RemoteEvent?
	if remote then
		return remote
	end
	local found = ReplicatedStorage:FindFirstChild(NetworkProtocol.Names.TRAINING)
	if found and found:IsA("RemoteEvent") then
		remote = found
		found.OnClientEvent:Connect(function(status)
			local text = TrainingRules.notice(status)
			if text then
				MainMenu.showNotice(text)
			end
		end)
	end
	return remote
end

-- Cette méthode permet de demander au serveur de rejoindre l'entraînement (depuis la partie) ou de le quitter (depuis
-- l'entraînement) lorsque le joueur clique ; la réponse s'affiche au menu.
function TrainingClient.request()
	local found = resolveRemote()
	if not found then
		MainMenu.showNotice(TrainingRules.notice("unavailable") :: string)
		return
	end
	found:FireServer(if TrainingClient.isTraining() then TrainingRules.LEAVE else TrainingRules.JOIN)
end

-- Cette méthode permet de construire le cadre du coin (vide, sans lecteur) lorsque la démo s'affiche pour la première
-- fois.
local function ensureCorner(): Frame
	if cornerHolder then
		return cornerHolder
	end
	local gui = UIKit.create("ScreenGui", {
		Name = "TrainingDemo",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		-- Comme l'écran Apprendre : en Global (défaut d'Instance.new), les libellés des touches et l'icône de la souris
		-- du lecteur passent sous la vue (ZIndex 2) et disparaissent
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = CORNER_ORDER,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	local root = UIKit.scaledRoot(gui, true)
	local holder = UIKit.frame({
		Name = "Corner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -CORNER_MARGIN, 0, CORNER_MARGIN),
		Size = UDim2.fromOffset(DemoPlayer.Size.X * CORNER_SCALE, DemoPlayer.Size.Y * CORNER_SCALE),
		Parent = root,
	})
	-- Sous la démo, aligné sur son bord droit : comment la masquer (même écriture que les aides du menu en partie) ;
	-- dans le même ScreenGui, masqué avec elle
	local hints = UIKit.hintRow(root, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -CORNER_MARGIN, 0, CORNER_MARGIN + holder.Size.Y.Offset + HINT_GAP),
	})
	UIKit.keyHint(hints, 1, LocalSettings.keyText(PlayerSettings.MENU_KEY), "MASQUER LA DÉMO")
	-- Sans les espaces de fin de keyHint (faits pour enchaîner plusieurs aides) : le texte finit au bord de la démo
	local action = hints:FindFirstChild("Action1")
	if action and action:IsA("TextLabel") then
		action.Text = "MASQUER LA DÉMO"
	end
	cornerGui, cornerHolder = gui, holder
	return holder
end

-- Cette méthode permet de lancer la démo dans le coin lorsque le joueur entre en partie sur un serveur d'entraînement ;
-- sans effet si elle tourne déjà (réapparition : la copie de la map est gardée).
local function showCorner()
	if demo then
		return
	end
	local holder = ensureCorner()
	local clips = InfosRules.demoClips(InfosContext.compose())
	local ids = {}
	for i, clip in clips do
		ids[i] = clip.id
	end
	local player = DemoPlayer.new(holder, 0, ids, true)
	UIKit.create("UIScale", { Scale = CORNER_SCALE, Parent = player.frame })
	demo = player
	local first = clips[1]
	if first then
		player.play(first.id, first.title, first.caption)
	end
	if cornerGui then
		cornerGui.Enabled = true
	end
end

-- Cette méthode permet d'arrêter la démo du coin et de libérer sa copie de la map lorsque le joueur revient au menu ou
-- la masque.
local function hideCorner()
	if demo then
		demo.destroy()
		demo = nil
	end
	if cornerGui then
		cornerGui.Enabled = false
	end
end

-- Cette méthode permet de montrer ou retirer la démo du coin lorsque l'état du client ou le réglage change : en partie
-- (vivant ou mort) sur un serveur d'entraînement, et si le joueur ne l'a pas masquée (réglage trainingDemo). Réglages
-- sauvegardés pas encore arrivés : rien (le défaut l'afficherait, puis la copie du décor serait jetée).
local function applyCorner()
	local inGame = gameState == "IN_ROUND" or gameState == "DEAD"
	if inGame and TrainingClient.isTraining() and LocalSettings.isLoaded() and LocalSettings.get().trainingDemo then
		showCorner()
	else
		hideCorner()
	end
end

-- Cette méthode permet d'adapter le coin à l'état du client (GameStateController) lorsqu'il change.
function TrainingClient.onGameState(state: string)
	gameState = state
	applyCorner()
end

-- Cette méthode permet de donner le libellé du choix du menu en partie qui masque ou affiche la démo lorsque le menu
-- s'ouvre ou qu'il vient d'être cliqué.
function TrainingClient.demoToggleLabel(): string
	return if LocalSettings.get().trainingDemo then "MASQUER LA DÉMO" else "AFFICHER LA DÉMO"
end

-- Cette méthode permet de masquer ou réafficher la démo lorsque le joueur clique dans le menu en partie : le réglage est
-- changé (et sauvegardé), le coin suit (LocalSettings.onChanged).
function TrainingClient.toggleDemo()
	LocalSettings.update({ trainingDemo = not LocalSettings.get().trainingDemo })
end

-- Réglage changé ici ou dans Réglages : le coin suit tout de suite
LocalSettings.onChanged(applyCorner)

return TrainingClient
