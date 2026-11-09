-- Armes d'un bot (#143), une par bot vivant : AWP et couteau copiés du StarterPack (sans scripts), un seul en main
-- (l'autre rangé dans un dossier du personnage, comme un sac), avec les mêmes contraintes qu'un joueur : temps de
-- sortie, cadence, chargeur, réserve et rechargement de WeaponConfig. Le tir part du regard réel du bot
-- (BotCombatRules) en vrai raycast ; la touche est ensuite validée par le serveur comme celle d'un joueur (onHit).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")

local BotCombatRules = require(ReplicatedStorage.Shared.BotCombatRules)
local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local WeaponThirdPerson = require(ReplicatedStorage.Shared.WeaponThirdPerson)

-- Touche d'un bot à valider (personnage visé, partie touchée ; nil pour un coup de couteau)
export type OnHit = (targetCharacter: Model, hitPart: BasePart?) -> ()

local BotArsenal = {}
BotArsenal.__index = BotArsenal

local BAG_NAME = "BotBag"
local MAX_RAY = 2048 -- longueur du rayon d'un tir (comme HitscanSystem côté client)

export type BotArsenal = typeof(setmetatable(
	{} :: {
		char: Model,
		bag: Folder,
		tools: { [string]: Tool },
		current: string?,
		readyAt: number, -- arme sortie et réarmée à partir de cet instant (os.clock)
		ammo: number,
		reserve: number,
		reloadEndsAt: number?,
		params: RaycastParams,
		onHit: OnHit,
		onWeapon: (string) -> (), -- arme changée (vitesse de course)
	},
	BotArsenal
))

-- Cette méthode permet de copier un outil du StarterPack sans ses scripts lorsqu'un bot apparaît (logique d'arme
-- côté client, inutile au bot) ; nil s'il est introuvable.
local function copyTool(name: string): Tool?
	local source = StarterPack:FindFirstChild(name)
	if not source or not source:IsA("Tool") then
		warn("[BotArsenal] outil " .. name .. " introuvable dans StarterPack")
		return nil
	end
	local tool = source:Clone()
	for _, inst in tool:GetDescendants() do
		if inst:IsA("BaseScript") then
			inst:Destroy()
		end
	end
	return tool
end

-- Cette méthode permet de créer les armes d'un bot lorsqu'il apparaît : fusil en main, couteau rangé.
function BotArsenal.new(char: Model, onHit: OnHit, onWeapon: (string) -> ()): BotArsenal
	local bag = Instance.new("Folder")
	bag.Name = BAG_NAME
	bag.Parent = char
	local tools = {}
	for _, name in { BotCombatRules.RIFLE, BotCombatRules.KNIFE } do
		local tool = copyTool(name)
		if tool then
			tool.Parent = bag
			tools[name] = tool
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local rifle = WeaponConfig.Weapons[BotCombatRules.RIFLE]
	local self = setmetatable({
		char = char,
		bag = bag,
		tools = tools,
		current = nil,
		readyAt = 0,
		ammo = rifle.Magazine or 0,
		reserve = rifle.Reserve or 0,
		reloadEndsAt = nil,
		params = params,
		onHit = onHit,
		onWeapon = onWeapon,
	}, BotArsenal)
	self:equip(BotCombatRules.RIFLE, os.clock())
	return self
end

-- Cette méthode permet de lire la fiche de l'arme en main lorsqu'on règle un tir ou une vitesse.
function BotArsenal.config(self: BotArsenal): any
	return self.current and WeaponConfig.Weapons[self.current]
end

-- Cette méthode permet de mettre une arme en main lorsque le bot en change : l'autre retourne dans le sac, l'arme
-- n'est prête qu'après son temps de sortie (rechargement interrompu, comme chez le joueur).
function BotArsenal.equip(self: BotArsenal, name: string, now: number)
	local tool = self.tools[name]
	if not tool or self.current == name then
		return
	end
	local previous = self.current and self.tools[self.current]
	if previous then
		previous.Parent = self.bag
	end
	tool.Parent = self.char
	self.current = name
	self.reloadEndsAt = nil
	local cfg = WeaponConfig.Weapons[name]
	self.readyAt = now + (cfg and cfg.EquipTime or 0)
	self.onWeapon(name)
end

-- Cette méthode permet de lancer un rechargement du fusil lorsque son chargeur n'est pas plein et qu'il reste une
-- réserve (chargeur vide, ou rien à viser).
function BotArsenal._startReload(self: BotArsenal, now: number)
	local cfg = self:config()
	if self.reloadEndsAt or not cfg or cfg.IsMelee or self.reserve <= 0 or self.ammo >= (cfg.Magazine or 0) then
		return
	end
	self.reloadEndsAt = now + (cfg.ReloadTime or 0)
	WeaponThirdPerson.setAction(self.char, "Reload")
end

-- Cette méthode permet de faire avancer les armes lorsque le bot réfléchit : rechargement terminé (chargeur rempli
-- depuis la réserve), ou lancé s'il n'a rien à viser et que son chargeur n'est pas plein.
function BotArsenal.update(self: BotArsenal, now: number, idle: boolean)
	local endsAt = self.reloadEndsAt
	if endsAt and now >= endsAt then
		self.reloadEndsAt = nil
		local cfg = WeaponConfig.Weapons[BotCombatRules.RIFLE]
		local moved = math.min((cfg.Magazine or 0) - self.ammo, self.reserve)
		self.ammo += moved
		self.reserve -= moved
	elseif idle and self.current == BotCombatRules.RIFLE then
		self:_startReload(now)
	end
end

-- Cette méthode permet de savoir si l'arme en main peut tirer lorsque le bot vise : sortie, réarmée, et pour le
-- fusil chargée et hors rechargement.
function BotArsenal.isReady(self: BotArsenal, now: number): boolean
	local cfg = self:config()
	if not cfg or now < self.readyAt then
		return false
	end
	return cfg.IsMelee or (self.ammo > 0 and self.reloadEndsAt == nil)
end

-- Cette méthode permet de lire la portée de l'arme en main lorsque le bot décide de tirer.
function BotArsenal.range(self: BotArsenal): number
	local cfg = self:config()
	return if cfg and cfg.IsMelee then BotConfig.KNIFE_HIT_RANGE else BotConfig.FIRE_RANGE
end

-- Cette méthode permet de trouver le personnage d'une partie touchée lorsqu'un rayon s'arrête (accessoire compris,
-- comme HitscanSystem côté client) ; nil pour un décor.
local function characterOf(part: Instance): Model?
	local model = part.Parent
	for _ = 1, 2 do
		if model and model:IsA("Model") and model:FindFirstChildWhichIsA("Humanoid") then
			return model
		end
		model = model and model.Parent
	end
	return nil
end

-- Cette méthode permet de tirer lorsque le bot a décidé de le faire : au fusil, rayon des yeux dans la direction
-- donnée (déjà dispersée), touche envoyée à la validation ; au couteau, coup porté à la cible. Cadence, chargeur et
-- action 3P comme chez un joueur ; renvoie le point d'arrivée du tir (debug).
function BotArsenal.fire(self: BotArsenal, now: number, eye: Vector3, direction: Vector3, target: Model): Vector3?
	local cfg = self:config()
	if not cfg or not self:isReady(now) then
		return nil
	end
	self.readyAt = now + (cfg.FireDelay or 0)
	WeaponThirdPerson.setAction(self.char, "Shoot")
	if cfg.IsMelee then
		self.onHit(target, nil)
		return nil
	end
	self.ammo -= 1
	local result = workspace:Raycast(eye, direction * MAX_RAY, self.params)
	if result then
		local victim = characterOf(result.Instance)
		if victim and result.Instance:IsA("BasePart") then
			self.onHit(victim, result.Instance)
		end
	end
	if self.ammo <= 0 then
		-- Comme le joueur : il recharge dès le chargeur vide, une fois l'arme réarmée
		self.readyAt = math.max(self.readyAt, now)
		self:_startReload(self.readyAt)
	end
	return if result then result.Position else eye + direction * MAX_RAY
end

return BotArsenal
