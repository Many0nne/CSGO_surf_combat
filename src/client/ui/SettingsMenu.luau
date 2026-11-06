-- Réglages souris et graphismes (direction « Ligne de mire »). Deux présentations du même écran : « page » à même la scène du menu, où
-- l'on règle en tirant, et « modal » sur un voile sombre (touche P en partie), sans tir ni hitmarker.
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraConfig = require(ReplicatedStorage.Shared.CameraConfig)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local MenuCursor = require(script.Parent.MenuCursor)
local MenuPage = require(script.Parent.MenuPage)
local MenuShot = require(script.Parent.MenuShot)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts
local Motion = UITheme.Motion

export type Mode = "page" | "modal"

local SettingsMenu = {}

local ROW_WIDTH = 620
local ROW_STEP = 110
local TRACK_TOP = 44
local BACKDROP_TRANSPARENCY = 0.45

local page: MenuPage.Page?
local backdrop: Frame
local open = false
local mode: Mode = "modal"
local savedMouseBehavior = Enum.MouseBehavior.LockCenter
local savedMouseIcon = false
local onClosedCallback: (() -> ())?
local pageRequest: (() -> boolean)?
local fpsCamRef: {
	setSensitivity: (number) -> (),
	getSensitivity: () -> number,
	setScopeMultiplier: (number) -> (),
	getScopeMultiplier: () -> number,
}?

-- Cette méthode permet de savoir si un geste doit tirer lorsqu'il est fait dans l'écran : jamais en partie.
local function shoots(): boolean
	return mode == "page"
end

-- Cette méthode permet de construire la ligne « libellé, valeur éditable, trace » lorsqu'un réglage est ajouté : un tir place
-- la valeur, puis la poignée (un impact) se glisse sans retirer. Renvoie la fonction qui applique une valeur.
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
		Position = UDim2.fromOffset(MenuPage.TextX, yOffset),
		Size = UDim2.fromOffset(ROW_WIDTH, ROW_STEP - 12),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIKit.text({
		Text = labelText,
		FontFace = F.DisplayMedium,
		TextSize = 22,
		TextColor3 = C.Bone,
		Size = UDim2.new(1, -110, 0, 36),
		Parent = row,
	})

	local valBox = UIKit.create("TextBox", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(90, 36),
		BackgroundTransparency = 1,
		FontFace = F.Display,
		TextSize = 26,
		TextColor3 = C.Bone,
		TextXAlignment = Enum.TextXAlignment.Right,
		ClearTextOnFocus = false,
		Text = string.format(fmt, initVal),
		Parent = row,
	})
	local valLine = UIKit.frame({
		Name = "Underline",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.Muted,
		Parent = valBox,
	})
	valBox.Focused:Connect(function()
		UIKit.tween(valLine, Motion.Hover, { BackgroundColor3 = C.Accent })
	end)

	-- Trace : zone cliquable haute contenant le trait, la traînée ambrée et l'impact
	local hit = UIKit.button({
		Name = "Track",
		Text = "",
		Position = UDim2.fromOffset(0, TRACK_TOP),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Parent = row,
	})
	local track = UIKit.frame({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = C.Bone,
		BackgroundTransparency = 0.65,
		Parent = hit,
	})
	local fill = UIKit.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Accent, Parent = track })
	local handle = UIKit.frame({
		Name = "Impact",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = C.Black,
		ZIndex = 2,
		Parent = track,
	})
	UIKit.create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = handle })
	local handleStroke = UIKit.stroke(handle, C.Bone, 2)
	local handleScale = UIKit.create("UIScale", { Parent = handle })
	UIKit.hover(hit, handleScale, { Scale = 1 }, { Scale = 1.25 })
	UIKit.hover(hit, handleStroke, { Color = C.Bone }, { Color = C.HitRed })
	hit.MouseEnter:Connect(function()
		MenuCursor.addHover(1)
	end)
	hit.MouseLeave:Connect(function()
		MenuCursor.addHover(-1)
	end)

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
		UIKit.tween(valLine, Motion.Hover, { BackgroundColor3 = C.Muted })
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
			if shoots() then
				MenuShot.fireAt(hit, inp, false)
			end
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

-- Cette méthode permet de construire la ligne « libellé, état, trace » d'un réglage oui/non lorsqu'il est ajouté : un tir
-- sur la ligne bascule l'état, la poignée (un impact) passe d'un bout à l'autre de la trace. Renvoie la fonction qui
-- applique un état.
local function makeToggle(
	parent: GuiObject,
	labelText: string,
	yOffset: number,
	onText: string,
	offText: string,
	initVal: boolean,
	onChange: (boolean) -> ()
): (boolean) -> ()
	local currentVal = initVal

	local row = UIKit.frame({
		Name = labelText,
		Position = UDim2.fromOffset(MenuPage.TextX, yOffset),
		Size = UDim2.fromOffset(ROW_WIDTH, ROW_STEP - 12),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIKit.text({
		Text = labelText,
		FontFace = F.DisplayMedium,
		TextSize = 22,
		TextColor3 = C.Bone,
		Size = UDim2.new(1, -160, 0, 36),
		Parent = row,
	})
	local valLabel = UIKit.text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(150, 36),
		FontFace = F.Display,
		TextSize = 26,
		TextColor3 = C.Bone,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	-- Toute la ligne se tire : libellé, état et trace
	local hit = UIKit.button({
		Name = "Track",
		Text = "",
		Size = UDim2.new(1, 0, 0, TRACK_TOP + 34),
		BackgroundTransparency = 1,
		Parent = row,
	})
	local track = UIKit.frame({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(0, TRACK_TOP + 17),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = C.Bone,
		BackgroundTransparency = 0.65,
		Parent = hit,
	})
	local fill = UIKit.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Accent, Parent = track })
	local handle = UIKit.frame({
		Name = "Impact",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = C.Black,
		ZIndex = 2,
		Parent = track,
	})
	UIKit.create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = handle })
	local handleStroke = UIKit.stroke(handle, C.Bone, 2)
	local handleScale = UIKit.create("UIScale", { Parent = handle })
	UIKit.hover(hit, handleScale, { Scale = 1 }, { Scale = 1.25 })
	UIKit.hover(hit, handleStroke, { Color = C.Bone }, { Color = C.HitRed })
	hit.MouseEnter:Connect(function()
		MenuCursor.addHover(1)
	end)
	hit.MouseLeave:Connect(function()
		MenuCursor.addHover(-1)
	end)

	local function applyValue(v: boolean)
		currentVal = v
		local t = if v then 1 else 0
		UIKit.tween(fill, Motion.Hover, { Size = UDim2.fromScale(t, 1) })
		UIKit.tween(handle, Motion.Hover, { Position = UDim2.fromScale(t, 0.5) })
		valLabel.Text = if v then onText else offText
		valLabel.TextColor3 = if v then C.Bone else C.Muted
		onChange(v)
	end

	hit.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 then
			applyValue(not currentVal)
			if shoots() then
				MenuShot.fireAt(hit, inp, false)
			end
		end
	end)

	applyValue(initVal)
	return applyValue
end

-- Cette méthode permet d'ouvrir ou fermer l'écran en sauvegardant puis restaurant l'état de la souris
-- lorsque le joueur appuie sur P, tire sur RÉGLAGES ou ferme l'écran.
local function setOpen(state: boolean)
	if not page or state == open then
		return
	end
	open = state
	if state then
		savedMouseBehavior = UserInputService.MouseBehavior
		savedMouseIcon = UserInputService.MouseIconEnabled
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		backdrop.Visible = mode == "modal"
		if mode == "modal" then
			backdrop.BackgroundTransparency = 1
			UIKit.tween(backdrop, Motion.Enter, { BackgroundTransparency = BACKDROP_TRANSPARENCY })
		end
		page.show()
	else
		page.hide()
		UserInputService.MouseBehavior = savedMouseBehavior
		UserInputService.MouseIconEnabled = savedMouseIcon
		if onClosedCallback then
			onClosedCallback()
		end
	end
end

-- Cette méthode permet de construire l'écran et de brancher la touche P et Échap lorsque le client démarre.
function SettingsMenu.init(fpsCam: typeof(fpsCamRef))
	if page then
		return
	end
	fpsCamRef = fpsCam

	local built = MenuPage.new("SettingsMenu", 3, MenuPage.Words.Reglages)
	page = built

	-- Le voile retient les clics pour qu'ils ne partent pas en tirs dans la partie
	backdrop = UIKit.frame({
		Name = "Backdrop",
		Active = true,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Black,
		BackgroundTransparency = BACKDROP_TRANSPARENCY,
		ZIndex = -1,
		Visible = false,
		Parent = built.gui,
	})

	makeSlider(built.group, "Sensibilité", MenuPage.ContentTop, 0.1, 5.0, CameraConfig.DEFAULT_SENS, 2, function(v)
		if fpsCamRef then
			fpsCamRef.setSensitivity(v)
		end
	end)
	makeSlider(
		built.group,
		"Sensibilité à la lunette",
		MenuPage.ContentTop + ROW_STEP,
		0.1,
		1.0,
		CameraConfig.SCOPE_SENS_MULT,
		2,
		function(v)
			if fpsCamRef then
				fpsCamRef.setScopeMultiplier(v)
			end
		end
	)
	-- Ombres du soleil sur ce poste seulement (#88) : la passe d'ombres est le plus gros coût GPU de la map
	makeToggle(
		built.group,
		"Ombres",
		MenuPage.ContentTop + 2 * ROW_STEP,
		"Activées",
		"Coupées",
		Lighting.GlobalShadows,
		function(v)
			Lighting.GlobalShadows = v
		end
	)
	built.exit(MenuPage.Words.Retour, function()
		setOpen(false)
	end, shoots)

	UserInputService.InputBegan:Connect(function(inp, gameProcessed)
		-- Échap ferme l'écran, même si Roblox traite aussi la touche (menu système)
		if inp.KeyCode == Enum.KeyCode.Escape then
			setOpen(false)
			return
		end
		if gameProcessed or inp.KeyCode ~= Enum.KeyCode.P then
			return
		end
		if open then
			setOpen(false)
		elseif not (pageRequest and pageRequest()) then
			mode = "modal"
			setOpen(true)
		end
	end)
	-- Échap ouvre le menu Roblox, qui peut capturer la touche avant nous : on ferme aussi à son ouverture
	GuiService.MenuOpened:Connect(function()
		setOpen(false)
	end)
end

-- Cette méthode permet d'enregistrer une action à exécuter à chaque fermeture de l'écran
-- lorsque le menu doit revenir à l'accueil.
function SettingsMenu.setOnClosed(callback: () -> ())
	onClosedCallback = callback
end

-- Cette méthode permet de laisser le menu traiter la touche P lorsqu'il est affiché ; le rappel renvoie true s'il s'en charge.
function SettingsMenu.setPageRequest(callback: () -> boolean)
	pageRequest = callback
end

-- Cette méthode permet d'ouvrir l'écran dans une présentation donnée lorsque le joueur tire sur RÉGLAGES.
function SettingsMenu.open(newMode: Mode)
	mode = newMode
	setOpen(true)
end

-- Cette méthode permet de fermer l'écran s'il est ouvert lorsque le joueur quitte la page ou lance une partie.
function SettingsMenu.close()
	setOpen(false)
end

-- Cette méthode permet de savoir si l'écran est ouvert lorsqu'un module doit s'y adapter.
function SettingsMenu.isOpen(): boolean
	return open
end

return SettingsMenu
