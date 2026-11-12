-- Inventaire des joueurs (#267), décidé par le serveur : items possédés = inventaire par défaut (Ka-Bar, AWP) + items
-- sauvegardés (DataStore `PlayerInventory_v1`) + tout le catalogue pour un admin (`Roles`, #266). Règles pures dans
-- `InventoryRules`. Le serveur ne place dans le sac que les Tools possédés, copiés de `ReplicatedStorage.Tools` (le
-- StarterPack est vide : rien n'est donné d'office), à chaque apparition et à chaque changement d'inventaire ; un Tool
-- non possédé qui arrive en main est retiré (`init.server`, `trackWeapon3P`) et le Validator refuse ses tirs et coups.
-- Lecture DataStore en échec (ou données d'une version plus récente) : inventaire par défaut (et admin), sauvegarde
-- coupée pour la session. Écriture par UpdateAsync qui réunit les ids déjà enregistrés et ceux de la session (un
-- inventaire ne fait que grandir) : une sauvegarde en retard ou d'un autre serveur n'efface rien.
-- Équipement (#280) : une arme par emplacement (SNIPER, COUTEAU) et son skin, choisis à l'accueil (remote `EquipItem`,
-- refusé en partie) et enregistrés dans le même DataStore (`equipped`) ; seules les armes équipées vont dans le sac.
-- Le choix est résolu contre les items possédés : un item qui ne l'est plus laisse la place à l'équipement par défaut.
-- Studio seulement : attribut Player `DebugInventory` = "default" (posé en contexte serveur), le joueur est traité
-- comme un non-admin, pour vérifier l'inventaire par défaut avec le compte propriétaire.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPack = game:GetService("StarterPack")

local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)
local CheatLog = require(ServerScriptService.Server.CheatLog)
local Participants = require(ServerScriptService.Server.Participants)
local Roles = require(ServerScriptService.Server.Roles)

local DEBUG_ATTRIBUTE = "DebugInventory"
local BACKPACK_WAIT = 5 -- s d'attente maximale du sac d'un personnage qui vient d'apparaître
local CLOSE_WAIT = 25 -- s d'attente maximale des sauvegardes en vol à l'arrêt du serveur (budget Roblox : 30 s)
local SAVE_RETRY_DELAY = 60 -- s avant un nouvel essai d'une sauvegarde en échec (panne passagère du DataStore)
local MAX_SAVE_FAILURES = 5 -- échecs d'affilée (de 3 essais chacun) avant d'abandonner l'écriture d'un profil
-- s minimum entre deux écritures d'un même profil après un changement d'équipement : Roblox limite les écritures d'une
-- clé (une toutes les 6 s), des clics rapprochés sont réunis en une seule écriture
local EQUIP_SAVE_SPACING = 6

-- owned : items possédés, recalculés à chaque changement (setup, chargement, déblocage, debug) et lus à chaque tir.
-- equipped : choix relu puis modifié (#280, nil tant que rien n'est choisi ni relu) ; chosen : emplacements choisis dans
-- cette session, seuls écrits (un autre serveur garde les siens) ; resolved : équipement appliqué, recalculé avec owned.
type Profile = {
	stored: { string },
	owned: InventoryRules.Owned,
	equipped: InventoryRules.Equipped?,
	chosen: InventoryRules.Equipped,
	resolved: InventoryRules.Equipped,
	loaded: boolean,
	dirty: boolean,
	saving: boolean,
	lastSaveAt: number,
	canSave: boolean,
	failures: number,
}

local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}
-- Sauvegardes en cours, attendues par BindToClose (celles lancées au départ d'un joueur comprises)
local savesInFlight = 0
-- Sauvegardes programmées plus tard (espacement, nouvel essai), lancées tout de suite par BindToClose : le joueur peut
-- être déjà parti (plus dans `profiles`)
local pendingSaves: { [Profile]: Player } = {}
-- Arrêt du serveur en cours (BindToClose) : une sauvegarde en échec est retentée tout de suite, pas après un délai
local closing = false
-- Inventaire des bots (#267) : celui par défaut, jamais sauvegardé
local BOT_OWNED = InventoryRules.resolve(nil, false)

local InventoryStore = {}

-- Cette méthode permet d'ouvrir le DataStore une seule fois lorsque le premier joueur arrive ; nil si les services
-- d'API sont coupés (Studio sans « Enable Studio Access to API Services »).
local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, "PlayerInventory_v1")
	if ok then
		store = result
	end
	return store
end

-- Cette méthode permet de lire ou d'écrire le DataStore avec trois essais espacés lorsque le réseau ou les quotas
-- refusent une requête ; renvoie la réussite et le résultat.
local function withRetry(fn: () -> any): (boolean, any)
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attempt < 3 then
			task.wait(2 ^ attempt)
		end
	end
	return false, nil
end

-- Cette méthode permet de savoir si un joueur compte comme admin pour l'inventaire lorsqu'il est calculé : rôle Admin,
-- sauf en Studio sous `DebugInventory` = "default" (simulation d'un non-admin).
local function isAdmin(player: Player): boolean
	if RunService:IsStudio() and player:GetAttribute(DEBUG_ATTRIBUTE) == "default" then
		return false
	end
	return Roles.hasRole(player, Roles.ADMIN)
end

-- Cette méthode permet de lire les items possédés d'un joueur lorsqu'un système serveur en a besoin ; joueur inconnu
-- (parti, pas encore inscrit) : l'inventaire par défaut (et tout pour un admin).
function InventoryStore.owned(player: Player): InventoryRules.Owned
	local profile = profiles[player]
	return if profile then profile.owned else InventoryRules.resolve(nil, isAdmin(player))
end

-- Cette méthode permet de savoir si un participant possède un Tool lorsque le serveur valide un equip, un tir ou un
-- coup (Validator) : inventaire du joueur, inventaire par défaut pour un bot.
function InventoryStore.ownsTool(participant: Participants.Participant, toolName: string): boolean
	local player = participant.player
	local owned = if participant.isBot or not player then BOT_OWNED else InventoryStore.owned(player)
	return InventoryRules.ownsTool(owned, toolName)
end

-- Cette méthode permet de lire l'équipement appliqué d'un joueur (#280) lorsqu'un système serveur en a besoin ; joueur
-- inconnu : l'équipement par défaut.
function InventoryStore.equipped(player: Player): InventoryRules.Equipped
	local profile = profiles[player]
	return if profile then profile.resolved else InventoryRules.resolveEquipped(nil, InventoryStore.owned(player))
end

-- Cette méthode permet de lister les Tools du joueur (sac et main) lorsqu'ils sont comparés à son inventaire.
local function presentTools(player: Player): { Tool }
	local tools: { Tool } = {}
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") then
					table.insert(tools, child)
				end
			end
		end
	end
	return tools
end

-- Cette méthode permet de mettre le sac d'un joueur en accord avec son équipement lorsqu'il apparaît, qu'un nouveau sac
-- lui est donné ou que son inventaire change : Tools des armes équipées (#280) copiés de ReplicatedStorage.Tools, les
-- autres retirés (main comprise). Idempotente : sans effet si le sac est déjà juste.
function InventoryStore.syncTools(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	if not (character and humanoid and humanoid.Health > 0) then
		return -- au menu ou mort (corps encore en place) : le sac sera rempli à l'apparition
	end
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", BACKPACK_WAIT)
	if not (backpack and backpack:IsA("Backpack")) or player.Character ~= character then
		return
	end
	local tools = presentTools(player)
	local names = {}
	for _, tool in tools do
		table.insert(names, tool.Name)
	end
	local wanted = InventoryRules.equippedTools(InventoryStore.equipped(player))
	local give, remove = InventoryRules.toolChanges(wanted, names)
	for _, tool in tools do
		if table.find(remove, tool.Name) then
			tool:Destroy()
		end
	end
	local folder = ReplicatedStorage:FindFirstChild("Tools")
	for _, name in give do
		local source = folder and folder:FindFirstChild(name)
		if source and source:IsA("Tool") then
			source:Clone().Parent = backpack
		else
			warn("[InventoryStore] Tool " .. name .. " introuvable dans ReplicatedStorage.Tools")
		end
	end
end

-- Cette méthode permet de recalculer et publier l'inventaire et l'équipement d'un joueur (attributs informatifs
-- `OwnedItems` et `EquippedItems`, lus par l'accueil et les Réglages du client) et de remettre son sac en accord
-- lorsqu'ils changent (chargement, déblocage, équipement, debug Studio).
local function refresh(player: Player, profile: Profile)
	profile.owned = InventoryRules.resolve(profile.stored, isAdmin(player))
	profile.resolved = InventoryRules.resolveEquipped(profile.equipped, profile.owned)
	if not player.Parent then
		return
	end
	player:SetAttribute(InventoryRules.ATTRIBUTE, InventoryRules.encode(profile.owned))
	player:SetAttribute(InventoryRules.EQUIPPED_ATTRIBUTE, InventoryRules.encodeEquipped(profile.resolved))
	task.spawn(InventoryStore.syncTools, player)
end

local saveProfile: (Player, Profile) -> ()

-- Cette méthode permet de programmer une seule écriture d'un profil plus tard (espacée d'EQUIP_SAVE_SPACING depuis la
-- précédente, ou après `delay`) lorsqu'un changement ne peut pas partir tout de suite ; BindToClose la lance d'avance.
local function queueSave(player: Player, profile: Profile, delay: number?)
	if pendingSaves[profile] then
		return
	end
	pendingSaves[profile] = player
	local wait = delay or math.max(0, profile.lastSaveAt + EQUIP_SAVE_SPACING - os.clock())
	task.delay(wait, function()
		if pendingSaves[profile] then
			pendingSaves[profile] = nil
			saveProfile(player, profile)
		end
	end)
end

-- Cette méthode permet d'écrire l'inventaire d'un profil s'il a changé (item obtenu, équipement, départ, arrêt), une
-- écriture à la fois (InventoryRules.mergeForSave) ; un changement arrivé pendant l'écriture en relance une.
function saveProfile(player: Player, profile: Profile)
	local ds = getStore()
	if not (ds and profile.loaded and profile.canSave and profile.dirty) or profile.saving then
		return
	end
	profile.saving = true
	profile.dirty = false
	-- Au départ de l'écriture : les clics qui arrivent pendant qu'elle part se calent sur EQUIP_SAVE_SPACING
	profile.lastSaveAt = os.clock()
	savesInFlight += 1
	local stored = profile.stored
	-- Seuls les emplacements choisis dans cette session : ceux relus au chargement ne réécrasent pas un autre serveur
	local chosen = table.clone(profile.chosen)
	local ok = withRetry(function()
		return ds:UpdateAsync(tostring(player.UserId), function(old)
			return InventoryRules.mergeForSave(old, stored, chosen)
		end)
	end)
	savesInFlight -= 1
	profile.saving = false
	if not ok then
		-- Retentée même si le joueur est parti (le profil reste tenu ici), MAX_SAVE_FAILURES fois au plus
		profile.dirty = true
		profile.failures += 1
		if profile.failures >= MAX_SAVE_FAILURES then
			warn("[InventoryStore] sauvegarde abandonnée pour", player.Name, "après", profile.failures, "échecs")
		elseif closing then
			warn("[InventoryStore] sauvegarde impossible pour", player.Name, "— nouvel essai avant l'arrêt")
			saveProfile(player, profile)
		else
			warn(
				"[InventoryStore] sauvegarde impossible pour",
				player.Name,
				"— nouvel essai dans",
				SAVE_RETRY_DELAY,
				"s"
			)
			queueSave(player, profile, SAVE_RETRY_DELAY)
		end
		return
	end
	profile.failures = 0
	if profile.dirty then
		-- Changement arrivé pendant l'écriture : une autre, tout de suite à l'arrêt du serveur (attendue par BindToClose),
		-- sinon espacée d'EQUIP_SAVE_SPACING
		if closing then
			saveProfile(player, profile)
		else
			queueSave(player, profile)
		end
	end
end

-- Cette méthode permet d'écrire l'inventaire d'un joueur inscrit s'il a changé (cf. saveProfile).
function InventoryStore.save(player: Player)
	local profile = profiles[player]
	if profile then
		saveProfile(player, profile)
	end
end

-- Cette méthode permet d'inscrire un joueur lorsqu'il arrive, avant le chargement DataStore : inventaire par défaut (et
-- admin) publié tout de suite, pour que le client n'attende pas le DataStore ; un nouveau sac (réapparition) est
-- resynchronisé.
function InventoryStore.setup(player: Player)
	local profile: Profile = {
		stored = {},
		owned = {},
		equipped = nil,
		chosen = {},
		resolved = {},
		loaded = false,
		dirty = false,
		saving = false,
		lastSaveAt = -math.huge,
		canSave = false,
		failures = 0,
	}
	profiles[player] = profile
	refresh(player, profile)
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			task.spawn(InventoryStore.syncTools, player)
		end
	end)
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal(DEBUG_ATTRIBUTE):Connect(function()
			if profiles[player] == profile then
				refresh(player, profile)
			end
		end)
	end
end

-- Cette méthode permet de charger l'inventaire sauvegardé d'un joueur lorsqu'il arrive ; un échec de lecture (ou des
-- données d'une version plus récente) garde l'inventaire par défaut et coupe la sauvegarde pour la session, pour ne pas
-- écraser ses vraies données.
function InventoryStore.load(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local ds = getStore()
	local ok, data = false, nil
	if ds then
		ok, data = withRetry(function()
			return ds:GetAsync(tostring(player.UserId))
		end)
	end
	if profiles[player] ~= profile then
		return -- parti pendant le chargement
	end
	local stored, canSave, equipped = InventoryRules.loadOutcome(ok, data)
	profile.stored = stored
	profile.canSave = canSave
	-- Rien d'enregistré : nil, pour qu'une sauvegarde garde l'équipement qu'un autre serveur aurait écrit entre-temps
	profile.equipped = if next(equipped) ~= nil then equipped else nil
	profile.loaded = true
	if not canSave then
		warn("[InventoryStore] chargement impossible pour", player.Name, "— inventaire par défaut, non sauvegardé")
	end
	refresh(player, profile)
end

-- Cette méthode permet de donner un item à un joueur lorsqu'il l'obtient (boutique, déblocage : à venir, hors #267) :
-- ajouté, publié, sac mis à jour, écrit tout de suite. Refusé (false) tant que l'inventaire n'est pas chargé ou s'il ne
-- peut pas être sauvegardé (l'item serait perdu au départ), ou si l'id est inconnu ou déjà possédé.
function InventoryStore.grant(player: Player, id: string): boolean
	local profile = profiles[player]
	if not (profile and profile.loaded and profile.canSave) then
		return false
	end
	local stored, changed = InventoryRules.grant(profile.stored, id)
	if not changed then
		return false
	end
	profile.stored = stored
	profile.dirty = true
	refresh(player, profile)
	task.spawn(saveProfile, player, profile)
	return true
end

-- Cette méthode permet d'équiper une arme et son skin (nil : d'origine) lorsque le joueur clique à l'accueil (#280),
-- refusé avant le chargement, personnage en jeu ou item invalide (InventoryRules.equip) ; renvoie l'acceptation, le motif.
function InventoryStore.equip(player: Player, slot: any, weaponId: any, skinId: any): (boolean, string?)
	local profile = profiles[player]
	if not (profile and profile.loaded) then
		return false, "loading"
	end
	-- Personnage en jeu, vivant ou corps pas encore détruit : on ne change d'équipement qu'au menu (le personnage y est
	-- détruit, `LeaveRound`). Limite : pendant la réapparition, corps détruit, un client modifié passe (docs/anticheat.md)
	local character = player.Character
	if character and character.Parent then
		return false, "in_round"
	end
	local equipped, reason = InventoryRules.equip(profile.equipped or {}, profile.owned, slot, weaponId, skinId)
	if not equipped then
		return false, reason
	end
	profile.equipped = equipped
	profile.chosen[slot] = equipped[slot]
	refresh(player, profile)
	if profile.canSave then
		profile.dirty = true
		-- Tout de suite si la dernière écriture date d'EQUIP_SAVE_SPACING, sinon une seule pour les clics rapprochés
		queueSave(player, profile)
	end
	return true
end

-- Cette méthode permet de vider le StarterPack lorsque le serveur démarre : une place Studio enregistrée avant #267 peut
-- encore y garder les Tools, que Roblox donnerait à tout joueur à chaque apparition.
local function clearStarterPack()
	for _, child in StarterPack:GetChildren() do
		if child:IsA("Tool") then
			warn("[InventoryStore] Tool " .. child.Name .. " retiré du StarterPack (distribué selon l'inventaire)")
			child:Destroy()
		end
	end
end

-- Motifs de refus d'un `EquipItem` qu'un client honnête n'envoie pas (il ne montre que les items possédés de chaque
-- emplacement) : journalisés. Les autres (chargement en cours, personnage en partie) tiennent au moment du clic.
local SUSPECT_REFUSALS = { unknown = true, wrong_slot = true, not_owned = true, wrong_skin = true }

-- Cette méthode permet de brancher le remote d'équipement (#280), le départ des joueurs et l'arrêt du serveur lorsque le
-- serveur démarre ; à l'arrêt, il attend les sauvegardes en vol (CLOSE_WAIT au plus).
function InventoryStore.init(equipRemote: RemoteEvent)
	clearStarterPack()
	equipRemote.OnServerEvent:Connect(function(player: Player, slot: any, weaponId: any, skinId: any)
		-- Garde commune (#170) : débit, emplacement connu, ids bornés
		if not CheatLog.admit(player, equipRemote.Name, slot, weaponId, skinId) then
			return
		end
		local ok, reason = InventoryStore.equip(player, slot, weaponId, if skinId == "" then nil else skinId)
		if not ok and reason and SUSPECT_REFUSALS[reason] then
			CheatLog.report(
				Participants.fromPlayer(player),
				CheatLog.Category.INVENTORY,
				CheatLog.Severity.LOW,
				string.format("équipement refusé (%s) : %s %s %s", reason, slot, weaponId, skinId)
			)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		profiles[player] = nil
		if profile then
			saveProfile(player, profile)
		end
	end)
	game:BindToClose(function()
		closing = true
		-- Écritures programmées plus tard (joueurs partis compris) : lancées maintenant
		for profile, player in pendingSaves do
			pendingSaves[profile] = nil
			task.spawn(saveProfile, player, profile)
		end
		for player, profile in profiles do
			task.spawn(saveProfile, player, profile)
		end
		local deadline = os.clock() + CLOSE_WAIT
		while savesInFlight > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return InventoryStore
