-- verify_place.luau
-- Relit la place produite par `rojo build` et vérifie que les viewmodels (assets/rbx/ViewModels), les Tools
-- (assets/rbx/Tools, dans ReplicatedStorage.Tools, StarterPack vide), la map (assets/rbx/Maps) et ses matières (assets/rbx/Materials) y sont, avec leurs animations,
-- sons, textures, attributs et scripts.
-- Signale aussi les Tools dont le nom d'arme n'a pas d'entrée dans src/shared/WeaponConfig.luau (avertissement,
-- sans échec).
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
	MaterialVariant = { "ColorMapContent", "ColorMap" },
}

-- Cette méthode permet de relever les ids d'assets (animations, sons, meshes) en lisant le XML de la place
-- lorsque Studio les écrit sous leurs noms récents (AnimationContent, AudioContent, MeshContent), que Lune 0.9 ignore.
local function scanAssetIds(xml: string): { [string]: { { name: string, uri: string? } } }
	local found = { Animation = {}, Sound = {}, MeshPart = {}, MaterialVariant = {} }
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

-- Tools des armes (#267) : dans ReplicatedStorage.Tools, donnés par le serveur selon l'inventaire ; le StarterPack reste
-- vide, sinon Roblox donnerait chaque arme à tout joueur
for _, child in game.StarterPack:GetChildren() do
	fail("StarterPack." .. child.Name .. " : le StarterPack doit rester vide (Tools dans ReplicatedStorage.Tools)")
end
local toolsFolder = game.ReplicatedStorage:FindFirstChild("Tools")
if not toolsFolder then
	fail("ReplicatedStorage.Tools absent")
end
for _, name in rbxmNames("assets/rbx/Tools") do
	local tool = toolsFolder and toolsFolder:FindFirstChild(name)
	if not tool or not tool:IsA("Tool") then
		fail("Tool " .. name .. " absent de ReplicatedStorage.Tools")
		continue
	end
	print("Tools." .. name .. " " .. summarize(tool))
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

-- maps (assets/rbx/Maps, #69) : chaque Workspace.Maps.<Nom> avec des points d'apparition ; lanceurs du soleil avec une
-- vitesse ; boosts configurés ; hauteur de mort numérique si présente
local maps = game.Workspace:FindFirstChild("Maps")

-- Cette méthode permet de contrôler une map lorsqu'on vérifie la place : spawns, lanceurs, boosts, matières, dunes.
local function checkMap(map)
	local ground = map:FindFirstChild("GroundSpawns")
	local launches = map:FindFirstChild("SunLaunch")
	local nGround = if ground then #ground:GetChildren() else 0
	local nLaunch = if launches then #launches:GetChildren() else 0
	if nGround + nLaunch == 0 then
		fail("Maps." .. map.Name .. " sans point d'apparition (GroundSpawns ni SunLaunch)")
	end
	for _, launch in if launches then launches:GetChildren() else {} do
		if type(launch:GetAttribute("Speed")) ~= "number" then
			fail("Maps." .. map.Name .. ".SunLaunch." .. launch.Name .. " sans attribut Speed")
		end
	end
	-- boosts (MapRules) : chaque volume a un type connu et le réglage qui va avec
	local boosts = map:FindFirstChild("Boosts")
	local nBoost = 0
	for _, boost in if boosts then boosts:GetChildren() else {} do
		nBoost += 1
		local kind = boost:GetAttribute("Kind")
		if kind == "Geyser" or kind == "Launcher" then
			if typeof(boost:GetAttribute("Velocity")) ~= "Vector3" then
				fail("Maps." .. map.Name .. ".Boosts." .. boost.Name .. " sans attribut Velocity (Vector3)")
			end
		elseif kind == "Portal" then
			if type(boost:GetAttribute("Boost")) ~= "number" then
				fail("Maps." .. map.Name .. ".Boosts." .. boost.Name .. " sans attribut Boost")
			end
		else
			fail("Maps." .. map.Name .. ".Boosts." .. boost.Name .. string.format(" : Kind %q inconnu", tostring(kind)))
		end
	end
	-- matières (#71) : toute MaterialVariant posée sur une pièce de la map existe dans MaterialService, sinon la
	-- pièce retombe en silence sur sa matière de base
	local variants = {}
	for _, v in game:GetService("MaterialService"):GetChildren() do
		variants[v.Name] = v
	end
	local missing = {}
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d.MaterialVariant ~= "" and not variants[d.MaterialVariant] then
			missing[d.MaterialVariant] = true
		end
	end
	for name in missing do
		fail("MaterialVariant " .. name .. " utilisée par Maps." .. map.Name .. " mais absente de MaterialService")
	end
	local kill = map:GetAttribute("KillHeight")
	if kill ~= nil and type(kill) ~= "number" then
		fail("Maps." .. map.Name .. ".KillHeight doit être un nombre")
	end
	print(
		string.format(
			"Maps.%s : %d instances, %d spawns au sol, %d lanceurs, %d boosts, KillHeight %s",
			map.Name,
			#map:GetDescendants(),
			nGround,
			nLaunch,
			nBoost,
			tostring(kill)
		)
	)
end

for _, mapName in rbxmNames("assets/rbx/Maps") do
	local map = maps and maps:FindFirstChild(mapName)
	if map then
		checkMap(map)
	else
		fail("Workspace.Maps." .. mapName .. " absent")
	end
end

-- ids d'assets : une animation, un mesh ou une matière sans texture est une erreur ; un son sans id est seulement
-- signalé
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
