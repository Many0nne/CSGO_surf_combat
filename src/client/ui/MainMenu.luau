local MainMenu = {}

local BG_COLOR     = Color3.fromRGB(12, 14, 20)
local CARD_COLOR   = Color3.fromRGB(20, 24, 34)
local TEXT_COLOR   = Color3.fromRGB(210, 215, 225)
local ACCENT_COLOR = Color3.fromRGB(55, 85, 140)
local MUTED_COLOR  = Color3.fromRGB(100, 110, 130)
local FONT        = Enum.Font.GothamBold
local FONT_LIGHT  = Enum.Font.Gotham

local gui: ScreenGui
local onPlayCallback:  (() -> ())?
local onInfosCallback: (() -> ())?

local function makeButton(parent: Frame, text: string, color: Color3, yPos: UDim2): TextButton
	local btn = Instance.new("TextButton")
	btn.Size            = UDim2.new(1, 0, 0, 44)
	btn.Position        = yPos
	btn.BackgroundColor3 = color
	btn.BorderSizePixel = 0
	btn.Text            = text
	btn.TextColor3      = TEXT_COLOR
	btn.Font            = FONT
	btn.TextSize        = 16
	btn.AutoButtonColor = true
	btn.Parent          = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent       = btn
	return btn
end

function MainMenu.init(onPlay: () -> (), onInfos: () -> ())
	onPlayCallback  = onPlay
	onInfosCallback = onInfos

	gui = Instance.new("ScreenGui")
	gui.Name            = "MainMenu"
	gui.ResetOnSpawn    = false
	gui.IgnoreGuiInset  = true
	gui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
	gui.Parent          = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

	-- Fond plein écran
	local bg = Instance.new("Frame")
	bg.Size             = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = BG_COLOR
	bg.BorderSizePixel  = 0
	bg.Parent           = gui

	-- Carte centrale
	local card = Instance.new("Frame")
	card.Size               = UDim2.new(0, 280, 0, 264)
	card.AnchorPoint        = Vector2.new(0.5, 0.5)
	card.Position           = UDim2.fromScale(0.5, 0.5)
	card.BackgroundColor3   = CARD_COLOR
	card.BorderSizePixel    = 0
	card.Parent             = bg
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 8)
	cardCorner.Parent       = card

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft   = UDim.new(0, 28)
	padding.PaddingRight  = UDim.new(0, 28)
	padding.PaddingTop    = UDim.new(0, 28)
	padding.PaddingBottom = UDim.new(0, 28)
	padding.Parent        = card

	-- Titre
	local title = Instance.new("TextLabel")
	title.Size            = UDim2.new(1, 0, 0, 40)
	title.Position        = UDim2.fromOffset(0, 0)
	title.BackgroundTransparency = 1
	title.Text            = "SURF FFA"
	title.TextColor3      = TEXT_COLOR
	title.Font            = FONT
	title.TextSize        = 28
	title.TextXAlignment  = Enum.TextXAlignment.Left
	title.Parent          = card

	-- Sous-titre
	local sub = Instance.new("TextLabel")
	sub.Size              = UDim2.new(1, 0, 0, 20)
	sub.Position          = UDim2.fromOffset(0, 46)
	sub.BackgroundTransparency = 1
	sub.Text              = "Free-for-all · Surf movement"
	sub.TextColor3        = MUTED_COLOR
	sub.Font              = FONT_LIGHT
	sub.TextSize          = 13
	sub.TextXAlignment    = Enum.TextXAlignment.Left
	sub.Parent            = card

	-- Boutons
	local playBtn  = makeButton(card, "JOUER", ACCENT_COLOR, UDim2.fromOffset(0, 100))
	local infosBtn = makeButton(card, "INFOS", Color3.fromRGB(35, 40, 55), UDim2.fromOffset(0, 154))

	playBtn.MouseButton1Click:Connect(function()
		if onPlayCallback then onPlayCallback() end
	end)
	infosBtn.MouseButton1Click:Connect(function()
		if onInfosCallback then onInfosCallback() end
	end)

	-- Version
	local ver = Instance.new("TextLabel")
	ver.Size              = UDim2.new(1, -16, 0, 18)
	ver.AnchorPoint       = Vector2.new(0, 1)
	ver.Position          = UDim2.new(0, 8, 1, -6)
	ver.BackgroundTransparency = 1
	ver.Text              = "v0.1"
	ver.TextColor3        = Color3.fromRGB(60, 65, 80)
	ver.Font              = FONT_LIGHT
	ver.TextSize          = 11
	ver.TextXAlignment    = Enum.TextXAlignment.Right
	ver.Parent            = bg
end

function MainMenu.show()
	if gui then gui.Enabled = true end
end

function MainMenu.hide()
	if gui then gui.Enabled = false end
end

return MainMenu
