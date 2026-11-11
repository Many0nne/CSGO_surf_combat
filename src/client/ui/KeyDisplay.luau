-- Affichage des touches (#197, direction « Ligne de mire ») : grille façon clavier en bas au centre de l'écran, une case par
-- touche (directions et Espace en « simple », plus accroupi et actions de jeu en « full »). Case au repos : fond sombre
-- translucide, trait et texte os atténués ; touche enfoncée : case os pleine, texte noir. Libellés selon la disposition
-- du clavier (LocalSettings.keyText). Affiché selon HUDRules.keyDisplayVisible : mode actif, HUD de jeu visible (donc ni
-- menu ni mort) et écran Réglages fermé. Pas de CanvasGroup (cf. docs/ui.md) : de simples Frame et TextLabel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage.Shared.UITheme)
local LocalSettings = require(script.Parent.Parent.systems.settings.LocalSettings)
local HUDRules = require(script.Parent.HUDRules)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts

local KEY_SIZE = 40 -- px, côté d'une case (résolution de référence, 720 px de haut)
local KEY_GAP = 4 -- px entre deux cases
local BOTTOM_MARGIN = 40 -- px entre la grille et le bas de l'écran
local REST_TRANSPARENCY = 0.35 -- fond d'une case au repos
local TEXT_SIZE = 18
local TEXT_SIZE_LONG = 13 -- libellés de plus de deux caractères dans une case simple (CTRL, MAJ)
local TEXT_SIZE_WIDE = 16 -- libellé de plus de deux caractères dans une case large (ESPACE)

local KeyDisplay = {}

type KeyView = { entry: HUDRules.KeyDisplayEntry, frame: Frame, stroke: UIStroke, label: TextLabel, down: boolean }

local gui: ScreenGui?
local grid: Frame?
local views: { KeyView } = {}
local builtMode: string? -- mode dont la grille est construite
local hudVisible = false -- règle « HUD de jeu visible » (HUDRules), posée par GameStateController
local menuOpen = false -- écran Réglages ouvert (SettingsMenu)

-- Cette méthode permet de savoir si une touche ou un bouton de souris est enfoncé lorsque la grille est rafraîchie.
local function isDown(entry: HUDRules.KeyDisplayEntry): boolean
	if entry.mouse then
		local button = if entry.mouse == 1 then Enum.UserInputType.MouseButton1 else Enum.UserInputType.MouseButton2
		return UserInputService:IsMouseButtonPressed(button)
	end
	-- Un champ de texte focalisé (chat) capte le clavier : le jeu ne reçoit pas ces touches, elles ne s'allument pas
	if UserInputService:GetFocusedTextBox() then
		return false
	end
	local names: { string } = entry.keys or {}
	for _, name in names do
		if UserInputService:IsKeyDown((Enum.KeyCode :: any)[name]) then
			return true
		end
	end
	return false
end

-- Cette méthode permet de peindre une case au repos ou enfoncée lorsque l'état de sa touche change.
local function paint(view: KeyView, down: boolean)
	view.down = down
	view.frame.BackgroundColor3 = if down then C.Bone else C.Scrim
	view.frame.BackgroundTransparency = if down then 0 else REST_TRANSPARENCY
	view.stroke.Color = if down then C.Bone else C.BoneMuted
	view.label.TextColor3 = if down then C.Black else C.BoneMuted
end

-- Cette méthode permet de donner le libellé d'une case lorsque la grille est construite : libellé fixe (ESPACE, CTRL, M1),
-- sinon celui de la touche sur la disposition du clavier du joueur (AZERTY : Z Q S D).
local function labelOf(entry: HUDRules.KeyDisplayEntry): string
	if entry.label then
		return entry.label
	end
	return LocalSettings.keyText(entry.keys and entry.keys[1] or "")
end

-- Cette méthode permet de reconstruire la grille lorsque le mode d'affichage change : une case par entrée du mode,
-- grille centrée en bas de l'écran.
local function build(mode: string)
	local container = grid
	if not container then
		return
	end
	for _, view in views do
		view.frame:Destroy()
	end
	views = {}
	builtMode = mode
	local entries = HUDRules.keyDisplayEntries(mode)
	local columns, rows = 0, 0
	for _, entry in entries do
		columns = math.max(columns, entry.col + entry.width)
		rows = math.max(rows, entry.row + 1)
	end
	container.Size =
		UDim2.fromOffset(columns * (KEY_SIZE + KEY_GAP) - KEY_GAP, math.max(rows, 1) * (KEY_SIZE + KEY_GAP) - KEY_GAP)
	for _, entry in entries do
		local frame = UIKit.frame({
			Name = entry.id,
			Position = UDim2.fromOffset(entry.col * (KEY_SIZE + KEY_GAP), entry.row * (KEY_SIZE + KEY_GAP)),
			Size = UDim2.fromOffset(entry.width * (KEY_SIZE + KEY_GAP) - KEY_GAP, KEY_SIZE),
			Parent = container,
		})
		local stroke = UIKit.stroke(frame, C.BoneMuted, 1)
		local text = labelOf(entry)
		local label = UIKit.text({
			Name = "Label",
			Text = text,
			FontFace = F.Display,
			TextSize = if (utf8.len(text) or #text) <= 2
				then TEXT_SIZE
				elseif entry.width > 1 then TEXT_SIZE_WIDE
				else TEXT_SIZE_LONG,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Parent = frame,
		})
		local view: KeyView = { entry = entry, frame = frame, stroke = stroke, label = label, down = false }
		paint(view, false)
		table.insert(views, view)
	end
end

-- Cette méthode permet d'afficher ou de masquer la grille, et de la reconstruire si le mode a changé, lorsque le réglage,
-- le HUD ou l'écran Réglages changent.
local function update()
	if not gui then
		return
	end
	local mode = LocalSettings.get().keyDisplay
	gui.Enabled = HUDRules.keyDisplayVisible(mode, hudVisible, menuOpen)
	if mode ~= builtMode then
		build(mode)
		return
	end
	-- Libellés relus à chaque changement de réglage : la disposition du clavier peut avoir changé depuis la construction
	for _, view in views do
		local text = labelOf(view.entry)
		if view.label.Text ~= text then
			view.label.Text = text
		end
	end
end

-- Cette méthode permet de mettre les cases à jour lorsque le HUD est affiché : une case ne se repeint que si l'état de sa
-- touche a changé depuis la frame précédente.
local function poll()
	if not (gui and gui.Enabled) then
		return
	end
	for _, view in views do
		local down = isDown(view.entry)
		if down ~= view.down then
			paint(view, down)
		end
	end
end

-- Cette méthode permet de savoir si le HUD de jeu est affiché lorsque l'état client change (règle HUDRules.gameHudVisible).
function KeyDisplay.setHudVisible(show: boolean)
	hudVisible = show
	update()
end

-- Cette méthode permet de masquer les touches lorsque l'écran Réglages s'ouvre ou se ferme (SettingsMenu).
function KeyDisplay.setMenuOpen(isOpen: boolean)
	menuOpen = isOpen
	update()
end

-- Cette méthode permet de construire l'affichage des touches et de suivre le réglage lorsque le client démarre ; le réglage
-- sauvegardé s'applique dès son arrivée du serveur, sans relancer.
function KeyDisplay.init()
	if gui then
		return
	end
	local screenGui = UIKit.create("ScreenGui", {
		Name = "KeyDisplay",
		Enabled = false,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 0,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	gui = screenGui
	local root = UIKit.scaledRoot(screenGui)
	grid = UIKit.frame({
		Name = "Grid",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN),
		Size = UDim2.fromOffset(0, 0),
		Parent = root,
	})

	LocalSettings.onChanged(update)
	RunService.Heartbeat:Connect(poll)
	update()
end

return KeyDisplay
