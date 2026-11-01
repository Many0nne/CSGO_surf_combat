-- studio_render.luau
-- À coller dans `execute_luau` (mode Edit, contexte Edit), pendant que tools/anim/capture_server.py tourne.
-- Rend chaque frame du JSON sur un clone temporaire du viewmodel, avec la caméra et le FOV du jeu, puis capture la
-- fenêtre. Le clone est supprimé et la caméra restaurée à la fin : la place n'a pas besoin d'être sauvegardée.

local VIEWMODEL = "M9Bayonet"
local GAME_FOV = 90 -- CameraConfig.DEFAULT_FOV : un autre FOV fausse tout le cadrage
local BASE = "http://127.0.0.1:34991"
local SETTLE = 0.12 -- laisse Studio afficher la frame avant la capture

local Http = game:GetService("HttpService")
local cam = workspace.CurrentCamera
local template = game:GetService("ReplicatedStorage").ViewModels[VIEWMODEL]
local savedCF, savedFov, savedType = cam.CFrame, cam.FieldOfView, cam.CameraType

local folder = Instance.new("Folder")
folder.Name = "__AnimPreview"
folder.Archivable = false
local clone = template:Clone()
for _, d in clone:GetDescendants() do
	if d:IsA("Motor6D") or d:IsA("LuaSourceContainer") or d:IsA("Animation") or d:IsA("Sound") then
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
local frames = Http:JSONDecode(Http:GetAsync(BASE .. "/frames"))
local ids = {}
for id in frames do
	table.insert(ids, id)
end
table.sort(ids)

local captured, failure = 0, nil
for _, id in ids do
	for name, values in frames[id] do
		local cf = CFrame.new(table.unpack(values))
		if name == "Handle" then
			cf *= handleInHand
		end
		clone:FindFirstChild(name, true).CFrame = camCF * cf
	end
	task.wait(SETTLE)
	local reply = Http:GetAsync(BASE .. "/shot?name=" .. id)
	if not string.find(reply, '"ok": 1') then
		failure = id
		break
	end
	captured += 1
end

cam.CFrame, cam.FieldOfView, cam.CameraType = savedCF, savedFov, savedType
folder:Destroy()
return "captures=" .. captured .. " echec=" .. tostring(failure) .. " viewport=" .. tostring(cam.ViewportSize)
