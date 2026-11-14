-- Briques communes des écrans : création d'Instances, texte au thème, tweens, icônes en Frames,
-- mise à l'échelle selon la résolution. Les valeurs de style viennent toutes de UITheme.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local WeaponSkins = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponSkins"))

local C = UITheme.Colors
local Motion = UITheme.Motion

local UIKit = {}

-- Cette méthode permet de créer une Instance avec ses propriétés et ses enfants lorsqu'un écran se construit.
function UIKit.create(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- Cette méthode permet de créer un cadre sans bordure lorsqu'on a besoin d'un fond ou d'un conteneur.
function UIKit.frame(props: { [string]: any }): Frame
	local defaults = { BorderSizePixel = 0, BackgroundColor3 = C.Panel }
	for key, value in props do
		defaults[key] = value
	end
	return UIKit.create("Frame", defaults)
end

-- Cette méthode permet de créer un texte au thème (fond transparent, police et couleur par défaut) lorsqu'un libellé est posé.
function UIKit.text(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = UITheme.Fonts.Body,
		TextColor3 = C.Text,
		TextSize = UITheme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in props do
		defaults[key] = value
	end
	return UIKit.create("TextLabel", defaults)
end

-- Cette méthode permet de poser un texte doublé d'une ombre noire décalée lorsque le titrage du HUD ou du menu est
-- construit ; renvoie le texte puis son ombre, à mettre à jour ensemble.
function UIKit.shadowedText(parent: GuiObject, props: { [string]: any }, offset: number): (TextLabel, TextLabel)
	local shadowProps = table.clone(props)
	shadowProps.Name = (props.Name or "Text") .. "Shadow"
	shadowProps.TextColor3 = C.Black
	shadowProps.TextTransparency = 0.35
	shadowProps.Position = (props.Position or UDim2.new()) + UDim2.fromOffset(offset, offset)
	shadowProps.Parent = parent
	local shadow = UIKit.text(shadowProps)
	props.Parent = parent
	return UIKit.text(props), shadow
end

-- Taille des libellés ambrés du menu (#280) : à 13 px avec contour noir, l'utilisateur les trouvait illisibles
local ACCENT_LABEL_SIZE = 16

-- Cette méthode permet de poser un libellé ambré du menu (Oswald gras 16 px, ombre noire décalée, sans contour) lorsque
-- un titre de section ou un nom de stat est construit ; renvoie le texte puis son ombre.
function UIKit.accentLabel(parent: GuiObject, props: { [string]: any }): (TextLabel, TextLabel)
	local merged: { [string]: any } = {
		FontFace = UITheme.Fonts.Display,
		TextSize = ACCENT_LABEL_SIZE,
		TextColor3 = C.Accent,
		ZIndex = 2,
	}
	for key, value in props do
		merged[key] = value
	end
	-- Ombre de 1 px : à 2 px, les lettres paraissaient doublées une fois l'écran réduit (fenêtre de 607 px de haut)
	return UIKit.shadowedText(parent, merged, 1)
end

-- Cette méthode permet de poser une étiquette en boîte (texte court sur fond plein, largeur selon le texte) lorsqu'une
-- ligne précise un état ou nomme une touche ; se range dans un UIListLayout par `order`.
function UIKit.tag(parent: GuiObject, name: string, order: number, background: Color3, color: Color3): TextLabel
	local label = UIKit.text({
		Name = name,
		FontFace = UITheme.Fonts.Display,
		TextSize = UITheme.TextSize.Min,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = background,
		BackgroundTransparency = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.padding(label, 0, 8, 0, 8)
	return label
end

-- Cette méthode permet de poser une ligne horizontale d'aides (alignée à gauche, centrée en hauteur) lorsqu'un écran
-- rappelle ses touches en bas à gauche ; à remplir avec UIKit.keyHint.
function UIKit.hintRow(parent: GuiObject, props: { [string]: any }): Frame
	local merged: { [string]: any } = {
		Name = "Hints",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		Parent = parent,
	}
	for key, value in props do
		merged[key] = value
	end
	local row = UIKit.frame(merged)
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = row,
	})
	return row
end

-- Cette méthode permet d'ajouter à une ligne d'aides une touche en boîte os suivie de son action lorsqu'un menu nomme
-- une touche (#308 : même écriture partout) ; `key` nil : texte seul, atténué (remarque en fin de ligne).
function UIKit.keyHint(row: GuiObject, order: number, key: string?, action: string)
	if key then
		UIKit.tag(row, "Key" .. order, 2 * order - 1, C.Bone, C.Ground).Text = key
	end
	UIKit.text({
		Name = "Action" .. order,
		Text = action .. "      ",
		FontFace = UITheme.Fonts.DisplayMedium,
		TextSize = UITheme.TextSize.Min,
		TextColor3 = if key then C.TextSoft else C.Muted,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		LayoutOrder = 2 * order,
		Parent = row,
	})
end

-- Cette méthode permet de dessiner la silhouette plate d'une arme, de profil, à partir des MeshParts de son viewmodel
-- (bras exclus) lorsqu'une icône d'arme est créée (barre d'armes, équipement) ; la teinte vient de ImageColor3.
-- `textured` (#308) : l'arme garde ses textures et ses couleurs, éclairée, pour un grand rendu plutôt qu'une icône ;
-- habillée du skin `skinId` (#268, nil : d'origine).
function UIKit.weaponSilhouette(
	parent: GuiObject,
	viewmodelName: string,
	aspect: number,
	textured: boolean?,
	skinId: string?
): ViewportFrame
	local fov = 15
	local viewport = UIKit.create("ViewportFrame", {
		Name = "Silhouette",
		BackgroundTransparency = 1,
		Ambient = if textured then Color3.fromRGB(170, 170, 170) else C.White,
		LightColor = if textured then C.White else C.Black,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	local viewModels = ReplicatedStorage:FindFirstChild("ViewModels")
	local source = viewModels and viewModels:FindFirstChild(viewmodelName)
	if not source then
		return viewport
	end
	local model = Instance.new("Model")
	for _, part in source:GetChildren() do
		if part:IsA("MeshPart") and part.Transparency < 1 then
			local copy = part:Clone()
			if textured then
				for _, child in copy:GetChildren() do
					if not child:IsA("SurfaceAppearance") then
						child:Destroy()
					end
				end
			else
				copy:ClearAllChildren()
				copy.TextureID = ""
				copy.Color = C.White
				copy.Material = Enum.Material.SmoothPlastic
			end
			copy.Anchored = true
			copy.Parent = model
		end
	end
	if textured and skinId then
		WeaponSkins.apply(model, viewmodelName, skinId)
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
	local halfHeight = math.max(axes[1].length / 2 / aspect, axes[2].length / 2) * 1.08
	local distance = halfHeight / math.tan(math.rad(fov / 2)) + axes[3].length
	local camera = UIKit.create("Camera", { FieldOfView = fov, Parent = viewport })
	camera.CFrame = CFrame.lookAt(frame.Position + axes[3].dir * distance, frame.Position, axes[2].dir)
	viewport.CurrentCamera = camera
	return viewport
end

-- Cette méthode permet de créer un bouton texte sans effet natif lorsqu'un écran gère lui-même survol et clic.
function UIKit.button(props: { [string]: any }): TextButton
	local defaults = {
		AutoButtonColor = false,
		BorderSizePixel = 0,
		FontFace = UITheme.Fonts.Display,
		TextColor3 = C.Text,
		TextSize = UITheme.TextSize.Small,
		BackgroundColor3 = C.Panel,
	}
	for key, value in props do
		defaults[key] = value
	end
	return UIKit.create("TextButton", defaults)
end

-- Cette méthode permet d'ajouter une bordure uniforme lorsqu'un panneau ou un bouton doit être cerné.
function UIKit.stroke(parent: GuiObject, color: Color3, thickness: number?): UIStroke
	return UIKit.create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- Cette méthode permet d'ajouter des marges internes lorsqu'un conteneur doit décoller son contenu des bords.
function UIKit.padding(parent: GuiObject, top: number, right: number, bottom: number, left: number): UIPadding
	return UIKit.create("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right),
		PaddingBottom = UDim.new(0, bottom),
		PaddingLeft = UDim.new(0, left),
		Parent = parent,
	})
end

-- Cette méthode permet de lancer une interpolation et de la renvoyer lorsqu'un élément doit s'animer.
function UIKit.tween(inst: Instance, info: TweenInfo, goals: { [string]: any }): Tween
	local tween = TweenService:Create(inst, info, goals)
	tween:Play()
	return tween
end

-- Cette méthode permet de tracer un segment (Frame tournée) entre deux points lorsqu'une icône est dessinée sans image.
function UIKit.line(parent: GuiObject, x1: number, y1: number, x2: number, y2: number, thickness: number, color: Color3)
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	return UIKit.frame({
		Name = "Line",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2),
		Size = UDim2.fromOffset(len + thickness, thickness),
		Rotation = math.deg(math.atan2(dy, dx)),
		BackgroundColor3 = color,
		Parent = parent,
	})
end

-- Cette méthode permet de créer un conteneur d'icône transparent lorsqu'une icône en segments est construite.
local function iconBox(parent: GuiObject, size: Vector2, name: string): Frame
	return UIKit.frame({
		Name = name,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		Parent = parent,
	})
end

-- Cette méthode permet de dessiner une croix de fermeture lorsqu'un bouton « fermer » est créé.
function UIKit.crossIcon(parent: GuiObject, color: Color3): Frame
	local box = iconBox(parent, Vector2.new(14, 14), "CrossIcon")
	UIKit.line(box, 2, 2, 12, 12, 2, color)
	UIKit.line(box, 12, 2, 2, 12, 2, color)
	return box
end

-- Cette méthode permet de dessiner une flèche vers la droite lorsqu'un bouton d'action en affiche une.
function UIKit.arrowIcon(parent: GuiObject, color: Color3): Frame
	local box = iconBox(parent, Vector2.new(22, 16), "ArrowIcon")
	UIKit.line(box, 1, 8, 18, 8, 3, color)
	UIKit.line(box, 12, 2, 18, 8, 3, color)
	UIKit.line(box, 12, 14, 18, 8, 3, color)
	return box
end

export type MouseIconKind = "wheelUp" | "wheelDown" | "wheelClick"

-- Icône de souris (#254) : corps de 14x20 px (trait compris) centré dans une boîte de 20x34, chevron de 4 px au-dessus
-- (molette vers le haut) ou en dessous (vers le bas), dans le sens du geste
local MOUSE_ICON_SIZE = Vector2.new(20, 34)
local MOUSE_BODY = Vector2.new(14, 20)
local MOUSE_STROKE = 2
UIKit.MouseIconSize = MOUSE_ICON_SIZE

-- Cette méthode permet de dessiner une souris (contour, molette pleine) avec un chevron au-dessus ou en dessous lorsqu'un
-- geste de molette remplace son libellé (Réglages > TOUCHES) ; sans chevron : clic molette.
function UIKit.mouseIcon(parent: GuiObject, kind: MouseIconKind, color: Color3, transparency: number?): Frame
	local alpha = transparency or 0
	local box = iconBox(parent, MOUSE_ICON_SIZE, "MouseIcon")
	box:SetAttribute("Kind", kind)
	local cx = MOUSE_ICON_SIZE.X / 2
	local bodyTop = (MOUSE_ICON_SIZE.Y - MOUSE_BODY.Y) / 2
	-- Corps : le trait (UIStroke) est posé à l'extérieur du cadre, d'où le retrait de MOUSE_STROKE de chaque côté
	local body = UIKit.frame({
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(cx, bodyTop + MOUSE_STROKE),
		Size = UDim2.fromOffset(MOUSE_BODY.X - 2 * MOUSE_STROKE, MOUSE_BODY.Y - 2 * MOUSE_STROKE),
		BackgroundTransparency = 1,
		Parent = box,
	})
	UIKit.create("UICorner", { CornerRadius = UDim.new(0, 7), Parent = body })
	UIKit.create("UIStroke", { Color = color, Thickness = MOUSE_STROKE, Transparency = alpha, Parent = body })
	local wheel = UIKit.frame({
		Name = "Wheel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(cx, bodyTop + 4),
		Size = UDim2.fromOffset(4, 7),
		BackgroundColor3 = color,
		BackgroundTransparency = alpha,
		Parent = box,
	})
	UIKit.create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = wheel })
	if kind ~= "wheelClick" then
		-- Chevron de 8 px de large et 4 px de haut, à 2 px du corps
		local up = kind == "wheelUp"
		local tipY = if up then 1 else MOUSE_ICON_SIZE.Y - 1
		local baseY = if up then 5 else MOUSE_ICON_SIZE.Y - 5
		for _, side in { -4, 4 } do
			local line = UIKit.line(box, cx + side, baseY, cx, tipY, 2, color)
			line.BackgroundTransparency = alpha
		end
	end
	return box
end

-- Cette méthode permet de dessiner l'emblème du jeu (deux rampes en Λ) lorsque le logo est affiché.
function UIKit.emblem(parent: GuiObject): Frame
	local box = iconBox(parent, Vector2.new(30, 30), "Emblem")
	UIKit.line(box, 3, 24, 15, 6, 2.5, C.Accent)
	UIKit.line(box, 15, 6, 27, 24, 2.5, C.Accent)
	UIKit.line(box, 3, 24, 27, 24, 2.5, C.Accent)
	UIKit.line(box, 8, 24, 15, 13, 2.5, C.Text)
	UIKit.line(box, 15, 13, 22, 24, 2.5, C.Text)
	return box
end

-- Échelle du HUD (#250, facteur 0,5 à 1) et rappels des éléments qui la suivent
local hudFactor = 1
local hudScaleListeners: { (number) -> () } = {}

-- Cette méthode permet de changer l'échelle des éléments de bord du HUD lorsque le réglage change : chaque racine
-- `edge` et chaque UIScale branché par onHudScale se met à jour en direct.
function UIKit.setHudScale(factor: number)
	if factor == hudFactor then
		return
	end
	hudFactor = factor
	for _, listener in hudScaleListeners do
		listener(factor)
	end
end

-- Cette méthode permet de suivre l'échelle du HUD lorsqu'un élément s'y adapte : le rappel est appelé tout de suite
-- avec le facteur courant, puis à chaque changement, jusqu'à la destruction de `owner` (pas de rappel orphelin).
function UIKit.onHudScale(owner: Instance, listener: (number) -> ())
	table.insert(hudScaleListeners, listener)
	owner.Destroying:Once(function()
		local index = table.find(hudScaleListeners, listener)
		if index then
			table.remove(hudScaleListeners, index)
		end
	end)
	listener(hudFactor)
end

-- Cette méthode permet de créer le cadre racine d'un ScreenGui mis à l'échelle de la résolution lorsque l'écran est construit :
-- les maquettes sont en 720 px de haut, le contenu est agrandi ou réduit en gardant le cadre plein écran. `edge` : racine
-- d'éléments de bord du HUD, qui suit en plus l'échelle du HUD (#250) ; l'attribut Scale vaut alors l'échelle totale.
function UIKit.scaledRoot(gui: ScreenGui, edge: boolean?): Frame
	local root = UIKit.frame({ Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	local scale = UIKit.create("UIScale", { Parent = root })
	local function update()
		local camera = workspace.CurrentCamera
		local height = camera and camera.ViewportSize.Y or UITheme.Layout.ReferenceHeight
		local s = math.clamp(height / UITheme.Layout.ReferenceHeight, 0.75, 1.6)
		if edge then
			s *= hudFactor
		end
		scale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
		root:SetAttribute("Scale", s)
	end
	update()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	if edge then
		UIKit.onHudScale(root, update)
	end
	return root
end

-- Fond sombre du HUD (assets/ui/hud/scrim_coin.png, Decal 139288849836344) : blanc, opaque en bas à gauche, effacé vers
-- le haut et la droite. Les autres coins s'obtiennent par rotation (un ImageRectSize négatif ne retourne pas l'image).
local SCRIM_IMAGE = "rbxassetid://128710099398466"
-- Variante bord (#247, assets/ui/hud/scrim_bord.png, Decal 76113717632250 ; ci-dessous l'id de l'image du Decal) :
-- opaque au milieu du bord bas, effacée vers le haut et les côtés. Une seule image : deux coins collés en miroir
-- laissaient un filet clair à leur jonction.
local SCRIM_EDGE_IMAGE = "rbxassetid://104671552818880"
local SCRIM_ROTATION = { BottomLeft = 0, TopLeft = 90, TopRight = 180, BottomRight = -90, Bottom = 0, Top = 180 }

-- Cette méthode permet de poser un fond sombre sans bord, opaque dans un coin (ou au milieu d'un bord, `Top` / `Bottom`) et
-- effacé vers les côtés opposés, lorsqu'un élément du HUD est posé sur la scène ; `size` est la taille vue (largeur totale
-- pour un bord).
function UIKit.cornerScrim(
	parent: GuiObject,
	corner: "BottomLeft" | "TopLeft" | "TopRight" | "BottomRight" | "Bottom" | "Top",
	size: Vector2,
	transparency: number
): ImageLabel
	local edge = corner == "Top" or corner == "Bottom"
	local right = corner == "TopRight" or corner == "BottomRight"
	local top = corner == "TopLeft" or corner == "TopRight" or corner == "Top"
	local originX = if edge then 0.5 elseif right then 1 else 0
	local origin = UDim2.fromScale(originX, top and 0 or 1)
	local offsetX = if edge then 0 elseif right then -size.X / 2 else size.X / 2
	local rotation = SCRIM_ROTATION[corner]
	local quarter = rotation % 180 ~= 0
	return UIKit.create("ImageLabel", {
		Name = "Scrim" .. corner,
		Image = if edge then SCRIM_EDGE_IMAGE else SCRIM_IMAGE,
		ImageColor3 = C.Scrim,
		ImageTransparency = transparency,
		BackgroundTransparency = 1,
		Rotation = rotation,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = origin + UDim2.fromOffset(offsetX, top and size.Y / 2 or -size.Y / 2),
		Size = quarter and UDim2.fromOffset(size.Y, size.X) or UDim2.fromOffset(size.X, size.Y),
		Parent = parent,
	})
end

-- Propriété de transparence à animer selon la classe (pas de CanvasGroup : sa texture devient floue à basse qualité).
local FADE_PROPS = {
	Frame = { "BackgroundTransparency" },
	TextLabel = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextButton = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
	ImageButton = { "BackgroundTransparency", "ImageTransparency" },
	UIStroke = { "Transparency" },
}

-- Reliquats de transparence d'un fondu en cours, par racine : un second fondu lancé en plein vol repart des vraies valeurs.
local activeFades: { [Instance]: { [Instance]: { [string]: number } } } = setmetatable({}, { __mode = "k" }) :: any

-- Cette méthode permet de faire apparaître une arborescence d'éléments en jouant la transparence de chacun lorsqu'un
-- groupe doit apparaître sans CanvasGroup ; `delay` retarde le début.
function UIKit.fadeIn(root: Instance, info: TweenInfo, delay: number?)
	local rest = activeFades[root]
	if not rest then
		rest = {}
		for _, inst in root:GetDescendants() do
			local props = FADE_PROPS[inst.ClassName]
			if props then
				local values = {}
				for _, prop in props do
					values[prop] = (inst :: any)[prop]
				end
				rest[inst] = values
			end
		end
		activeFades[root] = rest
	end
	for inst, values in rest do
		for prop in values do
			(inst :: any)[prop] = 1
		end
	end
	task.delay(delay or 0, function()
		for inst, values in rest do
			if inst.Parent then
				UIKit.tween(inst, info, values)
			end
		end
		task.delay(info.Time, function()
			if activeFades[root] == rest then
				activeFades[root] = nil
			end
		end)
	end)
end

-- Cette méthode permet de faire apparaître un cadre en fondu avec un léger glissement lorsqu'un écran entre ;
-- `dy` est le décalage vertical de départ (px), `delay` le retard avant l'animation.
function UIKit.reveal(group: GuiObject, delay: number?, dy: number?)
	local target = group:GetAttribute("RestPosition") or group.Position
	group:SetAttribute("RestPosition", target)
	group.Position = target + UDim2.fromOffset(0, dy or 14)
	UIKit.fadeIn(group, Motion.Enter, delay)
	task.delay(delay or 0, function()
		UIKit.tween(group, Motion.Enter, { Position = target })
	end)
end

-- Cette méthode permet d'ajouter un léger enfoncement au clic lorsqu'un bouton doit réagir à la pression.
function UIKit.pressFeedback(button: GuiButton)
	local scale = UIKit.create("UIScale", { Parent = button })
	button.MouseButton1Down:Connect(function()
		UIKit.tween(scale, Motion.Press, { Scale = 0.97 })
	end)
	button.MouseButton1Up:Connect(function()
		UIKit.tween(scale, Motion.Hover, { Scale = 1 })
	end)
	button.MouseLeave:Connect(function()
		UIKit.tween(scale, Motion.Hover, { Scale = 1 })
	end)
end

-- Cette méthode permet de relier survol et sortie de souris à deux jeux de propriétés lorsqu'un élément change d'aspect au survol.
function UIKit.hover(button: GuiButton, target: Instance, normal: { [string]: any }, hovered: { [string]: any })
	button.MouseEnter:Connect(function()
		UIKit.tween(target, Motion.Hover, hovered)
	end)
	button.MouseLeave:Connect(function()
		UIKit.tween(target, Motion.Hover, normal)
	end)
end

-- Cette méthode permet de créer un bouton secondaire cerné (ANNULER, CLOSE) lorsqu'une modale propose une action neutre.
function UIKit.ghostButton(parent: GuiObject, label: string, size: UDim2): TextButton
	local btn = UIKit.button({
		Text = label,
		Size = size,
		BackgroundColor3 = C.Panel,
		TextSize = UITheme.TextSize.Small,
		Parent = parent,
	})
	local stroke = UIKit.stroke(btn, C.BorderStrong)
	UIKit.hover(btn, stroke, { Color = C.BorderStrong }, { Color = C.Accent })
	UIKit.hover(btn, btn, { BackgroundColor3 = C.Panel }, { BackgroundColor3 = C.Raised })
	UIKit.pressFeedback(btn)
	return btn
end

-- Cette méthode permet de créer un bouton principal ambre lorsqu'une modale propose l'action à valider.
function UIKit.accentButton(parent: GuiObject, label: string, size: UDim2): TextButton
	local btn = UIKit.button({
		Text = label,
		Size = size,
		BackgroundColor3 = C.Accent,
		TextColor3 = C.Ground,
		TextSize = UITheme.TextSize.Small,
		Parent = parent,
	})
	btn.MouseEnter:Connect(function()
		if btn.Active then
			UIKit.tween(btn, Motion.Hover, { BackgroundColor3 = C.AccentHover })
		end
	end)
	btn.MouseLeave:Connect(function()
		if btn.Active then
			UIKit.tween(btn, Motion.Hover, { BackgroundColor3 = C.Accent })
		end
	end)
	UIKit.pressFeedback(btn)
	return btn
end

-- Cette méthode permet d'afficher un bouton ambre comme actif ou désactivé lorsqu'une condition d'envoi change.
function UIKit.setAccentEnabled(btn: TextButton, enabled: boolean)
	btn.Active = enabled
	UIKit.tween(btn, Motion.Color, {
		BackgroundColor3 = enabled and C.Accent or C.AccentMuted,
		TextColor3 = enabled and C.Ground or C.Muted,
	})
end

-- Cette méthode permet de créer un bouton carré « fermer » avec sa croix lorsqu'un panneau peut être fermé.
function UIKit.closeButton(parent: GuiObject): TextButton
	local btn = UIKit.button({
		Name = "Close",
		Text = "",
		Size = UDim2.fromOffset(44, 44),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local stroke = UIKit.stroke(btn, C.BorderStrong)
	local icon = UIKit.crossIcon(btn, C.Text)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	UIKit.hover(btn, stroke, { Color = C.BorderStrong }, { Color = C.Accent })
	for _, line in icon:GetChildren() do
		UIKit.hover(btn, line, { BackgroundColor3 = C.Text }, { BackgroundColor3 = C.Accent })
	end
	UIKit.pressFeedback(btn)
	return btn
end

return UIKit
