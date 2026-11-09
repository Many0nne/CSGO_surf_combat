-- Caméra du joueur tué (#102) : reste au lieu de la mort et pivote doucement vers le tueur, suivi en direct, avec un
-- repère au-dessus de lui (nom et distance, en rouge d'impact). Sans tueur (chute), elle reste figée. Passe après
-- FPSCamera (priorité Camera + 1), qui continue de tourner tant que le personnage mort existe.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local BotCharacters = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BotCharacters"))
local DeathRules = require(script.Parent.Parent.systems.game.DeathRules)
local UIKit = require(script.Parent.Parent.ui.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts

local BIND_NAME = "DeathCamera"
-- Hauteur du repère au-dessus de la tête du tueur (studs)
local MARKER_OFFSET = 2.6
-- Distance gardée entre la caméra reculée et un mur (studs)
local WALL_MARGIN = 0.6

local DeathCamera = {}

local active = false
local marker: BillboardGui? = nil

-- Cette méthode permet de trouver le point à regarder sur le tueur (tête, sinon racine) lorsqu'une frame est dessinée.
local function killerFocus(char: Model?): BasePart?
	if not char or not char.Parent then
		return nil
	end
	local focus = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
	return if focus and focus:IsA("BasePart") then focus else nil
end

-- Cette méthode permet de construire le repère du tueur (losange, nom et distance) lorsque la caméra de mort démarre.
local function buildMarker(killerName: string): (BillboardGui, TextLabel, TextLabel)
	local gui = UIKit.create("BillboardGui", {
		Name = "KillerMarker",
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(160, 52),
		StudsOffset = Vector3.new(0, MARKER_OFFSET, 0),
		ResetOnSpawn = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	UIKit.frame({
		Name = "Diamond",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(12, 12),
		Rotation = 45,
		Parent = gui,
	})
	UIKit.stroke(gui:FindFirstChild("Diamond") :: Frame, C.HitRed, 2)
	local label, shadow = UIKit.shadowedText(gui, {
		Name = "Label",
		Text = killerName,
		FontFace = F.Display,
		TextSize = 16,
		TextColor3 = C.HitRed,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 20),
	}, 2)
	return gui, label, shadow
end

-- Cette méthode permet de trouver où poser la caméra du tué lorsqu'il meurt : reculée au-dessus de son corps
-- (DeathRules.cameraOffset), arrêtée avant un mur ; personnages et corps sont ignorés.
local function cameraSpot(eye: Vector3, look: Vector3): Vector3
	local offset = DeathRules.cameraOffset(look)
	local exclude: { Instance } = BotCharacters.allCharacters() :: any
	local ragdolls = workspace:FindFirstChild("Ragdolls")
	if ragdolls then
		table.insert(exclude, ragdolls)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(eye, offset, params)
	if hit then
		return eye + offset.Unit * math.max(hit.Distance - WALL_MARGIN, 0)
	end
	return eye + offset
end

-- Cette méthode permet de prendre la main sur la caméra lorsque le joueur local meurt : elle recule au-dessus du corps
-- et pivote vers le personnage du tueur, joueur ou bot (nil pour une chute : orientation figée) ; killerName est le
-- nom affiché sur son repère (« BOT MARCEL » pour un bot).
function DeathCamera.start(killer: Model?, killerName: string?)
	DeathCamera.stop()
	active = true
	local cam = workspace.CurrentCamera
	local position = cam.CFrame.Position
	local origin = cameraSpot(position, cam.CFrame.LookVector)
	local current = cam.CFrame

	local label, shadow
	local markerName = string.upper(killerName or (killer and killer.Name) or "")
	if killer then
		local gui
		gui, label, shadow = buildMarker(markerName)
		marker = gui
	end

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		if not active then
			return
		end
		cam.CameraType = Enum.CameraType.Scriptable
		local alpha = DeathRules.turnAlpha(dt)
		-- Recul progressif depuis les yeux, pas de saut
		position = position:Lerp(origin, alpha)
		local focus = killerFocus(killer)
		if focus then
			local target = CFrame.lookAt(position, focus.Position)
			current = current:Lerp(target, alpha)
			if marker then
				marker.Adornee = focus
				marker.Enabled = true
				local text = string.format(
					"%s · %s",
					markerName,
					DeathRules.formatDistance((focus.Position - origin).Magnitude)
				)
				label.Text = text
				shadow.Text = text
			end
		elseif marker then
			marker.Enabled = false
		end
		cam.CFrame = CFrame.new(position) * current.Rotation
	end)
end

-- Cette méthode permet de rendre la caméra à FPSCamera lorsque le joueur réapparaît ou quitte la partie.
function DeathCamera.stop()
	if not active and not marker then
		return
	end
	active = false
	RunService:UnbindFromRenderStep(BIND_NAME)
	if marker then
		marker:Destroy()
		marker = nil
	end
end

return DeathCamera
