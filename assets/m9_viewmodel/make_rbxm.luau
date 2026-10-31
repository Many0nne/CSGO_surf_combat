-- make_rbxm.luau
-- Construit un .rbxm (une KeyframeSequence) par animation à partir des JSON exportés par build_viewmodel.py.
-- Usage : lune run assets/m9_viewmodel/make_rbxm.luau <dossier_json> <dossier_sortie> [Nom1 Nom2 ...]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instance = roblox.Instance
local CFrame = roblox.CFrame

local PREFIX = "M9_"

local inDir = process.args[1]
local outDir = process.args[2]
assert(inDir and outDir, "usage: make_rbxm.luau <dossier_json> <dossier_sortie> [noms...]")
local names = { table.unpack(process.args, 3) }
if #names == 0 then
	names = { "Equip", "Shoot" }
end

-- Cette méthode permet de construire la KeyframeSequence d'une animation lorsque son JSON
-- (frames, Transform par Motor6D, hiérarchie des pièces, marqueurs) a été exporté depuis Blender.
local function buildSequence(data)
	local ks = Instance.new("KeyframeSequence")
	ks.Name = PREFIX .. data.name
	ks.Loop = data.loop
	ks.Priority = if data.loop then roblox.Enum.AnimationPriority.Idle else roblox.Enum.AnimationPriority.Action

	local keyframes = {}
	for _, fr in data.frames do
		local kf = Instance.new("Keyframe")
		kf.Time = fr.t
		local poses = {}
		local root = Instance.new("Pose")
		root.Name = "HumanoidRootPart"
		root.Weight = 0
		root.Parent = kf
		poses.HumanoidRootPart = root

		local function getPose(n: string)
			if poses[n] then
				return poses[n]
			end
			local p = Instance.new("Pose")
			p.Name = n
			p.EasingStyle = roblox.Enum.PoseEasingStyle.Linear
			p.CFrame = CFrame.new(table.unpack(fr.poses[n]))
			p.Parent = getPose(data.parents[n])
			poses[n] = p
			return p
		end
		for n in fr.poses do
			getPose(n)
		end
		kf.Parent = ks
		table.insert(keyframes, kf)
	end

	-- marqueurs : rattachés à la keyframe la plus proche de leur instant
	for _, m in data.markers do
		local best, bestDist = nil, math.huge
		for _, kf in keyframes do
			local d = math.abs(kf.Time - m.t)
			if d < bestDist then
				best, bestDist = kf, d
			end
		end
		local marker = Instance.new("KeyframeMarker")
		marker.Name = m.name
		marker.Parent = best
	end
	return ks
end

for _, name in names do
	local data = serde.decode("json", fs.readFile(inDir .. "/anim_" .. name .. ".json"))
	local ks = buildSequence(data)
	local path = outDir .. "/" .. PREFIX .. name .. ".rbxm"
	fs.writeFile(path, roblox.serializeModel({ ks }))
	print(string.format("%s : %d keyframes, %d marqueurs -> %s", name, #data.frames, #data.markers, path))
end
