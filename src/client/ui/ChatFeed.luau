-- Chat in-game (#541, docs/ui.md « Chat » et docs/moderation.md) : interface du jeu par-dessus TextChatService, dont
-- la fenêtre et la barre natives sont masquées. Fil en bas à gauche, au-dessus du compteur de vitesse : nom en os
-- (rouge d'impact pour le joueur local), message en os, ombre décalée ; chaque ligne s'efface en fondu quelques secondes
-- après son arrivée et toutes réapparaissent saisie ouverte. Entrée ouvre la saisie (CaptureFocus) ; Entrée envoie
-- (TextChannel:SendAsync) et ferme ; Échap ferme sans envoyer. Saisie ouverte : touches de jeu coupées
-- (InputModule.setSuspended « chat »), souris toujours verrouillée en partie (on regarde encore autour), clics retenus
-- par un voile invisible, molette pour remonter le fil. PC seulement. Règles pures : shared/ChatRules.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local ChatRules = require(ReplicatedStorage.Shared.ChatRules)
local Locale = require(ReplicatedStorage.Shared.Locale)
local NetworkProtocol = require(ReplicatedStorage.Shared.NetworkProtocol)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local InputModule = require(script.Parent.Parent.input.InputModule)
local HUDRules = require(script.Parent.HUDRules)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts

-- Au-dessus du HUD (0) et du menu principal (onglets : 4) ; masqué quand un menu ou les Réglages sont ouverts (`canShow`)
local DISPLAY_ORDER = 5
-- Bloc en px de maquette (720 de haut) : bord gauche du compteur de vitesse, bas au-dessus de ses chiffres
local LEFT = 44
local BOTTOM = 166
local WIDTH = 460
local TEXT_SIZE = 18
local SHADOW = 2
local SHADOW_TRANSPARENCY = 0.35
local LINE_GAP = 2
local INPUT_HEIGHT = 30
local INPUT_GAP = 8
-- Hauteur réservée aux lignes : FEED_VISIBLE lignes d'une rangée (un message long passe sur deux, la plus ancienne
-- sort alors par le haut)
local LINES_HEIGHT = ChatRules.FEED_VISIBLE * (TEXT_SIZE + 6 + LINE_GAP)
-- Fond sombre sous le bloc saisie ouverte (même image que les coins du HUD)
local SCRIM_SIZE = Vector2.new(WIDTH + 200, LINES_HEIGHT + INPUT_HEIGHT + 140)
local SCRIM_TRANSPARENCY = 0.25
-- Entrée appuyée juste après une fermeture (envoi par Entrée) : ne rouvre pas
local REOPEN_GUARD = 0.25
-- Envoi par Entrée juste après l'ouverture (même appui vu par le champ) : ignoré
local SEND_GUARD = 0.15
local OPEN_KEYS = { [Enum.KeyCode.Return] = true, [Enum.KeyCode.KeypadEnter] = true }
local CHANNEL_NAME = "RBXGeneral"
-- Période (s) de relecture de la visibilité du fil (écran du menu, menu en partie ouvert)
local VISIBILITY_PERIOD = 0.1

-- `rich` et `raw` : texte de la ligne et de son ombre, composés une fois à l'arrivée
type Entry = { at: number, name: string?, text: string, mine: boolean, notice: boolean, rich: string?, raw: string? }
type Row = { holder: Frame, text: TextLabel, shadow: TextLabel }
export type Deps = {
	-- Fil affichable (partie, ou accueil du menu ; pas de chargement, de menu en partie ni de Réglages ouverts)
	canShow: () -> boolean,
}

local ChatFeed = {}

local deps: Deps? = nil
local gui: ScreenGui? = nil
local blocker: Frame
local scrim: ImageLabel
local inputBar: Frame
local box: TextBox
local rows: { Row } = {}
local entries: { Entry } = {}
local isOpen = false
local openedAt = -math.huge
local closedAt = -math.huge
local scroll = 0
local nextVisibilityCheck = 0
local commandRemote: RemoteEvent? = nil
local bucket = ChatRules.newBucket(os.clock())
local localUserId = Players.LocalPlayer.UserId

-- Cette méthode permet de composer le texte riche d'une ligne lorsqu'elle est affichée : nom (coloré, en gras) puis
-- message ; `colored` faux pour l'ombre, que les couleurs écraseraient.
local function lineText(entry: Entry, colored: boolean): string
	local message = HUDRules.escapeRichText(entry.text)
	if entry.notice then
		return if colored then string.format('<font color="#%s">%s</font>', C.Accent:ToHex(), message) else message
	end
	local name = "<b>" .. HUDRules.escapeRichText(entry.name or "?") .. "</b>"
	if colored then
		name = string.format('<font color="#%s">%s</font>', (if entry.mine then C.HitRed else C.Bone):ToHex(), name)
	end
	return name .. "   " .. message
end

-- Cette méthode permet de créer une rangée du fil (texte et ombre) lorsque le fil est construit ; les rangées sont
-- réutilisées, rangées de bas en haut par un UIListLayout.
local function makeRow(parent: Frame, index: number): Row
	local holder = UIKit.frame({
		Name = "Row" .. index,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
		-- Rangée 1 en bas : ordre décroissant
		LayoutOrder = -index,
		Visible = false,
		Parent = parent,
	})
	local props = {
		Name = "Text",
		RichText = true,
		Text = "",
		FontFace = F.DisplayText,
		TextSize = TEXT_SIZE,
		TextColor3 = C.Bone,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -SHADOW, 0, TEXT_SIZE + 6),
		ZIndex = 2,
	}
	local text, shadow = UIKit.shadowedText(holder, props, SHADOW)
	shadow.ZIndex = 1
	return { holder = holder, text = text, shadow = shadow }
end

-- Cette méthode permet de redessiner le fil lorsqu'une ligne arrive, que la saisie s'ouvre ou se ferme, ou que le
-- joueur fait défiler : les FEED_VISIBLE lignes au-dessus du défilement, chacune à sa transparence de fondu.
local function render()
	if not gui then
		return
	end
	local now = os.clock()
	local last = #entries - scroll
	for i, row in rows do
		local entry = entries[last - i + 1]
		if entry then
			local fade = ChatRules.lineTransparency(now - entry.at, isOpen)
			row.holder.Visible = fade < 1
			local wanted = entry.rich or ""
			if row.text.Text ~= wanted then
				row.text.Text = wanted
				row.shadow.Text = entry.raw or ""
			end
			row.text.TextTransparency = fade
			row.shadow.TextTransparency = SHADOW_TRANSPARENCY + (1 - SHADOW_TRANSPARENCY) * fade
		else
			row.holder.Visible = false
		end
	end
end

-- Cette méthode permet d'ajouter une ligne au fil lorsqu'un message ou un retour arrive ; les plus anciennes au-delà
-- de FEED_KEEP sont oubliées, le défilement en cours garde sa ligne en place.
local function push(entry: Entry)
	entry.rich = lineText(entry, true)
	entry.raw = lineText(entry, false)
	table.insert(entries, entry)
	if #entries > ChatRules.FEED_KEEP then
		table.remove(entries, 1)
	end
	-- Fil remonté : la ligne lue reste en place (un cran de plus depuis le bas, que la plus ancienne parte ou non)
	if scroll > 0 then
		scroll = ChatRules.clampScroll(scroll + 1, #entries)
	end
	render()
end

-- Cette méthode permet d'afficher un retour local (débit dépassé, retour d'une commande admin) lorsqu'il arrive.
local function pushNotice(text: string)
	push({ at = os.clock(), name = nil, text = text, mine = false, notice = true })
end

-- Cette méthode permet de savoir si le pointeur est verrouillé au centre (partie) lorsqu'un clic arrive pendant la
-- saisie : verrouillé, le clic est retenu et la saisie continue ; libre (menu), il ferme la saisie.
local function pointerLocked(): boolean
	return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
end

-- Cette méthode permet de rendre le curseur au champ lorsque la saisie doit continuer (clic retenu, envoi refusé).
local function refocus()
	task.defer(function()
		if isOpen and not box:IsFocused() then
			box:CaptureFocus()
		end
	end)
end

-- Cette méthode permet de fermer la saisie lorsque le joueur envoie, appuie sur Échap ou que le fil doit disparaître :
-- touches de jeu rendues, fil revenu en bas et lignes de nouveau en fondu.
local function close()
	if not isOpen then
		return
	end
	isOpen = false
	closedAt = os.clock()
	scroll = 0
	InputModule.setSuspended(false, "chat")
	inputBar.Visible = false
	scrim.Visible = false
	blocker.Visible = false
	if box:IsFocused() then
		box:ReleaseFocus()
	end
	box.Text = ""
	render()
end

-- Cette méthode permet d'ouvrir la saisie lorsque le joueur appuie sur Entrée, fil affichable : touches de jeu
-- coupées (le personnage cesse d'avancer), toutes les lignes visibles, curseur dans le champ.
local function open()
	if isOpen or not deps or not deps.canShow() then
		return
	end
	isOpen = true
	openedAt = os.clock()
	InputModule.setSuspended(true, "chat")
	box.Text = ""
	inputBar.Visible = true
	scrim.Visible = true
	blocker.Visible = pointerLocked()
	render()
	-- Après l'appui en cours : le champ ne doit pas voir l'Entrée qui l'ouvre
	task.defer(function()
		if isOpen then
			box:CaptureFocus()
		end
	end)
end

-- Cette méthode permet d'envoyer le texte du champ lorsque le joueur appuie sur Entrée : commande admin au serveur par
-- son remote, débit dépassé = retour et texte gardé, sinon envoi au canal général ; la saisie se ferme.
local function send()
	local text = ChatRules.clean(box.Text)
	local verdict = ChatRules.admit(bucket, text, os.clock(), false)
	if verdict == "rate" then
		pushNotice(Locale.t(ChatRules.Notice.RATE))
		refocus()
		return
	end
	close()
	if verdict == "command" then
		if commandRemote then
			commandRemote:FireServer(text)
		end
		return
	elseif verdict ~= "ok" then
		return
	end
	local channels = TextChatService:FindFirstChild("TextChannels")
	local channel = channels and channels:FindFirstChild(CHANNEL_NAME)
	if not (channel and channel:IsA("TextChannel")) then
		warn("[ChatFeed] canal " .. CHANNEL_NAME .. " absent : message non envoyé")
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			channel:SendAsync(text)
		end)
		if not ok then
			warn("[ChatFeed] envoi impossible :", err)
		end
	end)
end

-- Cette méthode permet de traiter la perte du focus du champ lorsque le joueur valide, appuie sur Échap ou clique :
-- Entrée envoie (sauf l'appui qui vient d'ouvrir), un clic pointeur verrouillé garde la saisie, le reste ferme.
local function onFocusLost(enterPressed: boolean, cause: InputObject?)
	if not isOpen then
		return
	end
	if enterPressed then
		if os.clock() - openedAt < SEND_GUARD then
			refocus()
			return
		end
		send()
		return
	end
	local clicked = cause ~= nil
		and (
			cause.UserInputType == Enum.UserInputType.MouseButton1
			or cause.UserInputType == Enum.UserInputType.MouseButton2
			or cause.UserInputType == Enum.UserInputType.MouseButton3
		)
	if clicked and pointerLocked() then
		refocus()
		return
	end
	close()
end

-- Cette méthode permet d'afficher un message reçu lorsque TextChatService le délivre : messages de joueurs seulement
-- (pas de messages système ni du jeu, décision 4 de #541), texte déjà filtré par Roblox.
local function onMessage(message: TextChatMessage)
	local source = message.TextSource
	if not source or message.Status ~= Enum.TextChatMessageStatus.Success or message.Text == "" then
		return
	end
	local player = Players:GetPlayerByUserId(source.UserId)
	push({
		at = os.clock(),
		name = if player then player.DisplayName else source.Name,
		text = ChatRules.unescape(message.Text),
		mine = source.UserId == localUserId,
		notice = false,
	})
end

-- Cette méthode permet d'afficher le retour d'une commande admin lorsque le serveur l'envoie (gabarit traduit ici ;
-- l'usage d'une commande est lui aussi traduit).
local function onNotice(template: unknown, args: unknown)
	if type(template) ~= "string" then
		return
	end
	local values = if type(args) == "table" then table.clone(args :: { [string]: any }) else {}
	if type(values.usage) == "string" then
		values.usage = Locale.t(values.usage)
	end
	pushNotice(Locale.t(template, values))
end

-- Cette méthode permet de suivre l'état du fil à chaque image lorsque le client tourne : fil masqué (et saisie fermée)
-- hors des écrans où il est disponible (relu 10 fois par seconde), voile des clics, redessin seulement pendant un fondu.
local function step()
	if not gui or not deps then
		return
	end
	local now = os.clock()
	local appearing = false
	if now >= nextVisibilityCheck then
		nextVisibilityCheck = now + VISIBILITY_PERIOD
		local visible = deps.canShow()
		if not visible and isOpen then
			close()
		end
		appearing = visible and not gui.Enabled
		if gui.Enabled ~= visible then
			gui.Enabled = visible
		end
	end
	local shown = gui.Enabled
	if isOpen then
		blocker.Visible = pointerLocked()
	end
	local newest = entries[#entries]
	local fading = newest ~= nil and now - newest.at <= ChatRules.FADE_DELAY + ChatRules.FADE_TIME + 0.1
	if appearing or (shown and fading and not isOpen) then
		render()
	end
end

-- Cette méthode permet de construire le champ de saisie (libellé du canal, champ, filet) lorsque le fil est construit ;
-- un texte long passe à la ligne (curseur toujours visible) et le champ grandit vers le haut, les lignes avec lui.
local function buildInput(parent: Frame, lines: Frame)
	inputBar = UIKit.frame({
		Name = "Input",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, INPUT_HEIGHT),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = parent,
	})
	local label = UIKit.accentLabel(inputBar, {
		Name = "Channel",
		Text = "TOUS",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, INPUT_HEIGHT),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	box = UIKit.create("TextBox", {
		Name = "Box",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		MultiLine = false,
		Text = "",
		PlaceholderText = "Écrire un message…",
		PlaceholderColor3 = C.Muted,
		FontFace = F.DisplayText,
		TextSize = TEXT_SIZE,
		TextColor3 = C.Bone,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(56, 0),
		Size = UDim2.new(1, -56, 0, INPUT_HEIGHT),
		ZIndex = 2,
		Parent = inputBar,
	})
	-- Cette méthode permet de convertir des px écran en px de maquette lorsque le champ se replace (racine à l'échelle).
	local function toLayout(px: number): number
		local scale = parent.Parent and (parent.Parent :: Instance):GetAttribute("Scale")
		return px / (if type(scale) == "number" and scale > 0 then scale else 1)
	end
	-- Libellé de largeur variable selon la langue : le champ commence juste après
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local width = toLayout(label.AbsoluteSize.X) + 12
		box.Position = UDim2.fromOffset(width, 0)
		box.Size = UDim2.new(1, -width, 0, INPUT_HEIGHT)
	end)
	-- Champ sur plusieurs lignes : le fil remonte d'autant
	inputBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local height = math.max(toLayout(inputBar.AbsoluteSize.Y), INPUT_HEIGHT)
		lines.Position = UDim2.new(0, 0, 1, -(height + INPUT_GAP))
	end)
	UIKit.frame({
		Name = "Rule",
		BackgroundColor3 = C.Bone,
		BackgroundTransparency = 0.88,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		Parent = inputBar,
	})
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local clipped = ChatRules.clip(box.Text)
		if clipped ~= box.Text then
			box.Text = clipped
		end
	end)
	box.FocusLost:Connect(onFocusLost)
end

-- Cette méthode permet de masquer fenêtre, barre de saisie et bulles natives de TextChatService lorsque leur
-- configuration existe ou apparaît ; une bulle au-dessus d'une tête trahirait la position du joueur.
local function hideNative(child: Instance)
	if
		child:IsA("ChatWindowConfiguration")
		or child:IsA("ChatInputBarConfiguration")
		or child:IsA("BubbleChatConfiguration")
	then
		(child :: any).Enabled = false
	end
end

-- Cette méthode permet de construire le chat et de brancher Entrée, la molette, la réception des messages et les
-- retours du serveur lorsque le client démarre ; masque la fenêtre et la barre natives de TextChatService.
function ChatFeed.init(newDeps: Deps)
	if gui then
		return
	end
	deps = newDeps
	for _, child in TextChatService:GetChildren() do
		hideNative(child)
	end
	-- Configurations créées par le moteur après le démarrage du client : masquées à leur arrivée
	TextChatService.ChildAdded:Connect(hideNative)

	local screenGui = UIKit.create("ScreenGui", {
		Name = "Chat",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = DISPLAY_ORDER,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	gui = screenGui
	-- Voile invisible saisie ouverte en partie : un clic (pointeur au centre) ne part pas en tir
	blocker = UIKit.frame({
		Name = "ClickBlocker",
		Active = true,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = screenGui,
	})
	local root = UIKit.scaledRoot(screenGui, true)
	local block = UIKit.frame({
		Name = "Block",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, LEFT, 1, -BOTTOM),
		Size = UDim2.fromOffset(WIDTH, LINES_HEIGHT + INPUT_GAP + INPUT_HEIGHT),
		Parent = root,
	})
	scrim = UIKit.cornerScrim(block, "BottomLeft", SCRIM_SIZE, SCRIM_TRANSPARENCY)
	scrim.Position += UDim2.fromOffset(-LEFT, 40)
	scrim.Visible = false
	-- Calé au-dessus de la ligne de saisie (replacé quand elle passe sur plusieurs lignes)
	local lines = UIKit.frame({
		Name = "Lines",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -(INPUT_HEIGHT + INPUT_GAP)),
		Size = UDim2.new(1, 0, 0, LINES_HEIGHT),
		Parent = block,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, LINE_GAP),
		Parent = lines,
	})
	for i = 1, ChatRules.FEED_VISIBLE do
		rows[i] = makeRow(lines, i)
	end
	buildInput(block, lines)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or isOpen or not OPEN_KEYS[input.KeyCode] then
			return
		end
		if os.clock() - closedAt < REOPEN_GUARD or UserInputService:GetFocusedTextBox() then
			return
		end
		open()
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if isOpen and input.UserInputType == Enum.UserInputType.MouseWheel then
			local delta = if input.Position.Z > 0 then 1 elseif input.Position.Z < 0 then -1 else 0
			scroll = ChatRules.clampScroll(scroll + delta, #entries)
			render()
		end
	end)
	TextChatService.MessageReceived:Connect(onMessage)
	task.spawn(function()
		local remote = NetworkProtocol.getRemote(NetworkProtocol.Names.CHAT_NOTICE)
		if remote then
			remote.OnClientEvent:Connect(onNotice)
		end
	end)
	task.spawn(function()
		commandRemote = NetworkProtocol.getRemote(NetworkProtocol.Names.CHAT_COMMAND)
	end)
	RunService.Heartbeat:Connect(step)
end

return ChatFeed
