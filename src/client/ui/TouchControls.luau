-- Commandes tactiles, minimum jouable (#276) : joystick de déplacement qui naît sous le pouce à gauche, glisser à droite
-- pour viser (FPSCamera.addTouchLook), boutons d'action à droite (tir, saut, accroupi, lunette, recharge, arme suivante)
-- et en haut (menu, classement). Les boutons passent par les mêmes actions que le clavier et la manette (InputModule).
-- Affiché seulement en partie (HUD de jeu, menu fermé) et si le tactile est le dernier appareil utilisé (InputDevice).
-- Les contrôles tactiles de Roblox sont coupés (StarterPlayer.DevTouchMovementMode = Scriptable, default.project.json).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage.Shared.UITheme)
local FPSCamera = require(script.Parent.Parent.camera.FPSCamera)
local InputDevice = require(script.Parent.Parent.input.InputDevice)
local InputModule = require(script.Parent.Parent.input.InputModule)
local HUDRules = require(script.Parent.HUDRules)
local HUDState = require(script.Parent.HUDState)
local InGameMenu = require(script.Parent.InGameMenu)
local RoundHUD = require(script.Parent.RoundHUD)
local UIKit = require(script.Parent.UIKit)
local WeaponBar = require(script.Parent.WeaponBar)

local C = UITheme.Colors
local F = UITheme.Fonts

local TouchControls = {}

local STICK_RADIUS = 60 -- px (repère 720 px de haut) : course du pouce pour un stick à fond
local KNOB_SIZE = 50
local BUTTON_TRANSPARENCY = 0.45

local gui: ScreenGui?
local root: Frame?

-- Cette méthode permet de convertir une position d'écran (px réels) dans le repère de la racine mise à l'échelle
-- lorsque le joystick suit un doigt.
local function toRoot(position: Vector3): Vector2
	local frame = root :: Frame
	local scale = frame.AbsoluteSize.Y / 720
	return (Vector2.new(position.X, position.Y) - frame.AbsolutePosition) / scale
end

-- Cette méthode permet d'actionner l'arme en main (tir) lorsque le bouton TIR est touché ; WeaponSystem décide si elle
-- peut tirer (Tool.Activated, comme le clic gauche et R2), puis répète le tir tant que le bouton est tenu (#473).
local function fire()
	InputModule.setTouchPointer("fire", true)
	local character = Players.LocalPlayer.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool then
		tool:Activate()
	end
end

-- Cette méthode permet de créer un bouton rond qui appelle `onDown` / `onUp` au toucher et au relâchement lorsque les
-- commandes sont construites ; `position` place son centre, `size` son diamètre (px).
local function button(text: string, position: UDim2, size: number, onDown: () -> (), onUp: (() -> ())?)
	local frame = UIKit.frame({
		Name = text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = C.Scrim,
		BackgroundTransparency = BUTTON_TRANSPARENCY,
		Active = true,
		ZIndex = 3,
		Parent = root,
	})
	UIKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
	local stroke = UIKit.create("UIStroke", { Color = C.Bone, Thickness = 2, Parent = frame })
	UIKit.create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextColor3 = C.Bone,
		FontFace = F.Display,
		TextSize = math.max(12, math.floor(size / 4.5)),
		ZIndex = 4,
		Parent = frame,
	})
	local touches: { [InputObject]: true } = {}
	frame.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if next(touches) == nil then
			stroke.Color = C.HitRed
			onDown()
		end
		touches[input] = true
	end)
	frame.InputEnded:Connect(function(input)
		if not touches[input] then
			return
		end
		touches[input] = nil
		if next(touches) == nil then
			stroke.Color = C.Bone
			if onUp then
				onUp()
			end
		end
	end)
end

-- Cette méthode permet de construire le joystick de gauche lorsque les commandes sont construites : il apparaît sous le
-- pouce, la distance au point de départ (bornée à STICK_RADIUS) donne la position du stick (InputModule.setTouchMove).
local function buildStick()
	local zone = UIKit.frame({
		Name = "MoveZone",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.4, 1),
		Active = true,
		ZIndex = 1,
		Parent = root,
	})
	local ring = UIKit.frame({
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(STICK_RADIUS * 2, STICK_RADIUS * 2),
		BackgroundColor3 = C.Scrim,
		BackgroundTransparency = 0.6,
		Visible = false,
		ZIndex = 2,
		Parent = root,
	})
	UIKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ring })
	UIKit.create("UIStroke", { Color = C.Bone, Thickness = 2, Transparency = 0.3, Parent = ring })
	local knob = UIKit.frame({
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE),
		BackgroundColor3 = C.Bone,
		BackgroundTransparency = 0.3,
		ZIndex = 3,
		Parent = ring,
	})
	UIKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = knob })

	local finger: InputObject?
	local origin = Vector2.zero
	zone.InputBegan:Connect(function(input)
		if finger or input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		finger = input
		origin = toRoot(input.Position)
		ring.Position = UDim2.fromOffset(origin.X, origin.Y)
		knob.Position = UDim2.fromScale(0.5, 0.5)
		ring.Visible = true
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input ~= finger then
			return
		end
		local offset = toRoot(input.Position) - origin
		if offset.Magnitude > STICK_RADIUS then
			offset = offset.Unit * STICK_RADIUS
		end
		knob.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
		-- Écran : y vers le bas ; stick : y en avant
		InputModule.setTouchMove(Vector2.new(offset.X, -offset.Y) / STICK_RADIUS)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input ~= finger then
			return
		end
		finger = nil
		ring.Visible = false
		InputModule.setTouchMove(Vector2.zero)
	end)
end

-- Cette méthode permet de construire la zone de visée (droite de l'écran, sous les boutons) lorsque les commandes sont
-- construites : chaque glisser de doigt fait tourner la caméra (px réels, comme la souris).
local function buildLook()
	local zone = UIKit.frame({
		Name = "LookZone",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.4, 0),
		Size = UDim2.fromScale(0.6, 1),
		Active = true,
		ZIndex = 1,
		Parent = root,
	})
	local fingers: { [InputObject]: Vector3 } = {}
	zone.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			fingers[input] = input.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local last = fingers[input]
		if last then
			local delta = input.Position - last
			fingers[input] = input.Position
			FPSCamera.addTouchLook(Vector2.new(delta.X, delta.Y))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		fingers[input] = nil
	end)
end

-- Cette méthode permet d'afficher les commandes seulement en partie au tactile lorsque l'état du HUD ou l'appareil
-- changent ; masquées, plus rien n'est tenu (joystick au repos, boutons relâchés).
local function update()
	if not gui then
		return
	end
	local hud = HUDState.get()
	local show = InputDevice.get() == "touch" and HUDRules.gameHudVisible(hud.gameState) and not hud.menuOpen
	if gui.Enabled and not show then
		InputModule.setTouchMove(Vector2.zero)
		for _, action in { "jump", "crouch" } do
			InputModule.setTouchAction(action :: any, false)
		end
		InputModule.setTouchPointer("fire", false)
		InputModule.setTouchPointer("aim", false)
		RoundHUD.setTouchScoreboard(false)
	end
	gui.Enabled = show
end

-- Cette méthode permet de construire les commandes tactiles lorsque le client démarre sur un appareil tactile ; rien
-- n'est créé sans écran tactile.
function TouchControls.init()
	if gui or not UserInputService.TouchEnabled then
		return
	end
	local screenGui = UIKit.create("ScreenGui", {
		Name = "TouchControls",
		Enabled = false,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1, -- au-dessus du HUD (0), sous le menu en partie (2)
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	gui = screenGui
	root = UIKit.scaledRoot(screenGui)
	buildStick()
	buildLook()
	-- Grappe d'actions à droite, à mi-hauteur (la barre d'armes et les munitions occupent le bas à droite)
	button("TIR", UDim2.new(1, -110, 0.5, 40), 100, fire, function()
		InputModule.setTouchPointer("fire", false)
	end)
	button("SAUT", UDim2.new(1, -230, 0.5, 110), 76, function()
		InputModule.setTouchAction("jump", true)
	end, function()
		InputModule.setTouchAction("jump", false)
	end)
	button("ACCR.", UDim2.new(1, -240, 0.5, 0), 60, function()
		InputModule.setTouchAction("crouch", true)
	end, function()
		InputModule.setTouchAction("crouch", false)
	end)
	button("VISÉE", UDim2.new(1, -120, 0.5, -70), 60, function()
		InputModule.setTouchPointer("aim", true)
	end, function()
		InputModule.setTouchPointer("aim", false)
	end)
	button("RECH.", UDim2.new(1, -40, 0.5, -90), 54, function()
		InputModule.setTouchAction("reload", true)
	end, function()
		InputModule.setTouchAction("reload", false)
	end)
	button("ARME", UDim2.new(1, -40, 0.5, -170), 54, WeaponBar.cycleNext)
	-- En haut à droite : menu en partie et classement tenu
	button("MENU", UDim2.new(1, -50, 0, 50), 56, InGameMenu.pressMenuKey)
	button("SCORES", UDim2.new(1, -120, 0, 50), 56, function()
		RoundHUD.setTouchScoreboard(true)
	end, function()
		RoundHUD.setTouchScoreboard(false)
	end)
	HUDState.onChanged(update)
	InputDevice.onChanged(update)
	update()
end

return TouchControls
