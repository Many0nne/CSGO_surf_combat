local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local WeaponSystem = {}

local ViewmodelSystem    = require(script.Parent.ViewmodelSystem)
local ScopeSystem        = require(script.Parent.ScopeSystem)
local MeleeHitDetection  = require(script.Parent.MeleeHitDetection)
local HitscanSystem      = require(script.Parent.HitscanSystem)
local FPSCamera          = require(script.Parent.Parent.Parent.camera.FPSCamera)
local InputModule        = require(script.Parent.Parent.Parent.input.InputModule)
local WeaponConfig       = require(ReplicatedStorage.Shared.WeaponConfig)

-- Per-tool runtime state (stored on the client)
local toolState = {} -- [tool] = { ammo, reserve, magazine, lastFire }

local meleeEvent   = ReplicatedStorage:WaitForChild("MeleeDamage", 10) :: RemoteEvent?
local hitscanEvent = ReplicatedStorage:WaitForChild("HitscanDamage", 10) :: RemoteEvent?

local currentTool = nil :: Tool?
local currentCfg  = nil
local scopeConn   = nil :: RBXScriptConnection?

-- Weapon action state machine
-- Transitions : IDLE ↔ SCOPED, IDLE → EQUIPPING → IDLE,
--               IDLE → RELOADING → IDLE, IDLE/SCOPED → FIRING → IDLE/SCOPED
local weaponState: string = "IDLE"
local cancelReload: (() -> ())? = nil

local function canAct(): boolean
	return weaponState == "IDLE" or weaponState == "SCOPED"
end

local function ensureAmmoState(tool, cfg)
	if toolState[tool] then return toolState[tool] end
	local s = {}
	s.magazine = cfg and cfg.Magazine or 0
	s.reserve  = cfg and cfg.Reserve or 0
	s.ammo     = s.magazine
	s.lastFire = 0
	toolState[tool] = s
	return s
end

local function clearAmmoState(tool)
	toolState[tool] = nil
end

local function getWeaponConfig(name)
	if not name or not WeaponConfig.Weapons then return nil end
	return WeaponConfig.Weapons[name]
end

local function createSpeedValueForChar(char, mult)
	if not char then return end
	local existing = char:FindFirstChild("WeaponSpeedMultiplier")
	if existing and existing:IsA("NumberValue") then
		existing.Value = mult
		return existing
	end
	local nv = Instance.new("NumberValue")
	nv.Name   = "WeaponSpeedMultiplier"
	nv.Value  = mult
	nv.Parent = char
	return nv
end

local function removeSpeedValue(char)
	if not char then return end
	local existing = char:FindFirstChild("WeaponSpeedMultiplier")
	if existing and existing:IsA("NumberValue") then
		existing:Destroy()
	end
end

local function reloadTool(tool, cfg)
	if not canAct() then return end
	local s = ensureAmmoState(tool, cfg)
	local fireDelay = cfg and cfg.FireDelay or 0
	if tick() - s.lastFire < fireDelay then return end
	if s.ammo >= (cfg and cfg.Magazine or 0) then return end
	if s.reserve <= 0 then return end

	ScopeSystem.resetVisuals()
	weaponState = "RELOADING"
	ViewmodelSystem.playReload(ViewmodelSystem.getActiveViewmodel())

	local reloadTime = cfg and cfg.ReloadTime or 2
	local thread = task.delay(reloadTime, function()
		cancelReload = nil
		if currentTool ~= tool then return end
		local needed = (cfg and cfg.Magazine or 0) - s.ammo
		local used   = math.min(needed, s.reserve)
		s.ammo    = s.ammo + used
		s.reserve = s.reserve - used
		weaponState = "IDLE"
	end)

	cancelReload = function()
		task.cancel(thread)
		cancelReload = nil
	end
end

local function onToolActivated(tool)
	local cfg = getWeaponConfig(tool:GetAttribute("WeaponName") or tool.Name)
	local s   = ensureAmmoState(tool, cfg)
	local now = tick()
	local firedelay = cfg and cfg.FireDelay or 0.1

	if not canAct() then return end
	if not (cfg and cfg.IsMelee) then
		if s.ammo <= 0 then
			reloadTool(tool, cfg)
			return
		end
	end
	if now - s.lastFire < firedelay then return end

	if not (cfg and cfg.IsMelee) then
		s.ammo = s.ammo - 1
	end
	s.lastFire = now
	weaponState = "FIRING"
	if cfg and cfg.IsMelee then
		ViewmodelSystem.playAnimation("Shoot", {
			["Stab Sound"] = function()
				return MeleeHitDetection.resolveHit(cfg, ViewmodelSystem.getActiveViewmodel())
			end
		})
	else
		ViewmodelSystem.playAnimation("Shoot")
	end
	ScopeSystem.resetVisuals()
	if not (cfg and cfg.IsMelee) then
		HitscanSystem.resolveHit(cfg, ViewmodelSystem.getActiveViewmodel())
	end
	local shootAnimTime = cfg and cfg.ShootAnimTime or 0.4
	task.delay(shootAnimTime, function()
		if currentTool == tool and weaponState == "FIRING" then
			weaponState = "IDLE"
		end
	end)
end

local function onToolEquipped(tool, char)
	if not tool or not char then return end
	local cfg = getWeaponConfig(tool:GetAttribute("WeaponName") or tool.Name)
	ensureAmmoState(tool, cfg)
	currentTool = tool
	currentCfg  = cfg
	weaponState = "EQUIPPING"

	if cfg and cfg.RunSpeedMultiplier then
		createSpeedValueForChar(char, cfg.RunSpeedMultiplier)
	end

	local equipTime = cfg and cfg.EquipTime or 0.8
	local animLength = ViewmodelSystem.getPreloadedTrackLength("Equip")
	local actualEquipTime = (animLength > 0 and animLength) or equipTime
	task.delay(actualEquipTime, function()
		if currentTool == tool and weaponState == "EQUIPPING" then
			weaponState = "IDLE"
		end
	end)

	if cfg and cfg.HasScope then
		scopeConn = UserInputService.InputBegan:Connect(function(input, gp)
			if gp then return end
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				if not canAct() then return end
				weaponState = ScopeSystem.toggle(cfg)
			end
		end)
	end

	if not tool:GetAttribute("_WeaponSystemBound") then
		tool.Activated:Connect(function()
			onToolActivated(tool)
		end)
		tool:SetAttribute("_WeaponSystemBound", true)
	end
end

local function onToolUnequipped(tool, char)
	if cancelReload then cancelReload() end
	if scopeConn then scopeConn:Disconnect(); scopeConn = nil end
	ScopeSystem.reset()
	weaponState = "IDLE"
	currentTool = nil
	currentCfg  = nil
	removeSpeedValue(char)
end

local function hookTool(tool, player)
	if not tool:IsA("Tool") then return end
	if tool:GetAttribute("_WeaponHookBound") then return end
	tool:SetAttribute("_WeaponHookBound", true)

	tool.Equipped:Connect(function()
		onToolEquipped(tool, player.Character)
	end)
	tool.Unequipped:Connect(function()
		onToolUnequipped(tool, player.Character)
	end)
end

function WeaponSystem.getSpeedMultiplier()
	local player = Players.LocalPlayer
	local char   = player and player.Character
	if not char then return 1 end
	local nv = char:FindFirstChild("WeaponSpeedMultiplier")
	if nv and nv:IsA("NumberValue") then
		return nv.Value
	end
	return 1
end

function WeaponSystem.reloadCurrent(tool)
	if not tool then return end
	local cfg = getWeaponConfig(tool:GetAttribute("WeaponName") or tool.Name)
	reloadTool(tool, cfg)
end

function WeaponSystem.init(player)
	local pl = player or Players.LocalPlayer
	if not pl then return end

	ScopeSystem.init(FPSCamera, ViewmodelSystem)
	MeleeHitDetection.init(meleeEvent)
	HitscanSystem.init(hitscanEvent)

	RunService.Heartbeat:Connect(function()
		if InputModule.isReloadPressed() and currentTool and currentCfg then
			reloadTool(currentTool, currentCfg)
		end
	end)

	local backpack = pl:WaitForChild("Backpack", 5)
	if backpack then
		for _, child in backpack:GetChildren() do
			hookTool(child, pl)
		end
		backpack.ChildAdded:Connect(function(child)
			hookTool(child, pl)
		end)
	end

	if pl.Character then
		for _, child in pl.Character:GetChildren() do
			hookTool(child, pl)
		end
	end
	pl.CharacterAdded:Connect(function(char)
		if cancelReload then cancelReload() end
		ScopeSystem.reset()
		weaponState = "IDLE"
		currentTool = nil
		currentCfg  = nil
		for _, child in char:GetChildren() do
			hookTool(child, pl)
		end
		char.ChildAdded:Connect(function(c)
			hookTool(c, pl)
		end)
	end)
end

return WeaponSystem
