-- Affichage des touches (#197, direction « Ligne de mire », DA #406) : mini-clavier en bas au centre de l'écran, une
-- touche par action (directions et Espace en « simple », plus accroupi et actions de jeu en « full »). Le clavier est une
-- vraie petite scène 3D vue de face et plongeante (ViewportFrame, HUDRules.KEY_DISPLAY_VIEW) : keycaps os évasés posés sur une plaque sombre, Espace, Ctrl,
-- Maj et la souris en ambre ; enfoncée, la touche descend dans la plaque et passe au rouge d'impact. Les libellés sont des
-- TextLabel droits posés par projection sur le dessus de chaque touche (un ViewportFrame ne rend pas de SurfaceGui).
-- Libellés selon la disposition du clavier (LocalSettings.keyText). Affiché selon HUDRules.keyDisplayVisible appliquée à
-- HUDState (#223) : mode actif, HUD de jeu visible (donc ni menu ni mort) et menu en partie fermé. Mode actif : réglage du
-- joueur, ou « full » pour un débutant (HUDRules.keyDisplayMode, BeginnerState, #291).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PerfMarkers = require(ReplicatedStorage.Shared.PerfMarkers)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local InputDevice = require(script.Parent.Parent.input.InputDevice)
local InputModule = require(script.Parent.Parent.input.InputModule)
local BeginnerState = require(script.Parent.Parent.systems.game.BeginnerState)
local LocalSettings = require(script.Parent.Parent.systems.settings.LocalSettings)
local HUDRules = require(script.Parent.HUDRules)
local HUDState = require(script.Parent.HUDState)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts

local KEY_SIZE = HUDRules.KEY_DISPLAY_KEY -- px, côté d'une touche (résolution de référence, 720 px de haut)
local KEY_GAP = HUDRules.KEY_DISPLAY_GAP -- px entre deux touches
local TEXT_SIZE = 18
local TEXT_SIZE_LONG = 13 -- libellés de plus de deux caractères dans une touche simple (CTRL, MAJ)
local TEXT_SIZE_WIDE = 16 -- libellé de plus de deux caractères dans une touche large (ESPACE)

-- Scène du clavier (#406) : un stud = un pas de grille (touche + écart) ; point de vue et emprise dans HUDRules
local VIEW = HUDRules.KEY_DISPLAY_VIEW
local STEP = KEY_SIZE + KEY_GAP -- px
local CAP = KEY_SIZE / STEP -- studs, côté d'une touche
local CAP_TOP_HEIGHT = 0.06 -- studs, épaisseur du dessus, plus clair, posé sur la jupe
local CAP_HEIGHT = VIEW.capHeight - CAP_TOP_HEIGHT -- studs, hauteur de la jupe (flancs) du keycap
local CAP_TOP_INSET = 0.08 -- studs, retrait du dessus sur la jupe (keycap évasé vers le bas)
local CAP_RADIUS = 0.12 -- studs, arrondi des coins
local CAP_PRESS = 0.2 -- studs dont la touche s'enfonce (moins que la plaque n'est épaisse)
local CAP_SKIRT_DARKEN = 0.22 -- jupe : couleur du dessus assombrie d'autant vers le noir
local PLATE_COLOR = C.Scrim
local PLATE_TRANSPARENCY = 0.25
local CAMERA_FOV = 2 -- degrés : champ étroit, caméra lointaine, presque sans perspective
local LIGHT_DIRECTION = Vector3.new(0.25, -1, -0.5) -- sens de la lumière : dessus clair, face avant plus sombre
local LIGHT_COLOR = Color3.fromRGB(150, 150, 150)
local AMBIENT = Color3.fromRGB(140, 140, 140)

-- Couleurs d'un keycap : dessus, jupe, libellé
type CapColors = { face: Color3, skirt: Color3, legend: Color3 }

-- Cette méthode permet de décrire les couleurs d'un keycap lorsque ses états sont posés : jupe tirée du dessus.
local function capColors(face: Color3, legend: Color3): CapColors
	return { face = face, skirt = face:Lerp(C.Black, CAP_SKIRT_DARKEN), legend = legend }
end

local CAP_KEY = capColors(C.Bone, C.Scrim)
-- Espace, Ctrl, Maj et la souris : les « modificateurs » du clavier, en ambre
local CAP_MOD = capColors(C.Accent, C.Scrim)
local CAP_DOWN = capColors(C.HitRed, C.Bone)
local CAP_MODIFIERS = { jump = true, crouch = true, walk = true, fire = true, aim = true }
-- Libellés A, B, X, Y aux couleurs de la manette (#276), foncées pour rester lisibles sur l'os et l'ambre
local PAD_TINTS = {
	ButtonA = Color3.fromRGB(20, 110, 40),
	ButtonB = Color3.fromRGB(150, 25, 25),
	ButtonX = Color3.fromRGB(25, 70, 160),
	ButtonY = Color3.fromRGB(130, 95, 0),
}

local KeyDisplay = {}

-- Touche construite : libellé et fonction qui peint la touche au repos ou enfoncée
export type Keycap = { label: TextLabel, paint: (boolean) -> () }

type KeyView = {
	entry: HUDRules.KeyDisplayEntry,
	codes: { Enum.KeyCode }, -- touches du clavier de l'entrée, résolues une fois à la construction
	pad: Enum.KeyCode?, -- bouton de manette de l'entrée (#276), nil pour une direction
	label: TextLabel,
	paint: (boolean) -> (),
	down: boolean,
}

local gui: ScreenGui?
local grid: Frame?
local root: Frame? -- racine mise à l'échelle (UIKit.scaledRoot), repère des marges de la grille
local views: { KeyView } = {}
local builtMode: string? -- mode dont la grille est construite

-- Cette méthode permet de savoir si une touche est enfoncée à la manette ou au tactile (#276) lorsque la grille est
-- rafraîchie : directions selon le stick (InputModule.getMoveAxes), actions tenues, sinon bouton de la manette.
local function isDownPad(view: KeyView): boolean
	local id = view.entry.id
	if id == "forward" or id == "back" or id == "left" or id == "right" then
		local fwd, rgt = InputModule.getMoveAxes()
		local axis = if id == "forward" or id == "back" then fwd else rgt
		local sign = if id == "forward" or id == "right" then 1 else -1
		return axis * sign > 0.3
	end
	if InputModule.isHeld(id) then
		return true
	end
	return view.pad ~= nil and UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, view.pad)
end

-- Cette méthode permet de savoir si une touche ou un bouton de souris est enfoncé lorsque la grille est rafraîchie ;
-- `typing` : un champ de texte (chat) a le focus et capte le clavier, le jeu ne reçoit pas ces touches.
local function isDown(view: KeyView, typing: boolean): boolean
	if InputDevice.get() ~= "keyboard" then
		return isDownPad(view)
	end
	local mouse = view.entry.mouse
	if mouse then
		local button = (Enum.UserInputType :: any)["MouseButton" .. mouse]
		return UserInputService:IsMouseButtonPressed(button)
	end
	if typing then
		return false
	end
	for _, code in view.codes do
		if UserInputService:IsKeyDown(code) then
			return true
		end
	end
	return false
end

-- Cette méthode permet de peindre une touche au repos ou enfoncée lorsque l'état de sa touche change.
local function paint(view: KeyView, down: boolean)
	view.down = down
	view.paint(down)
	local pad = view.entry.pad
	if not down and pad and InputDevice.get() == "gamepad" and (PAD_TINTS :: any)[pad] then
		view.label.TextColor3 = (PAD_TINTS :: any)[pad]
	end
end

-- Cette méthode permet de donner le libellé d'une touche lorsque la grille est construite : libellé fixe (ESPACE, CTRL,
-- M1), sinon celui de la touche sur la disposition du clavier du joueur (AZERTY : Z Q S D).
local function labelOf(entry: HUDRules.KeyDisplayEntry): string
	if InputDevice.get() == "gamepad" then
		return HUDRules.gamepadLabel(entry)
	end
	if entry.label then
		return entry.label
	end
	return LocalSettings.keyText(entry.keys and entry.keys[1] or "")
end

-- Cette méthode permet de choisir la taille du libellé d'une touche lorsque la grille est construite : lettre, libellé
-- long dans une touche simple (CTRL, MAJ) ou dans une touche large (ESPACE).
local function textSizeOf(entry: HUDRules.KeyDisplayEntry, text: string): number
	if (utf8.len(text) or #text) <= 2 then
		return TEXT_SIZE
	end
	return if entry.width > 1 then TEXT_SIZE_WIDE else TEXT_SIZE_LONG
end

-- Cette méthode permet de construire une pièce de la scène du clavier lorsqu'un keycap ou la plaque est construit.
local function piece(parent: Instance, size: Vector3, cframe: CFrame, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
	return part
end

-- Cette méthode permet de construire un pavé aux coins arrondis (deux pavés croisés et quatre cylindres debout) lorsqu'un
-- keycap ou la plaque est construit ; `center` est le centre du pavé, renvoie ses pièces.
local function roundedSlab(parent: Instance, center: Vector3, width: number, depth: number, height: number): { Part }
	local radius = math.min(CAP_RADIUS, width / 2, depth / 2)
	local parts = {
		piece(parent, Vector3.new(width, height, depth - 2 * radius), CFrame.new(center)),
		piece(parent, Vector3.new(width - 2 * radius, height, depth), CFrame.new(center)),
	}
	local upright = CFrame.Angles(0, 0, math.pi / 2)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local offset = Vector3.new(sx * (width / 2 - radius), 0, sz * (depth / 2 - radius))
			local post = Vector3.new(height, 2 * radius, 2 * radius)
			table.insert(parts, piece(parent, post, CFrame.new(center + offset) * upright, Enum.PartType.Cylinder))
		end
	end
	return parts
end

-- Cette méthode permet de construire le mini-clavier 3D d'une liste de touches lorsque le HUD ou une démo (écran
-- Apprendre, aide de première partie, #285) montre des touches : redimensionne `container` à la taille du clavier
-- projeté (HUDRules.keyDisplayFootprint) et renvoie, dans l'ordre des entrées, le libellé et le peintre de chaque touche.
function KeyDisplay.buildKeyboard(container: Frame, entries: { HUDRules.KeyDisplayEntry }): { Keycap }
	local width, height = HUDRules.keyDisplayFootprint(entries)
	container.Size = UDim2.fromOffset(width, height)
	if #entries == 0 then
		return {}
	end
	local viewport = UIKit.create("ViewportFrame", {
		Name = "Keyboard",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = AMBIENT,
		LightColor = LIGHT_COLOR,
		LightDirection = LIGHT_DIRECTION,
		ZIndex = 1,
		Parent = container,
	}) :: ViewportFrame
	local camera = Instance.new("Camera")
	camera.FieldOfView = CAMERA_FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- Emprise des touches (studs) : x vers la droite, z vers le joueur, dessus de la plaque à y = 0
	local gapStuds = KEY_GAP / STEP
	local minX, maxX, maxZ = math.huge, -math.huge, 0
	for _, entry in entries do
		minX = math.min(minX, entry.col)
		maxX = math.max(maxX, entry.col + entry.width - gapStuds)
		maxZ = math.max(maxZ, entry.row + CAP)
	end
	local margin, plateHeight = VIEW.plateMargin, VIEW.plateHeight
	local plateCenter = Vector3.new((minX + maxX) / 2, -plateHeight / 2, maxZ / 2)
	local plateWidth, plateDepth = maxX - minX + 2 * margin, maxZ + 2 * margin
	for _, part in roundedSlab(viewport, plateCenter, plateWidth, plateDepth, plateHeight) do
		part.Color = PLATE_COLOR
		part.Transparency = PLATE_TRANSPARENCY
	end

	-- Cadrage : de face et plongeant, la caméra vise le centre du clavier projeté (même emprise que keyDisplayFootprint)
	local pitch = math.rad(VIEW.pitch)
	local direction = Vector3.new(0, math.sin(pitch), math.cos(pitch))
	local up = Vector3.new(0, math.cos(pitch), -math.sin(pitch))
	local top = VIEW.capHeight
	local loY = -plateHeight * math.cos(pitch) - (maxZ + margin) * math.sin(pitch) -- bas de la face avant de la plaque
	local hiY = top * math.cos(pitch) + margin * math.sin(pitch) -- haut du bord arrière, au niveau des touches
	local target = Vector3.new(plateCenter.X, 0, 0) + up * (loY + hiY) / 2
	local pxPerStud = STEP * VIEW.scale
	local tanHalf = math.tan(math.rad(CAMERA_FOV / 2))
	local distance = (height / pxPerStud) / 2 / tanHalf
	camera.CFrame = CFrame.lookAt(target + direction * distance, target)
	local aspect = width / height

	-- Cette méthode permet de projeter un point de la scène en px du clavier lorsqu'un libellé est posé sur sa touche.
	local function project(point: Vector3): Vector2
		local local3 = camera.CFrame:PointToObjectSpace(point)
		local depth = -local3.Z * tanHalf
		return Vector2.new((local3.X / (depth * aspect) + 1) / 2 * width, (1 - local3.Y / depth) / 2 * height)
	end

	local keycaps = {}
	for _, entry in entries do
		local capWidth = entry.width - gapStuds
		local center = Vector3.new(entry.col + capWidth / 2, 0, entry.row + CAP / 2)
		local skirt = roundedSlab(viewport, center + Vector3.new(0, CAP_HEIGHT / 2, 0), capWidth, CAP, CAP_HEIGHT)
		local face = roundedSlab(
			viewport,
			center + Vector3.new(0, CAP_HEIGHT + CAP_TOP_HEIGHT / 2, 0),
			capWidth - 2 * CAP_TOP_INSET,
			CAP - 2 * CAP_TOP_INSET,
			CAP_TOP_HEIGHT
		)
		local rests: { [Part]: CFrame } = {}
		for _, part in skirt do
			rests[part] = part.CFrame
		end
		for _, part in face do
			rests[part] = part.CFrame
		end
		local text = labelOf(entry)
		local label = UIKit.text({
			Name = entry.id,
			Text = text,
			FontFace = F.Display,
			TextSize = textSizeOf(entry, text),
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(capWidth * STEP, KEY_SIZE),
			ZIndex = 2,
			Parent = container,
		})
		local rest = if CAP_MODIFIERS[entry.id] then CAP_MOD else CAP_KEY
		table.insert(keycaps, {
			label = label,
			-- Cette méthode permet de peindre la touche lorsque son état change : enfoncée, elle descend dans la plaque.
			paint = function(down: boolean)
				local colors = if down then CAP_DOWN else rest
				local sink = Vector3.new(0, if down then -CAP_PRESS else 0, 0)
				for part, cframe in rests do
					part.CFrame = cframe + sink
				end
				for _, part in skirt do
					part.Color = colors.skirt
				end
				for _, part in face do
					part.Color = colors.face
				end
				local at = project(center + Vector3.new(0, top, 0) + sink)
				label.Position = UDim2.fromOffset(at.X, at.Y)
				label.TextColor3 = colors.legend
			end,
		})
	end
	for _, keycap in keycaps do
		keycap.paint(false)
	end
	return keycaps
end

-- Cette méthode permet de poser la grille en bas au centre lorsque la taille de l'écran ou de la grille change : au-dessus
-- du compteur de munitions si elle l'atteindrait sur un écran étroit (HUDRules.keyDisplayBottom, #247).
local function place()
	local container, scaled, screenGui = grid, root, gui
	if not (container and scaled and screenGui) then
		return
	end
	-- Largeur vue dans le repère de la racine : écran x Size de la racine (1 / échelle, posée par UIKit.scaledRoot)
	local width = screenGui.AbsoluteSize.X * scaled.Size.X.Scale
	local bottom = HUDRules.keyDisplayBottom(width, container.Size.X.Offset)
	container.Position = UDim2.new(0.5, 0, 1, -bottom)
end

-- Cette méthode permet de reconstruire la grille lorsque le mode d'affichage change : un mini-clavier 3D des entrées du
-- mode, centré en bas de l'écran.
local function build(mode: string)
	local container = grid
	if not container then
		return
	end
	container:ClearAllChildren()
	views = {}
	builtMode = mode
	local entries = HUDRules.keyDisplayEntries(mode)
	local keycaps = KeyDisplay.buildKeyboard(container, entries)
	place()
	for index, entry in entries do
		local codes = {}
		for _, name in entry.keys or {} :: { string } do
			table.insert(codes, (Enum.KeyCode :: any)[name])
		end
		local keycap = keycaps[index]
		local view: KeyView = {
			entry = entry,
			codes = codes,
			pad = if entry.pad then (Enum.KeyCode :: any)[entry.pad] else nil,
			label = keycap.label,
			paint = keycap.paint,
			down = false,
		}
		table.insert(views, view)
		paint(view, false)
	end
end

-- Cette méthode permet d'afficher ou de masquer la grille, et de la reconstruire si le mode a changé, lorsque le réglage
-- ou l'état du HUD (HUDState) changent ; grille masquée, les touches repartent au repos (pas de touche restée enfoncée).
local function update()
	if not gui then
		return
	end
	-- Débutant (#291) : mode complet quel que soit le réglage, jamais réécrit
	local mode = HUDRules.keyDisplayMode(LocalSettings.get().keyDisplay, BeginnerState.isBeginner())
	gui.Enabled = HUDRules.keyDisplayVisible(HUDState.get(), mode)
	if mode ~= builtMode then
		build(mode)
	elseif gui.Enabled then
		place() -- un ScreenGui masqué a pu manquer un redimensionnement
	end
	if not gui.Enabled then
		for _, view in views do
			if view.down then
				paint(view, false)
			end
		end
	end
end

-- Cette méthode permet de relire les libellés des touches lorsque le HUD de jeu apparaît : la disposition du clavier a pu
-- changer depuis la construction de la grille.
local function refreshLabels()
	for _, view in views do
		local text = labelOf(view.entry)
		if view.label.Text ~= text then
			view.label.Text = text
			UIKit.setHudTextSize(view.label, textSizeOf(view.entry, text)) -- plancher du HUD réduit (#282)
		end
	end
end

-- Cette méthode permet de mettre les touches à jour lorsque le HUD est affiché : une touche ne se repeint que si son état
-- a changé depuis la frame précédente.
local function poll()
	if not (gui and gui.Enabled) then
		return
	end
	local typing = UserInputService:GetFocusedTextBox() ~= nil
	for _, view in views do
		local down = isDown(view, typing)
		if down ~= view.down then
			paint(view, down)
		end
	end
end

-- Cette méthode permet d'appliquer l'état du HUD lorsqu'il change, et de relire les libellés quand le HUD de jeu apparaît.
local function onHudChanged(hud: HUDState.Snapshot, previous: HUDState.Snapshot)
	update()
	if HUDRules.gameHudVisible(hud.gameState) and not HUDRules.gameHudVisible(previous.gameState) then
		refreshLabels()
	end
end

-- Cette méthode permet de construire l'affichage des touches et de suivre le réglage lorsque le client démarre ; le réglage
-- sauvegardé s'applique dès son arrivée du serveur, sans relancer.
function KeyDisplay.init()
	if gui then
		return
	end
	local screenGui = UIKit.create("ScreenGui", {
		Name = "KeyDisplay",
		Enabled = false,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, -- libellés au-dessus du clavier 3D
		DisplayOrder = 0,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	gui = screenGui
	local scaled = UIKit.scaledRoot(screenGui, true)
	root = scaled
	grid = UIKit.frame({
		Name = "Grid",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -HUDRules.KEY_DISPLAY_BOTTOM),
		Size = UDim2.fromOffset(0, 0),
		Parent = scaled,
	})
	-- Fenêtre redimensionnée : largeur seule (AbsoluteSize, échelle inchangée) ou hauteur (attribut Scale, posé par
	-- UIKit.scaledRoot après la taille de la racine) ; différé pour lire une racine à jour
	-- Cette méthode permet de replacer la grille à la frame suivante lorsque la taille ou l'échelle de l'écran change.
	local function replace()
		task.defer(place)
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(replace)
	scaled:GetAttributeChangedSignal("Scale"):Connect(replace)
	LocalSettings.onChanged(update)
	BeginnerState.onChanged(update)
	HUDState.onChanged(onHudChanged)
	-- Clavier ↔ manette (#276) : libellés et teintes suivent le dernier appareil utilisé
	InputDevice.onChanged(function()
		refreshLabels()
		for _, view in views do
			paint(view, view.down)
		end
	end)
	RunService.Heartbeat:Connect(PerfMarkers.wrap("touches", poll))
	update()
end

return KeyDisplay
