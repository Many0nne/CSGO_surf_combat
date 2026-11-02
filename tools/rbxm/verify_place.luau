-- verify_place.luau
-- Relit la place produite par `rojo build` et vérifie que les viewmodels (assets/rbx/ViewModels) et les Tools
-- (assets/rbx/Tools) y sont, avec leurs animations, sons, attributs et scripts. Signale aussi les Tools dont
-- le nom d'arme n'a pas d'entrée dans src/shared/WeaponConfig.luau (avertissement, sans échec).
-- Usage (racine du dépôt) : rojo build default.project.json -o CSGO.rbxlx && lune run tools/rbxm/verify_place.luau [CSGO.rbxlx]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local placePath = process.args[1] or "CSGO.rbxlx"
local game = roblox.deserializePlace(fs.readFile(placePath))
local errors = 0

-- Cette méthode permet de signaler une erreur bloquante lorsque la place ne contient pas ce qu'on attend.
local function fail(message: string)
	errors += 1
	print("ERREUR : " .. message)
end

-- Cette méthode permet de lister les noms des fichiers .rbxm d'un dossier lorsqu'on veut les retrouver dans la place.
local function rbxmNames(dir: string): { string }
	local names = {}
	for _, file in fs.readDir(dir) do
		local name = string.match(file, "^(.+)%.rbxm$")
		if name then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

-- propriétés d'id par classe : nom récent écrit par Studio, puis ancien nom
local ID_PROPS = {
	Animation = { "AnimationContent", "AnimationId" },
	Sound = { "AudioContent", "SoundId" },
	MeshPart = { "MeshContent", "MeshId" },
}

-- Cette méthode permet de relever les ids d'assets (animations, sons, meshes) en lisant le XML de la place
-- lorsque Studio les écrit sous leurs noms récents (AnimationContent, AudioContent, MeshContent), que Lune 0.9 ignore.
local function scanAssetIds(xml: string): { [string]: { { name: string, uri: string? } } }
	local found = { Animation = {}, Sound = {}, MeshPart = {} }
	for class, props in string.gmatch(xml, '<Item class="(%w+)" referent="[^"]*">%s*<Properties>(.-)</Properties>') do
		local idProps = ID_PROPS[class]
		if idProps then
			-- seulement la propriété d'id de la classe (pas TextureID ni une autre Content du même item)
			local uri
			for _, prop in idProps do
				uri = uri
					or string.match(props, '<Content name="' .. prop .. '">%s*<uri>(.-)</uri>')
					or string.match(props, '<Content name="' .. prop .. '">%s*<url>(.-)</url>')
			end
			table.insert(found[class], { name = string.match(props, '<string name="Name">(.-)</string>'), uri = uri })
		end
	end
	return found
end

-- Cette méthode permet de résumer une instance (classes clés, attributs) lorsqu'on l'affiche et la contrôle.
local function summarize(inst): string
	local counts = { Animation = 0, Sound = 0, BaseScript = 0, MeshPart = 0 }
	for _, d in inst:GetDescendants() do
		for class in counts do
			if d:IsA(class) then
				counts[class] += 1
			end
		end
	end
	local attrs = {}
	for key, value in inst:GetAttributes() do
		table.insert(attrs, key .. "=" .. tostring(value))
	end
	table.sort(attrs)
	return string.format(
		"[%s] %d descendants, %d Animation, %d Sound, %d Script, %d MeshPart, attributs {%s}",
		inst.ClassName,
		#inst:GetDescendants(),
		counts.Animation,
		counts.Sound,
		counts.BaseScript,
		counts.MeshPart,
		table.concat(attrs, ", ")
	)
end

-- clés de WeaponConfig.Weapons (lecture textuelle, limitée au bloc de la table : entrées indentées d'une tabulation)
local weaponKeys = {}
local weaponsBlock = string.match(fs.readFile("src/shared/WeaponConfig.luau"), "\nWeaponConfig%.Weapons = {(.-)\n}")
if not weaponsBlock then
	fail("bloc WeaponConfig.Weapons introuvable dans src/shared/WeaponConfig.luau")
else
	for key in string.gmatch(weaponsBlock, '\n\t%[?"?([%w_]+)"?%]?%s*=%s*{') do
		weaponKeys[key] = true
	end
end

local viewModels = game.ReplicatedStorage:FindFirstChild("ViewModels")
if not viewModels then
	fail("ReplicatedStorage.ViewModels absent")
else
	for _, name in rbxmNames("assets/rbx/ViewModels") do
		local vm = viewModels:FindFirstChild(name)
		if not vm then
			fail("viewmodel " .. name .. " absent de la place")
		else
			print("ViewModels." .. name .. " " .. summarize(vm))
			if not vm.PrimaryPart then
				fail("viewmodel " .. name .. " sans PrimaryPart")
			end
		end
	end
end

for _, name in rbxmNames("assets/rbx/Tools") do
	local tool = game.StarterPack:FindFirstChild(name)
	if not tool or not tool:IsA("Tool") then
		fail("Tool " .. name .. " absent de StarterPack")
		continue
	end
	print("StarterPack." .. name .. " " .. summarize(tool))
	local vmName = tool:GetAttribute("ViewmodelName")
	if type(vmName) ~= "string" or not (viewModels and viewModels:FindFirstChild(vmName)) then
		fail(string.format("Tool %s : ViewmodelName=%s sans viewmodel correspondant", name, tostring(vmName)))
	end
	-- même résolution que WeaponSystem/ViewmodelSystem : attribut WeaponName, sinon nom du Tool
	local weaponName = tool:GetAttribute("WeaponName") or name
	if not weaponKeys[weaponName] then
		print(string.format("ATTENTION : Tool %s -> arme %q absente de WeaponConfig.Weapons", name, weaponName))
	end
end

-- ids d'assets : une animation ou un mesh sans id est une erreur ; un son sans id est seulement signalé
-- (la place d'origine contient un Sound vide, AWP.Sounds.Sound)
for class, entries in scanAssetIds(fs.readFile(placePath)) do
	local withId = 0
	for _, entry in entries do
		if entry.uri and entry.uri ~= "" then
			withId += 1
		elseif class == "Sound" then
			print(string.format("ATTENTION : Sound %s sans id", tostring(entry.name)))
		else
			fail(string.format("%s %s sans id", class, tostring(entry.name)))
		end
	end
	print(string.format("%s : %d/%d avec un id d'asset", class, withId, #entries))
end

if errors > 0 then
	print(string.format("%d erreur(s)", errors))
	process.exit(1)
end
print("OK")
