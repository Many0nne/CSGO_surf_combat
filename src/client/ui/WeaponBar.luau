-- WeaponBar (direction « Ligne de mire ») : barre d'armes maison en bas à droite, en miroir du compteur de vitesse.
-- Remplace le Backpack Roblox (désactivé dans init.client) : par arme, silhouette tirée de son viewmodel, nom et touche.
-- Texte droit (seul le compteur de vitesse est penché). L'arme en main est en os avec son numéro et un trait rouge
-- d'impact. Toute la barre s'estompe peu après un changement d'arme et revient au suivant.
-- Équipement : touches 1 à 9, molette, toucher d'un emplacement (tactile), L1/R1 (manette). Règles pures dans HUDRules.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local UIKit = require(script.Parent.UIKit)
local HUDRules = require(script.Parent.HUDRules)

local C = UITheme.Colors
local F = UITheme.Fonts
local Motion = UITheme.Motion

local SLOT_SIZE = Vector2.new(300, 60)
local SLOT_STEP = 64
local KEY_WIDTH = 34 -- colonne du numéro, à droite de la silhouette et du nom
local ICON_ACTIVE = Vector2.new(170, 50)
local ICON_IDLE = Vector2.new(130, 40)
local ICON_ASPECT = ICON_ACTIVE.X / ICON_ACTIVE.Y
local ICON_FOV = 15
local IDLE_TRANSPARENCY = 0.3 -- silhouette, nom et numéro d'une arme pas en main
local SCRIM_SIZE = Vector2.new(460, 250)
local SCRIM_SHOWN = 0.15
local MARGIN = Vector2.new(44, 40)

local SLOT_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

type Slot = {
	tool: Tool,
	frame: Frame,
	icon: Frame,
	silhouette: ViewportFrame,
	name: TextLabel,
	key: TextLabel,
	tick: Frame,
}

local WeaponBar = {}

local player = Players.LocalPlayer
local gui: ScreenGui?
local root: Frame
local bar: Frame
local scrim: ImageLabel
local slots: { Slot } = {}
local alive = false
local faded = false -- barre masquée après le délai sans changement d'arme
local fadeToken = 0
local watchConns: { RBXScriptConnection } = {}

-- Cette méthode permet de lister les outils du joueur (sac et main) dans l'ordre des emplacements lorsque la barre se met à jour.
local function collectTools(): { Tool }
	local byName: { [string]: Tool } = {}
	local names = {}
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and not byName[child.Name] then
					byName[child.Name] = child
					table.insert(names, child.Name)
				end
			end
		end
	end
	local tools = {}
	for _, name in HUDRules.slotOrder(names) do
		table.insert(tools, byName[name])
	end
	return tools
end

-- Cette méthode permet de renvoyer l'outil en main lorsque la barre doit savoir quel emplacement est actif.
local function equippedTool(): Tool?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Tool")
end

-- Cette méthode permet de dessiner la silhouette plate d'une arme, de profil, à partir des pièces de son viewmodel
-- (bras exclus) lorsqu'un emplacement est créé ; la teinte vient ensuite de ImageColor3.
local function buildSilhouette(tool: Tool, parent: Frame): ViewportFrame
	local viewport = UIKit.create("ViewportFrame", {
		Name = "Silhouette",
		BackgroundTransparency = 1,
		Ambient = C.White,
		LightColor = C.Black,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	local viewModels = ReplicatedStorage:FindFirstChild("ViewModels")
	local source = viewModels and viewModels:FindFirstChild(tool:GetAttribute("ViewmodelName") or tool.Name)
	if not source then
		return viewport
	end
	local model = Instance.new("Model")
	for _, part in source:GetChildren() do
		if part:IsA("MeshPart") and part.Transparency < 1 then
			local copy = part:Clone()
			copy:ClearAllChildren()
			copy.TextureID = ""
			copy.Color = C.White
			copy.Material = Enum.Material.SmoothPlastic
			copy.Anchored = true
			copy.Parent = model
		end
	end
	model.Parent = viewport
	if #model:GetChildren() == 0 then
		return viewport
	end

	-- Vue de profil : axe le plus long à l'horizontale, regard le long de l'axe le plus mince
	local frame, size = model:GetBoundingBox()
	local axes = {
		{ length = size.X, dir = frame.RightVector },
		{ length = size.Y, dir = frame.UpVector },
		{ length = size.Z, dir = frame.LookVector },
	}
	table.sort(axes, function(a, b)
		return a.length > b.length
	end)
	local halfHeight = math.max(axes[1].length / 2 / ICON_ASPECT, axes[2].length / 2) * 1.08
	local distance = halfHeight / math.tan(math.rad(ICON_FOV / 2)) + axes[3].length
	local camera = UIKit.create("Camera", { FieldOfView = ICON_FOV, Parent = viewport })
	camera.CFrame = CFrame.lookAt(frame.Position + axes[3].dir * distance, frame.Position, axes[2].dir)
	viewport.CurrentCamera = camera
	return viewport
end

-- Cette méthode permet d'équiper l'arme d'un emplacement lorsque le joueur la choisit (touche, molette, toucher, manette).
local function equipSlot(index: number?)
	local slot = index and slots[index]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (slot and humanoid and alive and humanoid.Health > 0) or slot.tool.Parent == character then
		return
	end
	humanoid:EquipTool(slot.tool)
end

-- Cette méthode permet de passer à l'arme voisine lorsque la molette ou L1/R1 est utilisée.
local function cycle(step: number)
	local current = nil
	local tool = equippedTool()
	for i, slot in slots do
		if slot.tool == tool then
			current = i
		end
	end
	equipSlot(HUDRules.cycleSlot(current, #slots, step))
end

-- Cette méthode permet de construire un emplacement (silhouette, nom, numéro, trait, zone de toucher) lorsque la liste
-- des armes change.
local function buildSlot(tool: Tool, index: number): Slot
	-- Pas de CanvasGroup : sa GroupTransparency est ignorée quand Roblox retombe sur le rendu simple (qualité, mémoire)
	local group = UIKit.frame({
		Name = "Slot" .. index,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, (index - 1) * SLOT_STEP),
		Size = UDim2.fromOffset(SLOT_SIZE.X, SLOT_SIZE.Y),
		Parent = bar,
	})
	local icon = UIKit.frame({
		Name = "Icon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -KEY_WIDTH, 0, 0),
		Size = UDim2.fromOffset(ICON_IDLE.X, ICON_IDLE.Y),
		Parent = group,
	})
	local slot: Slot = {
		tool = tool,
		frame = group,
		icon = icon,
		silhouette = buildSilhouette(tool, icon),
		name = UIKit.text({
			Name = "Name",
			Text = HUDRules.weaponLabel(tool.Name),
			FontFace = F.DisplayMedium,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(ICON_ACTIVE.X, 22),
			Parent = group,
		}),
		key = UIKit.text({
			Name = "Key",
			Text = tostring(index),
			FontFace = F.Display,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(KEY_WIDTH - 8, 32),
			Parent = group,
		}),
		tick = UIKit.frame({
			Name = "Tick",
			BackgroundColor3 = C.HitRed,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 46),
			Size = UDim2.fromOffset(KEY_WIDTH - 8, 4),
			Parent = group,
		}),
	}
	local touch = UIKit.create("TextButton", {
		Name = "Touch",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = group,
	})
	touch.Activated:Connect(function()
		equipSlot(index)
	end)
	return slot
end

-- Cette méthode permet d'appliquer l'aspect de chaque emplacement (actif, au repos, ou masqué une fois la barre estompée)
-- lorsque l'arme en main change ou que la barre s'estompe ; `animate` fait glisser tailles et transparences.
local function applySlots(animate: boolean)
	local tool = equippedTool()
	for _, slot in slots do
		local active = slot.tool == tool
		local color = active and C.Bone or C.BoneMuted
		local transparency = faded and 1 or (active and 0 or IDLE_TRANSPARENCY)
		local iconSize = active and ICON_ACTIVE or ICON_IDLE
		local info = faded and Motion.Exit or Motion.Hover
		local goals: { [Instance]: { [string]: any } } = {
			[slot.icon] = { Size = UDim2.fromOffset(iconSize.X, iconSize.Y) },
			[slot.silhouette] = { ImageTransparency = transparency },
			[slot.name] = { TextTransparency = transparency },
			[slot.key] = { TextTransparency = transparency },
			[slot.tick] = { BackgroundTransparency = faded and 1 or 0 },
		}
		for inst, goal in goals do
			if animate then
				UIKit.tween(inst, info, goal)
			else
				for key, value in goal do
					(inst :: any)[key] = value
				end
			end
		end
		slot.silhouette.ImageColor3 = color
		slot.name.FontFace = active and F.Display or F.DisplayMedium
		slot.name.TextSize = active and 22 or 16
		slot.name.TextColor3 = color
		slot.name.Position = UDim2.new(1, -KEY_WIDTH, 0, iconSize.Y - 10)
		slot.key.TextSize = active and 30 or 20
		slot.key.TextColor3 = active and C.HitRed or color
		slot.key.Position = UDim2.new(1, 0, 0, active and 10 or 12)
		slot.tick.Visible = active
	end
end

-- Cette méthode permet de montrer toute la barre puis de la masquer entièrement après un délai sans changement
-- lorsque l'arme ou la liste des armes change.
local function wake(animate: boolean)
	fadeToken += 1
	local token = fadeToken
	faded = false
	applySlots(animate)
	UIKit.tween(scrim, Motion.Hover, { ImageTransparency = SCRIM_SHOWN })
	task.delay(HUDRules.WEAPON_BAR_FADE_DELAY, function()
		if token ~= fadeToken then
			return
		end
		faded = true
		applySlots(true)
		UIKit.tween(scrim, Motion.Exit, { ImageTransparency = 1 })
	end)
end

-- Cette méthode permet de reconstruire les emplacements si les outils ont changé (autres noms, ou nouvelles instances après
-- une réapparition), puis de rafraîchir l'aspect, lorsqu'un outil entre ou sort du sac ou de la main.
local function refresh()
	if not gui then
		return
	end
	local tools = collectTools()
	local rebuilt = #tools ~= #slots
	for i, tool in tools do
		if not slots[i] or slots[i].tool ~= tool then
			rebuilt = true
		end
	end
	if rebuilt then
		for _, slot in slots do
			slot.frame:Destroy()
		end
		slots = {}
		for i, tool in tools do
			slots[i] = buildSlot(tool, i)
		end
		bar.Size = UDim2.fromOffset(SLOT_SIZE.X, math.max(#tools, 1) * SLOT_STEP)
	end
	gui.Enabled = alive and #slots > 0
	wake(not rebuilt)
end

-- Cette méthode permet de suivre les entrées et sorties d'outils du sac et du personnage lorsqu'un personnage apparaît.
local function watchCharacter(character: Model)
	for _, conn in watchConns do
		conn:Disconnect()
	end
	watchConns = {}
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	-- Un personnage mort (sac recréé avant la réapparition) ne réactive pas la barre
	alive = humanoid.Health > 0 and character.Parent ~= nil
	local function onChange(child: Instance)
		if child:IsA("Tool") then
			task.defer(refresh)
		end
	end
	for _, container in { character, player:FindFirstChildOfClass("Backpack") } do
		table.insert(watchConns, container.ChildAdded:Connect(onChange))
		table.insert(watchConns, container.ChildRemoved:Connect(onChange))
	end
	table.insert(
		watchConns,
		humanoid.Died:Connect(function()
			alive = false
			refresh()
		end)
	)
	refresh()
end

-- Cette méthode permet de traduire les entrées (touches, manette) en changement d'arme lorsque la barre est affichée.
local function onInputBegan(input: InputObject, processed: boolean)
	if processed or not (gui and gui.Enabled) then
		return
	end
	local index = SLOT_KEYS[input.KeyCode]
	if index then
		equipSlot(index)
	elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
		cycle(1)
	elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
		cycle(-1)
	end
end

-- Cette méthode permet de changer d'arme à la molette lorsque la barre est affichée : vers le haut, arme précédente.
local function onInputChanged(input: InputObject, processed: boolean)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel or not (gui and gui.Enabled) then
		return
	end
	cycle(input.Position.Z > 0 and -1 or 1)
end

function WeaponBar.init()
	if gui then
		return
	end
	local screenGui = UIKit.create("ScreenGui", {
		Name = "WeaponBar",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	gui = screenGui
	root = UIKit.scaledRoot(screenGui)
	scrim = UIKit.cornerScrim(root, "BottomRight", SCRIM_SIZE, SCRIM_SHOWN)
	bar = UIKit.frame({
		Name = "Bar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -MARGIN.X, 1, -MARGIN.Y),
		Size = UDim2.fromOffset(SLOT_SIZE.X, SLOT_STEP),
		Parent = root,
	})

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(onInputChanged)
	player.CharacterAdded:Connect(watchCharacter)
	-- Le sac est recréé à chaque apparition : suivre le nouveau s'il arrive après le personnage
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") and player.Character then
			watchCharacter(player.Character)
		end
	end)
	player.CharacterRemoving:Connect(function()
		alive = false
		refresh()
	end)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
end

return WeaponBar
