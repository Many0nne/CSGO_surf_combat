-- AmmoCounter (direction « Ligne de mire ») : compteur de munitions « chargeur / réserve » en bas à droite, à gauche de la
-- barre d'armes. Chiffre du chargeur en gros (os, ombre décalée), réserve plus petite et atténuée, libellé ambré.
-- Chargeur vide : chiffre en rouge d'impact. Masqué pour une arme sans chargeur (couteau) et hors partie (HUDRules).
-- Pas de CanvasGroup (flou à basse qualité, cf. docs/ui.md) : de simples Frame et TextLabel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local HUDRules = require(script.Parent.HUDRules)
local UIKit = require(script.Parent.UIKit)
local WeaponSystem = require(script.Parent.Parent.systems.weapon.WeaponSystem)

local C = UITheme.Colors
local F = UITheme.Fonts

local MARGIN = Vector2.new(44 + 250, 40) -- à gauche de la barre d'armes (44 px de marge, 250 px de contenu)
local SIZE = Vector2.new(190, 78)
local SHADOW = 3

local AmmoCounter = {}

local player = Players.LocalPlayer
local gui: ScreenGui?
local magazineText: TextLabel
local magazineShadow: TextLabel
local reserveText: TextLabel
local reserveShadow: TextLabel
local hudVisible = false -- règle « HUD de jeu visible » (HUDRules), posée par GameStateController
local lastAmmo: number? = nil
local lastReserve: number? = nil

-- Cette méthode permet de mettre à jour les textes et la visibilité lorsque les munitions de l'arme en main changent.
local function update()
	if not gui then
		return
	end
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local ammo, reserve = WeaponSystem.getAmmo(tool)
	gui.Enabled = hudVisible and ammo ~= nil
	if ammo == lastAmmo and reserve == lastReserve then
		return
	end
	lastAmmo, lastReserve = ammo, reserve
	if not ammo then
		return
	end
	magazineText.Text = tostring(ammo)
	magazineShadow.Text = tostring(ammo)
	magazineText.TextColor3 = if ammo <= 0 then C.HitRed else C.Bone
	reserveText.Text = HUDRules.formatReserve(reserve)
	reserveShadow.Text = reserveText.Text
end

-- Cette méthode permet de masquer le compteur hors partie lorsque le HUD de jeu change de visibilité.
function AmmoCounter.setVisible(show: boolean)
	hudVisible = show
	update()
end

function AmmoCounter.init()
	if gui then
		return
	end
	local screenGui = UIKit.create("ScreenGui", {
		Name = "AmmoCounter",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	gui = screenGui
	local root = UIKit.scaledRoot(screenGui)
	local box = UIKit.frame({
		Name = "Box",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -MARGIN.X, 1, -MARGIN.Y),
		Size = UDim2.fromOffset(SIZE.X, SIZE.Y),
		Parent = root,
	})
	UIKit.text({
		Name = "Label",
		Text = "MUNITIONS",
		FontFace = F.DisplayMedium,
		TextSize = 14,
		TextColor3 = C.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(SIZE.X, 16),
		Parent = box,
	})
	magazineText, magazineShadow = UIKit.shadowedText(box, {
		Name = "Magazine",
		FontFace = F.Display,
		TextSize = 56,
		TextColor3 = C.Bone,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -78, 1, 0),
		Size = UDim2.fromOffset(100, 60),
	}, SHADOW)
	reserveText, reserveShadow = UIKit.shadowedText(box, {
		Name = "Reserve",
		FontFace = F.DisplayMedium,
		TextSize = 26,
		TextColor3 = C.BoneMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(1, -72, 1, -6),
		Size = UDim2.fromOffset(72, 30),
	}, SHADOW)

	RunService.Heartbeat:Connect(update)
end

return AmmoCounter
