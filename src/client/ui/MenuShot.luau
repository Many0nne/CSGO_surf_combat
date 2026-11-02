-- Tir dans les écrans du menu : l'AWP de MenuScene fait feu sur l'élément choisi, l'impact reste, puis l'action se déclenche.
-- Fournit aussi les choix en images usées (tools/ui/make_menu_type.py) communs à l'accueil, Réglages, Infos et Feedback.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local MenuScene = require(script.Parent.Parent.systems.game.MenuScene)
local MenuCursor = require(script.Parent.MenuCursor)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local Motion = UITheme.Motion

export type Word = { image: string, width: number, height: number }
export type Choice = {
	button: ImageButton,
	setSelected: (boolean) -> (),
	setEnabled: (boolean) -> (),
	reset: () -> (),
}

local MenuShot = {}

local ACTION_DELAY = 0.16 -- l'impact se voit avant l'ouverture de l'écran demandé
local HOVER_SHIFT = 10
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

-- Cette méthode permet de créer un choix en image à tirer (survol rouge et décalé) lorsqu'un écran du menu est construit ;
-- `shoots` peut couper le tir (Réglages en partie), `onFired` et `delay` servent aux actions longues, `locks` les garde exclusives.
function MenuShot.choice(props: {
	word: Word,
	height: number,
	position: UDim2,
	parent: Instance,
	action: () -> (),
	shoots: (() -> boolean)?,
	onFired: (() -> ())?,
	delay: number?,
	locks: boolean?,
}): Choice
	local rest = props.position
	local button = UIKit.create("ImageButton", {
		Name = props.word.image,
		Image = props.word.image,
		ImageColor3 = C.White,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = rest,
		Size = UDim2.fromOffset(math.round(props.height * props.word.width / props.word.height), props.height),
		Parent = props.parent,
	})
	local hovering, counted, selected, enabled = false, false, false, true

	local function refresh()
		local lit = enabled and (hovering or selected)
		UIKit.tween(button, Motion.Hover, {
			ImageColor3 = lit and C.HitRed or C.White,
			ImageTransparency = enabled and 0 or DISABLED_TRANSPARENCY,
			Position = lit and rest + UDim2.fromOffset(HOVER_SHIFT, 0) or rest,
		})
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

return MenuShot
