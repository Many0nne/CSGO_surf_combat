-- Réserve des modèles 3P déjà construits, par personnage (#607). Une arme rangée n'est plus détruite : son modèle part
-- dans un dossier du personnage sous ReplicatedStorage (hors du Workspace, donc ni rendu ni simulé, mais déjà connu
-- des clients). La ressortir n'est qu'un changement de parent, au lieu d'une copie, de soudures, d'un skin et d'un
-- ScaleTo par le serveur suivis de la réplication d'environ 70 instances à chaque client. Le modèle ressorti est
-- celui que WeaponThirdPerson.build construirait (même arme, même viewmodel, même skin) : rendu identique.
-- Un modèle n'est jamais réutilisé par un autre personnage (sa soudure tient la main de celui-ci) ; la réserve est
-- détruite avec le personnage. Références fortes seulement (une table faible indexée par une Instance peut perdre son
-- entrée quand Roblox recrée l'objet Lua de l'Instance), libérées à la destruction ou au départ du personnage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponThirdPerson = require(ReplicatedStorage.Shared.WeaponThirdPerson)

local Weapon3PStash = {}

Weapon3PStash.FOLDER_NAME = "Weapon3PStash"
-- Modèles gardés au plus par personnage (couteau, fusil, pistolet, plus un skin changé) ; le plus ancien part au-delà
Weapon3PStash.MAX_PER_CHARACTER = 4

type Builder = (Model, string, string?, string?) -> Model?
-- Modèle construit ici et sa clé (arme, viewmodel, skin), gardée hors des attributs : rien de plus n'est répliqué
type Gun = { model: Model, key: string }
-- Réserve d'un personnage : dossier, modèles rangés (le plus ancien d'abord) et modèle en main
type Entry = { folder: Folder, order: { Gun }, held: Gun? }

local stashes: { [Model]: Entry } = {}
local rootFolder: Folder? = nil
local builder: Builder = WeaponThirdPerson.build

-- Cette méthode permet de calculer la clé d'un modèle 3P lorsqu'on cherche s'il est déjà construit : arme, viewmodel
-- et skin (nil : d'origine).
function Weapon3PStash.key(weaponName: string, viewmodelName: string?, skinId: string?): string
	return weaponName .. "|" .. (viewmodelName or weaponName) .. "|" .. (skinId or "")
end

-- Cette méthode permet de remplacer la construction d'un modèle lorsqu'un test la simule (nil : WeaponThirdPerson.build).
function Weapon3PStash.setBuilder(value: Builder?)
	builder = value or WeaponThirdPerson.build
end

-- Cette méthode permet de retrouver (ou créer) le dossier commun des réserves lorsqu'une réserve est créée.
local function root(): Folder
	local folder = rootFolder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = Weapon3PStash.FOLDER_NAME
	created.Parent = ReplicatedStorage
	rootFolder = created
	return created
end

-- Cette méthode permet d'oublier et détruire la réserve d'un personnage lorsqu'il est détruit ou quitte le jeu.
local function release(char: Model)
	local entry = stashes[char]
	if entry then
		stashes[char] = nil
		entry.folder:Destroy()
	end
end

-- Cette méthode permet de lire la réserve d'un personnage lorsqu'une arme entre en main ou en sort : créée à la
-- première, détruite avec le personnage.
local function stashOf(char: Model): Entry
	local entry = stashes[char]
	if entry and entry.folder.Parent then
		return entry
	end
	local folder = Instance.new("Folder")
	folder.Name = char.Name
	folder.Parent = root()
	local created: Entry = { folder = folder, order = {}, held = nil }
	stashes[char] = created
	char.Destroying:Once(function()
		release(char)
	end)
	char.AncestryChanged:Connect(function()
		if char.Parent == nil then
			release(char)
		end
	end)
	return created
end

-- Cette méthode permet de ranger un modèle dans la réserve lorsqu'il quitte la main ou qu'il est préparé d'avance :
-- tag retiré (les clients cessent de l'animer), le plus ancien détruit au-delà de MAX_PER_CHARACTER.
local function put(entry: Entry, gun: Gun)
	gun.model:RemoveTag(WeaponThirdPerson.TAG)
	gun.model.Parent = entry.folder
	table.insert(entry.order, gun)
	while #entry.order > Weapon3PStash.MAX_PER_CHARACTER do
		local oldest = table.remove(entry.order, 1) :: Gun
		oldest.model:Destroy()
	end
end

-- Cette méthode permet de sortir de la réserve le modèle d'une clé lorsqu'une arme est équipée ; nil s'il n'y est pas.
local function take(entry: Entry, key: string): Gun?
	for index, gun in entry.order do
		if gun.key == key then
			table.remove(entry.order, index)
			return if gun.model.Parent == entry.folder then gun else nil
		end
	end
	return nil
end

-- Cette méthode permet de construire d'avance le modèle d'une arme et de le ranger dans la réserve lorsqu'un personnage
-- est préparé hors du jeu (bot, #607) : sa mise en main ne sera qu'un changement de parent.
function Weapon3PStash.prepare(char: Model, weaponName: string, viewmodelName: string?, skinId: string?)
	local key = Weapon3PStash.key(weaponName, viewmodelName, skinId)
	local entry = stashOf(char)
	for _, gun in entry.order do
		if gun.key == key then
			return
		end
	end
	local model = builder(char, weaponName, viewmodelName, skinId)
	if model then
		put(entry, { model = model, key = key })
	end
end

-- Cette méthode permet de ranger le modèle 3P en main lorsque l'arme quitte la main ou est remplacée : gardé dans la
-- réserve s'il vient d'ici, détruit sinon ; actions 3P effacées (comme WeaponThirdPerson.detach).
function Weapon3PStash.unequip(char: Model)
	local entry = stashes[char]
	local held = entry and entry.held
	local current = char:FindFirstChild(WeaponThirdPerson.MODEL_NAME)
	if entry and held and current == held.model then
		entry.held = nil
		put(entry, held)
	elseif current then
		current:Destroy()
	end
	char:SetAttribute(WeaponThirdPerson.ACTION_ATTR, nil)
	char:SetAttribute(WeaponThirdPerson.ACTION_AT_ATTR, nil)
end

-- Cette méthode permet de mettre en main le modèle 3P d'une arme lorsqu'un personnage l'équipe : celui de la réserve
-- s'il existe (changement de parent), sinon construit ; renvoie le modèle, nil sans main ni viewmodel.
function Weapon3PStash.equip(char: Model, weaponName: string, viewmodelName: string?, skinId: string?): Model?
	local key = Weapon3PStash.key(weaponName, viewmodelName, skinId)
	local entry = stashOf(char)
	-- Sorti de la réserve avant d'y ranger l'arme en main : ce rangement peut évincer le plus ancien modèle
	local gun = take(entry, key)
	Weapon3PStash.unequip(char)
	if not gun then
		local model = builder(char, weaponName, viewmodelName, skinId)
		if not model then
			return nil
		end
		gun = { model = model, key = key }
	end
	local held = gun :: Gun
	entry.held = held
	WeaponThirdPerson.mount(char, held.model)
	return held.model
end

-- Cette méthode permet de compter les modèles rangés d'un personnage lorsqu'un test ou une mesure le demande.
function Weapon3PStash.count(char: Model): number
	local entry = stashes[char]
	return if entry then #entry.order else 0
end

return Weapon3PStash
