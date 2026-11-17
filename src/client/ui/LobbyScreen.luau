-- Lobby (#523, docs/ui.md « Lobby ») : ouvert par JOUER, écran secondaire du menu (`MenuPage` : bloc centré sur un
-- voile, sans panneau). Sous le titre, une ligne dit qui lance ; à gauche le groupe (hôte en boîte ambrée, joueur local
-- en rouge d'impact, présence de chacun), à droite les amis Roblox avec leur statut et INVITER ou REJOINDRE, les raisons
-- des actions impossibles sous la liste ; en bas RETOUR, QUITTER LE GROUPE (à plusieurs) et LANCER. L'hôte lance pour
-- tous les membres présents dans le lobby ; un membre attend l'hôte tant que celui-ci est dans le lobby.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FriendRules = require(Shared:WaitForChild("FriendRules"))
local PartyRules = require(Shared:WaitForChild("PartyRules"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local FriendsProvider = require(script.Parent.Parent.systems.game.FriendsProvider)
local PartyClient = require(script.Parent.Parent.systems.game.PartyClient)
local MenuPage = require(script.Parent.MenuPage)
local MenuShot = require(script.Parent.MenuShot)
local UIKit = require(script.Parent.UIKit)

local C = UITheme.Colors
local F = UITheme.Fonts

local LobbyScreen = {}

-- Mise en page (px à 720 de haut), dans le bloc centré de 780 px
local STATUS_Y = MenuPage.TabsY + 6 -- ligne « qui lance », à la place des onglets
local HEADER_Y = MenuPage.ContentTop
local LIST_Y = HEADER_Y + 32
local GROUP_WIDTH = 300
local FRIENDS_X = 340
local FRIENDS_WIDTH = MenuPage.BlockWidth - FRIENDS_X
local ROW_HEIGHT = 40
local NAME_SIZE = 20
local INFO_SIZE = UITheme.TextSize.Min
local ACTION_SIZE = 18
local REASONS_HEIGHT = 44 -- deux lignes de raisons sous la liste d'amis
local FRIENDS_HEIGHT = MenuPage.ContentBottom - LIST_Y - REASONS_HEIGHT
-- Délai (s) après lequel la liste d'amis est rechargée à la réouverture du lobby (GetFriendsOnline a un cache de 30 s)
local REFRESH_AFTER = 30

local PRESENCE_LABELS = {
	lobby = "DANS LE LOBBY",
	game = "EN PARTIE",
	menu = "AU MENU",
}
local STATUS_COLORS: { [FriendRules.Status]: Color3 } = {
	here = C.Bone,
	game = C.Bone,
	online = C.TextSoft,
	offline = C.Muted,
}
local INVITE_NOTICES = {
	refused = "ROBLOX REFUSE CETTE INVITATION",
	studio = "INVITATION IMPOSSIBLE DANS STUDIO",
	failed = "INVITATION IMPOSSIBLE, RÉESSAIE",
}

local page: MenuPage.Page
local statusText: TextLabel
local statusShadow: TextLabel
local groupHeader: TextLabel
local groupHeaderShadow: TextLabel
local groupList: Frame
local friendsList: ScrollingFrame
local friendsNote: TextLabel
local reasonsLabel: TextLabel
local leaveChoice: MenuShot.Choice
local launchChoice: MenuShot.Choice
local callbacks: { onBack: () -> (), onLaunch: () -> boolean, onNotice: (string) -> () }
local open = false
-- Entrée dans la manche en cours (LANCER, ou LANCER de l'hôte reçu) : plus aucune action du lobby jusqu'à sa réouverture,
-- les volets mettent un instant à couvrir l'écran
local launching = false
-- Liste d'amis chargée (nil : pas encore, ou en échec si `failed`), heure du chargement et numéro du dernier lancé
local friends: { FriendRules.Friend }? = nil
local friendsFailed = false
local friendsAt = -math.huge
local fetchGeneration = 0
-- Ce qui a servi à dessiner la liste d'amis (liste, groupe, droits) : elle n'est refaite que si cela change, pas à chaque
-- changement de présence d'un joueur du serveur
local friendsKey: string? = nil
local groupKey: string? = nil
local canInvite: boolean? = nil
local canInviteAsked = false

-- Cette méthode permet de poser un texte de ligne (nom, statut) lorsqu'une ligne du groupe ou des amis se construit.
local function rowText(parent: Instance, props: { [string]: any }): TextLabel
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromScale(0, 1),
		Parent = parent,
	}
	for key, value in props do
		merged[key] = value
	end
	return UIKit.text(merged)
end

-- Cette méthode permet de créer une ligne vide (hauteur fixe, filet os en bas) lorsqu'une liste se dessine.
local function makeRow(parent: Instance, order: number, width: number): Frame
	local row = UIKit.frame({
		Name = "Row" .. order,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, ROW_HEIGHT),
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.frame({
		Name = "Rule",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.Bone,
		BackgroundTransparency = 0.88,
		Parent = row,
	})
	return row
end

-- Cette méthode permet de vider une liste (lignes seulement, pas sa mise en page) lorsqu'elle se redessine.
local function clearRows(list: Instance)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Cette méthode permet de réécrire un texte doublé de son ombre lorsqu'une ligne d'état change.
local function setShadowed(label: TextLabel, shadow: TextLabel, text: string)
	label.Text = text
	shadow.Text = text
end

-- Cette méthode permet d'écrire la ligne « qui lance » et l'état de LANCER et QUITTER LE GROUPE lorsque le groupe
-- change : l'hôte lance pour tous, un membre attend l'hôte s'il est dans le lobby, sinon lance pour lui seul.
local function paintLaunch(members: { PartyClient.Member })
	local host: PartyClient.Member? = nil
	for _, member in members do
		if member.isHost then
			host = member
		end
	end
	local state = PartyClient.launchState()
	local text =
		PartyRules.statusLine(#members, host ~= nil and host.isLocal, state, host and host.presence, host and host.name)
	setShadowed(statusText, statusShadow, text)
	launchChoice.setEnabled(state == "launch" and not launching)
	leaveChoice.button.Visible = #members > 1
end

-- Cette méthode permet de dessiner le groupe (hôte, présence, joueur local) lorsque le lobby s'ouvre ou que le groupe
-- change.
local function paintGroup(): { [number]: boolean }
	local members = PartyClient.members()
	local ids: { [number]: boolean } = {}
	local parts = {}
	for _, member in members do
		ids[member.id] = true
		table.insert(
			parts,
			string.format("%d:%s:%s:%s", member.id, member.presence, tostring(member.isHost), member.name)
		)
	end
	paintLaunch(members)
	-- Lignes refaites seulement si le groupe change (pas à chaque changement de présence d'un autre joueur du serveur)
	local key = table.concat(parts, ";")
	if key == groupKey then
		return ids
	end
	groupKey = key
	clearRows(groupList)
	for index, member in members do
		local row = makeRow(groupList, index, GROUP_WIDTH)
		local line = UIKit.frame({
			Name = "Line",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -110, 1, 0),
			Parent = row,
		})
		UIKit.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
			Parent = line,
		})
		local name = rowText(line, {
			Name = "Name",
			Text = member.name,
			FontFace = F.DisplayText,
			TextSize = NAME_SIZE,
			-- Rouge d'impact = « à moi » (docs/ui.md, #308)
			TextColor3 = if member.isLocal then C.HitRed else C.Bone,
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 1,
		})
		name.Size = UDim2.fromScale(0, 1)
		if member.isHost then
			UIKit.tag(line, "Host", 2, C.Accent, C.Ground).Text = "HÔTE"
		end
		rowText(row, {
			Name = "Presence",
			Text = PRESENCE_LABELS[member.presence],
			FontFace = F.DisplayMedium,
			TextSize = INFO_SIZE,
			TextColor3 = C.TextSoft,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 110, 1, 0),
		})
	end
	local count = #members
	setShadowed(groupHeader, groupHeaderShadow, if count > 1 then "GROUPE · " .. count else "GROUPE")
	return ids
end

-- Cette méthode permet de lancer l'action d'une ligne d'ami lorsque le joueur clique INVITER ou REJOINDRE.
local function act(friend: FriendRules.Friend, action: FriendRules.Action)
	if launching then
		return
	end
	if action == "follow" then
		PartyClient.follow(friend.id, friend.status == "game")
		return
	end
	task.spawn(function()
		local result = FriendsProvider.invite(friend.id)
		local notice = INVITE_NOTICES[result]
		if notice then
			callbacks.onNotice(notice)
		end
	end)
end

-- Cette méthode permet de dessiner la liste d'amis (statut, action, raisons des actions impossibles) lorsqu'elle est
-- chargée ou que le groupe change.
local function paintFriends(partyIds: { [number]: boolean })
	local ids = {}
	for id in partyIds do
		table.insert(ids, id)
	end
	table.sort(ids)
	local key = string.format(
		"%s|%s|%s|%s|%s",
		tostring(friends),
		table.concat(ids, ","),
		tostring(canInvite),
		tostring(#Players:GetPlayers() >= Players.MaxPlayers),
		tostring(friendsFailed)
	)
	if key == friendsKey then
		return
	end
	friendsKey = key
	clearRows(friendsList)
	reasonsLabel.Text = ""
	if not friends then
		friendsNote.Text = if friendsFailed then "LISTE D'AMIS INDISPONIBLE" else "CHARGEMENT DES AMIS…"
		friendsNote.Visible = true
		return
	end
	local list = friends :: { FriendRules.Friend }
	friendsNote.Text = "AUCUN AMI À AFFICHER"
	friendsNote.Visible = #list == 0
	local ctx: FriendRules.Context = {
		studio = RunService:IsStudio(),
		canInvite = canInvite,
		serverFull = #Players:GetPlayers() >= Players.MaxPlayers,
		partyIds = partyIds,
	}
	for index, friend in list do
		local row = makeRow(friendsList, index, FRIENDS_WIDTH - 12)
		rowText(row, {
			Name = "Name",
			Text = friend.name,
			FontFace = F.DisplayText,
			TextSize = NAME_SIZE,
			TextColor3 = C.Bone,
			Size = UDim2.new(0, 170, 1, 0),
		})
		rowText(row, {
			Name = "Status",
			Text = FriendRules.statusLabel(friend, ctx),
			FontFace = F.DisplayMedium,
			TextSize = INFO_SIZE,
			TextColor3 = if partyIds[friend.id] then C.Accent else STATUS_COLORS[friend.status],
			Position = UDim2.fromOffset(180, 0),
			Size = UDim2.new(0, 130, 1, 0),
		})
		local action, enabled = FriendRules.action(friend, ctx)
		if action then
			-- Pas page.choice : il garde chaque choix créé, et les lignes sont refaites à chaque changement
			local choice = MenuShot.textChoice({
				text = if action == "invite" then "INVITER" else "REJOINDRE",
				font = F.Display,
				size = ACTION_SIZE,
				color = C.TextSoft,
				selectedColor = C.Bone,
				anchor = Vector2.new(1, 0.5),
				position = UDim2.new(1, -4, 0.5, 0),
				parent = row,
				action = function()
					act(friend, action)
				end,
			})
			choice.setEnabled(enabled)
		end
	end
	reasonsLabel.Text = table.concat(FriendRules.reasons(list, ctx), "\n")
end

-- Cette méthode permet de tout redessiner (groupe, puis amis qui en dépendent) lorsque le lobby s'ouvre, que le groupe
-- change ou que la liste d'amis arrive.
local function paint()
	if not open then
		return
	end
	paintFriends(paintGroup())
end

-- Cette méthode permet de recharger la liste d'amis à part (appels web) lorsque le lobby s'ouvre et qu'elle date ; seul
-- le dernier chargement lancé est retenu.
local function refreshFriends()
	fetchGeneration += 1
	local generation = fetchGeneration
	friendsAt = os.clock()
	task.spawn(function()
		if not canInviteAsked then
			canInviteAsked = true
			canInvite = FriendsProvider.canInvite()
		end
		local list = FriendsProvider.fetch()
		if generation ~= fetchGeneration then
			return
		end
		if list then
			friends, friendsFailed = list, false
		elseif not friends then
			-- Échec sans liste précédente : la garder sinon
			friendsFailed = true
		end
		paint()
	end)
end

-- Cette méthode permet de construire l'écran lorsque le client démarre : `onBack` (RETOUR), `onLaunch` (LANCER,
-- entrée dans la manche) et `onNotice` (message sous les onglets du menu).
function LobbyScreen.init(handlers: { onBack: () -> (), onLaunch: () -> boolean, onNotice: (string) -> () })
	callbacks = handlers
	page = MenuPage.new("LobbyScreen", 2, "LOBBY")
	local block = page.block
	statusText, statusShadow = UIKit.accentLabel(block, {
		Name = "Status",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, STATUS_Y),
		Size = UDim2.fromOffset(MenuPage.BlockWidth, 20),
	})
	groupHeader, groupHeaderShadow = UIKit.accentLabel(block, {
		Name = "GroupHeader",
		Text = "GROUPE",
		Position = UDim2.fromOffset(0, HEADER_Y),
		Size = UDim2.fromOffset(GROUP_WIDTH, 20),
	})
	UIKit.accentLabel(block, {
		Name = "FriendsHeader",
		Text = "AMIS",
		Position = UDim2.fromOffset(FRIENDS_X, HEADER_Y),
		Size = UDim2.fromOffset(FRIENDS_WIDTH, 20),
	})
	groupList = UIKit.frame({
		Name = "Group",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, LIST_Y),
		Size = UDim2.fromOffset(GROUP_WIDTH, MenuPage.ContentBottom - LIST_Y),
		Parent = block,
	})
	UIKit.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = groupList })
	friendsList = UIKit.create("ScrollingFrame", {
		Name = "Friends",
		Position = UDim2.fromOffset(FRIENDS_X, LIST_Y),
		Size = UDim2.fromOffset(FRIENDS_WIDTH, FRIENDS_HEIGHT),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.Accent,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromScale(0, 0),
		Parent = block,
	})
	UIKit.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = friendsList })
	friendsNote = UIKit.text({
		Name = "FriendsNote",
		Text = "",
		FontFace = F.DisplayMedium,
		TextSize = INFO_SIZE,
		TextColor3 = C.Muted,
		Position = UDim2.fromOffset(FRIENDS_X, LIST_Y + 8),
		Size = UDim2.fromOffset(FRIENDS_WIDTH, 20),
		Parent = block,
	})
	reasonsLabel = UIKit.text({
		Name = "Reasons",
		Text = "",
		FontFace = F.DisplayMedium,
		TextSize = INFO_SIZE,
		TextColor3 = C.Muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(FRIENDS_X, LIST_Y + FRIENDS_HEIGHT + 6),
		Size = UDim2.fromOffset(FRIENDS_WIDTH, REASONS_HEIGHT - 6),
		Parent = block,
	})
	-- Actions en bas au centre : RETOUR, QUITTER LE GROUPE (à plusieurs), puis LANCER (action principale, en os vif)
	page.action("RETOUR", function()
		callbacks.onBack()
	end)
	leaveChoice = page.action("QUITTER LE GROUPE", function()
		if not launching then
			PartyClient.leave()
		end
	end)
	launchChoice = page.action("LANCER", function()
		if launching or PartyClient.launchState() ~= "launch" then
			return
		end
		-- Entrée dans la manche d'abord : le serveur ne tire les membres du lobby que si le lanceur y entre vraiment
		if callbacks.onLaunch() then
			LobbyScreen.lock()
			PartyClient.launch()
		end
	end)
	launchChoice.setSelected(true)

	PartyClient.onChanged(paint)
	-- Cette méthode permet de recalculer le statut « sur ce serveur » des amis lorsqu'un joueur arrive ou part pendant
	-- que le lobby est ouvert, sur la dernière liste lue (sans rappeler Roblox).
	local function onPlayersChanged()
		if open and friends then
			friends = FriendsProvider.remerge() or friends
			paint()
		end
	end
	Players.PlayerAdded:Connect(onPlayersChanged)
	Players.PlayerRemoving:Connect(function()
		-- Après les autres abonnés : le joueur qui part est alors marqué comme partant (FriendsProvider)
		task.defer(onPlayersChanged)
	end)
	Players.LocalPlayer:GetAttributeChangedSignal(FriendRules.DEBUG_ATTRIBUTE):Connect(function()
		if open then
			refreshFriends()
		end
	end)
end

-- Cette méthode permet d'ouvrir le lobby lorsque le joueur clique JOUER : le serveur le note dans le lobby (ses amis
-- le voient, l'hôte le fait entrer), la liste d'amis est rechargée si elle date.
function LobbyScreen.show()
	if not page then
		return
	end
	open = true
	launching = false
	-- Lignes refaites à l'ouverture : un survol resté en rouge à la fermeture disparaît
	friendsKey = nil
	groupKey = nil
	PartyClient.open()
	if os.clock() - friendsAt >= REFRESH_AFTER then
		refreshFriends()
	end
	paint()
	page.show()
end

-- Cette méthode permet de fermer le lobby lorsque le joueur va sur une autre page du menu ; `silent` lorsque c'est
-- l'entrée dans la manche (LANCER, enchaînement) : le serveur sait déjà qu'il est en partie.
function LobbyScreen.hide(silent: boolean?)
	if not page or not open then
		return
	end
	open = false
	page.hide()
	if not silent then
		PartyClient.close()
	end
end

-- Cette méthode permet de bloquer les actions du lobby lorsque le joueur entre dans la manche (LANCER, ou LANCER de
-- l'hôte reçu) : les volets mettent un instant à couvrir l'écran ; levé à la prochaine ouverture.
function LobbyScreen.lock()
	launching = true
	if launchChoice then
		launchChoice.setEnabled(false)
	end
end

-- Cette méthode permet de savoir si le lobby est ouvert lorsque l'hôte lance (seul un joueur du lobby entre dans la
-- manche avec lui).
function LobbyScreen.isOpen(): boolean
	return open
end

return LobbyScreen
