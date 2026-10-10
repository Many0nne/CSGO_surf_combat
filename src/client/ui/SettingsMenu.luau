-- Réglages souris (direction « Tactical »). Deux présentations du même panneau :
-- « page » (sous la barre de navigation, bouton SETTINGS du menu) et « modal » (centrée, touche P).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts
local T = UITheme.TextSize
local Motion = UITheme.Motion
local L = UITheme.Layout

export type Mode = "page" | "modal"

local SettingsMenu = {}

local PANEL_SIZE = Vector2.new(640, 266)

local gui: ScreenGui?
local backdrop: TextButton
local panel: CanvasGroup
local open = false
local mode: Mode = "modal"
local savedMouseBehavior = Enum.MouseBehavior.LockCenter
local savedMouseIcon = false
local onClosedCallback: (() -> ())?
local fpsCamRef: {
	setSensitivity: (number) -> (),
	getSensitivity: () -> number,
	setScopeMultiplier: (number) -> (),
	getScopeMultiplier: () -> number,
}?

-- Cette méthode permet de construire une ligne « libellé | curseur | valeur éditable » lorsqu'un réglage est ajouté ;
-- elle renvoie la fonction qui applique une valeur (bornée, formatée, transmise à `onChange`).
local function makeSlider(
	parent: GuiObject,
	labelText: string,
	yOffset: number,
	minVal: number,
	maxVal: number,
	initVal: number,
	decimals: number,
	onChange: (number) -> ()
): (number) -> ()
	local fmt = "%." .. decimals .. "f"
	local currentVal = initVal

	local row = UIKit.frame({
		Name = labelText,
		Position = UDim2.fromOffset(0, yOffset),
		Size = UDim2.new(1, 0, 0, 78),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIKit.padding(row, 0, 32, 0, 32)
	UIKit.text({
		Text = labelText,
		FontFace = F.DisplayMedium,
		TextSize = 17,
		Size = UDim2.new(0, 180, 1, 0),
		Parent = row,
	})

	local valBox = UIKit.create("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(84, 36),
		BackgroundColor3 = C.Ground,
		BorderSizePixel = 0,
		FontFace = F.MonoBold,
		TextSize = T.Body,
		TextColor3 = C.Accent,
		ClearTextOnFocus = false,
		Text = string.format(fmt, initVal),
		Parent = row,
	})
	local valStroke = UIKit.stroke(valBox, C.BorderStrong)
	valBox.Focused:Connect(function()
		UIKit.tween(valStroke, Motion.Hover, { Color = C.Accent })
	end)

	-- Piste : zone cliquable haute (24 px) contenant la barre fine, le remplissage et la poignée
	local hit = UIKit.button({
		Name = "Track",
		Text = "",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 200, 0.5, 0),
		Size = UDim2.new(1, -304, 0, 24),
		BackgroundTransparency = 1,
		Parent = row,
	})
	local track = UIKit.frame({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = C.BorderStrong,
		Parent = hit,
	})
	local fill = UIKit.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Accent, Parent = track })
	local handle = UIKit.frame({
		Name = "Handle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = C.Text,
		ZIndex = 2,
		Parent = track,
	})
	local handleScale = UIKit.create("UIScale", { Parent = handle })
	UIKit.hover(hit, handleScale, { Scale = 1 }, { Scale = 1.25 })
	UIKit.hover(hit, handle, { BackgroundColor3 = C.Text }, { BackgroundColor3 = C.Accent })

	local function applyValue(v: number)
		v = math.clamp(v, minVal, maxVal)
		currentVal = v
		local t = (v - minVal) / (maxVal - minVal)
		fill.Size = UDim2.fromScale(t, 1)
		handle.Position = UDim2.fromScale(t, 0.5)
		valBox.Text = string.format(fmt, v)
		onChange(v)
	end

	valBox.FocusLost:Connect(function()
		UIKit.tween(valStroke, Motion.Hover, { Color = C.BorderStrong })
		local num = tonumber(valBox.Text)
		if num then
			applyValue(num)
		else
			valBox.Text = string.format(fmt, currentVal)
		end
	end)

	local function valueFromMouse(inputPos: Vector3): number
		local absPos = track.AbsolutePosition
		local absSize = track.AbsoluteSize
		local t = math.clamp((inputPos.X - absPos.X) / absSize.X, 0, 1)
		return minVal + (maxVal - minVal) * t
	end

	local dragging = false
	hit.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			applyValue(valueFromMouse(inp.Position))
		end
	end)
	UserInputService.InputChanged:Connect(function(inp)
		if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
			applyValue(valueFromMouse(inp.Position))
		end
	end)
	UserInputService.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)

	applyValue(initVal)
	return applyValue
end

-- Cette méthode permet de placer le panneau selon la présentation (page sous la navigation ou modale centrée) lorsqu'il s'ouvre.
local function applyLayout()
	if mode == "page" then
		backdrop.Visible = false
		panel.AnchorPoint = Vector2.zero
		panel.Position = UDim2.fromOffset(L.Margin, L.ContentTop)
	else
		backdrop.Visible = true
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.fromScale(0.5, 0.5)
	end
	panel:SetAttribute("RestPosition", panel.Position)
end

-- Cette méthode permet d'ouvrir ou fermer le panneau en sauvegardant puis restaurant l'état de la souris
-- lorsque le joueur appuie sur P, clique sur SETTINGS ou ferme le panneau.
local function setOpen(state: boolean)
	if not gui or state == open then
		return
	end
	open = state
	if state then
		savedMouseBehavior = UserInputService.MouseBehavior
		savedMouseIcon = UserInputService.MouseIconEnabled
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		applyLayout()
		gui.Enabled = true
		if mode == "modal" then
			backdrop.BackgroundTransparency = 1
			UIKit.tween(backdrop, Motion.Enter, { BackgroundTransparency = 0.55 })
		end
		UIKit.reveal(panel, 0, 14)
	else
		gui.Enabled = false
		UserInputService.MouseBehavior = savedMouseBehavior
		UserInputService.MouseIconEnabled = savedMouseIcon
		if onClosedCallback then
			onClosedCallback()
		end
	end
end

function SettingsMenu.init(fpsCam: typeof(fpsCamRef))
	if gui then
		return
	end
	fpsCamRef = fpsCam

	local screenGui = UIKit.create("ScreenGui", {
		Name = "SettingsMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 3,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	gui = screenGui
	local root = UIKit.scaledRoot(screenGui)

	backdrop = UIKit.button({
		Name = "Backdrop",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Parent = root,
	})
	backdrop.MouseButton1Click:Connect(function()
		setOpen(false)
	end)

	panel = UIKit.create("CanvasGroup", {
		Name = "Panel",
		Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y),
		BackgroundColor3 = C.Ground,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Parent = root,
	})
	UIKit.stroke(panel, C.Border)

	UIKit.text({
		Text = "SETTINGS",
		FontFace = F.Display,
		TextSize = T.H1,
		Position = UDim2.fromOffset(32, 20),
		Size = UDim2.new(1, -120, 0, 40),
		Parent = panel,
	})
	UIKit.text({
		Text = "Souris",
		TextSize = T.Small,
		TextColor3 = C.Muted,
		Position = UDim2.fromOffset(32, 60),
		Size = UDim2.new(1, -120, 0, 20),
		Parent = panel,
	})
	local close = UIKit.closeButton(panel)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -24, 0, 24)
	close.MouseButton1Click:Connect(function()
		setOpen(false)
	end)
	for _, y in { 96, 174 } do
		UIKit.frame({
			Name = "Divider",
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = y == 96 and C.Border or C.Raised,
			Parent = panel,
		})
	end

	makeSlider(panel, "Sensitivity", 96, 0.1, 5.0, CameraConfig.DEFAULT_SENS, 2, function(v)
		if fpsCamRef then
			fpsCamRef.setSensitivity(v)
		end
	end)
	makeSlider(panel, "Scope Sens", 175, 0.1, 1.0, CameraConfig.SCOPE_SENS_MULT, 2, function(v)
		if fpsCamRef then
			fpsCamRef.setScopeMultiplier(v)
		end
	end)

	UserInputService.InputBegan:Connect(function(inp, gameProcessed)
		-- Échap ferme le panneau, même si Roblox traite aussi la touche (menu système)
		if inp.KeyCode == Enum.KeyCode.Escape then
			setOpen(false)
			return
		end
		if gameProcessed then
			return
		end
		if inp.KeyCode == Enum.KeyCode.P then
			if not open then
				mode = "modal"
			end
			setOpen(not open)
		end
	end)
	-- Échap ouvre le menu Roblox, qui peut capturer la touche avant nous : on ferme aussi à son ouverture
	GuiService.MenuOpened:Connect(function()
		setOpen(false)
	end)
end

-- Cette méthode permet d'enregistrer une action à exécuter à chaque fermeture du panneau
-- lorsque le menu doit remettre son onglet actif sur ACCUEIL.
function SettingsMenu.setOnClosed(callback: () -> ())
	onClosedCallback = callback
end

-- Cette méthode permet d'ouvrir le panneau dans une présentation donnée lorsque le menu clique sur SETTINGS.
function SettingsMenu.open(newMode: Mode)
	mode = newMode
	setOpen(true)
end

-- Cette méthode permet de fermer le panneau s'il est ouvert lorsque le joueur quitte la page (PLAY, ACCUEIL, INFOS).
function SettingsMenu.close()
	setOpen(false)
end

function SettingsMenu.isOpen(): boolean
	return open
end

return SettingsMenu
