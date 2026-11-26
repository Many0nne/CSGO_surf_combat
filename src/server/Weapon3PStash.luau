-- Réserve des modèles 3P déjà construits, par personnage (#607). Une arme rangée n'est plus détruite : son modèle part
-- dans un dossier du personnage sous ReplicatedStorage (hors du Workspace, donc ni rendu ni simulé, mais déjà connu
-- des clients). La ressortir n'est qu'un changement de parent, au lieu d'une copie, de soudures, d'un skin et d'un
-- ScaleTo par le serveur suivis de la réplication d'environ 70 instances à chaque client. Le modèle ressorti est
-- celui que WeaponThirdPerson.build construirait (même arme, même viewmodel, même skin) : rendu identique.
-- Un modèle n'est jamais réutilisé par un autre personnage (sa soudure tient la main de celui-ci) ; la réserve est
-- détruite avec le personnage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponThirdPerson = require(ReplicatedStorage.Shared.WeaponThirdPerson)

local Weapon3PStash = {}

Weapon3PStash.FOLDER_NAME = "Weapon3PStash"
-- Modèles gardés au plus par personnage (couteau, fusil, pistolet, plus un skin changé) ; le plus ancien part au-delà
Weapon3PStash.MAX_PER_CHARACTER = 4

type Builder = (Model, string, string?, string?) -> Model?
type Entry = { folder: Folder, order: { Model } }

local stashes: { [Model]: Entry } = setmetatable({}, { __mode = "k" }) :: any
-- Clé (arme, viewmodel, skin) de chaque modèle construit ici, gardée hors des attributs (rien de plus n'est répliqué)
local keys: { [Model]: string } = setmetatable({}, { __mode = "k" }) :: any
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

-- Cette méthode permet de lire la réserve d'un personnage lorsqu'une arme y entre (create) ou en sort ; créée au
-- premier rangement et détruite avec le personnage.
local function stashOf(char: Model, create: boolean): Entry?
	local entry = stashes[char]
	if entry and entry.folder.Parent then
		return entry
	end
	if not create then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = char.Name
	folder.Parent = root()
	local created: Entry = { folder = folder, order = {} }
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
local function put(entry: Entry, gun: Model)
	gun:RemoveTag(WeaponThirdPerson.TAG)
	gun.Parent = entry.folder
	table.insert(entry.order, gun)
	while #entry.order > Weapon3PStash.MAX_PER_CHARACTER do
		local oldest = table.remove(entry.order, 1) :: Model
		keys[oldest] = nil
		oldest:Destroy()
	end
end

-- Cette méthode permet de sortir de la réserve le modèle d'une clé lorsqu'une arme est équipée ; nil s'il n'y est pas.
local function take(entry: Entry, key: string): Model?
	for index, gun in entry.order do
		if keys[gun] == key then
			table.remove(entry.order, index)
			if gun.Parent == entry.folder then
				return gun
			end
			return nil
		end
	end
	return nil
end

-- Cette méthode permet de construire d'avance le modèle d'une arme et de le ranger dans la réserve lorsqu'un personnage
-- est préparé hors du jeu (bot, #607) : sa mise en main ne sera qu'un changement de parent.
function Weapon3PStash.prepare(char: Model, weaponName: string, viewmodelName: string?, skinId: string?)
	local key = Weapon3PStash.key(weaponName, viewmodelName, skinId)
	local entry = stashOf(char, true) :: Entry
	for _, gun in entry.order do
		if keys[gun] == key then
			return
		end
	end
	local gun = builder(char, weaponName, viewmodelName, skinId)
	if gun then
		keys[gun] = key
		put(entry, gun)
	end
end

-- Cette méthode permet de ranger le modèle 3P en main lorsque l'arme quitte la main ou est remplacée : gardé dans la
-- réserve s'il vient d'ici, détruit sinon ; actions 3P effacées (comme WeaponThirdPerson.detach).
function Weapon3PStash.unequip(char: Model)
	local gun = char:FindFirstChild(WeaponThirdPerson.MODEL_NAME)
	if gun and gun:IsA("Model") and keys[gun] then
		put(stashOf(char, true) :: Entry, gun)
	elseif gun then
		gun:Destroy()
	end
	char:SetAttribute(WeaponThirdPerson.ACTION_ATTR, nil)
	char:SetAttribute(WeaponThirdPerson.ACTION_AT_ATTR, nil)
end

-- Cette méthode permet de mettre en main le modèle 3P d'une arme lorsqu'un personnage l'équipe : celui de la réserve
-- s'il existe (changement de parent), sinon construit ; renvoie le modèle, nil sans main ni viewmodel.
function Weapon3PStash.equip(char: Model, weaponName: string, viewmodelName: string?, skinId: string?): Model?
	Weapon3PStash.unequip(char)
	local key = Weapon3PStash.key(weaponName, viewmodelName, skinId)
	local entry = stashOf(char, false)
	local gun = if entry then take(entry, key) else nil
	if not gun then
		gun = builder(char, weaponName, viewmodelName, skinId)
		if not gun then
			return nil
		end
		keys[gun] = key
	end
	WeaponThirdPerson.mount(char, gun)
	return gun
end

-- Cette méthode permet de compter les modèles rangés d'un personnage lorsqu'un test ou une mesure le demande.
function Weapon3PStash.count(char: Model): number
	local entry = stashOf(char, false)
	return if entry then #entry.order else 0
end

return Weapon3PStash
