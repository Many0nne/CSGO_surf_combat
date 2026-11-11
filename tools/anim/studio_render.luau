-- studio_render.luau
-- À coller dans `execute_luau` (mode Edit, contexte Edit), pendant que tools/anim/capture_server.py tourne.
-- Rend chaque frame du JSON sur un clone temporaire du viewmodel, avec la caméra et le FOV du jeu, puis capture la
-- fenêtre. Le clone est supprimé et la caméra restaurée à la fin : la place n'a pas besoin d'être sauvegardée.
-- Le rendu tourne dans un task.spawn (≈ 2,5 s par image) : l'appel MCP rend la main tout de suite. Suivre l'avancement
-- dans le dossier des captures, puis lire la ligne « [studio_render] » avec get_console_output.

local VIEWMODEL = "M9Bayonet"
local GAME_FOV = 90 -- CameraConfig.DEFAULT_FOV : un autre FOV fausse tout le cadrage
local BASE = "http://127.0.0.1:34991"
local SETTLE = 0.12 -- laisse Studio afficher la frame avant la capture
local FIRST_SETTLE = 1.5 -- la première capture sort vide si les meshes du clone n'ont pas eu le temps de s'afficher
-- Couteaux (build_viewmodel.py) : le JSON place la Handle sur la main virtuelle, à recaler sur le mesh réel. Mettre false
-- pour un JSON qui donne la CFrame réelle de chaque pièce (AWP : assets/awp_viewmodel/run_build.py).
local RECENTER_HANDLE = true

local Http = game:GetService("HttpService")
local cam = workspace.CurrentCamera
local template = game:GetService("ReplicatedStorage").ViewModels[VIEWMODEL]

-- Cette méthode permet de lister les pièces soudées à la Handle (lame, garde… d'une arme en plusieurs MeshParts) avec leur
-- décalage dans le viewmodel, lorsque le JSON ne pose que la Handle : elles la suivent à chaque frame.
local function weldedToHandle(model)
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("WeldConstraint") or d:IsA("Weld") then
			local other = if d.Part0 == model.Handle then d.Part1 elseif d.Part1 == model.Handle then d.Part0 else nil
			if other then
				parts[other.Name] = model.Handle.CFrame:ToObjectSpace(other.CFrame)
			end
		end
	end
	return parts
end

-- Cette méthode permet de rendre et capturer toutes les frames servies par capture_server.py, puis de tout remettre en place.
local function render()
	local savedCF, savedFov, savedType = cam.CFrame, cam.FieldOfView, cam.CameraType
	local folder = Instance.new("Folder")
	folder.Name = "__AnimPreview"
	folder.Archivable = false
	local clone = template:Clone()
	for _, d in clone:GetDescendants() do
		if
			d:IsA("Motor6D")
			or d:IsA("WeldConstraint")
			or d:IsA("Weld")
			or d:IsA("LuaSourceContainer")
			or d:IsA("Animation")
			or d:IsA("Sound")
		then
			d:Destroy()
		end
	end
	clone.Parent = folder
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	folder.Parent = workspace

	local camCF = CFrame.new(0, 3000, 0) -- loin de la map : fond uni, seule l'arme compte
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = camCF
	cam.FieldOfView = GAME_FOV

	-- Le mesh de l'arme n'a pas son origine sur le repère de prise : on repart de son décalage réel dans le viewmodel.
	local handleInHand = template:FindFirstChild("RightHand", true).CFrame:ToObjectSpace(template.Handle.CFrame)
	local welded = weldedToHandle(template)
	local frames = Http:JSONDecode(Http:GetAsync(BASE .. "/frames"))
	local ids = {}
	for id in frames do
		table.insert(ids, id)
	end
	table.sort(ids)

	local captured, failure = 0, nil
	for index, id in ids do
		for name, values in frames[id] do
			local cf = CFrame.new(table.unpack(values))
			if name == "Handle" and RECENTER_HANDLE then
				cf *= handleInHand
			end
			clone:FindFirstChild(name, true).CFrame = camCF * cf
		end
		for name, offset in welded do
			clone:FindFirstChild(name, true).CFrame = clone.Handle.CFrame * offset
		end
		task.wait(index == 1 and FIRST_SETTLE or SETTLE)
		local reply = Http:GetAsync(BASE .. "/shot?name=" .. id)
		if not string.find(reply, '"ok": 1') then
			failure = id
			break
		end
		captured += 1
	end

	cam.CFrame, cam.FieldOfView, cam.CameraType = savedCF, savedFov, savedType
	folder:Destroy()
	print(
		"[studio_render] captures="
			.. captured
			.. " echec="
			.. tostring(failure)
			.. " viewport="
			.. tostring(cam.ViewportSize)
	)
end

task.spawn(render)
return "rendu lancé"
