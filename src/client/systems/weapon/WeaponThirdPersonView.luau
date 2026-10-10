-- WeaponThirdPersonView.luau
-- Rendu client des armes 3e personne (#5) de tous les personnages (joueurs et bots).
-- Le serveur attache les modèles (WeaponThirdPerson.attach, tag "Weapon3P") et pose l'action
-- courante en attributs ; ici, chaque frame : décalage procédural du grip (tir/recharge/switch)
-- et visibilité (le joueur local ne voit pas son propre modèle 3P en 1re personne).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WeaponThirdPerson = require(ReplicatedStorage.Shared.WeaponThirdPerson)

local WeaponThirdPersonView = {}

-- Distance caméra ↔ tête en dessous de laquelle on considère être en 1re personne.
local FIRST_PERSON_DISTANCE = 2

local settingsCache: { [string]: any } = {}

-- Cette méthode permet de mémoriser les réglages 3P par arme lorsqu'on anime un modèle chaque frame.
local function getSettings(weaponName: string)
	local s = settingsCache[weaponName]
	if not s then
		s = WeaponThirdPerson.getSettings(weaponName)
		settingsCache[weaponName] = s
	end
	return s
end

-- Cette méthode permet d'appliquer une transparence locale à toutes les pièces d'un modèle 3P
-- lorsque sa visibilité pour ce client est recalculée.
local function setLocalVisible(gun: Instance, visible: boolean)
	local modifier = if visible then 0 else 1
	for _, inst in gun:GetDescendants() do
		if inst:IsA("BasePart") and inst.LocalTransparencyModifier ~= modifier then
			inst.LocalTransparencyModifier = modifier
		end
	end
end

-- Cette méthode permet de mettre à jour un modèle 3P lorsqu'une frame est rendue : visibilité
-- puis C0 du grip = grip de base * décalage de l'action en cours.
local function updateGun(gun: Instance, localChar: Model?, camPos: Vector3?)
	local char = gun.Parent
	if not char or not char:IsA("Model") then
		return
	end

	local own = char == localChar
	local firstPerson = false
	if own and camPos then
		local head = char:FindFirstChild("Head")
		firstPerson = head ~= nil
			and head:IsA("BasePart")
			and (head.Position - camPos).Magnitude < FIRST_PERSON_DISTANCE
	end
	setLocalVisible(gun, WeaponThirdPerson.isVisibleTo(own, firstPerson))

	local handle = gun:FindFirstChild("Handle")
	local weld = handle and handle:FindFirstChild(WeaponThirdPerson.WELD_NAME)
	local grip = gun:GetAttribute("GripC0")
	if not (weld and weld:IsA("Weld") and typeof(grip) == "CFrame") then
		return
	end
	local action = char:GetAttribute(WeaponThirdPerson.ACTION_ATTR)
	local at = char:GetAttribute(WeaponThirdPerson.ACTION_AT_ATTR)
	local offset = CFrame.identity
	if type(action) == "string" and type(at) == "number" then
		local weaponName = gun:GetAttribute("WeaponName")
		local settings = getSettings(if type(weaponName) == "string" then weaponName else "")
		offset = WeaponThirdPerson.actionOffset(action, workspace:GetServerTimeNow() - at, settings)
	end
	weld.C0 = grip * offset
end

-- Cette méthode permet de démarrer la boucle de rendu des armes 3P lorsque le client s'initialise.
function WeaponThirdPersonView.init()
	RunService.RenderStepped:Connect(function()
		local localChar = Players.LocalPlayer and Players.LocalPlayer.Character
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position
		for _, gun in CollectionService:GetTagged(WeaponThirdPerson.TAG) do
			updateGun(gun, localChar, camPos)
		end
	end)
end

return WeaponThirdPersonView
