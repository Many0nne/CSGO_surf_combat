-- Écran de chargement (#480) : volets couleur soleil fermés, libellé au centre et curseur qui va et vient sur un trait,
-- mêmes volets que la transition « DÉPLOIEMENT » (ui/Transition). Trois usages :
--   - lancement du jeu (script Loading, première image) : levé quand le client le dit prêt (setReadiness) ;
--   - téléportation vers l'entraînement et retour (TrainingClient) : fermé quand le serveur l'annonce, copié en gui de
--     téléportation (affiché par Roblox pendant le transfert), puis remontré à l'arrivée sans animation ;
--   - arrivée sur l'entraînement : les volets de Transition, fermés par l'apparition demandée, prennent le relais.
-- Dans ReplicatedFirst : il ne dépend que de LoadingRules (ReplicatedStorage n'est pas encore là au lancement).
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local LoadingRules = require(script.Parent:WaitForChild("LoadingRules"))

local LoadingScreen = {}

type Parts = {
	gui: ScreenGui,
	top: Frame,
	bottom: Frame,
	label: TextLabel,
	track: Frame,
	cursor: Frame,
}

-- Au-dessus des volets de Transition (50) qu'il recouvre au relais, sous l'overlay de performance (1000)
local DISPLAY_ORDER = 60
local LABEL_SIZE = 64 -- comme « DÉPLOIEMENT »
local TRACK_WIDTH = 240 -- px, trait sous le libellé
local TRACK_GAP = 60 -- px entre le centre de l'écran et le trait
local TRACK_TRANSPARENCY = 0.8
local CURSOR_WIDTH = 56
local SHUTTER = TweenInfo.new(LoadingRules.SHUTTER_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
local FADE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Aller-retour du curseur sur le trait, sans fin
local SWEEP = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
-- Volets ouverts (hors écran) et fermés
local TOP_OPEN, TOP_CLOSED = UDim2.fromScale(0, -0.5), UDim2.fromScale(0, 0)
local BOTTOM_OPEN, BOTTOM_CLOSED = UDim2.fromScale(0, 1), UDim2.fromScale(0, 0.5)

local parts: Parts? = nil
local covering = false
local generation = 0
local sweep: Tween? = nil
-- Lancement : instant d'affichage et prédicats donnés par le client (setReadiness)
local shownAt = 0
local isReady: (() -> boolean)? = nil
local isHandedOver: (() -> boolean)? = nil

-- Cette méthode permet de créer une Instance avec ses propriétés lorsque l'écran est construit (pas d'UIKit ici).
local function make(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	inst.Parent = parent
	return inst
end

-- Cette méthode permet de traduire un libellé français de l'écran lorsqu'il s'affiche, dans la langue du compte Roblox
-- (les réglages du joueur ne sont pas encore connus, cf. LoadingRules.translate).
local function localized(text: string): string
	local ok, localeId = pcall(function()
		return LocalizationService.RobloxLocaleId
	end)
	return LoadingRules.translate(text, if ok then localeId else nil)
end

-- Cette méthode permet de construire un écran complet, volets fermés et texte visible, lorsqu'il faut l'afficher ou le
-- confier à Roblox pour une téléportation ; le ScreenGui rendu n'a pas de parent.
local function build(text: string): Parts
	local gui = make("ScreenGui", {
		Name = "LoadingScreen",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = DISPLAY_ORDER,
	})
	local function panel(name: string, position: UDim2): Frame
		return make("Frame", {
			Name = name,
			Size = UDim2.fromScale(1, 0.5),
			Position = position,
			BackgroundColor3 = LoadingRules.PANEL_COLOR,
			BorderSizePixel = 0,
			Parent = gui,
		})
	end
	local top = panel("TopPanel", TOP_CLOSED)
	local bottom = panel("BottomPanel", BOTTOM_CLOSED)
	local label = make("TextLabel", {
		Name = "Label",
		Text = localized(text),
		FontFace = Font.new(LoadingRules.FONT_FAMILY, Enum.FontWeight.Bold),
		TextSize = LABEL_SIZE,
		TextColor3 = LoadingRules.TEXT_COLOR,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(900, 90),
		ZIndex = 2,
		Parent = gui,
	})
	local track = make("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, TRACK_GAP),
		Size = UDim2.fromOffset(TRACK_WIDTH, 2),
		BackgroundColor3 = LoadingRules.TEXT_COLOR,
		BackgroundTransparency = TRACK_TRANSPARENCY,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = gui,
	})
	local cursor = make("Frame", {
		Name = "Cursor",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CURSOR_WIDTH, 4),
		BackgroundColor3 = LoadingRules.TEXT_COLOR,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = track,
	})
	return { gui = gui, top = top, bottom = bottom, label = label, track = track, cursor = cursor }
end

-- Cette méthode permet d'obtenir l'écran du joueur (construit au premier appel, dans son PlayerGui) lorsqu'il s'affiche.
local function ensure(): Parts
	if not parts then
		local built = build(LoadingRules.INITIAL_LABEL)
		built.gui.Enabled = false
		built.gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		parts = built
	end
	return parts :: Parts
end

-- Cette méthode permet de faire aller et venir le curseur sur le trait lorsque l'écran est fermé, ou de l'arrêter.
local function setSweep(on: boolean)
	if sweep then
		sweep:Cancel()
		sweep = nil
	end
	local p = parts
	if not (on and p) then
		return
	end
	local half = (TRACK_WIDTH - CURSOR_WIDTH) / 2
	p.cursor.Position = UDim2.new(0.5, -half, 0.5, 0)
	local tween = TweenService:Create(p.cursor, SWEEP, { Position = UDim2.new(0.5, half, 0.5, 0) })
	tween:Play()
	sweep = tween
end

-- Cette méthode permet de rendre le texte et le trait visibles ou transparents d'un coup lorsque l'écran change d'état.
local function setInk(p: Parts, transparency: number)
	p.label.TextTransparency = transparency
	p.track.BackgroundTransparency = math.max(transparency, TRACK_TRANSPARENCY)
	p.cursor.BackgroundTransparency = transparency
end

-- Cette méthode permet d'afficher l'écran fermé d'un coup (sans volets qui glissent) lorsque rien ne doit apparaître
-- avant lui : lancement, arrivée d'une téléportation, relais d'un autre écran qui couvrait déjà tout.
function LoadingScreen.showNow(text: string)
	local p = ensure()
	generation += 1
	covering = true
	p.label.Text = localized(text)
	p.top.Position = TOP_CLOSED
	p.bottom.Position = BOTTOM_CLOSED
	setInk(p, 0)
	p.gui.Enabled = true
	setSweep(true)
end

-- Cette méthode permet de fermer les volets sur ce qui est affiché lorsqu'une attente commence (téléportation) ; déjà
-- fermé, seul le libellé change. Passé `timeout` s sans être rouvert, l'écran se rouvre seul.
function LoadingScreen.cover(text: string, timeout: number?)
	local p = ensure()
	p.label.Text = localized(text)
	if covering then
		return
	end
	generation += 1
	local myGeneration = generation
	covering = true
	p.top.Position = TOP_OPEN
	p.bottom.Position = BOTTOM_OPEN
	setInk(p, 1)
	p.gui.Enabled = true
	TweenService:Create(p.top, SHUTTER, { Position = TOP_CLOSED }):Play()
	local closing = TweenService:Create(p.bottom, SHUTTER, { Position = BOTTOM_CLOSED })
	closing.Completed:Connect(function()
		if myGeneration ~= generation then
			return
		end
		TweenService:Create(p.label, FADE, { TextTransparency = 0 }):Play()
		TweenService:Create(p.cursor, FADE, { BackgroundTransparency = 0 }):Play()
		TweenService:Create(p.track, FADE, { BackgroundTransparency = TRACK_TRANSPARENCY }):Play()
		setSweep(true)
	end)
	closing:Play()
	if timeout then
		task.delay(timeout, function()
			if myGeneration == generation and covering then
				LoadingScreen.uncover()
			end
		end)
	end
end

-- Cette méthode permet de rouvrir les volets sur le jeu lorsque l'attente est finie ; `instant` retire l'écran d'un coup,
-- quand un autre écran identique couvre déjà tout (volets de Transition).
function LoadingScreen.uncover(instant: boolean?)
	local p = parts
	if not (p and covering) then
		return
	end
	covering = false
	generation += 1
	local myGeneration = generation
	if instant then
		setSweep(false)
		p.gui.Enabled = false
		return
	end
	setInk(p, 1)
	TweenService:Create(p.top, SHUTTER, { Position = TOP_OPEN }):Play()
	local opening = TweenService:Create(p.bottom, SHUTTER, { Position = BOTTOM_OPEN })
	opening.Completed:Connect(function()
		if myGeneration == generation then
			setSweep(false)
			p.gui.Enabled = false
		end
	end)
	opening:Play()
end

-- Cette méthode permet de savoir si l'écran couvre tout lorsqu'un autre écran plein (Transition) doit s'y raccorder sans
-- animation.
function LoadingScreen.isCovering(): boolean
	return covering
end

-- Cette méthode permet de confier à Roblox une copie de l'écran fermé, affichée pendant le transfert, lorsque le joueur
-- demande une téléportation ; sans effet si Roblox la refuse.
function LoadingScreen.setTeleportGui(text: string)
	local copy = build(text)
	local ok, err = pcall(TeleportService.SetTeleportGui, TeleportService, copy.gui)
	if not ok then
		warn("[LoadingScreen] écran de téléportation refusé :", err)
	end
end

-- Cette méthode permet de donner au lancement ce qu'il attend du client lorsque celui-ci a tout démarré : `ready` dit si
-- le menu est prêt, `handedOver` si un autre écran plein (Transition) couvre déjà tout et doit prendre le relais.
function LoadingScreen.setReadiness(ready: () -> boolean, handedOver: () -> boolean)
	isReady = ready
	isHandedOver = handedOver
end

-- Cette méthode permet de lever l'écran du lancement lorsque le jeu est chargé et le client prêt (LoadingRules), en
-- vérifiant chaque dixième de seconde ; un autre écran affiché entre-temps (téléportation) n'est pas levé.
local function watchRelease(myGeneration: number)
	while myGeneration == generation and covering do
		local ready = isReady ~= nil and isReady()
		if LoadingRules.shouldRelease(os.clock() - shownAt, game:IsLoaded(), ready) then
			LoadingScreen.uncover(isHandedOver ~= nil and isHandedOver())
			return
		end
		task.wait(0.1)
	end
end

-- Cette méthode permet d'afficher l'écran dès la première image du client lorsqu'il démarre (script Loading), avec le
-- libellé de l'arrivée (lancement ou téléportation) à la place du gui de téléportation de Roblox, puis de le lever
-- quand le client est prêt.
function LoadingScreen.arrive()
	local okData, data = pcall(TeleportService.GetLocalPlayerTeleportData, TeleportService)
	LoadingScreen.showNow(LoadingRules.arrivalLabel(if okData then data else nil))
	local okGui, arriving = pcall(TeleportService.GetArrivingTeleportGui, TeleportService)
	if okGui and arriving then
		arriving:Destroy()
	end
	shownAt = os.clock()
	task.spawn(watchRelease, generation)
end

return LoadingScreen
