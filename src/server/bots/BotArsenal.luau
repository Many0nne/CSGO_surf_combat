-- Armes d'un bot (#143), une par bot vivant : AWP et couteau (Ka-Bar) copiés de ReplicatedStorage.Tools (sans scripts)
-- parmi ceux de l'inventaire par défaut (#267, InventoryRules), un seul en main
-- (l'autre rangé dans un dossier du personnage, comme un sac), avec les mêmes contraintes qu'un joueur : temps de
-- sortie, cadence, chargeur, réserve et rechargement de WeaponConfig. Le tir part du regard réel du bot
-- (BotCombatRules) en vrai raycast ; la touche est ensuite validée par le serveur comme celle d'un joueur (onHit).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BotCombatRules = require(ReplicatedStorage.Shared.BotCombatRules)
local BotConfig = require(ReplicatedStorage.Shared.BotConfig)
local InventoryRules = require(ReplicatedStorage.Shared.InventoryRules)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local WeaponThirdPerson = require(ReplicatedStorage.Shared.WeaponThirdPerson)
local SpawnProtection = require(ServerScriptService.Server.SpawnProtection)

-- Touche d'un bot à valider (personnage visé, partie touchée ; nil pour un coup de couteau)
export type OnHit = (targetCharacter: Model, hitPart: BasePart?) -> ()
-- Tir au fusil parti, touché ou manqué (origine = yeux, direction unitaire) : relayé aux joueurs pour le son (#156) et
-- le recul 3P (#215) ; renvoie true si le relais l'a accepté
export type OnFire = (origin: Vector3, direction: Vector3) -> boolean

local BotArsenal = {}
BotArsenal.__index = BotArsenal

local BAG_NAME = "BotBag"

export type BotArsenal = typeof(setmetatable(
	{} :: {
		char: Model,
		bag: Folder,
		tools: { [string]: Tool },
		current: string?,
		readyAt: number, -- arme sortie et réarmée à partir de cet instant (os.clock)
		ammo: number,
		reloadEndsAt: number?,
		params: RaycastParams,
		onHit: OnHit,
		onWeapon: (string) -> (), -- arme changée (vitesse de course)
		onFire: OnFire?,
	},
	BotArsenal
))

-- Inventaire d'un bot (#267) : celui par défaut
local BOT_OWNED = InventoryRules.resolve(nil, false)

-- Cette méthode permet de copier un outil de ReplicatedStorage.Tools sans ses scripts lorsqu'un bot apparaît (logique
-- d'arme côté client, inutile au bot) ; nil s'il est introuvable ou hors de l'inventaire par défaut.
local function copyTool(name: string): Tool?
	if not InventoryRules.ownsTool(BOT_OWNED, name) then
		warn("[BotArsenal] outil " .. name .. " hors de l'inventaire par défaut des bots")
		return nil
	end
	local folder = ReplicatedStorage:FindFirstChild("Tools")
	local source = folder and folder:FindFirstChild(name)
	if not source or not source:IsA("Tool") then
		warn("[BotArsenal] outil " .. name .. " introuvable dans ReplicatedStorage.Tools")
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
function BotArsenal.new(char: Model, onHit: OnHit, onWeapon: (string) -> (), onFire: OnFire?): BotArsenal
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
		reloadEndsAt = nil,
		params = params,
		onHit = onHit,
		onWeapon = onWeapon,
		onFire = onFire,
	}, BotArsenal)
	self:equip(BotCombatRules.RIFLE, os.clock())
	return self
end

-- Cette méthode permet de faire traverser des instances aux tirs du bot lorsque son comportement est branché : murs
-- d'air et grillages de la map (MapGeometry.bulletTransparent, #292), en plus de son propre personnage.
function BotArsenal.ignore(self: BotArsenal, instances: { Instance })
	local ignored = table.clone(instances)
	table.insert(ignored, self.char)
	self.params.FilterDescendantsInstances = ignored
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

-- Cette méthode permet de lancer un rechargement du fusil lorsque son chargeur n'est pas plein (réserve
-- illimitée : chargeur vide, ou rien à viser).
function BotArsenal._startReload(self: BotArsenal, now: number)
	local cfg = self:config()
	if self.reloadEndsAt or not cfg or cfg.IsMelee or self.ammo >= (cfg.Magazine or 0) then
		return
	end
	self.reloadEndsAt = now + (cfg.ReloadTime or 0)
	WeaponThirdPerson.setAction(self.char, "Reload")
end

-- Cette méthode permet de faire avancer les armes lorsque le bot réfléchit : rechargement terminé (chargeur rempli), ou lancé
-- s'il n'a rien à viser et que son chargeur n'est pas plein.
function BotArsenal.update(self: BotArsenal, now: number, idle: boolean)
	local endsAt = self.reloadEndsAt
	if endsAt and now >= endsAt then
		self.reloadEndsAt = nil
		local cfg = WeaponConfig.Weapons[BotCombatRules.RIFLE]
		self.ammo = cfg.Magazine or 0 -- réserve illimitée : le chargeur est toujours rempli
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
	-- Premier tir ou coup du bot : sa protection d'apparition tombe (#288), même si le relais écarte le tir
	SpawnProtection.drop(self.char)
	if cfg.IsMelee then
		WeaponThirdPerson.setAction(self.char, "Shoot")
		self.onHit(target, nil)
		return nil
	end
	self.ammo -= 1
	-- Son du tir chez les joueurs (#156), avant la touche : comme chez un joueur, le tir s'entend avant ses dégâts ;
	-- le relais joue aussi le recul 3P (#215). Sans relais branché, ou tir écarté par le relais (le rayon part quand
	-- même), le recul est posé ici, comme avant #215
	if not (self.onFire and self.onFire(eye, direction)) then
		WeaponThirdPerson.setAction(self.char, "Shoot")
	end
	local result = workspace:Raycast(eye, direction * WeaponConfig.HITSCAN_RANGE, self.params)
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
	return if result then result.Position else eye + direction * WeaponConfig.HITSCAN_RANGE
end

return BotArsenal
