-- Tir dans les écrans du menu : l'AWP de MenuScene fait feu sur l'élément choisi, l'impact reste, puis l'action se déclenche.
-- Fournit les choix en texte à ombre décalée (onglets et flèches de l'accueil, choix des écrans secondaires).
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local MenuScene = require(script.Parent.Parent.systems.game.MenuScene)
local MenuCursor = require(script.Parent.MenuCursor)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local Motion = UITheme.Motion

export type Choice = {
	button: GuiButton,
	setSelected: (boolean) -> (),
	setEnabled: (boolean) -> (),
	reset: () -> (),
}

local MenuShot = {}

local ACTION_DELAY = 0.16 -- l'impact se voit avant l'ouverture de l'écran demandé
local HOLE_SIZE = 13
local MAX_HOLES = 14 -- par écran, le plus ancien disparaît
local DISABLED_TRANSPARENCY = 0.6

local layers: { Frame } = {}
local activeLayer: Frame?
local busy = false

-- Cette méthode permet de calculer où part le tir lorsqu'un élément est activé : à la souris, sinon au centre de l'élément.
local function aimPoint(element: GuiObject, input: InputObject?): (number, number)
	if input and input.UserInputType == Enum.UserInputType.MouseButton1 then
		local mouse = UserInputService:GetMouseLocation()
		return mouse.X, mouse.Y
	end
	-- Tactile ou manette : AbsolutePosition exclut la barre du haut
	local top = GuiService:GetGuiInset().Y
	return element.AbsolutePosition.X + element.AbsoluteSize.X / 2,
		element.AbsolutePosition.Y + element.AbsoluteSize.Y / 2 + top
end

-- Cette méthode permet de laisser un impact de balle sur l'écran actif lorsqu'un tir touche un élément du menu.
local function addHole(x: number, y: number)
	local layer = activeLayer
	if not layer then
		return
	end
	local existing = layer:GetChildren()
	if #existing >= MAX_HOLES then
		existing[1]:Destroy()
	end
	local hole = UIKit.frame({
		Name = "BulletHole",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(HOLE_SIZE, HOLE_SIZE),
		BackgroundColor3 = C.Black,
		Parent = layer,
	})
	UIKit.create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = hole })
	UIKit.create("UIStroke", { Color = C.HitRed, Thickness = 1, Transparency = 0.35, Parent = hole })
end

-- Cette méthode permet de créer le calque d'impacts d'un écran lorsqu'il est construit.
function MenuShot.createLayer(parent: Instance): Frame
	local layer = UIKit.frame({
		Name = "Holes",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = parent,
	})
	table.insert(layers, layer)
	return layer
end

-- Cette méthode permet de désigner l'écran qui reçoit les impacts lorsqu'il devient visible.
function MenuShot.useLayer(layer: Frame)
	activeLayer = layer
end

-- Cette méthode permet de remettre le menu à neuf (impacts effacés, tir possible) lorsque le joueur y revient.
function MenuShot.reset()
	busy = false
	for _, layer in layers do
		layer:ClearAllChildren()
	end
end

-- Cette méthode permet de savoir si une action est déjà en cours lorsqu'un nouveau tir est demandé.
function MenuShot.isBusy(): boolean
	return busy
end

-- Cette méthode permet de tirer sur un élément du menu lorsqu'il est activé, avec ou sans impact à l'écran ;
-- renvoie false si une action est déjà en cours.
function MenuShot.fireAt(element: GuiObject, input: InputObject?, withHole: boolean): boolean
	if busy then
		return false
	end
	local x, y = aimPoint(element, input)
	local _, hasHit = MenuScene.shoot(x, y, true)
	MenuCursor.kick(hasHit)
	if withHole then
		addHole(x, y)
	end
	return true
end

type ShotProps = {
	action: () -> (),
	shoots: (() -> boolean)?,
	onFired: (() -> ())?,
	delay: number?,
	locks: boolean?,
}

-- Cette méthode permet de brancher survol, hitmarker et tir sur un bouton du menu lorsqu'un choix est créé ;
-- `paint(hovering, selected, enabled)` redessine le bouton à chaque changement d'état.
local function bindShot(button: GuiButton, props: ShotProps, paint: (boolean, boolean, boolean) -> ()): Choice
	local hovering, counted, selected, enabled = false, false, false, true

	local function refresh()
		paint(hovering, selected, enabled)
	end

	local function setCounted(value: boolean)
		if value ~= counted then
			counted = value
			MenuCursor.addHover(value and 1 or -1)
		end
	end

	button.MouseEnter:Connect(function()
		hovering = true
		setCounted(enabled)
		refresh()
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		setCounted(false)
		refresh()
	end)
	button.Activated:Connect(function(input: InputObject)
		if not enabled then
			return
		end
		if props.shoots and not props.shoots() then
			props.action()
			return
		end
		if not MenuShot.fireAt(button, input, true) then
			return
		end
		busy = true
		if props.onFired then
			props.onFired()
		end
		task.delay(props.delay or ACTION_DELAY, function()
			if not props.locks then
				busy = false
			end
			props.action()
		end)
	end)

	return {
		button = button,
		setSelected = function(value: boolean)
			selected = value
			refresh()
		end,
		setEnabled = function(value: boolean)
			enabled = value
			setCounted(enabled and hovering)
			refresh()
		end,
		reset = function()
			hovering = false
			setCounted(false)
			refresh()
		end,
	}
end

-- Cette méthode permet de créer un choix en texte à ombre décalée (onglets, flèches, actions des écrans secondaires)
-- lorsqu'un écran est construit : rouge d'impact au survol, `selectedColor` pour l'élément actif. Le bouton prend la
-- taille de son texte ; `shoots` peut couper le tir (Réglages en partie), `onFired` et `delay` servent aux actions
-- longues, `locks` les garde exclusives.
function MenuShot.textChoice(props: {
	text: string,
	font: Font,
	size: number,
	color: Color3,
	selectedColor: Color3?,
	parent: Instance,
	position: UDim2?,
	anchor: Vector2?,
	layoutOrder: number?,
	action: () -> (),
	shoots: (() -> boolean)?,
	onFired: (() -> ())?,
	delay: number?,
	locks: boolean?,
}): Choice
	local button = UIKit.create("TextButton", {
		Name = props.text,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		AnchorPoint = props.anchor or Vector2.zero,
		Position = props.position or UDim2.new(),
		LayoutOrder = props.layoutOrder or 0,
		Parent = props.parent,
	})
	local label, shadow = UIKit.shadowedText(button, {
		Name = "Label",
		Text = props.text,
		FontFace = props.font,
		TextSize = props.size,
		TextColor3 = props.color,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		ZIndex = 2,
	}, if props.size >= 26 then 3 else 2)
	shadow.ZIndex = 1
	local shadowRest = shadow.TextTransparency
	return bindShot(button, props, function(hovering: boolean, selected: boolean, enabled: boolean)
		local color = if enabled and hovering
			then C.HitRed
			elseif selected then props.selectedColor or props.color
			else props.color
		UIKit.tween(label, Motion.Hover, {
			TextColor3 = color,
			TextTransparency = enabled and 0 or DISABLED_TRANSPARENCY,
		})
		UIKit.tween(shadow, Motion.Hover, { TextTransparency = enabled and shadowRest or 0.9 })
	end)
end

return MenuShot
