-- verify_place.luau
-- Relit la place produite par `rojo build` et vérifie que les viewmodels (assets/rbx/ViewModels), les Tools
-- (assets/rbx/Tools, dans ReplicatedStorage.Tools, StarterPack vide), la map (assets/rbx/Maps) et ses matières (assets/rbx/Materials) y sont, avec leurs animations,
-- sons, textures, attributs et scripts, ainsi que les tenues de personnage (assets/rbx/Outfits, #521).
-- Contrôle les dossiers de chaque map lus par le code (src/shared/MapGeometry.luau, #292) : un renommage casse la CI.
-- Contrôle la hauteur des points d'apparition au sol (tools/map/SpawnCheck.luau, #328).
-- Signale aussi les Tools dont le nom d'arme n'a pas d'entrée dans src/shared/WeaponConfig.luau (avertissement,
-- sans échec).
-- Usage (racine du dépôt) : rojo build default.project.json -o CSGO.rbxlx && lune run tools/rbxm/verify_place.luau [CSGO.rbxlx]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local SpawnCheck = require("../map/SpawnCheck")

local placePath = process.args[1] or "CSGO.rbxlx"
-- module sans dépendance : chargé tel quel (source unique des noms de dossiers de map)
local MapGeometry = luau.load(fs.readFile("src/shared/MapGeometry.luau"), { debugName = "MapGeometry" })()
-- place du pochoir de la caisse (#456), comparée aux pièces de Props.Crate
local CrateStencil = luau.load(fs.readFile("src/shared/CrateStencil.luau"), { debugName = "CrateStencil" })()
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

-- Pièces de référence du profil des armes (#429, #444) : module chargé avec le Vector3 de Lune
local WeaponProfile = luau.load(fs.readFile("src/shared/WeaponProfile.luau"), {
	debugName = "WeaponProfile",
	environment = { Vector3 = roblox.Vector3 },
})()

-- Cette méthode permet de vérifier qu'un viewmodel a sa pièce de référence de profil lorsqu'un rendu le pose à plat :
-- MeshPart visible enfant direct (seules celles-là sont clonées par UIKit et ShopScene), sinon le sens n'est plus garanti.
local function checkReference(vm)
	local reference = WeaponProfile.REFERENCES[vm.Name]
	if not reference then
		fail("viewmodel " .. vm.Name .. " sans référence dans WeaponProfile.REFERENCES (sens de l'arme non garanti)")
		return
	end
	local part = vm:FindFirstChild(reference.part)
	if not (part and part:IsA("MeshPart") and part.Transparency < 1) then
		fail(
			string.format(
				"viewmodel %s : pièce de référence %s absente, pas une MeshPart ou invisible (WeaponProfile.REFERENCES)",
				vm.Name,
				reference.part
			)
		)
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
			checkReference(vm)
		end
	end
	for name in WeaponProfile.REFERENCES do
		if not viewModels:FindFirstChild(name) then
			fail("WeaponProfile.REFERENCES." .. name .. " sans viewmodel " .. name)
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

-- régénération de PV retirée (#289) : un Script `Health` dans StarterCharacterScripts remplace celui de Roblox
local charScripts = game:GetService("StarterPlayer"):FindFirstChild("StarterCharacterScripts")
local healthScript = charScripts and charScripts:FindFirstChild("Health")
if charScripts and charScripts.ClassName ~= "StarterCharacterScripts" then
	fail("StarterPlayer.StarterCharacterScripts est un " .. charScripts.ClassName .. " : Roblox l'ignorerait")
elseif not healthScript or not healthScript:IsA("Script") then
	fail("StarterPlayer.StarterCharacterScripts.Health (Script) absent : Roblox rétablirait la régénération des PV")
else
	print("StarterCharacterScripts.Health " .. summarize(healthScript))
	-- le script doit rester vide (commentaires seulement) et actif, sinon ce n'est plus un simple remplaçant
	local source = string.gsub(healthScript.Source, "%-%-%[(=*)%[.-%]%1%]", "")
	for line in string.gmatch(source, "[^\r\n]+") do
		if not string.match(line, "^%s*%-%-") and string.match(line, "%S") then
			fail("StarterCharacterScripts.Health doit ne contenir que des commentaires : " .. line)
			break
		end
	end
	if healthScript.Disabled then
		fail("StarterCharacterScripts.Health est désactivé : Roblox rétablirait la régénération des PV")
	end
end

-- maps (assets/rbx/Maps, #69) : chaque Workspace.Maps.<Nom> avec des points d'apparition au sol ; boosts configurés ;
-- hauteur de mort numérique si présente
local maps = game.Workspace:FindFirstChild("Maps")

-- Cette méthode permet de contrôler une map lorsqu'on vérifie la place : spawns, boosts, matières, dunes.
local function checkMap(map)
	local ground = map:FindFirstChild("GroundSpawns")
	local nGround = if ground then #ground:GetChildren() else 0
	if nGround == 0 then
		fail("Maps." .. map.Name .. " sans point d'apparition (GroundSpawns)")
	end
	-- hauteur des points (#328) : pieds du rig au-dessus du sol mesuré par un rayon vertical (tools/map/SpawnCheck.luau)
	local spawnLines, spawnErrors, spawnLow, spawnHigh = SpawnCheck.check(map)
	for _, message in spawnErrors do
		fail(message)
	end
	if #spawnErrors > 0 then
		print(table.concat(spawnLines, "\n"))
	elseif spawnLow <= spawnHigh then
		print(
			string.format(
				"Maps.%s : pieds de %.3f à %.3f stud au-dessus du sol à l'apparition",
				map.Name,
				spawnLow,
				spawnHigh
			)
		)
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
	-- dossiers lus par le code (#292) : murs d'air, rampes, spawns au sol, échelles
	for _, path in MapGeometry.missingFolders(map) do
		fail("Maps." .. map.Name .. "." .. path .. " absent (dossier lu par le code, cf. src/shared/MapGeometry.luau)")
	end
	local clips = MapGeometry.clips(map)
	local nClip = if clips then #clips:GetDescendants() else 0
	local nPass = #MapGeometry.bulletTransparent(map) - (if clips then 1 else 0)
	local kill = map:GetAttribute("KillHeight")
	if kill ~= nil and type(kill) ~= "number" then
		fail("Maps." .. map.Name .. ".KillHeight doit être un nombre")
	end
	print(
		string.format(
			"Maps.%s : %d instances, %d spawns au sol, %d boosts, %d murs d'air, %d grillages passbullets, KillHeight %s",
			map.Name,
			#map:GetDescendants(),
			nGround,
			nBoost,
			nClip,
			nPass,
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

-- Props (assets/rbx/Props) : la caisse du shop doit garder les pièces que ShopScene habille et recolore (#332)
local CRATE_PARTS = {
	"Interior",
	"BodyPlanks",
	"BodyFrame",
	"BodySteel",
	"Rope",
	"LidPlanks",
	"LidFrame",
	"LidSteel",
	"LidStripe",
}
local props = game.ReplicatedStorage:FindFirstChild("Props")
for _, name in rbxmNames("assets/rbx/Props") do
	local prop = props and props:FindFirstChild(name)
	if not prop then
		fail("ReplicatedStorage.Props." .. name .. " absent de la place")
	else
		print("Props." .. name .. " " .. summarize(prop))
	end
end
local crateModel = props and props:FindFirstChild("Crate")
if not crateModel then
	fail("ReplicatedStorage.Props.Crate absent (caisse du shop)")
else
	for _, partName in CRATE_PARTS do
		local part = crateModel:FindFirstChild(partName)
		if not (part and part:IsA("MeshPart")) then
			fail("Props.Crate." .. partName .. " absent ou pas une MeshPart")
		end
	end
	-- Pochoir posé par le jeu, propre à chaque caisse (#434) : un « LidStencil » dans le mesh doublerait le texte
	if crateModel:FindFirstChild("LidStencil") then
		fail("Props.Crate.LidStencil présent : le pochoir est posé par ShopScene (#434), pas modelé")
	end
	-- Place du pochoir (CrateStencil, #456) face aux boîtes des pièces, dans le repère du pivot : une caisse régénérée
	-- avec d'autres cotes ne doit pas l'enfoncer dans le bois, le laisser flotter ni le glisser sous la bande
	-- Lune n'a pas GetPivot : le pivot est stocké dans WorldPivotData
	local pivot = crateModel.WorldPivotData
	local boxes = {}
	for _, part in crateModel:GetChildren() do
		if part:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(part.CFrame)
			local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
			for _, sx in { -0.5, 0.5 } do
				for _, sy in { -0.5, 0.5 } do
					for _, sz in { -0.5, 0.5 } do
						local p = rel * roblox.Vector3.new(part.Size.X * sx, part.Size.Y * sy, part.Size.Z * sz)
						for axis, value in { p.X, p.Y, p.Z } do
							lo[axis], hi[axis] = math.min(lo[axis], value), math.max(hi[axis], value)
						end
					end
				end
			end
			boxes[part.Name] = { min = lo, max = hi }
		end
	end
	for _, problem in CrateStencil.problems(boxes) do
		fail("Props.Crate : " .. problem .. " (src/shared/CrateStencil.luau)")
	end
end

-- Tenues de personnage (assets/rbx/Outfits, #521) : une SurfaceAppearance par pièce du rig (copiée par
-- CharacterAppearance.dress), et une coque de tête qui ne bloque ni n'intercepte rien (la tête du rig reste la hitbox)
local OUTFIT_PARTS = {
	"UpperTorso",
	"LowerTorso",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}
local outfits = game.ReplicatedStorage:FindFirstChild("Outfits")
for _, name in rbxmNames("assets/rbx/Outfits") do
	local outfit = outfits and outfits:FindFirstChild(name)
	if not outfit then
		fail("ReplicatedStorage.Outfits." .. name .. " absent de la place")
		continue
	end
	for _, partName in OUTFIT_PARTS do
		local appearance = outfit:FindFirstChild(partName)
		if not (appearance and appearance:IsA("SurfaceAppearance")) then
			fail("Outfits." .. name .. "." .. partName .. " absent ou pas une SurfaceAppearance")
		end
	end
	local head = outfit:FindFirstChild("Head")
	if head then
		if not head:IsA("MeshPart") then
			fail("Outfits." .. name .. ".Head n'est pas une MeshPart")
		elseif head.CanCollide or head.CanQuery or head.CanTouch or not head.Massless then
			fail("Outfits." .. name .. ".Head doit être sans collision, ni requête, ni contact, et sans masse")
		elseif not head:FindFirstChildOfClass("SurfaceAppearance") then
			fail("Outfits." .. name .. ".Head sans SurfaceAppearance : la coque n'aurait pas la carte de la tenue")
		end
	end
	print("Outfits." .. name .. " " .. summarize(outfit))
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
