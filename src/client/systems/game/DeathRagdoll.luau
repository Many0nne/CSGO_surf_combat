-- Corps d'un joueur tué (#102) : chaque client clone le personnage mort, remplace ses articulations par des rotules et
-- le laisse tomber avec la vitesse du joueur plus une poussée dans le sens du tir. Le serveur ne détruit le personnage
-- qu'après CORPSE_HANDOFF_DELAY (init.server) pour laisser le temps au clone. Physique purement locale : les positions
-- des joueurs sont pilotées par les clients (CharacterSync), le serveur n'a rien à simuler.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DeathRules = require(script.Parent.DeathRules)
local CharacterSync = require(script.Parent.Parent.network.CharacterSync)
local MovementController = require(script.Parent.Parent.movement.MovementController)

local DeathRagdoll = {}

-- Limites des rotules (degrés) : assez souples pour s'affaisser, assez fermes pour ne pas se désarticuler
local JOINT_CONE = 55
local JOINT_TWIST = 40

type Corpse = { model: Model, bornAt: number, parts: { BasePart }, decals: { Decal } }

local corpses: { Corpse } = {}
local folder: Folder? = nil
local fadeConn: RBXScriptConnection? = nil

-- Cette méthode permet de retrouver (ou créer) le dossier local des corps lorsqu'un ragdoll est créé.
local function corpseFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "Ragdolls"
	created.Parent = workspace
	folder = created
	return created
end

-- Cette méthode permet de remplacer une articulation Motor6D par une rotule limitée lorsque le clone devient un
-- ragdoll ; les deux pièces ne se cognent plus entre elles (sinon le corps tremble).
local function toBallSocket(motor: Motor6D, p0: BasePart, p1: BasePart)
	local a0 = Instance.new("Attachment")
	a0.Name = "RagdollA0"
	a0.CFrame = motor.C0
	a0.Parent = p0
	local a1 = Instance.new("Attachment")
	a1.Name = "RagdollA1"
	a1.CFrame = motor.C1
	a1.Parent = p1
	local socket = Instance.new("BallSocketConstraint")
	socket.Attachment0 = a0
	socket.Attachment1 = a1
	socket.LimitsEnabled = true
	socket.UpperAngle = JOINT_CONE
	socket.TwistLimitsEnabled = true
	socket.TwistLowerAngle = -JOINT_TWIST
	socket.TwistUpperAngle = JOINT_TWIST
	socket.Parent = p0
	local noCollide = Instance.new("NoCollisionConstraint")
	noCollide.Part0 = p0
	noCollide.Part1 = p1
	noCollide.Parent = p0
end

-- Cette méthode permet de copier le personnage mort tel qu'il est affiché lorsque sa mort arrive : les personnages
-- joueurs ne sont pas Archivable, on lève le drapeau le temps du clonage.
local function cloneCharacter(char: Model): Model?
	local wasArchivable = char.Archivable
	char.Archivable = true
	local ok, clone = pcall(function()
		return char:Clone()
	end)
	char.Archivable = wasArchivable
	return if ok then clone else nil
end

-- Cette méthode permet de transformer le clone en corps inerte et articulé lorsqu'il vient d'être copié : scripts,
-- bouclier et étiquettes retirés, articulations du rig en rotules, autres soudures (arme, accessoires) gardées rigides.
local function rigClone(clone: Model): ({ BasePart }, { Decal })
	for _, inst in clone:GetDescendants() do
		if inst:IsA("LuaSourceContainer") or inst:IsA("ForceField") or inst:IsA("BillboardGui") then
			inst:Destroy()
		end
	end
	for _, inst in clone:GetDescendants() do
		if inst:IsA("Motor6D") then
			local p0, p1 = inst.Part0, inst.Part1
			local bodyJoint = p0
				and p1
				and p0.Parent == clone
				and p1.Parent == clone
				and p0.Name ~= "HumanoidRootPart"
				and p1.Name ~= "HumanoidRootPart"
			if bodyJoint then
				toBallSocket(inst, p0 :: BasePart, p1 :: BasePart)
				inst:Destroy()
			elseif p0 and p1 and p0.Name ~= "HumanoidRootPart" and p1.Name ~= "HumanoidRootPart" then
				-- Arme 3P ou accessoire monté sur Motor6D : soudure rigide
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = p0
				weld.Part1 = p1
				weld.Parent = p0
				inst:Destroy()
			else
				inst:Destroy()
			end
		end
	end
	local root = clone:FindFirstChild("HumanoidRootPart")
	if root then
		root:Destroy()
	end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Gardé pour l'apparence (vêtements), mais inerte
		humanoid.EvaluateStateMachine = false
		humanoid.BreakJointsOnDeath = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			animator:Destroy()
		end
	end

	local parts, decals = {}, {}
	for _, inst in clone:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.Anchored = false
			-- Ni raycast (mouvement, tirs) ni contact : le corps est un décor local
			inst.CanQuery = false
			inst.CanTouch = false
			local isBody = inst.Parent == clone
			inst.CanCollide = isBody
			inst.Massless = not isBody
			inst.LocalTransparencyModifier = 0
			table.insert(parts, inst)
		elseif inst:IsA("Decal") then
			table.insert(decals, inst)
		end
	end
	return parts, decals
end

-- Cette méthode permet de lire la vitesse d'un joueur au moment de sa mort lorsque son corps est créé : simulée pour
-- le joueur local, estimée d'après les positions relayées pour les autres.
local function velocityAtDeath(victim: Player): Vector3
	if victim == Players.LocalPlayer then
		return MovementController.getVelocity()
	end
	return CharacterSync.velocityOf(victim)
end

-- Cette méthode permet de retirer un corps et ses pièces lorsqu'il a fini de s'effacer ou qu'il faut faire de la place.
local function removeCorpse(index: number)
	local corpse = table.remove(corpses, index)
	if corpse then
		corpse.model:Destroy()
	end
end

-- Cette méthode permet d'estomper puis de retirer les corps lorsqu'ils vieillissent ; la boucle s'arrête quand il n'y
-- a plus de corps.
local function stepFade()
	local now = os.clock()
	for i = #corpses, 1, -1 do
		local corpse = corpses[i]
		local fade = DeathRules.ragdollFade(now - corpse.bornAt)
		if fade >= 1 then
			removeCorpse(i)
		elseif fade > 0 then
			for _, part in corpse.parts do
				part.LocalTransparencyModifier = fade
			end
			for _, decal in corpse.decals do
				decal.Transparency = fade
			end
		end
	end
	if #corpses == 0 and fadeConn then
		fadeConn:Disconnect()
		fadeConn = nil
	end
end

-- Cette méthode permet de remplacer le personnage d'un joueur tué par son ragdoll lorsque PlayerDied arrive ;
-- direction = du tueur vers la victime (nil pour une chute). Sans personnage encore présent, rien n'est créé.
function DeathRagdoll.spawn(victim: Player, direction: Vector3?, weapon: string?, headshot: boolean)
	local char = victim.Character
	if not char or not char.Parent then
		return
	end
	local clone = cloneCharacter(char)
	if not clone then
		return
	end
	local parts, decals = rigClone(clone)
	if #parts == 0 then
		clone:Destroy()
		return
	end

	-- L'original reste en place jusqu'à sa destruction par le serveur : on le masque
	for _, inst in char:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.LocalTransparencyModifier = 1
		end
	end

	while #corpses >= DeathRules.MAX_RAGDOLLS do
		removeCorpse(1)
	end
	clone.Name = victim.Name .. "_Ragdoll"
	clone.Parent = corpseFolder()
	local velocity = DeathRules.ragdollVelocity(velocityAtDeath(victim), direction, weapon, headshot)
	for _, part in parts do
		part.AssemblyLinearVelocity = velocity
	end
	table.insert(corpses, { model = clone, bornAt = os.clock(), parts = parts, decals = decals })
	if not fadeConn then
		fadeConn = RunService.Heartbeat:Connect(stepFade)
	end
end

-- Cette méthode permet de retirer tous les corps lorsque le joueur quitte la partie (menu, fin de round).
function DeathRagdoll.clear()
	for i = #corpses, 1, -1 do
		removeCorpse(i)
	end
end

return DeathRagdoll
