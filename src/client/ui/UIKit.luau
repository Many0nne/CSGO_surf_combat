-- Briques communes des écrans : création d'Instances, texte au thème, tweens, icônes en Frames,
-- mise à l'échelle selon la résolution. Les valeurs de style viennent toutes de UITheme.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))

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

-- Cette méthode permet de créer le cadre racine d'un ScreenGui mis à l'échelle de la résolution lorsque l'écran est construit :
-- les maquettes sont en 720 px de haut, le contenu est agrandi ou réduit en gardant le cadre plein écran.
function UIKit.scaledRoot(gui: ScreenGui): Frame
	local root = UIKit.frame({ Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	local scale = UIKit.create("UIScale", { Parent = root })
	local function update()
		local camera = workspace.CurrentCamera
		local height = camera and camera.ViewportSize.Y or UITheme.Layout.ReferenceHeight
		local s = math.clamp(height / UITheme.Layout.ReferenceHeight, 0.75, 1.6)
		scale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
		root:SetAttribute("Scale", s)
	end
	update()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return root
end

-- Cette méthode permet de faire apparaître un groupe en fondu avec un léger glissement lorsqu'un écran entre ;
-- `dy` est le décalage vertical de départ (px), `delay` le retard avant l'animation.
function UIKit.reveal(group: CanvasGroup, delay: number?, dy: number?)
	local target = group:GetAttribute("RestPosition") or group.Position
	group:SetAttribute("RestPosition", target)
	group.GroupTransparency = 1
	group.Position = target + UDim2.fromOffset(0, dy or 14)
	task.delay(delay or 0, function()
		UIKit.tween(group, Motion.Enter, { GroupTransparency = 0, Position = target })
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
