-- Affichage des touches (#197, direction « Ligne de mire », DA #229) : grille façon clavier en bas au centre de l'écran,
-- une touche par action (directions et Espace en « simple », plus accroupi et actions de jeu en « full »). Chaque touche
-- est un keycap en relief : dessus os bombé, rebord plus sombre sur les côtés et dessous, ombre portée ; Espace, Ctrl,
-- Maj et la souris en ambre ; enfoncée, la touche s'enfonce et passe au rouge d'impact. Libellés selon la disposition
-- du clavier (LocalSettings.keyText). Affiché selon HUDRules.keyDisplayVisible appliquée à HUDState (#223) : mode actif,
-- HUD de jeu visible (donc ni menu ni mort) et menu en partie fermé. Pas de CanvasGroup (cf. docs/ui.md) : de simples
-- Frame et TextLabel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(ReplicatedStorage.Shared.UITheme)
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

-- Relief du keycap, vu de face et d'un peu au-dessus
local CAP_SIDE = 4 -- px de rebord visibles à gauche et à droite du dessus
local CAP_TOP = 2 -- px de rebord au-dessus du dessus
local CAP_FRONT = 9 -- px de rebord visibles sous le dessus (face avant)
local CAP_PRESS = 5 -- px dont la touche s'enfonce
local CAP_CORNER = 5
local CAP_SHADOW_OFFSET = 3
local CAP_SHADOW_TRANSPARENCY = 0.45
local CAP_FACE_SHADE = Color3.fromRGB(205, 205, 205) -- bas du dessus (dégradé multiplié à la couleur)
local CAP_SIDE_SHADE = Color3.fromRGB(165, 165, 165) -- bas du rebord

-- Couleurs d'un keycap : dessus, rebord, libellé
type CapColors = { face: Color3, side: Color3, legend: Color3 }

local CAP_SIDE_DARKEN = 0.33 -- rebord : couleur du dessus assombrie d'autant vers le noir

-- Cette méthode permet de décrire les couleurs d'un keycap lorsque ses états sont posés : rebord tiré du dessus.
local function capColors(face: Color3, legend: Color3): CapColors
	return { face = face, side = face:Lerp(C.Black, CAP_SIDE_DARKEN), legend = legend }
end

local CAP_KEY = capColors(C.Bone, C.Scrim)
-- Espace, Ctrl, Maj et la souris : les « modificateurs » du clavier, en ambre
local CAP_MOD = capColors(C.Accent, C.Scrim)
local CAP_DOWN = capColors(C.HitRed, C.Bone)
local CAP_MODIFIERS = { jump = true, crouch = true, walk = true, fire = true, aim = true }

local KeyDisplay = {}

type KeyView = {
	entry: HUDRules.KeyDisplayEntry,
	codes: { Enum.KeyCode }, -- touches du clavier de l'entrée, résolues une fois à la construction
	label: TextLabel,
	paint: (boolean) -> (),
	down: boolean,
}

local gui: ScreenGui?
local grid: Frame?
local root: Frame? -- racine mise à l'échelle (UIKit.scaledRoot), repère des marges de la grille
local views: { KeyView } = {}
local builtMode: string? -- mode dont la grille est construite

-- Cette méthode permet de savoir si une touche ou un bouton de souris est enfoncé lorsque la grille est rafraîchie ;
-- `typing` : un champ de texte (chat) a le focus et capte le clavier, le jeu ne reçoit pas ces touches.
local function isDown(view: KeyView, typing: boolean): boolean
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
end

-- Cette méthode permet de donner le libellé d'une touche lorsque la grille est construite : libellé fixe (ESPACE, CTRL,
-- M1), sinon celui de la touche sur la disposition du clavier du joueur (AZERTY : Z Q S D).
local function labelOf(entry: HUDRules.KeyDisplayEntry): string
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

-- Cette méthode permet d'arrondir les coins d'une pièce de keycap lorsqu'elle est construite.
local function rounded(frame: Frame, radius: number): Frame
	UIKit.create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = frame })
	return frame
end

-- Cette méthode permet de poser un dégradé vertical multiplié à la couleur d'une pièce lorsqu'un keycap est construit :
-- haut à la couleur pleine, bas assombri de `shade`.
local function shaded(frame: Frame, shade: Color3)
	UIKit.create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), shade),
		Parent = frame,
	})
end

-- Cette méthode permet de construire un keycap (ombre, rebord, dessus bombé, libellé) lorsque la grille est construite ;
-- renvoie le libellé et la fonction qui peint la touche au repos ou enfoncée.
local function buildKey(container: Frame, entry: HUDRules.KeyDisplayEntry): (TextLabel, (boolean) -> ())
	local holder = UIKit.frame({
		Name = entry.id,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(entry.col * (KEY_SIZE + KEY_GAP), entry.row * (KEY_SIZE + KEY_GAP)),
		Size = UDim2.fromOffset(entry.width * (KEY_SIZE + KEY_GAP) - KEY_GAP, KEY_SIZE),
		Parent = container,
	})
	local shadow = rounded(
		UIKit.frame({
			Name = "Shadow",
			BackgroundColor3 = C.Black,
			BackgroundTransparency = CAP_SHADOW_TRANSPARENCY,
			ZIndex = 1,
			Parent = holder,
		}),
		CAP_CORNER
	)
	local body = rounded(UIKit.frame({ Name = "Body", ZIndex = 2, Parent = holder }), CAP_CORNER)
	shaded(body, CAP_SIDE_SHADE)
	local face = rounded(
		UIKit.frame({ Name = "Face", Position = UDim2.fromOffset(CAP_SIDE, CAP_TOP), Parent = body }),
		CAP_CORNER - 1
	)
	shaded(face, CAP_FACE_SHADE)
	local text = labelOf(entry)
	local label = UIKit.text({
		Name = "Label",
		Text = text,
		FontFace = F.Display,
		TextSize = textSizeOf(entry, text),
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = face,
	})
	local rest = if CAP_MODIFIERS[entry.id] then CAP_MOD else CAP_KEY
	return label,
		-- Cette méthode permet de peindre la touche lorsque son état change : enfoncée, le haut descend, le bas reste posé.
		function(down: boolean)
			local colors = if down then CAP_DOWN else rest
			local sink = if down then CAP_PRESS else 0
			body.Position = UDim2.fromOffset(0, sink)
			body.Size = UDim2.new(1, 0, 1, -sink)
			face.Size = UDim2.new(1, -2 * CAP_SIDE, 1, -CAP_TOP - CAP_FRONT + sink)
			shadow.Position = UDim2.fromOffset(0, CAP_SHADOW_OFFSET + sink)
			shadow.Size = UDim2.new(1, 0, 1, -sink)
			body.BackgroundColor3 = colors.side
			face.BackgroundColor3 = colors.face
			label.TextColor3 = colors.legend
		end
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

-- Cette méthode permet de reconstruire la grille lorsque le mode d'affichage change : un keycap par entrée du mode,
-- grille centrée en bas de l'écran.
local function build(mode: string)
	local container = grid
	if not container then
		return
	end
	container:ClearAllChildren()
	views = {}
	builtMode = mode
	local entries = HUDRules.keyDisplayEntries(mode)
	local width, height = HUDRules.keyDisplayGridSize(mode)
	container.Size = UDim2.fromOffset(width, height)
	place()
	for _, entry in entries do
		local label, paintKey = buildKey(container, entry)
		local codes = {}
		for _, name in entry.keys or {} :: { string } do
			table.insert(codes, (Enum.KeyCode :: any)[name])
		end
		local view: KeyView = { entry = entry, codes = codes, label = label, paint = paintKey, down = false }
		paint(view, false)
		table.insert(views, view)
	end
end

-- Cette méthode permet d'afficher ou de masquer la grille, et de la reconstruire si le mode a changé, lorsque le réglage
-- ou l'état du HUD (HUDState) changent ; grille masquée, les touches repartent au repos (pas de touche restée enfoncée).
local function update()
	if not gui then
		return
	end
	local mode = LocalSettings.get().keyDisplay
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
			view.label.TextSize = textSizeOf(view.entry, text)
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
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, -- ombre sous le rebord, dessus et libellé au-dessus de leur parent
		DisplayOrder = 0,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	gui = screenGui
	local scaled = UIKit.scaledRoot(screenGui)
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
	HUDState.onChanged(onHudChanged)
	RunService.Heartbeat:Connect(poll)
	update()
end

return KeyDisplay
