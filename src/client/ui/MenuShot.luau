-- Choix en texte à ombre décalée des écrans du menu (onglets et flèches de l'accueil, choix des écrans secondaires) :
-- un clic à la souris système déclenche l'action, sans tir ni impact (seule l'arme de la vitrine se tire, #130).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
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

local DISABLED_TRANSPARENCY = 0.6

local busy = false

-- Cette méthode permet de remettre le menu à neuf (clics de nouveau acceptés) lorsque le joueur y revient.
function MenuShot.reset()
	busy = false
end

-- Cette méthode permet de savoir si une action longue (JOUER) est en cours lorsqu'un nouveau clic arrive.
function MenuShot.isBusy(): boolean
	return busy
end

type ChoiceProps = {
	action: () -> (),
	onFired: (() -> ())?,
	delay: number?,
	locks: boolean?,
}

-- Cette méthode permet de brancher survol et clic sur un bouton du menu lorsqu'un choix est créé ;
-- `paint(hovering, selected, enabled)` redessine le bouton à chaque changement d'état.
local function bindChoice(button: GuiButton, props: ChoiceProps, paint: (boolean, boolean, boolean) -> ()): Choice
	local hovering, selected, enabled = false, false, true

	local function refresh()
		paint(hovering, selected, enabled)
	end

	button.MouseEnter:Connect(function()
		hovering = true
		refresh()
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		refresh()
	end)
	button.Activated:Connect(function()
		if not enabled or busy then
			return
		end
		if props.onFired then
			props.onFired()
		end
		if not props.delay then
			props.action()
			return
		end
		busy = true
		task.delay(props.delay, function()
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
			refresh()
		end,
		reset = function()
			hovering = false
			refresh()
		end,
	}
end

-- Cette méthode permet de créer un choix en texte à ombre décalée (onglets, flèches, actions des écrans secondaires)
-- lorsqu'un écran est construit : rouge d'impact au survol, `selectedColor` pour l'élément actif. Le bouton prend la
-- taille de son texte ; `onFired` et `delay` servent aux actions longues (JOUER), `locks` les garde exclusives.
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
	return bindChoice(button, props, function(hovering: boolean, selected: boolean, enabled: boolean)
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
