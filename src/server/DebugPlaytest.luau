-- DebugPlaytest.luau
-- Helper de playtest debug (#30), actif uniquement dans Studio. Déclenché depuis le MCP (contexte Server) par
-- l'attribut `DebugPlaytest` posé sur un joueur (nom d'outil ou numéro de slot) :
--   game.Players:GetPlayers()[1]:SetAttribute("DebugPlaytest", "AWP")
-- Le run enchaîne : spawn en round (même chemin que le bouton Play), équipement serveur de l'outil, cible
-- immobile devant le joueur, attaque simulée côté client (Tool:Activate → WeaponSystem → remote de dégâts →
-- Validator → TakeDamage, aucun chemin de dégâts dupliqué), puis écrit un PASS/FAIL par étape préfixé
-- `[DebugPlaytest]`. Le serveur décide et vérifie ; le client (client/debug/DebugPlaytest) exécute et observe
-- (pistes d'animation, marqueurs, sons) et répond par le remote `DebugPlaytest`, créé seulement dans Studio.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetworkProtocol = require(Shared:WaitForChild("NetworkProtocol"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local Rules = require(Shared:WaitForChild("DebugPlaytestRules"))

local CLIENT_TIMEOUT = 12 -- secondes d'attente max d'une réponse client
local DAMAGE_TIMEOUT = 3 -- secondes d'attente des dégâts sur la cible après l'attaque
local DUMMY_HEALTH = 1000 -- PV élevés : la cible survit et les dégâts réels de l'arme restent lisibles
local DUMMY_DISTANCE = 6 -- studs devant le joueur (dans la portée mêlée et Validator)

type Deps = {
	roundManager: any,
	botManager: any,
	validator: any,
	meleeRemote: RemoteEvent,
	hitscanRemote: RemoteEvent,
}

type Reply = { ok: boolean, detail: string, data: any }

local DebugPlaytest = {}

local deps: Deps
local remote: RemoteEvent
local PENDING = {}
local replies: { [number]: Reply | typeof(PENDING) } = {}
local replyOwners: { [number]: Player } = {}
local nextRequestId = 0
local running: { [Player]: boolean } = {}
local dummies: { [Player]: Model } = {}

-- Cette méthode permet d'écrire une ligne préfixée dans la console lorsque le run avance.
local function log(text: string)
	print(Rules.line(text))
end

-- Cette méthode permet d'envoyer une commande au client du joueur et d'attendre sa réponse lorsque le run
-- a besoin d'une action ou d'une observation côté client ; échec explicite au bout du délai.
local function callClient(player: Player, cmd: string, payload: any, timeout: number?): Reply
	nextRequestId += 1
	local id = nextRequestId
	replies[id] = PENDING
	replyOwners[id] = player
	remote:FireClient(player, id, cmd, payload)
	local deadline = os.clock() + (timeout or CLIENT_TIMEOUT)
	while replies[id] == PENDING and os.clock() < deadline and player.Parent do
		task.wait(0.05)
	end
	local reply = replies[id]
	replies[id] = nil
	replyOwners[id] = nil
	if reply == PENDING or reply == nil then
		return { ok = false, detail = "pas de réponse du client à « " .. cmd .. " »", data = nil }
	end
	return reply :: Reply
end

-- Cette méthode permet de supprimer la cible immobile d'un joueur lorsqu'un nouveau run démarre ou qu'il part.
local function clearDummy(player: Player)
	local dummy = dummies[player]
	dummies[player] = nil
	if dummy then
		dummy:Destroy()
	end
end

-- Cette méthode permet de lister les outils du joueur (sac et personnage) par nom lorsque le run doit en équiper un.
local function collectTools(player: Player): { [string]: Tool }
	local tools = {}
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") then
					tools[child.Name] = child
				end
			end
		end
	end
	return tools
end

-- Cette méthode permet de logger les remotes de dégâts reçus du joueur testé lorsque le run est en cours,
-- avec le verdict du Validator (lecture seule : l'application des dégâts reste dans init.server).
local function watchHitRemote(rmt: RemoteEvent, validate: (Player, Instance, number) -> boolean)
	rmt.OnServerEvent:Connect(function(player, target, damage)
		if not running[player] then
			return
		end
		local valid = typeof(target) == "Instance" and validate(player, target, damage)
		log(
			string.format(
				"serveur : %s reçu (cible=%s, dégâts=%s, validation=%s)",
				rmt.Name,
				typeof(target) == "Instance" and target.Name or tostring(target),
				tostring(damage),
				valid and "OK" or "REFUS"
			)
		)
	end)
end

-- Cette méthode permet d'exécuter un run complet (spawn, équipement, cible, attaque, dégâts) lorsque
-- l'attribut est posé ; chaque étape ajoute une ligne PASS/FAIL et le run se termine par RESULT.
local function run(player: Player, selector: any)
	local report = Rules.newReport()
	local function step(name: string, ok: boolean, detail: string?)
		print(report:add(name, ok, detail))
		return ok
	end
	local tool: Tool? = nil
	local unequipConn: RBXScriptConnection? = nil
	local unequippedTo: string? = nil

	log(string.format("début du run pour %s (sélecteur=%s)", player.Name, tostring(selector)))
	deps.botManager.setSuspended(true)
	clearDummy(player)

	local function finish()
		if unequipConn then
			unequipConn:Disconnect()
		end
		callClient(player, "finish", nil, 3)
		local line = report:summary()
		print(line)
		deps.botManager.setSuspended(false)
	end

	-- 1. Spawn en round : le client passe par le même chemin que le bouton Play.
	local spawnReply = callClient(player, "spawn")
	local char = player.Character
	local humanoid = char and char:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local alive = humanoid ~= nil and humanoid.Health > 0 and root ~= nil
	if
		not step(
			"SPAWN",
			spawnReply.ok and alive and deps.roundManager.isActive(),
			string.format("%s ; round serveur=%s", spawnReply.detail, deps.roundManager.getState())
		)
	then
		return finish()
	end
	assert(char and humanoid and root, "personnage incomplet")

	-- 2. Équipement serveur de l'outil demandé (déséquipé d'abord s'il l'était, pour rejouer l'Equip).
	local tools = collectTools(player)
	local names = {}
	for name in tools do
		table.insert(names, name)
	end
	local toolName = Rules.resolveToolName(names, selector)
	if not toolName then
		table.sort(names)
		step(
			"EQUIP",
			false,
			string.format("aucun outil « %s » (dispo : %s)", tostring(selector), table.concat(names, ", "))
		)
		return finish()
	end
	tool = tools[toolName]
	assert(tool, "outil introuvable")
	local cfg = WeaponConfig.Weapons[tool:GetAttribute("WeaponName") or tool.Name]
	if not cfg then
		log(string.format("ATTENTION : pas d'entrée WeaponConfig pour « %s » (attribut WeaponName ?)", tool.Name))
	end
	if tool.Parent == char then
		humanoid:UnequipTools()
		task.wait(0.3)
	end
	local watchReply = callClient(player, "watch", { tool = toolName })
	if not watchReply.ok then
		log("client : " .. watchReply.detail)
	end
	humanoid:EquipTool(tool)
	unequipConn = tool.AncestryChanged:Connect(function()
		if tool and tool.Parent ~= char and not unequippedTo then
			local where = tool.Parent and tool.Parent:GetFullName() or "nil"
			unequippedTo = where
			log("ATTENTION : outil déséquipé pendant le run (parent=" .. where .. ")")
		end
	end)
	local equipReply = callClient(player, "equipped", { tool = toolName })
	if not step("EQUIP", equipReply.ok and tool.Parent == char, toolName .. " ; " .. equipReply.detail) then
		return finish()
	end

	-- 3. Cible immobile devant le joueur (rig de bot, sans IA), puis visée caméra côté client.
	local flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local dummyPos = root.Position + flat * DUMMY_DISTANCE
	local dummy = deps.botManager.spawnDummy(
		CFrame.lookAt(dummyPos, Vector3.new(root.Position.X, dummyPos.Y, root.Position.Z)),
		DUMMY_HEALTH
	)
	local dummyHum = dummy and dummy:FindFirstChildWhichIsA("Humanoid") :: Humanoid?
	local dummyRoot = dummy and dummy:FindFirstChild("HumanoidRootPart") :: BasePart?
	if
		not step(
			"TARGET",
			dummyHum ~= nil and dummyRoot ~= nil,
			string.format("cible à %d studs, %d PV", DUMMY_DISTANCE, DUMMY_HEALTH)
		)
	then
		return finish()
	end
	assert(dummy and dummyHum and dummyRoot, "cible incomplète")
	dummies[player] = dummy
	local damageTaken = 0
	local lastHealth = dummyHum.Health
	dummyHum.HealthChanged:Connect(function(health)
		local delta = lastHealth - health
		lastHealth = health
		if delta > 0 then
			damageTaken += delta
			log(string.format("serveur : cible touchée -%g PV (reste %g/%g)", delta, health, dummyHum.MaxHealth))
		end
	end)
	local aimReply = callClient(player, "aim", { target = dummyRoot.Position })
	if not step("AIM", aimReply.ok, aimReply.detail) then
		return finish()
	end

	-- 4. Attaque simulée côté client (chemin réel de l'arme), observations renvoyées par le client.
	local attackReply = callClient(player, "attack", { tool = toolName })
	local data = attackReply.data or {}
	local anims = data.anims or {}
	local markers = data.markers or {}
	local sounds = data.sounds or {}
	step(
		"ATTACK",
		attackReply.ok and table.find(anims, "Shoot") ~= nil,
		string.format("%s ; pistes : %s", attackReply.detail, table.concat(anims, ", "))
	)
	step(
		"SOUND",
		#sounds > 0,
		string.format("marqueurs : %s ; sons : %s", table.concat(markers, ", "), table.concat(sounds, ", "))
	)

	-- 5. Dégâts reçus par la cible, comparés aux dégâts de base de l'arme (cible de face : pas de backstab).
	local deadline = os.clock() + DAMAGE_TIMEOUT
	while damageTaken <= 0 and os.clock() < deadline do
		task.wait(0.05)
	end
	local expected = Rules.expectedDamage(cfg)
	step(
		"DAMAGE",
		damageTaken > 0 and (expected == nil or damageTaken == expected),
		string.format(
			"reçus %g (attendu %s), PV restants %g/%g",
			damageTaken,
			expected and tostring(expected) or "?",
			dummyHum.Health,
			dummyHum.MaxHealth
		)
	)

	-- 6. L'outil doit être resté équipé tout le run.
	step(
		"STILL_EQUIPPED",
		tool.Parent == char and unequippedTo == nil,
		unequippedTo and ("déséquipé vers " .. unequippedTo) or "toujours en main"
	)
	return finish()
end

-- Cette méthode permet de suivre l'attribut de déclenchement d'un joueur lorsqu'il rejoint la partie ;
-- l'attribut est remis à nil en fin de run pour pouvoir relancer le même scénario.
local function watchPlayer(player: Player)
	player:GetAttributeChangedSignal(Rules.ATTRIBUTE):Connect(function()
		local selector = player:GetAttribute(Rules.ATTRIBUTE)
		if selector == nil then
			return
		end
		if running[player] then
			log("run déjà en cours pour " .. player.Name .. ", demande ignorée")
			return
		end
		running[player] = true
		task.spawn(function()
			local ok, err = pcall(run, player, selector)
			if not ok then
				print(Rules.line("RESULT FAIL (erreur : " .. tostring(err) .. ")"))
				deps.botManager.setSuspended(false)
			end
			running[player] = nil
			if player.Parent then
				player:SetAttribute(Rules.ATTRIBUTE, nil)
			end
		end)
	end)
end

-- Cette méthode permet d'activer le helper (remote, écoute de l'attribut, logs des remotes de dégâts)
-- lorsque le serveur tourne dans Studio ; hors Studio elle ne crée rien.
function DebugPlaytest.init(dependencies: Deps)
	if not RunService:IsStudio() then
		return
	end
	deps = dependencies

	remote = Instance.new("RemoteEvent")
	remote.Name = NetworkProtocol.Names.DEBUG_PLAYTEST
	remote.Parent = ReplicatedStorage
	remote.OnServerEvent:Connect(function(player, id, ok, detail, data)
		if typeof(id) ~= "number" or replies[id] ~= PENDING or replyOwners[id] ~= player then
			return
		end
		replies[id] = { ok = ok == true, detail = tostring(detail or ""), data = data }
	end)

	watchHitRemote(deps.meleeRemote, deps.validator.validateMelee)
	watchHitRemote(deps.hitscanRemote, deps.validator.validateHitscan)

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		clearDummy(player)
		running[player] = nil
	end)
	log('helper actif (Studio) : player:SetAttribute("' .. Rules.ATTRIBUTE .. '", "AWP") en contexte Server')
end

return DebugPlaytest
